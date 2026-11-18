"""Tests for reports.py: `python3 -m unittest deploy/site/test_reports.py`."""

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from datetime import date
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reports  # noqa: E402

MAC = {"app": "mac", "version": "1.16", "os": "15.1.2"}


class Taking(unittest.TestCase):
    def setUp(self):
        self.store = reports.Store(":memory:")

    def tearDown(self):
        self.store.db.close()

    def rows(self, kind):
        return self.store.db.execute(
            "SELECT app, version, os, name, n FROM counts WHERE kind = ? ORDER BY name", (kind,)
        ).fetchall()

    def test_usage_adds_up_by_day_app_and_version(self):
        self.assertTrue(reports.take_usage(self.store, {**MAC, "events": {"play-folder": 2, "skin.rave": 1}}))
        self.assertTrue(reports.take_usage(self.store, {**MAC, "events": {"play-folder": 3}}))
        self.assertEqual(
            self.rows("usage"), [("mac", "1.16", "15.1", "play-folder", 5), ("mac", "1.16", "15.1", "skin.rave", 1)]
        )
        self.assertEqual(self.rows("report"), [("mac", "1.16", "15.1", "usage", 2)])

    def test_refuses_what_an_app_never_sends(self):
        bad = [
            {**MAC, "app": "linux", "events": {"play": 1}},
            {**MAC, "version": "1.16 beta", "events": {"play": 1}},
            {**MAC, "events": {}},
            {**MAC, "events": {"Fleetwood Mac/Rumours": 1}},
            {**MAC, "events": {"play": 0}},
            {**MAC, "events": {"play": True}},
            {**MAC, "events": {"play": 10**9}},
            {**MAC, "events": {f"e{i}": 1 for i in range(reports.MAX_NAMES + 1)}},
        ]
        for body in bad:
            self.assertFalse(reports.take_usage(self.store, body), body)
        self.assertEqual(self.rows("usage"), [])

    def test_errors_are_counted_by_kind_and_a_path_is_refused(self):
        ok = {**MAC, "errors": [{"area": "player", "code": "track-skipped NSURLErrorDomain -1009", "count": 3}]}
        self.assertTrue(reports.take_errors(self.store, ok))
        self.assertEqual(self.rows("error"), [("mac", "1.16", "15.1", "player track-skipped NSURLErrorDomain -1009", 3)])
        path = {**MAC, "errors": [{"area": "player", "code": "track-skipped /Users/someone/Music/01.flac", "count": 1}]}
        self.assertFalse(reports.take_errors(self.store, path))
        self.assertFalse(reports.take_errors(self.store, {**MAC, "errors": [], "crashes": []}))

    def test_a_crash_is_new_once_per_version(self):
        new = []
        body = {**MAC, "crashes": [{"signature": "EXC_BAD_ACCESS PlayerController.start", "report": "x" * 50_000}]}
        tell = lambda sender, signature, report: new.append((sender, signature, len(report)))
        self.assertTrue(reports.take_errors(self.store, body, tell))
        self.assertTrue(reports.take_errors(self.store, body, tell))
        self.assertTrue(reports.take_errors(self.store, {**body, "version": "1.17"}, tell))
        self.assertEqual([n[0][1] for n in new], ["1.16", "1.17"])
        self.assertEqual(new[0][2], reports.MAX_REPORT)
        self.assertEqual(self.store.db.execute("SELECT n FROM crashes WHERE version = '1.16'").fetchone(), (2,))

    def test_digest_and_forgetting(self):
        self.assertIsNone(self.store.digest())
        who = ("mac", "1.16", "15.1")
        now = date(2026, 11, 23)
        self.store.add("usage", who, {"play-folder": 7}, day="2026-11-20")
        self.store.add("usage", who, {"ancient-event": 1}, day="2025-01-01")
        self.store.add("error", who, {"player track-skipped": 2}, day="2026-11-21")
        self.store.add("report", who, {"usage": 1}, day="2026-11-20")
        self.store.add_crash(who, "EXC_BAD_ACCESS", "stack", day="2026-11-22")
        text = self.store.digest(now=now)
        self.assertIn("      7  play-folder", text)
        self.assertIn("2x  mac 1.16  player track-skipped", text)
        self.assertIn("1x  mac 1.16 (system 15.1)  EXC_BAD_ACCESS", text)
        self.assertNotIn("ancient-event", text)
        self.store.forget_old(now=now)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM counts WHERE name = 'ancient-event'").fetchone(), (0,))
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM counts").fetchone(), (3,))


class OverHTTP(unittest.TestCase):
    def setUp(self):
        reports.recent.clear()
        self.store = reports.Store(":memory:")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), reports.handler(self.store))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.store.db.close()

    def post(self, path, body):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        try:
            # No proxy lookup: it is this machine, and the lookup is slow on a Mac.
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(urllib.request.Request(self.base + path, data=data), timeout=5) as r:
                return r.status
        except urllib.error.HTTPError as error:
            return error.code

    def test_statuses(self):
        self.assertEqual(self.post("/api/usage", {**MAC, "events": {"play-folder": 1}}), 204)
        self.assertEqual(self.post("/api/errors", {**MAC, "errors": [{"area": "app", "code": "x", "count": 1}]}), 204)
        self.assertEqual(self.post("/api/usage", b"not json"), 400)
        self.assertEqual(self.post("/api/usage", {**MAC, "events": {"Bad Name": 1}}), 400)
        self.assertEqual(self.post("/api/other", {}), 404)
        self.assertEqual(self.post("/api/usage", b"x" * (reports.MAX_BODY + 1)), 413)

    def test_floods_are_slowed(self):
        body = {**MAC, "events": {"play-folder": 1}}
        codes = [self.post("/api/usage", body) for _ in range(reports.LIMIT + 1)]
        self.assertEqual(codes[-1], 429)
        self.assertEqual(set(codes[:-1]), {204})


if __name__ == "__main__":
    unittest.main()

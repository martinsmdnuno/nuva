"""What the NuVa apps report, when the person using them agreed to it.

POST /api/usage   how often each feature was used since the app last reported
POST /api/errors  the failures the app wrote down (by kind, never by name) and its crashes

Standard library only. It keeps counts, not people: nothing that identifies an
installation is accepted or stored, no IP address is written anywhere (they are
held in memory for an hour, only to slow down floods), and a count is a row of
(day, app, version, system, name) with a number. Counts are dropped after a year,
crash reports after 90 days.

The author reads it by email: a digest every Monday, and a message the first time
a new crash shows up. `python reports.py digest` prints the last week's digest.

Environment: REPORTS_DB (the SQLite file, default /data/reports.db), REPORTS_TO
(default FEEDBACK_TO), and the same SMTP_* settings as the feedback form.

--- The bodies (JSON) ---

usage:  {"app": "mac", "version": "1.16", "os": "15.1",
         "events": {"play-folder": 12, "skin.rave": 1}}

errors: {"app": "mac", "version": "1.16", "os": "15.1",
         "errors": [{"area": "player", "code": "track-skipped NSURLErrorDomain -1009", "count": 3}],
         "crashes": [{"signature": "EXC_BAD_ACCESS PlayerController.start", "report": "..."}]}
"""

from __future__ import annotations

import json
import os
import re
import smtplib
import sqlite3
import ssl
import sys
import threading
import time
from datetime import date, datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import formataddr
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("REPORTS_DB", "/data/reports.db")
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
REPORTS_TO = os.environ.get("REPORTS_TO") or os.environ.get("FEEDBACK_TO", "")

MAX_BODY = 64_000
MAX_NAMES = 200
MAX_COUNT = 100_000
MAX_CRASHES = 5
MAX_REPORT = 30_000
# Per address: at most this many reports an hour (an app reports about once a day).
LIMIT = 30
KEEP_COUNTS_DAYS = 365
KEEP_CRASHES_DAYS = 90
# New crashes mailed in a day, at most; the rest wait for the digest.
MAX_CRASH_MAILS = 5

APPS = {"mac", "tv", "windows"}
VERSION = re.compile(r"^\d{1,3}(\.\d{1,3}){0,2}$")
SYSTEM = re.compile(r"^\d{1,3}(\.\d{1,3}){0,2}$")
# Feature names are fixed words chosen in the app: "play-folder", "skin.rave".
EVENT = re.compile(r"^[a-z0-9][a-z0-9.-]{0,39}$")
AREA = re.compile(r"^[a-z]{1,20}$")
# The kind of a failure: "track-skipped NSURLErrorDomain -1009". Short, and no path fits in it.
CODE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,119}$")
SIGNATURE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._:()<>,+-]{0,199}$")

recent: dict[str, list[float]] = {}
lock = threading.Lock()


def allowed(address: str) -> bool:
    now = time.time()
    with lock:
        for key in [k for k, times in recent.items() if times[-1] < now - 3600]:
            del recent[key]
        times = [t for t in recent.get(address, []) if t > now - 3600]
        if len(times) >= LIMIT:
            recent[address] = times
            return False
        recent[address] = times + [now]
        return True


def today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


class Store:
    """The counts, in one SQLite file. One connection, used under a lock."""

    def __init__(self, path: str):
        if path != ":memory:":
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.Lock()
        with self.lock, self.db:
            self.db.executescript(
                """
                CREATE TABLE IF NOT EXISTS counts (
                    day TEXT, kind TEXT, app TEXT, version TEXT, os TEXT, name TEXT, n INTEGER,
                    PRIMARY KEY (day, kind, app, version, os, name));
                CREATE TABLE IF NOT EXISTS crashes (
                    signature TEXT, app TEXT, version TEXT, os TEXT,
                    first_day TEXT, last_day TEXT, n INTEGER, report TEXT,
                    PRIMARY KEY (signature, app, version));
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
                """
            )

    def add(self, kind: str, who: tuple[str, str, str], counts: dict[str, int], day: str | None = None) -> None:
        app, version, system = who
        day = day or today()
        with self.lock, self.db:
            for name, n in counts.items():
                self.db.execute(
                    "INSERT INTO counts VALUES (?, ?, ?, ?, ?, ?, ?) "
                    "ON CONFLICT (day, kind, app, version, os, name) DO UPDATE SET n = n + excluded.n",
                    (day, kind, app, version, system, name, n),
                )

    def add_crash(self, who: tuple[str, str, str], signature: str, report: str, day: str | None = None) -> bool:
        """Counts a crash. True when this crash was never seen in this version of this app."""
        app, version, system = who
        day = day or today()
        with self.lock, self.db:
            known = self.db.execute(
                "SELECT 1 FROM crashes WHERE signature = ? AND app = ? AND version = ?", (signature, app, version)
            ).fetchone()
            if known:
                self.db.execute(
                    "UPDATE crashes SET n = n + 1, last_day = ? WHERE signature = ? AND app = ? AND version = ?",
                    (day, signature, app, version),
                )
            else:
                self.db.execute(
                    "INSERT INTO crashes VALUES (?, ?, ?, ?, ?, ?, 1, ?)",
                    (signature, app, version, system, day, day, report),
                )
            return not known

    def meta(self, key: str) -> str | None:
        with self.lock:
            row = self.db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None

    def set_meta(self, key: str, value: str) -> None:
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)", (key, value))

    def forget_old(self, now: date | None = None) -> None:
        now = now or datetime.now(timezone.utc).date()
        with self.lock, self.db:
            self.db.execute("DELETE FROM counts WHERE day < ?", ((now - timedelta(days=KEEP_COUNTS_DAYS)).isoformat(),))
            self.db.execute(
                "DELETE FROM crashes WHERE last_day < ?", ((now - timedelta(days=KEEP_CRASHES_DAYS)).isoformat(),)
            )

    def digest(self, days: int = 7, now: date | None = None) -> str | None:
        """The last `days` days in plain text, or None when nothing was reported."""
        now = now or datetime.now(timezone.utc).date()
        since = (now - timedelta(days=days)).isoformat()
        with self.lock:
            sent = self.db.execute(
                "SELECT app, version, name, SUM(n), COUNT(DISTINCT day) FROM counts "
                "WHERE kind = 'report' AND day > ? GROUP BY app, version, name ORDER BY app, version, name",
                (since,),
            ).fetchall()
            usage = self.db.execute(
                "SELECT app, name, SUM(n) FROM counts WHERE kind = 'usage' AND day > ? "
                "GROUP BY app, name ORDER BY app, SUM(n) DESC",
                (since,),
            ).fetchall()
            errors = self.db.execute(
                "SELECT app, version, name, SUM(n) FROM counts WHERE kind = 'error' AND day > ? "
                "GROUP BY app, version, name ORDER BY SUM(n) DESC",
                (since,),
            ).fetchall()
            crashes = self.db.execute(
                "SELECT app, version, os, signature, n, first_day, last_day FROM crashes "
                "WHERE last_day > ? ORDER BY n DESC",
                (since,),
            ).fetchall()
        if not (sent or usage or errors or crashes):
            return None
        lines = [f"NuVa, the {days} days up to {now.isoformat()}", ""]
        lines += ["REPORTS RECEIVED (an app reports about once a day, so reports per day is about the apps in use)"]
        lines += [f"  {app} {version}  {name}: {n} over {d} day(s)" for app, version, name, n, d in sent] or ["  none"]
        lines += ["", "CRASHES"]
        lines += [
            f"  {n}x  {app} {version} (system {system})  {signature}  [first {first}, last {last}]"
            for app, version, system, signature, n, first, last in crashes
        ] or ["  none"]
        lines += ["", "FAILURES (by kind)"]
        lines += [f"  {n}x  {app} {version}  {name}" for app, version, name, n in errors] or ["  none"]
        lines += ["", "USE (times each feature was used)"]
        app_now = None
        for app, name, n in usage:
            if app != app_now:
                lines.append(f"  {app}")
                app_now = app
            lines.append(f"    {n:>7}  {name}")
        if not usage:
            lines.append("  none")
        return "\n".join(lines) + "\n"


def mail(subject: str, text: str) -> None:
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = formataddr(("NuVa reports", SMTP_USER))
    message["To"] = REPORTS_TO
    message.set_content(text)
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
        smtp.starttls(context=ssl.create_default_context())
        smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(message)


def who(body: dict) -> tuple[str, str, str] | None:
    """The app, its version and the system's version, or None when they aren't what an app sends."""
    app, version, system = body.get("app"), body.get("version"), body.get("os")
    if app not in APPS or not isinstance(version, str) or not isinstance(system, str):
        return None
    if not VERSION.match(version) or not SYSTEM.match(system):
        return None
    # Major and minor only: a patch number adds rows and says little.
    return app, version, ".".join(system.split(".")[:2])


def count(value) -> int | None:
    # bool is an int in Python; a count is a whole number of times.
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= MAX_COUNT:
        return None
    return value


def take_usage(store: Store, body: dict) -> bool:
    sender = who(body)
    events = body.get("events")
    if sender is None or not isinstance(events, dict) or not events or len(events) > MAX_NAMES:
        return False
    counts = {}
    for name, n in events.items():
        if not isinstance(name, str) or not EVENT.match(name) or count(n) is None:
            return False
        counts[name] = n
    store.add("usage", sender, counts)
    store.add("report", sender, {"usage": 1})
    return True


def take_errors(store: Store, body: dict, on_new_crash=None) -> bool:
    sender = who(body)
    errors, crashes = body.get("errors", []), body.get("crashes", [])
    if sender is None or not isinstance(errors, list) or not isinstance(crashes, list):
        return False
    if not (errors or crashes) or len(errors) > MAX_NAMES or len(crashes) > MAX_CRASHES:
        return False
    counts: dict[str, int] = {}
    for item in errors:
        if not isinstance(item, dict):
            return False
        area, code, n = item.get("area"), item.get("code"), count(item.get("count"))
        if not isinstance(area, str) or not AREA.match(area) or not isinstance(code, str) or not CODE.match(code) or n is None:
            return False
        name = f"{area} {code}"
        counts[name] = counts.get(name, 0) + n
    seen = []
    for item in crashes:
        if not isinstance(item, dict):
            return False
        signature, report = item.get("signature"), item.get("report", "")
        if not isinstance(signature, str) or not SIGNATURE.match(signature) or not isinstance(report, str):
            return False
        seen.append((signature, report[:MAX_REPORT]))
    if counts:
        store.add("error", sender, counts)
    for signature, report in seen:
        if store.add_crash(sender, signature, report) and on_new_crash:
            on_new_crash(sender, signature, report)
    store.add("report", sender, {"errors": 1})
    return True


def new_crash(store: Store):
    """Mails a crash the first time it shows up, a few a day at most."""

    def tell(sender, signature, report):
        key = f"crash-mails-{today()}"
        sent = int(store.meta(key) or 0)
        if sent >= MAX_CRASH_MAILS or not (SMTP_USER and SMTP_PASSWORD and REPORTS_TO):
            return
        store.set_meta(key, str(sent + 1))
        app, version, system = sender
        text = f"A crash not seen before in {app} {version} (system {system}).\n\n{signature}\n\n{report}\n"

        def send():
            try:
                mail(f"NuVa crash: {app} {version}", text)
            except Exception as error:  # noqa: BLE001 - the digest will carry it anyway
                print(f"crash mail failed: {type(error).__name__}", flush=True)

        threading.Thread(target=send, daemon=True).start()

    return tell


def weekly(store: Store) -> None:
    """Every hour: forget what is old; on Mondays, mail the week once."""
    while True:
        try:
            store.forget_old()
            now = datetime.now(timezone.utc).date()
            if now.weekday() == 0 and store.meta("last-digest") != now.isoformat():
                text = store.digest()
                if text and SMTP_USER and SMTP_PASSWORD and REPORTS_TO:
                    mail(f"NuVa: the week to {now.isoformat()}", text)
                # After the mail went: one that failed is tried again in an hour.
                store.set_meta("last-digest", now.isoformat())
        except Exception as error:  # noqa: BLE001 - try again in an hour
            print(f"weekly failed: {type(error).__name__}", flush=True)
        time.sleep(3600)


def handler(store: Store):
    routes = {
        "/api/usage": lambda body: take_usage(store, body),
        "/api/errors": lambda body: take_errors(store, body, new_crash(store)),
    }

    class Handler(BaseHTTPRequestHandler):
        server_version = "nuva-reports"
        sys_version = ""

        def log_message(self, format, *args):
            # The default log line starts with the client's address; keep only the request.
            print(f"{self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)

        def reply(self, status: int) -> None:
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

        def do_POST(self):
            take = routes.get(self.path)
            if take is None:
                self.reply(404)
                return
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_BODY:
                self.reply(413)
                return
            raw = self.rfile.read(length)
            address = (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip()
            if not allowed(address):
                self.reply(429)
                return
            try:
                body = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                body = None
            if not isinstance(body, dict) or not take(body):
                self.reply(400)
                return
            self.reply(204)

    return Handler


if __name__ == "__main__":
    store = Store(DB_PATH)
    if sys.argv[1:] == ["digest"]:
        print(store.digest() or "Nothing was reported in the last 7 days.")
        sys.exit(0)
    if not (SMTP_USER and SMTP_PASSWORD and REPORTS_TO):
        print("SMTP_USER, SMTP_PASSWORD and REPORTS_TO (or FEEDBACK_TO) are needed to mail the digest", flush=True)
    threading.Thread(target=weekly, args=(store,), daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8081), handler(store)).serve_forever()

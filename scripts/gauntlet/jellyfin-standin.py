#!/usr/bin/env python3
"""A stand-in Jellyfin for the TV gauntlet (scripts/gauntlet/tv.sh): only what
android/app/src/main/java/pt/nunomartins/nuva/library/JellyfinSource.kt calls, over a made-up library.

Usage: jellyfin-standin.py <audio folder> [port]
The audio folder holds tone-<n>.flac files (tv.sh makes them with afconvert); every track streams one.
Accepts any username and password. Standard library only; never real music.
"""
import hashlib
import json
import os
import re
import sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

ROOT = "/media/music"
USER_ID = "gauntlet-user"
TOKEN = "gauntlet-token"

# Folder tree under the library: folder names as on a disk, track names with their extension.
LIBRARY = {
    "Fleetwood Mac": {
        "Rumours (1977)": [
            "01 - Second Hand News.flac", "02 - Dreams.flac", "03 - Never Going Back Again.flac",
            "04 - Don’t Stop.flac", "05 - Go Your Own Way.flac", "06 - Songbird.flac",
            "07 - The Chain.flac", "08 - You Make Loving Fun.flac", "09 - I Don’t Want to Know.flac",
            "10 - Oh Daddy.flac", "11 - Gold Dust Woman.flac",
        ],
        "Tusk (1979)": {
            "CD 1": ["01 - Over & Over.flac", "02 - The Ledge.flac", "03 - Think About Me.flac"],
            "CD 2": ["01 - That’s Enough for Me.flac", "02 - Brown Eyes.flac"],
        },
    },
    "Kraftwerk": {
        "Die Mensch-Maschine (1978) [2009 Remaster, Kling Klang Digital Master, 24-bit 96 kHz]": [
            "01 - Die Roboter.flac", "02 - Spacelab.flac", "03 - Metropolis.flac",
        ],
    },
    "Various Artists": {
        "Late Night Tales": ["1. Intro.flac", "2. Outro.flac", "10. Hidden Track.flac"],
    },
}
SECONDS = 180  # every track's length, as RunTimeTicks: the tones tv.sh makes are three minutes


def item_id(path):
    return hashlib.sha1(path.encode()).hexdigest()[:16]


def build():
    """Every item by id, and the children of every folder id."""
    items, children = {}, {}
    view = {"Id": "music-view", "Name": "Music", "IsFolder": True, "CollectionType": "music", "Path": None}
    items[view["Id"]] = view
    tones = 0

    def walk(node, parent_id, abs_path):
        nonlocal tones
        kids = children.setdefault(parent_id, [])
        entries = node.items() if isinstance(node, dict) else [(name, None) for name in node]
        for name, sub in entries:
            path = f"{abs_path}/{name}"
            iid = item_id(path)
            if sub is None:
                stem, ext = name.rsplit(".", 1)
                item = {"Id": iid, "Name": re.sub(r"^\d+\s*[-.]\s*", "", stem), "IsFolder": False, "Path": path,
                        "Container": ext, "RunTimeTicks": SECONDS * 10_000_000, "Tone": tones % 3}
                tones += 1
            else:
                item = {"Id": iid, "Name": name, "IsFolder": True, "Path": path}
                walk(sub, iid, path)
            items[iid] = item
            kids.append(item)

    walk(LIBRARY, view["Id"], ROOT)
    return view, items, children


VIEW, ITEMS, CHILDREN = build()


def cover_png(side=240):
    """A made-up cover, never a real one: four colour fields in the corners, as a PNG."""
    import struct
    import zlib
    corners = [(196, 120, 64), (52, 92, 148), (40, 128, 108), (168, 64, 84)]
    rows = bytearray()
    for y in range(side):
        rows.append(0)
        for x in range(side):
            fx, fy = x / (side - 1), y / (side - 1)
            top = [a * (1 - fx) + b * fx for a, b in zip(corners[0], corners[1])]
            bottom = [a * (1 - fx) + b * fx for a, b in zip(corners[2], corners[3])]
            rows += bytes(int(t * (1 - fy) + b * fy) for t, b in zip(top, bottom))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", side, side, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b"")


class Handler(BaseHTTPRequestHandler):
    audio = "."

    def log_message(self, fmt, *args):
        sys.stderr.write("standin: " + (fmt % args) + "\n")

    def send_json(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorised(self, query):
        header = self.headers.get("Authorization", "")
        return f'Token="{TOKEN}"' in header or query.get("api_key", [""])[0] == TOKEN

    def public(self, item):
        return {k: v for k, v in item.items() if k != "Tone"}

    def do_POST(self):
        if urlparse(self.path).path != "/Users/AuthenticateByName":
            return self.send_json({}, 404)
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        if not body.get("Username"):
            return self.send_json({}, 401)
        self.send_json({"AccessToken": TOKEN, "User": {"Id": USER_ID, "Name": body["Username"]}})

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if not self.authorised(query):
            return self.send_json({}, 401)
        if url.path in ("/UserViews", f"/Users/{USER_ID}/Views"):
            return self.send_json({"Items": [self.public(VIEW)]})
        if url.path in ("/Items", f"/Users/{USER_ID}/Items"):
            parent = query.get("parentId", [""])[0]
            if parent not in ITEMS:
                return self.send_json({}, 404)
            items = [self.public(i) for i in CHILDREN.get(parent, [])]
            # MediaSources only when asked for, as Jellyfin does: the size of the tone that streams.
            if "MediaSources" in query.get("fields", [""])[0]:
                for i in items:
                    if not i["IsFolder"]:
                        tone = os.path.join(self.audio, f"tone-{ITEMS[i['Id']]['Tone']}.flac")
                        i["MediaSources"] = [{"Id": i["Id"], "Size": os.path.getsize(tone)}]
            return self.send_json({"Items": items})
        # Folder artwork: Rumours (1977) has a cover.png in the folder, as Jellyfin reports it.
        match = re.fullmatch(r"/Items/([0-9a-f]+)/Images(/Primary)?", url.path)
        if match and match.group(1) in ITEMS:
            item = ITEMS[match.group(1)]
            has_cover = item.get("IsFolder") and item["Path"].endswith("/Rumours (1977)")
            if match.group(2) is None:
                return self.send_json([{"ImageType": "Primary", "Path": item["Path"] + "/cover.png"}] if has_cover else [])
            if has_cover:
                body = cover_png()
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                return self.wfile.write(body)
            return self.send_json({}, 404)
        match = re.fullmatch(r"/Audio/([0-9a-f]+)/stream\.(\w+)", url.path)
        if match and match.group(1) in ITEMS:
            return self.stream(os.path.join(self.audio, f"tone-{ITEMS[match.group(1)]['Tone']}.flac"))
        self.send_json({}, 404)

    def stream(self, file):
        data = open(file, "rb").read()
        start, end = 0, len(data) - 1
        ranged = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if ranged:
            start = int(ranged.group(1) or 0)
            end = int(ranged.group(2)) if ranged.group(2) else end
        chunk = data[start:end + 1]
        self.send_response(206 if ranged else 200)
        self.send_header("Content-Type", "audio/flac")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(chunk)))
        if ranged:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        self.wfile.write(chunk)


if __name__ == "__main__":
    Handler.audio = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8096
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()

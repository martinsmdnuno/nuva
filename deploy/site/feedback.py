"""The site's feedback form: takes a POST to /api/feedback and sends it by email.

Standard library only. Keeps nothing: no database, no files, and no IP addresses
in the logs (they are held in memory for an hour, only to slow down floods).

Environment: SMTP_USER and SMTP_PASSWORD (a Gmail address and an app password),
FEEDBACK_TO (where the messages go), and optionally SMTP_HOST and SMTP_PORT.
"""

import json
import os
import re
import smtplib
import ssl
import threading
import time
from email.message import EmailMessage
from email.utils import formataddr
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
# 587 with STARTTLS: Hetzner blocks outgoing 25 and 465 by default.
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
FEEDBACK_TO = os.environ.get("FEEDBACK_TO", "")

MAX_BODY = 20_000
MAX_MESSAGE = 5_000
# Per address: at most this many messages an hour.
LIMIT = 5
EMAIL = re.compile(r"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$")

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


def send(message: str, reply_to: str | None, language: str) -> None:
    mail = EmailMessage()
    mail["Subject"] = f"NuVa feedback ({language})"
    mail["From"] = formataddr(("NuVa site", SMTP_USER))
    mail["To"] = FEEDBACK_TO
    if reply_to:
        mail["Reply-To"] = reply_to
    mail.set_content(f"{message}\n\n--\nFrom: {reply_to or 'no email given'}\nPage: nuva.martinsnuno.com ({language})\n")
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
        smtp.starttls(context=ssl.create_default_context())
        smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(mail)


PAGES = {
    "en": ("Thank you. Your message was sent.", "Couldn't send it. Please try again later.", "/"),
    "pt": ("Obrigado. A mensagem foi enviada.", "Não foi possível enviar. Tenta de novo mais tarde.", "/pt/"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "nuva-feedback"
    sys_version = ""

    def log_message(self, format, *args):
        # The default log line starts with the client's address; keep only the request.
        print(f"{self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)

    def reply(self, ok: bool, language: str, status: int) -> None:
        if "application/json" in self.headers.get("Accept", ""):
            body = json.dumps({"success": ok}).encode()
            kind = "application/json"
        else:
            # Without JavaScript the form posts here directly: answer with a small page.
            text, error, home = PAGES[language]
            body = (
                f'<!doctype html><html lang="{language}"><meta charset="utf-8">'
                f'<meta name="viewport" content="width=device-width, initial-scale=1">'
                f'<link rel="stylesheet" href="/style.css"><title>NuVa</title>'
                f'<main class="wrap narrow hero"><h1>{text if ok else error}</h1>'
                f'<p><a class="key mode" href="{home}#feedback">NuVa</a></p></main></html>'
            ).encode()
            kind = "text/html; charset=utf-8"
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/feedback":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self.reply(False, "en", 413)
            return
        fields = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        field = lambda name: (fields.get(name) or [""])[0].strip()
        language = "pt" if field("language") == "pt" else "en"
        message = field("message")[:MAX_MESSAGE]
        email = field("email")

        # The honeypot: people never see this field, bots fill it in. Pretend it worked.
        if field("website"):
            self.reply(True, language, 200)
            return
        if not message:
            self.reply(False, language, 400)
            return
        address = (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip()
        if not allowed(address):
            self.reply(False, language, 429)
            return
        try:
            send(message, email if EMAIL.match(email) else None, language)
        except Exception as error:  # noqa: BLE001 - any failure is the same to the visitor
            print(f"send failed: {type(error).__name__}", flush=True)
            self.reply(False, language, 502)
            return
        self.reply(True, language, 200)


if __name__ == "__main__":
    if not (SMTP_USER and SMTP_PASSWORD and FEEDBACK_TO):
        print("SMTP_USER, SMTP_PASSWORD and FEEDBACK_TO are required (see .env.example)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

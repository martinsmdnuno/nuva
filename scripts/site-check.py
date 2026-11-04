#!/usr/bin/env python3
"""The site's objective checks for the gauntlet (scripts/gauntlet/site.sh, docs/gauntlet/site.md).

Usage: python3 scripts/site-check.py <html|links|privacy|seo|parity>
       python3 scripts/site-check.py snapshots <out folder>   (PNGs and render.json, Chrome headless)
       python3 scripts/site-check.py layout <out folder>      (reads render.json)

Standard library only. Prints one line per problem and exits 1 if there is any.
"""
import html
import http.server
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
ORIGIN = "https://nuva.martinsnuno.com"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
PLATFORM_HASHES = {"mac": "#mac", "tv": "#android-tv", "windows": "#windows"}  # site/platform.js
LANGS = {"en", "pt-PT"}
TITLE_MAX, DESCRIPTION_MIN, DESCRIPTION_MAX = 65, 70, 160

problems = []


def problem(where, text):
    problems.append(f"{where}: {text}")


# --- Parsing ---------------------------------------------------------------------------------------

class Node:
    def __init__(self, tag, attrs, parent, line):
        self.tag, self.attrs, self.parent, self.line = tag, dict(attrs), parent, line
        self.children, self.text = [], []

    def all(self):
        yield self
        for child in self.children:
            if isinstance(child, Node):
                yield from child.all()

    def find(self, tag=None, **attrs):
        return [n for n in self.all() if (tag is None or n.tag == tag)
                and all(n.attrs.get(k.rstrip("_")) == v for k, v in attrs.items())]

    def content(self):
        """Visible text, with whitespace collapsed (what a reader sees)."""
        parts = []
        for child in self.children:
            parts.append(child.content() if isinstance(child, Node) else child)
        return re.sub(r"\s+", " ", "".join(parts)).strip()

    def platforms(self):
        return set(self.attrs.get("data-for", "").split())


class Page(HTMLParser):
    """A small tree builder that also checks that every element is closed, in order."""

    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.name = str(path.relative_to(SITE))
        self.root = Node("#root", [], None, 0)
        self.stack = [self.root]
        self.raw = path.read_text(encoding="utf-8")
        self.feed(self.raw)
        self.close()
        for open_node in self.stack[1:]:
            problem(self.name, f"<{open_node.tag}> on line {open_node.line} is never closed")

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.stack[-1], self.getpos()[0])
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        node = Node(tag, attrs, self.stack[-1], self.getpos()[0])
        self.stack[-1].children.append(node)

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if self.stack[-1].tag == tag:
            self.stack.pop()
            return
        open_tags = [n.tag for n in self.stack]
        problem(self.name, f"line {self.getpos()[0]}: </{tag}> closes <{self.stack[-1].tag}>"
                + ("" if tag in open_tags else f" (no <{tag}> is open)"))
        if tag in open_tags:
            while self.stack[-1].tag != tag:
                self.stack.pop()
            self.stack.pop()

    def handle_data(self, data):
        self.stack[-1].children.append(data)

    # Helpers
    @property
    def url(self):
        rel = self.name
        if rel.endswith("index.html"):
            rel = rel[: -len("index.html")]
        return f"{ORIGIN}/{rel}"

    @property
    def lang(self):
        h = self.root.find("html")
        return h[0].attrs.get("lang") if h else None

    def meta(self, key, value):
        for m in self.root.find("meta"):
            if m.attrs.get(key) == value:
                return m.attrs.get("content")
        return None

    @property
    def indexed(self):
        return "noindex" not in (self.meta("name", "robots") or "")

    def link(self, rel):
        return [l for l in self.root.find("link") if rel in l.attrs.get("rel", "").split()]

    def alternates(self):
        return {l.attrs.get("hreflang"): l.attrs.get("href") for l in self.link("alternate") if l.attrs.get("hreflang")}

    def ids(self):
        return {n.attrs["id"] for n in self.root.all() if "id" in n.attrs}

    def has_switcher(self):
        return bool(self.root.find("button")) and any("data-platform" in b.attrs for b in self.root.find("button"))

    def switcher_keys(self):
        return [b.attrs["data-platform"] for b in self.root.find("button") if "data-platform" in b.attrs]


def pages():
    return [Page(p) for p in sorted(SITE.rglob("*.html"))]


def page_for_url(all_pages, url):
    return next((p for p in all_pages if p.url == url), None)


def caddy_routes():
    """Paths the site's Caddy answers itself (a handler or a redirect), not files."""
    caddy = (ROOT / "deploy/site/Caddyfile").read_text()
    return set(re.findall(r"^\s*(?:handle|redir)\s+(/[^\s{]+)", caddy, re.M))


def site_file(path):
    """The file under site/ a same-origin path names (or a route the Caddyfile answers), or None."""
    path = path.split("#")[0].split("?")[0]
    if path.startswith(ORIGIN):
        path = path[len(ORIGIN):] or "/"
    if not path.startswith("/"):
        return None
    if path in caddy_routes():
        return ROOT / "deploy/site/Caddyfile"
    target = SITE / path.lstrip("/")
    if path.endswith("/"):
        target = target / "index.html"
    return target if target.is_file() else None


def features():
    return json.loads((ROOT / "docs/features.json").read_text())


def released_platforms():
    return [p for p in features()["platforms"] if p.get("status") == "released" and p.get("public", True)]


def marketing_version():
    m = re.search(r'^\s*MARKETING_VERSION:\s*"?([^"\s]+)"?\s*$', (ROOT / "project.yml").read_text(), re.M)
    return m.group(1)


def json_ld(page):
    blocks = []
    for script in page.root.find("script"):
        if script.attrs.get("type") == "application/ld+json":
            raw = "".join(c for c in script.children if isinstance(c, str))
            try:
                blocks.append(json.loads(raw))
            except json.JSONDecodeError as error:
                problem(page.name, f"JSON-LD on line {script.line} doesn't parse: {error}")
    items = []
    for block in blocks:
        items.extend(block.get("@graph", [block]))
    return items


def css_urls(text):
    return re.findall(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)", text) + \
        re.findall(r"@import\s+(?:url\()?\s*['\"]([^'\"]+)['\"]", text)


# --- Gates -----------------------------------------------------------------------------------------

def check_html():
    all_pages = pages()
    titles = {}
    for page in all_pages:
        n = page.name
        if not page.raw.lstrip().lower().startswith("<!doctype html>"):
            problem(n, "doesn't start with <!doctype html>")
        if page.lang not in LANGS:
            problem(n, f"<html lang> is {page.lang!r}, not one of {sorted(LANGS)}")
        elif (page.name.startswith("pt/")) != (page.lang == "pt-PT"):
            problem(n, f"<html lang=\"{page.lang}\"> doesn't match where the page lives")
        charset = [m for m in page.root.find("meta") if m.attrs.get("charset", "").lower() == "utf-8"]
        if not charset:
            problem(n, "no <meta charset=\"utf-8\">")
        viewport = page.meta("name", "viewport") or ""
        if "width=device-width" not in viewport:
            problem(n, "no <meta name=\"viewport\" content=\"width=device-width…\">")
        h1 = page.root.find("h1")
        if len(h1) != 1:
            problem(n, f"has {len(h1)} <h1>, needs exactly one")
        title = page.root.find("title")
        title_text = title[0].content() if title else ""
        if not title_text:
            problem(n, "no <title>")
        elif len(title_text) > TITLE_MAX:
            problem(n, f"<title> is {len(title_text)} characters, more than {TITLE_MAX}: {title_text!r}")
        if title_text in titles:
            problem(n, f"<title> is the same as {titles[title_text]}'s")
        titles[title_text] = n
        description = page.meta("name", "description")
        if page.indexed:
            if not description:
                problem(n, "no <meta name=\"description\">")
            elif not DESCRIPTION_MIN <= len(description) <= DESCRIPTION_MAX:
                problem(n, f"meta description is {len(description)} characters, outside {DESCRIPTION_MIN}–{DESCRIPTION_MAX}")
        for img in page.root.find("img"):
            for attr in ("alt", "width", "height"):
                if attr not in img.attrs:
                    problem(n, f"line {img.line}: <img src=\"{img.attrs.get('src')}\"> has no {attr}")
        seen = set()
        for node in page.root.all():
            i = node.attrs.get("id")
            if i is not None:
                if i in seen:
                    problem(n, f"line {node.line}: id \"{i}\" is used twice")
                seen.add(i)
        for node in page.root.all():
            if node.tag in ("a", "button") and not node.content() and not node.attrs.get("aria-label") \
                    and not any(c.attrs.get("alt") for c in node.all() if c.tag == "img"):
                problem(n, f"line {node.line}: <{node.tag}> has no text or label")
        for field in page.root.find("textarea") + [i for i in page.root.find("input") if i.attrs.get("type") not in ("hidden",)]:
            if field.attrs.get("aria-hidden") == "true":
                continue
            if not any(a.tag == "label" for a in ancestors(field)) and not field.attrs.get("aria-label"):
                problem(n, f"line {field.line}: <{field.tag} name=\"{field.attrs.get('name')}\"> has no label")
    print(f"{len(all_pages)} pages checked")


def ancestors(node):
    node = node.parent
    while node is not None:
        yield node
        node = node.parent


def check_links():
    all_pages = pages()
    by_url = {p.url: p for p in all_pages}
    for page in all_pages:
        n = page.name
        ids = page.ids()
        for node in page.root.all():
            for attr in ("href", "src", "srcset", "action", "poster", "data"):
                value = node.attrs.get(attr)
                if not value:
                    continue
                values = [v.strip().split(" ")[0] for v in value.split(",")] if attr == "srcset" else [value]
                for v in values:
                    check_reference(page, node, v, ids, by_url)
            style = node.attrs.get("style", "")
            for v in css_urls(style):
                check_reference(page, node, v, ids, by_url)
        for v in re.findall(r'content="(https://nuva\.martinsnuno\.com/[^"]*)"', page.raw):
            if not site_file(v):
                problem(n, f"meta content {v} names no file under site/")
        if page.indexed:
            canonical = page.link("canonical")
            if len(canonical) != 1:
                problem(n, f"has {len(canonical)} canonical links, needs one")
            elif canonical[0].attrs.get("href") != page.url:
                problem(n, f"canonical is {canonical[0].attrs.get('href')}, not {page.url}")
            og = page.meta("property", "og:url")
            if og and og != page.url:
                problem(n, f"og:url is {og}, not {page.url}")
            alternates = page.alternates()
            if not alternates:
                problem(n, "no hreflang alternates")
            own = "pt" if page.lang == "pt-PT" else "en"
            if alternates.get(own) != page.url:
                problem(n, f"hreflang=\"{own}\" is {alternates.get(own)}, not the page itself ({page.url})")
            if set(alternates) - {"x-default"} != {"en", "pt"}:
                problem(n, f"hreflang alternates are {sorted(alternates)}, need en and pt")
            for lang, url in alternates.items():
                other = by_url.get(url)
                if other is None:
                    problem(n, f"hreflang=\"{lang}\" points at {url}, which is no page here")
                    continue
                if lang != "x-default" and (other.lang or "").split("-")[0] != lang:
                    problem(n, f"hreflang=\"{lang}\" points at {other.name}, whose lang is {other.lang}")
                if other.alternates() != alternates:
                    problem(n, f"hreflang alternates differ from {other.name}'s (not reciprocal): {alternates} vs {other.alternates()}")
    # CSS
    for css in SITE.rglob("*.css"):
        for v in css_urls(css.read_text()):
            if v.startswith("data:"):
                continue
            if not site_file(v):
                problem(str(css.relative_to(SITE)), f"url({v}) names no file under site/")
    # The sitemap lists every indexed page, with its alternates, and nothing else.
    sitemap = (SITE / "sitemap.xml").read_text()
    entries = re.findall(r"<url>(.*?)</url>", sitemap, re.S)
    listed = {}
    for entry in entries:
        loc = re.search(r"<loc>([^<]+)</loc>", entry).group(1)
        if loc in listed:
            problem("sitemap.xml", f"{loc} is listed twice")
        listed[loc] = dict(re.findall(r'hreflang="([^"]+)" href="([^"]+)"', entry))
    indexed = {p.url: p for p in all_pages if p.indexed}
    for url in sorted(set(indexed) - set(listed)):
        problem("sitemap.xml", f"doesn't list {url}")
    for url in sorted(set(listed) - set(indexed)):
        problem("sitemap.xml", f"lists {url}, which is no indexed page")
    for url, alts in listed.items():
        if url in indexed:
            expected = {k: v for k, v in indexed[url].alternates().items() if k != "x-default"}
            if alts != expected:
                problem("sitemap.xml", f"{url}: alternates {alts} differ from the page's {expected}")
    # Every file in site/ is used by something (no stale images or pages left behind).
    used = set()
    texts = [p.raw for p in all_pages] + [c.read_text() for c in SITE.rglob("*.css")] + [(SITE / "llms.txt").read_text()]
    for f in SITE.rglob("*"):
        if f.is_file() and f.suffix not in (".html",) and f.name not in ("robots.txt", "sitemap.xml", "llms.txt", "favicon.ico"):
            rel = "/" + str(f.relative_to(SITE))
            if not any(rel in t for t in texts):
                problem(rel, "is in site/ but nothing links to it")
    print(f"{len(all_pages)} pages, {len(listed)} sitemap entries checked")


def check_reference(page, node, value, ids, by_url):
    n = page.name
    if re.match(r"^(https?:)?//", value):
        if value.startswith(ORIGIN):
            if not site_file(value):
                problem(n, f"line {node.line}: {value} names no file under site/")
        return
    if re.match(r"^[a-z]+:", value):  # mailto:, data:, tel:
        return
    path, _, fragment = value.partition("#")
    if not path:
        target_ids, target = ids, page
    else:
        resolved = path if path.startswith("/") else "/" + str((page.path.parent / path).resolve().relative_to(SITE))
        f = site_file(resolved)
        if f is None:
            problem(n, f"line {node.line}: {value} names no file under site/")
            return
        target = next((p for p in by_url.values() if p.path == f), None)
        target_ids = target.ids() if target else set()
    if fragment:
        is_platform = target is not None and target.has_switcher() and ("#" + fragment.lower()) in list(PLATFORM_HASHES.values()) + ["#tv"]
        if fragment not in target_ids and not is_platform:
            problem(n, f"line {node.line}: {value}: no element with id \"{fragment}\"")


def check_privacy():
    other_host = re.compile(r"^(https?:)?//(?!nuva\.martinsnuno\.com[/:]|nuva\.martinsnuno\.com$)", re.I)
    loads = {"link": "href", "script": "src", "img": "src", "iframe": "src", "source": "src", "video": "src",
             "audio": "src", "embed": "src", "object": "data", "track": "src", "input": "src"}
    for page in pages():
        n = page.name
        for node in page.root.all():
            attr = loads.get(node.tag)
            if node.tag == "link" and set(node.attrs.get("rel", "").split()) & {"canonical", "alternate"}:
                attr = None  # an address, not a load
            if node.tag == "iframe":
                problem(n, f"line {node.line}: an <iframe>")
            if attr and other_host.match(node.attrs.get(attr, "")):
                problem(n, f"line {node.line}: <{node.tag}> loads {node.attrs[attr]} from another host")
            for v in [s.strip().split(" ")[0] for s in node.attrs.get("srcset", "").split(",") if s.strip()]:
                if other_host.match(v):
                    problem(n, f"line {node.line}: srcset loads {v} from another host")
            for v in css_urls(node.attrs.get("style", "")):
                if other_host.match(v):
                    problem(n, f"line {node.line}: style loads {v} from another host")
            if node.tag == "form" and other_host.match(node.attrs.get("action", "")):
                problem(n, f"line {node.line}: the form posts to another host")
            for attr_name in node.attrs:
                if attr_name.startswith("on"):
                    problem(n, f"line {node.line}: inline handler {attr_name}= (the CSP blocks it)")
            if node.tag == "script" and "src" not in node.attrs and node.attrs.get("type") != "application/ld+json":
                problem(n, f"line {node.line}: an inline <script> (the CSP allows only files from the site)")
            if node.tag == "style":
                for v in css_urls(node.content()):
                    if other_host.match(v):
                        problem(n, f"line {node.line}: <style> loads {v} from another host")
            if node.tag == "meta" and node.attrs.get("http-equiv", "").lower() in ("set-cookie", "refresh"):
                problem(n, f"line {node.line}: <meta http-equiv=\"{node.attrs['http-equiv']}\">")
    for css in SITE.rglob("*.css"):
        for v in css_urls(css.read_text()):
            if other_host.match(v):
                problem(str(css.relative_to(SITE)), f"loads {v} from another host")
    storage = re.compile(r"document\.cookie|localStorage|sessionStorage|indexedDB|navigator\.sendBeacon|WebSocket|EventSource|serviceWorker")
    for js in SITE.rglob("*.js"):
        text = js.read_text()
        rel = str(js.relative_to(SITE))
        for m in storage.finditer(text):
            problem(rel, f"uses {m.group(0)} (no storage, no tracking)")
        for m in re.finditer(r"""["'`]((?:https?:)?//[^"'`]+)""", text):
            problem(rel, f"names an address on another host: {m.group(1)}")
        for m in re.finditer(r"\bimport\s*\(|\bimportScripts\s*\(|XMLHttpRequest", text):
            problem(rel, f"uses {m.group(0).strip()} (only fetch to the site's own form action)")
    # The Caddyfile: the CSP keeps everything on the site, no access log, no cookies.
    caddy = (ROOT / "deploy/site/Caddyfile").read_text()
    csp = re.search(r'Content-Security-Policy\s+"([^"]+)"', caddy)
    if not csp:
        problem("deploy/site/Caddyfile", "no Content-Security-Policy header")
    else:
        directives = {d.split()[0]: d.split()[1:] for d in csp.group(1).split(";") if d.strip()}
        if directives.get("default-src") != ["'self'"]:
            problem("Caddyfile", f"CSP default-src is {directives.get('default-src')}, not 'self'")
        allowed = {"'self'", "'none'"}
        extra = {"img-src": {"data:"}, "font-src": {"data:"}, "style-src": {"'unsafe-inline'"}}
        for name, sources in directives.items():
            for source in sources:
                if source not in allowed | extra.get(name, set()):
                    problem("Caddyfile", f"CSP {name} allows {source}")
        for needed, value in (("frame-ancestors", ["'none'"]), ("form-action", ["'self'"]), ("base-uri", ["'self'"])):
            if directives.get(needed) != value:
                problem("Caddyfile", f"CSP {needed} is {directives.get(needed)}, not {' '.join(value)}")
    code = "\n".join(l.split("#")[0] for l in caddy.splitlines())
    if re.search(r"^\s*log\b", code, re.M):
        problem("Caddyfile", "has a log directive (the site keeps no access log)")
    if re.search(r"set-cookie", code, re.I):
        problem("Caddyfile", "sets a cookie")
    feedback = (ROOT / "deploy/site/feedback.py").read_text()
    if re.search(r"set-cookie|open\([^)]*['\"][wa]", feedback, re.I):
        problem("deploy/site/feedback.py", "sets a cookie or writes a file (it keeps nothing)")
    print("no other hosts, no storage; CSP is 'self'")


def faq_visible(page):
    sections = [s for s in page.root.find("section") if s.attrs.get("id") == "faq"]
    if not sections:
        return []
    return [(d.find("summary")[0].content(), " ".join(p.content() for p in d.find("p")))
            for d in sections[0].find("details")]


def check_seo():
    version = marketing_version()
    all_pages = pages()
    apps = {}
    for page in all_pages:
        n = page.name
        items = json_ld(page)
        if not page.indexed:
            continue
        if not items and page.root.find("section"):
            problem(n, "no JSON-LD")
        for item in items:
            kind = item.get("@type")
            if kind == "SoftwareApplication":
                apps[page.lang] = (page, item)
                if item.get("softwareVersion") != version:
                    problem(n, f"softwareVersion is {item.get('softwareVersion')}, project.yml says {version}")
                if item.get("url") != page.url:
                    problem(n, f"SoftwareApplication url is {item.get('url')}, not {page.url}")
                for url in [item.get("image")] + list(item.get("screenshot", [])):
                    if url and url.startswith(ORIGIN) and not site_file(url):
                        problem(n, f"JSON-LD names {url}, no file under site/")
            if kind == "FAQPage":
                ld = [(q.get("name"), q.get("acceptedAnswer", {}).get("text")) for q in item.get("mainEntity", [])]
                visible = faq_visible(page)
                if len(ld) != len(visible):
                    problem(n, f"FAQPage has {len(ld)} questions, the page shows {len(visible)}")
                for i, ((lq, la), (vq, va)) in enumerate(zip(ld, visible), 1):
                    if lq != vq:
                        problem(n, f"FAQ {i}: JSON-LD question {lq!r} ≠ visible {vq!r}")
                    if la != va:
                        problem(n, f"FAQ {i}: JSON-LD answer differs from the visible one:\n    JSON-LD: {la}\n    visible: {va}")
        for prop in ("og:title", "og:description", "og:image", "og:url"):
            if page.root.find("section") and not page.meta("property", prop):
                problem(n, f"no {prop}")
        image = page.meta("property", "og:image")
        if image and not site_file(image):
            problem(n, f"og:image {image} names no file under site/")
    if "en" in apps and "pt-PT" in apps:
        en, pt = apps["en"][1], apps["pt-PT"][1]
        if set(en) != set(pt):
            problem("index.html / pt/index.html", f"SoftwareApplication properties differ: only EN {sorted(set(en) - set(pt))}, only PT {sorted(set(pt) - set(en))}")
        for key in set(en) & set(pt):
            if isinstance(en[key], list) and isinstance(pt[key], list) and len(en[key]) != len(pt[key]):
                problem("index.html / pt/index.html", f"SoftwareApplication {key} has {len(en[key])} items in EN, {len(pt[key])} in PT")
        for key in ("softwareVersion", "downloadUrl", "installUrl", "license", "image", "screenshot", "offers", "sameAs"):
            if en.get(key) != pt.get(key):
                problem("index.html / pt/index.html", f"SoftwareApplication {key} differs between EN and PT")
    robots = (SITE / "robots.txt").read_text()
    if f"Sitemap: {ORIGIN}/sitemap.xml" not in robots:
        problem("robots.txt", "doesn't point at the sitemap")
    if re.search(r"^Disallow:\s*/\s*$", robots, re.M):
        problem("robots.txt", "disallows the whole site")
    llms = (SITE / "llms.txt").read_text()
    if not re.search(rf"Current version: {re.escape(version)}\.(\s|$)", llms):
        problem("llms.txt", f"doesn't say \"Current version: {version}.\"")
    summary = next((l for l in llms.splitlines() if l.startswith(">")), "")
    for platform in released_platforms():
        names = {platform["name"]["en"], platform["schemaOS"]["en"].split()[0]}  # Mac or macOS
        if not any(name in summary for name in names):
            problem("llms.txt", f"the summary (the > line) doesn't name {platform['name']['en']}, a released platform")
    for page in all_pages:
        if page.indexed and page.url not in llms:
            problem("llms.txt", f"doesn't link {page.url}")
    print(f"version {version}; JSON-LD, FAQ, robots.txt and llms.txt checked")


def structure(page):
    """What EN and PT must share: section ids, and per section the platform variants and images."""
    shape = []
    for s in page.root.find("section"):
        variants = sorted(f"{n.tag}[{n.attrs['data-for']}]" for n in s.all() if "data-for" in n.attrs)
        images = [n.attrs.get("src") for n in s.all() if n.tag == "img"]
        shape.append((s.attrs.get("id"), variants, images, len(s.find("details")), len(s.find("li"))))
    return shape


def check_parity():
    keys_expected = [p["id"] for p in released_platforms()]
    all_pages = pages()
    for page in all_pages:
        n = page.name
        if not page.has_switcher():
            if any("data-for" in node.attrs for node in page.root.all()):
                problem(n, "has data-for blocks but no platform switcher")
            continue
        keys = page.switcher_keys()
        if sorted(keys) != sorted(keys_expected):
            problem(n, f"switcher keys are {keys}; the released platforms in docs/features.json are {keys_expected}")
        for key in keys:
            if key not in PLATFORM_HASHES:
                problem(n, f"switcher key {key} has no address in platform.js")
        groups = {}
        for node in page.root.all():
            if "data-for" not in node.attrs:
                continue
            unknown = node.platforms() - set(keys)
            if unknown:
                problem(n, f"line {node.line}: data-for names {sorted(unknown)}, which has no key")
            groups.setdefault((id(node.parent), node.tag), []).append(node)
        for (_, tag), nodes in groups.items():
            covered = set().union(*(x.platforms() for x in nodes))
            missing = set(keys) - covered
            if missing:
                problem(n, f"line {nodes[0].line}: the <{tag} data-for> blocks here cover {sorted(covered)}, none for {sorted(missing)}")
        for key in keys:
            if not any(key in x.platforms() for x in page.root.find("figure") + page.root.find("img")) \
                    and not any(x.tag in ("img", "figure") and not x.platforms() and not any(a.platforms() for a in ancestors(x)) for x in page.root.all()):
                problem(n, f"no picture shows for {key}")
    # EN and PT have the same shape.
    pairs = [("index.html", "pt/index.html"), ("privacy/index.html", "pt/privacidade/index.html")]
    by_name = {p.name: p for p in all_pages}
    for en_name, pt_name in pairs:
        en, pt = by_name.get(en_name), by_name.get(pt_name)
        if not en or not pt:
            problem(en_name, f"has no pair {pt_name}")
            continue
        for a, b in zip(structure(en), structure(pt)):
            if a != b:
                problem(pt_name, f"section {a[0]!r} differs from {en_name}:\n    EN {a}\n    PT {b}")
        if len(structure(en)) != len(structure(pt)):
            problem(pt_name, f"has {len(structure(pt))} sections, {en_name} has {len(structure(en))}")
        for tag in ("h2", "h3", "li", "img", "details", "pre", "form", "input", "textarea", "button"):
            if len(en.root.find(tag)) != len(pt.root.find(tag)):
                problem(pt_name, f"has {len(pt.root.find(tag))} <{tag}>, {en_name} has {len(en.root.find(tag))}")
        # The same address in each language's own version (a fragment or ?hl=) is the same link.
        external = lambda p: sorted(re.split(r"[#?]", a.attrs["href"])[0] for a in p.root.find("a") if a.attrs.get("href", "").startswith(("http", "mailto")))
        if external(en) != external(pt):
            problem(pt_name, f"links elsewhere differ from {en_name}: only EN {sorted(set(external(en)) - set(external(pt)))}, only PT {sorted(set(external(pt)) - set(external(en)))}")
    print("platform variants and EN/PT structure checked")


# --- Snapshots (Chrome headless over the DevTools pipe) ---------------------------------------------

class Chrome:
    """Chrome headless driven over --remote-debugging-pipe: no websocket, no third-party package."""

    def __init__(self):
        self.profile = tempfile.TemporaryDirectory()
        to_chrome_r, self.to_chrome = os.pipe()
        self.from_chrome, from_chrome_w = os.pipe()
        # Chrome reads commands on fd 3 and writes replies on fd 4; the shell puts the pipes there.
        self.process = subprocess.Popen(
            ["/bin/sh", "-c", f'exec "$0" "$@" 3<&{to_chrome_r} 4>&{from_chrome_w}', CHROME,
             "--headless=new", "--remote-debugging-pipe", f"--user-data-dir={self.profile.name}",
             "--no-first-run", "--no-default-browser-check", "--hide-scrollbars", "--disable-extensions",
             "--disable-gpu", "--mute-audio", "about:blank"],
            pass_fds=(to_chrome_r, from_chrome_w), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(to_chrome_r)
        os.close(from_chrome_w)
        self.reader = os.fdopen(self.from_chrome, "rb")
        self.buffer = b""
        self.next_id = 0
        target = next(t for t in self.send("Target.getTargets")["targetInfos"] if t["type"] == "page")
        self.session = self.send("Target.attachToTarget", targetId=target["targetId"], flatten=True)["sessionId"]
        self.send("Page.enable", session=True)
        self.send("Runtime.enable", session=True)

    def send(self, method, session=False, **params):
        self.next_id += 1
        message = {"id": self.next_id, "method": method, "params": params}
        if session:
            message["sessionId"] = self.session
        os.write(self.to_chrome, json.dumps(message).encode() + b"\0")
        while True:
            reply = self.receive()
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply.get("result", {})
            if reply.get("method") == "Page.loadEventFired":
                self.loaded = True

    def receive(self):
        while b"\0" not in self.buffer:
            chunk = self.reader.read1(1 << 20)
            if not chunk:
                raise RuntimeError("Chrome closed the pipe")
            self.buffer += chunk
        raw, self.buffer = self.buffer.split(b"\0", 1)
        return json.loads(raw)

    def wait_load(self):
        while not getattr(self, "loaded", False):
            if self.receive().get("method") == "Page.loadEventFired":
                self.loaded = True

    def evaluate(self, expression):
        result = self.send("Runtime.evaluate", session=True, expression=expression, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in result:
            raise RuntimeError(f"evaluate: {result['exceptionDetails']}")
        return result["result"].get("value")

    def close(self):
        try:
            self.send("Browser.close")
        except Exception:
            pass
        self.process.wait(timeout=10)
        self.profile.cleanup()


# Before a capture: lazy images load now (the capture is the whole page), then fonts and images settle.
SETTLE = r"""
(async () => {
  for (const img of document.images) img.loading = "eager";
  const settled = (p) => Promise.race([p, new Promise((r) => setTimeout(r, 5000))]);
  await settled(document.fonts.ready);
  await settled(Promise.all([...document.images].map((i) => i.complete ? null : new Promise((r) => { i.onload = i.onerror = r; }))));
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
})()
"""

# Measured in the page after each capture: horizontal overflow, the platform shown, and text contrast.
MEASURE = r"""
(() => {
  // rgb(r, g, b[, a]) with 0–255, or color(srgb r g b[ / a]) with 0–1 (what color-mix() computes to).
  const parse = (c) => {
    const m = (c.match(/[\d.]+/g) || []).map(Number);
    if (m.length < 3) return null;
    const k = c.startsWith("color(") ? 255 : 1;
    return [m[0] * k, m[1] * k, m[2] * k, m.length > 3 ? m[3] : 1];
  };
  const lum = ([r, g, b]) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const blend = (top, bottom) => { const a = top[3]; return [0, 1, 2].map((i) => top[i] * a + bottom[i] * (1 - a)).concat(1); };
  const background = (el) => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c && c[3] > 0) { layers.push(c); if (c[3] >= 1) break; }
    }
    let bg = [255, 255, 255, 1];
    for (const c of layers.reverse()) bg = blend(c, bg);
    return bg;
  };
  const low = [];
  for (const el of document.querySelectorAll("body *")) {
    if (![...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) continue;
    const style = getComputedStyle(el);
    const box = el.getBoundingClientRect();
    if (style.visibility === "hidden" || box.width === 0 || box.height === 0 || el.closest("[aria-hidden=true]") && style.opacity === "0") continue;
    if (el.closest(".skip") || el.closest(".hp")) continue;
    let opacity = 1;
    for (let e = el; e; e = e.parentElement) opacity *= +getComputedStyle(e).opacity;
    const bg = background(el);
    const fg = blend([...parse(style.color).slice(0, 3), parse(style.color)[3] * opacity], bg);
    const [a, b] = [lum(fg), lum(bg)];
    const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    const size = parseFloat(style.fontSize), bold = +style.fontWeight >= 700;
    const need = size >= 24 || (bold && size >= 18.66) ? 3 : 4.5;
    if (ratio < need) low.push({ text: el.textContent.trim().slice(0, 60), tag: el.tagName.toLowerCase(), cls: el.className.baseVal ?? el.className, ratio: +ratio.toFixed(2), need, color: style.color, background: `rgb(${bg.slice(0, 3).map(Math.round).join(", ")})` });
  }
  const wide = [...document.querySelectorAll("body *")].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.right > innerWidth + 1 && getComputedStyle(e).position !== "fixed"; })
    .filter((e) => !e.closest("pre") || e.tagName === "PRE").slice(0, 5).map((e) => `${e.tagName.toLowerCase()}.${e.className} right=${Math.round(e.getBoundingClientRect().right)}`);
  return { platform: document.documentElement.dataset.platform || null, scrollWidth: document.documentElement.scrollWidth, innerWidth, height: document.documentElement.scrollHeight, overflow: wide, low };
})()
"""


def serve():
    class Quiet(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                          ".webp": "image/webp", ".woff2": "font/woff2", ".svg": "image/svg+xml", ".js": "text/javascript"}

        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(SITE), **kwargs)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Quiet)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def snapshots(out):
    import base64
    out = Path(out)
    server = serve()  # in this process, so it stops with it
    base = f"http://127.0.0.1:{server.server_address[1]}"
    sizes = {"phone": (390, 844, True), "desktop": (1440, 900, False)}
    targets = []
    for lang, prefix, privacy in (("en", "/", "/privacy/"), ("pt-PT", "/pt/", "/pt/privacidade/")):
        for platform, hash_ in PLATFORM_HASHES.items():
            targets.append((lang, f"home-{platform}", prefix + hash_, platform))
        targets.append((lang, "privacy", privacy, None))
    chrome = Chrome()
    results = []
    try:
        for lang, name, path, platform in targets:
            (out / "snapshots" / lang).mkdir(parents=True, exist_ok=True)
            for size, (w, h, mobile) in sizes.items():
                for theme in ("light", "dark"):
                    chrome.send("Emulation.setDeviceMetricsOverride", session=True, width=w, height=h, deviceScaleFactor=1, mobile=mobile)
                    chrome.send("Emulation.setEmulatedMedia", session=True, features=[
                        {"name": "prefers-color-scheme", "value": theme},
                        # Still: the rise-in animation follows the scroll, and a full-page capture doesn't scroll.
                        {"name": "prefers-reduced-motion", "value": "reduce"}])
                    chrome.loaded = False
                    chrome.send("Page.navigate", session=True, url="about:blank")
                    chrome.wait_load()
                    chrome.loaded = False
                    chrome.send("Page.navigate", session=True, url=base + path)
                    chrome.wait_load()
                    chrome.evaluate(SETTLE)
                    measured = chrome.evaluate(MEASURE)
                    shot = chrome.send("Page.captureScreenshot", session=True, format="png", captureBeyondViewport=True,
                                       clip={"x": 0, "y": 0, "width": w, "height": measured["height"], "scale": 1})
                    file = out / "snapshots" / lang / f"{name}-{size}-{theme}.png"
                    file.write_bytes(base64.b64decode(shot["data"]))
                    results.append({"file": str(file.relative_to(out)), "lang": lang, "page": path, "expect": platform,
                                    "size": size, "theme": theme, **measured})
                    # The same page in pieces two screens tall, readable at full size (tiles/…-01.png, -02…).
                    tiles = out / "snapshots" / lang / "tiles"
                    tiles.mkdir(exist_ok=True)
                    step = 2 * h
                    for i, y in enumerate(range(0, measured["height"], step), 1):
                        piece = chrome.send("Page.captureScreenshot", session=True, format="png", captureBeyondViewport=True,
                                            clip={"x": 0, "y": y, "width": w, "height": min(step, measured["height"] - y), "scale": 1})
                        (tiles / f"{name}-{size}-{theme}-{i:02}.png").write_bytes(base64.b64decode(piece["data"]))
                    print(f"{file.relative_to(out)}  {w}×{measured['height']}, {i} tiles")
    finally:
        chrome.close()
        server.shutdown()
    (out / "render.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    for lang in ("en", "pt-PT"):
        count = len(list((out / "snapshots" / lang).glob("*.png")))
        if count != len(targets) // 2 * len(sizes) * 2:
            problem(lang, f"{count} snapshots")


def layout(out):
    results = json.loads((Path(out) / "render.json").read_text())
    for r in results:
        where = r["file"]
        if r["expect"] and r["platform"] != r["expect"]:
            problem(where, f"shows the {r['platform']} variant, not {r['expect']} (the switcher)")
        if r["scrollWidth"] > r["innerWidth"]:
            problem(where, f"scrolls sideways: {r['scrollWidth']} px wide in a {r['innerWidth']} px window ({'; '.join(r['overflow'])})")
        for low in r["low"]:
            problem(where, f"contrast {low['ratio']}:1 < {low['need']}:1 on <{low['tag']} class=\"{low['cls']}\"> {low['text']!r} ({low['color']} on {low['background']})")
    print(f"{len(results)} renders checked")


if __name__ == "__main__":
    gate = sys.argv[1] if len(sys.argv) > 1 else ""
    run = {"html": check_html, "links": check_links, "privacy": check_privacy, "seo": check_seo, "parity": check_parity}
    if gate in run:
        run[gate]()
    elif gate in ("snapshots", "layout") and len(sys.argv) == 3:
        (snapshots if gate == "snapshots" else layout)(sys.argv[2])
    else:
        sys.exit(__doc__)
    for p in problems:
        print(p)
    sys.exit(1 if problems else 0)

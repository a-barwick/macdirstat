#!/usr/bin/env python3
"""Checks docs site pages for what a script can catch.

Usage: check.py PAGE [PAGE ...] [--render]
       check.py --all [--render]

--render loads each page in headless Chrome at 1440 and 375 px, measures sideways scrolling, console
errors and diagram collisions, and saves screenshots. It needs Chrome or Chromium.
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(os.environ.get("DOCS_REPO") or Path(__file__).resolve().parents[4])
SITE = ROOT / "docs" / "site"
WORD_LIMIT = 800
WORD_TARGET = 600
LONG_PAGES = {"decisions", "sources", "words", "code", "open-questions"}
VISUALS = {"table", "svg", "img", "pre"}
VISUAL_CLASSES = {"flow", "states", "shots", "grid2", "grid3", "map", "trace", "seq"}
RAW = {"code", "pre", "script", "style", "svg"}
VOID = {"br", "hr", "img", "input", "link", "meta", "path", "circle", "rect", "line", "polygon"}
WIDTHS = (1440, 375)
BLOCKS = {"p", "li", "h1", "h2", "h3"}
INLINE = {"a", "b", "i", "em", "strong", "code", "span", "small", "br", "sub", "sup"}

PHRASES = [
    (r"—", "em dash"),
    (r";", "semicolon"),
    (r"\b(?:sits? on|lives? in|sits? behind)\b", "figure of speech"),
    (r"\b(?:gitignored|npm install|git clone|pip install|cargo install)\b", "instructions for contributors"),
    (r"\b[\w-]+, not (?:a |an |the )?[\w-]+", "'X, not Y' construction"),
    (r"\b(?:isn't|is not|aren't) [^.]{1,40}[,;] (?:it's|it is|they're)", "'isn't X, it's Y' construction"),
    (r"\b(?:real|actual) (?:work|question|point|problem)\b", "empty emphasis"),
    (r"\b(?:load-bearing|seamless\w*|robust\w*|leverag\w+|delve\w*|game-chang\w+|under the hood|the heart of|backbone)\b", "stock phrase"),
    (r"\b(?:this (?:section|page) (?:explains|describes|covers)|it's worth noting|in short|simply put)\b", "narration"),
    (r"\b(?:data buttons?|this site|these pages|the other pages|designed markings?|the readme (?:retains|keeps|holds))\b", "describes the site itself"),
]
PRAISE = r"\b(?:real|really|actual|actually|honest|honestly|true|truly|trust\w*|natural\w*|feels?|useful|meaningful\w*|powerful)\b"
SHORTHAND = r"\s(?:=|→|\+|≠)\s"
PERSON = r"\b(?:notices|knows|thinks|understands|decides|cares|feels|wants|remembers)\b"


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.text, self.prose, self.classes, self.links, self.order = [], [], [], set(), [], []
        self.title, self.heading_links, self.scripts, self.has_style = "", [], [], False
        self.block = None
        self.code, self.code_now, self.source_code = [], None, []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        cls = (attrs.get("class") or "").split()
        self.classes.update(cls)
        self.order.append((tag, cls))
        if tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])
            if any(t in ("h1", "h2", "h3") for t in self.stack):
                self.heading_links.append(attrs["href"])
        if tag == "script" and attrs.get("src"):
            self.scripts.append(attrs["src"])
        if tag == "style":
            self.has_style = True
        if tag == "details" and "sources" in cls:
            self.in_sources = True
        if tag == "code":
            self.code_now = []
        if tag not in VOID:
            self.stack.append(tag)
        if tag in BLOCKS and self.block is None:
            self.block = []
            self.kind = tag

    in_sources = False
    kind = "p"

    def handle_endtag(self, tag):
        if tag == "code" and self.code_now is not None:
            value = "".join(self.code_now).strip()
            (self.source_code if self.in_sources else self.code).append(value)
            self.code_now = None
        if tag == "details":
            self.in_sources = False
        if tag in self.stack:
            while self.stack.pop() != tag:
                pass
        if tag in BLOCKS and self.block is not None and tag not in self.stack:
            if not BLOCKS & set(self.stack):
                self.prose.append(("".join(self.block).strip(), self.kind))
                self.block = None

    def handle_data(self, data):
        if self.code_now is not None:
            self.code_now.append(data)
        if "head" in self.stack:
            if "title" in self.stack:
                self.title += data
            return
        if RAW & set(self.stack):
            if self.block is not None and "code" in self.stack:
                self.block.append("`code`")
            return
        self.text.append(data)
        if self.block is not None:
            self.block.append(data)


def config():
    source = (SITE / "site-config.js").read_text(encoding="utf-8")
    name = re.search(r"name:\s*['\"]([^'\"]+)", source)
    pages = re.findall(r"\[\s*['\"]([\w-]+)['\"]\s*,\s*['\"][^'\"]+['\"]\s*\]", source)
    return (name.group(1) if name else ""), pages


def known_classes():
    css = (SITE / "site.css").read_text(encoding="utf-8")
    js = (SITE / "site.js").read_text(encoding="utf-8")
    return set(re.findall(r"\.([a-zA-Z][\w-]*)", css)) | set(re.findall(r"class(?:Name)?=?[\"' ]+([\w-]+)", js))


def in_repo(token):
    """True if the text appears in tracked or untracked repo files outside the docs site and its tooling."""
    if not re.search(r"[*…<>{}]", token) and (ROOT / token).exists():
        return True
    tag = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{token}"], cwd=ROOT, capture_output=True)
    done = subprocess.run(["git", "grep", "-qIF", "--untracked", "-e", token, "--", ":!docs/site", ":!.agents", ":!.claude"],
                          cwd=ROOT, capture_output=True)
    return tag.returncode == 0 or done.returncode == 0


def path_exists(path):
    path = path.rstrip("/").split(":")[0].split("#")[0]
    return not re.search(r"[*…<>{}]", path) and (ROOT / path).exists()


HTTP_VERBS = {"POST", "PATCH", "DELETE", "HEAD"}
PATHISH = re.compile(r"^[\w.@-]+(?:/[\w.@*{}<>…-]+)+/?(?::\d+)?$")


def check_code_names(page, fails, warns):
    for path in page.source_code:
        if PATHISH.match(path) or re.match(r"^[\w.-]+\.\w+$", path) or path.endswith("/"):
            if not re.search(r"[*…<>{}]", path) and not path_exists(path):
                fails.append(f"source path doesn't exist in the repo: {path}")
    seen = set()
    for raw in page.code:
        for token in raw.split():
            token = token.strip("(),;:'\"`")
            if len(token) < 4 or token in seen or token in HTTP_VERBS or re.search(r"[…<>{}]", token):
                continue
            seen.add(token)
            if PATHISH.match(token):
                if not path_exists(token) and not in_repo(token):
                    warns.append(f"path isn't in the repo: {token}")
            elif re.search(r"[A-Za-z_]", token) and re.fullmatch(r"[\w./:@=-]+", token) and not in_repo(token):
                warns.append(f"code name isn't in the repo: {token}")


def visible_words(page):
    return len(" ".join(page.text).split())


def check(path, name, nav):
    fails, warns = [], []
    source = path.read_text(encoding="utf-8")
    page = Page()
    page.feed(source)
    stem = path.stem
    tags = [tag for tag, _ in page.order]

    for needed, label in (('href="site.css"', "site.css link"), ('src="site-config.js"', "site-config.js script"),
                          ('src="site.js"', "site.js script"), ('name="viewport"', "viewport meta")):
        if needed not in source:
            fails.append(f"missing {label}")
    if not page.title.endswith(f"· {name}"):
        fails.append(f"title must end with '· {name}'")
    if tags.count("h1") != 1:
        fails.append("page needs exactly one h1")
    if "lede" not in page.classes:
        fails.append("missing p.lede")
    if "sources" not in page.classes and stem not in LONG_PAGES and stem != "index":
        fails.append("missing details.sources")
    if stem not in nav:
        fails.append("page isn't in nav in site-config.js")
    if "{{" in source:
        fails.append("unfilled {{placeholder}}")

    # A visual must open the page: before the first section or at the top of it
    sections = [i for i, (tag, _) in enumerate(page.order) if tag == "section"]
    opening = page.order[:sections[1] if len(sections) > 1 else len(page.order)]
    if not any(tag in VISUALS or VISUAL_CLASSES & set(cls) for tag, cls in opening):
        fails.append("no visual before the second section")

    words = visible_words(page)
    for box in re.findall(r'class="node[^"]*">(.*?)</div>', source, re.S):
        text = re.sub(r"<[^>]+>", " ", box)
        if len(text.split()) > 28:
            warns.append(f"long diagram box, move detail below: {text.split()[0]} ...")
    if words > WORD_LIMIT and stem not in LONG_PAGES:
        fails.append(f"{words} words, over the {WORD_LIMIT} limit: split it by topic")
    elif words > WORD_TARGET and stem not in LONG_PAGES:
        warns.append(f"{words} words, over the {WORD_TARGET} target: cut what a reader can't act on")
    if [cls for tag, cls in page.order if tag == "details"].count(["more"]) > 1:
        warns.append("more than one details.more section")

    if page.heading_links:
        fails.append("heading contains a link: only the copy icon is interactive")
    for src in page.scripts:
        if src.startswith(("http:", "https:", "//")):
            fails.append(f"external script: {src}")
        elif not (SITE / src).exists():
            fails.append(f"missing script: {src}")
    if page.has_style:
        warns.append("inline <style>: use site.css classes")
    unknown = sorted(page.classes - known_classes())
    if unknown:
        fails.append(f"classes not in site.css or site.js: {', '.join(unknown)}")

    for link in page.links:
        target = link.split("#")[0]
        if link.startswith("/"):
            fails.append(f"use a relative link: {link}")
        elif target and not re.match(r"[a-z]+:", target) and not (SITE / target).exists():
            fails.append(f"broken link: {link}")

    if re.search(r"[\w.+-]+@[\w-]+\.\w+|\bsk-[A-Za-z0-9]{8,}|/Users/\w+|/home/\w+", source):
        fails.append("possible email address, API key or personal path")
    if re.search(r"\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b", source):
        fails.append("possible private network address")
    if re.search(r"[\w-]+\.(?:vercel\.app|netlify\.app|run\.app|fly\.dev|ngrok\.\w+)\b", source):
        warns.append("deploy or preview hostname: leave it out, because the site may be public")
    if stem in ("index", "system"):
        for flow in source.split('class="flow"')[1:]:
            labels = re.findall(r'class="node[^"]*">\s*<b>([^<]+)</b>', flow.split('class="card"')[0])
            repeated = sorted({label for label in labels if labels.count(label) > 1})
            if repeated:
                warns.append(f"{', '.join(repeated)} appears twice in a diagram: show each part once here, and put the sequence on the example page")

    check_code_names(page, fails, warns)

    run = 0
    for tag, _ in page.order:
        if tag in INLINE:
            continue
        run = run + 1 if tag == "p" else 0
        if run == 3:
            warns.append("three paragraphs in a row: use a list, a table or a diagram")

    for block, kind in page.prose:
        short = block if len(block) < 90 else block[:87] + "..."
        for pattern, label in PHRASES:
            if re.search(pattern, block, re.I):
                warns.append(f"{label}: {short}")
        if re.search(rf"\b{re.escape(name)} {PERSON}", block):
            warns.append(f"software described as a person: {short}")
        for match in re.findall(PRAISE, block, re.I):
            warns.append(f"check '{match}' states a fact: {short}")
        if re.search(SHORTHAND, block):
            warns.append(f"symbol used as shorthand: {short}")
        if len(re.findall(r"[.!?](?:\s|$)", block)) > (2 if kind == "p" else 3):
            warns.append(f"long paragraph, use a list or split it: {short}")
    return words, fails, warns


def find_chrome():
    for candidate in ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                      "/Applications/Chromium.app/Contents/MacOS/Chromium",
                      shutil.which("google-chrome"), shutil.which("chromium"), shutil.which("chromium-browser"), shutil.which("chrome")):
        if candidate and Path(candidate).exists():
            return candidate
    return None


class Renderer:
    """Chrome won't open a window narrower than 500 px, so the phone width loads the page in a 375 px iframe."""

    def __init__(self):
        self.chrome = find_chrome()
        self.out = Path(tempfile.gettempdir()) / "docs-shots" / ROOT.name
        self.problem = None if self.chrome else "no Chrome or Chromium found"

    def run(self, url, width, height, extra):
        profile = tempfile.mkdtemp(prefix="docs-chrome-")
        try:
            return subprocess.run([self.chrome, "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars",
                                   f"--user-data-dir={profile}", f"--window-size={width},{height}", "--virtual-time-budget=4000", *extra, url],
                                  capture_output=True, text=True, timeout=60)
        finally:
            shutil.rmtree(profile, ignore_errors=True)

    def frame(self, url, width, height, name):
        """Writes a page that shows the url in an iframe and copies its audit into its own meta tag."""
        wrapper = self.out / f"{name}-{width}.frame.html"
        wrapper.write_text(f"""<!doctype html><meta charset="utf-8"><body style="margin:0;background:#888">
<iframe src="{url}" width="{width}" height="{height}" style="border:0;display:block;background:#fff"></iframe>
<script>addEventListener('message', e => {{ const m = document.createElement('meta'); m.name = 'docs-audit'; m.content = e.data; document.head.append(m); }});</script>""", encoding="utf-8")
        return wrapper.as_uri()

    def audit(self, url, width, stem):
        target = f"{url}?audit"
        if width >= 500:
            done = self.run(target, width, 1000, ["--dump-dom"])
        else:
            done = self.run(self.frame(target, width, 1000, stem), 500, 1000, ["--dump-dom"])
        if not done.stdout.strip():
            self.problem = "Chrome started but returned no page, which usually means a sandbox blocked it"
            return None
        found = re.search(r'<meta name="docs-audit" content="([^"]*)"', done.stdout)
        return json.loads(html.unescape(found.group(1))) if found else {}

    def shoot(self, url, width, height, path):
        height = min(max(height, 400), 9000)
        if width >= 500:
            self.run(url, width, height, [f"--screenshot={path}"])
        else:
            self.run(self.frame(url, width, height, path.stem), 500, height, [f"--screenshot={path}"])

    def render(self, path, fails, warns):
        """Adds findings for one page, and returns the screenshot paths."""
        if self.problem:
            return []
        self.out.mkdir(parents=True, exist_ok=True)
        shots = []
        url = path.resolve().as_uri()
        for width in WIDTHS:
            try:
                audit = self.audit(url, width, path.stem)
                if audit is None:
                    return shots
                if not audit:
                    fails.append(f"{width}px: site.js didn't finish, so the page has a script error")
                    continue
                if audit["width"] != width:
                    warns.append(f"{width}px: rendered at {audit['width']}px instead")
                over = audit["scrollWidth"] - audit["width"]
                if over > 1:
                    fails.append(f"{width}px: scrolls sideways by {over}px: {', '.join(audit['wide']) or 'see the screenshot'}")
                for error in audit["errors"]:
                    fails.append(f"{width}px: page error: {error}")
                for image in audit["brokenImages"]:
                    fails.append(f"{width}px: broken image: {image}")
                for issue in audit["diagrams"]:
                    warns.append(f"{width}px diagram: {issue}")
                shot = self.out / f"{path.stem}-{width}.png"
                self.shoot(url, width, audit["height"], shot)
                if shot.exists():
                    shots.append(str(shot))
            except (subprocess.TimeoutExpired, OSError) as error:
                self.problem = f"Chrome didn't run: {error}"
                return shots
        return shots


def check_site(nav):
    fails = []
    for page in nav:
        if not (SITE / f"{page}.html").exists():
            fails.append(f"nav lists {page} but {page}.html doesn't exist")
    for filename in ("AGENTS.md", "site-config.js"):
        if "{{" in (SITE / filename).read_text(encoding="utf-8"):
            fails.append(f"{filename} still has unfilled {{{{placeholders}}}}")
    if "index" not in nav:
        fails.append("nav has no index page")
    if "words" not in nav:
        fails.append("nav has no words page")
    for script in SITE.glob("*.js"):
        if script.name in ("site.js", "site-config.js"):
            continue
        for source in re.findall(r"""['"]?source['"]?\s*:\s*['"]([^'"]+)['"]""", script.read_text(encoding="utf-8")):
            if not path_exists(source.split(",")[0].strip()):
                fails.append(f"{script.name}: source doesn't exist in the repo: {source}")
    return fails


def main(argv):
    render = "--render" in argv
    argv = [a for a in argv if a != "--render"]
    if not argv:
        print(__doc__)
        return 2
    name, nav = config()
    every = argv == ["--all"]
    paths = sorted(SITE.glob("*.html")) if every else [Path(a) for a in argv]
    renderer = Renderer() if render else None
    failed = False
    if every:
        for line in check_site(nav):
            print(f"site: FAIL {line}")
            failed = True
    total = 0
    for path in paths:
        if not path.exists():
            print(f"{path}: not found")
            failed = True
            continue
        words, fails, warns = check(path.resolve(), name, nav)
        total += words
        shots = renderer.render(path, fails, warns) if renderer else []
        print(f"{path.name}: {words} words, {len(fails)} fail, {len(warns)} warn")
        for line in fails:
            print(f"  FAIL {line}")
        for line in warns:
            print(f"  WARN {line}")
        for shot in shots:
            print(f"  SHOT {shot}")
        failed = failed or bool(fails)
    if every:
        print(f"site: {len(paths)} pages, {total} words")
    if renderer and renderer.problem:
        print(f"RENDER NOT DONE: {renderer.problem}. Ask to run this command outside the sandbox. If you can't, say so in your report, and don't claim you viewed the pages.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Insert the Ludo Royale snippets into copies of the studio site's pages.

Usage:
  python3 apply_snippets.py INDEX_HTML SITEMAP_XML [--footer-page PAGE ...]
                           [--keep-more-card-full-width] [--dry-run]

INDEX_HTML  a copy of the site's index.html. Gets the Ludo Royale game card after the
            Brain Train card, and the Ludo Royale links after the Brain Train links in
            the footer's Games and Legal lists. With three game cards in the two-column
            grid, the "More on the way" card is moved into the free cell next to the
            third card (style="grid-column: auto" on <div class="more-card">), so the
            grid has no hole.
SITEMAP_XML a copy of the site's sitemap.xml. Gets snippets/sitemap-entries.xml before
            </urlset>.
--footer-page PAGE
            another page with the standard site footer (brain-train.html,
            king-teen-patti.html, terms.html, 404.html, brain-train/privacy/index.html, ...).
            Gets only the footer links. Repeat for each page.
--keep-more-card-full-width
            leave the "More on the way" card as it is (full width below the cards).
--dry-run   check everything and report, but write nothing.

The script is all-or-nothing: it refuses (exit 1, nothing written) if any anchor is
missing or ambiguous, or if a file already mentions Ludo Royale. Run it on copies,
check the result, then deploy the copies (see README.md).
"""

import argparse
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SNIPPETS = os.path.join(HERE, "snippets")

# The Brain Train game card on the homepage: <article class="game-card"> ... href="/brain-train" ... </article>
CARD_ANCHOR = re.compile(
    r'[ \t]*<article class="game-card">(?:(?!</article>).)*?href="/brain-train"(?:(?!</article>).)*?</article>[ \t]*\r?\n',
    re.S,
)
GAMES_LI_ANCHOR = re.compile(
    r'^[ \t]*<li><a href="/brain-train"(?: aria-current="page")?>Brain Train</a></li>[ \t]*\r?\n', re.M
)
LEGAL_LI_ANCHOR = re.compile(
    r'^[ \t]*<li><a href="/brain-train/privacy/"(?: aria-current="page")?>Brain Train Privacy Policy</a></li>[ \t]*\r?\n',
    re.M,
)
URLSET_END = re.compile(r"^</urlset>", re.M)
MORE_CARD = re.compile(r'<div class="more-card">')
MORE_CARD_BESIDE = '<div class="more-card" style="grid-column: auto">'
ALREADY_HTML = re.compile(r'href="/ludo-royale[/"]')


class Refused(Exception):
    pass


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def snippet(name):
    return read(os.path.join(SNIPPETS, name))


def insert_after(text, pattern, insert, what, path):
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise Refused(f"{path}: expected exactly one {what}, found {len(matches)}")
    end = matches[0].end()
    line = text.count("\n", 0, end) + 1
    return text[:end] + insert + text[end:], line


def insert_before(text, pattern, insert, what, path):
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise Refused(f"{path}: expected exactly one {what}, found {len(matches)}")
    start = matches[0].start()
    line = text.count("\n", 0, start) + 1
    return text[:start] + insert + text[start:], line


def footer_links(text, path, report):
    text, line = insert_after(text, GAMES_LI_ANCHOR, snippet("footer-games-link.html"), "footer Games <li> for Brain Train", path)
    report.append(f"{path}: footer Games link inserted at line {line}")
    text, line = insert_after(text, LEGAL_LI_ANCHOR, snippet("footer-legal-link.html"), "footer Legal <li> for Brain Train Privacy Policy", path)
    report.append(f"{path}: footer Legal link inserted at line {line}")
    return text


def plan(args):
    report, out = [], {}

    index = read(args.index)
    if ALREADY_HTML.search(index):
        raise Refused(f"{args.index}: already links to /ludo-royale; nothing to do")
    index, line = insert_after(index, CARD_ANCHOR, snippet("index-games-card.html"), "Brain Train game card", args.index)
    report.append(f"{args.index}: game card inserted at line {line}")
    if not args.keep_more_card_full_width:
        found = list(MORE_CARD.finditer(index))
        if len(found) != 1:
            raise Refused(f'{args.index}: expected exactly one <div class="more-card">, found {len(found)}')
        line = index.count("\n", 0, found[0].start()) + 1
        index = index[: found[0].start()] + MORE_CARD_BESIDE + index[found[0].end():]
        report.append(f"{args.index}: \"More on the way\" card set beside the third game card (line {line})")
    out[args.index] = footer_links(index, args.index, report)

    sitemap = read(args.sitemap)
    if "/ludo-royale" in sitemap:
        raise Refused(f"{args.sitemap}: already lists /ludo-royale; nothing to do")
    out[args.sitemap], line = insert_before(sitemap, URLSET_END, snippet("sitemap-entries.xml"), "</urlset>", args.sitemap)
    report.append(f"{args.sitemap}: entries inserted at line {line}")

    for page in args.footer_page:
        if page in out:
            raise Refused(f"{page}: given twice")
        text = read(page)
        if ALREADY_HTML.search(text):
            raise Refused(f"{page}: already links to /ludo-royale; nothing to do")
        out[page] = footer_links(text, page, report)
    return out, report


def write_atomic(path, text):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".apply-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("index")
    parser.add_argument("sitemap")
    parser.add_argument("--footer-page", action="append", default=[], metavar="PAGE")
    parser.add_argument("--keep-more-card-full-width", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        out, report = plan(args)
    except (Refused, OSError) as e:
        print(f"refused: {e}", file=sys.stderr)
        print("nothing was written", file=sys.stderr)
        return 1
    for line in report:
        print(line)
    if args.dry_run:
        print("dry run: nothing was written")
        return 0
    for path, text in out.items():
        write_atomic(path, text)
    print(f"wrote {len(out)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

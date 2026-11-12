#!/usr/bin/env python3
"""Post the current release's notes to Discord.

    python Tools/announce.py --dry-run     print the post, send nothing
    DISCORD_WEBHOOK=... python Tools/announce.py

The notes are the newest entry in Core/Changelog.lua, the same lines the
Toolbox card, CHANGELOG.md and the release pages show. That entry must be the
version in Lattice.toc, or nothing is sent.

The release workflow runs this when `publish` is ticked. The webhook is the
DISCORD_WEBHOOK secret and is never written into the repo: anyone holding it
can post to the channel.
"""

import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bump  # noqa: E402


# Joe's wording. Public text: change it with him, not for him.
HEADING = "**Lattice %(version)s - %(date)s is out**"
FOOTER = [
    "CurseForge, Wago and WoWInterface can take a while to approve and publish"
    " a new version. If you can't wait, grab it from GitHub:"
    " <https://github.com/drveoj/Lattice/releases/tag/v%(version)s>",
    "",
    "Found a bug? Type /lattice errors in game, copy what it shows and post it"
    " in <#1539206693756604466>.",
]


def message() -> str:
    cur = "%d.%d.%d" % bump.read_version()
    entries = bump.read_entries()
    if not entries or entries[0][0] != cur:
        sys.exit("announce: the newest changelog entry is not %s" % cur)
    version, date, lines = entries[0]
    fill = {"version": version, "date": date}
    text = "\n".join([HEADING % fill, ""] + ["- " + ln for ln in lines]
                     + [""] + [ln % fill for ln in FOOTER])
    if len(text) > 2000:  # Discord's limit for one message
        sys.exit("announce: the post is %d characters, over Discord's 2000" % len(text))
    return text


def send(url: str, text: str) -> None:
    body = json.dumps({
        "content": text,
        # No pings, whatever the notes happen to contain.
        "allowed_mentions": {"parse": []},
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "User-Agent": "Lattice-release",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status >= 300:
            sys.exit("announce: Discord answered %d" % resp.status)


def main() -> None:
    ap = argparse.ArgumentParser(description="Post the release notes to Discord.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    text = message()
    if args.dry_run:
        print(text)
        return

    # Missing is an error. An empty secret reads as "", and a step that skipped
    # quietly would go green having announced nothing.
    url = os.environ.get("DISCORD_WEBHOOK", "").strip()
    if not url:
        sys.exit("announce: DISCORD_WEBHOOK is not set")
    send(url, text)
    print("announce: posted Lattice %d.%d.%d" % bump.read_version())


if __name__ == "__main__":
    main()

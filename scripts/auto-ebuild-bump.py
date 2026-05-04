#!/usr/bin/env python3
"""
scripts/auto-ebuild-bump.py

Scan all packages in this overlay for upstream GitHub releases/tags and
copy the highest local ebuild to the new upstream version when an update is
detected.

Environment variables:
  GITHUB_TOKEN           – optional; raises API rate limit to 5 000 req/h
  BUMPED_PACKAGES_FILE   – path to write bumped package dirs (one per line);
                           default: /tmp/bumped_packages.txt

Usage:
  python3 scripts/auto-ebuild-bump.py
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

GITHUB_API = "https://api.github.com"
OVERLAY_DIR = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

def log(msg):   print(f"[bump] {msg}", flush=True)
def info(msg):  print(f"[bump]   {msg}", flush=True)
def skip(msg):  print(f"[bump]   SKIP  {msg}", flush=True)
def ok(msg):    print(f"[bump]   OK    {msg}", flush=True)
def bump(msg):  print(f"[bump]   BUMP  {msg}", flush=True)
def err(msg):   print(f"[bump]   ERROR {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# GitHub API helper
# ---------------------------------------------------------------------------

def github_get(url: str, token: str) -> dict | list:
    """Fetch *url* from the GitHub API and return the parsed JSON object."""
    headers = {"Accept": "application/vnd.github.v3+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


# ---------------------------------------------------------------------------
# Package discovery
# ---------------------------------------------------------------------------

def find_packages(overlay_dir: Path) -> list[Path]:
    """Return sorted unique package dirs (category/pkg/) that contain ebuilds."""
    dirs = {p.parent for p in overlay_dir.glob("*/*/*.ebuild")
            if ".git" not in p.parts}
    return sorted(dirs)


# ---------------------------------------------------------------------------
# Ebuild content helpers
# ---------------------------------------------------------------------------

def extract_github_repo(text: str) -> str:
    """Return the first 'owner/repo' slug found in *text*, or ''."""
    m = re.search(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)', text)
    if not m:
        return ""
    return re.sub(r'\.git$', '', m.group(1))


def detect_flags(content: str) -> tuple[bool, bool]:
    """
    Return (has_v_prefix, prefer_releases).

    has_v_prefix   – SRC_URI contains the literal token v${PV}
    prefer_releases – SRC_URI contains /releases/download/
    """
    has_v_prefix = 'v${PV}' in content
    prefer_releases = '/releases/download/' in content
    return has_v_prefix, prefer_releases


# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

_PRERELEASE_RE = re.compile(r'(rc|beta|alpha|pre|preview)([._-]?\d*|$)', re.I)


def _version_key(v: str) -> list:
    """Numeric sort key: split on [._-], convert digits to int, others to 0."""
    return [int(x) if x.isdigit() else 0
            for x in re.split(r'[._-]', v.lstrip('v'))]


def version_gt(v1: str, v2: str) -> bool:
    """Return True when v1 is strictly newer than v2."""
    return v1 != v2 and _version_key(v1) > _version_key(v2)


# ---------------------------------------------------------------------------
# Upstream version resolution
# ---------------------------------------------------------------------------

def latest_release(repo: str, token: str) -> str:
    """
    Query /releases/latest for *repo*.
    Return the tag name if it is not a pre-release, otherwise ''.
    """
    url = f"{GITHUB_API}/repos/{repo}/releases/latest"
    try:
        data = github_get(url, token)
    except urllib.error.HTTPError:
        return ""
    if data.get("prerelease"):
        return ""
    return data.get("tag_name", "")


def latest_stable_tag(repo: str, token: str) -> str:
    """
    Query /tags for *repo* and return the highest stable tag name.
    Stable = no rc/beta/alpha/pre/preview substring.
    Falls back to all tags when no stable tags exist.
    """
    url = f"{GITHUB_API}/repos/{repo}/tags?per_page=100"
    try:
        tags = github_get(url, token)
    except urllib.error.HTTPError:
        return ""
    names = [t["name"] for t in tags]
    stable = [n for n in names if not _PRERELEASE_RE.search(n)]
    if not stable:
        stable = names  # no stable → accept all
    if not stable:
        return ""
    stable.sort(key=_version_key, reverse=True)
    return stable[0]


# ---------------------------------------------------------------------------
# Per-package processing
# ---------------------------------------------------------------------------

def process_package(pkg_dir: Path, token: str, bumped_file: str) -> None:
    pkg_name = pkg_dir.name
    rel_path = pkg_dir.relative_to(OVERLAY_DIR)

    # ---- Find the highest-versioned ebuild ----------------------------------
    ebuilds = sorted(pkg_dir.glob(f"{pkg_name}-*.ebuild"), key=lambda p: _version_key(p.stem[len(pkg_name) + 1:]))
    if not ebuilds:
        return
    latest_ebuild = ebuilds[-1]
    current_pv = latest_ebuild.stem[len(pkg_name) + 1:]

    log(f"{rel_path}  (current: {current_pv})")

    # ---- Read HOMEPAGE and SRC_URI ------------------------------------------
    content = latest_ebuild.read_text(errors="replace")
    homepage_line = "\n".join(l for l in content.splitlines() if re.search(r'HOMEPAGE\s*=', l, re.I))
    src_uri_line  = "\n".join(l for l in content.splitlines() if re.search(r'SRC_URI\s*=',  l, re.I))

    # ---- Locate upstream GitHub repo (HOMEPAGE first, SRC_URI second) -------
    github_repo = extract_github_repo(homepage_line) or extract_github_repo(src_uri_line)
    if not github_repo:
        skip(f"no GitHub upstream for {pkg_name}")
        return
    info(f"upstream: {github_repo}")

    # ---- Detect v-prefix and release-preference flags -----------------------
    has_v_prefix, prefer_releases = detect_flags(content)

    # ---- Fetch upstream version ---------------------------------------------
    upstream_tag = ""

    if prefer_releases:
        info("querying releases/latest …")
        upstream_tag = latest_release(github_repo, token)

    if not upstream_tag:
        info("querying tags …")
        upstream_tag = latest_stable_tag(github_repo, token)

    if not upstream_tag:
        skip(f"could not determine upstream version for {pkg_name}")
        return

    # ---- Convert tag → Gentoo PV (strip leading 'v' when expected) ----------
    upstream_pv = upstream_tag
    if has_v_prefix and upstream_tag.startswith("v"):
        upstream_pv = upstream_tag[1:]
    info(f"upstream tag: {upstream_tag}  →  PV: {upstream_pv}")

    # ---- Compare versions ---------------------------------------------------
    if not version_gt(upstream_pv, current_pv):
        ok(f"{pkg_name} is already at {current_pv} (upstream: {upstream_pv})")
        return

    # ---- Bump: copy ebuild to new version -----------------------------------
    new_ebuild = pkg_dir / f"{pkg_name}-{upstream_pv}.ebuild"
    bump(f"{pkg_name}: {current_pv} → {upstream_pv}")
    import shutil
    shutil.copy2(latest_ebuild, new_ebuild)
    with open(bumped_file, "a") as fh:
        fh.write(str(pkg_dir) + "\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    token = os.environ.get("GITHUB_TOKEN", "")
    bumped_file = os.environ.get("BUMPED_PACKAGES_FILE", "/tmp/bumped_packages.txt")

    # Remove stale bumped-packages file
    try:
        os.remove(bumped_file)
    except FileNotFoundError:
        pass

    packages = find_packages(OVERLAY_DIR)
    if not packages:
        log(f"No ebuilds found under {OVERLAY_DIR}.")
        return

    for pkg_dir in packages:
        try:
            process_package(pkg_dir, token, bumped_file)
        except Exception as exc:
            err(f"failed processing {pkg_dir}: {exc}")

    print()
    if os.path.isfile(bumped_file):
        log("Packages bumped:")
        with open(bumped_file) as fh:
            for line in fh:
                d = Path(line.strip())
                log(f"  {d.relative_to(OVERLAY_DIR)}")
    else:
        log("All packages are up to date – nothing to bump.")


if __name__ == "__main__":
    main()

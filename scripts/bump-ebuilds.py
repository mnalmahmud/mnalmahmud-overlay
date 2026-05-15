#!/usr/bin/env python3
"""
scripts/auto-ebuild-bump.py

Scan all packages in this overlay for upstream releases/tags and copy the
highest local ebuild to the new upstream version when an update is detected.

Supported upstream sources
  • GitHub   (github.com)
  • GitLab   (gitlab.com)
  • AUR      (aur.archlinux.org)
  • Debian   (packages.debian.org / tracker.debian.org)

Environment variables:
  GITHUB_TOKEN           – optional; raises GitHub API rate limit to 5 000 req/h
  GITLAB_TOKEN           – optional; raises GitLab API rate limit
  BUMPED_PACKAGES_FILE   – path to write bumped package dirs (one per line);
                           default: /tmp/bumped_packages.txt

Usage:
  python3 scripts/auto-ebuild-bump.py
"""

import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

GITHUB_API = "https://api.github.com"
GITLAB_API = "https://gitlab.com/api/v4"
OVERLAY_DIR = Path(__file__).resolve().parent.parent

def log(msg):   print(f"[bump] {msg}", flush=True)
def info(msg):  print(f"[bump]   INFO  {msg}", flush=True)
def skip(msg):  print(f"[bump]   SKIP  {msg}", flush=True)
def ok(msg):    print(f"[bump]   OK    {msg}", flush=True)
def bump(msg):  print(f"[bump]   BUMP  {msg}", flush=True)
def err(msg):   print(f"[bump]   ERROR {msg}", file=sys.stderr, flush=True)

def http_get_json(url: str) -> dict | list:
    """Fetch *url* with a plain GET and return the parsed JSON (no auth)."""
    req = urllib.request.Request(url, headers={"User-Agent": "auto-ebuild-bump/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def github_get(url: str, token: str) -> dict | list:
    """Fetch *url* from the GitHub API and return the parsed JSON object."""
    headers = {"Accept": "application/vnd.github.v3+json",
               "User-Agent": "auto-ebuild-bump/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def gitlab_get(url: str, token: str) -> dict | list:
    """Fetch *url* from the GitLab API and return the parsed JSON object."""
    headers = {"Accept": "application/json",
               "User-Agent": "auto-ebuild-bump/1.0"}
    if token:
        headers["PRIVATE-TOKEN"] = token
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def find_packages(overlay_dir: Path) -> list[Path]:
    """Return sorted unique package dirs (category/pkg/) that contain ebuilds."""
    dirs = {p.parent for p in overlay_dir.glob("*/*/*.ebuild")
            if ".git" not in p.parts}
    return sorted(dirs)


def extract_github_repo(text: str) -> str:
    """Return the first 'owner/repo' slug found in a github.com URL, or ''."""
    m = re.search(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)', text)
    if not m:
        return ""
    return re.sub(r'\.git$', '', m.group(1))


def extract_gitlab_repo(text: str) -> str:
    """Return the first 'namespace/project' slug found in a gitlab.com URL, or ''."""
    m = re.search(r'https://gitlab\.com/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)', text)
    if not m:
        return ""
    parts = m.group(1).split('/')
    slug = '/'.join(parts[:2])
    return re.sub(r'\.git$', '', slug)


def extract_aur_package(text: str) -> str:
    """Return the AUR package name from an aur.archlinux.org URL, or ''."""
    m = re.search(r'https://aur\.archlinux\.org/(?:packages|pkgbase)/([A-Za-z0-9_@+.-]+)', text)
    return m.group(1) if m else ""


def extract_debian_package(text: str) -> str:
    """Return the package name from a packages.debian.org or tracker.debian.org URL, or ''."""
    m = re.search(
        r'https://(?:packages\.debian\.org/(?:[a-z]+/)?|tracker\.debian\.org/pkg/)([A-Za-z0-9.+_-]+)',
        text,
    )
    return m.group(1) if m else ""


def detect_upstream(homepage: str, src_uri: str) -> tuple[str, str]:
    """
    Return (source_type, identifier) for the first recognised upstream.

    source_type is one of 'github', 'gitlab', 'aur', 'debian', or ''.
    identifier is the owner/repo slug, package name, etc.
    """
    gh = extract_github_repo(homepage) or extract_github_repo(src_uri)
    if gh:
        return ("github", gh)
    gl = extract_gitlab_repo(homepage) or extract_gitlab_repo(src_uri)
    if gl:
        return ("gitlab", gl)
    aur = extract_aur_package(homepage)
    if aur:
        return ("aur", aur)
    deb = extract_debian_package(homepage)
    if deb:
        return ("debian", deb)
    return ("", "")


def detect_flags(src_uri: str) -> tuple[bool, bool]:
    """
    Return (has_v_prefix, prefer_releases) by inspecting the SRC_URI value.

    has_v_prefix    – SRC_URI contains the literal token v${PV}
    prefer_releases – SRC_URI uses a releases download URL (GitHub or GitLab)

    Accepts the already-extracted SRC_URI line(s) rather than the full ebuild
    content so that comments elsewhere in the file cannot produce false positives.
    """
    has_v_prefix = 'v${PV}' in src_uri
    prefer_releases = '/releases/download/' in src_uri or '/-/releases/' in src_uri
    return has_v_prefix, prefer_releases


# Matches a pre-release keyword only when it is NOT embedded inside a longer word
# (e.g. "prebuilt" or "comprehensive" must not be caught).
# Lookahead/lookbehind require the keyword to be bordered by a non-alpha character
# or start/end of string on each side.
_PRERELEASE_RE = re.compile(r'(?<![a-zA-Z])(rc|beta|alpha|pre|preview)(?![a-zA-Z])', re.I)


def _version_key(v: str) -> list:
    """Numeric sort key: split on [._-], convert digits to int, others to 0."""
    return [int(x) if x.isdigit() else 0
            for x in re.split(r'[._-]', v.lstrip('v'))]


def version_gt(v1: str, v2: str) -> bool:
    """Return True when v1 is strictly newer than v2."""
    return v1 != v2 and _version_key(v1) > _version_key(v2)


def latest_github_release(repo: str, token: str) -> str:
    """
    Query /releases/latest for *repo*.
    Return the tag name if it is not a pre-release, otherwise ''.
    """
    url = f"{GITHUB_API}/repos/{repo}/releases/latest"
    try:
        data = github_get(url, token)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""
    if data.get("prerelease"):
        return ""
    return data.get("tag_name", "")


def latest_github_stable_tag(repo: str, token: str) -> str:
    """
    Query /tags for *repo* and return the highest stable tag name.
    Stable = no rc/beta/alpha/pre/preview substring.
    Falls back to all tags when no stable tags exist.
    """
    url = f"{GITHUB_API}/repos/{repo}/tags?per_page=100"
    try:
        tags = github_get(url, token)
    except (urllib.error.HTTPError, urllib.error.URLError):
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
# Upstream version resolution — GitLab
# ---------------------------------------------------------------------------

def latest_gitlab_release(repo: str, token: str) -> str:
    """
    Return the tag name of the latest non-upcoming, non-prerelease GitLab
    release for *repo* (namespace/project), or ''.
    """
    encoded = urllib.parse.quote(repo, safe="")
    url = f"{GITLAB_API}/projects/{encoded}/releases?per_page=20"
    try:
        releases = gitlab_get(url, token)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""
    for rel in releases:
        tag = rel.get("tag_name", "")
        if not rel.get("upcoming_release") and not _PRERELEASE_RE.search(tag):
            return tag
    return ""


def latest_gitlab_tag(repo: str, token: str) -> str:
    """
    Return the highest stable tag name for *repo* on GitLab, or ''.
    """
    encoded = urllib.parse.quote(repo, safe="")
    url = f"{GITLAB_API}/projects/{encoded}/repository/tags?per_page=100&order_by=version"
    try:
        tags = gitlab_get(url, token)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""
    names = [t["name"] for t in tags]
    stable = [n for n in names if not _PRERELEASE_RE.search(n)]
    if not stable:
        stable = names
    if not stable:
        return ""
    stable.sort(key=_version_key, reverse=True)
    return stable[0]


def parse_aur_version(aur_version: str) -> str:
    """
    Convert an AUR Version string (e.g. '2:1.2.3-1') to a Gentoo-compatible PV.
    Strips the epoch prefix and pkgrel suffix.
    """
    v = re.sub(r"^\d+:", "", aur_version)   # strip epoch  (e.g. "2:")
    v = re.sub(r"-\d+$", "", v)             # strip pkgrel (e.g. "-1")
    return v


def latest_aur_version(pkg: str) -> str:
    """Return the latest version of an AUR package as a Gentoo PV, or ''."""
    url = f"https://aur.archlinux.org/rpc/v5/info?arg[]={urllib.parse.quote(pkg)}"
    try:
        data = http_get_json(url)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""
    results = data.get("results", [])
    if not results:
        return ""
    raw = results[0].get("Version", "")
    return parse_aur_version(raw) if raw else ""


def parse_debian_upstream_version(deb_version: str) -> str:
    """
    Convert a Debian version string to the upstream (Gentoo-compatible) version.
    Strips epoch, Debian revision, and common repacking suffixes.

    Examples:
      '2:1.2.3-4'       → '1.2.3'
      '1.2.3+dfsg-4'    → '1.2.3'
      '1.2.3~beta1-1'   → '1.2.3'
    """
    v = re.sub(r"^\d+:", "", deb_version)    # strip epoch
    v = re.sub(r"-\d+[a-z0-9.]*$", "", v)   # strip Debian revision
    v = re.sub(r"[+~][a-z].*$", "", v)       # strip repack/tilde suffix
    return v


def latest_debian_version(pkg: str) -> str:
    """
    Return the latest upstream version of a Debian source package from
    sid (unstable), or '' on failure.
    """
    url = f"https://sources.debian.org/api/src/{urllib.parse.quote(pkg)}/"
    try:
        data = http_get_json(url)
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""
    versions = data.get("versions", [])
    # Prefer versions tagged for sid (unstable), otherwise take any available
    sid = [v["version"] for v in versions if "sid" in v.get("suites", [])]
    candidates = sid or [v["version"] for v in versions]
    if not candidates:
        return ""
    candidates.sort(key=_version_key, reverse=True)
    return parse_debian_upstream_version(candidates[0])


def process_package(pkg_dir: Path, github_token: str, gitlab_token: str, bumped_file: str) -> None:
    pkg_name = pkg_dir.name
    rel_path = pkg_dir.relative_to(OVERLAY_DIR)

    ebuilds = sorted(pkg_dir.glob(f"{pkg_name}-*.ebuild"), key=lambda p: _version_key(p.stem[len(pkg_name) + 1:]))
    if not ebuilds:
        return
    latest_ebuild = ebuilds[-1]
    current_pv = latest_ebuild.stem[len(pkg_name) + 1:]

    log(f"{rel_path}  (current: {current_pv})")

    content = latest_ebuild.read_text(errors="replace")
    homepage_line = "\n".join(l for l in content.splitlines() if re.search(r'HOMEPAGE\s*=', l, re.I))
    src_uri_line  = "\n".join(l for l in content.splitlines() if re.search(r'SRC_URI\s*=',  l, re.I))

    source_type, upstream_id = detect_upstream(homepage_line, src_uri_line)
    if not source_type:
        skip(f"no supported upstream for {pkg_name}")
        return
    info(f"upstream: {source_type}:{upstream_id}")

    upstream_tag = ""
    upstream_pv  = ""
    has_v_prefix = False

    match source_type:
        case "github":
            has_v_prefix, prefer_releases = detect_flags(src_uri_line)
            if prefer_releases:
                info("querying GitHub releases/latest …")
                upstream_tag = latest_github_release(upstream_id, github_token)
            if not upstream_tag:
                info("querying GitHub tags …")
                upstream_tag = latest_github_stable_tag(upstream_id, github_token)

        case "gitlab":
            has_v_prefix, prefer_releases = detect_flags(src_uri_line)
            if prefer_releases:
                info("querying GitLab releases …")
                upstream_tag = latest_gitlab_release(upstream_id, gitlab_token)
            if not upstream_tag:
                info("querying GitLab tags …")
                upstream_tag = latest_gitlab_tag(upstream_id, gitlab_token)

        case "aur":
            info("querying AUR …")
            upstream_tag = latest_aur_version(upstream_id)

        case "debian":
            info("querying Debian tracker …")
            upstream_tag = latest_debian_version(upstream_id)

        case _:
            skip(f"Unknown source type: {source_type}")
            return

    if not upstream_tag:
        skip(f"could not determine upstream version for {pkg_name}")
        return

    upstream_pv = upstream_tag.removeprefix("v") if has_v_prefix else upstream_tag

    info(f"upstream tag: {upstream_tag}  →  PV: {upstream_pv}")

    if not version_gt(upstream_pv, current_pv):
        ok(f"{pkg_name} is already at {current_pv} (upstream: {upstream_pv})")
        return

    new_ebuild = pkg_dir / f"{pkg_name}-{upstream_pv}.ebuild"
    if new_ebuild.exists():
        skip(f"{new_ebuild.name} already exists – not overwriting")
        return
    bump(f"{pkg_name}: {current_pv} → {upstream_pv}")
    shutil.copy2(latest_ebuild, new_ebuild)
    with open(bumped_file, "a") as fh:
        fh.write(str(pkg_dir) + "\n")


def main() -> None:
    github_token = os.environ.get("GITHUB_TOKEN", "")
    gitlab_token = os.environ.get("GITLAB_TOKEN", "")
    bumped_file = os.environ.get("BUMPED_PACKAGES_FILE", "/tmp/bumped_packages.txt")

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
            process_package(pkg_dir, github_token, gitlab_token, bumped_file)
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

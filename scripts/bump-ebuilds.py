#!/usr/bin/env python3

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from portage.versions import vercmp
    HAS_PORTAGE = True
except ImportError:
    HAS_PORTAGE = False

GITHUB_API = "https://api.github.com"
GITLAB_API = "https://gitlab.com/api/v4"
OVERLAY_DIR = Path(__file__).resolve().parent.parent

_github_rate_limited = False

def log(msg):   print(f"[bump] {msg}", flush=True)
def info(msg):  print(f"[bump]   INFO  {msg}", flush=True)
def warn(msg):  print(f"[bump]   WARN  {msg}", flush=True)
def skip(msg):  print(f"[bump]   SKIP  {msg}", flush=True)
def ok(msg):    print(f"[bump]   OK    {msg}", flush=True)
def bump(msg):  print(f"[bump]   BUMP  {msg}", flush=True)
def err(msg):   print(f"[bump]   ERROR {msg}", file=sys.stderr, flush=True)

def http_get_json(url: str) -> dict | list:
    req = urllib.request.Request(url, headers={"User-Agent": "auto-ebuild-bump/1.2"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def github_get(url: str, token: str) -> dict | list | None:
    global _github_rate_limited
    headers = {"Accept": "application/vnd.github.v3+json",
               "User-Agent": "auto-ebuild-bump/1.2"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 403 and "rate limit" in str(exc).lower():
            if not _github_rate_limited:
                _github_rate_limited = True
                warn("GitHub API rate limit exceeded (HTTP 403). Falling back to web/git.")
        elif exc.code == 401:
            err(f"GitHub API authorization failed (HTTP 401) for {url}. Check GITHUB_TOKEN.")
        return None
    except urllib.error.URLError:
        return None


def gitlab_get(url: str, token: str) -> dict | list:
    headers = {"Accept": "application/json",
               "User-Agent": "auto-ebuild-bump/1.2"}
    if token:
        headers["PRIVATE-TOKEN"] = token
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def find_packages(overlay_dir: Path) -> list[Path]:
    dirs = {p.parent for p in overlay_dir.glob("*/*/*.ebuild")
            if ".git" not in p.parts}
    return sorted(dirs)


def extract_ebuild_var(content: str, var_name: str) -> str:
    """Extract full content of an ebuild variable, supporting multiline strings."""
    m = re.search(rf'^\s*{var_name}\s*=\s*(["\'])(.*?)\1', content, re.DOTALL | re.MULTILINE)
    if m:
        return m.group(2)
    m = re.search(rf'^\s*{var_name}\s*=\s*\((.*?)\)', content, re.DOTALL | re.MULTILINE)
    if m:
        return m.group(1)
    m = re.search(rf'^\s*{var_name}\s*=\s*(\S+)', content, re.MULTILINE)
    if m:
        return m.group(1)
    return ""


def extract_github_repo(text: str) -> str:
    m = re.search(r'https?://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)', text)
    if m:
        return re.sub(r'\.git$', '', m.group(1))
    m = re.search(r'https?://([A-Za-z0-9_.-]+)\.github\.io/([A-Za-z0-9_.-]+)', text)
    if m:
        return f"{m.group(1)}/{m.group(2)}"
    return ""


def extract_gitlab_repo(text: str) -> str:
    m = re.search(r'https://gitlab\.com/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)', text)
    if not m: return ""
    return re.sub(r'\.git$', '', '/'.join(m.group(1).split('/')[:2]))


def extract_aur_package(text: str) -> str:
    m = re.search(r'https://aur\.archlinux\.org/(?:packages|pkgbase)/([A-Za-z0-9_@+.-]+)', text)
    return m.group(1) if m else ""


def extract_debian_package(text: str) -> str:
    m = re.search(
        r'https://(?:packages\.debian\.org/(?:[a-z]+/)?|tracker\.debian\.org/pkg/)([A-Za-z0-9.+_-]+)', text)
    return m.group(1) if m else ""


def detect_upstream(homepage: str, src_uri: str) -> tuple[str, str]:
    gh = extract_github_repo(homepage) or extract_github_repo(src_uri)
    if gh: return ("github", gh)
    
    gl = extract_gitlab_repo(homepage) or extract_gitlab_repo(src_uri)
    if gl: return ("gitlab", gl)
    
    aur = extract_aur_package(homepage)
    if aur: return ("aur", aur)
    
    deb = extract_debian_package(homepage)
    if deb: return ("debian", deb)
    
    return ("", "")


def detect_flags(src_uri: str) -> tuple[bool, bool]:
    has_v_prefix = 'v${PV}' in src_uri
    prefer_releases = '/releases/download/' in src_uri or '/-/releases/' in src_uri
    return has_v_prefix, prefer_releases


_PRERELEASE_RE = re.compile(r'(?<![a-zA-Z])(rc|beta|alpha|pre|preview|b|a)(?![a-zA-Z])', re.I)


def _fallback_version_key(v: str) -> list:
    """Fallback if portage isn't available. Handles base cases and simple revisions."""
    parts = []
    for x in re.split(r'[._-]', v.lstrip('v')):
        if not x: continue
        if x.isdigit():
            parts.append(int(x))
        elif x.startswith('r') and x[1:].isdigit():  # Gentoo revisions (-r1)
            parts.append(int(x[1:]) + 1000) # Ensure revisions sort higher
        elif x.startswith('p') and not x.startswith('pre'):
            parts.append(1)
        else:
            parts.append(-1)
            
    parts.extend([0] * (10 - len(parts)))
    return parts[:10]

def version_gt(v1: str, v2: str) -> bool:
    """Return True when v1 is strictly newer than v2."""
    if HAS_PORTAGE:
        return vercmp(v1, v2) == 1
    return v1 != v2 and _fallback_version_key(v1) > _fallback_version_key(v2)

def version_sort_key(v: str):
    return _fallback_version_key(v)

def latest_github_release_web(repo: str) -> str:
    """Fallback to GitHub web releases/latest redirect (not rate-limited)."""
    url = f"https://github.com/{repo}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": "auto-ebuild-bump/1.2"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            final_url = resp.geturl()
            m = re.search(r'/releases/tag/([^/]+)$', final_url)
            if m:
                tag = urllib.parse.unquote(m.group(1))
                if not _PRERELEASE_RE.search(tag):
                    return tag
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return ""

def latest_git_tags(repo_url: str) -> list[str]:
    """Fetch tags via git ls-remote (not subject to GitHub REST API rate limits)."""
    try:
        res = subprocess.run(
            ["git", "ls-remote", "--tags", "--refs", repo_url],
            capture_output=True,
            text=True,
            timeout=20,
            check=True
        )
        tags = []
        for line in res.stdout.splitlines():
            parts = line.split("\trefs/tags/")
            if len(parts) == 2:
                tags.append(parts[1])
        return tags
    except Exception:
        return []

def latest_github_release(repo: str, token: str) -> str:
    if not _github_rate_limited:
        url = f"{GITHUB_API}/repos/{repo}/releases/latest"
        data = github_get(url, token)
        if isinstance(data, dict):
            tag_name = data.get("tag_name", "")
            if not (data.get("prerelease") or _PRERELEASE_RE.search(tag_name)):
                if tag_name:
                    return tag_name
    return latest_github_release_web(repo)

def latest_github_stable_tag(repo: str, token: str) -> str:
    names = []
    if not _github_rate_limited:
        url = f"{GITHUB_API}/repos/{repo}/tags?per_page=100"
        tags = github_get(url, token)
        if isinstance(tags, list):
            names = [t["name"] for t in tags if "name" in t]
    if not names:
        names = latest_git_tags(f"https://github.com/{repo}.git")
    if not names:
        return ""
    stable = [n for n in names if not _PRERELEASE_RE.search(n)]
    if not stable:
        stable = names
    stable.sort(key=version_sort_key, reverse=True)
    return stable[0]

def latest_gitlab_release(repo: str, token: str) -> str:
    encoded = urllib.parse.quote(repo, safe="")
    url = f"{GITLAB_API}/projects/{encoded}/releases?per_page=20"
    try:
        releases = gitlab_get(url, token)
        for rel in releases:
            tag = rel.get("tag_name", "")
            if not rel.get("upcoming_release") and not _PRERELEASE_RE.search(tag):
                return tag
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return ""

def latest_gitlab_tag(repo: str, token: str) -> str:
    encoded = urllib.parse.quote(repo, safe="")
    url = f"{GITLAB_API}/projects/{encoded}/repository/tags?per_page=100&order_by=version"
    try:
        tags = gitlab_get(url, token)
        names = [t["name"] for t in tags]
        stable = [n for n in names if not _PRERELEASE_RE.search(n)]
        if not stable: stable = names
        if not stable: return ""
        stable.sort(key=version_sort_key, reverse=True)
        return stable[0]
    except (urllib.error.HTTPError, urllib.error.URLError):
        return ""

def parse_aur_version(aur_version: str) -> str:
    v = re.sub(r"^\d+:", "", aur_version)
    v = re.sub(r"-\d+$", "", v)
    return v

def latest_aur_version(pkg: str) -> str:
    url = f"https://aur.archlinux.org/rpc/?v=5&type=info&arg[]={urllib.parse.quote(pkg)}"
    try:
        data = http_get_json(url)
        results = data.get("results", [])
        if results:
            raw = results[0].get("Version", "")
            return parse_aur_version(raw) if raw else ""
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return ""

def parse_debian_upstream_version(deb_version: str) -> str:
    v = re.sub(r"^\d+:", "", deb_version)
    v = re.sub(r"-\d+[a-z0-9.]*$", "", v)
    v = re.sub(r"[+~][a-z].*$", "", v)
    return v

def latest_debian_version(pkg: str) -> str:
    url = f"https://sources.debian.org/api/src/{urllib.parse.quote(pkg)}/"
    try:
        data = http_get_json(url)
        versions = data.get("versions", [])
        sid = [v["version"] for v in versions if "sid" in v.get("suites", [])]
        candidates = sid or [v["version"] for v in versions]
        if candidates:
            candidates.sort(key=version_sort_key, reverse=True)
            return parse_debian_upstream_version(candidates[0])
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return ""

def process_package(pkg_dir: Path, github_token: str, gitlab_token: str, bumped_file: str) -> None:
    pkg_name = pkg_dir.name
    rel_path = pkg_dir.relative_to(OVERLAY_DIR)

    # Ignore live (9999) ebuilds to prevent them from breaking standard version bumps
    ebuilds = [p for p in pkg_dir.glob(f"{pkg_name}-*.ebuild") if "9999" not in p.name]
    if not ebuilds:
        return
        
    ebuilds = sorted(ebuilds, key=lambda p: version_sort_key(p.stem[len(pkg_name) + 1:]))
    latest_ebuild = ebuilds[-1]
    current_pv = latest_ebuild.stem[len(pkg_name) + 1:]

    log(f"{rel_path}  (current: {current_pv})")

    content = latest_ebuild.read_text(encoding="utf-8", errors="replace")
    homepage = extract_ebuild_var(content, "HOMEPAGE")
    src_uri  = extract_ebuild_var(content, "SRC_URI")

    source_type, upstream_id = detect_upstream(homepage, src_uri)
    if not source_type:
        skip(f"no supported upstream for {pkg_name}")
        return
    
    info(f"upstream: {source_type}:{upstream_id}")

    upstream_tag = ""
    has_v_prefix = False

    match source_type:
        case "github":
            info("querying GitHub releases/latest …")
            upstream_tag = latest_github_release(upstream_id, github_token)
            if not upstream_tag:
                info("querying GitHub tags …")
                upstream_tag = latest_github_stable_tag(upstream_id, github_token)
        case "gitlab":
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

    upstream_pv = upstream_tag
    has_v_prefix, _ = detect_flags(src_uri)    
    if upstream_pv.startswith("v") and upstream_pv[1:2].isdigit() and not current_pv.startswith("v"):
        upstream_pv = upstream_pv[1:]
    elif has_v_prefix:
        upstream_pv = upstream_pv.removeprefix("v")

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
    with open(bumped_file, "a", encoding="utf-8") as fh:
        fh.write(str(pkg_dir) + "\n")

def main() -> None:
    if not HAS_PORTAGE:
        info("Portage module not found. Using fallback version comparison logic.")
        
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
        with open(bumped_file, encoding="utf-8") as fh:
            for line in fh:
                d = Path(line.strip())
                log(f"  {d.relative_to(OVERLAY_DIR)}")
    else:
        log("All packages are up to date – nothing to bump.")

if __name__ == "__main__":
    main()

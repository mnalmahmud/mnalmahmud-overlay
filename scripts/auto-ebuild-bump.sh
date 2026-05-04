#!/usr/bin/env bash
# scripts/auto-ebuild-bump.sh
#
# Scan all packages in this overlay for upstream GitHub releases/tags and
# copy the highest local ebuild to the new upstream version when an update is
# detected.
#
# Environment variables:
#   GITHUB_TOKEN           – optional; raises API rate limit to 5 000 req/h
#   BUMPED_PACKAGES_FILE   – path to write bumped package dirs (one per line);
#                            default: /tmp/bumped_packages.txt
#
# Usage:
#   bash scripts/auto-ebuild-bump.sh

set -euo pipefail

OVERLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_API="https://api.github.com"
BUMPED_PACKAGES_FILE="${BUMPED_PACKAGES_FILE:-/tmp/bumped_packages.txt}"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { printf '[bump] %s\n'        "$*"; }
info() { printf '[bump]   %s\n'      "$*"; }
skip() { printf '[bump]   SKIP  %s\n' "$*"; }
ok()   { printf '[bump]   OK    %s\n' "$*"; }
bump() { printf '[bump]   BUMP  %s\n' "$*"; }
err()  { printf '[bump]   ERROR %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# GitHub API helper
# ---------------------------------------------------------------------------
github_get() {
    local url="$1"
    local args=(-fsSL -H "Accept: application/vnd.github.v3+json")
    [[ -n "${GITHUB_TOKEN:-}" ]] && args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl "${args[@]}" "$url"
}

# ---------------------------------------------------------------------------
# Extract the first "owner/repo" slug from stdin text.
# Matches https://github.com/<owner>/<repo> (stops at next / or whitespace).
# Strips a trailing ".git" suffix if present.
# ---------------------------------------------------------------------------
extract_github_repo() {
    grep -oP 'https://github\.com/\K[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
        | head -1 \
        | sed 's/\.git$//'
}

# ---------------------------------------------------------------------------
# version_gt v1 v2
# Returns 0 (true) when v1 is strictly newer than v2, using GNU sort -V.
# ---------------------------------------------------------------------------
version_gt() {
    local v1="$1" v2="$2"
    [[ "$v1" != "$v2" ]] && \
        [[ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -1)" == "$v1" ]]
}

# ---------------------------------------------------------------------------
# latest_stable_tag
# Read a GitHub tags JSON array from stdin and print the highest stable tag.
# Stable = no rc/beta/alpha/pre/preview substring.  Falls back to all tags
# when no stable tags are found.
# ---------------------------------------------------------------------------
latest_stable_tag() {
    python3 - <<'PY'
import sys, json, re

tags = json.load(sys.stdin)
names = [t['name'] for t in tags]

stable = [n for n in names
          if not re.search(r'(rc|beta|alpha|pre|preview)([._-]?\d*|$)', n, re.I)]
if not stable:
    stable = names   # no stable → accept all

def sort_key(v):
    return [int(x) if x.isdigit() else 0
            for x in re.split(r'[._-]', v.lstrip('v'))]

stable.sort(key=sort_key, reverse=True)
print(stable[0] if stable else '')
PY
}

# ---------------------------------------------------------------------------
# process_package <pkg_dir>
# ---------------------------------------------------------------------------
process_package() {
    local pkg_dir="$1"
    local pkg_name rel_path
    pkg_name="$(basename "$pkg_dir")"
    rel_path="$(realpath --relative-to="$OVERLAY_DIR" "$pkg_dir")"

    # ---- Find the highest-versioned ebuild ----------------------------------
    local latest_ebuild
    latest_ebuild="$(find "$pkg_dir" -maxdepth 1 -name "${pkg_name}-*.ebuild" \
                     | sort -V | tail -1)"
    [[ -z "$latest_ebuild" ]] && return 0

    local current_pv
    current_pv="$(basename "$latest_ebuild" .ebuild)"
    current_pv="${current_pv#${pkg_name}-}"

    log "${rel_path}  (current: ${current_pv})"

    # ---- Read HOMEPAGE and SRC_URI ------------------------------------------
    # Use the raw file text; grep finds the variable line(s).
    local content homepage_text src_uri_text
    content="$(cat "$latest_ebuild")"
    homepage_text="$(printf '%s' "$content" | grep -i 'HOMEPAGE=' || true)"
    src_uri_text="$(printf '%s'  "$content" | grep -i 'SRC_URI='  || true)"

    # ---- Locate upstream GitHub repo (HOMEPAGE first, SRC_URI second) -------
    local github_repo=""
    github_repo="$(printf '%s' "$homepage_text" | extract_github_repo)"
    if [[ -z "$github_repo" ]]; then
        github_repo="$(printf '%s' "$src_uri_text" | extract_github_repo)"
    fi

    if [[ -z "$github_repo" ]]; then
        skip "no GitHub upstream for ${pkg_name}"
        return 0
    fi
    info "upstream: ${github_repo}"

    # ---- Detect v-prefix in SRC_URI -----------------------------------------
    # True when SRC_URI contains a literal v${PV} token (e.g. download/v${PV})
    local has_v_prefix=false
    if printf '%s' "$content" | grep -qF 'v${PV}'; then
        has_v_prefix=true
    fi

    # ---- Prefer GitHub Releases when SRC_URI uses /releases/download/ -------
    local prefer_releases=false
    if printf '%s' "$content" | grep -qF '/releases/download/'; then
        prefer_releases=true
    fi

    # ---- Fetch upstream version ---------------------------------------------
    local upstream_tag=""

    if [[ "$prefer_releases" == true ]]; then
        info "querying releases/latest …"
        local rel_json=""
        if rel_json="$(github_get "${GITHUB_API}/repos/${github_repo}/releases/latest" 2>/dev/null)"; then
            local prerelease
            prerelease="$(python3 -c \
                "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('prerelease',False))" \
                <<< "$rel_json" 2>/dev/null || echo "False")"
            if [[ "$prerelease" != "True" ]]; then
                upstream_tag="$(python3 -c \
                    "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tag_name',''))" \
                    <<< "$rel_json" 2>/dev/null || true)"
            fi
        fi
    fi

    # ---- Fallback: query tags -----------------------------------------------
    if [[ -z "$upstream_tag" ]]; then
        info "querying tags …"
        local tags_json=""
        if tags_json="$(github_get "${GITHUB_API}/repos/${github_repo}/tags?per_page=100" 2>/dev/null)"; then
            upstream_tag="$(latest_stable_tag <<< "$tags_json" || true)"
        fi
    fi

    if [[ -z "$upstream_tag" ]]; then
        skip "could not determine upstream version for ${pkg_name}"
        return 0
    fi

    # ---- Convert tag → Gentoo PV (strip leading 'v' when expected) ----------
    local upstream_pv="$upstream_tag"
    if [[ "$has_v_prefix" == true && "$upstream_tag" == v* ]]; then
        upstream_pv="${upstream_tag#v}"
    fi
    info "upstream tag: ${upstream_tag}  →  PV: ${upstream_pv}"

    # ---- Compare versions ---------------------------------------------------
    if ! version_gt "$upstream_pv" "$current_pv"; then
        ok "${pkg_name} is already at ${current_pv} (upstream: ${upstream_pv})"
        return 0
    fi

    # ---- Bump: copy ebuild to new version -----------------------------------
    local new_ebuild="${pkg_dir}/${pkg_name}-${upstream_pv}.ebuild"
    bump "${pkg_name}: ${current_pv} → ${upstream_pv}"
    cp "$latest_ebuild" "$new_ebuild"
    echo "$pkg_dir" >> "$BUMPED_PACKAGES_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    rm -f "$BUMPED_PACKAGES_FILE"

    # Find all package directories (category/package/name.ebuild = 3 levels deep)
    local pkg_dirs
    pkg_dirs="$(find "$OVERLAY_DIR" -mindepth 3 -maxdepth 3 -name '*.ebuild' \
                    ! -path '*/.git/*' \
                    -exec dirname {} \; \
                | sort -u)"

    if [[ -z "$pkg_dirs" ]]; then
        log "No ebuilds found under ${OVERLAY_DIR}."
        return 0
    fi

    while IFS= read -r pkg_dir; do
        process_package "$pkg_dir" || err "failed processing ${pkg_dir}"
    done <<< "$pkg_dirs"

    echo ""
    if [[ -f "$BUMPED_PACKAGES_FILE" ]]; then
        log "Packages bumped:"
        while IFS= read -r d; do
            log "  $(realpath --relative-to="$OVERLAY_DIR" "$d")"
        done < "$BUMPED_PACKAGES_FILE"
    else
        log "All packages are up to date – nothing to bump."
    fi
}

main "$@"

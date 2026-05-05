#!/usr/bin/env bash
# Must be run as root (or via sudo) so that ebuild can fetch distfiles.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$SCRIPT_DIR")"

find "$OVERLAY_DIR" -name '*.ebuild' | while IFS= read -r ebuild; do
    echo ">>> manifest: $ebuild"
    ebuild "$ebuild" manifest
done

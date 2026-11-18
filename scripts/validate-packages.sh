#!/usr/bin/env bash
# validate-packages.sh - static checks for community package recipes.
#
# Usage: scripts/validate-packages.sh [package...]
#
# Without arguments every directory under packages/ is checked. Nothing from a
# recipe is executed: the checks only read the files.
#
# Environment:
#   TERMUX_PACKAGES_DIR  checkout of termux-packages, used to detect name collisions

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_dir="$root/packages"
errors=0

fail() {
    echo "  [FAIL] $*"
    errors=$((errors + 1))
}

var_of() {
    sed -n "s/^$1=//p" "$2" | head -n 1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

check_package() {
    local name="$1"
    local dir="$packages_dir/$name"
    local build="$dir/build.sh"
    local var value file channel skip srcurl sha

    echo "==> $name"

    if ! [[ "$name" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
        fail "invalid package name (use lowercase letters, digits, '+', '-' and '.', at least two characters)"
    fi

    if [ ! -f "$build" ]; then
        fail "build.sh is missing"
        return
    fi

    if ! bash -n "$build" 2>/dev/null; then
        fail "build.sh has a syntax error"
    fi

    for var in TERMUX_PKG_HOMEPAGE TERMUX_PKG_DESCRIPTION TERMUX_PKG_LICENSE TERMUX_PKG_MAINTAINER TERMUX_PKG_VERSION; do
        if [ -z "$(var_of "$var" "$build")" ]; then
            fail "$var is missing"
        fi
    done

    value="$(var_of TERMUX_PKG_MAINTAINER "$build")"
    if [ -n "$value" ]; then
        case "$value" in
            @*) ;;
            *) fail "TERMUX_PKG_MAINTAINER must be a GitHub user or team that starts with @" ;;
        esac
    fi

    skip="$(var_of TERMUX_PKG_SKIP_SRC_EXTRACT "$build")"
    if [ "$skip" != "true" ]; then
        srcurl="$(var_of TERMUX_PKG_SRCURL "$build")"
        sha="$(var_of TERMUX_PKG_SHA256 "$build")"
        case "$srcurl" in
            https://*)
                if ! [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
                    fail "TERMUX_PKG_SHA256 must be a 64 character lowercase hex digest"
                fi
                ;;
            git+https://*)
                if ! [[ "$sha" =~ ^[0-9a-f]{64}$ || "$sha" = "SKIP_CHECKSUM" ]]; then
                    fail "TERMUX_PKG_SHA256 must be a 64 character lowercase hex digest or SKIP_CHECKSUM"
                fi
                ;;
            *)
                fail "TERMUX_PKG_SRCURL must start with https:// or git+https://"
                ;;
        esac
    fi

    if grep -rIl 'com\.termux' "$dir" >/dev/null 2>&1; then
        fail "files must not refer to com.termux; use \$TERMUX_PREFIX instead"
    fi

    if [ -n "$(find "$dir" -type f -size +1024k -print -quit)" ]; then
        fail "package files must be smaller than 1 MB"
    fi

    for file in "$dir"/*.subpackage.sh; do
        [ -e "$file" ] || continue
        value="$(basename "$file" .subpackage.sh)"
        if ! [[ "$value" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            fail "invalid subpackage name: $value"
        fi
    done

    if [ -n "${TERMUX_PACKAGES_DIR:-}" ]; then
        for channel in packages root-packages x11-packages disabled-packages; do
            if [ -e "$TERMUX_PACKAGES_DIR/$channel/$name" ]; then
                fail "the name collides with termux-packages ($channel/$name)"
            fi
        done
    fi
}

names=()
if [ $# -gt 0 ]; then
    names=("$@")
else
    for dir in "$packages_dir"/*/; do
        [ -d "$dir" ] && names+=("$(basename "$dir")")
    done
fi

if [ "${#names[@]}" -eq 0 ]; then
    echo "validate-packages: no packages were found" >&2
    exit 1
fi

for name in "${names[@]}"; do
    check_package "$name"
done

echo
if [ "$errors" -gt 0 ]; then
    echo "$errors problem(s) found"
    exit 1
fi
echo "All ${#names[@]} package(s) passed"
#!/usr/bin/env bash
# build-package.sh - build community packages for one app and one architecture.
#
# Usage: scripts/build-package.sh <application-id> <arch> <package>...
#   application-id  Android applicationId, for example app.term.one
#   arch            aarch64 or x86_64
#   package         names of directories under packages/
#
# Environment:
#   TERMUX_PACKAGES_REPO  git URL of termux-packages (default: the official repository)
#   TERMUX_PACKAGES_REF   branch, tag or commit to build (default: master)
#
# Result: debs/<application-id>/<arch>/*.deb (only the community packages and their subpackages)

set -euo pipefail

die() {
    echo "build-package: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

if [ $# -lt 3 ]; then
    die "usage: build-package.sh <application-id> <arch> <package>..."
fi
app_id="$1"
arch="$2"
shift 2
packages=("$@")

case "$arch" in
    aarch64|x86_64) ;;
    *) die "unsupported architecture: $arch (use aarch64 or x86_64)" ;;
esac

if ! [[ "$app_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    die "invalid application id: $app_id"
fi

for tool in git docker sed grep find sudo; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

repo_url="${TERMUX_PACKAGES_REPO:-https://github.com/termux/termux-packages.git}"
ref="${TERMUX_PACKAGES_REF:-master}"
rootfs_subdir="files/rootdir"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$root/work/$app_id-$arch"
debs_dir="$root/debs/$app_id/$arch"
log="$root/work/$app_id-$arch.log"
expected_prefix="/data/data/$app_id/files/rootdir/usr"

container="${CONTAINER_NAME:-termux-package-builder}"
export CONTAINER_NAME="$container"

for name in "${packages[@]}"; do
    [ -f "$root/packages/$name/build.sh" ] || die "unknown package: $name"
done

mkdir -p "$root/work"
rm -rf "$work" "$debs_dir"
: > "$log"

# ---------------------------------------------------------------- helpers

show_failure() {
    echo
    echo "==== lines of the log that mention errors ===="
    { grep -nE 'error:|ERROR:|Error:|fatal|undefined reference|Permission denied|No such file|Failed to' "$log" | grep -v 'Werror' | tail -n 40; } || true
    echo "==== last 30 lines of the log ===="
    tail -n 30 "$log" || true
}

run_build() {
    local attempt=1
    while true; do
        if ( cd "$work" && "$@" ) 2>&1 | tee -a "$log"; then
            return 0
        fi
        if [ "$attempt" -ge 2 ] || ! tail -n 400 "$log" | grep -qE 'Connection timed out|Failed to download|Could not resolve host|Connection reset'; then
            return 1
        fi
        attempt=$((attempt + 1))
        echo "A download failed; trying again in 60 seconds (attempt $attempt)"
        sleep 60
    done
}

prepare_container() {
    step "Preparing the builder container"

    sudo chown -R "$(id -u):$(id -g)" "$root/work" || die "could not take over the work folder"
    mkdir -p "$work/output"
    echo "runner: uid=$(id -u) gid=$(id -g)"

    # The restricted AppArmor profile of run-docker.sh blocks writes the build needs; see the TP repository.
    if [ -f "$work/scripts/profile-relaxed.apparmor" ] && [ -f "$work/scripts/profile-restricted.apparmor" ]; then
        cp "$work/scripts/profile-relaxed.apparmor" "$work/scripts/profile-restricted.apparmor"
    fi

    cat > "$work/scripts/term-preflight.sh" <<'EOF'
#!/bin/bash
set -e
echo "builder: uid=$(id -u) gid=$(id -g)"
cd /home/builder/termux-packages
mkdir -p output
touch output/.write-test
rm -f output/.write-test
touch .write-test
rm -f .write-test
mkdir -p /data/data/.preflight
rmdir /data/data/.preflight
echo "the builder can write to the checkout, to its output folder and to /data"
EOF
    chmod +x "$work/scripts/term-preflight.sh"

    ( cd "$work" && ./scripts/run-docker.sh true ) || die "the builder container could not be started"

    docker exec --user root "$container" sh -ec '
        id builder
        chmod a+rwx /home/builder/termux-packages
        chmod -R a+rwX /home/builder/termux-packages
        mkdir -p /data/data /home/builder/.termux-build
        chmod -R a+rwX /data
        chown -R builder:builder /data /home/builder/.termux-build
        ls -ld /home/builder/termux-packages /home/builder/termux-packages/output
    ' || die "could not open up the checkout inside the builder container"

    if ! ( cd "$work" && ./scripts/run-docker.sh ./scripts/term-preflight.sh ); then
        docker exec --user root "$container" sh -c 'id builder; ls -ld /home/builder /home/builder/termux-packages /data' || true
        die "the builder cannot write to the checkout (see the ids above)"
    fi
}

# ---------------------------------------------------------------- fetch

step "Fetching termux-packages at $ref"
git init -q "$work"
git -C "$work" remote add origin "$repo_url"
git -C "$work" fetch -q --depth 1 origin "$ref"
git -C "$work" checkout -q FETCH_HEAD
echo "termux-packages commit: $(git -C "$work" rev-parse HEAD)"

# ---------------------------------------------------------------- patch properties

step "Configuring properties for $app_id"
props="$work/scripts/properties.sh"
[ -f "$props" ] || die "scripts/properties.sh was not found in termux-packages"

sed -i "s|^TERMUX_APP__PACKAGE_NAME=\"com\.termux\"\$|TERMUX_APP__PACKAGE_NAME=\"$app_id\"|" "$props"
sed -i "s|^TERMUX__ROOTFS_SUBDIR=\"files\"\$|TERMUX__ROOTFS_SUBDIR=\"$rootfs_subdir\"|" "$props"

grep -q "^TERMUX_APP__PACKAGE_NAME=\"$app_id\"\$" "$props" \
    || die "could not set TERMUX_APP__PACKAGE_NAME; properties.sh changed upstream, pin termux_packages_ref"
grep -q "^TERMUX__ROOTFS_SUBDIR=\"$rootfs_subdir\"\$" "$props" \
    || die "could not set TERMUX__ROOTFS_SUBDIR; properties.sh changed upstream, pin termux_packages_ref"

actual_prefix="$(bash -c 'source "$1/scripts/properties.sh" >/dev/null && printf "%s" "$TERMUX__PREFIX"' _ "$work")" \
    || die "properties.sh rejected the configured layout"
if [ "$actual_prefix" != "$expected_prefix" ]; then
    die "resolved prefix is '$actual_prefix' but '$expected_prefix' is required"
fi
echo "prefix: $actual_prefix"

# ---------------------------------------------------------------- add the community recipes

step "Adding community recipes"
for dir in "$root"/packages/*/; do
    name="$(basename "$dir")"
    if [ -e "$work/packages/$name" ]; then
        die "package '$name' collides with a termux-packages recipe"
    fi
    cp -r "$dir" "$work/packages/$name"
    echo "added $name"
done

# ---------------------------------------------------------------- build

prepare_container

step "Building: ${packages[*]}"
# -s skips the dependencies: they are not built here, they come from the TP repository when the
# package is installed.
if ! run_build ./scripts/run-docker.sh ./build-package.sh -s -a "$arch" "${packages[@]}"; then
    show_failure
    die "the build failed (see $log)"
fi

# ---------------------------------------------------------------- collect

step "Collecting .deb files"
declare -A publish=()
for name in "${packages[@]}"; do
    publish["$name"]=1
    publish["$name-dev"]=1
    for sub in "$root/packages/$name"/*.subpackage.sh; do
        [ -e "$sub" ] || continue
        publish["$(basename "$sub" .subpackage.sh)"]=1
    done
done

mkdir -p "$debs_dir"
count=0
while IFS= read -r deb; do
    base="$(basename "$deb")"
    case "$base" in
        *-static_*) continue ;;
    esac
    pkg="${base%%_*}"
    if [ -n "${publish[$pkg]:-}" ]; then
        cp "$deb" "$debs_dir/"
        echo "collected $base"
        count=$((count + 1))
    fi
done < <(find "$work/output" -maxdepth 1 -type f -name '*.deb' 2>/dev/null | sort)

[ "$count" -gt 0 ] || die "no community .deb files were found in $work/output (see $log)"
echo "collected $count package files"
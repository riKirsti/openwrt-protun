#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

: "${PACKAGES_COMMIT:?Missing packages feed commit}"
: "${PROTUN_CARGO_TARGET_DIR:?Missing Cargo cache directory}"
: "${BUILD_JOBS:=2}"

if [[ ! $PACKAGES_COMMIT =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Invalid packages feed commit' >&2
    exit 1
fi
if [[ ! $BUILD_JOBS =~ ^[1-9][0-9]*$ ]]; then
    echo 'BUILD_JOBS must be a positive integer' >&2
    exit 1
fi
if [[ ${VERSION_PATH:-} != releases/25.12.5 ]]; then
    echo 'Expected the OpenWrt 25.12.5 release SDK' >&2
    exit 1
fi

cd /builder

# Release images contain the SDK; also handle images with a setup script.
if [[ ! -f rules.mk ]]; then
    bash ./setup.sh
fi

# Pin the Rust package and its helpers to the reviewed 25.12 feed revision.
printf 'src-git packages https://github.com/openwrt/packages.git^%s\nsrc-link action /feed\n' \
    "$PACKAGES_COMMIT" > feeds.conf
./scripts/feeds update -a
test "$(git -C feeds/packages rev-parse HEAD)" = "$PACKAGES_COMMIT"
make defconfig
./scripts/feeds install -f -p action protun

sed -i '/^CONFIG_PACKAGE_protun=/d; /^# CONFIG_PACKAGE_protun is not set$/d' .config
printf '\nCONFIG_PACKAGE_protun=m\n' >> .config
make defconfig
if ! grep -Eq '^CONFIG_PACKAGE_protun=[my]$' .config; then
    echo 'Protun was not selected; refusing to report a skipped build as successful' >&2
    exit 1
fi

make package/protun/download V=s
make package/protun/check V=s
make -j "$BUILD_JOBS" package/protun/compile V=s CONFIG_SIGNED_PACKAGES= CONFIG_AUTOREMOVE=

# Run the libraries using the SDK's ARM64 musl loader and QEMU binfmt support.
compilers=(staging_dir/toolchain-*/bin/aarch64-openwrt-linux-musl-gcc)
if (( ${#compilers[@]} != 1 )); then
    echo 'Expected one ARM64 SDK compiler' >&2
    exit 1
fi
sysroot="$("${compilers[0]}" -print-sysroot)"
loader="$sysroot/lib/ld-musl-aarch64.so.1"
test -x "$loader"
"${compilers[0]}" -Wall -Wextra -Werror -O2 /ci/load-library.c -o /tmp/protun-load-test -ldl

profile=release
if grep -qx 'CONFIG_DEBUG=y' .config; then
    profile=debug
fi
unpacked="$PROTUN_CARGO_TARGET_DIR/aarch64-unknown-linux-musl/$profile/libprotun.so"
test -s "$unpacked"

# Check before UPX, independently of dependency scanning on the packed ELF.
readelf="${compilers[0]%-gcc}-readelf"
needed="$("$readelf" -d "$unpacked" | sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p')"
test -n "$needed"
while IFS= read -r dependency; do
    case "$dependency" in
        libc.so|libgcc_s.so.1) ;;
        *)
            echo "Undeclared runtime dependency: $dependency; update Package/protun/DEPENDS" >&2
            exit 1
            ;;
    esac
done <<< "$needed"

mapfile -t packed < <(find build_dir -type f -path '*/ipkg-*/protun/usr/lib/libprotun.so')
if (( ${#packed[@]} != 1 )); then
    echo 'Expected one staged Protun shared library' >&2
    exit 1
fi
for library in "$unpacked" "${packed[0]}"; do
    "$loader" --library-path "$sysroot/lib:$sysroot/usr/lib" \
        /tmp/protun-load-test "$(realpath "$library")"
done

mapfile -t packages < <(find bin/packages -type f -name 'protun-*.apk')
if (( ${#packages[@]} != 1 )); then
    echo 'Expected exactly one Protun APK' >&2
    exit 1
fi
cp "${packages[0]}" /out/

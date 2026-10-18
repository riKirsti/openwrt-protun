#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

: "${PACKAGES_COMMIT:?Missing packages feed commit}"
: "${PROTUN_CARGO_TARGET_DIR:?Missing Cargo cache directory}"
: "${PROTUN_RUST_ROOT:?Missing prebuilt Rust toolchain}"
: "${RUST_VERSION:?Missing expected Rust version}"
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

# Call the mounted compiler directly: runner rustup shims are not in the SDK.
export PATH="$PROTUN_RUST_ROOT/bin:$PATH"
"$PROTUN_RUST_ROOT/bin/rustc" --version | grep -F "rustc $RUST_VERSION "
"$PROTUN_RUST_ROOT/bin/cargo" --version
target_libdir="$("$PROTUN_RUST_ROOT/bin/rustc" --print target-libdir --target aarch64-unknown-linux-musl)"
target_std=("$target_libdir"/libstd-*.rlib)
if (( ${#target_std[@]} != 1 )); then
    echo 'Missing prebuilt ARM64 musl standard library' >&2
    exit 1
fi
sdk_make=(make "PROTUN_RUST_ROOT=$PROTUN_RUST_ROOT")

# Release images contain the SDK; also handle images with a setup script.
if [[ ! -f rules.mk ]]; then
    bash ./setup.sh
fi

# Keep the SDK's Rust build flags and linker helpers at the reviewed revision.
printf 'src-git packages https://github.com/openwrt/packages.git^%s\nsrc-link action /feed\n' \
    "$PACKAGES_COMMIT" > feeds.conf
./scripts/feeds update -a
test "$(git -C feeds/packages rev-parse HEAD)" = "$PACKAGES_COMMIT"
"${sdk_make[@]}" defconfig
./scripts/feeds install -f -p action protun

sed -i '/^CONFIG_PACKAGE_protun=/d; /^# CONFIG_PACKAGE_protun is not set$/d' .config
printf '\nCONFIG_PACKAGE_protun=m\n' >> .config
"${sdk_make[@]}" defconfig
if ! grep -Eq '^CONFIG_PACKAGE_protun=[my]$' .config; then
    echo 'Protun was not selected; refusing to report a skipped build as successful' >&2
    exit 1
fi

# Check the evaluated package metadata before allowing an expensive compiler build.
package_info="$("${sdk_make[@]}" --no-print-directory -s -C package/feeds/action/protun TOPDIR=/builder DUMP=1)"
grep -qx 'Package: protun' <<< "$package_info"
if grep -Eq '^Build-Depends[^:]*:.*rust/host' <<< "$package_info"; then
    echo 'The build still requires compiling Rust/LLVM; refusing to continue' >&2
    exit 1
fi

"${sdk_make[@]}" package/protun/download V=s
"${sdk_make[@]}" package/protun/check V=s
"${sdk_make[@]}" -j "$BUILD_JOBS" package/protun/compile V=s CONFIG_SIGNED_PACKAGES= CONFIG_AUTOREMOVE=

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

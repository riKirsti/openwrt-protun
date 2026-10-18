#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

phase=startup
on_error() {
    printf 'Failed in phase %s at line %s (exit %s)\n' "$phase" "$2" "$1" >&2
    exit "$1"
}
trap 'on_error "$?" "$LINENO"' ERR

run_phase() {
    phase=$1
    shift
    local started=$SECONDS
    echo "::group::$phase"
    "$@"
    echo "$phase completed in $((SECONDS - started))s"
    echo '::endgroup::'
}

preflight() {
    : "${PACKAGES_COMMIT:?Missing packages feed commit}"
    : "${PROTUN_CARGO_TARGET_DIR:?Missing Cargo cache directory}"
    : "${PROTUN_RUST_ROOT:?Missing prebuilt Rust toolchain}"
    : "${RUST_VERSION:?Missing expected Rust version}"
    : "${BUILD_JOBS:=$(nproc)}"
    : "${PROTUN_FAST_BUILD:=0}"

    if [[ ! $PACKAGES_COMMIT =~ ^[0-9a-f]{40}$ ]]; then
        echo 'Invalid packages feed commit' >&2
        exit 1
    fi
    if [[ ! $BUILD_JOBS =~ ^[1-9][0-9]*$ ]]; then
        echo 'BUILD_JOBS must be a positive integer' >&2
        exit 1
    fi
    if [[ ! $PROTUN_FAST_BUILD =~ ^[01]$ ]]; then
        echo 'PROTUN_FAST_BUILD must be 0 or 1' >&2
        exit 1
    fi
    if [[ ${VERSION_PATH:-} != releases/25.12.5 ]]; then
        echo 'Expected the OpenWrt 25.12.5 release SDK' >&2
        exit 1
    fi

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
    sdk_make=(make "PROTUN_RUST_ROOT=$PROTUN_RUST_ROOT" "PROTUN_FAST_BUILD=$PROTUN_FAST_BUILD")
}

configure_sdk() {
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
}

compile_package() {
    "${sdk_make[@]}" package/protun/download V=s
    "${sdk_make[@]}" package/protun/check V=s
    "${sdk_make[@]}" -j "$BUILD_JOBS" package/protun/compile V=s CONFIG_SIGNED_PACKAGES= CONFIG_AUTOREMOVE=
}

verify_libraries() {
    # Run the libraries using the SDK's ARM64 musl loader and QEMU binfmt support.
    compilers=(staging_dir/toolchain-*/bin/aarch64-openwrt-linux-musl-gcc)
    if (( ${#compilers[@]} != 1 )); then
        echo 'Expected one ARM64 SDK compiler' >&2
        exit 1
    fi
    # OpenWrt's relocatable SDK keeps libc beside the toolchain, not necessarily
    # under GCC's reported sysroot. Make exports these staging paths only to its
    # own children; the standalone check compiler needs them explicitly as well.
    toolchain_dir="$(realpath "$(dirname "${compilers[0]}")/..")"
    target_dirs=(staging_dir/target-*)
    if (( ${#target_dirs[@]} != 1 )) || [[ ! -d ${target_dirs[0]} ]]; then
        echo 'Expected one SDK target staging directory' >&2
        exit 1
    fi
    STAGING_DIR="$(realpath "${target_dirs[0]}")"
    export STAGING_DIR
    export STAGING_DIR_HOST=/builder/staging_dir/host
    loader="$toolchain_dir/lib/ld-musl-aarch64.so.1"
    if [[ ! -x $loader ]]; then
        echo "Missing executable SDK musl loader: $loader" >&2
        exit 1
    fi
    echo "Checking library loading with SDK musl: $loader"
    "${compilers[0]}" -Wall -Wextra -Werror -O2 /ci/load-library.c -o /tmp/protun-load-test -ldl

    profile=release
    if grep -qx 'CONFIG_DEBUG=y' .config; then
        profile=debug
    fi
    unpacked="$PROTUN_CARGO_TARGET_DIR/aarch64-unknown-linux-musl/$profile/libprotun.so"
    if [[ ! -s $unpacked ]]; then
        echo "Missing built Protun library: $unpacked" >&2
        exit 1
    fi

    # Check the built library's dependencies independently of SDK package scanning.
    readelf="${compilers[0]%-gcc}-readelf"
    needed="$("$readelf" -d "$unpacked" | sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p')"
    if [[ -z $needed ]]; then
        echo "No shared-library dependencies found in: $unpacked" >&2
        exit 1
    fi
    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so|libgcc_s.so.1) ;;
            *)
                echo "Undeclared runtime dependency: $dependency; update Package/protun/DEPENDS" >&2
                exit 1
                ;;
        esac
    done <<< "$needed"

    mapfile -t staged < <(find build_dir -type f -path '*/ipkg-*/protun/usr/lib/libprotun.so')
    if (( ${#staged[@]} != 1 )); then
        echo 'Expected one staged Protun shared library' >&2
        exit 1
    fi
    for library in "$unpacked" "${staged[0]}"; do
        "$loader" --library-path "$toolchain_dir/lib:$STAGING_DIR/lib:$STAGING_DIR/usr/lib" \
            /tmp/protun-load-test "$(realpath "$library")"
    done
}

export_apk() {
    mapfile -t packages < <(find bin/packages -type f -name 'protun-*.apk')
    if (( ${#packages[@]} != 1 )); then
        echo 'Expected exactly one Protun APK' >&2
        exit 1
    fi
    cp "${packages[0]}" /out/
    local package_bytes
    package_bytes=$(stat -c %s "${packages[0]}")
    echo "Exported ${packages[0]##*/}: $package_bytes bytes"
}

cd /builder
run_phase 'Preflight' preflight
run_phase 'SDK feeds and configuration' configure_sdk
run_phase 'Compile and package' compile_package
run_phase 'ARM64 library checks' verify_libraries
run_phase 'Export APK' export_apk

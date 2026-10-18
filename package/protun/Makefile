include $(TOPDIR)/rules.mk

PKG_NAME:=protun
PKG_VERSION:=3.0.1
PKG_RELEASE:=6

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/ProtonVPN/protun/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=6204027ab912c33aacc7ae9535d1f622154e9d85076785824f6e05baf9514d0a

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
# Normal SDK builds use OpenWrt Rust; CI supplies a prebuilt toolchain instead.
ifeq ($(strip $(PROTUN_RUST_ROOT)),)
  PKG_BUILD_DEPENDS:=rust/host
endif
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

PROTUN_CARGO:=cargo
ifneq ($(strip $(PROTUN_RUST_ROOT)),)
  PROTUN_CARGO:=$(PROTUN_RUST_ROOT)/bin/cargo
  PROTUN_RUST_VARS:=RUSTC="$(PROTUN_RUST_ROOT)/bin/rustc"
  # Use the SDK's musl and startup objects, rather than Rust's bundled copies.
  CARGO_RUSTFLAGS+=-Clink-self-contained=no
endif

# Runtime builds favor device performance; fast builds shorten test compilation.
# These assignments must follow CARGO_PKG_VARS in the command below.
PROTUN_BUILD_MODE?=runtime
ifeq ($(PROTUN_BUILD_MODE),runtime)
  PROTUN_PROFILE_VARS:=CARGO_PROFILE_RELEASE_LTO=thin CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 CARGO_PROFILE_RELEASE_OPT_LEVEL=3
else ifeq ($(PROTUN_BUILD_MODE),fast)
  PROTUN_PROFILE_VARS:=CARGO_PROFILE_RELEASE_LTO=off CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 CARGO_PROFILE_RELEASE_OPT_LEVEL=1
else
  $(error PROTUN_BUILD_MODE must be runtime or fast)
endif

CARGO_OUTPUT_DIR:=$(if $(filter dev,$(CARGO_PKG_PROFILE)),debug,$(CARGO_PKG_PROFILE))
PROTUN_CARGO_TARGET_DIR?=$(PKG_BUILD_DIR)/target

define Package/protun
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Proton VPN core library
  URL:=https://github.com/ProtonVPN/protun
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libgcc
endef

define Package/protun/description
  Proton VPN core shared library for Linux.
  Upstream provides libprotun.so, not a standalone protun VPN command.
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/Cargo.lock $(PKG_BUILD_DIR)/Cargo.lock
endef

define Build/Compile
	+cd $(PKG_BUILD_DIR) && \
		$(CARGO_PKG_VARS) \
		$(PROTUN_PROFILE_VARS) \
		TARGET_AR="$(TARGET_AR)" \
		$(PROTUN_RUST_VARS) \
		$(PROTUN_CARGO) build -v --locked --lib \
			--profile $(CARGO_PKG_PROFILE) \
			--features linux \
			--target-dir $(PROTUN_CARGO_TARGET_DIR) \
			$(if $(filter --jobserver%,$(PKG_JOBS)),,-j1)
endef

define Package/protun/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PROTUN_CARGO_TARGET_DIR)/$(RUSTC_TARGET_ARCH)/$(CARGO_OUTPUT_DIR)/libprotun.so $(1)/usr/lib/
endef

$(eval $(call BuildPackage,protun))

include $(TOPDIR)/rules.mk

PKG_NAME:=protun
PKG_VERSION:=3.0.1
PKG_RELEASE:=2

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/ProtonVPN/protun/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=6204027ab912c33aacc7ae9535d1f622154e9d85076785824f6e05baf9514d0a

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

UPX_VERSION:=5.2.1
UPX_FILE:=upx-$(UPX_VERSION)-amd64_linux.tar.xz

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# Strip before UPX; do not strip the packed library again during packaging.
RSTRIP:=:
CARGO_OUTPUT_DIR:=$(if $(filter dev,$(CARGO_PKG_PROFILE)),debug,$(CARGO_PKG_PROFILE))
PROTUN_CARGO_TARGET_DIR?=$(PKG_BUILD_DIR)/target

define Download/upx
  FILE:=$(UPX_FILE)
  URL:=https://github.com/upx/upx/releases/download/v$(UPX_VERSION)/
  HASH:=402162aad30af47e60dbd767fb2e64ca394ace9727ba1f40283641f1d1b91657
endef
$(eval $(call Download,upx))

define Package/protun
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Proton VPN core library
  URL:=https://github.com/ProtonVPN/protun
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libgcc
endef

define Package/protun/description
  Proton VPN core shared library for Linux, with UPX 5.2.1 compression.
  Upstream provides libprotun.so, not a standalone protun VPN command.
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/Cargo.lock $(PKG_BUILD_DIR)/Cargo.lock
endef

define Build/Compile
	+cd $(PKG_BUILD_DIR) && \
		$(CARGO_PKG_VARS) \
		TARGET_AR="$(TARGET_AR)" \
		cargo build -v --locked --lib \
			--profile $(CARGO_PKG_PROFILE) \
			--features linux \
			--target-dir $(PROTUN_CARGO_TARGET_DIR) \
			$(if $(filter --jobserver%,$(PKG_JOBS)),,-j1)
endef

define Package/protun/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PROTUN_CARGO_TARGET_DIR)/$(RUSTC_TARGET_ARCH)/$(CARGO_OUTPUT_DIR)/libprotun.so $(1)/usr/lib/
	$(TARGET_CROSS)strip --strip-unneeded $(1)/usr/lib/libprotun.so

	mkdir -p $(PKG_BUILD_DIR)/upx-bin
	tar -xJf $(DL_DIR)/$(UPX_FILE) -C $(PKG_BUILD_DIR)/upx-bin --strip-components=1
	$(PKG_BUILD_DIR)/upx-bin/upx --ultra --best --force $(1)/usr/lib/libprotun.so
	$(PKG_BUILD_DIR)/upx-bin/upx -t $(1)/usr/lib/libprotun.so
endef

$(eval $(call BuildPackage,protun))

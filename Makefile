include $(TOPDIR)/rules.mk

PKG_NAME:=protun
PKG_VERSION:=3.0.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ProtonVPN/protun.git
PKG_SOURCE_VERSION:=3.0.1
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-3.0
PKG_MAINTAINER:=Your Name <your.email@example.com>

UPX_VERSION:=5.2.1
UPX_FILE:=upx-$(UPX_VERSION)-amd64_linux.tar.xz
UPX_URL:=https://github.com/upx/upx/releases/download/v$(UPX_VERSION)/$(UPX_FILE)

include $(INCLUDE_DIR)/package.mk
include ../../lang/rust/cargo-package.mk

define Package/protun
  SECTION:=net
  CATEGORY:=Network
  TITLE:=ProtonVPN Core Library / ProTUN
  URL:=https://github.com/ProtonVPN/protun
  DEPENDS:=+libc +libgcc +libopenssl +rustc
endef

define Package/protun/description
  Proton VPN Core Libraries packaged for OpenWrt using native Rust support and compressed with UPX 5.2.1.
endef

define Package/protun/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/protun $(1)/usr/bin/
	
	@mkdir -p $(BUILD_DIR)/upx-bin
	@if [ ! -f $(BUILD_DIR)/upx-bin/upx ]; then \
		echo "Downloading UPX $(UPX_VERSION)..."; \
		curl -sL $(UPX_URL) -o $(BUILD_DIR)/$(UPX_FILE); \
		tar -xf $(BUILD_DIR)/$(UPX_FILE) -C $(BUILD_DIR)/upx-bin --strip-components=1; \
		rm -f $(BUILD_DIR)/$(UPX_FILE); \
	fi
	$(BUILD_DIR)/upx-bin/upx --ultra --best --force $(1)/usr/bin/protun || true
endef

$(eval $(call RustPackage,protun))
$(eval $(call BuildPackage,protun))

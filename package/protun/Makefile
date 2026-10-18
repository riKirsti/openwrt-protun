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

# Strip before compression; the packaging stage must not strip a packed ELF.
RSTRIP:=:
CARGO_OUTPUT_DIR:=$(if $(filter dev,$(CARGO_PKG_PROFILE)),debug,$(CARGO_PKG_PROFILE))

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
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libgcc +libopenssl
endef

define Package/protun/description
  Proton VPN core shared library for Linux.
  Upstream provides libprotun.so, not a standalone protun VPN command.
endef

# Upstream does not ship Cargo.lock. Build only the library, rather than
# cargo install's uniffi-bindgen development tool.
define Build/Compile
	cd $(PKG_BUILD_DIR) && \
		$(CARGO_PKG_VARS) \
		TARGET_AR="$(TARGET_AR)" \
		cargo build -v --lib \
			--profile $(CARGO_PKG_PROFILE) \
			--features linux \
			--target-dir $(PKG_BUILD_DIR)/target \
			$(if $(filter --jobserver%,$(PKG_JOBS)),,-j1)
endef

define Package/protun/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/$(CARGO_OUTPUT_DIR)/libprotun.so $(1)/usr/lib/
	$(TARGET_CROSS)strip --strip-unneeded $(1)/usr/lib/libprotun.so
	mkdir -p $(PKG_BUILD_DIR)/upx-bin
	tar -xJf $(DL_DIR)/$(UPX_FILE) -C $(PKG_BUILD_DIR)/upx-bin --strip-components=1
	cp $(1)/usr/lib/libprotun.so $(PKG_BUILD_DIR)/libprotun-packed.so
	if $(PKG_BUILD_DIR)/upx-bin/upx --ultra --best --force $(PKG_BUILD_DIR)/libprotun-packed.so; then \
		$(PKG_BUILD_DIR)/upx-bin/upx -t $(PKG_BUILD_DIR)/libprotun-packed.so && \
		mv $(PKG_BUILD_DIR)/libprotun-packed.so $(1)/usr/lib/libprotun.so; \
	else \
		echo "WARNING: UPX could not compress libprotun.so; keeping the stripped library." >&2; \
		rm -f $(PKG_BUILD_DIR)/libprotun-packed.so; \
	fi
endef

$(eval $(call BuildPackage,protun))

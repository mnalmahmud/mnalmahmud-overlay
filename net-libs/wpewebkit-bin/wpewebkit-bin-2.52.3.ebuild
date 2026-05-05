EAPI=8

inherit multilib unpacker

DESCRIPTION="Embeddable web content engine"
HOMEPAGE="https://wpewebkit.org https://packages.debian.org/sid/libwpewebkit-2.0-1"
SRC_URI="
	amd64? ( https://deb.debian.org/debian/pool/main/w/wpewebkit/libwpewebkit-2.0-1_${PV}-1_amd64.deb -> ${P}-amd64.deb )
	arm64? ( https://deb.debian.org/debian/pool/main/w/wpewebkit/libwpewebkit-2.0-1_${PV}-1_arm64.deb -> ${P}-arm64.deb )
"
LICENSE="
	AFL-2.0
	Apache-2.0
	Apache-2.0-WITH-LLVM-exception
	BSD
	BSD-2
	BSD-2-Views
	BSD-Source-Code
	BSL-1.0
	bzip2
	GPL-2+
	GPL-2-only
	GPL-3-only-WITH-Autoconf-exception
	GPL-3+-WITH-Bison-exception
	ICU
	ISC
	LGPL-2.1
	LGPL-2.1+
	MIT
	MPL-1.1
	MPL-2.0
	NCSA
	OFL-1.1
	SunPro
	Unicode
"
SLOT="2.0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="mirror strip"
QA_PREBUILT="usr/lib*/*"
RDEPEND="
    app-accessibility/at-spi2-core:2
	dev-db/sqlite:3
	dev-libs/atk
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/hyphen
	dev-libs/icu:=
	dev-libs/libgcrypt:0=
	dev-libs/libinput
	dev-libs/libtasn1:=
	dev-libs/libxml2:2
	dev-libs/libxslt
	dev-libs/wayland
	gui-libs/libwpe:1.0
	gui-libs/wpebackend-fdo:1.0
	media-fonts/font-misc-misc
	media-libs/fontconfig
	media-libs/freetype
	media-libs/gst-plugins-bad:1.0
	media-libs/gst-plugins-base:1.0
	media-libs/gstreamer:1.0
	media-libs/harfbuzz:=[icu]
	media-libs/lcms:2
	media-libs/libavif:=
	media-libs/libepoxy
	media-libs/libjpeg-turbo:=
	media-libs/libjxl:=
	media-libs/libpng:0=
	media-libs/libwebp:=
	media-libs/mesa
	media-libs/openjpeg:2=
	media-libs/woff2
	net-libs/libsoup:3.0
	sys-apps/bubblewrap
	|| ( sys-apps/systemd sys-auth/elogind )
	sys-apps/xdg-dbus-proxy
	sys-devel/gcc
	sys-libs/libseccomp
	sys-libs/zlib
	x11-libs/cairo
	x11-libs/libdrm
	x11-libs/libxkbcommon
"

S="${WORKDIR}"

src_install() {
	local deb_libdir="usr/lib/$(usex amd64 x86_64 aarch64)-linux-gnu"
    local gentoo_libdir="/usr/$(get_libdir)"

    if [[ -d "${deb_libdir}" ]]; then
        dodir "${gentoo_libdir}"
        cp -a "${deb_libdir}"/* "${ED}${gentoo_libdir}/" || die "Failed to copy lib directory"
    fi

    if [[ -d "usr/share" ]]; then
        insinto /usr/share
        doins -r usr/share/*
    fi
}

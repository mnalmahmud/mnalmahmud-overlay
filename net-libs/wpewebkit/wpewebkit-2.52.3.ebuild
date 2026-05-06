EAPI=8

PYTHON_COMPAT=( python3_{10..14} )
inherit cmake flag-o-matic python-any-r1 toolchain-funcs

DESCRIPTION="Embeddable web content engine"
HOMEPAGE="https://wpewebkit.org"
SRC_URI="https://wpewebkit.org/releases/${P}.tar.xz"
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
IUSE="-doc +introspection -minibrowser -sysprof systemd"

BDEPEND="
	${PYTHON_DEPS}
	dev-lang/ruby
	dev-build/cmake
	dev-build/ninja
	introspection? ( dev-libs/gobject-introspection )
	dev-libs/wayland-protocols
	doc? ( dev-util/gi-docgen )
	dev-util/gperf
	dev-util/unifdef
	llvm-core/clang
	llvm-core/lld
	sys-devel/bison
	sys-devel/flex
"

RDEPEND="
    app-accessibility/at-spi2-core:2
	dev-db/sqlite:3
	dev-libs/atk
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/hyphen
	dev-libs/icu:=
	dev-libs/libgcrypt:=
	dev-libs/libinput
	dev-libs/libtasn1:=
	dev-libs/libxml2:2
	dev-libs/libxslt
	dev-libs/wayland
	sysprof? ( dev-util/sysprof-capture:4 )
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
	media-libs/libpng:=
	media-libs/libwebp:=
	media-libs/mesa
	media-libs/openjpeg:2=
	media-libs/woff2
	net-libs/libsoup:3.0
	sys-apps/bubblewrap
    systemd? ( sys-apps/systemd )
	sys-apps/xdg-dbus-proxy
	sys-libs/libseccomp
	sys-libs/zlib
	x11-libs/cairo
	x11-libs/libdrm
	x11-libs/libxkbcommon
"
DEPEND="${RDEPEND}"

src_configure() {
	# -DCMAKE_BUILD_TYPE=Release
	local mycmakeargs=(
		-DENABLE_DOCUMENTATION=$(usex doc)
		-DENABLE_INTROSPECTION=$(usex introspection)
		-DENABLE_MINIBROWSER=$(usex minibrowser)
		-DUSE_SYSTEM_SYSPROF_CAPTURE=$(usex sysprof)
		-DENABLE_JOURNALD_LOG=$(usex systemd)
		-DENABLE_SPEECH_SYNTHESIS=OFF
		-DENABLE_WPE_PLATFORM=ON
		-DPORT=WPE
		-DUSE_FLITE=OFF
		-DUSE_LIBBACKTRACE=OFF
	)

	export CC="clang" CXX="clang++"
	export AR="llvm-ar" NM="llvm-nm" RANLIB="llvm-ranlib"
    append-ldflags "-fuse-ld=lld"

	filter-flags "-D_FORTIFY_SOURCE=3"
    append-flags "-D_FORTIFY_SOURCE=2"

    append-flags -fcf-protection=none

	cmake_src_configure
}

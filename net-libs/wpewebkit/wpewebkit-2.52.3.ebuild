EAPI=8

CMAKE_MAKEFILE_GENERATOR="ninja"
PYTHON_COMPAT=( python3_{10..14} )
USE_RUBY="ruby32 ruby33 ruby34 ruby40"
inherit cmake flag-o-matic python-any-r1 ruby-single toolchain-funcs

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
IUSE="+accessibility debug doc examples experimental +gamepad +gstreamer +introspection +jpegxl qt +sandbox sysprof systemd test +webdriver +webrtc X"
REQUIRED_USE="webrtc? ( gstreamer )"

# doc X

BDEPEND="
	${PYTHON_DEPS}
	${RUBY_DEPS}
	dev-build/cmake
	dev-build/ninja
	dev-lang/perl
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

# ATK: /usr/include/atk-1.0 minimum required is "2.16.0"
RDEPEND="
	accessibility? (
	    app-accessibility/at-spi2-core
	)
	dev-db/sqlite:3
	dev-libs/expat
	>=dev-libs/glib-2.70.0:2
	dev-libs/hyphen
	>=dev-libs/icu-70.1:=
	>=dev-libs/libgcrypt-1.7.0
	>=dev-libs/libinput-1.19.0
	gamepad? ( >=dev-libs/libmanette-0.2.4 )
	dev-libs/libtasn1
	>=dev-libs/libxml2-2.9.13:=
	>=dev-libs/libxslt-1.1.13
	webrtc? (
		dev-libs/openssl
		>=media-plugins/gst-plugins-webrtc-1.24.10:1.0
	)
	>=dev-libs/wayland-1.20
	qt? (
		dev-qt/qtcore:6
		dev-qt/qtdeclarative:6
		dev-qt/qtgui:6
		dev-qt/qttest:6
		>=gui-libs/wpebackend-fdo-1.0
	)
	sysprof? ( dev-util/sysprof-capture:4 )
	gui-libs/libwpe:1.0
	media-fonts/font-misc-misc
	>=media-libs/fontconfig-2.16.0:=
	>=media-libs/freetype-2.14.0:=
	gstreamer? (
		>=media-libs/gstreamer-1.18.4:1.0
		>=media-libs/gst-plugins-bad-1.18.4:1.0
		>=media-libs/gst-plugins-base-1.18.4:1.0[egl]
        >=media-plugins/gst-plugins-libav-1.18.4:1.0
		>=media-plugins/gst-plugins-opus-1.18.4:1.0
		>=media-plugins/gst-plugins-vpx-1.18.4:1.0
	)
	>=media-libs/harfbuzz-2.7.4:=[icu(+)]
	media-libs/lcms:2
	>=media-libs/libavif-0.9.0
	>=media-libs/libepoxy-1.5.4:=
	media-libs/libjpeg-turbo
	jpegxl? ( >=media-libs/libjxl-0.7.0 )
	media-libs/libpng:=
	media-libs/libwebp:=
	media-libs/mesa
	>=media-libs/woff2-1.0.2
	>=net-libs/libsoup-3.0.0:3.0
	sandbox? ( sys-apps/bubblewrap )
    systemd? ( sys-apps/systemd )
	sys-apps/xdg-dbus-proxy
	sys-libs/libseccomp
	sys-libs/zlib
	>=x11-libs/cairo-1.18.0:=[X?]
	x11-libs/libdrm
	x11-libs/libxkbcommon
"
DEPEND="${RDEPEND}"

pkg_setup() {
    python-any-r1_pkg_setup
    ruby-single_pkg_setup
}

src_configure() {
    filter-lto

    if ! use debug; then
        append-cppflags -DNDEBUG
    fi
	local mycmakeargs=(
	    -DENABLE_ACCESSIBILITY_ISOLATED_TREE=OFF
	    -DENABLE_API_TESTS=$(usex test ON OFF)
		-DENABLE_BUBBLEWRAP_SANDBOX=$(usex sandbox ON OFF)
		-DENABLE_DOCUMENTATION=$(usex doc ON OFF)
		-DENABLE_EXPERIMENTAL_FEATURES=$(usex experimental ON OFF)
		-DENABLE_GAMEPAD=$(usex gamepad ON OFF)
		-DENABLE_INTROSPECTION=$(usex introspection ON OFF)
		-DENABLE_JOURNALD_LOG=$(usex systemd ON OFF)
		-DENABLE_LAYOUT_TESTS=$(usex test ON OFF)
		-DENABLE_MINIBROWSER=$(usex examples ON OFF)
		-DENABLE_SPEECH_SYNTHESIS=OFF
		-DENABLE_VIDEO=$(usex gstreamer ON OFF)
		-DENABLE_WEBDRIVER=$(usex webdriver ON OFF)
		-DENABLE_WEB_AUDIO=$(usex gstreamer ON OFF)
		-DENABLE_WEB_RTC=$(usex webrtc ON OFF)
		-DENABLE_MEDIA_STREAM=$(usex webrtc ON OFF)
		-DENABLE_WPE_PLATFORM=ON
		-DENABLE_WPE_QT_API=$(usex qt ON OFF)
		-DENABLE_XSLT=ON
		-DPORT=WPE
		-DRUBY_EXECUTABLE="${RUBY}"
		-DSHOULD_INSTALL_JS_SHELL=ON
		-DUSE_ATK=$(usex accessibility ON OFF)
		-DUSE_FLITE=OFF
		-DUSE_JPEGXL=$(usex jpegxl ON OFF)
		-DUSE_LIBBACKTRACE=OFF
		-DUSE_SYSTEM_SYSPROF_CAPTURE=$(usex sysprof ON OFF)
	)

    CC=${CHOST}-clang CXX=${CHOST}-clang++
    AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib
    tc-export CC CXX AR NM RANLIB
    append-ldflags "-fuse-ld=lld"

    replace-flags "-D_FORTIFY_SOURCE=3" "-D_FORTIFY_SOURCE=2"

    append-flags -fcf-protection=none

	cmake_src_configure
}

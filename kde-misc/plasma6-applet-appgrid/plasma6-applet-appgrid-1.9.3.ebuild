# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake ecm

DESCRIPTION="A modern fullscreen application launcher for KDE Plasma"
HOMEPAGE="https://github.com/xarbit/plasma6-applet-appgrid"
SRC_URI="https://github.com/xarbit/plasma6-applet-appgrid/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="GPL-2+"
SLOT="6"
KEYWORDS="~amd64 ~arm64"
IUSE="X test"
DEPEND="
    dev-libs/appstream[qt6]
	dev-qt/qtbase:6
	dev-qt/qtdeclarative:6
	kde-frameworks/kcmutils:6
	kde-frameworks/kcoreaddons:6
	kde-frameworks/kdeclarative:6
	kde-frameworks/ki18n:6
	kde-frameworks/kiconthemes:6
	kde-frameworks/kio:6
	kde-frameworks/kirigami:6
	kde-frameworks/kglobalaccel:6
	kde-frameworks/kpackage:6
	kde-frameworks/krunner:6
	kde-frameworks/kservice:6
	kde-frameworks/ksvg:6
	kde-frameworks/kwindowsystem:6
	kde-plasma/layer-shell-qt:6
	kde-plasma/libplasma:6
	kde-plasma/plasma-activities-stats:6
"
RDEPEND="${DEPEND}
	kde-plasma/plasma-workspace:6[X?]
"

BDEPEND="
    sys-devel/gettext
"

src_configure() {
	local mycmakeargs=(
		-DBUILD_TESTING=$(usex test ON OFF)
		-DENABLE_X11=$(usex X ON OFF)
	)
	
	cmake_src_configure
}

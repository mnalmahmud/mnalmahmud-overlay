# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10..12} )
inherit cmake optfeature python-single-r1

DESCRIPTION="Latte-Dock and WM status bar customization features for the KDE Plasma panels"
HOMEPAGE="https://github.com/luisbocanegra/plasma-panel-colorizer"
SRC_URI="https://github.com/luisbocanegra/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3+"
SLOT="6"
KEYWORDS="~amd64"
IUSE=""
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# Note: libplasma is required for Plasma 6
DEPEND="
	kde-plasma/libplasma:6
"
RDEPEND="
	${DEPEND}
	${PYTHON_DEPS}
	$(python_gen_cond_dep '
		dev-python/dbus-python[${PYTHON_USEDEP}]
		dev-python/pygobject:3[${PYTHON_USEDEP}]
	')
"
BDEPEND="
	${PYTHON_DEPS}
	kde-frameworks/extra-cmake-modules:0
	sys-devel/gettext
"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_prepare() {
	cmake_src_prepare

	# Generate i18n files using the provided python script before configuring
	einfo "Generating i18n files..."
	${EPYTHON} ./kpac i18n --no-merge || die "i18n generation failed"
}

src_configure() {
	local mycmakeargs=(
		-DINSTALL_PLASMOID=ON
		-DBUILD_PLUGIN=ON
	)
	cmake_src_configure
}

src_install() {
	cmake_src_install

	# Set execution permissions for the UI tools
	local tools_dir="${ED}/usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/tools"
	
	if [[ -d "${tools_dir}" ]]; then
		fperms 755 /usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/tools/list_presets.sh
		fperms 755 /usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/tools/gdbus_get_signal.sh
	else
		ewarn "Tools directory not found, skipping permission changes."
	fi
}

pkg_postinst() {
	optfeature "take preset preview support" kde-apps/spectacle
}

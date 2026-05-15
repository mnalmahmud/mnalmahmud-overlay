# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10..14} )

inherit cmake optfeature python-single-r1

DESCRIPTION="Latte-Dock and WM status bar customization features for the KDE Plasma panels"
HOMEPAGE="https://github.com/luisbocanegra/plasma-panel-colorizer"
SRC_URI="https://github.com/luisbocanegra/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="GPL-3+"
SLOT="6"
KEYWORDS="~amd64 ~arm64"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
DEPEND="
	kde-plasma/libplasma:6
"
RDEPEND="
	${DEPEND}
	${PYTHON_DEPS}
	kde-plasma/plasma-workspace:6
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

src_prepare() {
	cmake_src_prepare

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

    local plasmoid_dir="/usr/share/plasma/plasmoids/luisbocanegra.panel.colorizer"
    local tools_dir="${ED}${plasmoid_dir}/contents/ui/tools"

	if [[ -d "${tools_dir}" ]]; then
        chmod +x "${tools_dir}"/*.sh || die
	else
		ewarn "Tools directory not found, skipping permission changes."
	fi
	python_fix_shebang "${ED}${plasmoid_dir}"
	python_optimize "${ED}${plasmoid_dir}"
}

pkg_postinst() {
	optfeature "take preset preview support" kde-plasma/spectacle
}

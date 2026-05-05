# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd unpacker xdg fcaps

DESCRIPTION="Windscribe GUI tool for Linux"
HOMEPAGE="https://github.com/Windscribe/Desktop-App"
SRC_URI="
	amd64? ( https://github.com/Windscribe/Desktop-App/releases/download/v${PV}/windscribe_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( https://github.com/Windscribe/Desktop-App/releases/download/v${PV}/windscribe_${PV}_arm64.deb -> ${P}-arm64.deb )
"
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="mirror strip"
QA_PREBUILT="opt/windscribe/*"
RDEPEND="
	acct-group/windscribe
	app-admin/sudo
	dev-libs/glib:2
	media-libs/fontconfig
	media-libs/freetype
	media-libs/libglvnd
	net-dns/c-ares
	net-firewall/nftables
	sys-apps/dbus
	sys-apps/net-tools
	sys-apps/shadow
	sys-auth/polkit
	sys-libs/glibc
	sys-libs/zlib
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
	x11-themes/hicolor-icon-theme
"
S="${WORKDIR}"
FILECAPS=( cap_setgid+ep opt/windscribe/Windscribe )

src_install() {
	dodir /opt
	cp -a opt/windscribe "${ED}/opt/" || die
    fowners -R root:root /opt/windscribe

	insinto /usr/share
	doins -r usr/share/*
	insinto /etc
	doins -r etc/*

	if [[ -d usr/polkit-1/actions ]]; then
		insinto /usr/share/polkit-1/actions
		doins usr/polkit-1/actions/*
	fi

	dosym -r /opt/windscribe/windscribe-cli /usr/bin/windscribe-cli

    insinto /etc/windscribe
    echo "$(usex arm64 linux_deb_arm64 linux_deb_x64)" > "${T}/platform" || die
    doins "${T}/platform"

	insinto "$(systemd_get_systempresetdir)"
	doins usr/lib/systemd/system-preset/69-windscribe-helper.preset

	systemd_dounit usr/lib/systemd/system/windscribe-helper.service
	newinitd "${FILESDIR}/windscribe-helper.initd" windscribe-helper
}

pkg_prerm() {
	if [[ -x "${EROOT}/opt/windscribe/helper" ]]; then
		ebegin "Resetting MAC addresses via Windscribe helper"
		"${EROOT}/opt/windscribe/helper" --reset-mac-addresses
		eend $?
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	fcaps_pkg_postinst

	einfo "1. Add your user to the group to use the GUI:"
	einfo "   gpasswd -a <user> windscribe"
	einfo
	einfo "2. To enable the background service:"
	einfo "   systemd: systemctl enable --now windscribe-helper"
	einfo "   OpenRC: rc-update add windscribe-helper default"
	einfo
}

# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd unpacker xdg fcaps

DESCRIPTION="Windscribe GUI tool for Linux"
HOMEPAGE="https://windscribe.com/guides/linux https://github.com/Windscribe/Desktop-App"
SRC_URI="https://github.com/Windscribe/Desktop-App/releases/download/v${PV}/windscribe_${PV}_amd64.deb"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

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
DEPEND=""
BDEPEND=""

S="${WORKDIR}"

FILECAPS=( cap_setgid+ep opt/windscribe/Windscribe )

src_prepare() {
	default

	cat <<- 'EOF' > windscribe-helper.initd
		#!/sbin/openrc-run

		name="Windscribe Helper"
		description="Windscribe VPN Background Service"
		command="/opt/windscribe/helper"
		command_background="true"
		pidfile="/run/windscribe-helper.pid"

		depend() {
			need net
			use dns
		}
	EOF
}

src_install() {
	dodir /opt /usr/share /etc /etc/windscribe

	cp -a opt/windscribe "${ED}/opt/" || die
	cp -a usr/share/* "${ED}/usr/share/" || die
	cp -a etc/* "${ED}/etc/" || die

	if [[ -d usr/polkit-1 ]]; then
		cp -a usr/polkit-1/* "${ED}/usr/share/polkit-1/" || die
	fi

	dosym -r /opt/windscribe/windscribe-cli /usr/bin/windscribe-cli

	echo "linux_deb_x64" > "${ED}/etc/windscribe/platform" || die

	keepdir /var/tmp/windscribe

	insinto "$(systemd_get_systempresetdir)"
	doins usr/lib/systemd/system-preset/69-windscribe-helper.preset

	systemd_dounit usr/lib/systemd/system/windscribe-helper.service
	newinitd windscribe-helper.initd windscribe-helper
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

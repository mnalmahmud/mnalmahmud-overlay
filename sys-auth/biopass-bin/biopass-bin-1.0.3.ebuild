# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

DESCRIPTION="Modern, multi-modal biometric authentication (Binary Release)"
HOMEPAGE="https://github.com/TickLabVN/biopass"
SRC_URI="https://github.com/TickLabVN/biopass/releases/download/${PV}/biopass_${PV}_amd64.deb"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# Prevent Portage from stripping symbols, which can break pre-compiled binaries
RESTRICT="strip"

RDEPEND="
    media-libs/gst-plugins-good
    net-misc/curl
    net-libs/webkit-gtk:4.1
    sys-auth/fprintd
    sys-libs/pam
    x11-libs/gtk+:3
    x11-themes/hicolor-icon-theme
"
DEPEND="${RDEPEND}"
BDEPEND="dev-util/patchelf"

S="${WORKDIR}"

src_unpack() {
    unpack_deb ${A}
}

src_install() {
    dobin usr/bin/biopass

    patchelf --set-rpath "/usr/$(get_libdir)/biopass" usr/bin/biopass-helper
    dobin usr/bin/biopass-helper

    exeinto "/usr/$(get_libdir)/biopass"
    for libfile in usr/lib/biopass/*; do
        patchelf --set-rpath "/usr/$(get_libdir)/biopass" "${libfile}"
        doexe "${libfile}"
    done

    exeinto /$(get_libdir)/security
    doexe lib/security/libbiopass_pam.so

    insinto /etc/ld.so.conf.d
    doins -r etc/ld.so.conf.d/.

    insinto /usr/share
    doins -r usr/share/.
}

pkg_postinst() {
    xdg_desktop_database_update
    xdg_icon_cache_update

    einfo "Updating dynamic linker cache..."
    /sbin/ldconfig

    einfo "Biopass: Running AI model downloader..."
    bash "${EPREFIX}/usr/share/com.ticklab.biopass/download_models.sh" || ewarn "Biopass: Model download failed. You may need to run it manually later."

    einfo "Biopass is now installed."
}

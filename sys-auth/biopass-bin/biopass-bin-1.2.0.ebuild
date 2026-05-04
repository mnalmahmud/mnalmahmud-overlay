# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit multilib pam unpacker xdg

DESCRIPTION="Modern, multi-modal biometric authentication"
HOMEPAGE="https://github.com/TickLabVN/biopass"
SRC_URI="https://github.com/TickLabVN/biopass/releases/download/${PV}/biopass_${PV}_amd64.deb -> ${P}.deb"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RESTRICT="strip"

QA_PREBUILT="*"

RDEPEND="
    media-libs/gst-plugins-good
    net-libs/webkit-gtk:4.1
    net-misc/curl
    sys-auth/fprintd
    sys-libs/pam
    x11-libs/gtk+:3
    x11-themes/hicolor-icon-theme
"
BDEPEND="dev-util/patchelf"

S="${WORKDIR}"

src_install() {
    dobin usr/bin/biopass

    patchelf --set-rpath "${EPREFIX}/usr/$(get_libdir)/biopass" usr/bin/biopass-helper || die
    dobin usr/bin/biopass-helper

    exeinto "/usr/$(get_libdir)/biopass"
    for libfile in usr/lib/biopass/*; do
        if [[ "${libfile}" == usr/lib/biopass/libbiopass_*.so ]]; then
            patchelf --set-rpath "${EPREFIX}/usr/$(get_libdir)/biopass" "${libfile}" || die
        fi
        doexe "${libfile}"
    done

    dopammod lib/security/libbiopass_pam.so

    insinto /usr/share
    doins -r usr/share/*
}

pkg_postinst() {
    xdg_pkg_postinst

    einfo "Biopass core binaries are installed."
    einfo ""
    ewarn "ACTION REQUIRED: To use the AI features, you must manually download the models."
    ewarn "Run the following command as root:"
    ewarn "  bash ${EPREFIX}/usr/share/com.ticklab.biopass/download_models.sh"
}

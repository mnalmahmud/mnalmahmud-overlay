# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	aho-corasick@0.7.18
	autocfg@1.1.0
	bitflags@2.4.2
	cfg-if@1.0.0
	chrono@0.4.19
	error-chain@0.12.4
	getopts@0.2.21
	getrandom@0.2.6
	hostname@0.3.1
	itoa@1.0.2
	libc@0.2.153
	log@0.4.17
	match_cfg@0.1.0
	memchr@2.5.0
	nix@0.27.1
	num-integer@0.1.45
	num-traits@0.2.15
	num_threads@0.1.6
	pam-sys@0.5.6
	pam@0.7.0
	ppv-lite86@0.2.16
	rand@0.8.5
	rand_chacha@0.3.1
	rand_core@0.6.3
	regex-syntax@0.6.27
	regex@1.7.1
	rpassword@7.3.1
	rtoolbox@0.0.2
	syslog@6.0.1
	time@0.1.43
	time@0.3.9
	unicode-width@0.1.9
	users@0.8.1
	uzers@0.11.3
	version_check@0.9.4
	wasi@0.10.2+wasi-snapshot-preview1
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-x86_64-pc-windows-gnu@0.4.0
	winapi@0.3.9
	windows-sys@0.48.0
	windows-targets@0.48.5
	windows_aarch64_gnullvm@0.48.5
	windows_aarch64_msvc@0.48.5
	windows_i686_gnu@0.48.5
	windows_i686_msvc@0.48.5
	windows_x86_64_gnu@0.48.5
	windows_x86_64_gnullvm@0.48.5
	windows_x86_64_msvc@0.48.5
"

inherit bash-completion-r1 cargo pam

DESCRIPTION="please, a polite regex-first sudo alternative"
HOMEPAGE="https://gitlab.com/edneville/please"
SRC_URI="
	https://gitlab.com/edneville/please/-/archive/v${PV}/please-v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="GPL-3+"
# Dependent crate licenses
LICENSE+=" Apache-2.0 MIT"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="sys-libs/pam"
RDEPEND="${DEPEND}"

S="${WORKDIR}/please-v${PV}"

src_test() {
	# test_expand* fails; needs nightly rust
	cargo_src_test -- --skip test_expand
}

src_install() {
	cargo_src_install

	fperms 4755 /usr/bin/please /usr/bin/pleaseedit

	dodoc README.md examples/please.ini
	doman man/please.1 man/please.ini.5

	insinto /etc
	insopts -m0600
	doins examples/please.ini

	diropts -m0700
	keepdir /etc/please.d

	newbashcomp completions/bash/please please
	bashcomp_alias please pleaseedit

	insinto /usr/share/zsh/site-function
	doins completions/zsh/_please
	fowners root:root /usr/share/zsh/site-functions/_please
	fperms 0644 /usr/share/zsh/site-functions/_please

	pamd_mimic_system please auth account session
	pamd_mimic_system pleaseedit auth account session
}

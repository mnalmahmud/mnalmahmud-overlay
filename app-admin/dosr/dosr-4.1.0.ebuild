# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

RUST_MIN_VER="1.93.0"
CRATES="
	aho-corasick@1.1.5
	anstyle@1.0.14
	anyhow@1.0.104
	bitflags@1.3.2
	bitflags@2.13.2
	block-buffer@0.12.1
	bon-macros@3.10.1
	bon@3.10.1
	bstr@1.13.1
	bytecheck@0.8.3
	bytecheck_derive@0.8.3
	capctl@0.2.4
	cbor4ii@1.2.3
	cfg-if@1.0.4
	cfg_aliases@0.2.2
	clap@4.6.6
	clap_builder@4.6.6
	clap_derive@4.6.4
	clap_lex@1.1.0
	const_format@0.2.36
	const_format_proc_macros@0.2.34
	const_panic@0.2.17
	cpufeatures@0.3.1
	crossbeam-utils@0.8.23
	crypto-common@0.2.2
	darling@0.24.1
	darling_core@0.24.1
	darling_macro@0.24.1
	defmt-macros@1.1.1
	defmt-parser@1.0.0
	defmt@1.1.1
	digest@0.11.3
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	env_filter@2.0.0
	env_logger@0.11.11
	equivalent@1.0.2
	glob@0.3.4
	globset@0.4.20
	hashbrown@0.17.1
	heck@0.5.0
	hex@0.4.3
	hybrid-array@0.4.15
	ident_case@1.0.1
	indexmap@2.14.2
	itoa@1.0.18
	jiff-core@0.1.0
	jiff-static@0.2.37
	jiff@0.2.37
	konst@0.2.20
	konst@0.4.3
	konst_macro_rules@0.2.19
	konst_proc_macros@0.4.1
	landlock@0.4.7
	libc@0.2.189
	libpam-sys-helpers@0.2.0
	libpam-sys-impls@0.2.0
	libpam-sys@0.2.0
	libseccomp-sys@0.3.0
	libseccomp@0.4.0
	log@0.4.34
	memchr@2.8.3
	munge@0.4.7
	munge_macro@0.4.7
	nix@0.31.3
	nonstick2@0.1.3
	pest@2.9.1
	pest_derive@2.9.1
	pest_generator@2.9.1
	pest_meta@2.9.1
	pkg-config@0.3.34
	portable-atomic-util@0.2.8
	portable-atomic@1.15.0
	prettyplease@0.3.0
	proc-macro2@1.0.107
	ptr_meta@0.3.2
	ptr_meta_derive@0.3.2
	quote@1.0.47
	rancor@0.1.3
	regex-automata@0.4.18
	regex-syntax@0.8.11
	regex@1.13.1
	rend@0.5.4
	ringbuf@0.4.8
	rkyv@0.8.18
	rkyv_derive@0.8.18
	semver@1.0.28
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.151
	serde_test@1.0.177
	sha2@0.11.0
	shell-words@1.1.1
	simdutf8@0.1.5
	strsim@0.11.1
	syn@2.0.119
	syn@3.0.5
	test-log-core@0.2.21
	test-log-macros@0.2.21
	test-log@0.2.21
	thiserror-impl@2.0.20
	thiserror@2.0.20
	tinyvec@1.13.3
	typenum@1.20.1
	typewit@1.15.2
	ucd-trie@0.1.7
	unicode-ident@1.0.24
	unicode-xid@0.2.6
	zmij@1.0.23
"

inherit cargo fcaps pam

DESCRIPTION="A better alternative to sudo(-rs)/su • Fast • Memory-safe • Security-oriented"
HOMEPAGE="https://lechatp.github.io/RootAsRole/"
SRC_URI="
	https://github.com/LeChatP/RootAsRole/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"
LICENSE="LGPL-3+"
# Dependent crate licenses
LICENSE+=" MIT Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="~amd64"
IUSE="man test"
RESTRICT="!test? ( test )"

BDEPEND="
	virtual/pkgconfig
	man? ( app-text/pandoc )
"

DEPEND="
	dev-libs/libpcre2
	sys-fs/e2fsprogs
	sys-libs/libseccomp
	sys-libs/pam
"
RDEPEND="${DEPEND}"

FILECAPS=(
	"=p" usr/bin/dosr
)

S="${WORKDIR}/RootAsRole-${PV}"

src_configure() {
    local myfeatures=(finder editor)
    cargo_src_configure
}

src_compile() {
	cargo_src_compile

	if use man; then
		einfo "Building man pages..."
		mkdir -p man/{en,fr} || die "Failed to create man directories"
		pandoc -s -t man resources/man/en_US.md -o man/en/dosr.8 || die "Failed to build en man page"
		pandoc -s -t man resources/man/fr_FR.md -o man/fr/dosr.8 || die "Failed to build fr man page"
	fi
}

src_test() {
	export RAR_AUTHENTICATION="skip"
	export RAR_CFG_PATH="target/rootasrole.json"
	export SKIP_BUILD="true"

	cargo_src_test --all-features --bin dosr --bin chsr
}

src_install() {
    cargo_src_install

    pamd_mimic_system dosr auth account session

    insinto /etc/security
    newins resources/rootasrole.json rootasrole.json
    fperms 0440 /etc/security/rootasrole.json

	insinto /usr/share/rootasrole
	newins resources/rootasrole.json default.json

	if use man; then
		doman man/en/dosr.8
		doman  man/fr/dosr.8

		dosym -r dosr.8 /usr/share/man/man8/chsr.8
		dosym -r dosr.8 /usr/share/man/fr/man8/chsr.8
	fi
	einstalldocs
}

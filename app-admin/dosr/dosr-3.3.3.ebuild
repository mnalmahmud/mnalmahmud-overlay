# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

RUST_MIN_VER="1.93.0"
CRATES="
	aho-corasick@1.1.4
	android_system_properties@0.1.5
	anstream@0.6.21
	anstyle-parse@0.2.7
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.13
	anyhow@1.0.101
	autocfg@1.5.0
	bitflags@1.3.2
	bitflags@2.11.0
	block-buffer@0.10.4
	bon-macros@3.9.0
	bon@3.9.0
	bumpalo@3.19.1
	capctl@0.2.4
	cbor4ii@1.2.2
	cc@1.2.56
	cfg-if@1.0.4
	cfg_aliases@0.2.1
	chrono@0.4.43
	clap@4.5.58
	clap_builder@4.5.58
	clap_derive@4.5.55
	clap_lex@1.0.0
	colorchoice@1.0.4
	const_format@0.2.35
	const_format_proc_macros@0.2.34
	const_panic@0.2.15
	core-foundation-sys@0.8.7
	cpufeatures@0.2.17
	crypto-common@0.1.7
	darling@0.23.0
	darling_core@0.23.0
	darling_macro@0.23.0
	deranged@0.5.6
	derivative@2.2.0
	digest@0.10.7
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	env_filter@1.0.0
	env_logger@0.11.9
	equivalent@1.0.2
	errno@0.3.14
	error-chain@0.12.4
	find-msvc-tools@0.1.9
	generic-array@0.14.7
	getrandom@0.3.4
	glob@0.3.3
	hashbrown@0.16.1
	heck@0.5.0
	hex@0.4.3
	hostname@0.3.1
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.65
	ident_case@1.0.1
	indexmap@2.13.0
	is_terminal_polyfill@1.70.2
	itoa@1.0.17
	jiff-static@0.2.20
	jiff@0.2.20
	jobserver@0.1.34
	js-sys@0.3.85
	konst@0.3.16
	konst_kernel@0.3.15
	konst_proc_macros@0.3.10
	landlock@0.4.4
	libc@0.2.182
	libpam-sys-helpers@0.2.0
	libpam-sys-impls@0.2.0
	libpam-sys@0.2.0
	libseccomp-sys@0.2.1
	libseccomp@0.3.0
	linked-hash-map@0.5.6
	linked_hash_set@0.1.6
	linux-raw-sys@0.4.15
	lock_api@0.4.14
	log@0.4.29
	match_cfg@0.1.0
	memchr@2.8.0
	nix@0.29.0
	nix@0.30.1
	nonstick@0.1.1
	num-conv@0.2.0
	num-traits@0.2.19
	num_threads@0.1.7
	once_cell@1.21.3
	once_cell_polyfill@1.70.2
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	pcre2-sys@0.2.10
	pcre2@0.2.11
	pest@2.8.6
	pest_derive@2.8.6
	pest_generator@2.8.6
	pest_meta@2.8.6
	pkg-config@0.3.32
	portable-atomic-util@0.2.5
	portable-atomic@1.13.1
	powerfmt@0.2.0
	prettyplease@0.2.37
	proc-macro2@1.0.106
	pty-process@0.4.0
	quote@1.0.44
	r-efi@5.3.0
	redox_syscall@0.5.18
	regex-automata@0.4.14
	regex-syntax@0.8.9
	regex@1.12.3
	rustix@0.38.44
	rustversion@1.0.22
	scc@2.4.0
	scopeguard@1.2.0
	sdd@3.0.10
	semver@1.0.27
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.149
	serde_spanned@0.6.9
	serde_test@1.0.177
	serial_test@3.3.1
	serial_test_derive@3.3.1
	sha2@0.10.9
	shell-words@1.1.1
	shlex@1.3.0
	smallvec@1.15.1
	strsim@0.11.1
	strum@0.26.3
	strum_macros@0.26.4
	syn@1.0.109
	syn@2.0.116
	syslog@6.1.1
	test-log-macros@0.2.19
	test-log@0.2.19
	thiserror-impl@2.0.18
	thiserror@2.0.18
	time-core@0.1.8
	time-macros@0.2.27
	time@0.3.47
	toml@0.8.23
	toml_datetime@0.6.11
	toml_edit@0.22.27
	toml_write@0.1.2
	typenum@1.19.0
	typewit@1.14.2
	typewit_proc_macros@1.8.1
	ucd-trie@0.1.7
	unicode-ident@1.0.23
	unicode-xid@0.2.6
	utf8parse@0.2.2
	version_check@0.9.5
	wasip2@1.0.2+wasi-0.2.9
	wasm-bindgen-macro-support@0.2.108
	wasm-bindgen-macro@0.2.108
	wasm-bindgen-shared@0.2.108
	wasm-bindgen@0.2.108
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-x86_64-pc-windows-gnu@0.4.0
	winapi@0.3.9
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.59.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	winnow@0.7.14
	wit-bindgen@0.51.0
	zmij@1.0.21
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
LICENSE+=" Apache-2.0 MIT Unicode-3.0 ZLIB"
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

    pamd_mimic system-auth dosr auth account session

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

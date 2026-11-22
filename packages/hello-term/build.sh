TERMUX_PKG_HOMEPAGE=https://github.com/Term-org/TCP
TERMUX_PKG_DESCRIPTION="Prints a greeting; used to test the Term Community Packages pipeline"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@Term-org"
TERMUX_PKG_VERSION=1.0.0
TERMUX_PKG_DEPENDS="bash"
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_make_install() {
	local prefix="${TERMUX__PREFIX:-$TERMUX_PREFIX}"
	mkdir -p "$prefix/bin"
	printf '#!%s/bin/bash\necho "Hello from Term Community Packages"\n' "$prefix" > "$prefix/bin/hello-term"
	chmod 700 "$prefix/bin/hello-term"
}

# The package has no sources, so there is no license file to find in them.
termux_step_install_license() {
	local prefix="${TERMUX__PREFIX:-$TERMUX_PREFIX}"
	install -Dm600 "$TERMUX_PKG_BUILDER_DIR/LICENSE" "$prefix/share/doc/$TERMUX_PKG_NAME/LICENSE"
}
# shellcheck shell=bash
# Shared setup for run.sh and smoke-test.sh. Source it; do not run it.
#
# Gives a DashBeam build (and a Nautilus started next to it) its own home,
# XDG directories, runtime directory and D-Bus session, so it never touches an
# installed DashBeam: settings, transfer history, device identity, the
# single-instance lock and the Nautilus scripts folder all stay inside
# $SANDBOX_DIR.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SANDBOX_DIR="${DASHBEAM_SANDBOX_DIR:-$REPO_ROOT/tmp/linux-sandbox}"

die() {
	echo "error: $*" >&2
	exit 1
}

require() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' is required ($2)"
}

# The binary `pnpm tauri build --debug --no-bundle` produces, or a release one.
default_binary() {
	local candidate
	for candidate in \
		"$REPO_ROOT/src-tauri/target/debug/DashBeam" \
		"$REPO_ROOT/src-tauri/target/debug/dashbeam" \
		"$REPO_ROOT/src-tauri/target/release/DashBeam" \
		"$REPO_ROOT/src-tauri/target/release/dashbeam"; do
		if [ -x "$candidate" ]; then
			echo "$candidate"
			return
		fi
	done
	die "no DashBeam build found; run: pnpm tauri build --debug --no-bundle (or pass --binary)"
}

# Create the sandbox tree, a persistent device identity and sample files.
sandbox_init() {
	case "$SANDBOX_DIR" in
	/*) ;;
	*) die "DASHBEAM_SANDBOX_DIR must be an absolute path" ;;
	esac
	if [ -n "${HOME:-}" ] && [ "$(realpath -m "$SANDBOX_DIR")" = "$(realpath -m "$HOME")" ]; then
		die "refusing to use your real home directory as the sandbox"
	fi

	mkdir -p \
		"$SANDBOX_DIR/home/.config" \
		"$SANDBOX_DIR/home/.local/share" \
		"$SANDBOX_DIR/home/.local/state" \
		"$SANDBOX_DIR/home/.cache" \
		"$SANDBOX_DIR/runtime"
	chmod 700 "$SANDBOX_DIR/runtime"

	# A fixed identity per sandbox, so pairing survives restarts. Passing it via
	# IROH_SECRET also stops a fresh data directory from adopting the identity
	# an installed DashBeam left in the system keyring (secret_store.rs).
	if [ ! -s "$SANDBOX_DIR/identity.hex" ]; then
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' >"$SANDBOX_DIR/identity.hex"
		chmod 600 "$SANDBOX_DIR/identity.hex"
	fi

	# Names that tend to break shell scripts.
	local files="$SANDBOX_DIR/home/Test files"
	if [ ! -d "$files" ]; then
		mkdir -p "$files/A folder/nested"
		echo "plain" >"$files/simple.txt"
		echo "space" >"$files/with space.txt"
		echo "quote" >"$files/it's quoted.txt"
		echo "dollar" >"$files/\$HOME and \`ticks\`.txt"
		echo "unicode" >"$files/Ümlaut ✓ 文件.txt"
		echo "leading dash" >"$files/-starts-with-dash.txt"
		echo "inner" >"$files/A folder/nested/inner.txt"
		head -c 8M /dev/urandom >"$files/random-8MiB.bin"
	fi
}

# Export the sandbox environment into the current shell.
sandbox_export_env() {
	local real_runtime="${XDG_RUNTIME_DIR:-}"

	# Keep the real compositor reachable after XDG_RUNTIME_DIR moves:
	# libwayland accepts an absolute socket path.
	if [ -n "${WAYLAND_DISPLAY:-}" ] && [ "${WAYLAND_DISPLAY#/}" = "$WAYLAND_DISPLAY" ]; then
		[ -n "$real_runtime" ] || die "WAYLAND_DISPLAY is relative but XDG_RUNTIME_DIR is unset"
		export WAYLAND_DISPLAY="$real_runtime/$WAYLAND_DISPLAY"
	fi

	export HOME="$SANDBOX_DIR/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_DATA_HOME="$HOME/.local/share"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	# Own runtime dir: no shared dconf, document portal or control sockets.
	export XDG_RUNTIME_DIR="$SANDBOX_DIR/runtime"
	export IROH_SECRET
	IROH_SECRET="$(cat "$SANDBOX_DIR/identity.hex")"

	# A Flatpak or AppImage in the real session must not leak in.
	unset FLATPAK_ID APPIMAGE APPDIR DBUS_SESSION_BUS_ADDRESS
}

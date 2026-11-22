#!/usr/bin/env bash
# Automated check of the GNOME Files integration against a real DashBeam build,
# in a throwaway sandbox (never your real home, settings or scripts folder).
#
#   scripts/linux-sandbox/smoke-test.sh [--binary PATH] [--visible] [--keep]
#
# --binary PATH   DashBeam executable or .AppImage (default: newest build)
# --visible       use the current display instead of a headless Xvfb
# --keep          keep the sandbox afterwards for inspection
#
# Steps: start DashBeam with XDG_CURRENT_DESKTOP=GNOME, wait for the frontend
# to write the script, run it the way Nautilus does while DashBeam is running
# (the call must be forwarded to the running instance), then delete the
# binary and check that the script removes itself.

# shellcheck source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/sandbox-env.sh"

SCRIPT_NAME="Send with DashBeam"
MARKER="# managed-by: dashbeam"

pass() { echo "  ok   $*"; }
fail() {
	echo "  FAIL $*" >&2
	exit 1
}

# Runs inside the private D-Bus session and display.
inner() {
	# fd 3 is the terminal; fd 2 (D-Bus services, portals) goes to session.log.
	exec 2>&3 3>&-
	local binary="$DASHBEAM_SANDBOX_BINARY"
	local script="$XDG_DATA_HOME/nautilus/scripts/$SCRIPT_NAME"
	local app_log="$XDG_STATE_HOME/dashbeam.log"
	local app_pid

	"$binary" >"$app_log" 2>&1 &
	app_pid=$!
	# shellcheck disable=SC2064 # expand now: kill this instance on any exit
	trap "kill $app_pid 2>/dev/null || true" EXIT

	local waited=0
	until [ -f "$script" ]; do
		kill -0 "$app_pid" 2>/dev/null || {
			tail -n 20 "$app_log" >&2
			fail "DashBeam exited before writing the script (log above)"
		}
		[ "$waited" -lt 90 ] || fail "no script after 90 s at $script"
		sleep 1
		waited=$((waited + 1))
	done
	pass "script written after ${waited}s"

	[ "$(sed -n 2p "$script")" = "$MARKER" ] || fail "marker missing on line 2"
	pass "marker present"
	[ -x "$script" ] || fail "script is not executable"
	pass "script is executable"
	grep -qF "exec '$binary'" "$script" || fail "script does not launch $binary"
	pass "launches the sandbox binary"

	local selected="$HOME/Test files/it's quoted.txt
$HOME/Test files/with space.txt"
	if ! NAUTILUS_SCRIPT_SELECTED_FILE_PATHS="$selected" timeout 30 "$script" 2>>"$app_log"; then
		fail "script did not finish within 30 s (not forwarded to the running instance?)"
	fi
	pass "second launch handed off to the running instance"
	kill -0 "$app_pid" 2>/dev/null || fail "running instance died after the hand-off"
	pass "running instance still alive"

	kill "$app_pid"
	wait "$app_pid" 2>/dev/null || true
	rm -f -- "$binary"
	NAUTILUS_SCRIPT_SELECTED_FILE_PATHS="$HOME/Test files/simple.txt" "$script" 2>>"$app_log" ||
		fail "script failed after DashBeam was removed"
	[ ! -e "$script" ] || fail "script did not remove itself after DashBeam was removed"
	pass "script removed itself once DashBeam was gone"
}

case "${1:-}" in
--inner)
	inner
	exit 0
	;;
--session)
	# Inside the display (xvfb-run merges stderr into stdout, so redirect here):
	# start the private bus and keep its services' chatter in session.log.
	exec dbus-run-session -- bash "$0" --inner 3>&2 2>"$SANDBOX_DIR/session.log"
	;;
esac

binary=""
visible=0
keep=0
while [ $# -gt 0 ]; do
	case "$1" in
	--binary)
		binary="${2:?--binary needs a path}"
		shift 2
		;;
	--visible)
		visible=1
		shift
		;;
	--keep)
		keep=1
		shift
		;;
	-h | --help)
		sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*) die "unknown option: $1 (see --help)" ;;
	esac
done

require dbus-run-session "package dbus / dbus-daemon"
require timeout "coreutils"
if [ "$visible" = 0 ]; then
	require xvfb-run "package xvfb, or pass --visible"
fi

binary="$(realpath "${binary:-$(default_binary)}")"
[ -x "$binary" ] || die "not executable: $binary"

real_scripts="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts"
fingerprint() {
	# The folder may not exist; that is a valid state to compare too.
	{ find "$real_scripts" -maxdepth 1 -printf '%f %s %m %T@\n' 2>/dev/null || true; } |
		sort | md5sum
}
before="$(fingerprint)"

# Always a fresh sandbox, separate from the one run.sh uses.
SANDBOX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dashbeam-smoke.XXXXXX")"
export DASHBEAM_SANDBOX_DIR="$SANDBOX_DIR"
cleanup() {
	local status=$?
	if [ "$status" -ne 0 ]; then
		echo "Sandbox kept for inspection: $SANDBOX_DIR" >&2
		echo "  logs: home/.local/state/dashbeam.log, session.log" >&2
	elif [ "$keep" = 0 ]; then
		rm -rf -- "$SANDBOX_DIR"
	fi
}
trap cleanup EXIT
sandbox_init
# The test deletes the binary, so it runs a copy (an AppImage stays an
# AppImage, and its runtime sets $APPIMAGE to the copy).
mkdir -p "$SANDBOX_DIR/bin"
cp -- "$binary" "$SANDBOX_DIR/bin/"
export DASHBEAM_SANDBOX_BINARY
DASHBEAM_SANDBOX_BINARY="$SANDBOX_DIR/bin/$(basename "$binary")"

echo "DashBeam GNOME Files smoke test"
echo "  binary:  $binary"
echo "  sandbox: $SANDBOX_DIR"

(
	sandbox_export_env
	export XDG_CURRENT_DESKTOP=GNOME
	if [ "$visible" = 1 ]; then
		bash "$0" --session
	else
		unset WAYLAND_DISPLAY
		xvfb-run -a -s "-screen 0 1280x800x24" bash "$0" --session
	fi
)

[ "$(fingerprint)" = "$before" ] || fail "your real $real_scripts changed during the test"
pass "real scripts folder untouched"
[ "$keep" = 0 ] || echo "Sandbox kept at $SANDBOX_DIR"
echo "All checks passed."

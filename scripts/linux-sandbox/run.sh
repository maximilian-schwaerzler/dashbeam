#!/usr/bin/env bash
# Start a DashBeam build plus its own GNOME Files window in a sandbox that
# cannot clash with an installed DashBeam. See README.md in this folder.
#
#   scripts/linux-sandbox/run.sh [--binary PATH] [--reset] [--no-nautilus]
#
# --binary PATH   DashBeam executable or .AppImage (default: the newest
#                 build under src-tauri/target)
# --reset         delete the sandbox first (settings, identity, scripts)
# --no-nautilus   start only DashBeam
#
# Ctrl+C in this terminal ends the whole sandbox session.

# shellcheck source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/sandbox-env.sh"

binary=""
reset=0
with_nautilus=1
while [ $# -gt 0 ]; do
	case "$1" in
	--binary)
		binary="${2:?--binary needs a path}"
		shift 2
		;;
	--reset)
		reset=1
		shift
		;;
	--no-nautilus)
		with_nautilus=0
		shift
		;;
	-h | --help)
		sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*) die "unknown option: $1 (see --help)" ;;
	esac
done

require dbus-run-session "package dbus / dbus-daemon"
[ "$with_nautilus" = 0 ] || require nautilus "package nautilus, or pass --no-nautilus"
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || die "no graphical session (DISPLAY/WAYLAND_DISPLAY unset)"

binary="${binary:-$(default_binary)}"
binary="$(realpath "$binary")"
[ -x "$binary" ] || die "not executable: $binary"

if [ "$reset" = 1 ]; then
	rm -rf -- "$SANDBOX_DIR"
fi
sandbox_init
sandbox_export_env

cat <<EOF
DashBeam sandbox
  binary:   $binary
  sandbox:  $SANDBOX_DIR
  scripts:  $XDG_DATA_HOME/nautilus/scripts
  desktop:  ${XDG_CURRENT_DESKTOP:-<unset>} (Nautilus is detected on GNOME/Unity or when 'nautilus' is on PATH)

Your installed DashBeam, its settings and your real scripts folder are not touched.
EOF

# A private session bus: its own single-instance lock and its own Nautilus.
export DASHBEAM_SANDBOX_BINARY="$binary" DASHBEAM_SANDBOX_NAUTILUS="$with_nautilus"
# shellcheck disable=SC2016 # expanded by the inner shell
exec dbus-run-session -- bash -c '
	set -u
	trap "kill 0" INT TERM EXIT
	if [ "$DASHBEAM_SANDBOX_NAUTILUS" = 1 ]; then
		nautilus --new-window "$HOME/Test files" >"$XDG_STATE_HOME/nautilus.log" 2>&1 &
	fi
	"$DASHBEAM_SANDBOX_BINARY"
	echo "DashBeam exited; press Ctrl+C to close the sandbox Nautilus too."
	wait
'

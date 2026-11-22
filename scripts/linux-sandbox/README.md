# Linux sandbox for testing the GNOME Files integration

Runs a DashBeam build next to an installed DashBeam without the two touching
each other. Each sandbox gets its own:

| Shared by default | Isolated by |
| --- | --- |
| Settings, history, WebKit data (`~/.local/share/com.dashbeam.desktop`) | own `HOME` and XDG directories |
| Device identity (`identity.key` in that data folder) | own data folder, so the sandbox generates its own |
| Single-instance lock (a test launch would go to your running DashBeam) | own D-Bus session |
| Nautilus scripts folder (same script name and marker) | own `XDG_DATA_HOME`, plus its own Nautilus process |
| Runtime sockets, dconf, document portal | own `XDG_RUNTIME_DIR` |

Everything lives in `tmp/linux-sandbox/` (ignored by git). Delete that folder,
or pass `--reset`, to start over.

## Build

```bash
pnpm tauri build --debug --no-bundle
```

The scripts pick up `src-tauri/target/{debug,release}/DashBeam`. To test an
AppImage instead, pass `--binary path/to/DashBeam.AppImage`.

## Automated smoke test

```bash
scripts/linux-sandbox/smoke-test.sh
```

Runs headless under Xvfb (`apt install xvfb`), or on your screen with
`--visible`. It always uses a fresh temporary sandbox and checks that:

- DashBeam writes the script on startup when the desktop is GNOME
- the script is executable, marked as DashBeam's, and launches this build
- running it the way Nautilus does while DashBeam is open hands the path to
  the running instance
- the script deletes itself once the binary is gone
- your real `~/.local/share/nautilus/scripts` did not change

A failed run keeps its sandbox and prints where the logs are.

## Manual test with real Nautilus

```bash
scripts/linux-sandbox/run.sh
```

Starts the build and a separate Nautilus window on `~/Test files` inside the
sandbox. Its sample files have names that break careless shell quoting.
Checklist:

1. Settings → General → Startup & background shows **Files right-click menu**,
   switched on.
2. Right-click a file → **Scripts → Send with DashBeam**: DashBeam comes to the
   front with that file on the Send tab. Try `it's quoted.txt`,
   ``$HOME and `ticks`.txt``, `Ümlaut ✓ 文件.txt` and `-starts-with-dash.txt`.
3. The same for **A folder**.
4. With several items selected, only the first one is opened (expected).
5. Quit DashBeam, then use the menu entry: DashBeam starts with the item.
6. Switch the setting off: the Scripts entry disappears (Nautilus may need a
   moment, or a new window, to refresh the menu). Switch it on again.
7. Put your own executable named `Send with DashBeam` into
   `tmp/linux-sandbox/home/.local/share/nautilus/scripts/`: switching the
   setting on shows an error, switching it off leaves the file alone, and it is
   never overwritten.

`Ctrl+C` in the terminal ends the sandbox. Closing the window may only hide
DashBeam, since the sandbox's D-Bus session has no tray to restore it from.

The sandbox device is a separate device on your network, so you can pair it
with your installed DashBeam and send a real transfer between the two.

## Not covered

- **Flatpak, .deb and .rpm.** Installing a test package replaces your
  installed DashBeam, because the app ID and package name are the same. Test
  those in a VM or a separate user account.
- The sandbox starts with default GTK and GNOME settings, so it may look
  different from your desktop.

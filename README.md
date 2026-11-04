<p align="center">
  <img src="assets/icons/portly_256.png" alt="Portly icon" width="128" height="128">
</p>

<h1 align="center">Portly</h1>

<p align="center"><strong>See what's running on your ports — and free them in one click.</strong></p>

<p align="center">
  Free and open source · MIT License · Linux
</p>

Portly is a small Linux desktop app that lists every listening TCP and UDP port on your
machine, shows which process owns it, and lets you stop that process — from a window
or straight from the system tray. It starts in the tray, stays there when you close the
window, and only exits when you choose **Quit Portly**.

![Portly main window](docs/screenshot.png)
<!-- TODO: add a screenshot at docs/screenshot.png -->

## Why Portly?

The idea behind Portly is to **simplify managing the ports in my Linux ecosystem**.
Between dev servers, databases, Docker containers and system services, ports get
taken all the time, and finding out who holds one usually means remembering the
right `ss`, `lsof` or `fuser` incantation, then `kill`ing the right PID (with `sudo`
when it's not yours). Portly turns that into a glance at the top bar: what is
listening, who owns it, and a button to free it.

## Open source

Portly is **free and open source software**, released under the [MIT License](LICENSE).
You are welcome to use it, study the code, change it, share it and build on it — for
personal or commercial use — as long as the license notice stays with the code.

Ideas, bug reports and pull requests are welcome.

## Install

### Option 1 — Debian / Ubuntu package (.deb)

Download `portly_<version>_amd64.deb` (or build it, see [Build packages](#build-packages))
and install it with apt, which also pulls in the dependencies:

```bash
sudo apt install ./portly_1.0.0_amd64.deb
```

Then open **Portly** from the app grid, or run `portly` in a terminal. To remove it:

```bash
sudo apt remove portly
```

### Option 2 — AppImage (any distribution)

Download `Portly-<version>-x86_64.AppImage`, make it executable and run it:

```bash
chmod +x Portly-1.0.0-x86_64.AppImage
./Portly-1.0.0-x86_64.AppImage
```

On first launch Portly adds itself to your app grid and gives the dock its icon by
writing `~/.local/share/applications/dev.dosss.portly.desktop` and its icons under
`~/.local/share/icons/hicolor`. If you move the AppImage, the next launch updates the
entry. Restart Portly once if the dock icon does not appear straight away. Installing
the .deb later removes this per-user copy automatically.

The AppImage needs `libnotify4` and `libgtk-3-0`, which every Ubuntu desktop has.

### Option 3 — From source

Install the [build dependencies](#build-dependencies), then:

```bash
flutter pub get
flutter build linux --release
./build/linux/x64/release/bundle/portly
```

### Requirements

- Linux with a StatusNotifierItem tray. On GNOME that is the **Ubuntu AppIndicators**
  extension (enabled by default on Ubuntu).
- `iproute2` (for `ss`) and `pkexec` — present on standard Ubuntu desktops.

## Features

- Live list of listening ports (`ss -tulpneH`, refreshed every 3 s by default), with
  protocol, address, process, PID, user and full command line.
- Filter by port, process, PID or command; TCP/UDP chips; **Mine only / All** toggle;
  sort by port or process.
- **What's using port X?** — type a number, get the owner or "Port X is free".
- **Stop** (SIGTERM, waits up to 3 s) and **Force kill** (SIGKILL), with a confirmation
  showing the process and its command line, and an extra warning for system services.
- Root- and other-user processes are marked with a lock and are stopped through
  `pkexec`, so GNOME asks for your password. **Elevated scan** reveals them once.
- Never signals PID 1 or Portly itself. Ports held by systemd socket activation
  (e.g. `ssh.socket`) get a `systemctl stop` hint instead.
- **Open in browser** for TCP ports reachable on localhost.
- Tray menu: port count, your own processes (Kill / Copy port / Copy PID), favorite
  ports with open/free status, Open, Refresh, Start on login, Quit.
- Notifications when a favorite port opens or closes and after each kill.
- Single instance: launching Portly again brings the existing window back.
- Falls back to `/proc/net/{tcp,tcp6,udp,udp6}` if `ss` is missing.

## Build dependencies

To build Portly yourself (Ubuntu 26.04 / Debian, Flutter 3.47+ on the stable channel):

```bash
sudo apt install libgtk-3-dev libx11-dev libxi-dev libnotify-dev ninja-build cmake clang pkg-config
```

Optional, only to regenerate the PNG icons from the SVGs (otherwise GdkPixbuf is used):

```bash
sudo apt install librsvg2-bin
```

> `tray_manager` 0.8 talks StatusNotifierItem over D-Bus directly, so
> `libayatana-appindicator3-dev` is no longer required.

## Run in development

```bash
flutter pub get
flutter run -d linux
```

Start straight in the tray, as autostart does:

```bash
flutter run -d linux --dart-entrypoint-args=--hidden
```

Checks:

```bash
flutter analyze
flutter test
```

## Build packages

```bash
tool/package.sh          # .deb and AppImage
tool/package.sh deb      # dist/portly_<version>_amd64.deb
tool/package.sh appimage # dist/Portly-<version>-x86_64.AppImage
```

- The `.deb` installs the app to `/usr/lib/portly`, a `portly` launcher in `/usr/bin`,
  `dev.dosss.portly.desktop` in `/usr/share/applications` and the icons in
  `/usr/share/icons/hicolor/{128x128,256x256,512x512,scalable}/apps/portly.*`.
- The AppImage needs [appimagetool](https://github.com/AppImage/appimagetool/releases):
  put it in `tools/` (and `chmod +x` it) or point `APPIMAGETOOL` at it. Without it the
  script still assembles `build/package/Portly.AppDir` and skips the final step.

Install the result as described in [Install](#install).

Regenerate the icons after editing `assets/icons/portly.svg` or `portly_tray.svg`:

```bash
python3 tool/export_icons.py
```

## Start on login

Turn on **Settings → Start on login** (or tick **Start on login** in the tray menu).
Portly writes `~/.config/autostart/dev.dosss.portly.desktop` with
`Exec=portly --hidden`, so it starts in the tray without a window. **Start hidden**
in Settings controls the `--hidden` flag. Turning the option off deletes the file.

For an AppImage the entry points at the AppImage's own path; for a development build
it points at the absolute path of the binary.

## Known Linux limitations

- **Tray clicks open the menu.** On GNOME with AppIndicators (and most
  StatusNotifierItem hosts) clicking the icon always shows the menu; apps receive no
  usable left-click event. Use **Open Portly** in the menu to show the window.
- **No window positioning on Wayland.** Wayland does not let apps place their windows,
  so Portly cannot appear under the tray icon; it is centered (or wherever GNOME puts it).
- **Root processes need pkexec.** Without root, `ss` cannot see who owns sockets of
  other users. Portly still shows their owner and systemd unit (from `ss -e`). To stop
  one, it runs `pkexec ss` to identify the PID and then `pkexec kill`, so GNOME may ask
  for your password twice. Cancelling the prompt is harmless.
- **Socket-activated services.** Some ports (e.g. 22 on Ubuntu, held by `ssh.socket`)
  belong to systemd (PID 1). Portly will not kill PID 1; stop the unit with
  `sudo systemctl stop ssh.socket` instead.
- **Process names.** The kernel truncates process names to 15 characters and some
  runtimes rename their main thread; Portly uses the executable name from the command
  line in those cases.

## Project layout

```
lib/
  main.dart            startup: single instance, window, tray, notifications
  app.dart             MaterialApp, light/dark theme from the system
  core/                pure Dart, unit-tested: ss parser, /proc reader, scanner,
                       process killer, watcher (diff of snapshots)
  services/            tray, window, notifications, autostart, single instance, settings
  providers/           Riverpod state and user actions
  ui/                  home page, settings page, about dialog, widgets
test/                  parser, diff, killer (mocked), scanner, services, widget tests
assets/icons/          portly.svg, portly_tray.svg and exported PNGs
linux/packaging/       dev.dosss.portly.desktop
tool/                  package.sh, export_icons.py
```

## License

MIT — see [LICENSE](LICENSE).

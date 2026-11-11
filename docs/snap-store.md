# Publishing Portly to the Snap Store (Ubuntu App Center)

Ubuntu's **App Center** installs apps from the [Snap Store](https://snapcraft.io).
Portly is published there as a **strict** (sandboxed) snap, defined in
`snap/snapcraft.yaml`. Strict snaps pass the store's automated review, so a new
revision can be released right after upload.

## Why strict, and what changes in the snap

A classic snap was requested first and declined
([forum thread](https://forum.snapcraft.io/t/classic-confinement-request-for-portly/54129)):
running `pkexec` from a snap is not allowed, and classic is reserved for
established projects. Following the reviewer's advice, the snap:

- ships `ss` (iproute2) and plugs `network-observe` + `system-observe` to list
  sockets and read `/proc/<pid>/{cmdline,status}`;
- plugs `process-control` to stop the user's own processes. It is a
  super-privileged interface, so users connect it once by hand:
  `sudo snap connect portly:process-control` (Portly shows this command in a
  banner until it is connected). An auto-connection request can be made on the
  forum later, once the project is better established;
- does not elevate: for processes of root or other users Portly shows the
  command to run instead (`sudo systemctl stop <unit>`, `sudo kill <pid>`, or
  an `ss` lookup), and hides "Elevated scan";
- uses snapcraft's `autostart:` key for "Start on login";
- opens URLs with `xdg-open`, which goes through the desktop portal;
- uses the `gnome` extension for GTK and `unity7` for the tray icon.

The sandbox logic lives in `lib/core/sandbox.dart`. The .deb and AppImage keep
pkexec and every feature.

## 1. One-time setup

```bash
sudo snap install snapcraft --classic
snapcraft login
snapcraft register portly   # already done for "portly"
```

## 2. Build

```bash
tool/package.sh snap        # dist/portly_prod.snap
```

On Ubuntu 26.04 this builds directly on the machine (`--destructive-mode`,
because the `core26` base matches the host). On another release, build in LXD:
`sudo snap install lxd && sudo lxd init --auto`, add yourself to the `lxd`
group, then `snapcraft pack --output dist/portly_prod.snap`.

Try it locally before uploading:

```bash
sudo snap install --dangerous dist/portly_prod.snap
sudo snap connect portly:network-observe
sudo snap connect portly:system-observe
sudo snap connect portly:process-control
snap run portly
```

(`--dangerous` installs skip auto-connections, so connect the plugs by hand.)

## 3. Upload and release

```bash
snapcraft upload --release=stable dist/portly_prod.snap
snapcraft upload-metadata dist/portly_prod.snap
```

The automated review takes a few minutes; Portly then appears in App Center
within about an hour.

## 4. Store listing

Fill in <https://snapcraft.io/portly/listing>: screenshots (App Center shows
them prominently; ready-made ones are in `docs/screenshots/`, regenerate them
with `flutter test tool/screenshots/store_screenshots_test.dart`), a banner and
the category (**Utilities** or **Development**). Title, summary and
description come from `snap/snapcraft.yaml`.

## Updating

Bump `version:` in `pubspec.yaml` (and add a `<release>` to
`linux/packaging/dev.dosss.portly.metainfo.xml`), then build, upload and
release again.

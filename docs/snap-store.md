# Publishing Portly to the Snap Store (Ubuntu App Center)

Ubuntu's **App Center** installs apps from the [Snap Store](https://snapcraft.io).
Portly is packaged as a **classic** snap (`snap/snapcraft.yaml`): it needs the
host's `/proc`, `ss` and `pkexec` to list every port and stop processes of
other users, which strict confinement does not allow. Classic snaps are
reviewed by hand once, before their first release.

## 1. One-time setup

```bash
sudo snap install snapcraft --classic
```

Create an Ubuntu One account (or sign in) at <https://snapcraft.io/account>,
then log in from the terminal:

```bash
snapcraft login
```

Reserve the name (once per snap):

```bash
snapcraft register portly
```

If the name is taken, pick another (for example `portly-ports`) and change
`name:` in `snap/snapcraft.yaml`.

## 2. Build

```bash
tool/package.sh snap        # dist/portly_prod.snap
```

On Ubuntu 26.04 this builds directly on the machine (`--destructive-mode`,
because the `core26` base matches the host). On another release, build in LXD
instead: `sudo snap install lxd && sudo lxd init --auto`, add yourself to the
`lxd` group, then run `snapcraft pack --output dist/portly_prod.snap`.

Try it locally before uploading:

```bash
sudo snap install --dangerous --classic dist/portly_prod.snap
portly
```

## 3. Upload

```bash
snapcraft upload dist/portly_prod.snap
```

The first upload of a classic snap is held for manual review: it shows up in
the dashboard but cannot be released yet.

## 4. Ask for classic confinement

Post in the **classic-confinement** category of the Snapcraft forum
(<https://forum.snapcraft.io/c/store-requests/classic-confinement/26>)
(title: `Classic confinement request for portly`). A draft:

> **Snap name:** portly
> **Source:** https://github.com/dossmedaziz/portly
>
> Portly is a desktop port manager: it lists every listening TCP/UDP port on
> the machine with the process that owns it, and lets the user stop that
> process from a window or the system tray.
>
> **Why classic:**
> - It must read `/proc/<pid>/{cmdline,status,fd}` of all processes and run the
>   host's `ss -tulpne` to map sockets to processes.
> - Stopping a process owned by root or another user runs the host's
>   `pkexec kill`, so polkit shows the GNOME password prompt. `pkexec` is
>   setuid and cannot run inside strict confinement, and `process-control`
>   alone cannot signal other users' processes.
> - "Open in browser" runs the host's `xdg-open`, and "Start on login" writes
>   `~/.config/autostart/dev.dosss.portly.desktop`.
>
> This is the same class of tool as system monitors and process managers.

Reviewers usually answer within a few days. If they refuse, the fallback is
`confinement: strict` with the `network-observe`, `system-observe` and
`process-control` plugs: listing ports and stopping your own processes still
works; the password prompt for root processes does not.

## 5. Release

After approval, release the reviewed revision (see `snapcraft status portly`
or the dashboard for its number):

```bash
snapcraft release portly <revision> stable
```

## 6. Store listing

Fill in <https://snapcraft.io/portly/listing>: screenshots (App Center shows
them prominently; ready-made ones are in `docs/screenshots/`, regenerate them
with `flutter test tool/screenshots/store_screenshots_test.dart`), a banner, the category (**Utilities** or **Development**),
and check the title, summary and description that come from
`snap/snapcraft.yaml`. Once a revision is on `stable`, Portly appears in App
Center within about an hour; it can also be installed with:

```bash
sudo snap install portly --classic
```

## Updating

Bump `version:` in `pubspec.yaml` (and add a `<release>` to
`linux/packaging/dev.dosss.portly.metainfo.xml`), then build, upload and
release again. Later classic revisions are released without another review.

# Isolated Krita capture

Run live pen capture in a disposable Linux guest. The guest owns the virtual
input device, X server, Krita profile, and clipboard. Existing evidence can
be replayed from the host without launching a guest.

## Provision the guest

Use an Ubuntu 24.04 amd64 cloud image, verify its published SHA-256 checksum,
and make a qcow2 overlay. Create a NoCloud seed with an SSH public key for a
guest account and guest-local admin access. Use a scratch directory outside
the checkout. See the [Ubuntu QEMU instructions](https://ubuntu.com/docs/public-images/public-images-how-to/launch-qcow-with-qemu/)
and the [NoCloud setup](https://ubuntu.com/docs/public-images/public-images-how-to/use-local-cloud-init-ds/).

Build `tablet-probe` on the host and copy the executable into a dedicated
input directory. That directory can also hold a local Flatpak repository
containing the pinned app and runtime. Share just this directory read-only.
Set `vm_dir` to the scratch directory and launch QEMU.

```sh
qemu-system-x86_64 -enable-kvm -cpu host -m 4096 -smp 4 \
  -name scoundrill-tablet-test -display none \
  -drive "file=$vm_dir/guest.qcow2,if=virtio,format=qcow2" \
  -drive "file=$vm_dir/seed.iso,media=cdrom,readonly=on" \
  -netdev user,id=guestnet,hostfwd=tcp:127.0.0.1:39271-:22 \
  -device virtio-net-pci,netdev=guestnet \
  -virtfs "local,path=$vm_dir/input,mount_tag=test-input,security_model=none,readonly=on"
```

Connect over SSH to loopback port 39271 with X11 forwarding disabled. Run
the remaining capture commands inside that shell. Check the guest hostname
and confirm `/sys/class/dmi/id/sys_vendor` reports `QEMU` before input injection.

## Set up guest input and display

Inside the guest, install Xorg with the dummy video and libinput drivers,
Openbox, X11 utilities, and Flatpak. The capture used a dummy screen at
3840×2160, depth 24, with the X server listening on a local socket. The
guest window manager had its own display on `:0`.

```sh
sudo apt-get install --no-install-recommends \
  xserver-xorg-core xserver-xorg-video-dummy xserver-xorg-input-libinput \
  x11-xserver-utils x11-utils xinput xauth openbox xdotool xclip wmctrl \
  imagemagick flatpak dbus-x11 acl
sudo mkdir -p /mnt/scoundrill-input
sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro test-input /mnt/scoundrill-input
sudo modprobe uinput
sudo setfacl -m "u:$(id -un):w" /dev/uinput
```

Start with a 1920×1080 dummy screen and switch to 3840×2160 through RandR.
Save this configuration as `/etc/X11/scoundrill.conf` in the guest.

```text
Section "Device"
    Identifier "Guest Display"
    Driver "dummy"
    VideoRam 65536
EndSection
Section "Monitor"
    Identifier "Guest Monitor"
    HorizSync 28-100
    VertRefresh 48-120
    Modeline "1920x1080" 148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync
EndSection
Section "Screen"
    Identifier "Guest Screen"
    Device "Guest Display"
    Monitor "Guest Monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection
```

```sh
xauth -f "$HOME/.Xauthority" add :0 . "$(mcookie)"
sudo systemd-run --unit=scoundrill-xorg -- /usr/lib/xorg/Xorg :0   -config scoundrill.conf -auth "$HOME/.Xauthority" -noreset -nolisten tcp vt7
export DISPLAY=:0
xrandr --newmode 3840x2160-30 297.00 3840 4016 4104 4400 2160 2168 2178 2250 +hsync +vsync
xrandr --addmode DUMMY0 3840x2160-30
xrandr --output DUMMY0 --mode 3840x2160-30
xrandr --current
```

Install the pinned Krita binary and runtime. For the recorded run, a scratch
Flatpak repository was populated with `ostree pull-local` from the host's
already installed app and runtime commits, then indexed with
`flatpak build-update-repo`. Inside the guest, install those refs from the
read-only local repository and verify `flatpak info --show-commit org.kde.krita`
against the reference commit in the evidence notes.

Start Openbox and Krita inside a guest D-Bus session. Use a blank document
stored in the guest home directory.

```sh
DISPLAY=:0 dbus-run-session -- sh -c 'openbox & exec flatpak run   --env=LIBGL_ALWAYS_SOFTWARE=1 org.kde.krita "$1"' sh "$HOME/capture/blank.ppm"
```

Set the brush and curve in the guest
profile, confirm raw pressure in Tablet Tester, and export the canvas from
Krita after each replay. Copy the tester log, stroke plan, and exports back
with SSH, and shut down the guest. See
[the probe instructions](../README.md#capturing-krita-behavior) for the capture
controls and [the VM capture notes](../evidence/krita-5.3.4.1-qemu/README.md)
for the recorded layout and measurements.

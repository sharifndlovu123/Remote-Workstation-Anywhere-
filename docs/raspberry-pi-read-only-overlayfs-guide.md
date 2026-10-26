# Raspberry Pi 5 — Read-Only Root with RAM OverlayFS

## System and purpose

This guide records the **tested configuration** of a Raspberry Pi 5 (4 GB) running Ubuntu Server 26.04.1 LTS (initial kernel `7.0.0-1020-raspi`). The objective is to protect the microSD card from routine writes while keeping the running system usable:

- Persistent ext4 root filesystem: **read-only** during normal operation.
- Writable root view: **OverlayFS**, with changes stored in RAM and discarded at reboot.
- FAT32 boot partition: **read-only** by default.
- **Maintenance mode**: boot directly into writable ext4 whenever changes must persist.
- SSH and Tailscale remain accessible in both tested modes.

**Critical operating rule:** To install packages, change configurations permanently, update Tailscale state, or otherwise retain changes across reboots, **enter maintenance mode first**. Editing files in normal OverlayFS mode affects the RAM overlay only.

## Known device configuration

| Item | Value |
|---|---|
| Board | Raspberry Pi 5, 4 GB RAM |
| OS | Ubuntu Server 26.04.1 LTS |
| Root partition | `/dev/mmcblk0p2`, ext4, label `writable` |
| Boot partition | `/dev/mmcblk0p1`, FAT32, label `system-boot` |
| Active kernel command line | `/boot/firmware/current/cmdline.txt` |
| Original command-line backup | `/boot/firmware/current/cmdline.txt.pre-overlayfs` |
| Persistent fstab | `/etc/fstab` |
| RAM overlay capacity | 512 MiB maximum, allocated on demand |
| LAN IP at setup | `<GATEWAY_IP>` |
| Tailscale IP at setup | `<GATEWAY_TAILSCALE_IP>` |
| Advertised subnet at setup | `<HOME_SUBNET>` |

Network addresses and kernel versions may change. Confirm them on the device rather than assuming they remain current.

## 1. Architecture

At normal boot, Ubuntu's Dracut initramfs uses its OverlayFS boot support, activated by `rd.overlay=tmpfs:size=512M`. The result is:

```text
                  Applications, SSH, Tailscale
                              |
                              v
                    /  (OverlayFS, rw)
                       /           \
             lowerdir (ro)        upperdir/workdir (RAM)
                  |                       |
       /run/rootfsbase             /run/initramfs/overlay
          ext4 on SD                   tmpfs, 512 MiB max
        /dev/mmcblk0p2

       /boot/firmware (vfat, ro)
          /dev/mmcblk0p1
```

`/` is reported as **rw** because OverlayFS accepts writes. This does **not** mean the underlying ext4 filesystem is writable. The lower ext4 filesystem remains mounted read-only; changes go to RAM and disappear at reboot.

The 512 MiB setting is a **limit**, not a fixed 512 MiB RAM reservation. Monitor both available memory and overlay usage.

## 2. Persistent configuration

### Active kernel command line

Ubuntu's Pi boot management uses `os_prefix=current/`; therefore the active command line is:

```text
/boot/firmware/current/cmdline.txt
```

Do **not** edit a similarly named top-level file without confirming it is active. The tested normal-mode command line is a **single line**:

```text
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc ro rd.overlay=tmpfs:size=512M
```

The original pre-overlay command line was saved as:

```text
/boot/firmware/current/cmdline.txt.pre-overlayfs
```

Its contents are:

```text
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 panic=10 rootwait fixrtc
```

The `ro` and `rd.overlay=tmpfs:size=512M` arguments enable the read-only lower filesystem and RAM-backed OverlayFS. The original command line disables that arrangement for maintenance.

### Persistent `/etc/fstab`

The tested persistent configuration is:

```fstab
LABEL=writable    /               ext4    defaults    0 1
LABEL=system-boot /boot/firmware  vfat    ro          0 1
```

A copy of the earlier fstab is stored at `/etc/fstab.pre-overlayfs`. The boot partition is read-only **even in maintenance mode** unless explicitly remounted writable.

### Boot-management note

The Pi uses Ubuntu's `current/` and `new/` boot layout and may use `piboot-try` during updates. The recorded boot state at setup was `current/state = good`. Kernel/initramfs updates require special care; see §6.

## 3. Enter maintenance mode — for ALL permanent changes

**Use this procedure whenever you need changes to survive a reboot.** Examples: `apt` upgrades, software installation, SSH/network settings, systemd services, Tailscale login or state changes, editing `/etc/fstab`, and boot configuration.

Run the following commands **on the Raspberry Pi** while it is in normal OverlayFS mode.

**Step 1 — Temporarily unlock the boot partition:**

```bash
sudo mount -o remount,rw /boot/firmware
```

**Step 2 — Restore the saved original kernel command line:**

```bash
sudo cp \
  /boot/firmware/current/cmdline.txt.pre-overlayfs \
  /boot/firmware/current/cmdline.txt
```

This removes the `ro rd.overlay=tmpfs:size=512M` arguments. Inspect the result:

```bash
cat /boot/firmware/current/cmdline.txt
```

**Step 3 — Flush changes, lock boot, reboot:**

```bash
sync
sudo mount -o remount,ro /boot/firmware
sudo reboot
```

**Step 4 — Reconnect over SSH and verify:**

```bash
findmnt /
findmnt /boot/firmware
systemctl is-active ssh
systemctl is-active tailscaled
```

Expected: `/` is `/dev/mmcblk0p2` **ext4 rw** (not `LiveOS_rootfs overlay`); `/boot/firmware` remains **vfat ro**. SSH and Tailscale should report `active` if configured and running.

**You are now in maintenance mode. Changes to the root filesystem are persistent.**

### Working on boot files during maintenance

For edits to boot files or kernel/firmware/initramfs updates, temporarily unlock boot:

```bash
sudo mount -o remount,rw /boot/firmware
```

After the operation completes successfully:

```bash
sync
sudo mount -o remount,ro /boot/firmware
```

Do not remount boot read-only while a boot-related package operation is still running.

## 4. Return to normal read-only mode

After completing and checking all persistent changes in maintenance mode:

**Step 1 — Unlock boot:**

```bash
sudo mount -o remount,rw /boot/firmware
```

**Step 2 — Re-enable the tested boot parameters:**

```bash
sudo python3 - <<'PY'
from pathlib import Path

path = Path('/boot/firmware/current/cmdline.txt')
parameters = path.read_text().strip().split()

for parameter in ('ro', 'rd.overlay=tmpfs:size=512M'):
    if parameter not in parameters:
        parameters.append(parameter)

path.write_text(' '.join(parameters) + '\n')
PY
```

This preserves the other kernel parameters while adding the OverlayFS arguments if missing. Inspect the result; it must remain a single line:

```bash
cat /boot/firmware/current/cmdline.txt
```

**Step 3 — Flush changes, lock boot, reboot:**

```bash
sync
sudo mount -o remount,ro /boot/firmware
sudo reboot
```

**Step 4 — Reconnect and verify normal mode:**

```bash
findmnt /
findmnt /run/rootfsbase
findmnt /run/initramfs/overlay
findmnt /boot/firmware
systemctl is-active ssh
systemctl is-active tailscaled
```

Expected:

| Mount | Filesystem | State |
|---|---|---|
| `/` | `overlay` (`LiveOS_rootfs`) | `rw` (RAM-backed writes) |
| `/run/rootfsbase` | `ext4` on `/dev/mmcblk0p2` | `ro` |
| `/run/initramfs/overlay` | `tmpfs` | `rw`, `size=524288k` |
| `/boot/firmware` | `vfat` on `/dev/mmcblk0p1` | `ro` |

Check overlay and memory usage:

```bash
df -h /run/initramfs/overlay
free -h
```

## 5. Prove changes are temporary

In **normal read-only mode**, create a disposable test file:

```bash
echo 'OverlayFS persistence test' > ~/overlayfs-test.txt
cat ~/overlayfs-test.txt
sudo reboot
```

After reconnecting:

```bash
ls -l ~/overlayfs-test.txt
```

Expected: `No such file or directory`. **This persistence test was performed successfully** during setup. Avoid using important files for such tests.

## 6. Updates, services, and operational considerations

### Routine permanent changes

1. Enter maintenance mode using §3 and confirm ext4 root is writable.
2. Perform changes, installations, or upgrades.
3. Verify the affected service and configuration.
4. Return to normal mode using §4.
5. Confirm OverlayFS mounts and service availability after reboot.

For package upgrades that change the kernel, initramfs, or Pi boot files, **make `/boot/firmware` writable for the duration of the update**. Ubuntu may stage a new kernel under `new/` and use a trial boot. Complete that update's documented confirmation process, check the active `current/` kernel and initramfs, and verify the new initramfs still includes the OverlayFS support before re-enabling normal mode. Do not blindly copy old kernel files over new ones or assume `current/` never changes.

### Services and persistent state

- **Tailscale:** identity and state under `/var/lib/tailscale` persist only when updated in maintenance mode. Changes to login, authorization, or route configuration made in normal mode may vanish at reboot. External Tailscale authorization is not guaranteed by a disk image alone.
- **SSH:** remains accessible in both tested modes, provided network and service configuration are intact.
- **Logs and databases:** writes made in normal mode reside in RAM and disappear at reboot. Do not host workloads requiring persistent writes on this root arrangement without designing a separate persistent storage strategy.
- **Memory pressure:** applications, logs, caches, and temporary modifications all consume RAM. A full overlay can cause write failures. Monitor `df -h /run/initramfs/overlay`, `free -h`, and service logs.
- **Read-only protection:** this arrangement reduces routine microSD writes; it is not a substitute for backups or protection against hardware failure and does not prevent every possible low-level write path.

## 7. Troubleshooting and offline recovery

### Root is ext4 rw when normal mode was expected

```bash
cat /proc/cmdline
findmnt /
```

Check whether the active boot command line contains **both** `ro` and `rd.overlay=tmpfs:size=512M`. If missing, the system may still be in maintenance mode. Re-enable them via §4.

### Root is overlay rw — is that wrong?

No. This is expected. Confirm that `/run/rootfsbase` is **ext4 ro** and `/run/initramfs/overlay` is **tmpfs**.

### Changes disappear after reboot

That is expected in normal mode. Repeat any required permanent changes in maintenance mode.

### Boot partition is read-only in maintenance mode

That is intentional due to `/etc/fstab`. Unlock it only when needed:

```bash
sudo mount -o remount,rw /boot/firmware
```

### Device fails to boot after enabling OverlayFS

Use offline recovery on an Ubuntu desktop:

1. Power off the Pi; remove the microSD card.
2. Insert it into the desktop; identify the **correct** boot partition with `lsblk -f`.
3. Mount the FAT32 `system-boot` partition read/write, using the desktop's file manager or an explicit mount command.
4. Within the mounted boot partition, locate `current/cmdline.txt` and `current/cmdline.txt.pre-overlayfs`.
5. Replace `current/cmdline.txt` with the saved pre-overlay version, or remove **only** `ro rd.overlay=tmpfs:size=512M` from the active single-line kernel command line.
6. Flush changes, unmount, safely eject, reinstall the card, and boot. This should return the device to maintenance-style direct ext4 boot, provided the rest of the system is healthy.

**Do not edit the wrong disk or partition.** If the filesystem or boot installation is damaged, use the verified full-disk recovery image described in the separate backup guide.

### If SSH or Tailscale is unreachable

Check local network access, power, service status (if console access is available), and whether the boot completed. A filesystem rollback cannot guarantee that remote authorization or network conditions remain unchanged.

## 8. Quick reference

| Task | Action |
|---|---|
| Normal operation | OverlayFS active; ext4 lower RO; boot RO |
| Make a **permanent** change | Enter maintenance mode (§3) **before** editing |
| Edit boot files | `sudo mount -o remount,rw /boot/firmware` |
| Finish boot edits | `sync && sudo mount -o remount,ro /boot/firmware` |
| Restore read-only protection | Return to normal mode (§4) |
| Check overlay usage | `df -h /run/initramfs/overlay` |
| Check services | `systemctl is-active ssh tailscaled` |
| Recover failed OverlayFS boot | Restore original `current/cmdline.txt` offline |
| Recover entire card | Restore post-OverlayFS `.img.zst` backup |

**Companion document:** `raspberry-pi-backup-and-recovery-guide.md`.

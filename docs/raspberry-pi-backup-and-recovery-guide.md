# Raspberry Pi 5 — Full-Disk Backup and Recovery

## Purpose

This guide records the full-microSD backup and recovery process for the Raspberry Pi 5 running Ubuntu Server 26.04.1 LTS with a tested read-only OverlayFS configuration. It covers full-disk `dd` images, Zstandard compression, integrity checks, safe storage, and restoration.

Two recovery points were created:

| Recovery point | Image filename | Purpose |
|---|---|---|
| Before OverlayFS | `pi5-ubuntu-26.04-pre-overlayfs.img` | Baseline Ubuntu system |
| After OverlayFS | `pi5-ubuntu-26.04-post-overlayfs.img` | Configured read-only system |

Compressed equivalents have the suffix `.img.zst`. The pre-overlay image was compared byte-for-byte to the source card; the post-overlay image and both compressed archives were processed and the Pi was subsequently booted successfully. **Retain checksums and confirm their `OK` output whenever you copy or restore archives.** A successfully booting original card is not the same as a tested restore onto a spare card.

## 1. Safety rules

- **Shut down the Pi and remove its microSD card before imaging it.** Never rely on a live, changing system card for a consistent raw-disk snapshot.
- Identify the correct device using `lsblk` **every time**. A card previously identified as `/dev/sdb` may receive a different name later.
- `dd of=/dev/sdX` **irreversibly overwrites the entire destination disk**. Confirm its size, model, partitions, and whether it contains any needed data.
- Use the **whole-disk** path (`/dev/sdX`), not a partition (`/dev/sdX1`), for complete images and restorations.
- Unmount source partitions before imaging; unmount destination partitions before restoring.
- Keep at least one verified copy on another physical drive. Checksums detect corruption but cannot repair a missing backup.
- A disk image includes local secrets such as SSH host keys and potentially Tailscale credentials; protect backup files and storage accordingly.

## 2. Shut down and identify the card

On the Raspberry Pi:

```bash
sudo shutdown -h now
```

Wait for full shutdown, remove the microSD card, and insert it into an Ubuntu desktop. On the desktop:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

At setup, the card was approximately **29.2 GiB**, with a ~512 MiB FAT32 `system-boot` partition and ~28.6 GiB ext4 `writable` partition. The device was then `/dev/sdb`; **verify the current device name independently**.

The examples below use `/dev/sdb` **only as an illustration**. Substitute the verified whole-disk device if different.

Unmount its partitions:

```bash
sudo umount /dev/sdb1
sudo umount /dev/sdb2
```

If a partition is already unmounted, the corresponding message is harmless. Verify with `lsblk` that neither partition has a mountpoint.

## 3. Create a full-disk image

Create the backup directory:

```bash
mkdir -p ~/raspberrypi-backups
cd ~/raspberrypi-backups
```

Check free space:

```bash
df -h .
```

Each raw image requires roughly the capacity of the entire card (~29.2 GiB for the original card), **not** just the used filesystem space.

### Baseline image (already captured)

```bash
sudo dd \
  if=/dev/sdb \
  of="$HOME/raspberrypi-backups/pi5-ubuntu-26.04-pre-overlayfs.img" \
  bs=4M status=progress conv=fsync
```

### Post-OverlayFS image (already captured)

```bash
sudo dd \
  if=/dev/sdb \
  of="$HOME/raspberrypi-backups/pi5-ubuntu-26.04-post-overlayfs.img" \
  bs=4M status=progress conv=fsync
```

These commands are **separate snapshots at different points in time**, not two commands to run on the same unchanged card. Always ensure the Pi is fully powered down before removing the card.

## 4. Verify raw images against the card

While the card is still attached, compare the whole device to the newly created image:

```bash
sudo cmp /dev/sdb "$HOME/raspberrypi-backups/pi5-ubuntu-26.04-post-overlayfs.img"
echo $?
```

Expected exit code: `0`. A nonzero result means the comparison did not complete successfully or bytes differ. `cmp` can take time and may print nothing when the files match.

For the baseline image, use its corresponding filename and the **original baseline card state**; comparing the baseline image against a card already modified for OverlayFS is expected to fail.

## 5. Generate checksums

From the backup directory:

```bash
cd ~/raspberrypi-backups
sha256sum pi5-ubuntu-26.04-pre-overlayfs.img \
  > pi5-ubuntu-26.04-pre-overlayfs.img.sha256
sha256sum pi5-ubuntu-26.04-post-overlayfs.img \
  > pi5-ubuntu-26.04-post-overlayfs.img.sha256
```

Verify the raw images while they exist:

```bash
sha256sum -c pi5-ubuntu-26.04-pre-overlayfs.img.sha256
sha256sum -c pi5-ubuntu-26.04-post-overlayfs.img.sha256
```

Expected: `<filename>: OK` for each. `sha256sum -c` means **check** the file against the stored checksum; it does not generate a new checksum file.

## 6. Compress both images with Zstandard

Check/install Zstandard on the desktop:

```bash
zstd --version
# If missing:
sudo apt install zstd
```

Check available space with `df -h .` first. These commands keep the raw images and produce new `.zst` files:

```bash
cd ~/raspberrypi-backups
zstd -T0 -3 -k -v pi5-ubuntu-26.04-pre-overlayfs.img
zstd -T0 -3 -k -v pi5-ubuntu-26.04-post-overlayfs.img
```

| Option | Meaning |
|---|---|
| `-T0` | Use available CPU threads |
| `-3` | Fast/moderate compression level |
| `-k` | Keep the input image |
| `-v` | Verbose progress/details |

**Compression ratio varies** depending on how much free space on the card contains zeros or compressible data. A raw disk image includes unused sectors.

### Verify compressed archives

Test each archive's integrity:

```bash
zstd -t pi5-ubuntu-26.04-pre-overlayfs.img.zst
zstd -t pi5-ubuntu-26.04-post-overlayfs.img.zst
```

For stronger verification, compare the decompressed output with the original image **while the raw images are still present**:

```bash
set -o pipefail
zstd -dc pi5-ubuntu-26.04-pre-overlayfs.img.zst | \
  cmp - pi5-ubuntu-26.04-pre-overlayfs.img
zstd -dc pi5-ubuntu-26.04-post-overlayfs.img.zst | \
  cmp - pi5-ubuntu-26.04-post-overlayfs.img
```

No `cmp` output and exit code `0` indicate a match. `set -o pipefail` ensures a decompression error is not hidden by a successful downstream command.

Create checksums for the archives:

```bash
sha256sum *.img.zst > compressed-images.sha256
sha256sum -c compressed-images.sha256
```

Expected: `OK` for both archives.

### Optional: reclaim space

**Only after the raw images, compressed archives, and checksums have been verified**, remove raw images if desired:

```bash
rm -i pi5-ubuntu-26.04-pre-overlayfs.img
rm -i pi5-ubuntu-26.04-post-overlayfs.img
```

Keep the `.img.sha256` files. They are useful for verifying raw images after future decompression. Note that `sha256sum -c *.img.sha256` cannot work until the corresponding `.img` files exist again.

## 7. Decompress a backup

In the backup directory:

```bash
cd ~/raspberrypi-backups
```

Decompress the baseline image while keeping the compressed archive:

```bash
zstd -d -k pi5-ubuntu-26.04-pre-overlayfs.img.zst
```

Decompress the configured read-only image:

```bash
zstd -d -k pi5-ubuntu-26.04-post-overlayfs.img.zst
```

Verify the recovered raw images against their original checksums:

```bash
sha256sum -c pi5-ubuntu-26.04-pre-overlayfs.img.sha256
sha256sum -c pi5-ubuntu-26.04-post-overlayfs.img.sha256
```

Decompression requires approximately **29.2 GiB per image** for the original card size. If a raw `.img` already exists, `zstd` may refuse to overwrite it; do not force an overwrite unless intentional.

## 8. Restore a microSD card from a raw image

**DANGER: This erases the destination card completely.** Prefer a spare microSD card for recovery testing.

1. Insert the destination card into the Ubuntu desktop.
2. Identify its **current** whole-disk device with `lsblk -o NAME,SIZE,MODEL,TRAN,TYPE,FSTYPE,LABEL,MOUNTPOINTS`.
3. Ensure the card is **at least as large in bytes** as the original source image. Two cards advertised with the same nominal capacity can differ slightly.
4. Unmount any mounted partitions on the destination card.
5. Restore the image to the **whole disk**, not a partition.

Example, **only if `/dev/sdX` has been verified as the intended destination card**:

```bash
sudo dd \
  if="$HOME/raspberrypi-backups/pi5-ubuntu-26.04-post-overlayfs.img" \
  of=/dev/sdX \
  bs=4M status=progress conv=fsync
sync
```

To confirm the destination matches the image, compare only the image's byte length (not extra trailing sectors on a larger card):

```bash
sudo cmp -n "$(stat -c%s "$HOME/raspberrypi-backups/pi5-ubuntu-26.04-post-overlayfs.img")" \
  /dev/sdX \
  "$HOME/raspberrypi-backups/pi5-ubuntu-26.04-post-overlayfs.img"
echo $?
```

Expected exit code `0`. Re-read the destination device name before running either command.

## 9. Restore directly from `.img.zst` without unpacking

This avoids needing an additional ~29.2 GiB for a raw intermediate file. **It still overwrites the entire destination disk.**

First verify the archive checksum and archive integrity:

```bash
cd ~/raspberrypi-backups
sha256sum -c compressed-images.sha256
zstd -t pi5-ubuntu-26.04-post-overlayfs.img.zst
```

Then, after identifying and unmounting the correct destination card, restore:

```bash
set -o pipefail
zstd -dc pi5-ubuntu-26.04-post-overlayfs.img.zst | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

**Check that the pipeline exited successfully.** If either decompression or `dd` fails, the destination may be only partially written and must not be trusted.

For a stronger read-back check without extracting the image to disk:

```bash
set -o pipefail
zstd -dc pi5-ubuntu-26.04-post-overlayfs.img.zst | \
  sudo cmp -n "$(zstd -dc pi5-ubuntu-26.04-post-overlayfs.img.zst | wc -c)" \
    /dev/sdX -
```

This re-decompresses the archive to calculate its length and compare it to the device. It can take significant time. Alternatively, decompress once to a raw image and use the simpler `cmp -n` command in §8.

## 10. Safely eject and test the restored card

After writes and verification finish:

```bash
sync
sudo udisksctl power-off -b /dev/sdX
```

Replace `/dev/sdX` with the **verified** device name. Reinsert the card into the Pi, power on, and check:

```bash
findmnt /
findmnt /run/rootfsbase
findmnt /run/initramfs/overlay
findmnt /boot/firmware
systemctl is-active ssh
systemctl is-active tailscaled
```

For the **post-OverlayFS** image, expected state: root overlay `rw`, underlying ext4 `ro`, RAM tmpfs upper, and boot vfat `ro`. For the **pre-OverlayFS** image, expect the original direct ext4 root configuration instead.

A successful boot and service check on a **spare card** is the strongest practical validation of the recovery process. A file checksum alone does not guarantee the card will boot or that external services will authorize it.

## 11. Suggested backup directory

```text
~/raspberrypi-backups/
├── pi5-ubuntu-26.04-pre-overlayfs.img.zst
├── pi5-ubuntu-26.04-pre-overlayfs.img.sha256
├── pi5-ubuntu-26.04-post-overlayfs.img.zst
├── pi5-ubuntu-26.04-post-overlayfs.img.sha256
└── compressed-images.sha256
```

If raw images are retained, their `.img` files will appear alongside the archives.

Keep a copy of the compressed images and checksum files on a **separate physical disk**. For long-term storage, periodically rerun:

```bash
cd ~/raspberrypi-backups
sha256sum -c compressed-images.sha256
```

## 12. Recovery decision guide

| Problem | Recommended action |
|---|---|
| Need to make a permanent change | Use maintenance mode in the read-only guide; **no restore needed** |
| OverlayFS kernel parameters cause a boot failure | Edit the FAT32 boot partition offline and restore original `current/cmdline.txt` |
| Root filesystem or boot installation is damaged | Restore the verified post-OverlayFS full-disk image |
| Need to revert the entire setup to its baseline | Restore the verified pre-OverlayFS full-disk image |
| Archive fails checksum/integrity check | Do **not** restore it; obtain another known-good copy |
| New SD card has fewer bytes than original image | Use a sufficiently large destination card; do not truncate the image |

**Companion document:** `raspberry-pi-read-only-overlayfs-guide.md`.

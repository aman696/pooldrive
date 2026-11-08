# Drive operation and troubleshooting

[Quick start](../README.md#quick-start) handles a fresh install. The extra disk can be an HDD or SSD. To keep mount paths compatible with existing PoolDrive setups, the installer calls the extra disk's path `/srv/pool/hdd` in both cases.

## Remove or reconnect the extra drive

1. Finish any transfers to or from the drive and close open files.
2. On the server, run `sudo systemctl stop srv-pool-hdd.mount`. Verify `findmnt --mountpoint /srv/pool/hdd` returns no mount before unplugging. If the stop fails, close any processes holding files open and retry.
3. Refresh the browser after ten seconds. Expect **Unavailable** in `HDD-status.txt` and continued access to a known internal-drive file.
4. Reinsert the drive. The udev rule asks systemd to mount it by UUID. The monitor reattaches its branch when it sees the right filesystem mounted read/write. Check for **Online** and verify a known extra-drive file is visible again.

If you stopped the mount but left the drive plugged in, start it manually with `sudo systemctl start srv-pool-hdd.mount`.

## Diagnose

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,UUID,MOUNTPOINTS
findmnt --mountpoint /srv/storage/Files
findmnt --mountpoint /srv/pool/hdd
df -hT /srv/storage/Files
cat /srv/storage/HDD-status.txt
getfattr --only-values -n user.mergerfs.branches /srv/storage/Files/.mergerfs
systemctl status pooldrive-web.service --no-pager
journalctl -u pooldrive-web.service -u pooldrive-hdd-state.service -n 50 --no-pager
```

- **Online but files are missing.** List `/srv/pool/hdd/PoolFiles` and `/srv/storage/Files` from the server. Existing files at the root of the drive remain outside the pool until you move them into `PoolFiles`.
- **Drive detected but unavailable.** Check for a read/write mount at `/srv/pool/hdd` with the expected UUID. If the disk needs repair, unmount it and follow the filesystem's repair procedure after checking your backup.
- **Web ports occupied.** Run `sudo ss -ltnp '( sport = :8080 or sport = :8081 )'` and identify the process before retrying.
- **Web sign-in works but uploads fail.** Open **Files** and confirm the Unix storage user can write to the underlying directories. On ext4, files retain the Unix ownership and modes from their original locations. On exFAT, setup supplies the ownership and mode mask at mount time.
- **Samba login fails.** Run `sudo smbpasswd -a YOUR_STORAGE_USER` and use the resulting Samba credentials. If the share is reachable but free space looks wrong, check `sudo /usr/local/sbin/pooldrive-dfree /srv/storage`.
- **Web and Samba show different data.** Check that the SFTPGo user has `/srv/storage` as their home and that both clients are in **Files**. Concurrent edits to the same file can conflict.

## Files changed by setup

- `/etc/fstab` gets the pool mount and, if selected, one extra drive mount. The initial file is copied to `/etc/fstab.before-pooldrive`.
- `/etc/pooldrive/` stores application and drive settings. `/var/lib/pooldrive/` holds the SFTPGo account database and its application state.
- Setup installs the browser service, and installs the drive monitor, timer and udev rule when an extra drive is configured.
- If Samba is selected, setup includes the share from `/etc/pooldrive/samba-share.conf`, retaining the prior configuration at `/etc/samba/smb.conf.before-pooldrive`.

If setup stops partway, address the reported error and rerun it with the same options. Setup rejects conflicting mount definitions and an existing Samba share named `Storage`. For a host already configured with mergerfs, follow the [existing pool instructions](../README.md#use-an-existing-pool).

Back up `/var/lib/pooldrive` before changing the SFTPGo version or uninstalling. To stop browser access, run `sudo systemctl disable --now pooldrive-web.service`. If you also enabled Tailscale Serve for the browser, inspect `tailscale serve status` and remove the corresponding route.

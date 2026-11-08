# PoolDrive

Turn an old Ubuntu laptop or PC into a file server. PoolDrive combines a folder on the host's internal drive and one optional HDD or SSD into a single file tree. Open it in a browser with SFTPGo, or in a file manager with the optional Samba share.

Each file lives on one drive. Keep a separate backup of important data. If you detach the extra drive, its files disappear from the pool until you reconnect it. Files on the internal drive stay accessible.

## Quick start

You need an Ubuntu Server host with systemd, an ordinary sudo account, and an Internet connection for package downloads. The installer targets amd64 and arm64. It installs OpenSSH if needed and uses it for private browser access. The optional extra drive must already have an **ext4** or **exFAT** filesystem. Plug it in directly without mounting it in a file manager.

Download or clone this repository onto the server and open a terminal in the repository directory. Find the extra drive by model and size, then copy its **filesystem UUID** from the correct partition row.

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,UUID,MOUNTPOINTS
sudo bash setup.sh --disk YOUR_FILESYSTEM_UUID
```

- For the internal drive alone, run `sudo bash setup.sh`.
- To enable Samba as well, append `--samba`. The installer prompts for a Samba password if the account is new.
- The setup uses the Unix account that ran `sudo`. For a different existing account, append `--user USERNAME`.
- If you rerun setup, use the same options. You can add `--disk` later to an internal-only setup. Existing pools created by hand can use the [web-only installer](#use-an-existing-pool).

The installer adds the mount definitions, configures the drive monitor when an extra drive is selected, and installs the pinned SFTPGo release with checksum verification. It creates an empty `PoolFiles` directory on the extra drive and leaves the rest of that drive in place.

## Open the browser

From the computer you'll use to browse files, replace `YOUR_SSH_USER@SERVER_IP` with your server login and address. Keep this command running.

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:18080:127.0.0.1:8080 \
  -L 127.0.0.1:18081:127.0.0.1:8081 \
  YOUR_SSH_USER@SERVER_IP
```

1. Open [WebAdmin](http://127.0.0.1:18081/web/admin) and create the first admin.
2. In **Users**, create a separate browser user. Select **Local filesystem**, set **Home directory** to `/srv/storage`, and grant file permissions at `/`. Choose a strong password.
3. Sign in at [WebClient](http://127.0.0.1:18080/web/client), open **Files**, and upload a small test file. If you enabled Samba, open `smb://SERVER_IP/Storage/Files/` in your file manager and look for the same file. On Windows, use `\\SERVER_IP\Storage\Files`.

The admin, browser user, and Samba login are separate accounts. The browser listeners bind to loopback. Keep Samba on a trusted LAN or private network.

## See files already on the extra drive

Only the extra drive's `PoolFiles` folder is shared. To share selected files already on it, confirm the drive is mounted and move the files into that folder from the server. Replace `Photos` with an actual name on the drive and run as the storage user.

```bash
mountpoint -q /srv/pool/hdd &&
  mv -nv -- "/srv/pool/hdd/Photos" /srv/pool/hdd/PoolFiles/
```

This is a move within the same filesystem. Refresh **Files** to see the result. For ext4, the Unix storage user also needs permissions on the imported files. Keep any sensitive or system files you do not want to share outside `PoolFiles`.

## Use an existing pool

If you already have mergerfs mounted at `/srv/storage/Files`, use the installer below to add just the browser service. Replace `YOUR_STORAGE_USER` with an existing Unix user with read and write access to the pool. Then follow [Open the browser](#open-the-browser).

```bash
sudo apt install curl ca-certificates iproute2 python3
sudo bash scripts/install-web.sh YOUR_STORAGE_USER
```

## Access away from home

For private access from an enrolled phone or computer, install Tailscale on the server and the client devices. Sign in to your tailnet and enable MagicDNS and HTTPS certificates. After checking that the browser works over SSH, run this on the server.

```bash
sudo tailscale serve --bg http://127.0.0.1:8080
tailscale serve status
```

Append `/web/client` to the HTTPS URL shown by Tailscale. Tailnet access rules control who can reach the address, and SFTPGo requires its own login. The admin interface remains available through the SSH tunnel.

## How it works

| Layer | Default |
|---|---|
| Internal drive folder | `/srv/pool/ssd` |
| Extra HDD or SSD | `/srv/pool/hdd/PoolFiles`, mounted by filesystem UUID |
| Combined files | `/srv/storage/Files` |
| Extra-drive status | `/srv/storage/HDD-status.txt` |
| Browser client and admin | Server loopback ports 8080 and 8081 |
| Optional file-manager share | `Storage` in Samba |

New files go to the eligible branch with the most free space. The fresh installer requires 4 GiB of free space on a branch when it creates a file. A file that's already open can grow past that threshold. Keep free space available on the internal drive, especially if it also holds Ubuntu.

See [Drive operation and troubleshooting](pool/SETUP.md) for safe removal, verification, and the files managed by setup.

## Upstream projects

- [mergerfs](https://github.com/trapexit/mergerfs)
- [SFTPGo](https://github.com/drakkan/sftpgo)
- [Samba](https://www.samba.org/)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

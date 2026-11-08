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

## Use the Android app

Enable Samba with the `--samba` installer option. Connect your phone to the same home network as the server and install Material Files. [Google Play](https://play.google.com/store/apps/details?id=me.zhanghai.android.files) · [F-Droid](https://f-droid.org/en/packages/me.zhanghai.android.files/)

1. In Material Files, tap **Add storage → SMB Server → Add manually**.
2. Enter the server's LAN IP as the host and `445` as the port. Use the storage user's Samba username and password.
3. Tap **Connect and add**, then open **Storage → Files**.

If you need the server's LAN IP, run `ip -br -4 addr` on the server and use the address on its home-network interface.

| Transfer | Steps |
|---|---|
| Server to phone | Select the files in **Storage → Files**, tap **Copy**, then paste into your phone's **Download** folder. The copies are available offline. |
| Phone to server | Select local files, for example from **DCIM → Camera**, tap **Copy**, then paste into **Storage → Files**. |

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

Install Tailscale on the server and the phone or computer you want to connect from. Join both devices to the same tailnet. The server needs to stay awake and connected to the internet while you're away. [Tailscale setup guide](https://tailscale.com/docs/use-cases/personal-or-at-home-use/access-nas-media-file-servers)

### Android app over Tailscale

Connect Tailscale on the phone. Run `tailscale ip -4` on the server, then add a second SMB entry in Material Files with that IP as the host. Use the same port and Samba login as on your home network. Keep TCP port 445 private to your LAN and permitted tailnet devices.

To test from outside your LAN, turn off Wi-Fi on the phone, leave mobile data and Tailscale connected, and copy a small file from **Storage → Files** into **Download**. Download speed depends in part on the server's internet upload speed and whether Tailscale can connect directly. [Tailscale connection types](https://tailscale.com/docs/reference/connection-types)

### Browser over Tailscale

Enable MagicDNS and HTTPS certificates for your tailnet. After checking that the browser works over SSH, run this on the server.

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

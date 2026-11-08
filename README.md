# PoolDrive

PoolDrive gives an Ubuntu Server mergerfs pool a browser interface using SFTPGo. The same files can be accessed over Samba and the browser. SFTPGo lists the live filesystem and stores its own accounts and database separately.

| Layer | Path or service |
|---|---|
| SSD files | `/srv/pool/ssd` |
| External HDD files | `/srv/pool/hdd/PoolFiles` |
| Pooled files | `/srv/storage/Files` |
| Share root and optional drive status | `/srv/storage` and `HDD-status.txt` |
| Browser WebClient | `127.0.0.1:8080/web/client` on the server |
| WebAdmin | `127.0.0.1:8081/web/admin` on the server |

## Use an existing pool

Ubuntu Server on amd64 or arm64, an existing mergerfs mount at `/srv/storage/Files`, and an ordinary Unix user with write access to the pool are required. Run these commands on the server, from the repository root. Replace `YOUR_STORAGE_USER` with that Unix username.

```bash
sudo apt install curl ca-certificates python3
sudo bash scripts/install-web.sh YOUR_STORAGE_USER
```

The installer downloads the pinned upstream SFTPGo 2.7.6 package and checks its SHA-256. It extracts the executable and web assets, then starts a dedicated systemd service under the storage user. Both web listeners are on loopback. The service checks that the pool is mounted before starting and stops if systemd deactivates that mount. Its writable paths are the pool and its private application state in `/var/lib/pooldrive`.

### Open the browser

From your main computer, replace `YOUR_STORAGE_USER@SERVER_IP` with your SSH login. Keep the command running while using the browser.

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:18080:127.0.0.1:8080 \
  -L 127.0.0.1:18081:127.0.0.1:8081 \
  YOUR_STORAGE_USER@SERVER_IP
```

1. Open [WebAdmin](http://127.0.0.1:18081/web/admin). Create the first administrator when prompted.
2. In **Users**, add a separate browser user with a strong password, **Local filesystem** as storage, and **Home directory** set to `/srv/storage`. Grant the user file permissions at `/`. The parent folder is readable and the `Files` folder is writable. The admin, browser user, and Samba login are separate accounts.
3. Sign in at [WebClient](http://127.0.0.1:18080/web/client). Open **Files**, then upload a small test file. Check that the same file appears in Samba. For the reverse test, put a second file into Samba and refresh the browser.

### Private access away from home

Install Tailscale on the server and the devices that need browser access. Sign in to your tailnet and enable MagicDNS and HTTPS certificates. On the server, after confirming the browser works over SSH, run:

```bash
sudo tailscale serve --bg http://127.0.0.1:8080
tailscale serve status
```

Open the HTTPS URL shown by Tailscale and append `/web/client`. Your tailnet access rules control which devices can reach it, and SFTPGo still requires a browser login. Use mobile data on an enrolled phone to verify access from outside your LAN. Administration stays on the separate SSH-forwarded port. Keep the SMB share on the LAN or a trusted private network and leave public port forwarding disabled.

## Build the pool on a fresh Ubuntu server

See [pool/SETUP.md](pool/SETUP.md) to create the same folder layout on existing formatted drives and configure removable drive status. Each file occupies one underlying disk. The pool combines available capacity and does not create a second copy of a file. Files on an unplugged HDD are inaccessible until the drive is mounted again. The 50 GiB placement threshold applies at file creation and is not a quota on existing file growth. Keep independent backups of important files.

## Troubleshooting

On the server:

```bash
findmnt --mountpoint /srv/storage/Files
df -hT /srv/storage/Files
systemctl status pooldrive-web.service --no-pager
journalctl -u pooldrive-web.service -n 50 --no-pager
```

- If the installer reports occupied ports, check `sudo ss -ltnp '( sport = :8080 or sport = :8081 )'` before changing anything.
- If the browser can list files but cannot upload, confirm the user chose `Files` and verify the Unix owner's permissions on the mounted pool.
- If the browser and Samba both write to the pool, avoid concurrent edits to the same path. The clients share the files directly and do not share a version history.
- To stop browser access, run `sudo systemctl disable --now pooldrive-web.service`. If using Tailscale Serve, remove that listener using `sudo tailscale serve --bg http://127.0.0.1:8080 off` when it is the default HTTPS service for this target. Inspect `tailscale serve status` before changing existing routes.
- To update the pinned release, update the version and both verified release hashes in `scripts/install-web.sh`. Back up `/var/lib/pooldrive` before upgrades.

## Upstream references

- [SFTPGo releases](https://github.com/drakkan/sftpgo/releases)
- [SFTPGo configuration reference](https://github.com/sftpgo/docs/blob/main/docs/config-file.md)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
- [mergerfs manual for Ubuntu](https://manpages.ubuntu.com/manpages/resolute/man1/mergerfs.1.html)

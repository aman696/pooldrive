# Create an SSD + HDD pool on Ubuntu

These steps use already formatted disks. For an existing installation with `/srv/storage/Files` mounted, continue with [the web installer](../README.md#use-an-existing-pool).

Run the commands as the ordinary account that will own the pool, using sudo where shown.

```bash
sudo apt install mergerfs attr
lsblk -o NAME,SIZE,MODEL,FSTYPE,UUID,MOUNTPOINTS
id -u
id -g
```

Identify the external filesystem's UUID and the numeric UID/GID of your storage user. Take a backup of the HDD's files before changing mount configuration.

```bash
sudo install -d -m 0755 /srv/storage /srv/pool/hdd
sudo install -d -m 0555 /srv/storage/Files
sudo install -d -o "$USER" -g "$(id -gn)" -m 0750 /srv/pool/ssd
sudo cp -a /etc/fstab /etc/fstab.before-pooldrive
sudoedit /etc/fstab
```

Add these lines once. Replace `HDD_UUID`, `YOUR_UID` and `YOUR_GID`. The first line is for an **exFAT** HDD.

```fstab
UUID=HDD_UUID /srv/pool/hdd exfat defaults,nofail,x-systemd.device-bound,x-systemd.device-timeout=10s,uid=YOUR_UID,gid=YOUR_GID,fmask=0137,dmask=0027 0 0
/srv/pool/ssd /srv/storage/Files mergerfs defaults,nofail,allow_other,category.create=mfs,minfreespace=50G 0 0
```

For an **ext4** HDD, use the following first line instead. Once mounted, grant your storage user ownership of the new `PoolFiles` directory using `sudo chown "$USER:$(id -gn)" /srv/pool/hdd/PoolFiles`.

```fstab
UUID=HDD_UUID /srv/pool/hdd ext4 defaults,nofail,x-systemd.device-bound,x-systemd.device-timeout=10s 0 2
```

Reload the mount definitions, then verify that the HDD is the expected filesystem before creating its pool folder. Substitute your actual UUID in the following block.

```bash
HDD_UUID='replace-with-your-hdd-filesystem-uuid'
sudo systemctl daemon-reload
sudo systemctl start srv-pool-hdd.mount &&
  findmnt -n -M /srv/pool/hdd -S "UUID=$HDD_UUID" &&
  sudo mkdir -p /srv/pool/hdd/PoolFiles &&
  sudo systemctl start srv-storage-Files.mount
```

Existing HDD data outside `PoolFiles` stays outside the share. Move only the files you want to share into that directory. The `PoolFiles` branch is inside the mounted HDD so the branch path disappears when the HDD is unmounted.

## Configure HDD detection

Run this from the repository root, with the real `HDD_UUID` still set in your shell.

```bash
sudo install -d -m 0755 /etc/pooldrive
printf 'HDD_UUID=%s\n' "$HDD_UUID" | sudo tee /etc/pooldrive/hdd.env
sudo install -m 0755 pool/hdd-state.sh /usr/local/sbin/pooldrive-hdd-state
sudo install -m 0644 pool/pooldrive-hdd-state.{service,timer} /etc/systemd/system/
printf 'ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="%s", TAG+="systemd", ENV{SYSTEMD_WANTS}+="srv-pool-hdd.mount"\n' "$HDD_UUID" |
  sudo tee /etc/udev/rules.d/99-pooldrive-hdd.rules
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
sudo systemctl start pooldrive-hdd-state.service
sudo systemctl enable --now pooldrive-hdd-state.timer
cat /srv/storage/HDD-status.txt
df -hT /srv/storage/Files
```

Check the status after boot and after reinserting the HDD. For the removal test, finish file transfers, stop `srv-pool-hdd.mount`, and verify that `findmnt --mountpoint /srv/pool/hdd` shows no mount before unplugging. Refresh the browser after ten seconds. Expect **Unavailable** and continued access to a known SSD file. Reinsert the drive and check that **Online** and a known HDD file return. An unplug during writes can interrupt them.

## Optional Samba access

Install Samba using `sudo apt install samba`. Append the following section to `/etc/samba/smb.conf`, replacing `YOUR_STORAGE_USER` with your Unix account name.

```ini
[Storage]
    path = /srv/storage
    valid users = YOUR_STORAGE_USER
    guest ok = no
    read only = no
    ea support = no
    store dos attributes = no
    map archive = no
    dfree command = /usr/local/sbin/pooldrive-dfree
```

```bash
sudo install -m 0755 pool/dfree.sh /usr/local/sbin/pooldrive-dfree
sudo smbpasswd -a "$USER"
sudo testparm -s && sudo systemctl enable --now smbd && sudo systemctl reload smbd
```

Open `smb://SERVER_IP/Storage/Files/` from your file manager. The free-space helper reports the pooled mount's capacity even when the client queries the share root.

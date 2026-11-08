#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' 'Usage: sudo bash setup.sh [--disk FILESYSTEM_UUID] [--samba] [--user UNIX_USER]'
}

die() {
    printf 'pooldrive: %s\n' "$*" >&2
    exit 1
}

owner=${SUDO_USER:-}
uuid=
samba=false
while (( $# )); do
    case $1 in
        --disk)
            (( $# >= 2 )) && [[ -n $2 ]] || die '--disk needs a filesystem UUID.'
            uuid=$2
            shift
            ;;
        --user)
            (( $# >= 2 )) && [[ -n $2 ]] || die '--user needs a Unix username.'
            owner=$2
            shift
            ;;
        --samba) samba=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown option $1." ;;
    esac
    shift
done

[[ $EUID == 0 ]] || die 'Run this installer with sudo.'
[[ $owner =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || die 'Specify a non-root Unix username with --user.'
uid=$(id -u "$owner") || die "Unknown user $owner."
gid=$(id -g "$owner")
(( uid != 0 )) || die 'Specify a non-root storage user.'
[[ -d /run/systemd/system ]] || die 'Boot an Ubuntu Server host with systemd first.'

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
storage=/srv/storage
ssd=/srv/pool/ssd
hdd=/srv/pool/hdd
pool=$storage/Files
hdd_unit=srv-pool-hdd.mount
pool_unit=srv-storage-Files.mount
pool_entry="$ssd $pool mergerfs defaults,nofail,allow_other,category.create=mfs,minfreespace=4G 0 0"
hdd_entry=
device=

exec 9>/run/lock/pooldrive-setup.lock
flock -n 9 || die 'Another PoolDrive setup is running.'

if [[ -n $uuid ]]; then
    [[ $uuid =~ ^[A-Fa-f0-9]+(-[A-Fa-f0-9]+)*$ ]] ||
        die 'Use the UUID column from lsblk, without a device path or UUID= prefix.'
    [[ -b /dev/disk/by-uuid/$uuid ]] || die "Filesystem $uuid is unavailable. Attach the drive and check lsblk."
    device=$(readlink -f -- "/dev/disk/by-uuid/$uuid")
    fstype=$(blkid -p -s TYPE -o value "$device") || die "Cannot identify the filesystem on $device."
    options=defaults,nofail,nosuid,nodev,x-systemd.device-bound,x-systemd.device-timeout=10s
    case $fstype in
        exfat) options+=",uid=$uid,gid=$gid,fmask=0137,dmask=0027"; pass=0 ;;
        ext4) pass=2 ;;
        *) die "Unsupported filesystem $fstype. Choose a formatted ext4 or exFAT filesystem." ;;
    esac
    hdd_entry="UUID=$uuid $hdd $fstype $options 0 $pass"
    if [[ -n $(lsblk -nr -o MOUNTPOINTS -- "$device" | awk -v path="$hdd" 'NF && $0 != path') ]] ||
       [[ -n $(findmnt --fstab --evaluate --source "$device" -n -o TARGET | awk -v path="$hdd" '$0 != path') ]]; then
        die "$device is already used elsewhere. Select an unused data filesystem."
    fi
fi

check_fstab_entry() {
    local path=$1 expected=$2 existing
    existing=$(awk -v path="$path" '$1 !~ /^#/ && $2 == path' /etc/fstab)
    [[ -z $existing || $existing == "$expected" ]] ||
        die "An existing /etc/fstab entry for $path differs. For an existing pool, use the web installer in the README."
    if [[ -n $existing ]]; then
        grep -Fxq '# PoolDrive managed mounts' /etc/fstab ||
            die "Found an unmanaged /etc/fstab entry for $path."
    fi
}

check_fstab_entry "$pool" "$pool_entry"
check_fstab_entry "$hdd" "$hdd_entry"
for path in /srv/pool "$storage" "$ssd" "$hdd" "$pool"; do
    [[ ! -L $path ]] || die "Move the symlink at $path aside before installing."
    [[ ! -e $path || -d $path ]] || die "$path must be a directory."
done
if mountpoint -q "$pool"; then
    grep -Fxq -- "$pool_entry" /etc/fstab &&
        findmnt -n -M "$pool" -t fuse.mergerfs >/dev/null ||
        die "A different filesystem is already mounted at $pool."
elif [[ -d $pool && -n $(find "$pool" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    die "Move the contents of $pool aside before mounting over it."
fi
if mountpoint -q "$hdd"; then
    [[ -n $uuid ]] && grep -Fxq -- "$hdd_entry" /etc/fstab &&
        findmnt -n -M "$hdd" -S "UUID=$uuid" >/dev/null ||
        die "An unmanaged filesystem is already mounted at $hdd."
elif [[ -d $hdd && -n $(find "$hdd" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    die "Move the contents of $hdd aside before mounting over it."
fi
if [[ -e $ssd && $(stat -c %u -- "$ssd") != "$uid" ]]; then
    die "The existing storage directory $ssd belongs to another user."
fi
if [[ -e /var/lib/pooldrive && $(stat -c '%u:%g' /var/lib/pooldrive) != "$uid:$gid" ]]; then
    die 'The existing browser service data belongs to another user.'
fi

packages=(attr ca-certificates curl iproute2 mergerfs python3)
if $samba; then
    packages+=(samba)
fi
if ! systemctl is-active --quiet ssh.service && ! systemctl is-active --quiet ssh.socket; then
    packages+=(openssh-server)
fi
apt-get update
apt-get install -y "${packages[@]}"
if ! systemctl is-active --quiet ssh.service && ! systemctl is-active --quiet ssh.socket; then
    systemctl enable --now ssh.service
fi

mkdir -p -m 0755 /etc/pooldrive /srv/pool "$storage"
if [[ ! -d $ssd ]]; then
    install -d -m 0750 -o "$uid" -g "$gid" "$ssd"
fi
if ! mountpoint -q "$pool"; then
    install -d -m 0555 "$pool"
fi
if ! mountpoint -q "$hdd"; then
    install -d -m 0555 "$hdd"
fi

if ! grep -Fxq -- "$pool_entry" /etc/fstab ||
   { [[ -n $hdd_entry ]] && ! grep -Fxq -- "$hdd_entry" /etc/fstab; }; then
    cp -an -- /etc/fstab /etc/fstab.before-pooldrive
    fstab=$(mktemp /etc/.pooldrive-fstab.XXXXXX)
    trap 'rm -f -- "$fstab"' EXIT
    cp --preserve=mode,ownership -- /etc/fstab "$fstab"
    if ! grep -Fxq '# PoolDrive managed mounts' /etc/fstab; then
        printf '\n# PoolDrive managed mounts\n' >> "$fstab"
    fi
    for entry in "$pool_entry" "$hdd_entry"; do
        if [[ -n $entry ]] && ! grep -Fxq -- "$entry" "$fstab"; then
            printf '%s\n' "$entry" >> "$fstab"
        fi
    done
    mv -f -- "$fstab" /etc/fstab
    trap - EXIT
fi

systemctl daemon-reload
systemctl start "$pool_unit"
if [[ -n $uuid ]]; then
    systemctl start "$hdd_unit"
    findmnt -n -M "$hdd" -S "UUID=$uuid" -O rw >/dev/null ||
        die "Expected $uuid to be mounted read/write at $hdd."
    [[ ! -L $hdd/PoolFiles ]] || die "$hdd/PoolFiles must be a real directory."
    if [[ ! -e $hdd/PoolFiles ]]; then
        # exFAT presents the owner and permissions set in the mount options.
        if [[ $fstype == ext4 ]]; then
            install -d -m 0750 -o "$uid" -g "$gid" "$hdd/PoolFiles"
        else
            mkdir -- "$hdd/PoolFiles"
        fi
    fi
    [[ -d $hdd/PoolFiles ]] &&
        runuser -u "$owner" -- test -r "$hdd/PoolFiles" &&
        runuser -u "$owner" -- test -w "$hdd/PoolFiles" &&
        runuser -u "$owner" -- test -x "$hdd/PoolFiles" ||
        die "$owner needs read, write and traversal permissions on $hdd/PoolFiles."

    printf 'HDD_UUID=%s\n' "$uuid" > /etc/pooldrive/hdd.env
    install -m 0755 "$repo/pool/hdd-state.sh" /usr/local/sbin/pooldrive-hdd-state
    install -m 0644 "$repo"/pool/pooldrive-hdd-state.{service,timer} /etc/systemd/system/
    printf 'ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="%s", TAG+="systemd", ENV{SYSTEMD_WANTS}+="%s"\n' \
        "$uuid" "$hdd_unit" > /etc/udev/rules.d/99-pooldrive-hdd.rules
    udevadm control --reload-rules
    systemctl daemon-reload
    systemctl start pooldrive-hdd-state.service
    systemctl enable --now pooldrive-hdd-state.timer
fi

bash "$repo/scripts/install-web.sh" "$owner"
if $samba; then
    bash "$repo/scripts/install-samba.sh" "$owner"
fi
printf '\nPoolDrive is ready at %s. Follow the browser sign-in steps in README.md.\n' "$pool"

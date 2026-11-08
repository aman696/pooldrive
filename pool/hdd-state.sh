#!/bin/sh
set -eu

: "${HDD_UUID:?Set HDD_UUID in the monitor configuration}"
storage=/srv/storage
hdd=/srv/pool/hdd
control=$storage/Files/.mergerfs
status_file=$storage/HDD-status.txt
branches=/srv/pool/ssd=RW
state=Unavailable

write_status() {
    if [ "$(cat "$status_file" 2>/dev/null || true)" = "$1" ]; then
        return
    fi
    temporary=$(mktemp "$storage/.HDD-status.XXXXXX")
    printf '%s\n' "$1" > "$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$status_file"
}

if [ -b "/dev/disk/by-uuid/$HDD_UUID" ] &&
   findmnt -n -M "$hdd" -S "UUID=$HDD_UUID" -O rw >/dev/null &&
   [ -d "$hdd/PoolFiles" ] && [ ! -L "$hdd/PoolFiles" ]; then
    branches="$branches:$hdd/PoolFiles=RW"
    state=Online
fi

if [ "$state" = Unavailable ]; then
    write_status Unavailable
fi
if ! current=$(getfattr --only-values --absolute-names -n user.mergerfs.branches "$control"); then
    write_status Unavailable
    exit 1
fi
if [ "$current" != "$branches" ] &&
   ! setfattr -n user.mergerfs.branches -v "$branches" "$control"; then
    write_status Unavailable
    exit 1
fi
write_status "$state"

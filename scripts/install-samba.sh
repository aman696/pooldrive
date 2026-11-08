#!/usr/bin/env bash
set -euo pipefail

owner=$1
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config=/etc/samba/smb.conf
snippet=/etc/pooldrive/samba-share.conf
include="    include = $snippet"

staging=$(mktemp -d /etc/samba/.pooldrive.XXXXXX)
trap 'rm -rf -- "$staging"' EXIT
cat > "$staging/share.conf" <<CONFIG

[Storage]
    path = /srv/storage
    valid users = $owner
    guest ok = no
    read only = no
    ea support = no
    store dos attributes = no
    map archive = no
    dfree command = /usr/local/sbin/pooldrive-dfree
CONFIG

if [[ -e $snippet || -L $snippet ]] || grep -Fxq -- "$include" "$config"; then
    if [[ -L $snippet ]] || ! cmp -s "$staging/share.conf" "$snippet"; then
        printf 'pooldrive: Existing Samba share configuration differs at %s.\n' "$snippet" >&2
        exit 1
    fi
fi

if ! grep -Fxq -- "$include" "$config"; then
    if [[ -L $config ]]; then
        printf 'pooldrive: Samba configuration is a symlink at %s.\n' "$config" >&2
        exit 1
    fi
    testparm -s "$config" > "$staging/current.conf"
    if grep -Eiq '^[[:space:]]*\[storage\][[:space:]]*$' "$staging/current.conf"; then
        printf 'pooldrive: A Samba share named Storage already exists.\n' >&2
        exit 1
    fi
    # Samba processes includes in context. Start a global section for the include.
    cp --preserve=mode,ownership -- "$config" "$staging/smb.conf"
    printf '\n[global]\n    include = %s\n' "$staging/share.conf" >> "$staging/smb.conf"
    testparm -s "$staging/smb.conf" >/dev/null
    cp -an -- "$config" "$config.before-pooldrive"
    install -m 0644 "$staging/share.conf" "$snippet"
    cp --preserve=mode,ownership -- "$config" "$staging/smb.conf"
    printf '\n[global]\n%s\n' "$include" >> "$staging/smb.conf"
    mv -f -- "$staging/smb.conf" "$config"
fi

testparm -s "$config" >/dev/null
install -m 0755 "$repo/pool/dfree.sh" /usr/local/sbin/pooldrive-dfree
systemctl enable --now smbd.service
systemctl reload smbd.service
if ! pdbedit -L -u "$owner" >/dev/null 2>&1; then
    if [[ -t 0 ]]; then
        smbpasswd -a "$owner"
    else
        printf 'Set the Samba password with sudo smbpasswd -a %s.\n' "$owner"
    fi
fi

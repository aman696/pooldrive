#!/usr/bin/env bash
set -euo pipefail

die() { printf 'pooldrive: %s\n' "$*" >&2; exit 1; }

[[ $EUID == 0 ]] || die 'Run with sudo and pass your storage username.'
[[ $# -eq 1 ]] || die 'Usage: sudo bash scripts/install-web.sh STORAGE_USERNAME'
owner=$1
[[ $owner =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || die 'Invalid Unix username.'
uid=$(id -u "$owner") || die "Unknown Unix user: $owner"
gid=$(id -g "$owner")
[[ $uid != 0 ]] || die 'Use a non-root account that already owns the pool files.'

pool=/srv/storage/Files
state=/var/lib/pooldrive
version=2.7.6
release=/opt/pooldrive/sftpgo-$version

findmnt -n -M "$pool" -t fuse.mergerfs >/dev/null ||
    die "Mount mergerfs at $pool first. See README.md."
runuser -u "$owner" -- test -r "$pool" &&
    runuser -u "$owner" -- test -w "$pool" &&
    runuser -u "$owner" -- test -x "$pool" ||
    die "$owner needs read, write and traversal permissions on the pool."
if [[ -e $state && $(stat -c '%u:%g' "$state") != "$uid:$gid" ]]; then
    die "Existing application state belongs to another account: $state"
fi
for app in curl dpkg-deb sha256sum python3 ss; do
    command -v "$app" >/dev/null || die "Missing dependency: $app"
done

arch=$(dpkg --print-architecture)
case $arch in
    amd64) checksum=34b66f9316157e44996e251049333476aed6618f3d4c846b0900f9c0abc51c4a ;;
    arm64) checksum=301929100c84fa0e65c90a587a9f6f3eef3298d29e7e9cd2a790250307019fa9 ;;
    *) die "Supported architectures: amd64 and arm64. Detected $arch." ;;
esac

if ! systemctl is-active --quiet pooldrive-web.service &&
   [[ -n $(ss -H -ltn '( sport = :8080 or sport = :8081 )') ]]; then
    die 'Port 8080 or 8081 is already in use. Resolve the conflict before installing.'
fi

install -d -m 0755 /opt/pooldrive /etc/pooldrive
install -d -m 0700 -o "$uid" -g "$gid" "$state" "$state/backups"
staging=$(mktemp -d /opt/pooldrive/.install.XXXXXX)
trap 'rm -rf -- "$staging"' EXIT

if [[ ! -d $release ]]; then
    package=sftpgo_${version}-1_${arch}.deb
    curl --fail --show-error --silent --location --retry 2 --connect-timeout 15 --max-time 300 --proto '=https' \
        -o "$staging/$package" "https://github.com/drakkan/sftpgo/releases/download/v$version/$package"
    printf '%s  %s\n' "$checksum" "$staging/$package" | sha256sum --check --status ||
        die 'SFTPGo release checksum mismatch.'
    dpkg-deb --extract "$staging/$package" "$staging/package"

    binary=$(find "$staging/package/usr" -type f -name sftpgo -perm /111 -print -quit)
    templates=$(find "$staging/package/usr" -type d -name templates -print -quit)
    static=$(find "$staging/package/usr" -type d -name static -print -quit)
    [[ -n $binary && -n $templates && -n $static ]] ||
        die 'Could not locate SFTPGo and its web assets in the release package.'
    install -D -m 0755 "$binary" "$staging/release/sftpgo"
    cp -a "$templates" "$staging/release/templates"
    cp -a "$static" "$staging/release/static"
    chown -R root:root "$staging/release"
    mv -- "$staging/release" "$release"
fi

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$repo/scripts/render-web.py" "$owner" "$release" "$staging"
if ! cmp -s "$staging/sftpgo.json" /etc/pooldrive/sftpgo.json ||
   ! cmp -s "$staging/pooldrive-web.service" /etc/systemd/system/pooldrive-web.service; then
    install -m 0644 "$staging/sftpgo.json" /etc/pooldrive/sftpgo.json
    install -m 0644 "$staging/pooldrive-web.service" /etc/systemd/system/pooldrive-web.service
    systemctl daemon-reload
    systemctl enable pooldrive-web.service
    systemctl restart pooldrive-web.service
else
    systemctl enable --now pooldrive-web.service
fi

for ((attempt = 0; attempt < 15; attempt++)); do
    if curl --noproxy '*' --max-time 3 -fsS -o /dev/null http://127.0.0.1:8080/web/client &&
       curl --noproxy '*' --max-time 3 -fsS -o /dev/null http://127.0.0.1:8081/web/admin; then
        printf '\nPoolDrive WebClient and WebAdmin are responding on loopback.\n'
        exit 0
    fi
    sleep 1
done

journalctl -u pooldrive-web.service -n 25 --no-pager >&2
die 'One or both web endpoints failed to respond.'

#!/bin/sh
/usr/bin/mountpoint -q /srv/storage/Files || exit 1
exec /usr/bin/stat -f -c '%b %a %S' /srv/storage/Files

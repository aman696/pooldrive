#!/usr/bin/env python3
"""Render a local-only SFTPGo configuration and its systemd unit."""

import json
from pathlib import Path
import sys

owner, release_path, output_path = sys.argv[1:]
release = Path(release_path)
output = Path(output_path)
state = "/var/lib/pooldrive"
pool = "/srv/storage/Files"


def binding(port, *, admin):
    return {
        "port": port,
        "address": "127.0.0.1",
        "enable_web_admin": admin,
        "enable_web_client": not admin,
        "enable_rest_api": False,
    }


config = {
    "sftpd": {"bindings": [{"port": 0}]},
    "ftpd": {"bindings": [{"port": 0}]},
    "webdavd": {"bindings": [{"port": 0}]},
    "telemetry": {"bind_port": 0},
    "data_provider": {
        "driver": "sqlite",
        "name": f"{state}/sftpgo.db",
        "backups_path": f"{state}/backups",
    },
    "httpd": {
        "bindings": [binding(8080, admin=False), binding(8081, admin=True)],
        "templates_path": str(release / "templates"),
        "static_files_path": str(release / "static"),
        "openapi_path": "",
    },
}

(output / "sftpgo.json").write_text(json.dumps(config, indent=2) + "\n")
(output / "pooldrive-web.service").write_text(f"""[Unit]
Description=PoolDrive browser access
BindsTo=srv-storage-Files.mount
After=srv-storage-Files.mount network.target

[Service]
Type=simple
User={owner}
WorkingDirectory={state}
Environment=HOME={state}
UMask=0027
ExecStartPre=/usr/bin/findmnt --noheadings --mountpoint {pool} --types fuse.mergerfs
ExecStart={release}/sftpgo serve --config-dir {state} --config-file /etc/pooldrive/sftpgo.json --log-file-path=
Restart=on-failure
RestartSec=3s
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths={state} {pool}

[Install]
WantedBy=multi-user.target
""")

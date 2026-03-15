[Unit]
Description=ClamAV Download Scanner (inotify)
After=clamav-freshclam.service clamd@scan.service network.target
Requires=clamd@scan.service
Wants=clamav-freshclam.service

[Service]
User=root
Group=root
Type=simple
ExecStart=/usr/local/bin/download-clamscan
Restart=always
RestartSec=10

# Security hardening
ProtectSystem=strict
##READWRITE_PATHS##

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target

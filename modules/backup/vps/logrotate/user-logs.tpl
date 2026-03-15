__HOME__/.local/log/backup-vps/*.log {
    su __USER__ __USER__
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

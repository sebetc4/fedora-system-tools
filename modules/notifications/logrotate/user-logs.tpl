__HOME__/.local/log/notifications/*.log {
    su __USER__ __USER__
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

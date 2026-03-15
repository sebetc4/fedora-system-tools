# Override RPM default: wider perms for script access
d /run/clamd.scan 0755 __CLAM_USER__ __CLAM_GROUP__ -

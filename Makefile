# =============================================================================
# Fedora System Tools - Makefile
# =============================================================================
# Targets for installing, upgrading, and uninstalling modules and submodules.
#
# Usage:
#   make install                    # Install lib + all modules
#   make install-lib                # Install shared library only
#   make install-clamav             # Install all clamav submodules
#   make install-clamav-quarantine  # Install only quarantine submodule
#   make uninstall-clamav           # Uninstall all clamav submodules
#   make uninstall-clamav-quarantine# Uninstall only quarantine submodule
#   make reinstall-clamav           # Force reinstall all clamav submodules
#   make reinstall-clamav-quarantine# Force reinstall only quarantine
#   make list                       # List installed modules + submodules
#   make upgrade                    # Upgrade already-installed modules
#   make shellcheck                 # Run ShellCheck on all scripts
#   make test                       # Run the bats unit tests
# =============================================================================

.PHONY: install install-lib install-clamav install-torrent \
        install-notifications install-nautilus install-firewall \
        install-backup install-build-kernel \
        uninstall-clamav uninstall-torrent \
        uninstall-notifications uninstall-nautilus \
        uninstall-firewall uninstall-backup uninstall-build-kernel \
        reinstall-clamav reinstall-torrent \
        reinstall-notifications reinstall-nautilus \
        reinstall-firewall reinstall-backup reinstall-build-kernel \
        list upgrade shellcheck lint test help

# ===================
# Full install
# ===================
install: install-lib
	@echo ""
	@echo "=== Installing all modules ==="
	@for module in notifications clamav torrent nautilus firewall backup; do \
		if [ -f modules/$$module/install.sh ]; then \
			echo ""; \
			echo "==> Installing $$module..."; \
			sudo ./modules/$$module/install.sh --all; \
		fi; \
	done
	@echo ""
	@echo "=== All modules installed ==="

# ===================
# Shared library
# ===================
install-lib:
	@echo "==> Installing shared library..."
	sudo ./lib/install.sh

# ===================
# Module-level install (all submodules)
# ===================
install-clamav: install-lib
	sudo ./modules/clamav/install.sh --all

install-torrent: install-lib
	sudo ./modules/torrent/install.sh

install-notifications: install-lib
	./modules/notifications/install.sh

install-nautilus: install-lib
	sudo ./modules/nautilus/install.sh

install-firewall: install-lib
	sudo ./modules/firewall/install.sh

install-backup: install-lib
	sudo ./modules/backup/install.sh --all

install-build-kernel: install-lib
	sudo ./modules/build-kernel/install.sh --all

# ===================
# Submodule-level install (pattern rules)
# ===================
install-clamav-%: install-lib
	sudo ./modules/clamav/install.sh --only $*

install-backup-%: install-lib
	sudo ./modules/backup/install.sh --only $*

install-build-kernel-%: install-lib
	sudo ./modules/build-kernel/install.sh --only $*

# ===================
# Module-level uninstall (all submodules)
# ===================
uninstall-clamav:
	sudo ./modules/clamav/uninstall.sh --all

uninstall-torrent:
	sudo ./modules/torrent/uninstall.sh

uninstall-notifications:
	./modules/notifications/uninstall.sh

uninstall-nautilus:
	sudo ./modules/nautilus/uninstall.sh

uninstall-firewall:
	sudo ./modules/firewall/uninstall.sh

uninstall-backup:
	sudo ./modules/backup/uninstall.sh --all

uninstall-build-kernel:
	sudo ./modules/build-kernel/uninstall.sh --all

# ===================
# Submodule-level uninstall (pattern rules)
# ===================
uninstall-clamav-%:
	sudo ./modules/clamav/uninstall.sh --only $*

uninstall-backup-%:
	sudo ./modules/backup/uninstall.sh --only $*

uninstall-build-kernel-%:
	sudo ./modules/build-kernel/uninstall.sh --only $*

# ===================
# Module-level reinstall (force reinstall all submodules)
# ===================
reinstall-clamav: install-lib
	sudo ./modules/clamav/install.sh --force --all

reinstall-torrent: install-lib
	sudo ./modules/torrent/install.sh --force

reinstall-notifications: install-lib
	./modules/notifications/install.sh --force

reinstall-nautilus: install-lib
	sudo ./modules/nautilus/install.sh --force

reinstall-firewall: install-lib
	sudo ./modules/firewall/install.sh --force

reinstall-backup: install-lib
	sudo ./modules/backup/install.sh --force --all

reinstall-build-kernel: install-lib
	sudo ./modules/build-kernel/install.sh --force --all

# ===================
# Submodule-level reinstall (pattern rules)
# ===================
reinstall-clamav-%: install-lib
	sudo ./modules/clamav/install.sh --force --only $*

reinstall-backup-%: install-lib
	sudo ./modules/backup/install.sh --force --only $*

reinstall-build-kernel-%: install-lib
	sudo ./modules/build-kernel/install.sh --force --only $*

# ===================
# Version management
# ===================
list:
	@./setup.sh --list

upgrade:
	@./setup.sh --upgrade

# ===================
# Quality checks
# ===================
# Every *.sh and *.bats file git tracks, plus new ones not ignored yet
# (wildcard drops files deleted from the working tree but still in the index).
SHELL_SCRIPTS = $(wildcard $(shell git ls-files --cached --others --exclude-standard '*.sh' '*.bats'))

shellcheck:
	@echo "==> Running ShellCheck on $(words $(SHELL_SCRIPTS)) scripts..."
	@shellcheck -x $(SHELL_SCRIPTS)
	@echo "ShellCheck passed"

lint: shellcheck

test:
	@command -v bats >/dev/null 2>&1 || { echo "bats is not installed. Run: sudo dnf install bats" >&2; exit 1; }
	@bats --recursive tests/unit

# ===================
# Help
# ===================
help:
	@echo "Fedora System Tools - Available targets:"
	@echo ""
	@echo "  install                    Install lib + all modules"
	@echo "  install-lib                Install shared library only"
	@echo "  install-<module>           Install all submodules of a module"
	@echo "  install-<module>-<sub>     Install a specific submodule"
	@echo ""
	@echo "  list                       List installed modules + submodules"
	@echo "  upgrade                    Upgrade already-installed modules"
	@echo "  uninstall-<module>         Uninstall all submodules of a module"
	@echo "  uninstall-<module>-<sub>   Uninstall a specific submodule"
	@echo "  reinstall-<module>         Force reinstall all submodules"
	@echo "  reinstall-<module>-<sub>   Force reinstall a specific submodule"
	@echo ""
	@echo "  shellcheck                 Run ShellCheck on all scripts"
	@echo "  test                       Run the bats unit tests"
	@echo "  help                       Show this help"
	@echo ""
	@echo "Modules: notifications, clamav, torrent, nautilus, firewall, backup, build-kernel"
	@echo ""
	@echo "Examples:"
	@echo "  make install-clamav              # All clamav submodules"
	@echo "  make install-clamav-quarantine   # Only quarantine"
	@echo "  make install-clamav-usb-clamscan # Only USB scanner"
	@echo "  make install-backup-vps          # Only VPS backup"
	@echo "  make uninstall-clamav-quarantine  # Remove quarantine only"
	@echo "  make reinstall-clamav-quarantine # Force reinstall quarantine"

# Installs the user-facing scripts into BINDIR (default: $(HOME)/bin).
# Script installation only; the APK is installed separately with adb.
.PHONY: install
install:
	@bash scripts/install-scripts.sh

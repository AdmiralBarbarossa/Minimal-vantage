PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SYSTEMD_DIR = /etc/systemd/system

install:
	@echo "Installing Vantage TUI"
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 vantage-core.sh $(DESTDIR)$(BINDIR)/vantage-core
	install -m 755 vantage-cli.sh $(DESTDIR)$(BINDIR)/vantage
	
	# SYSTEMD CHECK
	# Create the systemd directory relative to DESTDIR.
	# Runs systemctl commands if DESTDIR is empty (meaning this is a live, manual install).
	@if command -v systemctl >/dev/null 2>&1; then \
		install -d $(DESTDIR)$(SYSTEMD_DIR); \
		install -m 644 vantage.service $(DESTDIR)$(SYSTEMD_DIR)/vantage.service; \
		if [ -z "$(DESTDIR)" ]; then \
			systemctl daemon-reload; \
			systemctl enable vantage.service; \
			echo "Installation complete! Systemd persistence is active."; \
		else \
			echo "Packaging mode (DESTDIR set). Systemd service copied, skipping live enablement."; \
		fi \
	else \
		echo "Installation complete! Non-systemd init detected. Skipping service enablement."; \
	fi

uninstall:
	@echo "Uninstalling ThinkPad Vantage..."
	# attempt to interact with the live systemctl if we aren't using DESTDIR
	@if command -v systemctl >/dev/null 2>&1 && [ -z "$(DESTDIR)" ]; then \
		systemctl disable vantage.service 2>/dev/null || true; \
		systemctl daemon-reload; \
	fi
	rm -f $(DESTDIR)$(SYSTEMD_DIR)/vantage.service
	rm -f $(DESTDIR)$(BINDIR)/vantage-core
	rm -f $(DESTDIR)$(BINDIR)/vantage
	rm -f $(DESTDIR)/etc/vantage.conf
	@echo "Uninstalled successfully."
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SYSCONFDIR ?= /etc
SYSTEMD_DIR ?= $(SYSCONFDIR)/systemd/system

.PHONY: install uninstall

install:
	@echo "Installing Minimal-vantage..."
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 vantage-core.sh $(DESTDIR)$(BINDIR)/vantage-core
	install -m 755 vantage-cli.sh $(DESTDIR)$(BINDIR)/vantage
	@if command -v systemctl >/dev/null 2>&1; then \
		echo "Installing systemd service..."; \
		install -d $(DESTDIR)$(SYSTEMD_DIR); \
		install -m 644 vantage.service $(DESTDIR)$(SYSTEMD_DIR)/vantage.service; \
		if [ -z "$(DESTDIR)" ]; then \
			systemctl daemon-reload; \
			systemctl enable vantage.service; \
			echo "Systemd service enabled."; \
		else \
			echo "Packaging mode (DESTDIR set); skipping systemctl enable."; \
		fi \
	else \
		echo "Non-systemd init detected; skipping service install."; \
	fi

uninstall:
	@echo "==> Uninstalling ThinkPad Vantage..."
	@if command -v systemctl >/dev/null 2>&1 && [ -z "$(DESTDIR)" ]; then \
		systemctl disable vantage.service 2>/dev/null || true; \
		systemctl daemon-reload 2>/dev/null || true; \
	fi
	rm -f $(DESTDIR)$(SYSTEMD_DIR)/vantage.service
	rm -f $(DESTDIR)$(BINDIR)/vantage-core
	rm -f $(DESTDIR)$(BINDIR)/vantage
	rm -f $(DESTDIR)$(SYSCONFDIR)/vantage.conf
	@echo "Uninstalled successfully"
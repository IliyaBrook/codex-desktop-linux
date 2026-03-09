BUNDLE := $(lastword $(sort $(wildcard Codex*.dmg)))

.PHONY: help build rebuild run appimage uninstall clean

help:
	@echo "Available targets:"
	@echo "  make build      - build codex-app from cached or freshly downloaded DMG"
	@echo "  make rebuild    - kill running app and rebuild codex-app"
	@echo "  make run        - launch the rebuilt Linux app"
	@echo "  make appimage   - build AppImage into project root (requires make build first)"
	@echo "  make uninstall  - remove desktop entries and icons"
	@echo "  make clean      - remove generated app output"

build:
ifdef BUNDLE
	./install.sh "$(BUNDLE)"
else
	./install.sh
endif

rebuild:
	@pkill -f '[c]odex-desktop-linux/codex-app/electron' 2>/dev/null || true
	@pkill -f '[c]odex-desktop-linux/codex-app/start.sh' 2>/dev/null || true
	@sleep 0.5
	$(MAKE) build

run:
	@if [ ! -x ./codex-app/start.sh ]; then echo "No build found. Run 'make build' first."; exit 1; fi
	./codex-app/start.sh

appimage: build
	./package-appimage.sh

uninstall:
	@pkill -f '[c]odex-desktop-linux/codex-app/electron' 2>/dev/null || true
	@pkill -f '[c]odex-desktop-linux/codex-app/start.sh' 2>/dev/null || true
	@desktop_dir="$${XDG_DATA_HOME:-$$HOME/.local/share}/applications"; \
	icon_dir="$${XDG_DATA_HOME:-$$HOME/.local/share}/icons/hicolor/256x256/apps"; \
	rm -f "$$desktop_dir/codex-appimage.desktop"; \
	rm -f "$$icon_dir/codex.png"; \
	update-desktop-database "$$desktop_dir" 2>/dev/null || true; \
	if command -v xdg-mime >/dev/null 2>&1; then \
		current=$$(xdg-mime query default x-scheme-handler/codex 2>/dev/null || true); \
		if [ "$$current" = "codex-appimage.desktop" ]; then \
			xdg-mime default "" x-scheme-handler/codex 2>/dev/null || true; \
		fi; \
	fi

clean:
	rm -rf codex-app/ tmp/AppDir/ tmp/appimagetool tmp/appimagetool-extracted Codex-*.AppImage

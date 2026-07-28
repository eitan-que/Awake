# Awake - build and installation.
#
#   make            build the app bundle into build/
#   sudo make install    install system-wide
#   sudo make uninstall  remove every installed file
#
# Installation is system-wide because the privileged helper is a LaunchDaemon,
# which has to live under /Library either way.

SWIFT_BUILD  := .build/release
BUNDLE       := build/Awake.app
CONTENTS     := $(BUNDLE)/Contents

APP_DEST     := /Applications/Awake.app
CLI_DEST     := /usr/local/bin/awake
HELPER_BIN   := /usr/local/libexec/awake-helper
AGENT_PLIST  := /Library/LaunchAgents/com.awake.app.plist
DAEMON_PLIST := /Library/LaunchDaemons/com.awake.helper.plist
AGENT_LABEL  := com.awake.app
DAEMON_LABEL := com.awake.helper

# Under sudo, id -u reports root; the GUI agent has to be bootstrapped into the
# real user's session instead.
REAL_UID := $(shell if [ -n "$$SUDO_UID" ]; then echo $$SUDO_UID; else id -u; fi)

.PHONY: all build bundle install uninstall clean check-root

all: bundle

build:
	swift build -c release

# Generated rather than committed, so the app icon and the menu bar glyph can
# never drift apart -- both come from the same SF Symbol.
Resources/Awake.icns: build Tools/MakeIcon/main.swift
	@mkdir -p build
	@rm -rf build/Awake.iconset
	$(SWIFT_BUILD)/MakeIcon build/Awake.iconset
	iconutil -c icns build/Awake.iconset -o $@

bundle: build Resources/Awake.icns
	@rm -rf $(BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Helpers $(CONTENTS)/Resources
	cp $(SWIFT_BUILD)/AwakeApp    $(CONTENTS)/MacOS/Awake
	cp $(SWIFT_BUILD)/AwakeCLI    $(CONTENTS)/Helpers/awake
	cp $(SWIFT_BUILD)/AwakeHelper $(CONTENTS)/Helpers/awake-helper
	cp Resources/Info.plist       $(CONTENTS)/Info.plist
	cp Resources/Awake.icns       $(CONTENTS)/Resources/Awake.icns
	@# Ad-hoc signature: enough for local use. Replace with a Developer ID to
	@# distribute a build others can open without Gatekeeper complaining.
	codesign --force --deep --sign - $(BUNDLE)
	@echo "built $(BUNDLE)"

check-root:
	@if [ "$$(id -u)" != "0" ]; then \
		echo "this target needs root: sudo make $(MAKECMDGOALS)"; \
		exit 1; \
	fi

install: bundle check-root
	@# Stop whatever is already running before replacing it on disk.
	-@launchctl bootout gui/$(REAL_UID)/$(AGENT_LABEL) 2>/dev/null || true
	-@launchctl bootout system/$(DAEMON_LABEL) 2>/dev/null || true

	rm -rf $(APP_DEST)
	cp -R $(BUNDLE) $(APP_DEST)
	chown -R root:wheel $(APP_DEST)

	install -d /usr/local/bin
	ln -sf $(APP_DEST)/Contents/Helpers/awake $(CLI_DEST)

	@# Already root here, so the helper goes in without a password prompt and
	@# the app never has to ask on first launch.
	$(APP_DEST)/Contents/MacOS/Awake --install-daemon

	install -o root -g wheel -m 0644 Resources/com.awake.app.plist $(AGENT_PLIST)
	launchctl bootstrap gui/$(REAL_UID) $(AGENT_PLIST)

	@echo
	@echo "Awake installed. The mug is in your menu bar; try: awake on"

uninstall: check-root
	-@launchctl bootout gui/$(REAL_UID)/$(AGENT_LABEL) 2>/dev/null || true
	-@launchctl bootout system/$(DAEMON_LABEL) 2>/dev/null || true
	rm -f $(AGENT_PLIST) $(DAEMON_PLIST) $(HELPER_BIN) $(CLI_DEST)
	rm -rf $(APP_DEST)
	@# Never leave a machine that cannot sleep behind.
	pmset -a disablesleep 0
	@echo "Awake removed and normal sleep restored."

clean:
	swift package clean
	rm -rf build Resources/Awake.icns

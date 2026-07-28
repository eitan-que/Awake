# Awake - build and installation.
#
#   make            build the app bundle into build/
#   sudo make install    install system-wide
#   sudo make uninstall  remove every installed file
#   make dmg             package build/Awake.app into dist/ for a release
#
# Installation is system-wide because the privileged helper is a LaunchDaemon,
# which has to live under /Library either way.

SWIFT_BUILD  := .build/release
BUNDLE       := build/Awake.app
CONTENTS     := $(BUNDLE)/Contents

# Info.plist is the single source of truth, so a release cannot be named a
# version the app does not report.
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DIST         := dist
DMG          := $(DIST)/Awake-$(VERSION).dmg

# Ad-hoc by default, which is all Awake needs to run. The cost is cosmetic:
# Login Items & Extensions lists the agent and the daemon as two anonymous
# rows reading "Item from unidentified developer", with no icon.
#
# That is AssociatedBundleIdentifiers -- the key in both launchd plists meant
# to fold the two jobs into a single "Awake" row -- being ignored, because
# macOS honours it only when the program carries a Team ID, and an ad-hoc
# signature has none. Signing with any real certificate supplies one; take the
# name from `security find-identity -v -p codesigning` and pass it verbatim:
#
#   sudo make install CODESIGN_ID="Apple Development: you@example.com (XXXXXXXXXX)"
#
# A free Apple ID is enough -- Xcode's Settings > Accounts > Manage
# Certificates issues an "Apple Development" certificate under a personal
# team, which has a Team ID like any other. A Developer ID is only needed to
# hand the built app to someone else.
CODESIGN_ID  ?= -

APP_DEST     := /Applications/Awake.app
CLI_DEST     := /usr/local/bin/awake
AGENT_PLIST  := /Library/LaunchAgents/com.awake.app.plist

# Separate helper binary from before the executables were merged into one.
LEGACY_HELPER := /usr/local/libexec/awake-helper
DAEMON_PLIST := /Library/LaunchDaemons/com.awake.helper.plist
AGENT_LABEL  := com.awake.app
DAEMON_LABEL := com.awake.helper

# Under sudo, id -u reports root; the GUI agent has to be bootstrapped into the
# real user's session instead.
REAL_UID := $(shell if [ -n "$$SUDO_UID" ]; then echo $$SUDO_UID; else id -u; fi)

.PHONY: all build bundle dmg install uninstall clean check-root

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
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(SWIFT_BUILD)/Awake  $(CONTENTS)/MacOS/Awake
	cp Resources/Info.plist  $(CONTENTS)/Info.plist
	cp Resources/Awake.icns  $(CONTENTS)/Resources/Awake.icns
	@# Ad-hoc signature unless CODESIGN_ID says otherwise -- see the note at
	@# the top of this file. Quoted: an identity name carries spaces and
	@# parentheses.
	codesign --force --sign "$(CODESIGN_ID)" $(BUNDLE)
	@echo "built $(BUNDLE)"

# A release asset. The Applications symlink is the usual drag-here target; the
# daemon cannot be installed from inside the disk image, so the app asks for a
# password on first launch from /Applications instead.
dmg: bundle
	@rm -rf $(DIST)/stage $(DMG)
	@mkdir -p $(DIST)/stage
	cp -R $(BUNDLE) $(DIST)/stage/
	ln -s /Applications $(DIST)/stage/Applications
	hdiutil create -volname "Awake $(VERSION)" -srcfolder $(DIST)/stage \
		-ov -quiet -format UDZO $(DMG)
	@rm -rf $(DIST)/stage
	@echo "built $(DMG)"

check-root:
	@if [ "$$(id -u)" != "0" ]; then \
		echo "this target needs root: sudo make $(MAKECMDGOALS)"; \
		exit 1; \
	fi

# Building under sudo would leave root-owned artifacts in .build/ that the
# next ordinary `swift build` cannot overwrite, so drop back to the invoking
# user for the compile and keep only the installation privileged.
#
# CODESIGN_ID is repeated explicitly because sudo clears the environment, and
# with it the MAKEFLAGS that would otherwise carry a command-line override
# into the sub-make -- which would silently sign ad-hoc despite the argument.
build-as-user:
	@if [ -n "$$SUDO_USER" ]; then \
		sudo -u "$$SUDO_USER" $(MAKE) bundle CODESIGN_ID="$(CODESIGN_ID)"; \
	else \
		$(MAKE) bundle CODESIGN_ID="$(CODESIGN_ID)"; \
	fi

# Heals a tree left by an earlier version of this Makefile, which compiled
# under sudo. Runs while still root, because that is the only way to remove
# what root created.
clean-stale: check-root
	@if [ -n "$$SUDO_USER" ]; then \
		find build .build -user root -print -quit 2>/dev/null | grep -q . \
			&& echo "removing root-owned build artifacts" \
			&& rm -rf build .build || true; \
	fi

install: check-root clean-stale build-as-user
	@# Stop whatever is already running before replacing it on disk.
	-@launchctl bootout gui/$(REAL_UID)/$(AGENT_LABEL) 2>/dev/null || true
	-@launchctl bootout system/$(DAEMON_LABEL) 2>/dev/null || true

	rm -rf $(APP_DEST)
	cp -R $(BUNDLE) $(APP_DEST)
	chown -R root:wheel $(APP_DEST)

	@# The CLI is the same binary; nothing is copied.
	install -d /usr/local/bin
	ln -sf $(APP_DEST)/Contents/MacOS/Awake $(CLI_DEST)

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
	rm -f $(AGENT_PLIST) $(DAEMON_PLIST) $(CLI_DEST)
	@# Left behind by installations from before the binaries were merged.
	rm -f $(LEGACY_HELPER)
	rm -rf $(APP_DEST)
	@# Never leave a machine that cannot sleep behind.
	pmset -a disablesleep 0
	@echo "Awake removed and normal sleep restored."

clean:
	swift package clean
	rm -rf build $(DIST) Resources/Awake.icns

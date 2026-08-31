APP      := Ledge
SCHEME   := Ledge
PROJECT  := $(APP).xcodeproj
BUILD    := build
ARCHIVE  := $(BUILD)/$(APP).xcarchive
EXPORT   := $(BUILD)/export
STAGE    := $(BUILD)/dmg
DMG      := $(BUILD)/$(APP).dmg
DERIVED  := $(BUILD)/derived
CATALOG  := Ledge/Resources/Localizable.xcstrings
LANGUAGE := tr

# Signing and notarization need two things set in the environment. Neither is
# required for `make test`, `make build` or `make clean`, which is the whole
# point of splitting them out — a contributor with no Apple Developer account
# can still run everything CI runs.
#
#   TEAM_ID         your Apple Developer team id (10 characters)
#   NOTARY_PROFILE  the name of a keychain profile created once with:
#                     xcrun notarytool store-credentials <profile-name> \
#                       --apple-id you@example.com \
#                       --team-id  TEAMID \
#                       --password <app-specific-password>
#
# Example:
#   make release TEAM_ID=ABCDE12345 NOTARY_PROFILE=ledge-notary

.DEFAULT_GOAL := help
# `export-app`, not `export`: `export` is a GNU Make directive, and a target
# sharing that name is asking a future make version to reinterpret the line.
.PHONY: help test build strings clean archive export-app dmg notarize verify \
        release require-team require-notary

help:
	@echo "Ledge"
	@echo
	@echo "  make test       run the LedgeCore suite (no signing, no Xcode account)"
	@echo "  make build      compile the app, unsigned"
	@echo "  make strings    check every UI string is in the $(LANGUAGE) catalog"
	@echo "  make clean      remove $(BUILD)/"
	@echo
	@echo "  Signing required (see the comments at the top of this file):"
	@echo "  make archive    TEAM_ID=..."
	@echo "  make dmg        TEAM_ID=..."
	@echo "  make notarize   TEAM_ID=... NOTARY_PROFILE=..."
	@echo "  make verify     check the exported app against Gatekeeper"
	@echo "  make release    test, then notarize a stapled DMG"

# --- Everything below this line runs without an Apple Developer account. -----

test:
	cd LedgeCore && swift test

# -derivedDataPath is not cosmetic: `make strings` reads the .stringsdata this
# build emits, and the default DerivedData path carries a hash that no script
# can predict. Putting it under $(BUILD) also means `make clean` clears it.
build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) -quiet \
		CODE_SIGNING_ALLOWED=NO

# Catches the gap xcodebuild leaves: it does not write newly discovered keys
# back into the source .xcstrings the way Xcode's GUI does, so a new Text("…")
# renders in English under $(LANGUAGE) forever with nothing reporting it.
#
# Depends on build because the check reads what the compiler extracted
# (SWIFT_EMIT_LOC_STRINGS), not a grep over the sources — a grep misses
# .help() tooltips, hidden Picker labels, and bare Text("\(count)").
strings: build
	@command -v python3 >/dev/null 2>&1 || { \
		echo "make strings needs python3, which is not on PATH."; \
		echo "It ships with the Xcode Command Line Tools: xcode-select --install"; \
		exit 1; }
	@python3 Scripts/check-strings.py \
		--stringsdata-root $(DERIVED) \
		--catalog $(CATALOG) \
		--language $(LANGUAGE)

clean:
	rm -rf $(BUILD)

# --- Everything below this line needs a Developer ID certificate. ------------

require-team:
ifndef TEAM_ID
	$(error TEAM_ID is not set. Pass it: make $(MAKECMDGOALS) TEAM_ID=ABCDE12345)
endif

require-notary:
ifndef NOTARY_PROFILE
	$(error NOTARY_PROFILE is not set. Create one with `xcrun notarytool store-credentials`, then pass it: make $(MAKECMDGOALS) NOTARY_PROFILE=ledge-notary)
endif

archive: require-team
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'platform=macOS' \
		-archivePath $(ARCHIVE) \
		DEVELOPMENT_TEAM=$(TEAM_ID)

export-app: archive
	rm -rf $(EXPORT)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) \
		-exportPath $(EXPORT) -exportOptionsPlist ExportOptions.plist

# A staging folder with an /Applications symlink beside the app, so the
# mounted volume is the drag-to-install window people expect rather than a
# lone binary they have to know what to do with.
dmg: export-app
	rm -rf $(STAGE) $(DMG)
	mkdir -p $(STAGE)
	cp -R $(EXPORT)/$(APP).app $(STAGE)/
	ln -s /Applications $(STAGE)/Applications
	hdiutil create -volname $(APP) -srcfolder $(STAGE) \
		-ov -format UDZO $(DMG)

notarize: require-notary dmg
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)

# Worth running before publishing: `spctl` is the check that answers the
# question users actually care about — whether Gatekeeper opens it without a
# right-click.
#
# Depends on export-app so it can never be pointed at an absent
# $(EXPORT)/$(APP).app and report success on a path that isn't there.
verify: export-app
	codesign --verify --deep --strict --verbose=2 $(EXPORT)/$(APP).app
	spctl --assess --type exec --verbose=2 $(EXPORT)/$(APP).app

release: test notarize
	@echo "Ready: $(DMG)"

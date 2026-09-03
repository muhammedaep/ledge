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
CORE_SRC := LedgeCore/Sources
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
.PHONY: help test build strings clean archive export-app dmg notarize notarize-resume verify \
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

# Two checks, reported separately so a failure says which problem it is.
#
# 1. Catalog coverage. xcodebuild does not write newly discovered keys back
#    into the source .xcstrings the way Xcode's GUI does, so a new Text("…")
#    renders in English under $(LANGUAGE) forever with nothing reporting it.
#    Depends on build because it reads what the compiler extracted
#    (SWIFT_EMIT_LOC_STRINGS) rather than grepping the sources — a grep misses
#    .help() tooltips, hidden Picker labels, and bare Text("\(count)").
#
# 2. No localization APIs in $(CORE_SRC). LedgeCore is a separate package with
#    no catalog, so a sentence written there cannot be translated at all. Core
#    carries the values; the app target composes the wording.
strings: build
	@command -v python3 >/dev/null 2>&1 || { \
		echo "make strings needs python3, which is not on PATH."; \
		echo "It ships with the Xcode Command Line Tools: xcode-select --install"; \
		exit 1; }
	@python3 Scripts/check-strings.py \
		--stringsdata-root $(DERIVED) \
		--catalog $(CATALOG) \
		--core-sources $(CORE_SRC) \
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

# `-allowProvisioningUpdates` on both signing steps: with automatic signing
# and no certificate on the machine yet, the first run creates the Apple
# Development and Developer ID Application certificates through the Apple ID
# signed into Xcode (Xcode → Settings → Accounts). Without an account the
# flag does nothing, so it costs a contributor nothing to leave it in.
archive: require-team
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'platform=macOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM_ID)

export-app: archive
	rm -rf $(EXPORT) $(BUILD)/notary-*.id
	xcodebuild -exportArchive -archivePath $(ARCHIVE) \
		-exportPath $(EXPORT) -exportOptionsPlist ExportOptions.plist \
		-allowProvisioningUpdates

# A staging folder with an /Applications symlink beside the app, so the
# mounted volume is the drag-to-install window people expect rather than a
# lone binary they have to know what to do with. A macro, because `notarize`
# packages the DMG again after stapling the app, and a `dmg` prerequisite
# would re-export first and throw that staple away.
# The image is signed too. hdiutil writes an unsigned image, and notarizing
# one is allowed — but Gatekeeper then reports "no usable signature" for the
# image itself, and only the app inside carries a verdict. Signed, both do.
SIGN_ID ?= Developer ID Application
define PACKAGE_DMG
	rm -rf $(STAGE) $(DMG) && mkdir -p $(STAGE) && cp -R $(EXPORT)/$(APP).app $(STAGE)/ && \
	ln -s /Applications $(STAGE)/Applications && \
	hdiutil create -volname $(APP) -srcfolder $(STAGE) -ov -format UDZO $(DMG) && \
	codesign --force --sign "$(SIGN_ID)" --timestamp $(DMG)
endef

dmg: export-app
	$(PACKAGE_DMG)

# Submit, then wait, then ask — three calls rather than one `submit --wait`,
# because the single call conflates three different outcomes into one exit
# code: Apple refusing the build, Apple still thinking, and the connection to
# Apple dropping. Only the first is a reason to stop. The submission id is
# written beside the build, so a run cut off by a dropped connection resumes
# with `make notarize` instead of uploading the same bytes again; `export-app`
# clears the ids because a fresh export is fresh bytes.
#   $(1) the file to notarize   $(2) a short name for the id file
define NOTARIZE
	@idfile=$(BUILD)/notary-$(2).id; \
	if [ -s "$$idfile" ]; then id=$$(cat "$$idfile"); echo "Resuming $(1): submission $$id"; \
	else id=$$(xcrun notarytool submit $(1) --keychain-profile $(NOTARY_PROFILE) --output-format json \
	        | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])') || exit 1; \
	     echo "$$id" > "$$idfile"; echo "Submitted $(1): $$id"; fi; \
	until xcrun notarytool wait "$$id" --keychain-profile $(NOTARY_PROFILE) --timeout 2h; do \
	  echo "Lost the connection to Apple while waiting; asking again in 30s."; sleep 30; done; \
	status=$$(xcrun notarytool info "$$id" --keychain-profile $(NOTARY_PROFILE) --output-format json \
	        | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'); \
	echo "Apple says: $$status"; \
	if [ "$$status" != "Accepted" ]; then echo "Apple did not accept $(1). Its log:"; \
	  xcrun notarytool log "$$id" --keychain-profile $(NOTARY_PROFILE); exit 1; fi
endef

# Twice, on purpose. The app first, so the copy a user drags into
# /Applications carries its own ticket and opens on a Mac that is offline;
# then the DMG built from that stapled app, so the disk image opens cleanly
# too. Stapling only the DMG leaves the installed app dependent on an online
# lookup at first launch.
define NOTARIZE_ALL
	@[ -s $(BUILD)/notary-app.id ] || { rm -f $(BUILD)/$(APP).zip; ditto -c -k --keepParent $(EXPORT)/$(APP).app $(BUILD)/$(APP).zip; }
	$(call NOTARIZE,$(BUILD)/$(APP).zip,app)
	xcrun stapler staple $(EXPORT)/$(APP).app
	@[ -s $(BUILD)/notary-dmg.id ] || { $(PACKAGE_DMG); }
	$(call NOTARIZE,$(DMG),dmg)
	xcrun stapler staple $(DMG)
endef

notarize: require-notary export-app
	$(NOTARIZE_ALL)

# The same steps without the export in front: for a run that was cut off
# while Apple was still thinking. Same bytes, same submission ids.
notarize-resume: require-notary
	@test -d $(EXPORT)/$(APP).app || { echo "Nothing to resume: no app at $(EXPORT)/$(APP).app."; exit 1; }
	$(NOTARIZE_ALL)

# The check that answers the question users care about: does Gatekeeper open
# it without a right-click. It runs on what will ship — the stapled app and
# the stapled DMG — and deliberately does not depend on `export-app`, which
# would replace the stapled app with a fresh, ticketless one and report
# "Unnotarized Developer ID" after a perfectly good notarization.
verify:
	@test -d $(EXPORT)/$(APP).app || { echo "No app at $(EXPORT)/$(APP).app — run make notarize first."; exit 1; }
	@test -f $(DMG) || { echo "No DMG at $(DMG) — run make notarize first."; exit 1; }
	codesign --verify --deep --strict --verbose=2 $(EXPORT)/$(APP).app
	xcrun stapler validate $(EXPORT)/$(APP).app
	spctl --assess --type exec --verbose=2 $(EXPORT)/$(APP).app
	xcrun stapler validate $(DMG)
	spctl --assess --type open --context context:primary-signature --verbose=2 $(DMG)

release: test notarize verify
	@echo "Ready: $(DMG)"

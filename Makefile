FLUTTER ?= flutter
POMODOIST_BILLING_CHANNEL ?= stripe
ASC_KEY_ID ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH ?= key-$(ASC_KEY_ID).p8
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist
IOS_IPA_PATH ?= build/ios/ipa/Pomodoist.ipa
IOS_GOOGLE_OAUTH_CONFIG ?= ios/Flutter/GoogleOAuth.xcconfig
MACOS_GOOGLE_OAUTH_CONFIG ?= macos/Runner/Configs/GoogleOAuth.xcconfig
MACOS_ARCHIVE_PATH ?= build/macos/archive/Pomodoist.xcarchive
MACOS_EXPORT_PATH ?= build/macos/export
MACOS_PKG_PATH ?= $(MACOS_EXPORT_PATH)/pomodoist.pkg
TESTFLIGHT_CONFIG ?= .env.testflight
POMODOIST_RELEASE ?= $(shell git rev-parse HEAD)
GOOGLE_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(IOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_REVERSED_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_REVERSED_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(IOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_DESKTOP_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_DESKTOP_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(MACOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_DESKTOP_CLIENT_SECRET ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_DESKTOP_CLIENT_SECRET[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(MACOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))

.PHONY: analyze test check run web build-web format testflight-preflight ios-oauth-check macos-oauth-check testflight mac-app-store

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

check: analyze test

run:
	$(FLUTTER) run --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

web:
	$(FLUTTER) run -d chrome --dart-define=POMODOIST_BILLING_CHANNEL=stripe

build-web:
	$(FLUTTER) build web --release --dart-define=POMODOIST_BILLING_CHANNEL=stripe

format:
	dart format lib test tool

testflight-preflight:
	python3 tool/check_testflight_env.py "$(TESTFLIGHT_CONFIG)"

ios-oauth-check:
	@case "$(GOOGLE_CLIENT_ID)" in *.apps.googleusercontent.com) ;; *) echo "Set GOOGLE_CLIENT_ID in $(IOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1;; esac
	@client_id="$(GOOGLE_CLIENT_ID)"; expected="com.googleusercontent.apps.$${client_id%.apps.googleusercontent.com}"; \
		test "$(GOOGLE_REVERSED_CLIENT_ID)" = "$$expected" || (echo "Set the matching GOOGLE_REVERSED_CLIENT_ID in $(IOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1)

macos-oauth-check:
	@case "$(GOOGLE_DESKTOP_CLIENT_ID)" in *.apps.googleusercontent.com) ;; *) echo "Set GOOGLE_DESKTOP_CLIENT_ID in $(MACOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1;; esac
	@case "$(GOOGLE_DESKTOP_CLIENT_SECRET)" in ""|your-*|replace-*) echo "Set GOOGLE_DESKTOP_CLIENT_SECRET in $(MACOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1;; esac

testflight: testflight-preflight ios-oauth-check
	@test -n "$(ASC_KEY_ID)" || (echo "Set ASC_KEY_ID=<App Store Connect key ID>" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "Set ASC_ISSUER_ID=<App Store Connect issuer ID>" >&2; exit 1)
	@test -f "$(ASC_KEY_PATH)" || (echo "Missing App Store Connect key: $(ASC_KEY_PATH)" >&2; exit 1)
	@$(FLUTTER) build ipa --release \
		--export-options-plist="$(IOS_EXPORT_OPTIONS)" \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit \
		--dart-define=GOOGLE_CLIENT_ID="$(GOOGLE_CLIENT_ID)"
	@test -f "$(IOS_IPA_PATH)" || (echo "Missing $(IOS_IPA_PATH)" >&2; exit 1)
	@xcrun altool --validate-app "$(IOS_IPA_PATH)" \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"
	@xcrun altool --upload-app -f "$(IOS_IPA_PATH)" \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"

mac-app-store: testflight-preflight macos-oauth-check
	@test -n "$(ASC_KEY_ID)" || (echo "Set ASC_KEY_ID=<App Store Connect key ID>" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "Set ASC_ISSUER_ID=<App Store Connect issuer ID>" >&2; exit 1)
	@test -f "$(ASC_KEY_PATH)" || (echo "Missing App Store Connect key: $(ASC_KEY_PATH)" >&2; exit 1)
	@$(FLUTTER) build macos --release --config-only \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit \
		--dart-define=GOOGLE_DESKTOP_CLIENT_ID="$(GOOGLE_DESKTOP_CLIENT_ID)" \
		--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET="$(GOOGLE_DESKTOP_CLIENT_SECRET)"
	xcodebuild -workspace macos/Runner.xcworkspace \
		-scheme Runner \
		-configuration Release \
		-destination generic/platform=macOS \
		-archivePath "$(MACOS_ARCHIVE_PATH)" \
		-allowProvisioningUpdates archive
	xcodebuild -exportArchive \
		-archivePath "$(MACOS_ARCHIVE_PATH)" \
		-exportPath "$(MACOS_EXPORT_PATH)" \
		-exportOptionsPlist "$(IOS_EXPORT_OPTIONS)" \
		-allowProvisioningUpdates
	@test -f "$(MACOS_PKG_PATH)" || (echo "Missing $(MACOS_PKG_PATH)" >&2; exit 1)
	@xcrun altool --validate-app -f "$(MACOS_PKG_PATH)" -t macos \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"
	@xcrun altool --upload-app -f "$(MACOS_PKG_PATH)" -t macos \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"

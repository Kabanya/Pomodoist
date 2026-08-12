FLUTTER ?= flutter
POMODOIST_BILLING_CHANNEL ?= stripe
ASC_KEY_ID ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH ?= key-$(ASC_KEY_ID).p8
IOS_ARCHIVE_PATH ?= build/ios/archive/Runner.xcarchive
IOS_EXPORT_PATH ?= build/ios/export
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist

.PHONY: analyze test check run web build-web format testflight

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

testflight:
	@test -n "$(ASC_KEY_ID)" || (echo "Set ASC_KEY_ID=<App Store Connect key ID>" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "Set ASC_ISSUER_ID=<App Store Connect issuer ID>" >&2; exit 1)
	@test -f "$(ASC_KEY_PATH)" || (echo "Missing App Store Connect key: $(ASC_KEY_PATH)" >&2; exit 1)
	$(FLUTTER) build ios --release --no-codesign \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit
	xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
		-configuration Release -destination generic/platform=iOS \
		-archivePath "$(IOS_ARCHIVE_PATH)" archive
	xcodebuild -exportArchive -archivePath "$(IOS_ARCHIVE_PATH)" \
		-exportPath "$(IOS_EXPORT_PATH)" \
		-exportOptionsPlist "$(IOS_EXPORT_OPTIONS)"
	@test -f "$(IOS_EXPORT_PATH)/Pomodoist.ipa" || (echo "Missing $(IOS_EXPORT_PATH)/Pomodoist.ipa" >&2; exit 1)
	xcrun altool --upload-app -f "$(IOS_EXPORT_PATH)/Pomodoist.ipa" \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"

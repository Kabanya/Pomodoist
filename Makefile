# Pomodoist development commands
.DEFAULT_GOAL := help

# Tools
FLUTTER ?= flutter

# Runtime
POMODOIST_BILLING_CHANNEL ?= stripe

# TestFlight
ASC_KEY_ID ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH ?= key-$(ASC_KEY_ID).p8
IOS_ARCHIVE_PATH ?= build/ios/archive/Runner.xcarchive
IOS_EXPORT_PATH ?= build/ios/export
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist

.PHONY: help setup run web analyze test check format build-web build-macos-debug build-macos-release testflight devices clean

help:
	@if [ -t 1 ] && [ -z "$${NO_COLOR:-}" ]; then \
		red="$$(printf '\033[31m')"; \
		bold="$$(printf '\033[1m')"; \
		dim="$$(printf '\033[2m')"; \
		reset="$$(printf '\033[0m')"; \
	else \
		red=''; bold=''; dim=''; reset=''; \
	fi; \
	printf '\n%s\n' "$${red}$${bold}██████╗  ██████╗ ███╗   ███╗ ██████╗ ██████╗  ██████╗ ██╗███████╗████████╗"; \
	printf '%s\n' "$${red}$${bold}██╔══██╗██╔═══██╗████╗ ████║██╔═══██╗██╔══██╗██╔═══██╗██║██╔════╝╚══██╔══╝"; \
	printf '%s\n' "$${red}$${bold}██████╔╝██║   ██║██╔████╔██║██║   ██║██║  ██║██║   ██║██║███████╗   ██║"; \
	printf '%s\n' "$${red}$${bold}██╔═══╝ ██║   ██║██║╚██╔╝██║██║   ██║██║  ██║██║   ██║██║╚════██║   ██║"; \
	printf '%s\n' "$${red}$${bold}██║     ╚██████╔╝██║ ╚═╝ ██║╚██████╔╝██████╔╝╚██████╔╝██║███████║   ██║"; \
	printf '%s\n' "$${red}$${bold}╚═╝      ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝╚══════╝   ╚═╝$${reset}"; \
	printf '%s%s%s\n' "$${dim}" 'Tasks • Focus • Reports' "$${reset}"; \
	printf '\n%sUsage:%s make <target> [VARIABLE=value]\n' "$${bold}" "$${reset}"; \
	printf '\n%s%sGetting started%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make setup' "$${reset}" 'Resolve Flutter dependencies'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make run' "$${reset}" 'Run Pomodoist on a connected device'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make web' "$${reset}" 'Run Pomodoist in Chrome'; \
	printf '\n%s%sQuality%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make analyze' "$${reset}" 'Analyze Dart code'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make test' "$${reset}" 'Run Flutter tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make check' "$${reset}" 'Run analysis and tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make format' "$${reset}" 'Format source files'; \
	printf '\n%s%sBuild & release%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-web' "$${reset}" 'Build the release web app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-macos-debug' "$${reset}" 'Build the debug macOS app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-macos-release' "$${reset}" 'Build the release macOS app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make testflight' "$${reset}" 'Build and upload the iOS app'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-26s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

setup:
	$(FLUTTER) pub get

run:
	$(FLUTTER) run --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

web:
	$(FLUTTER) run -d chrome --dart-define=POMODOIST_BILLING_CHANNEL=stripe

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

check: analyze test

format:
	dart format lib test tool

build-web:
	$(FLUTTER) build web --release --dart-define=POMODOIST_BILLING_CHANNEL=stripe

build-macos-debug:
	$(FLUTTER) build macos --debug --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

build-macos-release:
	$(FLUTTER) build macos --release --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

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

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean

# Pomodoist development commands
.DEFAULT_GOAL := help

# Tools. Prefer the project-pinned FVM SDK when it has been bootstrapped.
FVM_FLUTTER := .fvm/flutter_sdk/bin/flutter
FLUTTER ?= $(if $(wildcard $(FVM_FLUTTER)),$(FVM_FLUTTER),flutter)

# Runtime
POMODOIST_BILLING_CHANNEL ?= stripe

# Windows
WINDOWS_CONFIG ?= C:/secure/pomodoist-windows-production.json
WINDOWS_RELEASE_DIR ?= build/windows/x64/runner/Release

# TestFlight
ASC_KEY_ID ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH ?= key-$(ASC_KEY_ID).p8
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist
IOS_IPA_PATH ?= build/ios/ipa/Pomodoist.ipa
IOS_GOOGLE_OAUTH_CONFIG ?= ios/Flutter/GoogleOAuth.xcconfig
MACOS_GOOGLE_OAUTH_CONFIG ?= macos/Runner/Configs/GoogleOAuth.xcconfig
TESTFLIGHT_CONFIG ?= .env.testflight
POMODOIST_RELEASE ?= $(shell git rev-parse HEAD)
GOOGLE_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(IOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_REVERSED_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_REVERSED_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(IOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_DESKTOP_CLIENT_ID ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_DESKTOP_CLIENT_ID[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(MACOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
GOOGLE_DESKTOP_CLIENT_SECRET ?= $(strip $(shell awk -F= '/^[[:space:]]*GOOGLE_DESKTOP_CLIENT_SECRET[[:space:]]*=/{sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$$/, ""); print; exit}' "$(MACOS_GOOGLE_OAUTH_CONFIG)" 2>/dev/null))
export GOOGLE_DESKTOP_CLIENT_ID GOOGLE_DESKTOP_CLIENT_SECRET

.PHONY: help setup setup-linux run run-linux web analyze test test-linux-installer test-linux-appimage test-linux-packaging check format build-web build-linux-release build-linux-appimage install-linux windows-installer build-macos-debug build-macos-release testflight-preflight ios-oauth-check macos-oauth-check testflight devices clean

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
	printf '  %s%-26s%s %s\n' "$${bold}" 'make setup-linux' "$${reset}" 'Prepare an Arch Linux workstation'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make run' "$${reset}" 'Run Pomodoist on a connected device'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make run-linux' "$${reset}" 'Run the native Linux desktop app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make web' "$${reset}" 'Run Pomodoist in Chrome'; \
	printf '\n%s%sQuality%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make analyze' "$${reset}" 'Analyze Dart code'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make test' "$${reset}" 'Run Flutter tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make test-linux-packaging' "$${reset}" 'Test Linux installers and AppImage layout'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make check' "$${reset}" 'Run analysis and tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make format' "$${reset}" 'Format source files'; \
	printf '\n%s%sBuild & release%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-web' "$${reset}" 'Build the release web app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-linux-appimage' "$${reset}" 'Build the distributable Linux AppImage'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-linux-release' "$${reset}" 'Build the raw Linux developer bundle'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make install-linux' "$${reset}" 'Install Pomodoist for the current user'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make windows-installer' "$${reset}" 'Build the Windows EXE installer'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-macos-debug' "$${reset}" 'Build the debug macOS app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make build-macos-release' "$${reset}" 'Build the release macOS app'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make testflight' "$${reset}" 'Build and upload the iOS app'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-26s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

setup:
	$(FLUTTER) pub get

setup-linux:
	./tool/linux/setup_arch.sh

run:
	$(FLUTTER) run --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

run-linux:
	$(FLUTTER) run -d linux --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

web:
	$(FLUTTER) run -d chrome --dart-define=POMODOIST_BILLING_CHANNEL=stripe

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

test-linux-installer:
	./tool/linux/test_install.sh

test-linux-appimage:
	./tool/linux/test_appimage.sh

test-linux-packaging: test-linux-installer test-linux-appimage

check: analyze test

format:
	dart format lib test tool

build-web:
	$(FLUTTER) build web --release --dart-define=POMODOIST_BILLING_CHANNEL=stripe

build-linux-release:
	$(FLUTTER) build linux --release --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

build-linux-appimage: build-linux-release
	./tool/linux/build_appimage.sh

install-linux: build-linux-release
	./tool/linux/install.sh

windows-installer:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\windows\build.ps1 -Configuration Release -Clean -ConfigFile "$(WINDOWS_CONFIG)" -ReleaseSha "$(POMODOIST_RELEASE)"
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\windows\installer\build.ps1 -BuildDirectory "$(WINDOWS_RELEASE_DIR)"

build-macos-debug:
	$(FLUTTER) build macos --debug --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

build-macos-release: testflight-preflight macos-oauth-check
	$(FLUTTER) build macos --release \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

testflight-preflight:
	python3 tool/check_testflight_env.py "$(TESTFLIGHT_CONFIG)"

ios-oauth-check:
	@case "$(GOOGLE_CLIENT_ID)" in *.apps.googleusercontent.com) ;; *) echo "Set GOOGLE_CLIENT_ID in $(IOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1;; esac
	@client_id="$(GOOGLE_CLIENT_ID)"; expected="com.googleusercontent.apps.$${client_id%.apps.googleusercontent.com}"; \
		test "$(GOOGLE_REVERSED_CLIENT_ID)" = "$$expected" || (echo "Set the matching GOOGLE_REVERSED_CLIENT_ID in $(IOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1)

macos-oauth-check:
	@case "$$GOOGLE_DESKTOP_CLIENT_ID" in *.apps.googleusercontent.com) ;; *) echo "Set GOOGLE_DESKTOP_CLIENT_ID in $(MACOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1;; esac
	@test -n "$$GOOGLE_DESKTOP_CLIENT_SECRET" || (echo "Set GOOGLE_DESKTOP_CLIENT_SECRET in $(MACOS_GOOGLE_OAUTH_CONFIG)" >&2; exit 1)

testflight: testflight-preflight ios-oauth-check
	@test -n "$(ASC_KEY_ID)" || (echo "Set ASC_KEY_ID=<App Store Connect key ID>" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "Set ASC_ISSUER_ID=<App Store Connect issuer ID>" >&2; exit 1)
	@test -f "$(ASC_KEY_PATH)" || (echo "Missing App Store Connect key: $(ASC_KEY_PATH)" >&2; exit 1)
	$(FLUTTER) build ipa --release \
		--export-options-plist="$(IOS_EXPORT_OPTIONS)" \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit \
		--dart-define=GOOGLE_CLIENT_ID="$(GOOGLE_CLIENT_ID)"
	@test -f "$(IOS_IPA_PATH)" || (echo "Missing $(IOS_IPA_PATH)" >&2; exit 1)
	xcrun altool --validate-app "$(IOS_IPA_PATH)" \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"
	xcrun altool --upload-app -f "$(IOS_IPA_PATH)" \
		--api-key "$(ASC_KEY_ID)" \
		--api-issuer "$(ASC_ISSUER_ID)" \
		--p8-file-path "$(ASC_KEY_PATH)"

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean

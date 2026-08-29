# Pomodoist development commands
.DEFAULT_GOAL := help

# GNU Make launched from PowerShell otherwise uses cmd.exe, while this file
# intentionally uses POSIX recipes. Git for Windows provides the shell.
ifeq ($(OS),Windows_NT)
SHELL := C:/Program Files/Git/bin/bash.exe
endif

# Tools. Prefer the project-pinned FVM SDK when it has been bootstrapped.
FVM_FLUTTER := .fvm/flutter_sdk/bin/flutter
FLUTTER ?= $(if $(wildcard $(FVM_FLUTTER)),$(FVM_FLUTTER),flutter)
FVM_DART := .fvm/flutter_sdk/bin/dart
DART ?= $(if $(wildcard $(FVM_DART)),$(FVM_DART),dart)

# Runtime
POMODOIST_BILLING_CHANNEL ?= stripe

# Linux release downloads use direct HTTPS. This prevents stale localhost
# proxy variables from breaking reproducible local builds.
LINUX_BUILD_ENV ?= env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY
POMODOIST_APPIMAGE_BUILDER ?= ./tool/linux/build_appimage.sh
LINUX_CONFIG ?= $(CURDIR)/.env.linux-production.json

# Windows
WINDOWS_CONFIG ?= C:/secure/pomodoist-windows-production.json
WINDOWS_RELEASE_DIR ?= build/windows/x64/runner/Release

# TestFlight
ASC_KEY_ID ?=
ASC_ISSUER_ID ?=
ASC_KEY_PATH ?= key-$(ASC_KEY_ID).p8
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist
IOS_IPA_PATH ?= build/ios/ipa/Pomodoist.ipa
TESTFLIGHT_CONFIG ?= .env.testflight
POMODOIST_RELEASE ?= $(shell git rev-parse HEAD)

.PHONY: setup setup-linux run run-linux web
.PHONY: analyze test test-linux-installer test-linux-appimage test-linux-build-network test-linux-packaging check format
.PHONY: web-debug web-profile web-release
.PHONY: linux-pub-get linux-debug linux-profile linux-release linux-appimage linux-install
.PHONY: windows-debug windows-profile windows-release windows-installer
.PHONY: macos-debug macos-profile macos-release
.PHONY: ios-debug ios-profile ios-release testflight-preflight testflight
.PHONY: help devices clean

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
	printf '\n%s%sSetup & run%s\n' "$${red}" "$${bold}" "$${reset}"; \
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
	printf '\n%s%sRelease & distribution%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-9s %-26s %s%s\n' "$${dim}" 'Platform' 'Command' 'Action' "$${reset}"; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-release' "$${reset}" 'Release app'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-release' "$${reset}" 'Raw developer bundle'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-appimage' "$${reset}" 'Distributable AppImage'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-install' "$${reset}" 'Install for current user'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-release' "$${reset}" 'Release app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-installer' "$${reset}" 'EXE installer'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-release' "$${reset}" 'Release app'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make ios-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make ios-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make ios-release' "$${reset}" 'Release app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make testflight' "$${reset}" 'Upload to TestFlight'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-26s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

setup:
	$(FLUTTER) pub get

setup-linux:
	./tool/linux/setup_arch.sh

run:
	$(FLUTTER) run --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

run-linux:
	$(FLUTTER) run -d linux --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

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

test-linux-build-network:
	./tool/linux/test_make_build.sh

test-linux-packaging: test-linux-installer test-linux-appimage test-linux-build-network

check: analyze test

format:
	$(DART) format lib test tool

web-debug:
	$(FLUTTER) build web --debug --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-profile:
	$(FLUTTER) build web --profile --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-release:
	$(FLUTTER) build web --release --dart-define=POMODOIST_BILLING_CHANNEL=stripe

linux-pub-get:
	$(LINUX_BUILD_ENV) bash ./tool/linux/pub_get_with_retry.sh "$(FLUTTER)"

linux-debug: linux-pub-get
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --debug --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-profile: linux-pub-get
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --profile --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-release: linux-pub-get
	$(LINUX_BUILD_ENV) $(DART) run tool/desktop_release_config.dart --config "$(LINUX_CONFIG)"
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --release --dart-define-from-file="$(LINUX_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

linux-appimage: linux-release
	$(LINUX_BUILD_ENV) $(POMODOIST_APPIMAGE_BUILDER)

linux-install: linux-release
	./tool/linux/install.sh

windows-debug:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Debug

windows-profile:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Profile

windows-release:
	$(DART) run tool/desktop_release_config.dart --config "$(WINDOWS_CONFIG)"
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Release -Clean -ConfigFile "$(WINDOWS_CONFIG)" -ReleaseSha "$(POMODOIST_RELEASE)"

windows-installer: windows-release
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/installer/build.ps1 -BuildDirectory "$(WINDOWS_RELEASE_DIR)"

macos-debug:
	$(FLUTTER) build macos --debug --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

macos-profile:
	$(FLUTTER) build macos --profile --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

macos-release: testflight-preflight
	$(FLUTTER) build macos --release \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

testflight-preflight:
	python3 tool/check_testflight_env.py "$(TESTFLIGHT_CONFIG)"

ios-debug:
	$(FLUTTER) build ios --debug --dart-define=POMODOIST_BILLING_CHANNEL=storekit

ios-profile:
	$(FLUTTER) build ios --profile --dart-define=POMODOIST_BILLING_CHANNEL=storekit

ios-release: testflight-preflight
	$(FLUTTER) build ios --release \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

testflight: testflight-preflight
	@test -n "$(ASC_KEY_ID)" || (echo "Set ASC_KEY_ID=<App Store Connect key ID>" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "Set ASC_ISSUER_ID=<App Store Connect issuer ID>" >&2; exit 1)
	@test -f "$(ASC_KEY_PATH)" || (echo "Missing App Store Connect key: $(ASC_KEY_PATH)" >&2; exit 1)
	$(FLUTTER) build ipa --release \
		--export-options-plist="$(IOS_EXPORT_OPTIONS)" \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit
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

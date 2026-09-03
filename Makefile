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
IOS_SIMULATOR ?= iPhone 17 Pro
IPAD_SIMULATOR ?= iPad Pro 13-inch (M5)
WATCH_SIMULATOR ?= Apple Watch Series 11 (46mm)
WATCH_BUILD_DIR ?= build/watch-simulator
WATCH_BUILD_PATH = $(abspath $(WATCH_BUILD_DIR))

# Linux release downloads use direct HTTPS. This prevents stale localhost
# proxy variables from breaking reproducible local builds.
LINUX_BUILD_ENV ?= env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY
POMODOIST_APPIMAGE_BUILDER ?= ./tool/linux/build_appimage.sh
LOCAL_CONFIG ?= .env.local
LINUX_CONFIG ?= .env.linux

# Windows
WINDOWS_CONFIG ?= .env.windows
WINDOWS_RELEASE_DIR ?= build/windows/x64/runner/Release

# TestFlight credentials stay in the private env and are never Dart defines.
PRIVATE_CONFIG ?= .env.private
ASC_KEY_ID ?= $(shell $(DART) tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_KEY_ID 2>/dev/null)
ASC_ISSUER_ID ?= $(shell $(DART) tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_ISSUER_ID 2>/dev/null)
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist
IOS_IPA_PATH ?= build/ios/ipa/Pomodoist.ipa
TESTFLIGHT_CONFIG ?= .env.testflight
DEPLOY_CONFIG ?= .env.deploy
POMODOIST_RELEASE ?= $(shell git rev-parse HEAD)

.PHONY: setup setup-env setup-flutter setup-linux run run-linux web
.PHONY: analyze test test-linux-installer test-linux-appimage test-linux-build-network test-linux-packaging check format
.PHONY: web-debug web-profile web-release
.PHONY: linux-pub-get linux-debug linux-profile linux-release linux-appimage linux-install
.PHONY: windows-debug windows-profile windows-release windows-installer
.PHONY: macos-debug macos-profile macos-release
.PHONY: ios-debug ios-profile ipad-debug ipad-profile watch-debug watch-profile testflight-preflight testflight-auth testflight-ios testflight-macos testflight
.PHONY: deploy-staging deploy-production deploy-all
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
	printf '  %s%-26s%s %s\n' "$${bold}" 'make setup' "$${reset}" 'Full setup: env files + Flutter dependencies'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make setup-env' "$${reset}" 'Create the .env.setup template'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make setup-flutter' "$${reset}" 'Generate env files and resolve Flutter dependencies'; \
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
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iPhone' "$${reset}" "$${bold}" 'make ios-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iPhone' "$${reset}" "$${bold}" 'make ios-profile' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iPad' "$${reset}" "$${bold}" 'make ipad-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iPad' "$${reset}" "$${bold}" 'make ipad-profile' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Watch' "$${reset}" "$${bold}" 'make watch-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Watch' "$${reset}" "$${bold}" 'make watch-profile' "$${reset}" 'Run Simulator (profile)'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make testflight-ios' "$${reset}" 'Upload iOS to TestFlight'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make testflight-macos' "$${reset}" 'Upload macOS to TestFlight'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'All' "$${reset}" "$${bold}" 'make testflight' "$${reset}" 'Upload iOS + macOS to TestFlight'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-staging' "$${reset}" 'Deploy backend + web staging'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-production' "$${reset}" 'Deploy backend + web production'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-all' "$${reset}" 'Deploy staging, then production'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-26s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

setup: setup-env setup-flutter

setup-env:
	$(DART) tool/env_setup.dart bootstrap

setup-flutter: setup-env
	$(DART) tool/env_setup.dart sync
	$(FLUTTER) pub get

setup-linux: setup-env
	./tool/linux/setup_arch.sh

run:
	$(FLUTTER) run --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

run-linux:
	$(FLUTTER) run -d linux --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

web:
	$(FLUTTER) run -d chrome --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

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
	$(FLUTTER) build web --debug --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-profile:
	$(FLUTTER) build web --profile --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-release:
	$(FLUTTER) build web --release --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

linux-pub-get:
	$(LINUX_BUILD_ENV) bash ./tool/linux/pub_get_with_retry.sh "$(FLUTTER)"

linux-debug: linux-pub-get
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --debug --dart-define-from-file="$(LINUX_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-profile: linux-pub-get
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --profile --dart-define-from-file="$(LINUX_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-release: linux-pub-get
	$(LINUX_BUILD_ENV) $(DART) tool/desktop_release_config.dart --config "$(LINUX_CONFIG)"
	$(LINUX_BUILD_ENV) $(FLUTTER) build linux --release --dart-define-from-file="$(LINUX_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

linux-appimage: linux-release
	$(LINUX_BUILD_ENV) $(POMODOIST_APPIMAGE_BUILDER)

linux-install: linux-release
	./tool/linux/install.sh

windows-debug:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Debug -ConfigFile "$(WINDOWS_CONFIG)"

windows-profile:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Profile -ConfigFile "$(WINDOWS_CONFIG)"

windows-release:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Release -Clean -ConfigFile "$(WINDOWS_CONFIG)" -ReleaseSha "$(POMODOIST_RELEASE)"

windows-installer: windows-release
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/installer/build.ps1 -BuildDirectory "$(WINDOWS_RELEASE_DIR)"

macos-debug:
	$(FLUTTER) build macos --debug \
		--dart-define-from-file="$(LOCAL_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

macos-profile:
	$(FLUTTER) build macos --profile \
		--dart-define-from-file="$(LOCAL_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

macos-release: testflight-preflight
	$(FLUTTER) build macos --release \
		--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

# Flutter profile mode is unavailable on iOS Simulator, so local runs use debug.
ios-debug ios-profile: RUN_SIMULATOR = $(IOS_SIMULATOR)
ipad-debug ipad-profile: RUN_SIMULATOR = $(IPAD_SIMULATOR)
ios-debug ios-profile ipad-debug ipad-profile:
	xcrun simctl bootstatus "$(RUN_SIMULATOR)" -b
	open -a Simulator
	$(FLUTTER) run -d "$(RUN_SIMULATOR)" --debug --dart-define-from-file="$(LOCAL_CONFIG)" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=storekit

watch-debug: WATCH_CONFIGURATION = Debug
watch-profile: WATCH_CONFIGURATION = Profile
watch-debug watch-profile:
	xcrun simctl bootstatus "$(WATCH_SIMULATOR)" -b
	open -a Simulator
	xcodebuild -quiet -project ios/Runner.xcodeproj -target PomodoistWatch -configuration "$(WATCH_CONFIGURATION)" -sdk watchsimulator SYMROOT="$(WATCH_BUILD_PATH)" OBJROOT="$(WATCH_BUILD_PATH)/obj" build
	xcrun simctl install "$(WATCH_SIMULATOR)" "$(WATCH_BUILD_PATH)/$(WATCH_CONFIGURATION)-watchsimulator/PomodoistWatch.app"
	xcrun simctl launch "$(WATCH_SIMULATOR)" com.finchforge.pomodoist.watchkitapp

testflight: testflight-ios testflight-macos

deploy-staging deploy-production deploy-all:
	@set -eu; \
		runner="$$( $(DART) tool/env_setup.dart value --env "$(DEPLOY_CONFIG)" --key RUNNER )"; \
		"$$runner" "$(patsubst deploy-%,%,$@)" "$(CURDIR)" "$(abspath $(DEPLOY_CONFIG))"

testflight-preflight:
	python3 tool/check_testflight_env.py "$(TESTFLIGHT_CONFIG)"

testflight-auth:
	@test -f "$(PRIVATE_CONFIG)" || (echo "Missing $(PRIVATE_CONFIG); run make setup-flutter" >&2; exit 1)
	@test -n "$(ASC_KEY_ID)" || (echo "ASC_KEY_ID is missing in $(PRIVATE_CONFIG)" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "ASC_ISSUER_ID is missing in $(PRIVATE_CONFIG)" >&2; exit 1)
	@$(DART) tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_PRIVATE_KEY_BASE64 >/dev/null

testflight-ios: testflight-preflight testflight-auth
	@set -eu; \
		key_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/pomodoist-testflight.XXXXXX")"; \
		trap 'test -n "$$key_dir" && rm -rf -- "$$key_dir"' EXIT HUP INT TERM; \
		key_path="$$key_dir/AuthKey_$(ASC_KEY_ID).p8"; \
		$(DART) tool/env_setup.dart write-asc-key --env "$(PRIVATE_CONFIG)" --output "$$key_path"; \
		$(FLUTTER) build ipa --release \
			--export-options-plist="$(IOS_EXPORT_OPTIONS)" \
			--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit; \
		test -f "$(IOS_IPA_PATH)" || (echo "Missing $(IOS_IPA_PATH)" >&2; exit 1); \
		xcrun altool --validate-app "$(IOS_IPA_PATH)" \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"; \
		xcrun altool --upload-app -f "$(IOS_IPA_PATH)" \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"

MACOS_ARCHIVE_PATH = $(abspath build/TestFlight/Pomodoist-macOS.xcarchive)
MACOS_EXPORT_PATH = $(abspath build/TestFlight/macos)
MACOS_PACKAGE_PATH = $(MACOS_EXPORT_PATH)/pomodoist.pkg

testflight-macos: testflight-preflight testflight-auth
	@set -eu; \
		key_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/pomodoist-testflight.XXXXXX")"; \
		trap 'test -n "$$key_dir" && rm -rf -- "$$key_dir"' EXIT HUP INT TERM; \
		key_path="$$key_dir/AuthKey_$(ASC_KEY_ID).p8"; \
		$(DART) tool/env_setup.dart write-asc-key --env "$(PRIVATE_CONFIG)" --output "$$key_path"; \
		$(FLUTTER) build macos --release \
			--dart-define-from-file="$(TESTFLIGHT_CONFIG)" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit; \
		rm -rf "$(MACOS_ARCHIVE_PATH)" "$(MACOS_EXPORT_PATH)"; \
		xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
			-configuration Release -archivePath "$(MACOS_ARCHIVE_PATH)" archive \
			-hideShellScriptEnvironment \
			-allowProvisioningUpdates \
			-authenticationKeyPath "$$key_path" \
			-authenticationKeyID "$(ASC_KEY_ID)" \
			-authenticationKeyIssuerID "$(ASC_ISSUER_ID)"; \
		xcodebuild -exportArchive \
			-archivePath "$(MACOS_ARCHIVE_PATH)" \
			-exportPath "$(MACOS_EXPORT_PATH)" \
			-exportOptionsPlist "$(IOS_EXPORT_OPTIONS)" \
			-allowProvisioningUpdates \
			-authenticationKeyPath "$$key_path" \
			-authenticationKeyID "$(ASC_KEY_ID)" \
			-authenticationKeyIssuerID "$(ASC_ISSUER_ID)"; \
		test -f "$(MACOS_PACKAGE_PATH)" || (echo "Missing $(MACOS_PACKAGE_PATH)" >&2; exit 1); \
		xcrun altool --validate-app "$(MACOS_PACKAGE_PATH)" \
			--type macos \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"; \
		xcrun altool --upload-app -f "$(MACOS_PACKAGE_PATH)" \
			--type macos \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean

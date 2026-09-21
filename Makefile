# Pomodoist development commands
.DEFAULT_GOAL := help

# GNU Make launched from PowerShell otherwise uses cmd.exe, while this file
# intentionally uses POSIX recipes. Git for Windows provides the shell.
ifeq ($(OS),Windows_NT)
SHELL := C:/Program Files/Git/bin/bash.exe
endif

REPO_ROOT := $(CURDIR)
# Make abspath splits paths at spaces; configuration paths are single values.
repo_path      = $(if $(or $(filter /%,$(firstword $(1))),$(findstring :/,$(firstword $(1)))),$(1),$(REPO_ROOT)/$(1))
FLUTTER_ROOT  := $(REPO_ROOT)/apps/flutter
# Flutter always writes to <project>/build and keeps its compile cache in
# <project>/.dart_tool. Both paths are symlinks to the repository-root build
# directory. Every generated artifact lands under build/, including the Dart
# tool state, and nothing is left next to the sources.
FLUTTER_BUILD     := $(REPO_ROOT)/build/flutter
FLUTTER_DART_TOOL := $(REPO_ROOT)/build/dart_tool
FLUTTER_LINK      := $(FLUTTER_ROOT)/build
DART_TOOL_LINK    := $(FLUTTER_ROOT)/.dart_tool
# Git Bash cannot create junctions, so Windows delegates to the same script
# tool/windows/build.ps1 runs; PowerShell is available on every supported setup.
ifeq ($(OS),Windows_NT)
LINK_FLUTTER_BUILD = powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(REPO_ROOT)/tool/windows/link-build.ps1"
else
LINK_FLUTTER_BUILD = mkdir -p "$(FLUTTER_BUILD)" "$(FLUTTER_DART_TOOL)" && \
	{ [ -L "$(FLUTTER_LINK)" ] || { rm -rf "$(FLUTTER_LINK)"; ln -s ../../build/flutter "$(FLUTTER_LINK)"; }; } && \
	{ [ -L "$(DART_TOOL_LINK)" ] || { rm -rf "$(DART_TOOL_LINK)"; ln -s ../../build/dart_tool "$(DART_TOOL_LINK)"; }; }
endif

# Restores the build and .dart_tool symlinks after flutter clean removes them
# or a Flutter process replaces them with real directories.
.PHONY: flutter-build-link
flutter-build-link:
	@$(LINK_FLUTTER_BUILD)

# Tools. Prefer the project-pinned FVM SDK when it has been bootstrapped.
FVM_FLUTTER := $(REPO_ROOT)/.fvm/flutter_sdk/bin/flutter
FLUTTER     ?= $(if $(wildcard .fvm/flutter_sdk/bin/flutter),$(FVM_FLUTTER),flutter)
FVM_DART    := $(REPO_ROOT)/.fvm/flutter_sdk/bin/dart
DART        ?= $(if $(wildcard .fvm/flutter_sdk/bin/dart),$(FVM_DART),dart)

# Runtime defaults
POMODOIST_BILLING_CHANNEL ?= stripe

# Simulators and their local build output
IOS_SIMULATOR   ?= iPhone 17 Pro
IPAD_SIMULATOR  ?= iPad Pro 13-inch (M5)
WATCH_SIMULATOR ?= Apple Watch Series 11 (46mm)
WATCH_BUILD_DIR ?= build/watch-simulator
WATCH_BUILD_PATH = $(call repo_path,$(WATCH_BUILD_DIR))

# Linux packaging. Release downloads use direct HTTPS, which prevents stale
# localhost proxy variables from breaking reproducible local builds.
LINUX_BUILD_ENV ?= env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY
POMODOIST_APPIMAGE_BUILDER ?= ./tool/linux/build_appimage.sh

# Flutter dart-define files. LOCAL and STAGING are shared environments; the
# platform files carry production values.
LOCAL_CONFIG ?= .env.local
STAGING_CONFIG ?= .env.staging
# TestFlight uploads production by default; TESTFLIGHT_ENV=staging uploads a
# staging client.
TESTFLIGHT_ENV    ?= production
TESTFLIGHT_CONFIG ?= $(if $(filter staging,$(TESTFLIGHT_ENV)),$(STAGING_CONFIG),.env.testflight)
LINUX_CONFIG   ?= .env.linux
WINDOWS_CONFIG ?= .env.windows
ANDROID_CONFIG ?= .env.android

# Flutter entry points. Each entry point declares the environment it serves and
# refuses to start when the dart-define file names another one, so every run and
# build passes --target next to --dart-define-from-file.
LOCAL_TARGET      ?= lib/main_development.dart
STAGING_TARGET    ?= lib/main_staging.dart
PRODUCTION_TARGET ?= lib/main.dart
# The entry point follows the TestFlight environment choice above.
TESTFLIGHT_TARGET ?= $(if $(filter staging,$(TESTFLIGHT_ENV)),$(STAGING_TARGET),$(PRODUCTION_TARGET))
# make android builds the debug APK described in tool/android/README.md. Its
# entry point is read back from the dart-define file so the pair cannot drift:
# local -> development, staging -> staging, anything else (a production or
# selfhosted profile, a JSON file the reader cannot parse, an unreadable file)
# -> production. Override ANDROID_CONFIG for another profile, or ANDROID_TARGET
# to force an entry point.
ANDROID_ENVIRONMENT ?= $(shell "$(DART)" tool/env_setup.dart value --env "$(call repo_path,$(ANDROID_CONFIG))" --key POMODOIST_ENVIRONMENT 2>/dev/null)
ANDROID_TARGET ?= $(if $(filter local,$(ANDROID_ENVIRONMENT)),$(LOCAL_TARGET),$(if $(filter staging,$(ANDROID_ENVIRONMENT)),$(STAGING_TARGET),$(PRODUCTION_TARGET)))

# Build output locations
ANDROID_GRADLE_HOME ?= $(abspath build/android/gradle-home)
IOS_EXPORT_OPTIONS ?= $(FLUTTER_ROOT)/ios/ExportOptions.plist
IOS_IPA_PATH ?= $(FLUTTER_BUILD)/ios/ipa/Pomodoist.ipa
WINDOWS_RELEASE_DIR ?= $(FLUTTER_BUILD)/windows/x64/runner/Release

# Desktop builds use <PLATFORM>_<MODE>_CONFIG. Debug targets default to
# staging; profile and release targets keep their platform configuration.
# Override any of them to point one build at another environment, including
# production. Each configuration is paired with its entry point, so an override
# must move <PLATFORM>_<MODE>_TARGET as well: a mismatch stops the app at
# startup with "Entrypoint/config mismatch".
MACOS_DEBUG_CONFIG   ?= $(STAGING_CONFIG)
MACOS_PROFILE_CONFIG ?= $(LOCAL_CONFIG)
MACOS_RELEASE_CONFIG ?= $(TESTFLIGHT_CONFIG)
MACOS_DEBUG_TARGET   ?= $(STAGING_TARGET)
MACOS_PROFILE_TARGET ?= $(LOCAL_TARGET)
MACOS_RELEASE_TARGET ?= $(TESTFLIGHT_TARGET)
LINUX_DEBUG_CONFIG   ?= $(STAGING_CONFIG)
LINUX_PROFILE_CONFIG ?= $(LINUX_CONFIG)
LINUX_RELEASE_CONFIG ?= $(LINUX_CONFIG)
LINUX_DEBUG_TARGET   ?= $(STAGING_TARGET)
LINUX_PROFILE_TARGET ?= $(PRODUCTION_TARGET)
LINUX_RELEASE_TARGET ?= $(PRODUCTION_TARGET)
WINDOWS_DEBUG_CONFIG ?= $(STAGING_CONFIG)
WINDOWS_PROFILE_CONFIG ?= $(WINDOWS_CONFIG)
WINDOWS_RELEASE_CONFIG ?= $(WINDOWS_CONFIG)
WINDOWS_DEBUG_TARGET   ?= $(STAGING_TARGET)
WINDOWS_PROFILE_TARGET ?= $(PRODUCTION_TARGET)
WINDOWS_RELEASE_TARGET ?= $(PRODUCTION_TARGET)

# TestFlight credentials stay in the private env and are never Dart defines.
PRIVATE_CONFIG ?= .env.private
ASC_KEY_ID     ?= $(shell "$(DART)" tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_KEY_ID 2>/dev/null)
ASC_ISSUER_ID  ?= $(shell "$(DART)" tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_ISSUER_ID 2>/dev/null)
DEPLOY_CONFIG  ?= .env.deploy
TELEGRAM_ENV   ?= staging
COMPANION_OPEN ?= 1
POMODOIST_RELEASE        ?= $(shell git rev-parse HEAD)
TELEGRAM_DEBUG_CONFIG    ?= .env.telegram.staging
COMPANION_DEBUG_CONFIG   ?= .env.staging
COMPANION_RELEASE_CONFIG ?= $(TESTFLIGHT_CONFIG)

.PHONY: setup setup-env setup-flutter setup-linux run run-linux web
.PHONY: setup-telegram telegram-configure
.PHONY: telegram-debug telegram-release chrome-debug chrome-release
.PHONY: architecture analyze test test-linux-installer test-linux-appimage test-linux-build-network test-linux-packaging check format
.PHONY: android web-debug web-profile web-release
.PHONY: linux-pub-get linux-debug linux-profile linux-release linux-appimage linux-install
.PHONY: windows-debug windows-profile windows-release windows-installer
.PHONY: macos macos-debug macos-run macos-profile macos-release macos-reset
.PHONY: ios-debug ios-profile ipad-debug ipad-profile watch-debug watch-profile testflight-preflight testflight-auth testflight-ios testflight-macos testflight
.PHONY: deploy-staging deploy-production deploy-all deploy-telegram-staging deploy-telegram-production
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
	printf '  %s%-26s%s %s\n' "$${bold}" 'make telegram-debug' "$${reset}" 'Local Mini App through HTTPS, using the staging bot'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make chrome-debug' "$${reset}" 'Build the staging extension and open Chrome'; \
	printf '\n%s%sQuality%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make analyze' "$${reset}" 'Analyze Dart code'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make test' "$${reset}" 'Run Flutter tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make test-linux-packaging' "$${reset}" 'Test Linux installers and AppImage layout'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make check' "$${reset}" 'Run analysis and tests'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make format' "$${reset}" 'Format source files'; \
	printf '\n%s%sRelease & distribution%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-9s %-26s %s%s\n' "$${dim}" 'Platform' 'Command' 'Action' "$${reset}"; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Android' "$${reset}" "$${bold}" 'make android' "$${reset}" 'Debug APK'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-release' "$${reset}" 'Release app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Telegram' "$${reset}" "$${bold}" 'make telegram-release' "$${reset}" 'Production Mini App files and ZIP'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Chrome' "$${reset}" "$${bold}" 'make chrome-release' "$${reset}" 'Production extension files and ZIP'; \
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
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos' "$${reset}" 'Debug app (alias of macos-debug)'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-run' "$${reset}" 'Debug app with hot reload'; \
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
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-staging' "$${reset}" '     Deploy backend + web staging'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-production' "$${reset}" '     Deploy backend + web production'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-telegram-staging' "$${reset}" '   Deploy staging and configure @pomodoist_test_bot'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-telegram-production' "$${reset}" 'Deploy production and configure @pomodoist_bot'; \
	printf '  %s%-9s%s %s%-26s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-all' "$${reset}" '     Deploy everything, including both Telegram bots'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-26s%s %s\n' "$${bold}" 'make macos-reset' "$${reset}" 'Erase local app data and permissions (quit Pomodoist first)'; \
	printf '  %s%-26s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

setup: setup-env setup-flutter

setup-env:
	"$(DART)" tool/env_setup.dart bootstrap

setup-flutter: setup-env flutter-build-link
	"$(DART)" tool/env_setup.dart sync
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" pub get

setup-linux: setup-env
	./tool/linux/setup_arch.sh

setup-telegram: setup-env
	"$(DART)" tool/env_setup.dart sync

# Register only after deploying the matching function and secrets.
telegram-configure: setup-telegram
	@case "$(TELEGRAM_ENV)" in staging|production) ;; *) echo 'TELEGRAM_ENV must be staging or production' >&2; exit 1;; esac
	node --env-file=".env.telegram.$(TELEGRAM_ENV)" tool/configure-telegram-bot.mjs --apply

telegram-debug:
	node tool/telegram-debug.mjs --config "$(COMPANION_DEBUG_CONFIG)" --bot-config "$(TELEGRAM_DEBUG_CONFIG)" $(if $(filter 0,$(COMPANION_OPEN)),--no-open,)

telegram-release:
	node tool/web-companions.mjs telegram release --config "$(COMPANION_RELEASE_CONFIG)"

chrome-debug:
	node tool/web-companions.mjs chrome debug --config "$(COMPANION_DEBUG_CONFIG)" $(if $(filter 0,$(COMPANION_OPEN)),--no-open,)

chrome-release:
	node tool/web-companions.mjs chrome release --config "$(COMPANION_RELEASE_CONFIG)"

run: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

run-linux: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d linux --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

web: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d chrome --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

analyze:
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" analyze
	"$(DART)" analyze tool

test: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" test

test-linux-installer:
	./tool/linux/test_install.sh

test-linux-appimage:
	./tool/linux/test_appimage.sh

test-linux-build-network:
	./tool/linux/test_make_build.sh

test-linux-packaging: test-linux-installer test-linux-appimage test-linux-build-network

test-xcode-warnings:
	sh tool/test_xcode_warnings.sh

architecture: flutter-build-link
	python3 tool/check_architecture.py
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" pub get
	cd "$(FLUTTER_ROOT)" && "$(DART)" run tool/check_architecture_types.dart

check: architecture analyze test

format:
	"$(DART)" format apps/flutter/lib apps/flutter/test apps/flutter/tool tool

android: flutter-build-link
	cd "$(FLUTTER_ROOT)" && GRADLE_USER_HOME="$(call repo_path,$(ANDROID_GRADLE_HOME))" "$(FLUTTER)" build apk --debug --target "$(ANDROID_TARGET)" --dart-define-from-file="$(call repo_path,$(ANDROID_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=storekit

web-debug: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --debug --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-profile: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --profile --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-release: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --release --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

linux-pub-get: flutter-build-link
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) bash "$(REPO_ROOT)/tool/linux/pub_get_with_retry.sh" "$(FLUTTER)"

linux-debug: linux-pub-get
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) "$(FLUTTER)" build linux --debug --target "$(LINUX_DEBUG_TARGET)" --dart-define-from-file="$(call repo_path,$(LINUX_DEBUG_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-profile: linux-pub-get
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) "$(FLUTTER)" build linux --profile --target "$(LINUX_PROFILE_TARGET)" --dart-define-from-file="$(call repo_path,$(LINUX_PROFILE_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

linux-release: linux-pub-get
	$(LINUX_BUILD_ENV) "$(DART)" tool/desktop_release_config.dart --config "$(LINUX_RELEASE_CONFIG)"
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) "$(FLUTTER)" build linux --release --target "$(LINUX_RELEASE_TARGET)" --dart-define-from-file="$(call repo_path,$(LINUX_RELEASE_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=$(POMODOIST_BILLING_CHANNEL)

linux-appimage: linux-release
	$(LINUX_BUILD_ENV) $(POMODOIST_APPIMAGE_BUILDER)

linux-install: linux-release
	./tool/linux/install.sh

windows-debug:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Debug -ConfigFile "$(WINDOWS_DEBUG_CONFIG)" -Target "$(WINDOWS_DEBUG_TARGET)"

windows-profile:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Profile -ConfigFile "$(WINDOWS_PROFILE_CONFIG)" -Target "$(WINDOWS_PROFILE_TARGET)"

windows-release:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Release -Clean -ConfigFile "$(WINDOWS_RELEASE_CONFIG)" -Target "$(WINDOWS_RELEASE_TARGET)" -ReleaseSha "$(POMODOIST_RELEASE)"

windows-installer: windows-release
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/installer/build.ps1 -BuildDirectory "$(WINDOWS_RELEASE_DIR)"

macos-debug macos-run macos-profile: POMODOIST_BILLING_CHANNEL = storekit
macos-debug macos-run macos-profile: flutter-build-link

# `make macos` is the usual entry point; it builds the debug app.
macos: macos-debug

# Swift Package Manager dependencies emit hundreds of deprecation warnings that
# drown out the build result; the filter drops them while keeping real errors.
macos-debug:
	set -o pipefail; cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --debug \
		--target "$(MACOS_DEBUG_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_DEBUG_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)" 2>&1 \
		| awk -f "$(REPO_ROOT)/tool/xcode-warnings.awk"

macos-profile:
	set -o pipefail; cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --profile \
		--target "$(MACOS_PROFILE_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_PROFILE_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)" 2>&1 \
		| awk -f "$(REPO_ROOT)/tool/xcode-warnings.awk"

# Interactive debug run with hot reload. Output is left unfiltered so the
# "Flutter run key commands" stay usable.
macos-run:
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d macos --debug \
		--target "$(MACOS_DEBUG_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_DEBUG_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

macos-release: testflight-preflight flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --release \
		--target "$(MACOS_RELEASE_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_RELEASE_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

# Destructive local reset; cloud accounts and purchases are unchanged.
# Keep macOS container metadata; rm does not follow the sandbox's symlinks.
macos-reset:
	@test "$$(uname -s)" = Darwin || { echo 'macos-reset requires macOS.' >&2; exit 1; }
	@test -n "$${HOME:-}" && test "$$HOME" != / && test -d "$$HOME" || { echo 'A valid HOME directory is required.' >&2; exit 1; }
	@if pgrep -ix pomodoist >/dev/null; then echo 'Quit Pomodoist with Cmd+Q, then run make macos-reset again.' >&2; exit 1; fi
	@echo 'Deleting local Pomodoist data, including unsynced tasks, settings and saved sessions.'
	@for domain in com.finchforge.pomodoist com.finchforge.pomodoist.focuswidget group.com.pomodoist \
		"$$HOME/Library/Containers/com.finchforge.pomodoist/Data/Library/Preferences/com.finchforge.pomodoist" \
		"$$HOME/Library/Containers/com.finchforge.pomodoist.focuswidget/Data/Library/Preferences/com.finchforge.pomodoist.focuswidget" \
		"$$HOME/Library/Group Containers/group.com.pomodoist/Library/Preferences/group.com.pomodoist"; do \
		defaults delete "$$domain" 2>/dev/null || true; \
	done
	rm -rf "$$HOME/Library/Containers/com.finchforge.pomodoist/Data" \
		"$$HOME/Library/Containers/com.finchforge.pomodoist.focuswidget/Data" \
		"$$HOME/Library/Group Containers/group.com.pomodoist/Library" \
		"$$HOME/Library/Group Containers/group.com.pomodoist/focus-snapshot-v1.json" \
		"$$HOME/Library/Application Support/com.finchforge.pomodoist" \
		"$$HOME/Library/Caches/com.finchforge.pomodoist" \
		"$$HOME/Library/Saved Application State/com.finchforge.pomodoist.savedState"
	rm -f "$$HOME/Library/Preferences/com.finchforge.pomodoist.plist" \
		"$$HOME/Documents/pomodoist.sqlite" "$$HOME/Documents/pomodoist.sqlite-wal" "$$HOME/Documents/pomodoist.sqlite-shm"
	tccutil reset All com.finchforge.pomodoist
	@echo 'Local reset complete. Start Pomodoist in guest mode for a clean slate.'

# Flutter profile mode is unavailable on iOS Simulator, so local runs use debug.
ios-debug ios-profile: RUN_SIMULATOR = $(IOS_SIMULATOR)
ipad-debug ipad-profile: RUN_SIMULATOR = $(IPAD_SIMULATOR)
ios-debug ios-profile ipad-debug ipad-profile: flutter-build-link
	xcrun simctl bootstatus "$(RUN_SIMULATOR)" -b
	open -a Simulator
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d "$(RUN_SIMULATOR)" --debug --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=storekit

watch-debug: WATCH_CONFIGURATION = Debug
watch-profile: WATCH_CONFIGURATION = Profile
watch-debug watch-profile:
	xcrun simctl bootstatus "$(WATCH_SIMULATOR)" -b
	open -a Simulator
	xcodebuild -quiet -project "$(FLUTTER_ROOT)/ios/Runner.xcodeproj" -target PomodoistWatch -configuration "$(WATCH_CONFIGURATION)" -sdk watchsimulator SYMROOT="$(WATCH_BUILD_PATH)" OBJROOT="$(WATCH_BUILD_PATH)/obj" build
	xcrun simctl install "$(WATCH_SIMULATOR)" "$(WATCH_BUILD_PATH)/$(WATCH_CONFIGURATION)-watchsimulator/PomodoistWatch.app"
	xcrun simctl launch "$(WATCH_SIMULATOR)" com.finchforge.pomodoist.watchkitapp

testflight: testflight-ios testflight-macos

deploy-staging deploy-production deploy-all:
	@set -eu; \
		runner="$$( "$(DART)" tool/env_setup.dart value --env "$(DEPLOY_CONFIG)" --key RUNNER )"; \
		"$$runner" "$(patsubst deploy-%,%,$@)" "$(CURDIR)" "$(call repo_path,$(DEPLOY_CONFIG))"
	@if [ "$@" = deploy-all ]; then \
			$(MAKE) telegram-configure TELEGRAM_ENV=staging; \
			$(MAKE) telegram-configure TELEGRAM_ENV=production; \
		fi

deploy-all: setup-telegram

deploy-telegram-staging: setup-telegram deploy-staging
	$(MAKE) telegram-configure TELEGRAM_ENV=staging

deploy-telegram-production: setup-telegram deploy-production
	$(MAKE) telegram-configure TELEGRAM_ENV=production

testflight-preflight:
	python3 tool/check_testflight_env.py "$(TESTFLIGHT_CONFIG)"

testflight-auth:
	@test -f "$(PRIVATE_CONFIG)" || (echo "Missing $(PRIVATE_CONFIG); run make setup-flutter" >&2; exit 1)
	@test -n "$(ASC_KEY_ID)" || (echo "ASC_KEY_ID is missing in $(PRIVATE_CONFIG)" >&2; exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "ASC_ISSUER_ID is missing in $(PRIVATE_CONFIG)" >&2; exit 1)
	@"$(DART)" tool/env_setup.dart value --env "$(PRIVATE_CONFIG)" --key ASC_PRIVATE_KEY_BASE64 >/dev/null

testflight-ios: testflight-preflight testflight-auth flutter-build-link
	@set -eu; \
		key_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/pomodoist-testflight.XXXXXX")"; \
		trap 'test -n "$$key_dir" && rm -rf -- "$$key_dir"' EXIT HUP INT TERM; \
		key_path="$$key_dir/AuthKey_$(ASC_KEY_ID).p8"; \
		"$(DART)" tool/env_setup.dart write-asc-key --env "$(PRIVATE_CONFIG)" --output "$$key_path"; \
		(cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build ipa --release \
			--target "$(TESTFLIGHT_TARGET)" \
			--export-options-plist="$(call repo_path,$(IOS_EXPORT_OPTIONS))" \
			--dart-define-from-file="$(call repo_path,$(TESTFLIGHT_CONFIG))" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit); \
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
MACOS_PACKAGE_PATH = $(MACOS_EXPORT_PATH)/Pomodoist.pkg
# Keep Xcode's archive intermediates under build/ instead of the global
# ~/Library/Developer/Xcode/DerivedData.
MACOS_DERIVED_DATA = $(abspath build/TestFlight/derived-data)

testflight-macos: testflight-preflight testflight-auth flutter-build-link
	@set -eu; \
		key_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/pomodoist-testflight.XXXXXX")"; \
		trap 'test -n "$$key_dir" && rm -rf -- "$$key_dir"' EXIT HUP INT TERM; \
		key_path="$$key_dir/AuthKey_$(ASC_KEY_ID).p8"; \
		"$(DART)" tool/env_setup.dart write-asc-key --env "$(PRIVATE_CONFIG)" --output "$$key_path"; \
		(cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --release \
			--target "$(TESTFLIGHT_TARGET)" \
			--dart-define-from-file="$(call repo_path,$(TESTFLIGHT_CONFIG))" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit); \
		rm -rf "$(MACOS_ARCHIVE_PATH)" "$(MACOS_EXPORT_PATH)"; \
		xcodebuild -workspace "$(FLUTTER_ROOT)/macos/Runner.xcworkspace" -scheme Runner \
			-configuration Release -archivePath "$(MACOS_ARCHIVE_PATH)" archive \
			-derivedDataPath "$(MACOS_DERIVED_DATA)" \
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
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" devices

clean:
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" clean
	rm -rf "$(FLUTTER_BUILD)" "$(FLUTTER_DART_TOOL)"
	@$(LINK_FLUTTER_BUILD)

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
# Xcode 27 uses Device Hub; older Xcode versions ship Simulator.
OPEN_SIMULATOR = developer_dir="$$(xcode-select -p)" && \
	if [ -d "$$developer_dir/../Applications/DeviceHub.app" ]; then \
		open -a "$$developer_dir/../Applications/DeviceHub.app"; \
	else open -a "$$developer_dir/Applications/Simulator.app"; fi

# Linux packaging. Release downloads use direct HTTPS, which prevents stale
# localhost proxy variables from breaking reproducible local builds.
LINUX_BUILD_ENV ?= env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY
POMODOIST_APPIMAGE_BUILDER ?= ./tool/linux/build_appimage.sh

# Flutter dart-define files. LOCAL and STAGING are shared environments; the
# platform files carry production values.
LOCAL_CONFIG ?= .env.local
STAGING_CONFIG ?= .env.staging
# TestFlight selects the environment and its own App Store Connect app.
# Staging requires the .stg App IDs, App Group and provisioning profiles.
TESTFLIGHT_ENV    ?= production
TESTFLIGHT_CONFIG ?= $(if $(filter staging,$(TESTFLIGHT_ENV)),$(STAGING_CONFIG),.env.testflight)
# Staging keeps the in-process test store independent of its App Store catalog.
TESTFLIGHT_STAGING_DEFINES = --dart-define=POMODOIST_DEV_UNLOCK=1 --dart-define=POMODOIST_LOCAL_STOREKIT=1
TESTFLIGHT_DEFINES ?= $(if $(filter $(FLAVOR_STAGING),$(TESTFLIGHT_FLAVOR)),$(TESTFLIGHT_STAGING_DEFINES),)
LINUX_CONFIG   ?= .env.linux
WINDOWS_CONFIG ?= .env.windows
ANDROID_CONFIG ?= .env.android
# Per-environment Linux dotenv profiles. The Linux identities have their own
# files rather than borrowing the shared LOCAL and STAGING ones, because a
# desktop profile carries the Linux OAuth client and the billing channel that
# belong to that environment. Generate them with `make setup-flutter`.
LINUX_DEVELOPMENT_PROFILE ?= .env.linux-development
LINUX_STAGING_PROFILE     ?= .env.linux-staging

# Flutter entry points. Each entry point declares the environment it serves and
# refuses to start when the dart-define file names another one, so every run and
# build passes --target next to --dart-define-from-file.
LOCAL_TARGET      ?= lib/main_development.dart
STAGING_TARGET    ?= lib/main_staging.dart
PRODUCTION_TARGET ?= lib/main.dart

# Flutter flavor names. `--flavor` is what makes Flutter compile
# FLUTTER_APP_FLAVOR into the build, and lib/domain/models/app_flavor.dart turns
# that value into the display name, the bundle identifier, the URL scheme, the
# app group and the Windows toast GUID. A run or build that omits the option
# silently ships the production identity, so every target below passes the
# flavor of its entry point, and an unknown entry point is rejected instead of
# falling back to production.
FLAVOR_DEVELOPMENT := development
FLAVOR_STAGING     := staging
FLAVOR_PRODUCTION  := production
# Maps an entry point ($1) to the flavor it must be built with.
flavor_of = $(if $(filter $1,$(LOCAL_TARGET)),$(FLAVOR_DEVELOPMENT),$(if $(filter $1,$(STAGING_TARGET)),$(FLAVOR_STAGING),$(if $(filter $1,$(PRODUCTION_TARGET)),$(FLAVOR_PRODUCTION),$(error no flavor for entry point '$1'; use $(LOCAL_TARGET), $(STAGING_TARGET) or $(PRODUCTION_TARGET)))))
TESTFLIGHT_TARGET ?= $(if $(filter staging,$(TESTFLIGHT_ENV)),$(STAGING_TARGET),$(PRODUCTION_TARGET))
# make android builds the debug APK described in tool/android/README.md. Its
# entry point is read back from the dart-define file so the pair cannot drift:
# local -> development, staging -> staging, anything else (a production or
# selfhosted profile, a JSON file the reader cannot parse, an unreadable file)
# -> production. Override ANDROID_CONFIG for another profile, or ANDROID_TARGET
# to force an entry point.
ANDROID_ENVIRONMENT ?= $(shell "$(DART)" tool/env_setup.dart value --env "$(call repo_path,$(ANDROID_CONFIG))" --key POMODOIST_ENVIRONMENT 2>/dev/null)
ANDROID_TARGET ?= $(if $(filter local,$(ANDROID_ENVIRONMENT)),$(LOCAL_TARGET),$(if $(filter staging,$(ANDROID_ENVIRONMENT)),$(STAGING_TARGET),$(PRODUCTION_TARGET)))
ANDROID_FLAVOR ?= $(call flavor_of,$(ANDROID_TARGET))

# Build output locations. Flutter inserts the flavor into the Windows and Linux
# output directories, so both paths carry the flavor segment. Xcode names the
# exported .ipa and .pkg after the selected variant's display name.
ANDROID_GRADLE_HOME ?= $(abspath build/android/gradle-home)
IOS_EXPORT_OPTIONS ?= $(FLUTTER_ROOT)/ios/ExportOptions.plist
IOS_IPA_PATH ?= $(FLUTTER_BUILD)/ios/ipa/$(TESTFLIGHT_PRODUCT_NAME).ipa
WINDOWS_RELEASE_DIR ?= $(FLUTTER_BUILD)/windows/x64/$(WINDOWS_RELEASE_FLAVOR)/runner/Release

# Desktop builds use <PLATFORM>_<MODE>_CONFIG. macOS debug targets reuse
# MACOS_DEVELOPMENT_CONFIG/_TARGET, so `make macos-debug` and
# `make macos-debug-development` are the same build. Override any of them to
# point one build at another environment, including production. Each
# configuration is paired with its entry point, so an override must move the
# matching _TARGET as well: a mismatch stops the app at startup with
# "Entrypoint/config mismatch". macos-run follows the debug pair.
MACOS_DEBUG_CONFIG   ?= $(MACOS_DEVELOPMENT_CONFIG)
MACOS_DEBUG_TARGET   ?= $(MACOS_DEVELOPMENT_TARGET)
MACOS_PROFILE_CONFIG ?= $(LOCAL_CONFIG)
MACOS_RELEASE_CONFIG ?= $(TESTFLIGHT_CONFIG)
MACOS_PROFILE_TARGET ?= $(LOCAL_TARGET)
MACOS_RELEASE_TARGET ?= $(TESTFLIGHT_TARGET)
# Linux defaults to the development environment, which is the dotenv profile a
# workstation runs against locally. The profile and release targets build what
# is shipped, so they read the production profile; override the pair to point
# one build at another environment.
LINUX_DEBUG_CONFIG   ?= $(LINUX_DEVELOPMENT_PROFILE)
LINUX_PROFILE_CONFIG ?= $(LINUX_CONFIG)
LINUX_RELEASE_CONFIG ?= $(LINUX_CONFIG)
LINUX_DEBUG_TARGET   ?= $(LOCAL_TARGET)
LINUX_PROFILE_TARGET ?= $(PRODUCTION_TARGET)
LINUX_RELEASE_TARGET ?= $(PRODUCTION_TARGET)
# The billing channel of a generic build is the one its environment ships, so
# linux-debug matches linux-debug-development and linux-release matches
# linux-release-production.
LINUX_DEBUG_BILLING_CHANNEL   ?= $(LINUX_DEVELOPMENT_BILLING_CHANNEL)
LINUX_PROFILE_BILLING_CHANNEL ?= $(LINUX_PRODUCTION_BILLING_CHANNEL)
LINUX_RELEASE_BILLING_CHANNEL ?= $(LINUX_PRODUCTION_BILLING_CHANNEL)
WINDOWS_DEBUG_CONFIG ?= $(STAGING_CONFIG)
WINDOWS_PROFILE_CONFIG ?= $(WINDOWS_CONFIG)
WINDOWS_RELEASE_CONFIG ?= $(WINDOWS_CONFIG)
WINDOWS_DEBUG_TARGET   ?= $(STAGING_TARGET)
WINDOWS_PROFILE_TARGET ?= $(PRODUCTION_TARGET)
WINDOWS_RELEASE_TARGET ?= $(PRODUCTION_TARGET)

# Per-environment macOS builds behind the macos-<mode>-<environment> targets.
# development reuses the local dotenv profile, which talks to the production
# Supabase project with CAPTCHA disabled; staging uses .env.staging; production
# uses .env.testflight, the profile the release build already ships. Each
# configuration stays paired with its entry point so flavor_of derives the
# matching flavor. Override MACOS_<ENVIRONMENT>_CONFIG/_TARGET to move one
# environment everywhere it is used.
MACOS_DEVELOPMENT_CONFIG ?= $(LOCAL_CONFIG)
MACOS_DEVELOPMENT_TARGET ?= $(LOCAL_TARGET)
MACOS_STAGING_CONFIG     ?= $(STAGING_CONFIG)
MACOS_STAGING_TARGET     ?= $(STAGING_TARGET)
MACOS_PRODUCTION_CONFIG  ?= $(TESTFLIGHT_CONFIG)
MACOS_PRODUCTION_TARGET  ?= $(PRODUCTION_TARGET)

# Per-environment Linux builds behind the linux-<mode>-<environment> targets.
# The naming mirrors the macos-<mode>-<environment> targets, but the supported
# modes differ: the macOS table is driven by Xcode configurations, while the
# Linux table is the build, the AppImage packaging and the user installer
# repeated per environment. Every environment reads its own dotenv profile —
# development .env.linux-development, staging .env.linux-staging, production
# .env.linux, the profile the shipped AppImage is built from — so no two Linux
# builds share a configuration. Each configuration stays paired with its entry
# point so flavor_of derives the matching flavor. Override
# LINUX_<ENVIRONMENT>_CONFIG/_TARGET to move one environment everywhere it is
# used.
LINUX_DEVELOPMENT_CONFIG ?= $(LINUX_DEVELOPMENT_PROFILE)
LINUX_DEVELOPMENT_TARGET ?= $(LOCAL_TARGET)
LINUX_STAGING_CONFIG     ?= $(LINUX_STAGING_PROFILE)
LINUX_STAGING_TARGET     ?= $(STAGING_TARGET)
LINUX_PRODUCTION_CONFIG  ?= $(LINUX_CONFIG)
LINUX_PRODUCTION_TARGET  ?= $(PRODUCTION_TARGET)
# Billing channel per environment, used when a target has no dotenv file of its
# own to declare one (a run against an arbitrary override, or a config path the
# repository does not own). Each profile above already carries the matching
# POMODOIST_BILLING_CHANNEL.
LINUX_DEVELOPMENT_BILLING_CHANNEL ?= storekit
LINUX_STAGING_BILLING_CHANNEL     ?= stripe
LINUX_PRODUCTION_BILLING_CHANNEL  ?= stripe

# Each flavor is read back from its entry point, so moving a
# <PLATFORM>_<MODE>_TARGET moves the flavor with it and the app keeps one
# identity. Overriding a flavor on its own builds an identity the entry point
# does not declare, which the app rejects at startup.
LOCAL_FLAVOR           ?= $(call flavor_of,$(LOCAL_TARGET))
TESTFLIGHT_FLAVOR      ?= $(call flavor_of,$(TESTFLIGHT_TARGET))
MACOS_DEBUG_FLAVOR     ?= $(call flavor_of,$(MACOS_DEBUG_TARGET))
MACOS_PROFILE_FLAVOR   ?= $(call flavor_of,$(MACOS_PROFILE_TARGET))
MACOS_RELEASE_FLAVOR   ?= $(call flavor_of,$(MACOS_RELEASE_TARGET))
LINUX_DEBUG_FLAVOR     ?= $(call flavor_of,$(LINUX_DEBUG_TARGET))
LINUX_PROFILE_FLAVOR   ?= $(call flavor_of,$(LINUX_PROFILE_TARGET))
LINUX_RELEASE_FLAVOR   ?= $(call flavor_of,$(LINUX_RELEASE_TARGET))
WINDOWS_DEBUG_FLAVOR   ?= $(call flavor_of,$(WINDOWS_DEBUG_TARGET))
WINDOWS_PROFILE_FLAVOR ?= $(call flavor_of,$(WINDOWS_PROFILE_TARGET))
WINDOWS_RELEASE_FLAVOR ?= $(call flavor_of,$(WINDOWS_RELEASE_TARGET))
MACOS_DEVELOPMENT_FLAVOR ?= $(call flavor_of,$(MACOS_DEVELOPMENT_TARGET))
MACOS_STAGING_FLAVOR     ?= $(call flavor_of,$(MACOS_STAGING_TARGET))
MACOS_PRODUCTION_FLAVOR  ?= $(call flavor_of,$(MACOS_PRODUCTION_TARGET))
LINUX_DEVELOPMENT_FLAVOR ?= $(call flavor_of,$(LINUX_DEVELOPMENT_TARGET))
LINUX_STAGING_FLAVOR     ?= $(call flavor_of,$(LINUX_STAGING_TARGET))
LINUX_PRODUCTION_FLAVOR  ?= $(call flavor_of,$(LINUX_PRODUCTION_TARGET))
# The bundle a packaging target consumes is derived from the release flavor it
# packaged, so linux-appimage-staging picks the staging segment instead of
# reusing a production path. Override LINUX_BUNDLE_DIR to point at a bundle
# Flutter wrote somewhere else.
LINUX_BUNDLE_DIR ?= $(FLUTTER_BUILD)/linux/x64/$(LINUX_RELEASE_FLAVOR)/release/bundle
TESTFLIGHT_PRODUCT_NAME ?= $(if $(filter $(FLAVOR_STAGING),$(TESTFLIGHT_FLAVOR)),Pomodoist Stg,Pomodoist)

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
.PHONY: telegram-debug telegram-local telegram-release chrome-debug chrome-run chrome-release
.PHONY: architecture analyze test test-linux-installer test-linux-appimage test-linux-build-network test-linux-flavor-identity test-linux-packaging check format app-icons app-icons-check
.PHONY: android web-debug web-profile web-release
.PHONY: linux-pub-get linux-debug linux-profile linux-release linux-appimage linux-install
.PHONY: linux-run
.PHONY: linux-debug-development linux-debug-staging linux-debug-production
.PHONY: linux-profile-development linux-profile-staging linux-profile-production
.PHONY: linux-release-development linux-release-staging linux-release-production
.PHONY: windows-debug windows-profile windows-release windows-installer
.PHONY: macos macos-debug macos-run macos-profile macos-release macos-reset
.PHONY: macos-debug-development macos-debug-staging macos-debug-production
.PHONY: macos-profile-development macos-profile-staging macos-profile-production
.PHONY: macos-provision-staging
.PHONY: macos-release-development macos-release-staging macos-release-production
.PHONY: macos-dmg-production macos-dmg-staging macos-dmg-development
.PHONY: ios-debug ios-profile ipad-debug ipad-profile watch-debug watch-profile ios-flavor-settings testflight-preflight testflight-auth testflight-ios testflight-macos testflight
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
	printf '  %s%-27s%s %s\n' "$${bold}" 'make setup' "$${reset}" 'Full setup: env files + Flutter dependencies'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make setup-env' "$${reset}" 'Create the .env.setup template'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make setup-flutter' "$${reset}" 'Generate env files and resolve Flutter dependencies'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make setup-linux' "$${reset}" 'Prepare an Arch Linux workstation'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make run' "$${reset}" 'Run Pomodoist on a connected device'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make run-linux' "$${reset}" 'Run the native Linux desktop app'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make web' "$${reset}" 'Run Pomodoist in Chrome'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make telegram-debug' "$${reset}" 'Local Mini App through HTTPS, using the staging bot'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make telegram-local' "$${reset}" 'Mini App preview in Chrome, no tunnel or bot changes'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make chrome-debug' "$${reset}" 'Build the staging extension and open Chrome'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make chrome-run' "$${reset}" 'Load the built extension and check the popup renders'; \
	printf '\n%s%sQuality%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make analyze' "$${reset}" 'Analyze Dart code'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make test' "$${reset}" 'Run Flutter tests'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make test-linux-packaging' "$${reset}" 'Test Linux installers, AppImage layout and flavor identity'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make check' "$${reset}" 'Run analysis, tests and icon checks'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make format' "$${reset}" 'Format source files'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make app-icons' "$${reset}" 'Regenerate app icons from the master PNGs'; \
	printf '\n%s%sRelease & distribution%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-9s %-27s %s%s\n' "$${dim}" 'Platform' 'Command' 'Action' "$${reset}"; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Android' "$${reset}" "$${bold}" 'make android' "$${reset}" 'Debug APK'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Web' "$${reset}" "$${bold}" 'make web-release' "$${reset}" 'Release app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Telegram' "$${reset}" "$${bold}" 'make telegram-release' "$${reset}" 'Production Mini App files and ZIP'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Chrome' "$${reset}" "$${bold}" 'make chrome-run' "$${reset}" 'Debug extension in a stable local profile'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Chrome' "$${reset}" "$${bold}" 'make chrome-release' "$${reset}" 'Production extension files and ZIP'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-debug' "$${reset}" 'Debug app (development)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-release' "$${reset}" 'Raw developer bundle'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-appimage' "$${reset}" 'Distributable AppImage'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-install' "$${reset}" 'Install for current user'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-run' "$${reset}" 'Debug app with hot reload'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-debug-staging' "$${reset}" 'Debug app (staging)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-debug-production' "$${reset}" 'Debug app (production)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-profile-development' "$${reset}" 'Profile app (development)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-profile-staging' "$${reset}" 'Profile app (staging)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-profile-production' "$${reset}" 'Profile app (production)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-release-development' "$${reset}" 'Release app (local, development)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-release-staging' "$${reset}" 'Release app (local, staging)'; \
	printf '  %s%-9s%s %s%-32s%s %s\n' "$${dim}" 'Linux' "$${reset}" "$${bold}" 'make linux-release-production' "$${reset}" 'Release app (local, production)'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-debug' "$${reset}" 'Debug app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-release' "$${reset}" 'Release app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Windows' "$${reset}" "$${bold}" 'make windows-installer' "$${reset}" 'EXE installer'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos' "$${reset}" 'Debug app (alias of macos-debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-debug' "$${reset}" 'Debug app (development)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-debug-staging' "$${reset}" 'Debug app (staging)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-debug-production' "$${reset}" 'Debug app (production)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-run' "$${reset}" 'Debug app with hot reload'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-provision-staging' "$${reset}" 'Get staging signing profiles'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-profile-staging' "$${reset}" 'Profile app (staging)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-profile-production' "$${reset}" 'Profile app (production)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-release-staging' "$${reset}" 'Release app (local, staging)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-release-production' "$${reset}" 'Release app (local, production)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-profile' "$${reset}" 'Profile app'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make macos-release' "$${reset}" 'Release app'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'iPhone' "$${reset}" "$${bold}" 'make ios-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'iPhone' "$${reset}" "$${bold}" 'make ios-profile' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'iPad' "$${reset}" "$${bold}" 'make ipad-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'iPad' "$${reset}" "$${bold}" 'make ipad-profile' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Watch' "$${reset}" "$${bold}" 'make watch-debug' "$${reset}" 'Run Simulator (debug)'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Watch' "$${reset}" "$${bold}" 'make watch-profile' "$${reset}" 'Run Simulator (profile)'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'iOS' "$${reset}" "$${bold}" 'make testflight-ios' "$${reset}" 'Upload iOS to TestFlight'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'macOS' "$${reset}" "$${bold}" 'make testflight-macos' "$${reset}" 'Upload macOS to TestFlight'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'All' "$${reset}" "$${bold}" 'make testflight' "$${reset}" 'Upload iOS + macOS to TestFlight'; \
	printf '\n'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-staging' "$${reset}" 'Deploy backend + web staging'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-production' "$${reset}" 'Deploy backend + web production'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-telegram-staging' "$${reset}" 'Deploy staging and configure @pomodoist_test_bot'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-telegram-production' "$${reset}" 'Deploy production and configure @pomodoist_bot'; \
	printf '  %s%-9s%s %s%-27s%s %s\n' "$${dim}" 'Deploy' "$${reset}" "$${bold}" 'make deploy-all' "$${reset}" 'Deploy everything, including both Telegram bots'; \
	printf '\n%s%sUtilities%s\n' "$${red}" "$${bold}" "$${reset}"; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make help' "$${reset}" 'Show this command reference'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make devices' "$${reset}" 'List available Flutter devices'; \
	printf '  %s%-27s%s %s\n' "$${bold}" 'make macos-reset' "$${reset}" 'Erase local app data and permissions (quit Pomodoist first)'; \
	printf '  %s%-27s%s %s\n\n' "$${bold}" 'make clean' "$${reset}" 'Remove Flutter build outputs'

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

# Browser preview of the Mini App without a tunnel or bot changes.
telegram-local:
	node tool/telegram-debug.mjs --local --config "$(COMPANION_DEBUG_CONFIG)" $(if $(filter 0,$(COMPANION_OPEN)),--no-open,)

telegram-release:
	node tool/web-companions.mjs telegram release --config "$(COMPANION_RELEASE_CONFIG)"

chrome-debug:
	node tool/web-companions.mjs chrome debug --config "$(COMPANION_DEBUG_CONFIG)" $(if $(filter 0,$(COMPANION_OPEN)),--no-open,)

# Loads the built debug extension into a dedicated profile, so the extension id
# stays the same across runs and manual sign-in survives. Signing in is the one
# step that stays interactive; the tool only automates loading and inspection.
chrome-run: chrome-debug
	node tool/chrome-extension-run.mjs $(if $(filter 0,$(COMPANION_OPEN)),--no-open,) $(if $(filter 1,$(COMPANION_OPEN)),--keep-profile --await 600,)

chrome-release:
	node tool/web-companions.mjs chrome release --config "$(COMPANION_RELEASE_CONFIG)"

run: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run --flavor "$(LOCAL_FLAVOR)" --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

run-linux: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d linux --flavor "$(LOCAL_FLAVOR)" --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)"

# Web picks its environment from config.js at runtime and Flutter ignores
# --flavor on this platform, so the web targets pass only the entry point.
web: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d chrome --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

analyze: flutter-build-link
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

test-linux-flavor-identity:
	./tool/linux/test_flavor_identity.sh

test-linux-packaging: test-linux-installer test-linux-appimage test-linux-build-network test-linux-flavor-identity

test-xcode-warnings:
	sh tool/test_xcode_warnings.sh

architecture: flutter-build-link
	python3 tool/check_architecture.py
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" pub get
	cd "$(FLUTTER_ROOT)" && "$(DART)" run tool/check_architecture_types.dart

check: architecture analyze test app-icons-check

format:
	"$(DART)" format apps/flutter/lib apps/flutter/test apps/flutter/tool tool

# Regenerate the platform icons from the master PNGs; --check verifies the
# committed icons still match the sources without writing them.
app-icons:
	cd "$(FLUTTER_ROOT)" && "$(DART)" run tool/generate_app_icons.dart

app-icons-check:
	cd "$(FLUTTER_ROOT)" && "$(DART)" run tool/generate_app_icons.dart --check

android: flutter-build-link
	cd "$(FLUTTER_ROOT)" && GRADLE_USER_HOME="$(call repo_path,$(ANDROID_GRADLE_HOME))" "$(FLUTTER)" build apk --debug --flavor "$(ANDROID_FLAVOR)" --target "$(ANDROID_TARGET)" --dart-define-from-file="$(call repo_path,$(ANDROID_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=storekit

web-debug: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --debug --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-profile: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --profile --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

web-release: flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build web --release --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=stripe

linux-pub-get: flutter-build-link
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) bash "$(REPO_ROOT)/tool/linux/pub_get_with_retry.sh" "$(FLUTTER)"

# Linux build modes behind linux-<mode> and linux-<mode>-<environment>. Each
# target is defined once through linux_flavor_target, which reads the
# <PLATFORM>_<MODE>_CONFIG/_TARGET pair the target pins, so a per-environment
# target and its generic counterpart cannot drift apart. --target always
# accompanies --dart-define-from-file: the entry point refuses to start when the
# configuration it was handed names another environment.
#
# Unlike the macos_flavor_target macro these recipes contain no shell operators,
# so they expand to one command line per target and `make --dry-run` lists them
# cleanly, which is what the make contract tests read.
define linux_flavor_target
cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) "$(FLUTTER)" build linux --$(1) --flavor "$(LINUX_$(2)_FLAVOR)" --target "$(LINUX_$(2)_TARGET)" --dart-define-from-file="$(call repo_path,$(LINUX_$(2)_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=$(LINUX_$(2)_BILLING_CHANNEL)
endef

# Only the release targets validate their configuration first: it is the
# artifact that ships, and only a release is allowed to be built from a
# production profile.
define linux_release_target
$(LINUX_BUILD_ENV) "$(DART)" tool/desktop_release_config.dart --config "$(LINUX_RELEASE_CONFIG)"
$(call linux_flavor_target,release,RELEASE)
endef

define linux_appimage_target
$(LINUX_BUILD_ENV) POMODOIST_LINUX_BUNDLE="$(LINUX_BUNDLE_DIR)" $(POMODOIST_APPIMAGE_BUILDER)
endef

define linux_install_target
POMODOIST_LINUX_BUNDLE="$(LINUX_BUNDLE_DIR)" ./tool/linux/install.sh
endef

linux-debug linux-profile linux-release: linux-pub-get

linux-debug:
	$(call linux_flavor_target,debug,DEBUG)

linux-profile:
	$(call linux_flavor_target,profile,PROFILE)

linux-release:
	$(linux_release_target)

# Point the packaging scripts at the bundle linux-release just built. The path
# carries the flavor segment, which is how the scripts pick the identity they
# package.
linux-appimage: linux-release
	$(linux_appimage_target)

linux-install: linux-release
	$(linux_install_target)

# Interactive debug run with hot reload. Output is left unfiltered so the
# "Flutter run key commands" stay usable. It follows the debug pair, which is
# the development environment, and therefore shares `make linux-debug`.
linux-run: flutter-build-link
	cd "$(FLUTTER_ROOT)" && $(LINUX_BUILD_ENV) "$(FLUTTER)" run -d linux --debug --flavor "$(LINUX_DEBUG_FLAVOR)" --target "$(LINUX_DEBUG_TARGET)" --dart-define-from-file="$(call repo_path,$(LINUX_DEBUG_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL="$(LINUX_DEBUG_BILLING_CHANNEL)"

# Per-environment builds: linux-<mode>-<environment>. A generic target and the
# environment it defaults to are the same build, so linux-debug and
# linux-debug-development produce identical commands; the environment targets
# pin the pair through target-specific variables, which also set the flavor
# through <PLATFORM>_<ENVIRONMENT>_FLAVOR. Every target resolves packages first,
# exactly as its generic counterpart does.
linux-debug-development linux-debug-staging linux-debug-production \
linux-profile-development linux-profile-staging linux-profile-production \
linux-release-development linux-release-staging linux-release-production: linux-pub-get

linux-debug-development: LINUX_DEBUG_CONFIG = $(LINUX_DEVELOPMENT_CONFIG)
linux-debug-development: LINUX_DEBUG_TARGET = $(LINUX_DEVELOPMENT_TARGET)
linux-debug-development: LINUX_DEBUG_FLAVOR = $(LINUX_DEVELOPMENT_FLAVOR)
linux-debug-development:
	$(call linux_flavor_target,debug,DEBUG)

linux-debug-staging: LINUX_DEBUG_CONFIG = $(LINUX_STAGING_CONFIG)
linux-debug-staging: LINUX_DEBUG_TARGET = $(LINUX_STAGING_TARGET)
linux-debug-staging: LINUX_DEBUG_FLAVOR = $(LINUX_STAGING_FLAVOR)
linux-debug-staging:
	$(call linux_flavor_target,debug,DEBUG)

linux-debug-production: LINUX_DEBUG_CONFIG = $(LINUX_PRODUCTION_CONFIG)
linux-debug-production: LINUX_DEBUG_TARGET = $(LINUX_PRODUCTION_TARGET)
linux-debug-production: LINUX_DEBUG_FLAVOR = $(LINUX_PRODUCTION_FLAVOR)
linux-debug-production:
	$(call linux_flavor_target,debug,DEBUG)

linux-profile-development: LINUX_PROFILE_CONFIG = $(LINUX_DEVELOPMENT_CONFIG)
linux-profile-development: LINUX_PROFILE_TARGET = $(LINUX_DEVELOPMENT_TARGET)
linux-profile-development: LINUX_PROFILE_FLAVOR = $(LINUX_DEVELOPMENT_FLAVOR)
linux-profile-development:
	$(call linux_flavor_target,profile,PROFILE)

linux-profile-staging: LINUX_PROFILE_CONFIG = $(LINUX_STAGING_CONFIG)
linux-profile-staging: LINUX_PROFILE_TARGET = $(LINUX_STAGING_TARGET)
linux-profile-staging: LINUX_PROFILE_FLAVOR = $(LINUX_STAGING_FLAVOR)
linux-profile-staging:
	$(call linux_flavor_target,profile,PROFILE)

linux-profile-production: LINUX_PROFILE_CONFIG = $(LINUX_PRODUCTION_CONFIG)
linux-profile-production: LINUX_PROFILE_TARGET = $(LINUX_PRODUCTION_TARGET)
linux-profile-production: LINUX_PROFILE_FLAVOR = $(LINUX_PRODUCTION_FLAVOR)
linux-profile-production:
	$(call linux_flavor_target,profile,PROFILE)

linux-release-development: LINUX_RELEASE_CONFIG = $(LINUX_DEVELOPMENT_CONFIG)
linux-release-development: LINUX_RELEASE_TARGET = $(LINUX_DEVELOPMENT_TARGET)
linux-release-development: LINUX_RELEASE_FLAVOR = $(LINUX_DEVELOPMENT_FLAVOR)
linux-release-development:
	$(linux_release_target)

linux-release-staging: LINUX_RELEASE_CONFIG = $(LINUX_STAGING_CONFIG)
linux-release-staging: LINUX_RELEASE_TARGET = $(LINUX_STAGING_TARGET)
linux-release-staging: LINUX_RELEASE_FLAVOR = $(LINUX_STAGING_FLAVOR)
linux-release-staging:
	$(linux_release_target)

linux-release-production: LINUX_RELEASE_CONFIG = $(LINUX_PRODUCTION_CONFIG)
linux-release-production: LINUX_RELEASE_TARGET = $(LINUX_PRODUCTION_TARGET)
linux-release-production: LINUX_RELEASE_FLAVOR = $(LINUX_PRODUCTION_FLAVOR)
linux-release-production:
	$(linux_release_target)

# Package and install one environment's release. These stand to linux-appimage
# and linux-install the way linux-release-<environment> stands to linux-release,
# and they extend it so the bundle being packaged is always the one the
# environment build just produced. Each pins LINUX_RELEASE_FLAVOR so
# LINUX_BUNDLE_DIR resolves to that environment's bundle instead of inheriting
# the production default, which would package one flavor under another's name.
linux-appimage-development: LINUX_RELEASE_FLAVOR = $(LINUX_DEVELOPMENT_FLAVOR)
linux-appimage-development: linux-release-development
	$(linux_appimage_target)

linux-appimage-staging: LINUX_RELEASE_FLAVOR = $(LINUX_STAGING_FLAVOR)
linux-appimage-staging: linux-release-staging
	$(linux_appimage_target)

linux-appimage-production: LINUX_RELEASE_FLAVOR = $(LINUX_PRODUCTION_FLAVOR)
linux-appimage-production: linux-release-production
	$(linux_appimage_target)

linux-install-development: LINUX_RELEASE_FLAVOR = $(LINUX_DEVELOPMENT_FLAVOR)
linux-install-development: linux-release-development
	$(linux_install_target)

linux-install-staging: LINUX_RELEASE_FLAVOR = $(LINUX_STAGING_FLAVOR)
linux-install-staging: linux-release-staging
	$(linux_install_target)

linux-install-production: LINUX_RELEASE_FLAVOR = $(LINUX_PRODUCTION_FLAVOR)
linux-install-production: linux-release-production
	$(linux_install_target)

# build.ps1 forwards -Flavor to `flutter build windows`; without it Flutter
# compiles the production identity into the executable.
windows-debug:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Debug -Flavor "$(WINDOWS_DEBUG_FLAVOR)" -ConfigFile "$(WINDOWS_DEBUG_CONFIG)" -Target "$(WINDOWS_DEBUG_TARGET)"

windows-profile:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Profile -Flavor "$(WINDOWS_PROFILE_FLAVOR)" -ConfigFile "$(WINDOWS_PROFILE_CONFIG)" -Target "$(WINDOWS_PROFILE_TARGET)"

windows-release:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/build.ps1 -Configuration Release -Clean -Flavor "$(WINDOWS_RELEASE_FLAVOR)" -ConfigFile "$(WINDOWS_RELEASE_CONFIG)" -Target "$(WINDOWS_RELEASE_TARGET)" -ReleaseSha "$(POMODOIST_RELEASE)"

windows-installer: windows-release
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tool/windows/installer/build.ps1 -Flavor "$(WINDOWS_RELEASE_FLAVOR)" -BuildDirectory "$(WINDOWS_RELEASE_DIR)"

# Direct-download macOS distribution: a universal .app in a .dmg with a SHA-256
# sidecar, billed through Stripe and not sandboxed. These are the counterpart of
# windows-installer and are unrelated to the macos-* targets below, which build
# App Store flavors with StoreKit billing.
macos-dmg-production:
	./tool/macos/build.sh --flavor production

macos-dmg-staging:
	./tool/macos/build.sh --flavor staging

macos-dmg-development:
	./tool/macos/build.sh --flavor development

macos-debug macos-run macos-profile macos-debug-development macos-debug-staging macos-debug-production macos-profile-development macos-profile-staging macos-profile-production: POMODOIST_BILLING_CHANNEL = storekit
macos-debug macos-run macos-profile macos-debug-development macos-debug-staging macos-debug-production macos-profile-development macos-profile-staging macos-profile-production macos-release-development macos-release-staging macos-release-production: flutter-build-link

# `flutter build macos` drives xcodebuild without -allowProvisioningUpdates, so
# Xcode can neither find nor create a profile for a flavor whose App IDs are not
# on the account yet. Only the flags below reach xcodebuild (Flutter turns
# environment variables into build settings); CODE_SIGN_IDENTITY=- alone leaves
# the profile requirement in place. The supported way to build a local flavor is
# FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO, which builds without signing at all.
MACOS_LOCAL_SIGNING_FLAGS ?=

# `make macos` is the usual entry point; it builds the debug app, which is the
# development environment. The same build is reachable as macos-debug-development.
macos: macos-debug

# Swift Package Manager dependencies emit hundreds of deprecation warnings that
# drown out the build result; the filter drops them while keeping real errors.
macos-debug: macos-debug-development

macos-profile:
	set -o pipefail; cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --profile \
		--flavor "$(MACOS_PROFILE_FLAVOR)" \
		--target "$(MACOS_PROFILE_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_PROFILE_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)" \
		$(MACOS_LOCAL_SIGNING_FLAGS) 2>&1 \
		| awk -f "$(REPO_ROOT)/tool/xcode-warnings.awk"

# Interactive debug run with hot reload. Output is left unfiltered so the
# "Flutter run key commands" stay usable.
macos-run:
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d macos --debug \
		--flavor "$(MACOS_DEBUG_FLAVOR)" \
		--target "$(MACOS_DEBUG_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_DEBUG_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL="$(POMODOIST_BILLING_CHANNEL)" \
		$(MACOS_LOCAL_SIGNING_FLAGS)

macos-release: testflight-preflight flutter-build-link
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --release \
		--flavor "$(MACOS_RELEASE_FLAVOR)" \
		--target "$(MACOS_RELEASE_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_RELEASE_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit

# Per-environment builds: macos-<mode>-<environment>. macos-debug is the
# development case, so the two spellings build the same app. The staging and
# production targets pin the environment through target-specific variables, which
# also set the flavor, and release-<environment> skips the TestFlight preflight
# that macos-release runs because it builds locally and never uploads.
define macos_flavor_target
	set -o pipefail; cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --$(1) \
		--flavor "$(MACOS_$(2)_FLAVOR)" \
		--target "$(MACOS_$(2)_TARGET)" \
		--dart-define-from-file="$(call repo_path,$(MACOS_$(2)_CONFIG))" \
		--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
		--dart-define=POMODOIST_BILLING_CHANNEL=storekit \
		$(3) $(MACOS_LOCAL_SIGNING_FLAGS) 2>&1 \
		| awk -f "$(REPO_ROOT)/tool/xcode-warnings.awk"
endef

macos-debug-development: MACOS_DEBUG_CONFIG = $(MACOS_DEVELOPMENT_CONFIG)
macos-debug-development: MACOS_DEBUG_TARGET = $(MACOS_DEVELOPMENT_TARGET)
macos-debug-development:
	$(call macos_flavor_target,debug,DEBUG)

macos-debug-staging: MACOS_DEBUG_CONFIG = $(MACOS_STAGING_CONFIG)
macos-debug-staging: MACOS_DEBUG_TARGET = $(MACOS_STAGING_TARGET)
macos-debug-staging:
	$(call macos_flavor_target,debug,DEBUG)

macos-debug-production: MACOS_DEBUG_CONFIG = $(MACOS_PRODUCTION_CONFIG)
macos-debug-production: MACOS_DEBUG_TARGET = $(MACOS_PRODUCTION_TARGET)
macos-debug-production:
	$(call macos_flavor_target,debug,DEBUG)

macos-profile-development: MACOS_PROFILE_CONFIG = $(MACOS_DEVELOPMENT_CONFIG)
macos-profile-development: MACOS_PROFILE_TARGET = $(MACOS_DEVELOPMENT_TARGET)
macos-profile-development:
	$(call macos_flavor_target,profile,PROFILE)

macos-profile-staging: MACOS_PROFILE_CONFIG = $(MACOS_STAGING_CONFIG)
macos-profile-staging: MACOS_PROFILE_TARGET = $(MACOS_STAGING_TARGET)
macos-profile-staging:
	$(call macos_flavor_target,profile,PROFILE)

# One signed build lets Xcode create/cache missing app and widget profiles.
macos-provision-staging: MACOS_PROFILE_CONFIG = $(MACOS_STAGING_CONFIG)
macos-provision-staging: MACOS_PROFILE_TARGET = $(MACOS_STAGING_TARGET)
macos-provision-staging: flutter-build-link
macos-provision-staging:
	$(call macos_flavor_target,profile,PROFILE,--config-only)
	xcodebuild -workspace "$(FLUTTER_ROOT)/macos/Runner.xcworkspace" \
		-scheme "Staging" -configuration "Profile-Staging" \
		-derivedDataPath "$(FLUTTER_ROOT)/build/macos" \
		-destination 'platform=macOS' \
		-quiet -hideShellScriptEnvironment \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		OBJROOT="$(FLUTTER_ROOT)/build/macos/Build/Intermediates.noindex" \
		SYMROOT="$(FLUTTER_ROOT)/build/macos/Build/Products" \
		COMPILER_INDEX_STORE_ENABLE=NO build

macos-profile-production: MACOS_PROFILE_CONFIG = $(MACOS_PRODUCTION_CONFIG)
macos-profile-production: MACOS_PROFILE_TARGET = $(MACOS_PRODUCTION_TARGET)
macos-profile-production:
	$(call macos_flavor_target,profile,PROFILE)

macos-release-development: MACOS_RELEASE_CONFIG = $(MACOS_DEVELOPMENT_CONFIG)
macos-release-development: MACOS_RELEASE_TARGET = $(MACOS_DEVELOPMENT_TARGET)
macos-release-development:
	$(call macos_flavor_target,release,RELEASE)

macos-release-staging: MACOS_RELEASE_CONFIG = $(MACOS_STAGING_CONFIG)
macos-release-staging: MACOS_RELEASE_TARGET = $(MACOS_STAGING_TARGET)
macos-release-staging:
	$(call macos_flavor_target,release,RELEASE)

macos-release-production: MACOS_RELEASE_CONFIG = $(MACOS_PRODUCTION_CONFIG)
macos-release-production: MACOS_RELEASE_TARGET = $(MACOS_PRODUCTION_TARGET)
macos-release-production:
	$(call macos_flavor_target,release,RELEASE)

# Destructive local reset; cloud accounts and purchases are unchanged.
# Keep macOS container metadata; rm does not follow the sandbox's symlinks.
macos-reset:
	@test "$$(uname -s)" = Darwin || { echo 'macos-reset requires macOS.' >&2; exit 1; }
	@test -n "$${HOME:-}" && test "$$HOME" != / && test -d "$$HOME" || { echo 'A valid HOME directory is required.' >&2; exit 1; }
	@if pgrep -ix 'Pomodoist|Pomodoist Dev|Pomodoist Stg|PomodoistFocus.*' >/dev/null; then echo 'Quit all Pomodoist variants and focus widgets, then run make macos-reset again.' >&2; exit 1; fi
	@echo 'Deleting local Pomodoist development, staging and production data, including unsynced tasks, settings and saved sessions.'
	@for suffix in .dev .stg ''; do \
		app="com.finchforge.pomodoist$$suffix"; widget="$$app.focuswidget"; group="group.com.pomodoist$$suffix"; \
		for domain in "$$app" "$$widget" "$$group" \
			"$$HOME/Library/Containers/$$app/Data/Library/Preferences/$$app" \
			"$$HOME/Library/Containers/$$widget/Data/Library/Preferences/$$widget" \
			"$$HOME/Library/Group Containers/$$group/Library/Preferences/$$group"; do \
			defaults delete "$$domain" 2>/dev/null || true; \
		done; \
		for bundle in "$$app" "$$widget"; do \
			rm -rf "$$HOME/Library/Containers/$$bundle/Data" \
				"$$HOME/Library/Application Support/$$bundle" \
				"$$HOME/Library/Caches/$$bundle" \
				"$$HOME/Library/Saved Application State/$$bundle.savedState"; \
			rm -f "$$HOME/Library/Preferences/$$bundle.plist"; \
			tccutil reset All "$$bundle"; \
		done; \
		rm -rf "$$HOME/Library/Group Containers/$$group/Library" \
			"$$HOME/Library/Group Containers/$$group/focus-snapshot-v1.json"; \
	done
	rm -f "$$HOME/Documents/pomodoist.sqlite" "$$HOME/Documents/pomodoist.sqlite-wal" "$$HOME/Documents/pomodoist.sqlite-shm"
	@echo 'Local reset complete. Start Pomodoist in guest mode for a clean slate.'

# Flutter profile mode is unavailable on iOS Simulator, so local runs use debug.
ios-debug ios-profile: RUN_SIMULATOR = $(IOS_SIMULATOR)
ipad-debug ipad-profile: RUN_SIMULATOR = $(IPAD_SIMULATOR)
ios-debug ios-profile ipad-debug ipad-profile: flutter-build-link
	xcrun simctl bootstatus "$(RUN_SIMULATOR)" -b
	$(OPEN_SIMULATOR)
	cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" run -d "$(RUN_SIMULATOR)" --debug --flavor "$(LOCAL_FLAVOR)" --target "$(LOCAL_TARGET)" --dart-define-from-file="$(call repo_path,$(LOCAL_CONFIG))" --dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" --dart-define=POMODOIST_BILLING_CHANNEL=storekit

# The flavor identity of the Xcode project, as a scheme name and as target
# settings. The Xcode project is the only place the iOS flavor identity is
# declared, and `apps/flutter/test/ios_flavor_configuration_test.dart` reads it
# directly; this target is how you cross-check that file against what Xcode
# resolves. Flutter lowercases `--flavor` into the Xcode scheme name, so
# `Debug-Development` is what `flutter run --flavor development` builds, and a
# scheme carries exactly one configuration.
.flavor_scheme = $(shell printf '%s' '$(1)' | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')
.flavor_configuration = $(if $(filter production,$(1)),Debug,$(if $(filter staging,$(1)),Debug-Staging,Debug-Development))
flavor_scheme = $(call .flavor_scheme,$(1))
flavor_configuration = $(call .flavor_configuration,$(1))

ios-flavor-settings:
	@xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b >/dev/null 2>&1 || true
	xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b
	xcodebuild -project "$(FLUTTER_ROOT)/ios/Runner.xcodeproj" -target Runner -configuration "$(call flavor_configuration,$(STAGING_FLAVOR))" -sdk iphonesimulator -showBuildSettings | grep -E '^ +(PRODUCT_BUNDLE_IDENTIFIER|PRODUCT_NAME|INFOPLIST_FILE|POMODOIST_APP_GROUP|POMODOIST_URL_SCHEME|POMODOIST_DISPLAY_NAME|ASSETCATALOG_COMPILER_APPICON_NAME|CODE_SIGN_ENTITLEMENTS) ='
	xcrun simctl bootstatus "$(WATCH_SIMULATOR)" -b >/dev/null 2>&1 || true
	xcodebuild -project "$(FLUTTER_ROOT)/ios/Runner.xcodeproj" -target Runner -configuration "$(call flavor_configuration,$(LOCAL_FLAVOR))" -sdk iphonesimulator -showBuildSettings | grep -E '^ +(PRODUCT_BUNDLE_IDENTIFIER|PRODUCT_NAME|INFOPLIST_FILE|POMODOIST_APP_GROUP|POMODOIST_URL_SCHEME|POMODOIST_DISPLAY_NAME|ASSETCATALOG_COMPILER_APPICON_NAME|CODE_SIGN_ENTITLEMENTS) ='
	xcodebuild -project "$(FLUTTER_ROOT)/ios/Runner.xcodeproj" -target PomodoistWatch -configuration "$(call flavor_configuration,$(LOCAL_FLAVOR))" -sdk watchsimulator -showBuildSettings | grep -E '^ +(PRODUCT_BUNDLE_IDENTIFIER|PRODUCT_NAME|TARGET_NAME|ASSETCATALOG_COMPILER_APPICON_NAME|CODE_SIGN_ENTITLEMENTS) ='
	xcodebuild -project "$(FLUTTER_ROOT)/ios/Runner.xcodeproj" -target RunnerTests -configuration "$(call flavor_configuration,$(LOCAL_FLAVOR))" -sdk iphonesimulator -showBuildSettings | grep -E '^ +(PRODUCT_BUNDLE_IDENTIFIER|TEST_HOST|BUNDLE_LOADER) ='

# The watch app is built straight from the Xcode project, which takes no
# flavor, so it keeps the base Debug/Profile configurations and the production
# watch bundle identifier.
watch-debug: WATCH_CONFIGURATION = Debug
watch-profile: WATCH_CONFIGURATION = Profile
watch-debug watch-profile:
	xcrun simctl bootstatus "$(WATCH_SIMULATOR)" -b
	$(OPEN_SIMULATOR)
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
			--flavor "$(TESTFLIGHT_FLAVOR)" \
			--target "$(TESTFLIGHT_TARGET)" \
			--export-options-plist="$(call repo_path,$(IOS_EXPORT_OPTIONS))" \
			--dart-define-from-file="$(call repo_path,$(TESTFLIGHT_CONFIG))" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit $(TESTFLIGHT_DEFINES)); \
		test -f "$(IOS_IPA_PATH)" || (echo "Missing $(IOS_IPA_PATH)" >&2; exit 1); \
		xcrun altool --validate-app "$(IOS_IPA_PATH)" \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"; \
		xcrun altool --upload-app -f "$(IOS_IPA_PATH)" \
			--api-key "$(ASC_KEY_ID)" \
			--api-issuer "$(ASC_ISSUER_ID)" \
			--p8-file-path "$$key_path"

MACOS_ARTIFACT_SUFFIX = $(if $(filter $(FLAVOR_PRODUCTION),$(TESTFLIGHT_FLAVOR)),,-$(TESTFLIGHT_FLAVOR))
MACOS_ARCHIVE_PATH = $(abspath build/TestFlight/Pomodoist-macOS$(MACOS_ARTIFACT_SUFFIX).xcarchive)
MACOS_EXPORT_PATH = $(abspath build/TestFlight/macos$(MACOS_ARTIFACT_SUFFIX))
MACOS_PACKAGE_PATH = $(MACOS_EXPORT_PATH)/$(TESTFLIGHT_PRODUCT_NAME).pkg
# Keep Xcode's archive intermediates under build/ instead of the global
# ~/Library/Developer/Xcode/DerivedData.
MACOS_DERIVED_DATA = $(abspath build/TestFlight/derived-data)
TESTFLIGHT_MACOS_SCHEME ?= $(if $(filter $(FLAVOR_STAGING),$(TESTFLIGHT_FLAVOR)),Staging,Runner)
TESTFLIGHT_MACOS_CONFIGURATION ?= $(if $(filter $(FLAVOR_STAGING),$(TESTFLIGHT_FLAVOR)),Release-Staging,Release)

testflight-macos: testflight-preflight testflight-auth flutter-build-link
	@set -eu; \
		key_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/pomodoist-testflight.XXXXXX")"; \
		trap 'test -n "$$key_dir" && rm -rf -- "$$key_dir"' EXIT HUP INT TERM; \
		key_path="$$key_dir/AuthKey_$(ASC_KEY_ID).p8"; \
		"$(DART)" tool/env_setup.dart write-asc-key --env "$(PRIVATE_CONFIG)" --output "$$key_path"; \
		(cd "$(FLUTTER_ROOT)" && "$(FLUTTER)" build macos --release \
			--flavor "$(TESTFLIGHT_FLAVOR)" \
			--target "$(TESTFLIGHT_TARGET)" \
			--dart-define-from-file="$(call repo_path,$(TESTFLIGHT_CONFIG))" \
			--dart-define=POMODOIST_RELEASE="$(POMODOIST_RELEASE)" \
			--dart-define=POMODOIST_BILLING_CHANNEL=storekit $(TESTFLIGHT_DEFINES)); \
		rm -rf "$(MACOS_ARCHIVE_PATH)" "$(MACOS_EXPORT_PATH)"; \
		xcodebuild -workspace "$(FLUTTER_ROOT)/macos/Runner.xcworkspace" -scheme "$(TESTFLIGHT_MACOS_SCHEME)" \
			-configuration "$(TESTFLIGHT_MACOS_CONFIGURATION)" -archivePath "$(MACOS_ARCHIVE_PATH)" archive \
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

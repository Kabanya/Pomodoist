FLUTTER ?= flutter
POMODOIST_BILLING_CHANNEL ?= stripe

.PHONY: analyze test check run web build-web format

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

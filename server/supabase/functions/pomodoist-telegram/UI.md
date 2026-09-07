# Pomodoist Telegram interface

The chat is a quick-capture entry point. An ordinary message creates an Inbox
task, followed by a short confirmation and a Mini App launch button. `/start` and
legacy interactions show the launcher. Old edit replies never become new tasks.

All task management lives in `telegram-mini-app`: five bottom navigation tabs,
account access in the header, compact task rows, and a task detail sheet. Details
include title, comment, all-day date, priority, project and read-only schedule,
recurrence and deadline metadata. Completion is available in the list. Deletion
has an explicit confirmation; recurring-task and subtree limits remain enforced
by the shared backend, with a route to the full app.

The light/dark palettes mirror `lib/app/theme/app_theme.dart`; Telegram chooses
the mode. Controls use 8px corners, native form fields, system fonts, touch targets,
visible keyboard focus and Telegram safe-area insets. The task sheet fits the
keyboard-adjusted viewport. Telegram Back closes a sheet before returning to
Inbox. Optional haptics accompany completion and focus controls. Reduced-motion
settings disable the loading animation.

Focus controls are in the Mini App itself. A compact active-session card remains
available in task lists; the Focus tab expands the timer. Remaining time comes
from stored timestamps, and the server verifies elapsed completion.

Titles and comments are inserted with `textContent` or form values. The chat
launcher uses plain text. No user text is interpreted as HTML or Markdown.
Seven Mini App languages remain available, including Arabic right-to-left layout;
chat copy supports English/Russian with English fallback.

See README.md for the signed API, draft/outbox behavior, validation commands,
browser regression and live release acceptance steps.

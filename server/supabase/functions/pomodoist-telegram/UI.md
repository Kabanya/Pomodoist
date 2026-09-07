# Pomodoist chat UI

Issue #56 aligns the existing private-chat bot with the main app. This is a
presentation update, not a new Mini App, deployment, or synchronization protocol.

## Design contract

`bot_ui.ts` owns English/Russian copy and screen layouts. Its `appCopyKeys` map
links shared terms to `lib/l10n/app_en.arb` and `app_ru.arb`. The localization
regression test reads those real dictionaries; Telegram CI also runs when either
ARB changes. Bot-specific instructions remain here because they describe chat
interactions rather than Flutter controls. Other Telegram languages fall back to
English, as before.

Every screen uses a bold `Pomodoist · section` heading, short blocks, and the same
three-row footer: Today / Upcoming / Inbox, Focus / Completed / Account, Add task.
The completed-list footer uses the app's short Completed status label. Tasks use
numbered previews and matching one-line buttons. An open circle and check mark
distinguish open/completed tasks; priority always includes its P1–P4 number rather
than relying on color. Task cards separate title, status/priority, project,
schedule, deadline and comment. Destructive confirmation places Cancel before
Delete. Focus displays the linked task even outside the current list page, work
state, a monospace remaining clock, and explicit Refresh guidance.

Telegram owns chat fonts, button styling, and light/dark themes. The bot does not
attempt to reproduce Flutter colors with images, custom emoji dependencies, or
HTML/CSS. Semantic hierarchy, labels and product behavior are shared instead.
`bot_format.ts` sends explicit Telegram message entities, never `parse_mode`:
user HTML/Markdown remains literal text. Offsets are UTF-16 units; truncation does
not split surrogate pairs. Messages reserve room for notices and remain below
4096 units. Notices shift formatting offsets. Signed edit metadata remains the
last text line (hidden visually with a spoiler entity), preserving existing HMAC
validation, expiry and idempotency. Truncation affects display only, not stored
content or comments.

## Product semantics

The `taskPage` snapshot adds read-only project, deadline, time-zone and active
focus metadata. Existing fields, filtering, pagination and mutation semantics
remain intact. Archived/deleted projects and tasks stay hidden, including in the
linked Focus title.

- P1–P4 keep the existing numeric priority contract. The picker writes only the
  `priority` patch with the captured revision and stable callback receipt.
- All-day schedules and `deadlineJson` dates are floating calendar dates. A
  deadline is displayed separately and never treated as the scheduled day.
- Timed schedules display their start/end range in the configured bot display
  zone, including both dates across midnight. Timed status follows
  `lib/app/task_time.dart`: completed, focused, future, current, overdue; the end
  boundary is overdue. Open all-day tasks before today are overdue. Completed
  cards do not show overdue warnings.
- Today continues to include overdue scheduled tasks; Upcoming starts after
  today. Relative day labels use the same configured zone as the snapshot.
- Chat scheduling remains explicitly all-day and warns that it replaces a timed
  schedule. Deadline/recurrence editing remains in the main app. A recurrence
  marker does not imply that the bot can change or delete a recurring series.
- The existing 25-minute chat work interval and pause/resume/stop/elapsed-only
  completion rules remain unchanged. This does not add auto-refresh, background
  notifications or cross-device native timer control.

Callback acknowledgement still happens before account/database work. Rendering
adds no external requests or additional database queries to existing screens.

## Verification

From `server/supabase`:

```sh
deno check functions/pomodoist-telegram/index.ts
deno test --allow-read --allow-env functions/pomodoist-telegram \
  functions/pomodoist-watch/pomodoist_watch_test.ts \
  ../../telegram-mini-app/core_test.ts
```

`bot_ui_test.ts` exercises rendering, time boundaries, long Unicode text,
formatting offsets, snapshot compatibility, priority interactions, notices and
signed edit replies. `bot_copy_test.ts` prevents translation drift. Existing
webhook, storage, Watch and Mini App tests remain part of the same CI job.

Manual release checks (not substitutes for automated tests): inspect Russian and
English private chats on mobile and desktop, in light/dark themes; open all four
lists, create/edit a task and comment, schedule, change priority, complete/reopen,
cancel and confirm deletion; start/pause/resume/stop/finish Focus; inspect empty
lists, expired controls and malformed inputs. Confirm that long titles wrap only
in the message, action labels remain readable, and account linking still opens
the existing flow. A live bot deployment and these client checks are separate
release steps; no production credentials or webhook registration are required to
run the tests.

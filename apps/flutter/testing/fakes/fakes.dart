/// Hand-written test doubles for the repositories, services, and platform
/// ports the app depends on.
///
/// Doubles record what they were asked to do and replay what the test told
/// them to answer; nothing here touches a database, a network, or a plugin
/// channel.
///
/// Importing this library pulls in `package:flutter_test`, so it is meant for
/// `test/` only. Application code under `lib/` must never depend on it.
library;

export 'fake_account_client.dart';
export 'fake_account_management_repository.dart';
export 'fake_account_session_repository.dart';
export 'fake_achievement_repository.dart';
export 'fake_billing_repository.dart';
export 'fake_billing_store.dart';
export 'fake_calendar_integration_repository.dart';
export 'fake_focus_repository.dart';
export 'fake_kanban_repository.dart';
export 'fake_label_repository.dart';
export 'fake_linux_shortcuts_portal.dart';
export 'fake_notification_scheduler.dart';
export 'fake_notifiers.dart';
export 'fake_outbox_service.dart';
export 'fake_project_repository.dart';
export 'fake_quick_add_hint.dart';
export 'fake_recorded_recognizer.dart';
export 'fake_startup_monitor.dart';
export 'fake_sync_repository.dart';
export 'fake_task_decomposer.dart';
export 'fake_task_repository.dart';
export 'fake_update_contracts.dart';
export 'fake_voice_capture_repository.dart';
export 'fake_voice_recorder.dart';
export 'strict_fake.dart';

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonStop => 'Stop';

  @override
  String get skip => 'Skip';

  @override
  String get onboardingLanguageTitle => 'Choose language';

  @override
  String get onboardingLanguageSubtitle =>
      'Pick the language Pomodoist should use.';

  @override
  String get onboardingTimerTitle => 'Choose timer style';

  @override
  String get onboardingTimerSubtitle =>
      'Pick the Pomodoro progress view for focus sessions.';

  @override
  String get onboardingPaywallTitle => 'Unlock Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'The Lifetime offer is available for 24 hours every week.';

  @override
  String get onboardingAccountTitle => 'Create an account';

  @override
  String get onboardingAccountSubtitle =>
      'Sign in to sync tasks, focus history, and settings between devices.';

  @override
  String get startupPreparingTasks => 'Preparing your tasks';

  @override
  String get operationTakingLonger =>
      'This is taking longer than usual. The operation is still running.';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingMaybeLater => 'Maybe later';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Dictate tasks in natural language, and Pomodoist turns your words into tasks. Task history is saved forever.';

  @override
  String get billingSubtitleHighlight => 'natural language';

  @override
  String get billingCancelAnytime => 'Cancel anytime.';

  @override
  String get billingMonthlyTitle => 'Monthly';

  @override
  String get billingAnnualTitle => 'Annual';

  @override
  String billingPricePerMonth(String price) {
    return '$price/month';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/year';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'First 3 months, then $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Then $price.';
  }

  @override
  String get billingLifetimeTitle => 'Lifetime';

  @override
  String get billingLifetimeSubtitle => 'One payment forever.';

  @override
  String get billingBestValue => 'Best value';

  @override
  String get billingChoose => 'Choose';

  @override
  String get billingActive => 'Pomodoist Pro is active on this device.';

  @override
  String get billingActiveShort => 'Active';

  @override
  String get billingRestore => 'Restore purchases';

  @override
  String get billingManageLink => 'Manage through Link';

  @override
  String get billingExternalBrowserTitle => 'Payment opens in your browser';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist will open Stripe Checkout in Safari or your default browser. Allow the browser window to continue.';

  @override
  String get billingAppleOnly =>
      'Purchases are available on iPhone, iPad, and Mac.';

  @override
  String get billingStoreUnavailable =>
      'The App Store is not available right now.';

  @override
  String billingPurchaseError(String error) {
    return 'Purchase error: $error';
  }

  @override
  String get purchaseSuccessTitle => 'Pro is active';

  @override
  String get purchaseSuccessMessage =>
      'Thanks for supporting Pomodoist. All Pro features are ready to use.';

  @override
  String get purchaseSuccessContinue => 'Continue';

  @override
  String get purchaseProcessingTitle => 'Payment is processing';

  @override
  String get purchaseProcessingMessage =>
      'Your payment is being confirmed. If Pro does not appear shortly, refresh again later.';

  @override
  String get purchaseOpenApp => 'Open Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return 'Lifetime offer ends in $time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'Email';

  @override
  String get loginTitle => 'Sign in to Pomodoist';

  @override
  String get accountChecking => 'Checking your account';

  @override
  String get oauthConsentTitle => 'Connect an agent';

  @override
  String get oauthConsentLoading => 'Checking the connection request';

  @override
  String get oauthConsentInvalidAuthorization =>
      'This connection request is missing or invalid.';

  @override
  String get oauthConsentLoadError => 'Could not load the connection request.';

  @override
  String get oauthConsentActionError =>
      'Could not complete the request. Try again.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist received an unsafe or missing return address. Access was not handed off.';

  @override
  String get oauthConsentClientFallback => 'Agent';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName wants to access Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Return address';

  @override
  String get oauthConsentCapabilitiesTitle => 'This agent can';

  @override
  String get oauthConsentManagePlanning =>
      'Read and manage tasks, projects, user labels, and Kanban.';

  @override
  String get oauthConsentReadInsights =>
      'Read completed focus history, productivity reports, and achievements.';

  @override
  String get oauthConsentUnavailableTitle => 'This agent cannot';

  @override
  String get oauthConsentUnavailable =>
      'Access your account or billing, Google Calendar, or the live focus timer.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'This request asks for unsupported account access and cannot be approved.';

  @override
  String get oauthConsentApprove => 'Allow';

  @override
  String get oauthConsentDeny => 'Deny';

  @override
  String get oauthConsentApproving => 'Allowing access…';

  @override
  String get oauthConsentDenying => 'Denying access…';

  @override
  String get oauthConsentRedirecting => 'Returning to the agent…';

  @override
  String get loginCreateAccountPrompt => 'No account yet?';

  @override
  String get loginCreateAccountAction => 'Create account';

  @override
  String get registerTitle => 'Create an account';

  @override
  String get registerSubtitle =>
      'Sync tasks, focus history, and settings between devices.';

  @override
  String get registerPassword => 'Password';

  @override
  String get registerSubmit => 'Create account';

  @override
  String get registerSignInPrompt => 'Already have an account?';

  @override
  String get registerSignInAction => 'Sign in';

  @override
  String get registerCheckEmailTitle => 'Check your email';

  @override
  String get registerCheckEmailMessage =>
      'Open the confirmation link to finish creating your account.';

  @override
  String registerError(Object error) {
    return 'Could not create account: $error';
  }

  @override
  String get navSearch => 'Search';

  @override
  String get navInbox => 'Inbox';

  @override
  String get navPriorityMatrix => 'Priority Matrix';

  @override
  String get navTimeline => 'Timeline';

  @override
  String get navKanban => 'Kanban';

  @override
  String get kanbanTitle => 'Kanban';

  @override
  String get kanbanSubtitle =>
      'Visualize your workflow and focus on what matters now.';

  @override
  String get kanbanDefaultBacklog => 'Backlog';

  @override
  String get kanbanDefaultTodo => 'To do';

  @override
  String get kanbanDefaultInProgress => 'In progress';

  @override
  String get kanbanDefaultDone => 'Done';

  @override
  String get kanbanSearchTooltip => 'Search Kanban';

  @override
  String get kanbanSearchHint => 'Search tasks or projects';

  @override
  String get kanbanHideDone => 'Hide Done';

  @override
  String get kanbanShowDone => 'Show Done';

  @override
  String get kanbanProjectsTitle => 'Projects on this board';

  @override
  String kanbanAddToStatus(String status) {
    return 'Add to $status';
  }

  @override
  String get kanbanTaskField => 'Task';

  @override
  String get kanbanProjectField => 'Project';

  @override
  String get kanbanChooseProject => 'Choose a project.';

  @override
  String get kanbanTaskActions => 'Task actions';

  @override
  String get kanbanDragTask => 'Drag task';

  @override
  String kanbanMoveTo(String status) {
    return 'Move to $status';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Restore the task before starting Focus.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'Could not start Focus: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'Could not load Kanban: $error';
  }

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonContinueWaiting => 'Continue waiting';

  @override
  String kanbanTasksCount(int count) {
    return '$count tasks';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '$completed of $total subtasks';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '$completed of $total focus intervals';
  }

  @override
  String get kanbanActive => 'Active';

  @override
  String kanbanPriority(int priority) {
    return 'Priority $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Moved to $status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Focus started for $task';
  }

  @override
  String get kanbanNoTasks => 'No tasks yet';

  @override
  String get navToday => 'Today';

  @override
  String get navUpcoming => 'Upcoming';

  @override
  String get navBrowse => 'Browse';

  @override
  String get navIntegrations => 'Integrations';

  @override
  String get navReports => 'Reports';

  @override
  String get navFocus => 'Focus';

  @override
  String get navProjects => 'Projects';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get csvImportTitle => 'Import tasks from CSV';

  @override
  String get csvImportSubtitle =>
      'Review a CSV file before creating tasks, projects, labels, and workflow statuses.';

  @override
  String get csvImportSelectFile => 'Choose CSV file';

  @override
  String get csvImportHumanGuideButton => 'Guide for people';

  @override
  String get csvImportAgentGuideButton => 'Guide for agents';

  @override
  String get csvImportHumanGuideTitle => 'How to prepare a CSV file';

  @override
  String get csvImportAgentGuideTitle => 'CSV contract for an agent';

  @override
  String get csvImportCopy => 'Copy';

  @override
  String get csvImportCopied => 'Copied to clipboard.';

  @override
  String get csvImportPreviewTitle => 'Review import';

  @override
  String get csvImportPreviewTasks => 'Tasks';

  @override
  String get csvImportPreviewSubtasks => 'Subtasks';

  @override
  String get csvImportPreviewNewProjects => 'New projects';

  @override
  String get csvImportPreviewNewLabels => 'New labels';

  @override
  String get csvImportPreviewNewStatuses => 'New workflow statuses';

  @override
  String get csvImportNone => 'None';

  @override
  String get csvImportDuplicateWarning =>
      'Importing the same file again will create duplicate tasks.';

  @override
  String get csvImportConfirm => 'Import';

  @override
  String get csvImportSuccess => 'Tasks imported';

  @override
  String get csvImportErrorTitle => 'CSV import failed';

  @override
  String get csvImportUnexpectedError => 'The file could not be imported.';

  @override
  String get csvImportHumanGuide =>
      '1. Save the file as UTF-8 CSV. Use a comma (recommended) or semicolon as the separator.\n\n2. The content column is required. You may also use: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Put one open task on each row. Separate labels with |. Priority is 1–4; an empty value means 4. An empty project means Inbox and an empty workflow status means Backlog. Missing projects, labels, and open statuses are created automatically.\n\n4. For an all-day task, use due_date in YYYY-MM-DD format. For a timed task, fill start_at and end_at as RFC3339 values with a UTC offset and provide an IANA time_zone, for example Europe/Moscow.\n\n5. To create subtasks, give the parent row a unique key and put that value in the child\'s parent_key. Parents may appear later in the file. A child must use the same project as its parent.\n\n6. Pomodoist validates the whole file and shows a preview before importing. Nothing is saved if any row is invalid. Re-importing creates duplicate tasks.';

  @override
  String get settingsConnectedAgentsTitle => 'Connected agents';

  @override
  String get settingsConnectedAgentsLoading => 'Loading connected agents…';

  @override
  String get settingsConnectedAgentsEmpty => 'No agents are connected.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'Could not load connected agents.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Agent';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Connected on $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Revoke access';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'Revoke agent access?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'Revoke Pomodoist access for $clientName?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'Could not revoke access. Try again.';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Choose the app language.';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsThemeSubtitle => 'Choose the app appearance.';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsTimerVisualTitle => 'Pomodoro timer';

  @override
  String get settingsTimerVisualSubtitle =>
      'Choose how progress is shown on the focus screen.';

  @override
  String get settingsTimerVisualBar => 'Bar';

  @override
  String get settingsTimerVisualCircle => 'Circle';

  @override
  String get settingsReturnRemindersTitle => 'Return reminders';

  @override
  String get settingsReturnRemindersSubtitle =>
      'A gentle evening nudge if today has no focus or completed task.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Default calendar block duration';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'When only a time is entered, new tasks use this calendar duration.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Custom duration';

  @override
  String get settingsDefaultTimedBlockError => 'Enter 1 to 480 minutes.';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get localUser => 'Local User';

  @override
  String get addTask => 'Add task';

  @override
  String get quickAddHint => 'Write sync engine tomorrow p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'Could not add task: $error';
  }

  @override
  String couldNotAddProject(Object error) {
    return 'Could not add project: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count tasks',
      one: 'Added 1 task',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Voice quick add';

  @override
  String get voiceTitle => 'Voice add';

  @override
  String get voiceRecord => 'Record';

  @override
  String get voiceAgain => 'Again';

  @override
  String get voiceStop => 'Stop';

  @override
  String voiceAddCount(int count) {
    return 'Add $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Task $index';
  }

  @override
  String get voiceRemoveTask => 'Remove';

  @override
  String get voiceInstruction => 'Tap record and dictate tasks.';

  @override
  String get voiceStatusIdle => 'Built-in microphone input only';

  @override
  String get voiceStatusRequestingPermission => 'Requesting access';

  @override
  String get voiceStatusRecording => 'Listening to the built-in microphone';

  @override
  String get voiceStatusTranscribing => 'Transcribing recording';

  @override
  String get voiceStatusCanceled => 'Recording canceled';

  @override
  String get voiceStatusUnsupported => 'Platform is not supported';

  @override
  String get voiceStatusError => 'Could not recognize speech';

  @override
  String get voiceStatusAnalyzing => 'Splitting into tasks';

  @override
  String get voiceStatusReview => 'Review tasks before adding';

  @override
  String get voiceStepRecord => 'Record';

  @override
  String get voiceStepText => 'Text';

  @override
  String get voiceStepAnalyze => 'Analyze';

  @override
  String get voiceStepReview => 'Review';

  @override
  String get voiceAnalyzing => 'Pomodoist is splitting speech into tasks';

  @override
  String get voiceFallbackError =>
      'Pomodoist could not process speech; kept a draft for manual editing.';

  @override
  String get voiceSmartMode => 'Smart mode';

  @override
  String get voiceRetryAnalysis => 'Retry analysis';

  @override
  String get screenInboxSubtitle => 'Capture tasks before organizing them.';

  @override
  String get priorityMatrixSubtitle =>
      'Drag tasks between priorities. Dates only sort tasks inside a priority.';

  @override
  String get priorityMatrixP1Title => 'Do now';

  @override
  String get priorityMatrixP2Title => 'Schedule';

  @override
  String get priorityMatrixP3Title => 'Delegate';

  @override
  String get priorityMatrixP4Title => 'Drop';

  @override
  String get priorityMatrixAxisUrgent => 'Urgent';

  @override
  String get priorityMatrixAxisNotUrgent => 'Not urgent';

  @override
  String get priorityMatrixAxisImportant => 'Important';

  @override
  String get priorityMatrixAxisNotImportant => 'Not important';

  @override
  String get timelineSubtitle => 'Plan one day on a time grid.';

  @override
  String get timelineAllDay => 'All-day';

  @override
  String get timelineBeforeHours => 'Before visible hours';

  @override
  String get timelineAfterHours => 'After visible hours';

  @override
  String get timelineVisibleHours => 'Visible hours';

  @override
  String get timelineStartHour => 'Start';

  @override
  String get timelineEndHour => 'End';

  @override
  String get timelineZoomOut => 'Zoom out';

  @override
  String get timelineZoomIn => 'Zoom in';

  @override
  String timelineAddTimedHint(String time) {
    return 'Task for $time';
  }

  @override
  String get timelineAddAllDayHint => 'All-day task';

  @override
  String get timelineNoAllDayTasks => 'No all-day tasks';

  @override
  String get timelineNoTimedTasks => 'No timed tasks';

  @override
  String get timelinePreviousDay => 'Previous day';

  @override
  String get timelineNextDay => 'Next day';

  @override
  String get timelinePickDate => 'Pick date';

  @override
  String get upcomingPreviousPeriod => 'Previous period';

  @override
  String get upcomingNextPeriod => 'Next period';

  @override
  String get upcomingOpenDatePicker => 'Open date picker';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
      zero: 'No tasks',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Focus load: $planned intervals - Done: $completed - Focus: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Planned tasks after today.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Tasks scheduled for $date.';
  }

  @override
  String get noTasksHere => 'No tasks here';

  @override
  String get noUpcomingTasks => 'No dated tasks';

  @override
  String get noTasksForDay => 'No tasks scheduled for this day';

  @override
  String failedToLoadTasks(Object error) {
    return 'Failed to load tasks: $error';
  }

  @override
  String get searchTasks => 'Search tasks';

  @override
  String get searchStartTyping => 'Start typing to search tasks';

  @override
  String get searchNoMatches => 'No matching tasks';

  @override
  String failedToSearchTasks(Object error) {
    return 'Failed to search tasks: $error';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get clearDateFilter => 'Clear date filter';

  @override
  String get weekMon => 'Mon';

  @override
  String get weekTue => 'Tue';

  @override
  String get weekWed => 'Wed';

  @override
  String get weekThu => 'Thu';

  @override
  String get weekFri => 'Fri';

  @override
  String get weekSat => 'Sat';

  @override
  String get weekSun => 'Sun';

  @override
  String get browseTitle => 'Browse';

  @override
  String get unifiedAccount => 'Unified Account';

  @override
  String accountUnavailable(Object error) {
    return 'Account unavailable: $error';
  }

  @override
  String get signOut => 'Sign out';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountConfirmation =>
      'This permanently deletes your account, cloud data, and local tasks, projects, and focus history. This cannot be undone. Store subscriptions are not canceled automatically.';

  @override
  String get deleteAccountFinalConfirmation =>
      'Are you absolutely sure? This is your final confirmation.';

  @override
  String deleteAccountError(Object error) {
    return 'Could not delete account: $error';
  }

  @override
  String get accountDeleted => 'Account deleted.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Your account was deleted, but local data could not be cleared. Clear the app\'s data before using this device again.';

  @override
  String get productivityTitle => 'Productivity';

  @override
  String get achievementsTitle => 'Achievements';

  @override
  String get allTimeLabel => 'All time';

  @override
  String get lastSevenDaysLabel => 'Last 7 days';

  @override
  String get noWeeklyStatsLabel => 'No focus or task data yet';

  @override
  String get completedFocuses => 'Completed focuses';

  @override
  String get completedTasks => 'Completed tasks';

  @override
  String get unlocked => 'Unlocked';

  @override
  String get locked => 'Locked';

  @override
  String get progressLabel => 'Progress';

  @override
  String get focusAchievements => 'Focus achievements';

  @override
  String get taskAchievements => 'Task achievements';

  @override
  String get comboAchievements => 'Combo achievements';

  @override
  String get focusIntervals => 'Focus intervals';

  @override
  String get focusTime => 'Focus time';

  @override
  String get openTasks => 'Open tasks';

  @override
  String get plannedIntervals => 'Planned intervals';

  @override
  String get labelsTitle => 'Labels';

  @override
  String get newProject => 'New project';

  @override
  String get newLabel => 'New label';

  @override
  String get syncReadyQueue => 'Sync-ready queue';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending local commands',
      one: '1 pending local command',
      zero: 'No pending local commands',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'Failed to load projects: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'Failed to load labels: $error';
  }

  @override
  String get addProject => 'Add project';

  @override
  String get projectName => 'Project name';

  @override
  String get addLabel => 'Add label';

  @override
  String get labelName => 'Label name';

  @override
  String couldNotAddLabel(Object error) {
    return 'Could not add label: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Projects unavailable: $error';
  }

  @override
  String get projectsUnavailableShort => 'Projects unavailable';

  @override
  String get noProjects => 'No projects';

  @override
  String get searchProjects => 'Search projects';

  @override
  String get searchLabels => 'Search labels';

  @override
  String get archivedProjectsOnly => 'Archived projects only';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'No labels';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count labels',
      one: '1 label',
    );
    return '$_temp0';
  }

  @override
  String get deleteProject => 'Delete project';

  @override
  String get deleteLabel => 'Delete label';

  @override
  String deleteProjectConfirmation(String name) {
    return 'Delete \"$name\"? Tasks in this project will move to Inbox.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'Could not delete project: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'Could not delete label: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Projects: $count';
  }

  @override
  String get collapseProjects => 'Collapse projects';

  @override
  String get expandProjects => 'Expand projects';

  @override
  String get projectFallbackTitle => 'Project';

  @override
  String get projectSubtitle =>
      'List view - board and calendar are roadmap items.';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsFocusedDay => 'A focused day so far';

  @override
  String get reportsThisWeek => 'Your week in focus';

  @override
  String get reportsNextAchievement => 'Next achievement';

  @override
  String get viewAllAchievements => 'View all achievements';

  @override
  String viewAllAchievementsCount(int count) {
    return 'View all $count';
  }

  @override
  String get allAchievementsUnlocked => 'All achievements unlocked';

  @override
  String get noAchievementsYet => 'No achievements yet';

  @override
  String failedToLoadAchievements(Object error) {
    return 'Failed to load achievements: $error';
  }

  @override
  String get backToReports => 'Back to reports';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '$completed of $target focus intervals completed';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '$completed focus intervals completed; no goal set';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Focus time for the last 7 days: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'Failed to load reports: $error';
  }

  @override
  String get taskNotFound => 'Task not found';

  @override
  String get taskTitleHint => 'Task title';

  @override
  String get taskComment => 'Comment';

  @override
  String get taskCommentHint => 'Add a comment';

  @override
  String get subtasks => 'Sub-tasks';

  @override
  String get addSubtask => 'Add sub-task';

  @override
  String get addSubtaskHint => 'Add a sub-task';

  @override
  String get noSubtasks => 'No sub-tasks yet.';

  @override
  String get makeParentTask => 'Make parent task';

  @override
  String couldNotMoveTask(Object error) {
    return 'Could not move task: $error';
  }

  @override
  String get scheduleTitle => 'Schedule';

  @override
  String get allDay => 'All-day';

  @override
  String get timedBlock => 'Timed block';

  @override
  String get recurrenceTitle => 'Repeat';

  @override
  String get recurrenceNeedsSchedule => 'Add a date or time before repeating.';

  @override
  String get recurrenceIntervalLabel => 'Interval';

  @override
  String get recurrenceUnitDay => 'Days';

  @override
  String get recurrenceUnitWeek => 'Weeks';

  @override
  String get recurrenceUnitMonth => 'Months';

  @override
  String get recurrenceInvalidInterval => 'Enter 1 to 999.';

  @override
  String recurrenceEveryDays(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'every $interval days',
      one: 'every day',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'every $interval weeks',
      one: 'every week',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'every $interval months',
      one: 'every month',
    );
    return '$_temp0';
  }

  @override
  String get noDate => 'No date';

  @override
  String get calendarNotLinked => 'Calendar not linked';

  @override
  String get calendarLinked => 'Google Calendar linked';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total focus';
  }

  @override
  String get startFocus => 'Start focus';

  @override
  String get focusStarted => 'Focus started';

  @override
  String get taskReopened => 'Task reopened';

  @override
  String get taskCompleted => 'Task completed';

  @override
  String get taskDeleted => 'Task deleted';

  @override
  String get recurringDeleteTitle => 'Delete recurring task?';

  @override
  String get recurringDeleteMessage =>
      'This task belongs to a recurring series.';

  @override
  String get recurringDeleteThis => 'Delete this task';

  @override
  String get recurringDeleteThisAndFollowing => 'Delete this and following';

  @override
  String get markOpen => 'Mark open';

  @override
  String get markComplete => 'Mark complete';

  @override
  String get focusHistory => 'Focus history';

  @override
  String failedToLoadTask(Object error) {
    return 'Failed to load task: $error';
  }

  @override
  String get noFocusIntervals => 'No focus intervals yet.';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get clearDate => 'Clear date';

  @override
  String priority(int priority) {
    return 'Priority $priority';
  }

  @override
  String get focusTitle => 'Focus';

  @override
  String focusLoadError(Object error) {
    return 'Could not load focus: $error';
  }

  @override
  String get focusViewFull => 'Full';

  @override
  String get focusViewMinimal => 'Minimal';

  @override
  String get noActiveSession => 'No active session';

  @override
  String get focusIdleSubtitle =>
      'Start a standalone focus interval or launch focus from a task.';

  @override
  String get noPreset => 'No preset';

  @override
  String get preparingFocus => 'Preparing focus';

  @override
  String get moreFocusOptions => 'More focus options';

  @override
  String get moreFocusActions => 'More focus actions';

  @override
  String get preset => 'Preset';

  @override
  String get newPreset => 'New preset';

  @override
  String get customize => 'Customize';

  @override
  String get customizePreset => 'Customize preset';

  @override
  String get startInterval => 'Start interval';

  @override
  String get intervalStarted => 'Interval started';

  @override
  String get intervalCompleted => 'Interval completed';

  @override
  String get focusStopped => 'Focus stopped';

  @override
  String get completeInterval => 'Complete interval';

  @override
  String get logDistraction => 'Log distraction';

  @override
  String get workInterval => 'Work interval';

  @override
  String get work => 'Work';

  @override
  String get shortBreak => 'Short break';

  @override
  String get breakLabel => 'Break';

  @override
  String get longBreak => 'Long break';

  @override
  String readyLabel(String label) {
    return 'Ready: $label';
  }

  @override
  String get readyShort => 'Ready';

  @override
  String focusTimerTotal(String duration) {
    return 'of $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Session $current of $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Focus rhythm preview, $count steps';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Focus rhythm, step $current of $total: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, $remaining remaining, $total total';
  }

  @override
  String get focusStatusRunning => 'Running';

  @override
  String get focusStatusPaused => 'Paused';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total work';
  }

  @override
  String intervalNumber(int number) {
    return 'Interval $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total work - Interval $number';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get presetForNextIntervals => 'Preset for next intervals';

  @override
  String usePreset(String name) {
    return 'Use $name';
  }

  @override
  String minutesWork(int minutes) {
    return '${minutes}m work';
  }

  @override
  String minutesShort(int minutes) {
    return '${minutes}m short';
  }

  @override
  String minutesLong(int minutes) {
    return '${minutes}m long';
  }

  @override
  String longEvery(int count) {
    return 'Long every $count';
  }

  @override
  String get autoBreaks => 'Auto breaks';

  @override
  String get autoWork => 'Auto work';

  @override
  String get noPause => 'No pause';

  @override
  String get focusPauseUnavailable => 'Pause unavailable for this preset';

  @override
  String get strict => 'Strict';

  @override
  String get flexible => 'Flexible';

  @override
  String get name => 'Name';

  @override
  String get workField => 'Work';

  @override
  String get shortField => 'Short';

  @override
  String get longField => 'Long';

  @override
  String get every => 'Every';

  @override
  String get minutesSuffix => 'min';

  @override
  String get makeDefault => 'Make default';

  @override
  String get autoStartBreaks => 'Auto-start breaks';

  @override
  String get autoStartWork => 'Auto-start work';

  @override
  String get allowPause => 'Allow pause';

  @override
  String get strictMode => 'Strict mode';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get nameMustBeUnique => 'Name must be unique';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'Two-way sync is active for the Pomodoist calendar.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Connect a Google account to sync scheduled tasks.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'Google Calendar sync is running on another device. Pomodoist data still syncs here.';

  @override
  String get syncNow => 'Sync now';

  @override
  String get useThisDevice => 'Use this device';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String failedToLoadIntegration(Object error) {
    return 'Failed to load integration: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Calendar failed: $message';
  }

  @override
  String get googleAuthRequired =>
      'Google Calendar authorization is required. Sign in again and run Sync now.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_REVERSED_CLIENT_ID for this iOS target.';

  @override
  String get googleCallbackNotConfigured =>
      'Google Sign-In callback is not configured. Set GOOGLE_REVERSED_CLIENT_ID in ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'On web, click the Google sign-in button first, then Connect.';

  @override
  String get googleAccessDenied =>
      'Google access is denied. Add this Google account as an OAuth test user, or publish and verify the OAuth app.';

  @override
  String get status => 'Status';

  @override
  String get account => 'Account';

  @override
  String get calendar => 'Calendar';

  @override
  String get calendarId => 'Calendar ID';

  @override
  String get lastSync => 'Last sync';

  @override
  String get notConnected => 'Not connected';

  @override
  String get notCreated => 'Not created';

  @override
  String get never => 'Never';

  @override
  String durationMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get projectColor => 'Project color';

  @override
  String projectColorOption(int number) {
    return 'Color $number';
  }

  @override
  String get addProjectToFavorites => 'Add project to favorites';

  @override
  String get removeProjectFromFavorites => 'Remove project from favorites';

  @override
  String get timelineProjectsMenu => 'Manage Timeline projects';

  @override
  String get timelineShowProject => 'Show project in Timeline';

  @override
  String get timelineHideProject => 'Hide temporary project';

  @override
  String get timelineCollapseProject => 'Collapse project branch';

  @override
  String get timelineExpandProject => 'Expand project branch';

  @override
  String get timelineCurrentTime => 'Current time';

  @override
  String couldNotUpdateProject(Object error) {
    return 'Could not update project: $error';
  }
}

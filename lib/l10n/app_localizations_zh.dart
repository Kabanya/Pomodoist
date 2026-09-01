// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => '添加';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonOpen => '打开';

  @override
  String get commonBack => '返回';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCreate => '创建';

  @override
  String get commonClear => '清除';

  @override
  String get commonStop => '停止';

  @override
  String get skip => '跳过';

  @override
  String get onboardingLanguageTitle => '选择语言';

  @override
  String get onboardingLanguageSubtitle => '选择 Pomodoist 要使用的语言。';

  @override
  String get onboardingTimerTitle => '选择计时器样式';

  @override
  String get onboardingTimerSubtitle => '选择专注会话中的番茄钟进度视图。';

  @override
  String get onboardingPaywallTitle => '解锁 Pomodoist';

  @override
  String get onboardingPaywallSubtitle => '终身优惠每周开放 24 小时。';

  @override
  String get onboardingAccountTitle => '创建账户';

  @override
  String get onboardingAccountSubtitle => '登录后可在设备间同步任务、专注历史和设置。';

  @override
  String get startupPreparingTasks => '正在准备你的任务';

  @override
  String get operationTakingLonger => '此操作耗时比平时更长，但仍在进行中。';

  @override
  String get onboardingContinue => '继续';

  @override
  String get onboardingMaybeLater => '稍后再说';

  @override
  String get onboardingFinish => '完成';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle => '用自然语言口述任务，Pomodoist 会把你的语音变成任务。任务历史会永久保存。';

  @override
  String get billingSubtitleHighlight => '自然语言';

  @override
  String get billingCancelAnytime => '可随时取消。';

  @override
  String get billingMonthlyTitle => '月度';

  @override
  String get billingAnnualTitle => '年度';

  @override
  String billingPricePerMonth(String price) {
    return '$price/月';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/年';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return '前 3 个月，之后为 $price。';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return '之后为 $price。';
  }

  @override
  String get billingLifetimeTitle => '终身';

  @override
  String get billingLifetimeSubtitle => '一次付费，永久使用。';

  @override
  String get billingBestValue => '最划算';

  @override
  String get billingChoose => '选择';

  @override
  String get billingActive => 'Pomodoist Pro 已在此设备上激活。';

  @override
  String get billingActiveShort => '已激活';

  @override
  String get billingRestore => '恢复购买';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get termsOfUse => '使用条款';

  @override
  String get support => '支持';

  @override
  String get billingManageLink => '通过 Link 管理';

  @override
  String get billingExternalBrowserTitle => '付款将在浏览器中打开';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist 将在 Safari 或默认浏览器中打开 Stripe Checkout。请允许打开浏览器窗口以继续。';

  @override
  String get billingAppleOnly => '可在 iPhone、iPad 和 Mac 上购买。';

  @override
  String get billingStoreUnavailable => 'App Store 当前不可用。';

  @override
  String billingPurchaseError(String error) {
    return '购买错误：$error';
  }

  @override
  String get billingStripeAuthenticationRequired => '请登录 Pomodoist 后重试。';

  @override
  String get billingStripeDisabled => '付款功能尚未开放。请稍后重试。';

  @override
  String get billingStripeAlreadyEntitled => 'Pomodoist Pro 已激活。请刷新帐户状态。';

  @override
  String get billingStripeOfferExpired => '此优惠已过期。请选择其他可用方案。';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'Stripe 付款暂时不可用。请稍后重试或联系支持。';

  @override
  String get billingStripeCheckoutFailed => '无法开始付款。请检查网络连接后重试。';

  @override
  String get purchaseSuccessTitle => 'Pro 已激活';

  @override
  String get purchaseSuccessMessage => '感谢支持 Pomodoist。所有 Pro 功能现在都可以使用。';

  @override
  String get purchaseSuccessContinue => '继续';

  @override
  String get purchaseProcessingTitle => '付款处理中';

  @override
  String get purchaseProcessingMessage => '正在确认付款。如果 Pro 未很快出现，请稍后再次刷新。';

  @override
  String get purchaseOpenApp => '打开 Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return '$time 后终身优惠结束';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => '邮箱';

  @override
  String get loginTitle => '登录 Pomodoist';

  @override
  String get accountChecking => '正在检查你的账户';

  @override
  String get oauthConsentTitle => '连接智能体';

  @override
  String get oauthConsentLoading => '正在检查连接请求';

  @override
  String get oauthConsentInvalidAuthorization => '此连接请求缺失或无效。';

  @override
  String get oauthConsentLoadError => '无法加载连接请求。';

  @override
  String get oauthConsentActionError => '无法完成请求，请重试。';

  @override
  String get oauthConsentRedirectError => 'Pomodoist 收到了不安全或缺失的返回地址，未移交访问权限。';

  @override
  String get oauthConsentClientFallback => '智能体';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName 想要访问 Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => '返回地址';

  @override
  String get oauthConsentCapabilitiesTitle => '此智能体可以';

  @override
  String get oauthConsentManagePlanning => '读取和管理任务、项目、自定义标签与看板。';

  @override
  String get oauthConsentReadInsights => '读取已完成的专注历史、效率报告与成就。';

  @override
  String get oauthConsentUnavailableTitle => '此智能体不能';

  @override
  String get oauthConsentUnavailable => '访问你的账户或账单、Google 日历或正在运行的专注计时器。';

  @override
  String get oauthConsentUnsupportedScopes => '此请求要求不支持的账户访问权限，无法批准。';

  @override
  String get oauthConsentApprove => '允许';

  @override
  String get oauthConsentDeny => '拒绝';

  @override
  String get oauthConsentApproving => '正在允许访问…';

  @override
  String get oauthConsentDenying => '正在拒绝请求…';

  @override
  String get oauthConsentRedirecting => '正在返回智能体…';

  @override
  String get loginCreateAccountPrompt => '还没有账户？';

  @override
  String get loginCreateAccountAction => '创建账户';

  @override
  String get registerTitle => '创建账户';

  @override
  String get registerSubtitle => '在设备间同步任务、专注历史和设置。';

  @override
  String get registerPassword => '密码';

  @override
  String get registerSubmit => '创建账户';

  @override
  String get registerSignInPrompt => '已有账户？';

  @override
  String get registerSignInAction => '登录';

  @override
  String get registerCheckEmailTitle => '查看你的邮箱';

  @override
  String get registerCheckEmailMessage => '打开确认链接以完成账户创建。';

  @override
  String registerError(Object error) {
    return '无法创建账户：$error';
  }

  @override
  String get authEmailSignInTitle => '使用邮箱登录';

  @override
  String get authSignInAction => '登录';

  @override
  String get authSendLink => '发送链接';

  @override
  String get authMagicLinkSent => '登录链接已发送。请检查收件箱和垃圾邮件文件夹。';

  @override
  String get authAccountCreated => '账户已创建。';

  @override
  String get authSignedIn => '已登录。';

  @override
  String get authEmailRequired => '请输入邮箱。';

  @override
  String get authEmailInvalid => '请检查邮箱地址，例如 name@example.com。';

  @override
  String get authPasswordRequired => '请输入密码。';

  @override
  String get authInvalidCredentials => '邮箱或密码不正确。请检查后重试。';

  @override
  String get authEmailUnconfirmed => '请使用我们发送的链接确认邮箱，然后重新登录。';

  @override
  String get authWeakPassword => '此密码太容易被猜到。请使用更长、更难预测的密码。';

  @override
  String get authAccountMayExist => '无法创建账户。如果你曾用此邮箱注册，请改为登录。';

  @override
  String get authRateLimited => '尝试次数过多。请等待几分钟后重试。';

  @override
  String get authEmailRateLimited => '请求邮件次数过多。请等待几分钟后再请求。';

  @override
  String get authOffline => '无法连接账户服务。请检查网络连接后重试。';

  @override
  String get authTimeout => '账户服务响应时间过长。请重试。';

  @override
  String get authServiceUnavailable => '账户服务暂时不可用。请稍后重试。';

  @override
  String get authCaptchaRequired => '请完成安全验证以继续。';

  @override
  String get authCaptchaExpired => '安全验证已过期。请重新完成验证。';

  @override
  String get authCaptchaFailed => '安全验证失败。请重新验证。';

  @override
  String get authCaptchaCancelled => '安全验证已取消。请重新开始以继续。';

  @override
  String get authCaptchaUnavailable => '安全验证暂时不可用。请检查网络后重试。';

  @override
  String get authCaptchaOpenFailed => 'Pomodoist 无法在浏览器中打开安全验证。请检查默认浏览器后重试。';

  @override
  String get authProviderFallback => '此服务商';

  @override
  String authProviderUnavailable(String provider) {
    return '暂时无法使用 $provider 登录。请重试或使用其他方式。';
  }

  @override
  String get authSignUpDisabled => '暂时无法使用邮箱创建账户。请使用其他登录方式。';

  @override
  String get authAccountRestricted => '此账户目前无法登录。如果你认为这是错误，请联系支持。';

  @override
  String get authLinkExpired => '此登录链接无效或已过期。请申请新链接。';

  @override
  String get authUnexpectedSignIn => '无法登录。请重试。';

  @override
  String get authUnexpectedSignUp => '无法创建账户。请重试。';

  @override
  String get authUnexpectedMagicLink => '无法发送登录链接。请重试。';

  @override
  String get authRetryVerification => '重新验证';

  @override
  String get captchaSecurityLabel => '安全验证';

  @override
  String get captchaChallengeTitle => 'Pomodoist 安全验证';

  @override
  String get captchaChallengePrompt => '请确认你是真人，以继续使用 Pomodoist。';

  @override
  String get captchaChallengeInvalid => '此安全验证链接无效。请返回 Pomodoist 后重试。';

  @override
  String get captchaChallengeHandoffHelp =>
      '如果 Pomodoist 未打开，请使用下方按钮。如果尚未安装应用，请关闭此页面并返回开始操作的设备。';

  @override
  String get captchaReturnToApp => '返回 Pomodoist';

  @override
  String get navSearch => '搜索';

  @override
  String get navInbox => '收件箱';

  @override
  String get navPriorityMatrix => '优先级矩阵';

  @override
  String get navTimeline => '时间线';

  @override
  String get navKanban => '看板';

  @override
  String get kanbanTitle => '看板';

  @override
  String get kanbanSubtitle => '可视化工作流程，专注当下最重要的事情。';

  @override
  String get kanbanDefaultBacklog => '待整理';

  @override
  String get kanbanDefaultTodo => '待办';

  @override
  String get kanbanDefaultInProgress => '进行中';

  @override
  String get kanbanDefaultDone => '已完成';

  @override
  String get kanbanSearchTooltip => '搜索看板';

  @override
  String get kanbanSearchHint => '搜索任务或项目';

  @override
  String get kanbanHideDone => '隐藏已完成';

  @override
  String get kanbanShowDone => '显示已完成';

  @override
  String get kanbanProjectsTitle => '此看板中的项目';

  @override
  String kanbanAddToStatus(String status) {
    return '添加到$status';
  }

  @override
  String get kanbanTaskField => '任务';

  @override
  String get kanbanProjectField => '项目';

  @override
  String get kanbanChooseProject => '请选择项目。';

  @override
  String get kanbanTaskActions => '任务操作';

  @override
  String get kanbanDragTask => '拖动任务';

  @override
  String kanbanMoveTo(String status) {
    return '移动到$status';
  }

  @override
  String get kanbanRestoreBeforeFocus => '开始专注前请先恢复任务。';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return '无法开始专注：$error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return '无法加载看板：$error';
  }

  @override
  String get commonRetry => '重试';

  @override
  String get commonContinueWaiting => '继续等待';

  @override
  String kanbanTasksCount(int count) {
    return '$count 个任务';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '子任务 $completed/$total';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '专注时段 $completed/$total';
  }

  @override
  String get kanbanActive => '进行中';

  @override
  String kanbanPriority(int priority) {
    return '优先级 $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return '已移动到$status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return '已为$task开始专注';
  }

  @override
  String get kanbanNoTasks => '暂无任务';

  @override
  String get navToday => '今天';

  @override
  String get navUpcoming => '即将到来';

  @override
  String get navBrowse => '浏览';

  @override
  String get navIntegrations => '集成';

  @override
  String get navReports => '报告';

  @override
  String get navFocus => '专注';

  @override
  String get navProjects => '项目';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAboutTitle => '关于';

  @override
  String get settingsFocusCompletionCelebrationTitle => '专注完成庆祝';

  @override
  String get settingsFocusCompletionCelebrationSubtitle => '在最后一次休息后显示全屏庆祝画面。';

  @override
  String get settingsVersionLabel => '版本';

  @override
  String get settingsPlanLabel => '方案';

  @override
  String get settingsPlanFree => '免费';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => '键盘快捷键';

  @override
  String get settingsShortcutsSubtitle => '自定义实体键盘可用的命令。';

  @override
  String get settingsShortcutsToggleSidebar => '显示或隐藏侧边栏';

  @override
  String get settingsShortcutsGlobalQuickAdd => '全局快速添加';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle => '即使 Pomodoist 未激活也可使用。';

  @override
  String get settingsShortcutsRecordTitle => '按下快捷键';

  @override
  String get settingsShortcutsRecordPrompt =>
      '请将按键与 Command、Control 或 Alt 组合使用。按 Esc 取消。';

  @override
  String get settingsShortcutsInvalid => '请加入 Command、Control 或 Alt。';

  @override
  String get settingsShortcutsConflict => '此快捷键已被使用。';

  @override
  String get settingsShortcutsGlobalError => '该全局快捷键不可用。先前的快捷键仍然有效。';

  @override
  String get settingsShortcutsResetAll => '全部重置';

  @override
  String get settingsShortcutsResetDone => '键盘快捷键已重置。';

  @override
  String get csvImportTitle => '从 CSV 导入任务';

  @override
  String get csvImportSubtitle => '创建任务、项目、标签和状态前先检查 CSV 文件。';

  @override
  String get csvImportSelectFile => '选择 CSV 文件';

  @override
  String get csvImportHumanGuideButton => '用户说明';

  @override
  String get csvImportAgentGuideButton => '智能体说明';

  @override
  String get csvImportHumanGuideTitle => '如何准备 CSV 文件';

  @override
  String get csvImportAgentGuideTitle => '智能体 CSV 规范';

  @override
  String get csvImportCopy => '复制';

  @override
  String get csvImportCopied => '已复制到剪贴板。';

  @override
  String get csvImportPreviewTitle => '检查导入内容';

  @override
  String get csvImportPreviewTasks => '任务';

  @override
  String get csvImportPreviewSubtasks => '子任务';

  @override
  String get csvImportPreviewNewProjects => '新项目';

  @override
  String get csvImportPreviewNewLabels => '新标签';

  @override
  String get csvImportPreviewNewStatuses => '新状态';

  @override
  String get csvImportNone => '无';

  @override
  String get csvImportDuplicateWarning => '再次导入同一文件会创建重复任务。';

  @override
  String get csvImportConfirm => '导入';

  @override
  String get csvImportSuccess => '已导入任务';

  @override
  String get csvImportErrorTitle => 'CSV 导入失败';

  @override
  String get csvImportUnexpectedError => '无法导入该文件。';

  @override
  String get csvImportHumanGuide =>
      '1. 将文件保存为 UTF-8 编码的 CSV。使用逗号（推荐）或分号作为分隔符。\n\n2. content 列为必填。还可使用：key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key。\n\n3. 每行创建一个未完成任务。多个标签用 | 分隔。优先级为 1–4，空值表示 4。项目为空表示 Inbox，状态为空表示 Backlog。缺少的项目、标签和未完成状态会自动创建。\n\n4. 全天任务使用 YYYY-MM-DD 格式的 due_date。定时任务需填写带 UTC 偏移的 RFC3339 格式 start_at 和 end_at，并提供 IANA time_zone，例如 Asia/Shanghai。\n\n5. 创建子任务时，为父行设置唯一 key，并在子行的 parent_key 中填写该值。父行可以出现在文件后面。子任务必须与父任务使用同一项目。\n\n6. Pomodoist 会验证整个文件并在导入前显示预览。只要有一行无效，就不会保存任何内容。再次导入会创建重复任务。';

  @override
  String get settingsConnectedAgentsTitle => '已连接的智能体';

  @override
  String get settingsConnectedAgentsLoading => '正在加载已连接的智能体…';

  @override
  String get settingsConnectedAgentsEmpty => '尚未连接智能体。';

  @override
  String get settingsConnectedAgentsLoadError => '无法加载已连接的智能体。';

  @override
  String get settingsConnectedAgentsUnknownClient => '智能体';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return '连接日期：$date';
  }

  @override
  String get settingsConnectedAgentsRevoke => '撤销访问权限';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle => '撤销智能体访问权限？';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return '撤销 $clientName 对 Pomodoist 的访问权限？';
  }

  @override
  String get settingsConnectedAgentsRevokeError => '无法撤销访问权限，请重试。';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageSubtitle => '选择应用语言。';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsThemeSubtitle => '选择应用外观。';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsTimerVisualTitle => '番茄钟计时器';

  @override
  String get settingsTimerVisualSubtitle => '选择专注屏幕上的进度显示方式。';

  @override
  String get settingsTimerVisualBar => '进度条';

  @override
  String get settingsTimerVisualCircle => '圆环';

  @override
  String get settingsReturnRemindersTitle => '回归提醒';

  @override
  String get settingsReturnRemindersSubtitle => '如果今天没有完成专注或任务，晚上给你一个轻提醒。';

  @override
  String get settingsDefaultTimedBlockTitle => '默认日历块时长';

  @override
  String get settingsDefaultTimedBlockSubtitle => '只输入时间时，新任务会使用这个日历时长。';

  @override
  String get settingsDefaultTimedBlockCustomLabel => '自定义时长';

  @override
  String get settingsDefaultTimedBlockError => '请输入 1 到 480 分钟。';

  @override
  String get settingsTaskTimeDisplayTitle => '任务时间显示';

  @override
  String get settingsTaskTimeDisplaySubtitle => '选择如何显示有时间安排的任务。';

  @override
  String get settingsTaskTimeDisplaySmart => '智能';

  @override
  String get settingsTaskTimeDisplayRange => '开始和结束时间';

  @override
  String get settingsTaskTimeDisplayStartOnly => '仅开始时间';

  @override
  String get taskTimeStatusFuture => '即将开始';

  @override
  String get taskTimeStatusFocused => '正在专注';

  @override
  String get taskTimeStatusCurrent => '进行中';

  @override
  String get taskTimeStatusOverdue => '已逾期';

  @override
  String get taskTimeStatusCompleted => '已完成';

  @override
  String get menuTooltip => '菜单';

  @override
  String get localUser => '本地用户';

  @override
  String get addTask => '添加任务';

  @override
  String get quickAddHint => '写 sync engine 明天 p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return '无法添加任务：$error';
  }

  @override
  String get taskCreateFailed => '无法创建任务。请重试。';

  @override
  String couldNotAddProject(Object error) {
    return '无法添加项目：$error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已添加 $count 个任务',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => '语音快速添加';

  @override
  String get voiceTitle => '语音添加';

  @override
  String get voiceRecord => '录制';

  @override
  String get voiceAgain => '重来';

  @override
  String get voiceStop => '停止';

  @override
  String voiceAddCount(int count) {
    return '添加 $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return '任务 $index';
  }

  @override
  String get voiceRemoveTask => '移除';

  @override
  String get voiceInstruction => '点击录制并说出任务。';

  @override
  String get voiceStatusIdle => '仅使用内置麦克风输入';

  @override
  String get voiceStatusRequestingPermission => '正在请求访问权限';

  @override
  String get voiceStatusRecording => '正在监听内置麦克风';

  @override
  String get voiceStatusTranscribing => '正在转写录音';

  @override
  String get voiceStatusCanceled => '录制已取消';

  @override
  String get voiceStatusUnsupported => '平台不受支持';

  @override
  String get voiceStatusError => '无法识别语音';

  @override
  String get voiceStatusAnalyzing => '正在拆分为任务';

  @override
  String get voiceStatusReview => '添加前请检查任务';

  @override
  String get voiceStepRecord => '录音';

  @override
  String get voiceStepText => '文本';

  @override
  String get voiceStepAnalyze => '分析';

  @override
  String get voiceStepReview => '检查';

  @override
  String get voiceAnalyzing => 'Pomodoist 正在将语音拆分为任务';

  @override
  String get voiceFallbackError => 'Pomodoist 无法处理语音，已保留草稿供手动编辑。';

  @override
  String get voiceMicrophoneUnavailable => '麦克风当前不可用。请结束正在进行的通话或语音聊天，然后重试。';

  @override
  String get voiceSmartMode => '智能模式';

  @override
  String get voiceRetryAnalysis => '重试分析';

  @override
  String get screenInboxSubtitle => '先收集任务，再进行整理。';

  @override
  String get priorityMatrixSubtitle => '在优先级之间拖动任务。日期只用于排序同一优先级内的任务。';

  @override
  String get priorityMatrixP1Title => '立即处理';

  @override
  String get priorityMatrixP2Title => '安排计划';

  @override
  String get priorityMatrixP3Title => '委派';

  @override
  String get priorityMatrixP4Title => '移除';

  @override
  String get priorityMatrixAxisUrgent => '紧急';

  @override
  String get priorityMatrixAxisNotUrgent => '不紧急';

  @override
  String get priorityMatrixAxisImportant => '重要';

  @override
  String get priorityMatrixAxisNotImportant => '不重要';

  @override
  String get timelineSubtitle => '在时间网格上规划一天。';

  @override
  String get timelineAllDay => '全天';

  @override
  String get timelineBeforeHours => '可见时间前';

  @override
  String get timelineAfterHours => '可见时间后';

  @override
  String get timelineVisibleHours => '可见时间';

  @override
  String get timelineStartHour => '开始';

  @override
  String get timelineEndHour => '结束';

  @override
  String get timelineZoomOut => '缩小';

  @override
  String get timelineZoomIn => '放大';

  @override
  String timelineAddTimedHint(String time) {
    return '$time 的任务';
  }

  @override
  String get timelineAddAllDayHint => '全天任务';

  @override
  String get timelineNoAllDayTasks => '没有全天任务';

  @override
  String get timelineNoTimedTasks => '没有定时任务';

  @override
  String get timelinePreviousDay => '前一天';

  @override
  String get timelineNextDay => '后一天';

  @override
  String get timelinePickDate => '选择日期';

  @override
  String get upcomingPreviousPeriod => '上一时段';

  @override
  String get upcomingNextPeriod => '下一时段';

  @override
  String get upcomingOpenDatePicker => '打开日期选择器';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务',
      one: '1 个任务',
      zero: '没有任务',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return '专注负载：$planned 个间隔 - 已完成：$completed - 专注：$focus';
  }

  @override
  String get screenUpcomingSubtitle => '今天之后计划的任务。';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return '$date 的任务。';
  }

  @override
  String get noTasksHere => '这里没有任务';

  @override
  String get noUpcomingTasks => '没有带日期的任务';

  @override
  String get noTasksForDay => '这一天没有计划任务';

  @override
  String failedToLoadTasks(Object error) {
    return '无法加载任务：$error';
  }

  @override
  String get searchTasks => '搜索任务';

  @override
  String get searchStartTyping => '开始输入以搜索任务';

  @override
  String get searchNoMatches => '没有匹配的任务';

  @override
  String failedToSearchTasks(Object error) {
    return '无法搜索任务：$error';
  }

  @override
  String get previousMonth => '上个月';

  @override
  String get nextMonth => '下个月';

  @override
  String get clearDateFilter => '清除日期筛选';

  @override
  String get weekMon => '一';

  @override
  String get weekTue => '二';

  @override
  String get weekWed => '三';

  @override
  String get weekThu => '四';

  @override
  String get weekFri => '五';

  @override
  String get weekSat => '六';

  @override
  String get weekSun => '日';

  @override
  String get browseTitle => '浏览';

  @override
  String get unifiedAccount => '统一账户';

  @override
  String accountUnavailable(Object error) {
    return '账户不可用：$error';
  }

  @override
  String get signOut => '退出登录';

  @override
  String get deleteAccount => '删除账户';

  @override
  String get deleteAccountConfirmation =>
      '这将永久删除您的账户、云端数据，以及本地任务、项目和专注历史记录。此操作无法撤销。应用商店订阅不会自动取消。如果您使用了“通过 Apple 登录”，还需在 Apple 账户设置中单独撤销 Pomodoist 的访问权限。';

  @override
  String get manageSignInWithApple => '管理通过 Apple 登录';

  @override
  String get deleteAccountFinalConfirmation => '您确定要继续吗？这是最后一次确认。';

  @override
  String deleteAccountError(Object error) {
    return '无法删除账户：$error';
  }

  @override
  String get accountDeleted => '账户已删除。';

  @override
  String get accountDeletedLocalCleanupError =>
      '您的账户已删除，但无法清除本地数据。再次使用此设备前，请先清除应用数据。';

  @override
  String get productivityTitle => '生产力';

  @override
  String get achievementsTitle => '成就';

  @override
  String get allTimeLabel => '全部时间';

  @override
  String get lastSevenDaysLabel => '最近 7 天';

  @override
  String get noWeeklyStatsLabel => '暂无专注或任务数据';

  @override
  String get completedFocuses => '已完成专注';

  @override
  String get completedTasks => '已完成任务';

  @override
  String get unlocked => '已解锁';

  @override
  String get locked => '未解锁';

  @override
  String get progressLabel => '进度';

  @override
  String get focusAchievements => '专注成就';

  @override
  String get taskAchievements => '任务成就';

  @override
  String get comboAchievements => '组合成就';

  @override
  String get focusIntervals => '专注间隔';

  @override
  String get focusTime => '专注时间';

  @override
  String get openTasks => '未完成任务';

  @override
  String get plannedIntervals => '计划间隔';

  @override
  String get labelsTitle => '标签';

  @override
  String get newProject => '新项目';

  @override
  String get newLabel => '新标签';

  @override
  String get syncReadyQueue => '待同步队列';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个本地命令待处理',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return '无法加载项目：$error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return '无法加载标签：$error';
  }

  @override
  String get addProject => '添加项目';

  @override
  String get projectName => '项目名称';

  @override
  String get addLabel => '添加标签';

  @override
  String get labelName => '标签名称';

  @override
  String couldNotAddLabel(Object error) {
    return '无法添加标签：$error';
  }

  @override
  String projectsUnavailable(Object error) {
    return '项目不可用：$error';
  }

  @override
  String get projectsUnavailableShort => '项目不可用';

  @override
  String get noProjects => '没有项目';

  @override
  String get searchProjects => '搜索项目';

  @override
  String get searchLabels => '搜索标签';

  @override
  String get archivedProjectsOnly => '仅归档项目';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个项目',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => '没有标签';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个标签',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => '重命名项目';

  @override
  String get deleteProject => '删除项目';

  @override
  String get deleteLabel => '删除标签';

  @override
  String deleteProjectConfirmation(String name) {
    return '删除 \"$name\"？此项目中的任务将移至 Inbox。';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return '删除 \"$name\"？';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return '无法删除项目：$error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return '无法删除标签：$error';
  }

  @override
  String projectsCountCompact(int count) {
    return '项目：$count';
  }

  @override
  String get collapseProjects => '折叠项目';

  @override
  String get expandProjects => '展开项目';

  @override
  String get projectFallbackTitle => '项目';

  @override
  String get projectSubtitle => '列表视图 - 看板和日历在路线图中。';

  @override
  String get reportsTitle => '报告';

  @override
  String get reportsFocusedDay => '今天专注得不错';

  @override
  String get reportsThisWeek => '本周专注情况';

  @override
  String get reportsNextAchievement => '下一个成就';

  @override
  String get viewAllAchievements => '查看所有成就';

  @override
  String viewAllAchievementsCount(int count) {
    return '查看全部 $count 个';
  }

  @override
  String get allAchievementsUnlocked => '所有成就均已解锁';

  @override
  String get noAchievementsYet => '暂无成就';

  @override
  String failedToLoadAchievements(Object error) {
    return '无法加载成就：$error';
  }

  @override
  String get backToReports => '返回报告';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '已完成 $completed/$target 个专注时段';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '已完成 $completed 个专注时段；未设目标';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return '过去 7 天的专注时间：$summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return '无法加载报告：$error';
  }

  @override
  String get taskNotFound => '未找到任务';

  @override
  String get taskTitleHint => '任务标题';

  @override
  String get taskComment => '评论';

  @override
  String get taskCommentHint => '添加评论';

  @override
  String get subtasks => '子任务';

  @override
  String get addSubtask => '添加子任务';

  @override
  String get addSubtaskHint => '添加子任务';

  @override
  String get noSubtasks => '还没有子任务。';

  @override
  String get makeParentTask => '设为父任务';

  @override
  String couldNotMoveTask(Object error) {
    return '无法移动任务：$error';
  }

  @override
  String get scheduleTitle => '日程';

  @override
  String get allDay => '全天';

  @override
  String get timedBlock => '时间块';

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
  String get noDate => '无日期';

  @override
  String get calendarNotLinked => '日历未关联';

  @override
  String get calendarLinked => 'Google Calendar 已关联';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total 专注';
  }

  @override
  String get startFocus => '开始专注';

  @override
  String get focusStarted => '已开始专注';

  @override
  String get taskReopened => '任务已重新打开';

  @override
  String get taskCompleted => '任务已完成';

  @override
  String get taskDeleted => '任务已删除';

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
  String get markOpen => '标记为未完成';

  @override
  String get markComplete => '标记为完成';

  @override
  String get focusHistory => '专注历史';

  @override
  String failedToLoadTask(Object error) {
    return '无法加载任务：$error';
  }

  @override
  String get noFocusIntervals => '还没有专注间隔。';

  @override
  String get today => '今天';

  @override
  String get tomorrow => '明天';

  @override
  String get yesterday => '昨天';

  @override
  String get clearDate => '清除日期';

  @override
  String priority(int priority) {
    return '优先级 $priority';
  }

  @override
  String get focusTitle => '专注';

  @override
  String focusLoadError(Object error) {
    return '无法加载专注：$error';
  }

  @override
  String get focusViewFull => '完整';

  @override
  String get focusViewMinimal => '极简';

  @override
  String get focusSwitchToFullView => '切换到完整模式';

  @override
  String get focusSwitchToMinimalView => '切换到极简模式';

  @override
  String get focusActionFailed => '无法更新专注。请重试。';

  @override
  String get noActiveSession => '没有活动会话';

  @override
  String get focusIdleSubtitle => '启动单独的专注间隔，或从任务启动专注。';

  @override
  String get noPreset => '无预设';

  @override
  String get preparingFocus => '正在准备专注';

  @override
  String get moreFocusOptions => '更多专注选项';

  @override
  String get moreFocusActions => '更多专注操作';

  @override
  String get preset => '预设';

  @override
  String get newPreset => '新预设';

  @override
  String get customize => '自定义';

  @override
  String get customizePreset => '自定义预设';

  @override
  String get startInterval => '开始间隔';

  @override
  String get intervalStarted => '间隔已开始';

  @override
  String get intervalCompleted => '间隔已完成';

  @override
  String get focusStopped => '专注已停止';

  @override
  String get focusCompletionTitle => '做得漂亮！';

  @override
  String get focusCompletionLinkedSubtitle => '此任务计划的所有专注时段均已完成。';

  @override
  String get focusCompletionStandaloneSubtitle => '你的专注周期已完成。';

  @override
  String get focusCompletionQuestion => '要完成此任务吗？';

  @override
  String get focusCompletionCompleteTask => '完成任务';

  @override
  String get focusCompletionKeepOpen => '保持任务未完成';

  @override
  String get focusCompletionDone => '完成';

  @override
  String get focusCompletionNextTask => '下一个计划任务';

  @override
  String focusCompletionTaskError(Object error) {
    return '无法完成任务：$error';
  }

  @override
  String get completeInterval => '完成间隔';

  @override
  String get logDistraction => '记录分心';

  @override
  String get workInterval => '工作间隔';

  @override
  String get work => '工作';

  @override
  String get shortBreak => '短休息';

  @override
  String get breakLabel => '休息';

  @override
  String get longBreak => '长休息';

  @override
  String readyLabel(String label) {
    return '就绪：$label';
  }

  @override
  String get readyShort => '就绪';

  @override
  String focusTimerTotal(String duration) {
    return '共 $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return '第 $current/$total 节';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return '专注节奏预览，共 $count 步';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return '专注节奏，第 $current/$total 步：$phase，$status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase，$status，剩余 $remaining，总计 $total';
  }

  @override
  String get focusStatusRunning => '进行中';

  @override
  String get focusStatusPaused => '已暂停';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total 工作';
  }

  @override
  String intervalNumber(int number) {
    return '间隔 $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total 工作 - 间隔 $number';
  }

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get presetForNextIntervals => '后续间隔的预设';

  @override
  String usePreset(String name) {
    return '使用 $name';
  }

  @override
  String minutesWork(int minutes) {
    return '$minutes 分钟工作';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutes 分钟短休息';
  }

  @override
  String minutesLong(int minutes) {
    return '$minutes 分钟长休息';
  }

  @override
  String longEvery(int count) {
    return '每 $count 次长休息';
  }

  @override
  String get autoBreaks => '自动休息';

  @override
  String get autoWork => '自动工作';

  @override
  String get noPause => '不可暂停';

  @override
  String get focusPauseUnavailable => '此预设不可暂停';

  @override
  String get strict => '严格';

  @override
  String get flexible => '灵活';

  @override
  String get name => '名称';

  @override
  String get workField => '工作';

  @override
  String get shortField => '短';

  @override
  String get longField => '长';

  @override
  String get every => '每';

  @override
  String get minutesSuffix => '分钟';

  @override
  String get makeDefault => '设为默认';

  @override
  String get autoStartBreaks => '自动开始休息';

  @override
  String get autoStartWork => '自动开始工作';

  @override
  String get allowPause => '允许暂停';

  @override
  String get strictMode => '严格模式';

  @override
  String get nameRequired => '名称必填';

  @override
  String get nameMustBeUnique => '名称必须唯一';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle => 'Pomodoist 日历的双向同步已启用。';

  @override
  String get googleCalendarDisconnectedSubtitle => '连接 Google 账户以同步计划任务。';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'Google 日历同步正在另一台设备上运行。Pomodoist 数据仍会在此同步。';

  @override
  String get syncNow => '立即同步';

  @override
  String get useThisDevice => '使用此设备';

  @override
  String get connect => '连接';

  @override
  String get disconnect => '断开连接';

  @override
  String failedToLoadIntegration(Object error) {
    return '无法加载集成：$error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Calendar 失败：$message';
  }

  @override
  String get googleAuthRequired => '需要 Google Calendar 授权。请重新登录并运行立即同步。';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In 未配置。请为此 iOS target 设置 GOOGLE_CLIENT_ID 和 GOOGLE_REVERSED_CLIENT_ID。';

  @override
  String get googleCallbackNotConfigured =>
      'Google Sign-In 回调未配置。请在 ios/Flutter/GoogleOAuth.xcconfig 中设置 GOOGLE_REVERSED_CLIENT_ID。';

  @override
  String get googleWebButtonFirst => '在 Web 上，请先点击 Google 登录按钮，然后点击连接。';

  @override
  String get googleAccessDenied =>
      'Google 访问被拒绝。请将此 Google 账户添加为 OAuth 测试用户，或发布并验证 OAuth 应用。';

  @override
  String get status => '状态';

  @override
  String get account => '账户';

  @override
  String get calendar => '日历';

  @override
  String get calendarId => '日历 ID';

  @override
  String get lastSync => '上次同步';

  @override
  String get notConnected => '未连接';

  @override
  String get notCreated => '未创建';

  @override
  String get never => '从不';

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String get projectColor => '项目颜色';

  @override
  String projectColorOption(int number) {
    return '颜色 $number';
  }

  @override
  String get addProjectToFavorites => '将项目添加到收藏';

  @override
  String get removeProjectFromFavorites => '从收藏中移除项目';

  @override
  String get timelineProjectsMenu => '管理时间轴项目';

  @override
  String get timelineShowProject => '在时间轴中显示项目';

  @override
  String get timelineHideProject => '隐藏临时项目';

  @override
  String get timelineCollapseProject => '折叠项目分支';

  @override
  String get timelineExpandProject => '展开项目分支';

  @override
  String get timelineCurrentTime => '当前时间';

  @override
  String couldNotUpdateProject(Object error) {
    return '无法更新项目：$error';
  }

  @override
  String get commonDone => '完成';

  @override
  String get taskSelect => '选择';

  @override
  String taskSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get taskSelectAll => '全选';

  @override
  String get taskDeselectAll => '取消全选';

  @override
  String get taskDue => '截止日期';

  @override
  String get taskProject => '项目';

  @override
  String get taskLabels => '标签';

  @override
  String get taskPriority => '优先级';

  @override
  String get taskMore => '更多';

  @override
  String get taskSchedule => '安排';

  @override
  String get taskMove => '移动';

  @override
  String get taskDuplicate => '复制';

  @override
  String get taskDuplicateTitle => '复制任务';

  @override
  String get taskDuplicateSelectedOnly => '仅所选任务';

  @override
  String get taskDuplicateWithSubtasks => '包含子任务';

  @override
  String get taskWeekend => '本周末';

  @override
  String get taskNextWeek => '下周';

  @override
  String get taskEnterDue => '输入截止日期或时间';

  @override
  String get taskInvalidDue => '请输入有效的日期或时间';

  @override
  String get taskClearDue => '清除截止日期';

  @override
  String get taskDeleteSelectedTitle => '删除所选任务？';

  @override
  String get taskDeleteSelectedMessage => '你可以在 7 秒内撤销此操作。';

  @override
  String get taskCompleteSelected => '完成所选任务';

  @override
  String get taskReopenSelected => '重新打开所选任务';

  @override
  String taskActionFailedCount(int count) {
    return '有 $count 项任务无法更新';
  }
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'إضافة';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonUndo => 'تراجع';

  @override
  String get commonOpen => 'فتح';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonCreate => 'إنشاء';

  @override
  String get commonClear => 'مسح';

  @override
  String get commonStop => 'إيقاف';

  @override
  String get skip => 'تخطي';

  @override
  String get onboardingLanguageTitle => 'اختر اللغة';

  @override
  String get onboardingLanguageSubtitle =>
      'اختر اللغة التي يجب أن يستخدمها Pomodoist.';

  @override
  String get onboardingTimerTitle => 'اختر نمط المؤقت';

  @override
  String get onboardingTimerSubtitle =>
      'اختر عرض تقدم بومودورو لجلسات التركيز.';

  @override
  String get onboardingPaywallTitle => 'افتح Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'يتوفر عرض مدى الحياة لمدة 24 ساعة كل أسبوع.';

  @override
  String get onboardingAccountTitle => 'أنشئ حسابا';

  @override
  String get onboardingAccountSubtitle =>
      'سجل الدخول لمزامنة المهام وسجل التركيز والإعدادات بين الأجهزة.';

  @override
  String get startupPreparingTasks => 'نجهز مهامك';

  @override
  String get operationTakingLonger =>
      'تستغرق العملية وقتًا أطول من المعتاد، لكنها لا تزال قيد التنفيذ.';

  @override
  String get onboardingContinue => 'متابعة';

  @override
  String get onboardingMaybeLater => 'ربما لاحقا';

  @override
  String get onboardingFinish => 'إنهاء';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'أملِ المهام بلغة طبيعية، وسيحوّل Pomodoist كلامك إلى مهام. يبقى سجل المهام محفوظا دائما.';

  @override
  String get billingSubtitleHighlight => 'بلغة طبيعية';

  @override
  String get billingCancelAnytime => 'يمكنك الإلغاء في أي وقت.';

  @override
  String get billingMonthlyTitle => 'شهريا';

  @override
  String get billingAnnualTitle => 'سنويا';

  @override
  String billingPricePerMonth(String price) {
    return '$price/شهر';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/سنة';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'أول 3 أشهر، ثم $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'ثم $price.';
  }

  @override
  String get billingLifetimeTitle => 'مدى الحياة';

  @override
  String get billingLifetimeSubtitle => 'دفعة واحدة إلى الأبد.';

  @override
  String get billingBestValue => 'أفضل قيمة';

  @override
  String get billingChoose => 'اختر';

  @override
  String get billingActive => 'Pomodoist Pro نشط على هذا الجهاز.';

  @override
  String get billingActiveShort => 'نشط';

  @override
  String get billingRestore => 'استعادة المشتريات';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get termsOfUse => 'شروط الاستخدام';

  @override
  String get support => 'الدعم';

  @override
  String get billingManageLink => 'الإدارة عبر Link';

  @override
  String get billingExternalBrowserTitle => 'سيُفتح الدفع في المتصفح';

  @override
  String get billingExternalBrowserMessage =>
      'سيفتح Pomodoist صفحة Stripe Checkout في Safari أو متصفحك الافتراضي. اسمح بفتح نافذة المتصفح للمتابعة.';

  @override
  String get billingAppleOnly => 'تتوفر المشتريات على iPhone و iPad و Mac.';

  @override
  String get billingStoreUnavailable => 'App Store غير متاح الآن.';

  @override
  String billingPurchaseError(String error) {
    return 'خطأ في الشراء: $error';
  }

  @override
  String get billingStripeAuthenticationRequired =>
      'سجّل الدخول إلى Pomodoist ثم حاول مرة أخرى.';

  @override
  String get billingStripeDisabled =>
      'المدفوعات غير متاحة بعد. حاول مرة أخرى لاحقًا.';

  @override
  String get billingStripeAlreadyEntitled =>
      'Pomodoist Pro مفعّل بالفعل. حدّث حالة حسابك.';

  @override
  String get billingStripeOfferExpired =>
      'انتهى هذا العرض. اختر خطة أخرى متاحة.';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'مدفوعات Stripe غير متاحة مؤقتًا. حاول لاحقًا أو تواصل مع الدعم.';

  @override
  String get billingStripeCheckoutFailed =>
      'تعذّر بدء الدفع. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.';

  @override
  String get purchaseSuccessTitle => 'Pro مفعل';

  @override
  String get purchaseSuccessMessage =>
      'شكرًا لدعم Pomodoist. جميع ميزات Pro متاحة الآن.';

  @override
  String get purchaseSuccessContinue => 'متابعة';

  @override
  String get purchaseProcessingTitle => 'تتم معالجة الدفع';

  @override
  String get purchaseProcessingMessage =>
      'جارٍ تأكيد الدفع. إذا لم يظهر Pro قريبًا، فحاول التحديث لاحقًا.';

  @override
  String get purchaseOpenApp => 'فتح Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return '$time متبقية حتى انتهاء عرض مدى الحياة';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'البريد الإلكتروني';

  @override
  String get loginTitle => 'سجّل الدخول إلى Pomodoist';

  @override
  String get accountChecking => 'جارٍ التحقق من حسابك';

  @override
  String get oauthConsentTitle => 'ربط وكيل';

  @override
  String get oauthConsentLoading => 'جارٍ التحقق من طلب الاتصال';

  @override
  String get oauthConsentInvalidAuthorization =>
      'طلب الاتصال هذا مفقود أو غير صالح.';

  @override
  String get oauthConsentLoadError => 'تعذر تحميل طلب الاتصال.';

  @override
  String get oauthConsentActionError => 'تعذر إكمال الطلب. حاول مرة أخرى.';

  @override
  String get oauthConsentRedirectError =>
      'تلقى Pomodoist عنوان عودة مفقودًا أو غير آمن. لم يتم تسليم الوصول.';

  @override
  String get oauthConsentClientFallback => 'وكيل';

  @override
  String oauthConsentClientRequest(String clientName) {
    return 'يريد $clientName الوصول إلى Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'عنوان العودة';

  @override
  String get oauthConsentCapabilitiesTitle => 'يمكن لهذا الوكيل';

  @override
  String get oauthConsentManagePlanning =>
      'قراءة وإدارة المهام والمشاريع والتسميات الشخصية وكانبان.';

  @override
  String get oauthConsentReadInsights =>
      'قراءة سجل التركيز المكتمل وتقارير الإنتاجية والإنجازات.';

  @override
  String get oauthConsentUnavailableTitle => 'لا يمكن لهذا الوكيل';

  @override
  String get oauthConsentUnavailable =>
      'الوصول إلى حسابك أو الفوترة أو تقويم Google أو مؤقت التركيز المباشر.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'يطلب هذا الطلب وصولًا غير مدعوم إلى الحساب ولا يمكن الموافقة عليه.';

  @override
  String get oauthConsentApprove => 'سماح';

  @override
  String get oauthConsentDeny => 'رفض';

  @override
  String get oauthConsentApproving => 'جارٍ السماح بالوصول…';

  @override
  String get oauthConsentDenying => 'جارٍ رفض الطلب…';

  @override
  String get oauthConsentRedirecting => 'جارٍ العودة إلى الوكيل…';

  @override
  String get loginCreateAccountPrompt => 'ليس لديك حساب؟';

  @override
  String get loginCreateAccountAction => 'إنشاء حساب';

  @override
  String get registerTitle => 'أنشئ حسابا';

  @override
  String get registerSubtitle =>
      'زامن المهام وسجل التركيز والإعدادات بين الأجهزة.';

  @override
  String get registerPassword => 'كلمة المرور';

  @override
  String get registerSubmit => 'إنشاء حساب';

  @override
  String get registerSignInPrompt => 'لديك حساب بالفعل؟';

  @override
  String get registerSignInAction => 'تسجيل الدخول';

  @override
  String get registerCheckEmailTitle => 'تحقق من بريدك الإلكتروني';

  @override
  String get registerCheckEmailMessage =>
      'افتح رابط التأكيد لإكمال إنشاء حسابك.';

  @override
  String registerError(Object error) {
    return 'تعذر إنشاء الحساب: $error';
  }

  @override
  String get authEmailSignInTitle => 'تسجيل الدخول بالبريد الإلكتروني';

  @override
  String get authSignInAction => 'تسجيل الدخول';

  @override
  String get authSendLink => 'إرسال الرابط';

  @override
  String get authMagicLinkSent =>
      'تم إرسال رابط تسجيل الدخول. تحقق من صندوق الوارد ومجلد الرسائل غير المرغوب فيها.';

  @override
  String get authAccountCreated => 'تم إنشاء الحساب.';

  @override
  String get authSignedIn => 'تم تسجيل الدخول.';

  @override
  String get authEmailRequired => 'أدخل بريدك الإلكتروني.';

  @override
  String get authEmailInvalid =>
      'تحقق من عنوان البريد الإلكتروني، مثل name@example.com.';

  @override
  String get authPasswordRequired => 'أدخل كلمة المرور.';

  @override
  String get authInvalidCredentials =>
      'البريد الإلكتروني أو كلمة المرور غير صحيحين. تحقّق منهما وحاول مجددًا.';

  @override
  String get authEmailUnconfirmed =>
      'أكد بريدك الإلكتروني عبر الرابط الذي أرسلناه، ثم سجّل الدخول مجددًا.';

  @override
  String get authWeakPassword =>
      'يسهل تخمين كلمة المرور هذه. استخدم كلمة مرور أطول وأقل قابلية للتوقع.';

  @override
  String get authAccountMayExist =>
      'تعذر إنشاء الحساب. إذا سبق أن سجلت بهذا البريد الإلكتروني، فسجّل الدخول بدلاً من ذلك.';

  @override
  String get authRateLimited =>
      'محاولات كثيرة جدًا. انتظر بضع دقائق وحاول مجددًا.';

  @override
  String get authEmailRateLimited =>
      'طُلبت رسائل كثيرة جدًا. انتظر بضع دقائق قبل طلب رسالة أخرى.';

  @override
  String get authOffline =>
      'تعذر الوصول إلى خدمة الحسابات. تحقق من اتصال الإنترنت وحاول مجددًا.';

  @override
  String get authTimeout =>
      'تستغرق خدمة الحسابات وقتًا طويلاً للرد. حاول مجددًا.';

  @override
  String get authServiceUnavailable =>
      'خدمة الحسابات غير متاحة مؤقتًا. حاول لاحقًا.';

  @override
  String get authCaptchaRequired => 'أكمل التحقق الأمني للمتابعة.';

  @override
  String get authCaptchaExpired => 'انتهت صلاحية التحقق الأمني. أكمله مجددًا.';

  @override
  String get authCaptchaFailed => 'فشل التحقق الأمني. حاول التحقق مجددًا.';

  @override
  String get authCaptchaCancelled =>
      'تم إلغاء التحقق الأمني. ابدأه مجددًا للمتابعة.';

  @override
  String get authCaptchaUnavailable =>
      'التحقق الأمني غير متاح الآن. تحقق من اتصالك وحاول مجددًا.';

  @override
  String get authCaptchaOpenFailed =>
      'تعذر على Pomodoist فتح التحقق الأمني في المتصفح. تحقق من المتصفح الافتراضي وحاول مجددًا.';

  @override
  String get authProviderFallback => 'مقدم الخدمة هذا';

  @override
  String authProviderUnavailable(String provider) {
    return 'تسجيل الدخول باستخدام $provider غير متاح الآن. حاول مجددًا أو استخدم طريقة أخرى.';
  }

  @override
  String get authSignUpDisabled =>
      'إنشاء الحساب بالبريد الإلكتروني غير متاح مؤقتًا. استخدم طريقة تسجيل دخول أخرى.';

  @override
  String get authAccountRestricted =>
      'لا يمكن تسجيل الدخول إلى هذا الحساب الآن. تواصل مع الدعم إذا كنت تعتقد أن هذا خطأ.';

  @override
  String get authLinkExpired =>
      'رابط تسجيل الدخول هذا غير صالح أو منتهي الصلاحية. اطلب رابطًا جديدًا.';

  @override
  String get authUnexpectedSignIn => 'تعذر تسجيل الدخول. حاول مجددًا.';

  @override
  String get authUnexpectedSignUp => 'تعذر إنشاء الحساب. حاول مجددًا.';

  @override
  String get authUnexpectedMagicLink =>
      'تعذر إرسال رابط تسجيل الدخول. حاول مجددًا.';

  @override
  String get authRetryVerification => 'إعادة محاولة التحقق';

  @override
  String get captchaSecurityLabel => 'التحقق الأمني';

  @override
  String get captchaChallengeTitle => 'تحقق أمان Pomodoist';

  @override
  String get captchaChallengePrompt => 'أكد أنك إنسان للمتابعة في Pomodoist.';

  @override
  String get captchaChallengeInvalid =>
      'رابط التحقق الأمني غير صالح. عُد إلى Pomodoist وحاول مجددًا.';

  @override
  String get captchaChallengeHandoffHelp =>
      'إذا لم يفتح Pomodoist، فاستخدم الزر أدناه. إذا لم يكن التطبيق مثبتًا، فأغلق هذه الصفحة وعُد إلى الجهاز الذي بدأت منه.';

  @override
  String get captchaReturnToApp => 'العودة إلى Pomodoist';

  @override
  String get navSearch => 'بحث';

  @override
  String get navInbox => 'الوارد';

  @override
  String get navPriorityMatrix => 'مصفوفة الأولويات';

  @override
  String get navTimeline => 'المخطط الزمني';

  @override
  String get navKanban => 'كانبان';

  @override
  String get kanbanTitle => 'كانبان';

  @override
  String get kanbanSubtitle => 'اعرض سير العمل وركّز على ما يهم الآن.';

  @override
  String get kanbanDefaultBacklog => 'المهام المؤجلة';

  @override
  String get kanbanDefaultTodo => 'للإنجاز';

  @override
  String get kanbanDefaultInProgress => 'قيد التنفيذ';

  @override
  String get kanbanDefaultDone => 'مكتمل';

  @override
  String get kanbanSearchTooltip => 'البحث في كانبان';

  @override
  String get kanbanSearchHint => 'ابحث عن مهام أو مشاريع';

  @override
  String get kanbanHideDone => 'إخفاء المكتمل';

  @override
  String get kanbanShowDone => 'إظهار المكتمل';

  @override
  String get kanbanProjectsTitle => 'مشاريع هذه اللوحة';

  @override
  String kanbanAddToStatus(String status) {
    return 'إضافة إلى $status';
  }

  @override
  String get kanbanTaskField => 'المهمة';

  @override
  String get kanbanProjectField => 'المشروع';

  @override
  String get kanbanChooseProject => 'اختر مشروعًا.';

  @override
  String get kanbanTaskActions => 'إجراءات المهمة';

  @override
  String get kanbanDragTask => 'سحب المهمة';

  @override
  String kanbanMoveTo(String status) {
    return 'نقل إلى $status';
  }

  @override
  String get kanbanRestoreBeforeFocus => 'استعد المهمة قبل بدء التركيز.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'تعذر بدء التركيز: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'تعذر تحميل كانبان: $error';
  }

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonContinueWaiting => 'متابعة الانتظار';

  @override
  String kanbanTasksCount(int count) {
    return 'المهام: $count';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return 'المهام الفرعية: $completed من $total';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return 'فترات التركيز: $completed من $total';
  }

  @override
  String get kanbanActive => 'نشط';

  @override
  String kanbanPriority(int priority) {
    return 'الأولوية $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'تم النقل إلى $status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'بدأ التركيز للمهمة $task';
  }

  @override
  String get kanbanNoTasks => 'لا توجد مهام بعد';

  @override
  String get navToday => 'اليوم';

  @override
  String get navUpcoming => 'القادمة';

  @override
  String get navBrowse => 'تصفح';

  @override
  String get navIntegrations => 'التكاملات';

  @override
  String get navReports => 'التقارير';

  @override
  String get navFocus => 'التركيز';

  @override
  String get navProjects => 'المشاريع';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsAboutTitle => 'حول التطبيق';

  @override
  String get settingsFocusCompletionCelebrationTitle => 'احتفال بإكمال التركيز';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      'عرض احتفال بملء الشاشة بعد الاستراحة الأخيرة.';

  @override
  String get settingsVersionLabel => 'الإصدار';

  @override
  String get settingsPlanLabel => 'الخطة';

  @override
  String get settingsPlanFree => 'مجاني';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'اختصارات لوحة المفاتيح';

  @override
  String get settingsShortcutsSubtitle =>
      'خصّص الأوامر المتاحة من لوحة مفاتيح فعلية.';

  @override
  String get settingsShortcutsToggleSidebar => 'إظهار الشريط الجانبي أو إخفاؤه';

  @override
  String get settingsShortcutsGlobalQuickAdd => 'إضافة سريعة عامة';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'يعمل حتى عندما لا يكون Pomodoist نشطًا.';

  @override
  String get settingsShortcutsRecordTitle => 'اضغط اختصارًا';

  @override
  String get settingsShortcutsRecordPrompt =>
      'استخدم مفتاحًا مع Command أو Control أو Alt. اضغط Esc للإلغاء.';

  @override
  String get settingsShortcutsInvalid => 'أضف Command أو Control أو Alt.';

  @override
  String get settingsShortcutsConflict => 'هذا الاختصار مستخدم بالفعل.';

  @override
  String get settingsShortcutsGlobalError =>
      'هذا الاختصار العام غير متاح. سيبقى الاختصار السابق نشطًا.';

  @override
  String get settingsShortcutsResetAll => 'إعادة ضبط الكل';

  @override
  String get settingsShortcutsResetDone =>
      'تمت إعادة ضبط اختصارات لوحة المفاتيح.';

  @override
  String get csvImportTitle => 'استيراد المهام من CSV';

  @override
  String get csvImportSubtitle =>
      'راجع ملف CSV قبل إنشاء المهام والمشاريع والتسميات والحالات.';

  @override
  String get csvImportSelectFile => 'اختيار ملف CSV';

  @override
  String get csvImportHumanGuideButton => 'دليل للأشخاص';

  @override
  String get csvImportAgentGuideButton => 'دليل للوكلاء';

  @override
  String get csvImportHumanGuideTitle => 'كيفية إعداد ملف CSV';

  @override
  String get csvImportAgentGuideTitle => 'عقد CSV للوكيل';

  @override
  String get csvImportCopy => 'نسخ';

  @override
  String get csvImportCopied => 'تم النسخ إلى الحافظة.';

  @override
  String get csvImportPreviewTitle => 'مراجعة الاستيراد';

  @override
  String get csvImportPreviewTasks => 'المهام';

  @override
  String get csvImportPreviewSubtasks => 'المهام الفرعية';

  @override
  String get csvImportPreviewNewProjects => 'المشاريع الجديدة';

  @override
  String get csvImportPreviewNewLabels => 'التسميات الجديدة';

  @override
  String get csvImportPreviewNewStatuses => 'الحالات الجديدة';

  @override
  String get csvImportNone => 'لا يوجد';

  @override
  String get csvImportDuplicateWarning =>
      'سيؤدي استيراد الملف نفسه مرة أخرى إلى إنشاء مهام مكررة.';

  @override
  String get csvImportConfirm => 'استيراد';

  @override
  String get csvImportSuccess => 'المهام المستوردة';

  @override
  String get csvImportErrorTitle => 'فشل استيراد CSV';

  @override
  String get csvImportUnexpectedError => 'تعذر استيراد الملف.';

  @override
  String get csvImportHumanGuide =>
      '1. احفظ الملف بصيغة CSV وترميز UTF-8. استخدم الفاصلة (موصى بها) أو الفاصلة المنقوطة كفاصل.\n\n2. العمود content إلزامي. ويمكنك أيضًا استخدام: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. ينشئ كل صف مهمة مفتوحة واحدة. افصل التسميات بعلامة |. الأولوية من 1 إلى 4، والقيمة الفارغة تعني 4. المشروع الفارغ يعني Inbox والحالة الفارغة تعني Backlog. تُنشأ المشاريع والتسميات والحالات المفتوحة الناقصة تلقائيًا.\n\n4. لمهمة طوال اليوم استخدم due_date بالصيغة YYYY-MM-DD. ولمهمة محددة الوقت املأ start_at وend_at بقيم RFC3339 مع فرق UTC، وحدد time_zone من IANA مثل Asia/Riyadh.\n\n5. لإنشاء مهام فرعية، امنح صف المهمة الأصلية key فريدًا وضع قيمته في parent_key للمهمة الفرعية. يمكن أن يظهر الصف الأصلي لاحقًا في الملف. يجب أن يتطابق المشروعان.\n\n6. يتحقق Pomodoist من الملف كاملًا ويعرض معاينة قبل الاستيراد. إذا كان أي صف غير صالح فلن يُحفظ شيء. إعادة الاستيراد تنشئ نسخًا مكررة.';

  @override
  String get settingsConnectedAgentsTitle => 'الوكلاء المتصلون';

  @override
  String get settingsConnectedAgentsLoading => 'جارٍ تحميل الوكلاء المتصلين…';

  @override
  String get settingsConnectedAgentsEmpty => 'لا يوجد وكلاء متصلون.';

  @override
  String get settingsConnectedAgentsLoadError => 'تعذر تحميل الوكلاء المتصلين.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'وكيل';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'تاريخ الاتصال: $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'إلغاء الوصول';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle => 'إلغاء وصول الوكيل؟';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'هل تريد إلغاء وصول $clientName إلى Pomodoist؟';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'تعذر إلغاء الوصول. حاول مرة أخرى.';

  @override
  String get settingsLanguageTitle => 'اللغة';

  @override
  String get settingsLanguageSubtitle => 'اختر لغة التطبيق.';

  @override
  String get settingsLanguageSystem => 'افتراضي النظام';

  @override
  String get settingsThemeTitle => 'السمة';

  @override
  String get settingsThemeSubtitle => 'اختر مظهر التطبيق.';

  @override
  String get settingsThemeSystem => 'النظام';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsTimerVisualTitle => 'مؤقت بومودورو';

  @override
  String get settingsTimerVisualSubtitle =>
      'اختر طريقة عرض التقدم في شاشة التركيز.';

  @override
  String get settingsTimerVisualBar => 'شريط';

  @override
  String get settingsTimerVisualCircle => 'دائرة';

  @override
  String get settingsReturnRemindersTitle => 'تذكيرات العودة';

  @override
  String get settingsReturnRemindersSubtitle =>
      'تنبيه مسائي لطيف إذا لم يكتمل أي تركيز أو مهمة اليوم.';

  @override
  String get settingsDefaultTimedBlockTitle => 'مدة كتلة التقويم الافتراضية';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'عند إدخال وقت فقط، تستخدم المهام الجديدة هذه المدة في التقويم.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'مدة مخصصة';

  @override
  String get settingsDefaultTimedBlockError => 'أدخل من 1 إلى 480 دقيقة.';

  @override
  String get settingsTaskTimeDisplayTitle => 'عرض وقت المهمة';

  @override
  String get settingsTaskTimeDisplaySubtitle =>
      'اختر كيفية عرض المهام المجدولة بوقت.';

  @override
  String get settingsTaskTimeDisplaySmart => 'ذكي';

  @override
  String get settingsTaskTimeDisplayRange => 'وقت البدء والانتهاء';

  @override
  String get settingsTaskTimeDisplayStartOnly => 'وقت البدء فقط';

  @override
  String get taskTimeStatusFuture => 'قادم';

  @override
  String get taskTimeStatusFocused => 'قيد التركيز';

  @override
  String get taskTimeStatusCurrent => 'قيد التنفيذ';

  @override
  String get taskTimeStatusOverdue => 'متأخرة';

  @override
  String get taskTimeStatusCompleted => 'مكتملة';

  @override
  String get menuTooltip => 'القائمة';

  @override
  String get localUser => 'مستخدم محلي';

  @override
  String get addTask => 'إضافة مهمة';

  @override
  String get quickAddHint => 'اكتب sync engine غدا p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'تعذرت إضافة المهمة: $error';
  }

  @override
  String get taskCreateFailed => 'تعذر إنشاء المهمة. حاول مرة أخرى.';

  @override
  String couldNotAddProject(Object error) {
    return 'تعذرت إضافة المشروع: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count مهام',
      one: 'تمت إضافة مهمة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'إضافة بالصوت';

  @override
  String get voiceTitle => 'إضافة بالصوت';

  @override
  String get voiceRecord => 'تسجيل';

  @override
  String get voiceAgain => 'مرة أخرى';

  @override
  String get voiceStop => 'إيقاف';

  @override
  String voiceAddCount(int count) {
    return 'إضافة $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'مهمة $index';
  }

  @override
  String get voiceRemoveTask => 'إزالة';

  @override
  String get voiceInstruction => 'اضغط تسجيل وأمل المهام.';

  @override
  String get voiceStatusIdle => 'إدخال من الميكروفون المدمج فقط';

  @override
  String get voiceStatusRequestingPermission => 'جار طلب الوصول';

  @override
  String get voiceStatusRecording => 'جار الاستماع إلى الميكروفون المدمج';

  @override
  String get voiceStatusTranscribing => 'جار تفريغ التسجيل';

  @override
  String get voiceStatusCanceled => 'تم إلغاء التسجيل';

  @override
  String get voiceStatusUnsupported => 'المنصة غير مدعومة';

  @override
  String get voiceStatusError => 'تعذر التعرف على الكلام';

  @override
  String get voiceStatusAnalyzing => 'جار التقسيم إلى مهام';

  @override
  String get voiceStatusReview => 'راجع المهام قبل الإضافة';

  @override
  String get voiceStepRecord => 'تسجيل';

  @override
  String get voiceStepText => 'نص';

  @override
  String get voiceStepAnalyze => 'تحليل';

  @override
  String get voiceStepReview => 'مراجعة';

  @override
  String get voiceAnalyzing => 'يقسم Pomodoist الكلام إلى مهام';

  @override
  String get voiceFallbackError =>
      'تعذر على Pomodoist معالجة الكلام، تم الاحتفاظ بمسودة للتعديل اليدوي.';

  @override
  String get voiceMicrophoneUnavailable =>
      'الميكروفون غير متاح حاليًا. أنهِ المكالمة أو الدردشة الصوتية النشطة ثم حاول مرة أخرى.';

  @override
  String get voiceSmartMode => 'الوضع الذكي';

  @override
  String get voiceRetryAnalysis => 'إعادة التحليل';

  @override
  String get screenInboxSubtitle => 'التقط المهام قبل تنظيمها.';

  @override
  String get priorityMatrixSubtitle =>
      'اسحب المهام بين الأولويات. تُستخدم التواريخ فقط لترتيب المهام داخل الأولوية.';

  @override
  String get priorityMatrixP1Title => 'أنجز الآن';

  @override
  String get priorityMatrixP2Title => 'جدولة';

  @override
  String get priorityMatrixP3Title => 'تفويض';

  @override
  String get priorityMatrixP4Title => 'إزالة';

  @override
  String get priorityMatrixAxisUrgent => 'عاجل';

  @override
  String get priorityMatrixAxisNotUrgent => 'غير عاجل';

  @override
  String get priorityMatrixAxisImportant => 'مهم';

  @override
  String get priorityMatrixAxisNotImportant => 'غير مهم';

  @override
  String get timelineSubtitle => 'خطط يوما واحدا على شبكة زمنية.';

  @override
  String get timelineAllDay => 'طوال اليوم';

  @override
  String get timelineBeforeHours => 'قبل الساعات المرئية';

  @override
  String get timelineAfterHours => 'بعد الساعات المرئية';

  @override
  String get timelineVisibleHours => 'الساعات المرئية';

  @override
  String get timelineStartHour => 'البداية';

  @override
  String get timelineEndHour => 'النهاية';

  @override
  String get timelineZoomOut => 'تصغير';

  @override
  String get timelineZoomIn => 'تكبير';

  @override
  String timelineAddTimedHint(String time) {
    return 'مهمة في $time';
  }

  @override
  String get timelineAddAllDayHint => 'مهمة طوال اليوم';

  @override
  String get timelineNoAllDayTasks => 'لا توجد مهام طوال اليوم';

  @override
  String get timelineNoTimedTasks => 'لا توجد مهام بوقت';

  @override
  String get timelinePreviousDay => 'اليوم السابق';

  @override
  String get timelineNextDay => 'اليوم التالي';

  @override
  String get timelinePickDate => 'اختيار تاريخ';

  @override
  String get upcomingPreviousPeriod => 'الفترة السابقة';

  @override
  String get upcomingNextPeriod => 'الفترة التالية';

  @override
  String get upcomingOpenDatePicker => 'فتح منتقي التاريخ';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مهمة',
      many: '$count مهمة',
      few: '$count مهام',
      two: 'مهمتان',
      one: 'مهمة واحدة',
      zero: 'لا توجد مهام',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'حمل التركيز: $planned فترات - المنجز: $completed - التركيز: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'المهام المخططة بعد اليوم.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'مهام مجدولة في $date.';
  }

  @override
  String get noTasksHere => 'لا توجد مهام هنا';

  @override
  String get noUpcomingTasks => 'لا توجد مهام مؤرخة';

  @override
  String get noTasksForDay => 'لا توجد مهام مجدولة لهذا اليوم';

  @override
  String failedToLoadTasks(Object error) {
    return 'تعذر تحميل المهام: $error';
  }

  @override
  String get searchTasks => 'بحث في المهام';

  @override
  String get searchStartTyping => 'ابدأ الكتابة للبحث في المهام';

  @override
  String get searchNoMatches => 'لا توجد مهام مطابقة';

  @override
  String failedToSearchTasks(Object error) {
    return 'تعذر البحث في المهام: $error';
  }

  @override
  String get previousMonth => 'الشهر السابق';

  @override
  String get nextMonth => 'الشهر التالي';

  @override
  String get clearDateFilter => 'مسح مرشح التاريخ';

  @override
  String get weekMon => 'الإثنين';

  @override
  String get weekTue => 'الثلاثاء';

  @override
  String get weekWed => 'الأربعاء';

  @override
  String get weekThu => 'الخميس';

  @override
  String get weekFri => 'الجمعة';

  @override
  String get weekSat => 'السبت';

  @override
  String get weekSun => 'الأحد';

  @override
  String get browseTitle => 'تصفح';

  @override
  String get unifiedAccount => 'حساب موحد';

  @override
  String accountUnavailable(Object error) {
    return 'الحساب غير متاح: $error';
  }

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get deleteAccount => 'حذف الحساب';

  @override
  String get deleteAccountConfirmation =>
      'سيؤدي هذا إلى حذف حسابك وبياناتك السحابية والمهام والمشاريع وسجل التركيز المحلي نهائيًا. لا يمكن التراجع عن ذلك. لا تُلغى اشتراكات المتجر تلقائيًا. إذا استخدمت تسجيل الدخول باستخدام Apple، فألغِ وصول Pomodoist بشكل منفصل من إعدادات حساب Apple.';

  @override
  String get manageSignInWithApple => 'إدارة تسجيل الدخول باستخدام Apple';

  @override
  String get deleteAccountFinalConfirmation =>
      'هل أنت متأكد تمامًا؟ هذا هو التأكيد الأخير.';

  @override
  String deleteAccountError(Object error) {
    return 'تعذر حذف الحساب: $error';
  }

  @override
  String get accountDeleted => 'تم حذف الحساب.';

  @override
  String get accountDeletedLocalCleanupError =>
      'تم حذف حسابك، لكن تعذر مسح البيانات المحلية. امسح بيانات التطبيق قبل استخدام هذا الجهاز مرة أخرى.';

  @override
  String get productivityTitle => 'الإنتاجية';

  @override
  String get achievementsTitle => 'الإنجازات';

  @override
  String get allTimeLabel => 'كل الوقت';

  @override
  String get lastSevenDaysLabel => 'آخر 7 أيام';

  @override
  String get noWeeklyStatsLabel => 'لا توجد بيانات تركيز أو مهام بعد';

  @override
  String get completedFocuses => 'التركيزات المكتملة';

  @override
  String get completedTasks => 'المهام المكتملة';

  @override
  String get unlocked => 'مفتوح';

  @override
  String get locked => 'مقفل';

  @override
  String get progressLabel => 'التقدم';

  @override
  String get focusAchievements => 'إنجازات التركيز';

  @override
  String get taskAchievements => 'إنجازات المهام';

  @override
  String get comboAchievements => 'إنجازات الكومبو';

  @override
  String get focusIntervals => 'فترات التركيز';

  @override
  String get focusTime => 'وقت التركيز';

  @override
  String get openTasks => 'المهام المفتوحة';

  @override
  String get plannedIntervals => 'الفترات المخططة';

  @override
  String get labelsTitle => 'التسميات';

  @override
  String get newProject => 'مشروع جديد';

  @override
  String get newLabel => 'تسمية جديدة';

  @override
  String get syncReadyQueue => 'قائمة جاهزة للمزامنة';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count أوامر محلية معلقة',
      one: 'أمر محلي واحد معلق',
      zero: 'لا توجد أوامر محلية معلقة',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'تعذر تحميل المشاريع: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'تعذر تحميل التسميات: $error';
  }

  @override
  String get addProject => 'إضافة مشروع';

  @override
  String get projectName => 'اسم المشروع';

  @override
  String get addLabel => 'إضافة تسمية';

  @override
  String get labelName => 'اسم التسمية';

  @override
  String couldNotAddLabel(Object error) {
    return 'تعذرت إضافة التسمية: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'المشاريع غير متاحة: $error';
  }

  @override
  String get projectsUnavailableShort => 'المشاريع غير متاحة';

  @override
  String get noProjects => 'لا توجد مشاريع';

  @override
  String get searchProjects => 'بحث في المشاريع';

  @override
  String get searchLabels => 'بحث في التسميات';

  @override
  String get archivedProjectsOnly => 'المشاريع المؤرشفة فقط';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مشاريع',
      one: 'مشروع واحد',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'لا توجد تسميات';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تسميات',
      one: 'تسمية واحدة',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => 'إعادة تسمية المشروع';

  @override
  String get deleteProject => 'حذف المشروع';

  @override
  String get deleteLabel => 'حذف التسمية';

  @override
  String deleteProjectConfirmation(String name) {
    return 'حذف \"$name\"؟ ستنتقل مهام هذا المشروع إلى Inbox.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'تعذر حذف المشروع: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'تعذر حذف التسمية: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'المشاريع: $count';
  }

  @override
  String get collapseProjects => 'طي المشاريع';

  @override
  String get expandProjects => 'توسيع المشاريع';

  @override
  String get projectFallbackTitle => 'مشروع';

  @override
  String get projectSubtitle => 'عرض القائمة - اللوحة والتقويم ضمن الخطة.';

  @override
  String get reportsTitle => 'التقارير';

  @override
  String get reportsFocusedDay => 'يوم مليء بالتركيز حتى الآن';

  @override
  String get reportsThisWeek => 'أسبوعك في التركيز';

  @override
  String get reportsNextAchievement => 'الإنجاز التالي';

  @override
  String get viewAllAchievements => 'عرض كل الإنجازات';

  @override
  String viewAllAchievementsCount(int count) {
    return 'عرض الكل: $count';
  }

  @override
  String get allAchievementsUnlocked => 'تم فتح جميع الإنجازات';

  @override
  String get noAchievementsYet => 'لا توجد إنجازات بعد';

  @override
  String failedToLoadAchievements(Object error) {
    return 'تعذر تحميل الإنجازات: $error';
  }

  @override
  String get backToReports => 'العودة إلى التقارير';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return 'اكتمل $completed من $target فترات تركيز';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return 'اكتملت $completed فترات تركيز؛ لا يوجد هدف';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'وقت التركيز في آخر 7 أيام: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'تعذر تحميل التقارير: $error';
  }

  @override
  String get taskNotFound => 'المهمة غير موجودة';

  @override
  String get taskTitleHint => 'عنوان المهمة';

  @override
  String get taskComment => 'تعليق';

  @override
  String get taskCommentHint => 'إضافة تعليق';

  @override
  String get subtasks => 'المهام الفرعية';

  @override
  String get addSubtask => 'إضافة مهمة فرعية';

  @override
  String get addSubtaskHint => 'إضافة مهمة فرعية';

  @override
  String get noSubtasks => 'لا توجد مهام فرعية بعد.';

  @override
  String get makeParentTask => 'تحويل إلى مهمة رئيسية';

  @override
  String couldNotMoveTask(Object error) {
    return 'تعذر نقل المهمة: $error';
  }

  @override
  String get scheduleTitle => 'الجدولة';

  @override
  String get allDay => 'طوال اليوم';

  @override
  String get timedBlock => 'كتلة زمنية';

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
  String get noDate => 'بلا تاريخ';

  @override
  String get calendarNotLinked => 'التقويم غير مرتبط';

  @override
  String get calendarLinked => 'Google Calendar مرتبط';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total تركيز';
  }

  @override
  String get startFocus => 'بدء التركيز';

  @override
  String get focusStarted => 'بدأ التركيز';

  @override
  String get taskReopened => 'أعيد فتح المهمة';

  @override
  String get taskCompleted => 'اكتملت المهمة';

  @override
  String get taskDeleted => 'حذفت المهمة';

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
  String get markOpen => 'تعليم كمفتوحة';

  @override
  String get markComplete => 'تعليم كمكتملة';

  @override
  String get focusHistory => 'سجل التركيز';

  @override
  String failedToLoadTask(Object error) {
    return 'تعذر تحميل المهمة: $error';
  }

  @override
  String get noFocusIntervals => 'لا توجد فترات تركيز بعد.';

  @override
  String get today => 'اليوم';

  @override
  String get tomorrow => 'غدا';

  @override
  String get yesterday => 'أمس';

  @override
  String get clearDate => 'مسح التاريخ';

  @override
  String priority(int priority) {
    return 'الأولوية $priority';
  }

  @override
  String get focusTitle => 'التركيز';

  @override
  String focusLoadError(Object error) {
    return 'تعذر تحميل التركيز: $error';
  }

  @override
  String get focusViewFull => 'كامل';

  @override
  String get focusViewMinimal => 'مصغر';

  @override
  String get focusSwitchToFullView => 'التبديل إلى العرض الكامل';

  @override
  String get focusSwitchToMinimalView => 'التبديل إلى العرض المصغر';

  @override
  String get focusActionFailed => 'تعذر تحديث التركيز. حاول مرة أخرى.';

  @override
  String get noActiveSession => 'لا توجد جلسة نشطة';

  @override
  String get focusIdleSubtitle =>
      'ابدأ فترة تركيز مستقلة أو ابدأ التركيز من مهمة.';

  @override
  String get noPreset => 'لا يوجد إعداد مسبق';

  @override
  String get preparingFocus => 'جار تجهيز التركيز';

  @override
  String get moreFocusOptions => 'المزيد من خيارات التركيز';

  @override
  String get moreFocusActions => 'المزيد من إجراءات التركيز';

  @override
  String get preset => 'إعداد مسبق';

  @override
  String get newPreset => 'إعداد مسبق جديد';

  @override
  String get customize => 'تخصيص';

  @override
  String get customizePreset => 'تخصيص الإعداد المسبق';

  @override
  String get startInterval => 'بدء الفترة';

  @override
  String get intervalStarted => 'بدأت الفترة';

  @override
  String get intervalCompleted => 'اكتملت الفترة';

  @override
  String get focusStopped => 'توقف التركيز';

  @override
  String get focusCompletionTitle => 'عمل رائع!';

  @override
  String get focusCompletionLinkedSubtitle =>
      'اكتملت جميع فترات التركيز المخططة لهذه المهمة.';

  @override
  String get focusCompletionStandaloneSubtitle => 'اكتملت دورة التركيز.';

  @override
  String get focusCompletionQuestion => 'هل تريد إكمال هذه المهمة؟';

  @override
  String get focusCompletionCompleteTask => 'إكمال المهمة';

  @override
  String get focusCompletionKeepOpen => 'إبقاء المهمة مفتوحة';

  @override
  String get focusCompletionDone => 'تم';

  @override
  String get focusCompletionNextTask => 'المهمة المجدولة التالية';

  @override
  String focusCompletionTaskError(Object error) {
    return 'تعذر إكمال المهمة: $error';
  }

  @override
  String get completeInterval => 'إكمال الفترة';

  @override
  String get logDistraction => 'تسجيل تشتيت';

  @override
  String get workInterval => 'فترة عمل';

  @override
  String get work => 'عمل';

  @override
  String get shortBreak => 'استراحة قصيرة';

  @override
  String get breakLabel => 'استراحة';

  @override
  String get longBreak => 'استراحة طويلة';

  @override
  String readyLabel(String label) {
    return 'جاهز: $label';
  }

  @override
  String get readyShort => 'جاهز';

  @override
  String focusTimerTotal(String duration) {
    return 'من أصل $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'الجلسة $current من $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'معاينة إيقاع التركيز، $count خطوات';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'إيقاع التركيز، الخطوة $current من $total: $phase، $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase، $status، متبقٍ $remaining، الإجمالي $total';
  }

  @override
  String get focusStatusRunning => 'جارٍ';

  @override
  String get focusStatusPaused => 'متوقف مؤقتًا';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total عمل';
  }

  @override
  String intervalNumber(int number) {
    return 'الفترة $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total عمل - الفترة $number';
  }

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get resume => 'متابعة';

  @override
  String get presetForNextIntervals => 'إعداد مسبق للفترات التالية';

  @override
  String usePreset(String name) {
    return 'استخدام $name';
  }

  @override
  String minutesWork(int minutes) {
    return '$minutesد عمل';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutesد قصيرة';
  }

  @override
  String minutesLong(int minutes) {
    return '$minutesد طويلة';
  }

  @override
  String longEvery(int count) {
    return 'طويلة كل $count';
  }

  @override
  String get autoBreaks => 'استراحات تلقائية';

  @override
  String get autoWork => 'عمل تلقائي';

  @override
  String get noPause => 'بلا إيقاف مؤقت';

  @override
  String get focusPauseUnavailable =>
      'الإيقاف المؤقت غير متاح لهذا الإعداد المسبق';

  @override
  String get strict => 'صارم';

  @override
  String get flexible => 'مرن';

  @override
  String get name => 'الاسم';

  @override
  String get workField => 'عمل';

  @override
  String get shortField => 'قصيرة';

  @override
  String get longField => 'طويلة';

  @override
  String get every => 'كل';

  @override
  String get minutesSuffix => 'د';

  @override
  String get makeDefault => 'جعله افتراضيا';

  @override
  String get autoStartBreaks => 'بدء الاستراحات تلقائيا';

  @override
  String get autoStartWork => 'بدء العمل تلقائيا';

  @override
  String get allowPause => 'السماح بالإيقاف المؤقت';

  @override
  String get strictMode => 'الوضع الصارم';

  @override
  String get nameRequired => 'الاسم مطلوب';

  @override
  String get nameMustBeUnique => 'يجب أن يكون الاسم فريدا';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'المزامنة ثنائية الاتجاه نشطة لتقويم Pomodoist.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'صل حساب Google لمزامنة المهام المجدولة.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'تتم مزامنة Google Calendar على جهاز آخر. ستستمر مزامنة بيانات Pomodoist هنا.';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String get useThisDevice => 'استخدم هذا الجهاز';

  @override
  String get connect => 'اتصال';

  @override
  String get disconnect => 'قطع الاتصال';

  @override
  String failedToLoadIntegration(Object error) {
    return 'تعذر تحميل التكامل: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'فشل Google Calendar: $message';
  }

  @override
  String get googleAuthRequired =>
      'يلزم تفويض Google Calendar. سجل الدخول مرة أخرى ثم شغل مزامنة الآن.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In غير مهيأ. عيّن GOOGLE_CLIENT_ID و GOOGLE_REVERSED_CLIENT_ID لهذا هدف iOS.';

  @override
  String get googleCallbackNotConfigured =>
      'رد Google Sign-In غير مهيأ. عيّن GOOGLE_REVERSED_CLIENT_ID في ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'على الويب، اضغط زر تسجيل الدخول إلى Google أولا، ثم اتصال.';

  @override
  String get googleAccessDenied =>
      'تم رفض وصول Google. أضف هذا الحساب كمستخدم اختبار OAuth أو انشر تطبيق OAuth وتحقق منه.';

  @override
  String get status => 'الحالة';

  @override
  String get account => 'الحساب';

  @override
  String get calendar => 'التقويم';

  @override
  String get calendarId => 'معرف التقويم';

  @override
  String get lastSync => 'آخر مزامنة';

  @override
  String get notConnected => 'غير متصل';

  @override
  String get notCreated => 'غير منشأ';

  @override
  String get never => 'أبدا';

  @override
  String durationMinutes(int minutes) {
    return '$minutesد';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hoursس $minutesد';
  }

  @override
  String get projectColor => 'لون المشروع';

  @override
  String projectColorOption(int number) {
    return 'اللون $number';
  }

  @override
  String get addProjectToFavorites => 'إضافة المشروع إلى المفضلة';

  @override
  String get removeProjectFromFavorites => 'إزالة المشروع من المفضلة';

  @override
  String get timelineProjectsMenu => 'إدارة مشاريع المخطط الزمني';

  @override
  String get timelineShowProject => 'إظهار المشروع في المخطط الزمني';

  @override
  String get timelineHideProject => 'إخفاء المشروع المؤقت';

  @override
  String get timelineCollapseProject => 'طي فرع المشروع';

  @override
  String get timelineExpandProject => 'توسيع فرع المشروع';

  @override
  String get timelineCurrentTime => 'الوقت الحالي';

  @override
  String couldNotUpdateProject(Object error) {
    return 'تعذر تحديث المشروع: $error';
  }

  @override
  String get commonDone => 'تم';

  @override
  String get taskSelect => 'تحديد';

  @override
  String taskSelectedCount(int count) {
    return 'تم تحديد $count';
  }

  @override
  String get taskSelectAll => 'تحديد الكل';

  @override
  String get taskDeselectAll => 'إلغاء تحديد الكل';

  @override
  String get taskDue => 'الموعد';

  @override
  String get taskProject => 'المشروع';

  @override
  String get taskLabels => 'التسميات';

  @override
  String get taskPriority => 'الأولوية';

  @override
  String get taskMore => 'المزيد';

  @override
  String get taskSchedule => 'جدولة';

  @override
  String get taskMove => 'نقل';

  @override
  String get taskDuplicate => 'تكرار';

  @override
  String get taskDuplicateTitle => 'تكرار المهام';

  @override
  String get taskDuplicateSelectedOnly => 'المحددة فقط';

  @override
  String get taskDuplicateWithSubtasks => 'مع المهام الفرعية';

  @override
  String get taskWeekend => 'نهاية هذا الأسبوع';

  @override
  String get taskNextWeek => 'الأسبوع القادم';

  @override
  String get taskEnterDue => 'أدخل موعداً أو وقتاً';

  @override
  String get taskInvalidDue => 'أدخل تاريخاً أو وقتاً صالحاً';

  @override
  String get taskClearDue => 'مسح الموعد';

  @override
  String get taskDeleteSelectedTitle => 'حذف المهام المحددة؟';

  @override
  String get taskDeleteSelectedMessage =>
      'يمكنك التراجع عن هذا الإجراء خلال 7 ثوانٍ.';

  @override
  String get taskCompleteSelected => 'إكمال المحددة';

  @override
  String get taskReopenSelected => 'إعادة فتح المحددة';

  @override
  String taskActionFailedCount(int count) {
    return 'تعذر تحديث $count من المهام';
  }

  @override
  String get voiceCollapse => 'طي لوحة الصوت';

  @override
  String get voiceExpand => 'توسيع لوحة الصوت';

  @override
  String get voiceMovePanel => 'نقل لوحة الصوت';
}

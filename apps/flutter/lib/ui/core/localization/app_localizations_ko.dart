// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get settingsSectionGeneral => '일반';

  @override
  String get settingsSectionAppearance => '모양';

  @override
  String get settingsSectionTasksFocus => '작업 및 집중';

  @override
  String get settingsSectionIntegrations => '연동 및 데이터';

  @override
  String get settingsSectionAccount => '계정 및 Pro';

  @override
  String get settingsThemeColorsTab => '색상';

  @override
  String get settingsThemeBackgroundsTab => '배경';

  @override
  String get settingsRefreshAccount => '계정 새로고침';

  @override
  String get settingsSubscriptionActions => '구독 옵션';

  @override
  String get settingsSubscriptionError =>
      '구독을 새로고침하지 못했습니다. 이전에 확인된 이용 권한은 유지됩니다.';

  @override
  String get settingsVersionError => '버전을 불러오지 못했습니다.';

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => '추가';

  @override
  String get commonCancel => '취소';

  @override
  String get commonSave => '저장';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonUndo => '실행 취소';

  @override
  String get commonOpen => '열기';

  @override
  String get commonBack => '뒤로';

  @override
  String get commonClose => '닫기';

  @override
  String get commonCreate => '만들기';

  @override
  String get commonClear => '지우기';

  @override
  String get commonStop => '중지';

  @override
  String get skip => '건너뛰기';

  @override
  String get onboardingLanguageTitle => '언어 선택';

  @override
  String get onboardingLanguageSubtitle => 'Pomodoist에서 사용할 언어를 선택하세요.';

  @override
  String get onboardingTimerTitle => '타이머 스타일 선택';

  @override
  String get onboardingTimerSubtitle => '집중 세션에서 포모도로 진행 상황을 표시할 방식을 선택하세요.';

  @override
  String get onboardingPaywallTitle => 'Pomodoist 잠금 해제';

  @override
  String get onboardingPaywallSubtitle => '평생 이용권 혜택은 매주 24시간 동안 제공됩니다.';

  @override
  String get onboardingAccountTitle => '계정 만들기';

  @override
  String get onboardingAccountSubtitle => '로그인하여 기기 간에 작업, 집중 기록, 설정을 동기화하세요.';

  @override
  String get startupPreparingTasks => '작업 준비 중';

  @override
  String get operationTakingLonger => '평소보다 오래 걸리고 있습니다. 작업은 계속 진행 중입니다.';

  @override
  String get onboardingContinue => '계속';

  @override
  String get onboardingMaybeLater => '나중에';

  @override
  String get onboardingFinish => '완료';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      '자연어로 말하면 Pomodoist가 말을 작업으로 바꿔 줍니다. 작업 기록은 영구적으로 저장됩니다.';

  @override
  String get billingSubtitleHighlight => '자연어';

  @override
  String get billingCancelAnytime => '언제든 해지할 수 있습니다.';

  @override
  String get billingMonthlyTitle => '월간';

  @override
  String get billingAnnualTitle => '연간';

  @override
  String billingPricePerMonth(String price) {
    return '$price/월';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/년';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return '첫 3개월 이후 $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return '이후 $price.';
  }

  @override
  String get billingLifetimeTitle => '평생';

  @override
  String get billingLifetimeSubtitle => '한 번 결제로 평생 이용.';

  @override
  String get billingBestValue => '최고의 혜택';

  @override
  String get billingChoose => '선택';

  @override
  String get billingActive => '이 기기에서 Pomodoist Pro가 활성화되어 있습니다.';

  @override
  String get billingActiveShort => '활성';

  @override
  String get billingRestore => '구입 복원';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get termsOfUse => '이용약관';

  @override
  String get support => '지원';

  @override
  String get billingManageLink => 'Link에서 관리';

  @override
  String get billingExternalBrowserTitle => '브라우저에서 결제가 열립니다';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist가 Safari 또는 기본 브라우저에서 Stripe Checkout을 엽니다. 계속하려면 브라우저 창을 허용하세요.';

  @override
  String get billingAppleOnly => 'iPhone, iPad, Mac에서 구입할 수 있습니다.';

  @override
  String get billingStoreUnavailable => '현재 App Store를 이용할 수 없습니다.';

  @override
  String get billingStoreConnectionFailed => 'VPN을 끄고 다시 시도하세요.';

  @override
  String billingPurchaseError(String error) {
    return '구입 오류: $error';
  }

  @override
  String get billingStripeAuthenticationRequired =>
      'Pomodoist에 로그인한 후 다시 시도하세요.';

  @override
  String get billingStripeDisabled => '아직 결제를 이용할 수 없습니다. 나중에 다시 시도하세요.';

  @override
  String get billingStripeAlreadyEntitled =>
      'Pomodoist Pro가 이미 활성화되어 있습니다. 계정 상태를 새로고침하세요.';

  @override
  String get billingStripeOfferExpired =>
      '이 혜택은 만료되었습니다. 다른 이용 가능한 요금제를 선택하세요.';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'Stripe 결제를 일시적으로 이용할 수 없습니다. 나중에 다시 시도하거나 지원팀에 문의하세요.';

  @override
  String get billingStripeCheckoutFailed =>
      '결제를 시작하지 못했습니다. 연결을 확인하고 다시 시도하세요.';

  @override
  String get purchaseSuccessTitle => 'Pro 활성화 완료';

  @override
  String get purchaseSuccessMessage =>
      'Pomodoist를 지원해 주셔서 감사합니다. 모든 Pro 기능을 사용할 수 있습니다.';

  @override
  String get purchaseSuccessContinue => '계속';

  @override
  String get purchaseProcessingTitle => '결제 처리 중';

  @override
  String get purchaseProcessingMessage =>
      '결제를 확인하고 있습니다. 잠시 후에도 Pro가 표시되지 않으면 나중에 다시 새로고침하세요.';

  @override
  String get purchaseOpenApp => 'Pomodoist 열기';

  @override
  String launchOfferEndsIn(String time) {
    return '평생 이용권 혜택 종료까지 $time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => '이메일';

  @override
  String get loginTitle => 'Pomodoist에 로그인';

  @override
  String get accountChecking => '계정 확인 중';

  @override
  String get oauthConsentTitle => '에이전트 연결';

  @override
  String get oauthConsentLoading => '연결 요청 확인 중';

  @override
  String get oauthConsentInvalidAuthorization => '연결 요청이 없거나 유효하지 않습니다.';

  @override
  String get oauthConsentLoadError => '연결 요청을 불러오지 못했습니다.';

  @override
  String get oauthConsentActionError => '요청을 완료하지 못했습니다. 다시 시도하세요.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist가 받은 반환 주소가 없거나 안전하지 않습니다. 접근 권한을 전달하지 않았습니다.';

  @override
  String get oauthConsentClientFallback => '에이전트';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName에서 Pomodoist에 접근하려고 합니다';
  }

  @override
  String get oauthConsentRedirectOrigin => '반환 주소';

  @override
  String get oauthConsentCapabilitiesTitle => '이 에이전트가 할 수 있는 일';

  @override
  String get oauthConsentManagePlanning => '작업, 프로젝트, 사용자 라벨, 칸반을 읽고 관리합니다.';

  @override
  String get oauthConsentReadInsights => '완료된 집중 기록, 생산성 보고서, 업적을 읽습니다.';

  @override
  String get oauthConsentUnavailableTitle => '이 에이전트가 할 수 없는 일';

  @override
  String get oauthConsentUnavailable =>
      '계정이나 결제, Google Calendar, 실행 중인 집중 타이머에 접근합니다.';

  @override
  String get oauthConsentUnsupportedScopes =>
      '이 요청은 지원하지 않는 계정 접근 권한을 요구하므로 승인할 수 없습니다.';

  @override
  String get oauthConsentApprove => '허용';

  @override
  String get oauthConsentDeny => '거부';

  @override
  String get oauthConsentApproving => '접근 허용 중…';

  @override
  String get oauthConsentDenying => '접근 거부 중…';

  @override
  String get oauthConsentRedirecting => '에이전트로 돌아가는 중…';

  @override
  String get loginCreateAccountPrompt => '아직 계정이 없으신가요?';

  @override
  String get loginCreateAccountAction => '계정 만들기';

  @override
  String get registerTitle => '계정 만들기';

  @override
  String get registerSubtitle => '기기 간에 작업, 집중 기록, 설정을 동기화하세요.';

  @override
  String get registerPassword => '비밀번호';

  @override
  String get registerSubmit => '계정 만들기';

  @override
  String get registerSignInPrompt => '이미 계정이 있으신가요?';

  @override
  String get registerSignInAction => '로그인';

  @override
  String get registerCheckEmailTitle => '이메일 확인';

  @override
  String get registerCheckEmailMessage =>
      '이 주소에 확인이 필요한 경우 링크가 포함된 이메일이 전송됩니다. 이미 계정이 있다면 로그인하거나 비밀번호를 재설정하세요.';

  @override
  String registerError(Object error) {
    return '계정을 만들지 못했습니다: $error';
  }

  @override
  String get authEmailSignInTitle => '이메일로 로그인';

  @override
  String get authWelcomeTitle => 'Pomodoist에 로그인';

  @override
  String get authWelcomeDescription => '모든 기기에서 작업과 집중을 이어 가세요.';

  @override
  String get authSignInWithLink => '링크로 로그인';

  @override
  String get authForgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get authBackToSignIn => '로그인으로 돌아가기';

  @override
  String get authNoAccount => '아직 계정이 없으신가요?';

  @override
  String get authHaveAccount => '이미 계정이 있으신가요?';

  @override
  String get authShowPassword => '비밀번호 표시';

  @override
  String get authHidePassword => '비밀번호 숨기기';

  @override
  String get authResetTitle => '비밀번호 재설정';

  @override
  String get authResetDescription =>
      '계정 이메일을 입력하세요. 비밀번호를 변경할 수 있는 링크를 보내 드립니다.';

  @override
  String get authResetEmailSentTitle => '이메일 확인';

  @override
  String get authResetEmailSent => '이 이메일로 등록된 계정이 있으면 비밀번호 재설정 링크가 전송됩니다.';

  @override
  String get authResetSendAgain => '다시 보내기';

  @override
  String get authResetEditEmail => '이메일 변경';

  @override
  String get authNewPasswordTitle => '새 비밀번호 선택';

  @override
  String get authNewPasswordDescription => '다른 계정에서 사용하지 않는 비밀번호를 사용하세요.';

  @override
  String get authNewPassword => '새 비밀번호';

  @override
  String get authConfirmPassword => '비밀번호 재입력';

  @override
  String get authSavePassword => '비밀번호 저장';

  @override
  String get authPasswordMismatch => '비밀번호가 일치하지 않습니다.';

  @override
  String get authPasswordUnchanged => '현재 비밀번호와 다른 비밀번호를 선택하세요.';

  @override
  String get authPasswordUpdatedTitle => '비밀번호 업데이트 완료';

  @override
  String get authPasswordUpdatedMessage =>
      '새 비밀번호가 저장되었습니다. Pomodoist를 계속 사용할 수 있습니다.';

  @override
  String get authResetLinkExpired =>
      '비밀번호 재설정 링크가 유효하지 않거나 만료되었습니다. 새 링크를 요청하세요.';

  @override
  String get authUnexpectedReset => '비밀번호 재설정 이메일을 보내지 못했습니다. 다시 시도하세요.';

  @override
  String get authUnexpectedPasswordUpdate => '새 비밀번호를 저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get authCheckingResetLink => '비밀번호 재설정 링크 확인 중…';

  @override
  String get authSignInAction => '로그인';

  @override
  String get authSendLink => '링크 보내기';

  @override
  String get authMagicLinkSent =>
      '이 주소로 등록된 계정이 있으면 로그인 링크가 전송됩니다. 받은 편지함과 스팸 폴더를 확인하세요.';

  @override
  String get authAccountCreated => '계정이 생성되었습니다.';

  @override
  String get authSignedIn => '로그인했습니다.';

  @override
  String get authEmailRequired => '이메일을 입력하세요.';

  @override
  String get authEmailInvalid => '이메일 주소를 확인하세요. 예: name@example.com.';

  @override
  String get authPasswordRequired => '비밀번호를 입력하세요.';

  @override
  String get authInvalidCredentials =>
      '이메일 또는 비밀번호가 올바르지 않습니다. 주소를 확인하거나 비밀번호를 재설정하거나 계정을 만드세요.';

  @override
  String get authEmailUnconfirmed => '전송된 링크로 이메일을 확인한 후 다시 로그인하세요.';

  @override
  String get authWeakPassword =>
      '이 비밀번호는 추측하기 쉽습니다. 더 길고 예측하기 어려운 비밀번호를 사용하세요.';

  @override
  String get authAccountMayExist =>
      '이 이메일을 사용하는 계정이 이미 있을 수 있습니다. 로그인하거나 비밀번호를 재설정하세요.';

  @override
  String get authRateLimited => '시도 횟수가 너무 많습니다. 몇 분 후 다시 시도하세요.';

  @override
  String get authEmailRateLimited => '이메일을 너무 많이 요청했습니다. 몇 분 후 다시 요청하세요.';

  @override
  String get authOffline => '계정 서비스에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도하세요.';

  @override
  String get authTimeout => '계정 서비스의 응답이 지연되고 있습니다. 다시 시도하세요.';

  @override
  String get authServiceUnavailable =>
      '계정 서비스를 일시적으로 이용할 수 없습니다. 나중에 다시 시도하세요.';

  @override
  String get authCaptchaRequired => '계속하려면 보안 확인을 완료하세요.';

  @override
  String get authCaptchaExpired => '보안 확인이 만료되었습니다. 다시 완료하세요.';

  @override
  String get authCaptchaFailed => '보안 확인에 실패했습니다. 다시 시도하세요.';

  @override
  String get authCaptchaCancelled => '보안 확인이 취소되었습니다. 계속하려면 다시 시작하세요.';

  @override
  String get authCaptchaUnavailable =>
      '현재 보안 확인을 이용할 수 없습니다. 연결을 확인하고 다시 시도하세요.';

  @override
  String get authCaptchaOpenFailed =>
      'Pomodoist가 브라우저에서 보안 확인을 열지 못했습니다. 기본 브라우저를 확인하고 다시 시도하세요.';

  @override
  String get authProviderFallback => '이 제공업체';

  @override
  String authProviderUnavailable(String provider) {
    return '현재 $provider 로그인을 이용할 수 없습니다. 다시 시도하거나 다른 방법을 사용하세요.';
  }

  @override
  String authProviderUnavailableHere(String provider) {
    return '이 환경에서는 $provider 로그인을 이용할 수 없습니다. 다른 로그인 방법을 사용하세요.';
  }

  @override
  String get authSignUpDisabled =>
      '이메일 계정 생성을 일시적으로 이용할 수 없습니다. 다른 로그인 방법을 시도하세요.';

  @override
  String get authAccountRestricted =>
      '현재 이 계정으로 로그인할 수 없습니다. 오류라고 생각되면 지원팀에 문의하세요.';

  @override
  String get authLinkExpired => '로그인 링크가 유효하지 않거나 만료되었습니다. 새 링크를 요청하세요.';

  @override
  String get authUnexpectedSignIn => '로그인하지 못했습니다. 다시 시도하세요.';

  @override
  String get authUnexpectedSignUp => '계정을 만들지 못했습니다. 다시 시도하세요.';

  @override
  String get authUnexpectedMagicLink => '로그인 링크를 보내지 못했습니다. 다시 시도하세요.';

  @override
  String get authResendConfirmation => '확인 이메일 다시 보내기';

  @override
  String get authConfirmationSendFailed => '확인 이메일을 보내지 못했습니다. 나중에 다시 시도하세요.';

  @override
  String get authRetryVerification => '확인 다시 시도';

  @override
  String get captchaSecurityLabel => '보안 확인';

  @override
  String get captchaChallengeTitle => 'Pomodoist 보안 확인';

  @override
  String get captchaChallengePrompt => 'Pomodoist에서 계속하려면 사람임을 확인하세요.';

  @override
  String get captchaChallengeInvalid =>
      '보안 확인 링크가 유효하지 않습니다. Pomodoist로 돌아가 다시 시도하세요.';

  @override
  String get captchaChallengeHandoffHelp =>
      'Pomodoist가 열리지 않았다면 아래 버튼을 사용하세요. 앱이 설치되어 있지 않으면 이 페이지를 닫고 시작한 기기로 돌아가세요.';

  @override
  String get captchaReturnToApp => 'Pomodoist로 돌아가기';

  @override
  String get navSearch => '검색';

  @override
  String get navInbox => '받은 편지함';

  @override
  String get navPriorityMatrix => '우선순위 매트릭스';

  @override
  String get navCalendar => '캘린더';

  @override
  String get calendarSubtitle => '하루를 계획하고 삶을 위한 여유를 남겨 두세요.';

  @override
  String get calendarDay => '일';

  @override
  String get calendarWeek => '주';

  @override
  String get calendarMonth => '월';

  @override
  String get calendarRoutine => '일과';

  @override
  String get calendarOverview => '하루 개요';

  @override
  String get calendarOpenMonth => '월 보기 열기';

  @override
  String get calendarUnscheduled => '일정 없음';

  @override
  String get calendarAllProjects => '모든 프로젝트';

  @override
  String get calendarRoutineDefault => '평소의 하루';

  @override
  String get calendarRoutineDescription =>
      '작업은 시작 시간별로 그룹화됩니다. 하루에 맞게 시간대를 조정하세요.';

  @override
  String get calendarEditRoutine => '시간대 설정';

  @override
  String get calendarRoutineTitle => '일과 설정';

  @override
  String get calendarRoutineName => '일과 이름';

  @override
  String get calendarPeriodName => '시간대 이름';

  @override
  String get calendarAddPeriod => '시간대 추가';

  @override
  String get calendarRemovePeriod => '시간대 삭제';

  @override
  String get calendarPeriodStart => '시작';

  @override
  String get calendarPeriodEnd => '종료';

  @override
  String get calendarRoutineInvalid =>
      '일과와 시간대에 이름을 지정하세요. 종료 시간은 시작 시간보다 늦어야 하며 시간대가 겹치면 안 됩니다.';

  @override
  String get calendarOutsideRoutine => '일과 시간대 외';

  @override
  String get calendarFreeTime => '자유 시간';

  @override
  String get calendarMorning => '아침';

  @override
  String get calendarAfternoon => '오후';

  @override
  String get calendarEvening => '저녁';

  @override
  String get calendarNewPeriod => '새 시간대';

  @override
  String get calendarResize => '작업 시간 변경';

  @override
  String get calendarPreviousPeriod => '이전 시간대';

  @override
  String get calendarNextPeriod => '다음 시간대';

  @override
  String get calendarSaveFailed => '캘린더 설정을 저장하지 못했습니다';

  @override
  String get calendarNoActiveFocus => '진행 중인 집중 세션 없음';

  @override
  String get calendarCurrentTask => '현재 작업';

  @override
  String get navTimeline => '타임라인';

  @override
  String get navKanban => '칸반';

  @override
  String get kanbanTitle => '칸반';

  @override
  String get kanbanSubtitle => '작업 흐름을 시각화하고 지금 중요한 일에 집중하세요.';

  @override
  String get kanbanDefaultBacklog => '백로그';

  @override
  String get kanbanDefaultTodo => '할 일';

  @override
  String get kanbanDefaultInProgress => '진행 중';

  @override
  String get kanbanDefaultDone => '완료';

  @override
  String get kanbanSearchTooltip => '칸반 검색';

  @override
  String get kanbanSearchHint => '작업 또는 프로젝트 검색';

  @override
  String get kanbanHideDone => '완료 숨기기';

  @override
  String get kanbanShowDone => '완료 표시';

  @override
  String get kanbanProjectsTitle => '이 보드의 프로젝트';

  @override
  String kanbanAddToStatus(String status) {
    return '$status에 추가';
  }

  @override
  String get kanbanTaskField => '작업';

  @override
  String get kanbanProjectField => '프로젝트';

  @override
  String get kanbanChooseProject => '프로젝트를 선택하세요.';

  @override
  String get kanbanTaskActions => '작업 동작';

  @override
  String get kanbanDragTask => '작업 드래그';

  @override
  String kanbanMoveTo(String status) {
    return '$status(으)로 이동';
  }

  @override
  String get kanbanRestoreBeforeFocus => '집중을 시작하기 전에 작업을 복원하세요.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return '집중을 시작하지 못했습니다: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return '칸반을 불러오지 못했습니다: $error';
  }

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonContinueWaiting => '계속 기다리기';

  @override
  String kanbanTasksCount(int count) {
    return '작업 $count개';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '하위 작업 $completed/$total개';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '집중 구간 $completed/$total회';
  }

  @override
  String get kanbanActive => '활성';

  @override
  String kanbanPriority(int priority) {
    return '우선순위 $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return '$status(으)로 이동했습니다';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return '$task 집중을 시작했습니다';
  }

  @override
  String get kanbanNoTasks => '아직 작업이 없습니다';

  @override
  String get navToday => '오늘';

  @override
  String get navUpcoming => '예정';

  @override
  String get navBrowse => '둘러보기';

  @override
  String get navIntegrations => '연동';

  @override
  String get navReports => '보고서';

  @override
  String get navFocus => '집중';

  @override
  String get navProjects => '프로젝트';

  @override
  String get navSettings => '설정';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsAboutTitle => '정보';

  @override
  String get settingsFocusCompletionCelebrationTitle => '집중 완료 축하';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      '마지막 휴식 후 전체 화면으로 축하를 표시합니다.';

  @override
  String get settingsVersionLabel => '버전';

  @override
  String get settingsPlanLabel => '요금제';

  @override
  String get settingsPlanFree => '무료';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => '키보드 단축키';

  @override
  String get settingsShortcutsSubtitle => '하드웨어 키보드에서 사용할 명령을 사용자화하세요.';

  @override
  String get settingsShortcutsToggleSidebar => '사이드바 전환';

  @override
  String get settingsShortcutsGlobalQuickAdd => '전역 빠른 추가';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Pomodoist가 활성 상태가 아니어도 작동합니다.';

  @override
  String get settingsShortcutsRecordTitle => '단축키를 누르세요';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Command, Control 또는 Alt와 함께 키를 누르세요. 취소하려면 Esc를 누르세요.';

  @override
  String get settingsShortcutsInvalid => 'Command, Control 또는 Alt를 포함하세요.';

  @override
  String get settingsShortcutsConflict => '이미 사용 중인 단축키입니다.';

  @override
  String get settingsShortcutsGlobalError =>
      '이 전역 단축키를 사용할 수 없습니다. 이전 단축키는 계속 활성화됩니다.';

  @override
  String get settingsShortcutsResetAll => '모두 재설정';

  @override
  String get settingsShortcutsResetDone => '키보드 단축키를 재설정했습니다.';

  @override
  String get csvImportTitle => 'CSV에서 작업 가져오기';

  @override
  String get csvImportSubtitle =>
      '작업, 프로젝트, 라벨, 작업 흐름 상태를 만들기 전에 CSV 파일을 검토하세요.';

  @override
  String get csvImportSelectFile => 'CSV 파일 선택';

  @override
  String get csvImportHumanGuideButton => '사용자용 가이드';

  @override
  String get csvImportAgentGuideButton => '에이전트용 가이드';

  @override
  String get csvImportHumanGuideTitle => 'CSV 파일 준비 방법';

  @override
  String get csvImportAgentGuideTitle => '에이전트용 CSV 규격';

  @override
  String get csvImportCopy => '복사';

  @override
  String get csvImportCopied => '클립보드에 복사했습니다.';

  @override
  String get csvImportPreviewTitle => '가져오기 검토';

  @override
  String get csvImportPreviewTasks => '작업';

  @override
  String get csvImportPreviewSubtasks => '하위 작업';

  @override
  String get csvImportPreviewNewProjects => '새 프로젝트';

  @override
  String get csvImportPreviewNewLabels => '새 라벨';

  @override
  String get csvImportPreviewNewStatuses => '새 작업 흐름 상태';

  @override
  String get csvImportNone => '없음';

  @override
  String get csvImportDuplicateWarning => '같은 파일을 다시 가져오면 작업이 중복 생성됩니다.';

  @override
  String get csvImportConfirm => '가져오기';

  @override
  String get csvImportSuccess => '작업을 가져왔습니다';

  @override
  String get csvImportErrorTitle => 'CSV 가져오기 실패';

  @override
  String get csvImportUnexpectedError => '파일을 가져오지 못했습니다.';

  @override
  String get csvImportHumanGuide =>
      '1. 파일을 UTF-8 CSV로 저장하세요. 구분자로 쉼표(권장) 또는 세미콜론을 사용하세요.\n\n2. content 열은 필수입니다. 다음 열도 사용할 수 있습니다: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. 각 행에 미완료 작업 하나를 넣으세요. 라벨은 |로 구분합니다. 우선순위는 1~4이며 빈 값은 4입니다. 프로젝트가 비어 있으면 받은 편지함, 작업 흐름 상태가 비어 있으면 백로그로 처리됩니다. 없는 프로젝트, 라벨, 미완료 상태는 자동 생성됩니다.\n\n4. 종일 작업은 due_date에 YYYY-MM-DD 형식을 사용하세요. 시간이 지정된 작업은 start_at과 end_at을 UTC 오프셋이 포함된 RFC3339 값으로 입력하고 Europe/Moscow와 같은 IANA time_zone을 지정하세요.\n\n5. 하위 작업을 만들려면 상위 행에 고유한 key를 지정하고 하위 행의 parent_key에 그 값을 넣으세요. 상위 행은 파일 뒤쪽에 있어도 됩니다. 하위 작업은 상위 작업과 같은 프로젝트를 사용해야 합니다.\n\n6. Pomodoist는 전체 파일을 검증하고 가져오기 전에 미리보기를 표시합니다. 유효하지 않은 행이 하나라도 있으면 아무것도 저장하지 않습니다. 다시 가져오면 작업이 중복 생성됩니다.';

  @override
  String get settingsConnectedAgentsTitle => '연결된 에이전트';

  @override
  String get settingsConnectedAgentsLoading => '연결된 에이전트 불러오는 중…';

  @override
  String get settingsConnectedAgentsEmpty => '연결된 에이전트가 없습니다.';

  @override
  String get settingsConnectedAgentsLoadError => '연결된 에이전트를 불러오지 못했습니다.';

  @override
  String get settingsConnectedAgentsUnknownClient => '에이전트';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return '$date에 연결됨';
  }

  @override
  String get settingsConnectedAgentsRevoke => '접근 권한 취소';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle => '에이전트 접근 권한을 취소할까요?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return '$clientName의 Pomodoist 접근 권한을 취소할까요?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      '접근 권한을 취소하지 못했습니다. 다시 시도하세요.';

  @override
  String get settingsLanguageTitle => '언어';

  @override
  String get settingsLanguageSubtitle => '앱 언어를 선택하세요.';

  @override
  String get settingsLanguageSystem => '시스템 기본값';

  @override
  String get settingsVoiceTranscriptionTitle => '음성 받아쓰기';

  @override
  String get settingsVoiceTranscriptionSubtitle =>
      '이 기기에서 녹음을 텍스트로 변환하는 방식을 선택하세요.';

  @override
  String get settingsVoiceTranscriptionSystem => '시스템(Apple)';

  @override
  String get settingsVoiceTranscriptionCloud => '클라우드';

  @override
  String get settingsVoiceTranscriptionCloudDescription =>
      '클라우드 받아쓰기는 오디오를 Pomodoist로 전송하며 인터넷 연결이 필요합니다.';

  @override
  String get settingsVoiceTranscriptionCloudRequiresSignIn =>
      '클라우드 받아쓰기를 사용하려면 로그인하세요. 그전까지 시스템 받아쓰기가 활성화됩니다.';

  @override
  String get settingsThemeTitle => '테마';

  @override
  String get settingsThemeSubtitle => '앱의 모양을 선택하세요.';

  @override
  String get settingsThemeSystem => '시스템';

  @override
  String get settingsThemeLight => '라이트';

  @override
  String get settingsThemeDark => '다크';

  @override
  String get settingsTimerVisualTitle => '포모도로 타이머';

  @override
  String get settingsTimerVisualSubtitle => '집중 화면에서 진행 상황을 표시할 방식을 선택하세요.';

  @override
  String get settingsTimerVisualBar => '막대';

  @override
  String get settingsTimerVisualCircle => '원';

  @override
  String get settingsReturnRemindersTitle => '복귀 알림';

  @override
  String get settingsReturnRemindersSubtitle =>
      '오늘 완료한 작업이 없으면 20:30에 알려 드립니다.';

  @override
  String get settingsDefaultTimedBlockTitle => '기본 캘린더 블록 길이';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      '시간만 입력하면 새 작업은 캘린더에서 이 길이를 사용합니다.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => '사용자 지정 길이';

  @override
  String get settingsDefaultTimedBlockError => '1~480분을 입력하세요.';

  @override
  String get settingsTaskTimeDisplayTitle => '작업 시간 표시';

  @override
  String get settingsTaskTimeDisplaySubtitle => '시간이 지정된 작업 일정을 표시할 방식을 선택하세요.';

  @override
  String get settingsTaskTimeDisplaySmart => '스마트';

  @override
  String get settingsTaskTimeDisplayRange => '시작 및 종료 시간';

  @override
  String get settingsTaskTimeDisplayStartOnly => '시작 시간만';

  @override
  String get taskTimeStatusFuture => '예정';

  @override
  String get taskTimeStatusFocused => '집중 중';

  @override
  String get taskTimeStatusCurrent => '진행 중';

  @override
  String get taskTimeStatusOverdue => '기한 지남';

  @override
  String get taskTimeStatusCompleted => '완료';

  @override
  String get menuTooltip => '메뉴';

  @override
  String get localUser => '로컬 사용자';

  @override
  String get addTask => '작업 추가';

  @override
  String get quickAddHint => '동기화 기능 만들기 내일 p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return '작업을 추가하지 못했습니다: $error';
  }

  @override
  String get taskCreateFailed => '작업을 만들지 못했습니다. 다시 시도하세요.';

  @override
  String couldNotAddProject(Object error) {
    return '프로젝트를 추가하지 못했습니다: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '작업 $count개 추가됨',
      one: '작업 1개 추가됨',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => '음성 빠른 추가';

  @override
  String get voiceTitle => '음성 추가';

  @override
  String get voiceRecord => '녹음';

  @override
  String get voiceAgain => '다시';

  @override
  String get voiceStop => '중지';

  @override
  String voiceAddCount(int count) {
    return '$count개 추가';
  }

  @override
  String voiceTaskLabel(int index) {
    return '작업 $index';
  }

  @override
  String get voiceRemoveTask => '제거';

  @override
  String get voiceInstruction => '녹음을 누르고 작업을 말하세요.';

  @override
  String get voiceStatusIdle => '내장 마이크 입력만 사용';

  @override
  String get voiceStatusRequestingPermission => '접근 요청 중';

  @override
  String get voiceStatusRecording => '내장 마이크로 듣는 중';

  @override
  String get voiceStatusTranscribing => '녹음 받아쓰는 중';

  @override
  String get voiceStatusCanceled => '녹음 취소됨';

  @override
  String get voiceStatusUnsupported => '지원하지 않는 플랫폼입니다';

  @override
  String get voiceStatusError => '음성을 인식하지 못했습니다';

  @override
  String get voiceStatusAnalyzing => '작업으로 나누는 중';

  @override
  String get voiceStatusReview => '추가하기 전에 작업 검토';

  @override
  String get voiceStepRecord => '녹음';

  @override
  String get voiceStepText => '텍스트';

  @override
  String get voiceStepAnalyze => '분석';

  @override
  String get voiceStepReview => '검토';

  @override
  String get voiceAnalyzing => 'Pomodoist가 음성을 작업으로 나누고 있습니다';

  @override
  String get voiceFallbackError =>
      'Pomodoist가 음성을 처리하지 못했습니다. 직접 수정할 수 있도록 초안을 보관했습니다.';

  @override
  String get voiceMicrophoneUnavailable =>
      '현재 마이크를 사용할 수 없습니다. 통화나 음성 채팅을 종료한 후 다시 시도하세요.';

  @override
  String get voiceSmartMode => '스마트 모드';

  @override
  String get voiceRetryTranscription => '받아쓰기 다시 시도';

  @override
  String get voiceRecordingSaved => '이 기기에 녹음을 저장했습니다. 다시 녹음하지 않고 재시도할 수 있습니다.';

  @override
  String get voiceAllowAccess => '접근 허용';

  @override
  String get voiceOpenMicrophoneSettings => '마이크 설정 열기';

  @override
  String get voiceOpenSpeechSettings => '음성 인식 설정 열기';

  @override
  String get voiceEnableDictation => '받아쓰기 활성화';

  @override
  String get voiceUseCloudTranscription => '클라우드 받아쓰기 사용';

  @override
  String get voiceMicrophoneDenied => '시스템 설정에서 마이크 접근을 허용하세요.';

  @override
  String get voiceSpeechDenied => '시스템 설정에서 음성 인식을 허용하세요.';

  @override
  String get voiceAccessRestricted => '관리자 또는 스크린 타임 설정으로 접근이 제한됩니다.';

  @override
  String get voiceDictationDisabled =>
      '시스템 설정 → 키보드 → 받아쓰기에서 받아쓰기를 활성화하고 언어를 선택한 후 다시 시도하세요.';

  @override
  String get voiceServiceUnavailable =>
      '음성 인식을 이용할 수 없습니다. 연결을 확인하세요. Mac에서는 시스템 설정 → 키보드 → 받아쓰기 및 언어도 확인하세요.';

  @override
  String get voiceCloudServiceUnavailable =>
      '클라우드 받아쓰기에 실패했습니다. 인터넷 연결을 확인하고 저장된 녹음으로 다시 시도하세요.';

  @override
  String get voiceLocaleUnsupported => '이 기기의 시스템 음성 인식은 선택한 언어를 지원하지 않습니다.';

  @override
  String get voiceNetworkUnavailable =>
      '이 언어의 음성 인식에는 인터넷 연결이 필요합니다. 다시 연결한 후 시도하세요.';

  @override
  String get voiceSettingsFailed =>
      '설정을 열지 못했습니다. 시스템 설정을 직접 열어 마이크 및 음성 인식 접근 권한을 확인하세요. Mac에서는 키보드 → 받아쓰기도 확인하세요.';

  @override
  String get voiceRetryAnalysis => '분석 다시 시도';

  @override
  String get screenInboxSubtitle => '정리하기 전에 작업을 기록하세요.';

  @override
  String get priorityMatrixSubtitle =>
      '우선순위 간에 작업을 드래그하세요. 날짜는 같은 우선순위 안에서 작업 순서만 정합니다.';

  @override
  String get priorityMatrixP1Title => '지금 하기';

  @override
  String get priorityMatrixP2Title => '일정 잡기';

  @override
  String get priorityMatrixP3Title => '위임하기';

  @override
  String get priorityMatrixP4Title => '제외하기';

  @override
  String get priorityMatrixAxisUrgent => '긴급';

  @override
  String get priorityMatrixAxisNotUrgent => '긴급하지 않음';

  @override
  String get priorityMatrixAxisImportant => '중요';

  @override
  String get priorityMatrixAxisNotImportant => '중요하지 않음';

  @override
  String get timelineSubtitle => '시간 격자에서 하루를 계획하세요.';

  @override
  String get timelineAllDay => '종일';

  @override
  String get timelineBeforeHours => '표시 시간 이전';

  @override
  String get timelineAfterHours => '표시 시간 이후';

  @override
  String get timelineVisibleHours => '표시 시간';

  @override
  String get timelineStartHour => '시작';

  @override
  String get timelineEndHour => '종료';

  @override
  String get timelineZoomOut => '축소';

  @override
  String get timelineZoomIn => '확대';

  @override
  String timelineAddTimedHint(String time) {
    return '$time 작업';
  }

  @override
  String get timelineAddAllDayHint => '종일 작업';

  @override
  String get timelineNoAllDayTasks => '종일 작업이 없습니다';

  @override
  String get timelineNoTimedTasks => '시간이 지정된 작업이 없습니다';

  @override
  String get timelinePreviousDay => '이전 날';

  @override
  String get timelineNextDay => '다음 날';

  @override
  String get timelinePickDate => '날짜 선택';

  @override
  String get upcomingPreviousPeriod => '이전 기간';

  @override
  String get upcomingNextPeriod => '다음 기간';

  @override
  String get upcomingOpenDatePicker => '날짜 선택기 열기';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '작업 $count개',
      one: '작업 1개',
      zero: '작업 없음',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return '집중 계획: $planned회 - 완료: $completed회 - 집중: $focus';
  }

  @override
  String get screenUpcomingSubtitle => '오늘 이후에 계획된 작업입니다.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return '$date에 예정된 작업입니다.';
  }

  @override
  String get noTasksHere => '여기에 작업이 없습니다';

  @override
  String get noUpcomingTasks => '날짜가 지정된 작업이 없습니다';

  @override
  String get noTasksForDay => '이 날에 예정된 작업이 없습니다';

  @override
  String failedToLoadTasks(Object error) {
    return '작업을 불러오지 못했습니다: $error';
  }

  @override
  String get searchTasks => '작업 검색';

  @override
  String get searchStartTyping => '입력하여 작업 검색';

  @override
  String get searchNoMatches => '일치하는 작업이 없습니다';

  @override
  String failedToSearchTasks(Object error) {
    return '작업을 검색하지 못했습니다: $error';
  }

  @override
  String get previousMonth => '이전 달';

  @override
  String get nextMonth => '다음 달';

  @override
  String get clearDateFilter => '날짜 필터 지우기';

  @override
  String get weekMon => '월';

  @override
  String get weekTue => '화';

  @override
  String get weekWed => '수';

  @override
  String get weekThu => '목';

  @override
  String get weekFri => '금';

  @override
  String get weekSat => '토';

  @override
  String get weekSun => '일';

  @override
  String get browseTitle => '둘러보기';

  @override
  String get unifiedAccount => '통합 계정';

  @override
  String accountUnavailable(Object error) {
    return '계정을 사용할 수 없습니다: $error';
  }

  @override
  String get signOut => '로그아웃';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountConfirmation =>
      '계정, 클라우드 데이터, 로컬 작업, 프로젝트, 집중 기록이 영구적으로 삭제됩니다. 되돌릴 수 없습니다. 스토어 구독은 자동으로 해지되지 않습니다. Apple로 로그인을 사용했다면 Apple 계정 설정에서 Pomodoist 접근 권한을 별도로 취소하세요.';

  @override
  String get manageSignInWithApple => 'Apple로 로그인 관리';

  @override
  String get deleteAccountFinalConfirmation => '정말 확실한가요? 마지막 확인입니다.';

  @override
  String deleteAccountError(Object error) {
    return '계정을 삭제하지 못했습니다: $error';
  }

  @override
  String get accountDeleted => '계정이 삭제되었습니다.';

  @override
  String get accountDeletedLocalCleanupError =>
      '계정은 삭제되었지만 로컬 데이터를 지우지 못했습니다. 이 기기를 다시 사용하기 전에 앱 데이터를 지우세요.';

  @override
  String get browseSevenDays => '7일';

  @override
  String get browseOpenNow => '현재 미완료';

  @override
  String get browseQueueLoading => '대기 중인 변경 사항 불러오는 중…';

  @override
  String get browseQueueUnavailable => '대기 중인 변경 사항을 불러오지 못했습니다.';

  @override
  String get browseQueueExplanation =>
      '전송을 기다리는 로컬 변경 사항을 표시합니다. 대기열이 비어 있어도 모든 기기가 최신 상태임을 의미하지는 않습니다.';

  @override
  String get productivityTitle => '생산성';

  @override
  String get achievementsTitle => '업적';

  @override
  String get allTimeLabel => '전체 기간';

  @override
  String get lastSevenDaysLabel => '최근 7일';

  @override
  String get noWeeklyStatsLabel => '아직 집중 또는 작업 데이터가 없습니다';

  @override
  String get completedFocuses => '완료한 집중';

  @override
  String get completedTasks => '완료한 작업';

  @override
  String get unlocked => '달성';

  @override
  String get locked => '미달성';

  @override
  String get progressLabel => '진행 상황';

  @override
  String get focusAchievements => '집중 업적';

  @override
  String get taskAchievements => '작업 업적';

  @override
  String get comboAchievements => '콤보 업적';

  @override
  String get focusIntervals => '집중 구간';

  @override
  String get focusTime => '집중 시간';

  @override
  String get openTasks => '미완료 작업';

  @override
  String get plannedIntervals => '계획된 구간';

  @override
  String get labelsTitle => '라벨';

  @override
  String get newProject => '새 프로젝트';

  @override
  String get newLabel => '새 라벨';

  @override
  String get syncReadyQueue => '동기화 대기열';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '대기 중인 로컬 명령 $count개',
      one: '대기 중인 로컬 명령 1개',
      zero: '대기 중인 로컬 명령 없음',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return '프로젝트를 불러오지 못했습니다: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return '라벨을 불러오지 못했습니다: $error';
  }

  @override
  String get addProject => '프로젝트 추가';

  @override
  String get projectName => '프로젝트 이름';

  @override
  String get addLabel => '라벨 추가';

  @override
  String get labelName => '라벨 이름';

  @override
  String couldNotAddLabel(Object error) {
    return '라벨을 추가하지 못했습니다: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return '프로젝트를 사용할 수 없습니다: $error';
  }

  @override
  String get projectsUnavailableShort => '프로젝트를 사용할 수 없습니다';

  @override
  String get noProjects => '프로젝트 없음';

  @override
  String get searchProjects => '프로젝트 검색';

  @override
  String get searchLabels => '라벨 검색';

  @override
  String get archivedProjectsOnly => '보관된 프로젝트만';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '프로젝트 $count개',
      one: '프로젝트 1개',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => '라벨 없음';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '라벨 $count개',
      one: '라벨 1개',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => '프로젝트 이름 변경';

  @override
  String get deleteProject => '프로젝트 삭제';

  @override
  String get deleteLabel => '라벨 삭제';

  @override
  String deleteProjectConfirmation(String name) {
    return '\"$name\"을(를) 삭제할까요? 이 프로젝트의 작업은 받은 편지함으로 이동합니다.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return '\"$name\"을(를) 삭제할까요?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return '프로젝트를 삭제하지 못했습니다: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return '라벨을 삭제하지 못했습니다: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return '프로젝트: $count';
  }

  @override
  String get collapseProjects => '프로젝트 접기';

  @override
  String get expandProjects => '프로젝트 펼치기';

  @override
  String get projectFallbackTitle => '프로젝트';

  @override
  String get projectSubtitle => '목록 보기입니다. 보드와 캘린더는 향후 제공 예정입니다.';

  @override
  String get reportsTitle => '보고서';

  @override
  String get reportsFocusedDay => '오늘도 집중하고 있어요';

  @override
  String get reportsThisWeek => '이번 주 집중';

  @override
  String get reportsNextAchievement => '다음 업적';

  @override
  String get viewAllAchievements => '모든 업적 보기';

  @override
  String viewAllAchievementsCount(int count) {
    return '$count개 모두 보기';
  }

  @override
  String get allAchievementsUnlocked => '모든 업적 달성';

  @override
  String get noAchievementsYet => '아직 업적이 없습니다';

  @override
  String failedToLoadAchievements(Object error) {
    return '업적을 불러오지 못했습니다: $error';
  }

  @override
  String get backToReports => '보고서로 돌아가기';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '집중 구간 $completed/$target회 완료';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '집중 구간 $completed회 완료, 목표 미설정';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return '최근 7일 집중 시간: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return '보고서를 불러오지 못했습니다: $error';
  }

  @override
  String get taskNotFound => '작업을 찾을 수 없습니다';

  @override
  String get taskTitleHint => '작업 제목';

  @override
  String get taskComment => '댓글';

  @override
  String get taskCommentHint => '댓글 추가';

  @override
  String get subtasks => '하위 작업';

  @override
  String get addSubtask => '하위 작업 추가';

  @override
  String get addSubtaskHint => '하위 작업 추가';

  @override
  String get noSubtasks => '아직 하위 작업이 없습니다.';

  @override
  String get makeParentTask => '상위 작업으로 만들기';

  @override
  String couldNotMoveTask(Object error) {
    return '작업을 이동하지 못했습니다: $error';
  }

  @override
  String get scheduleTitle => '일정';

  @override
  String get allDay => '종일';

  @override
  String get timedBlock => '시간 블록';

  @override
  String get recurrenceTitle => '반복';

  @override
  String get recurrenceNeedsSchedule => '반복하기 전에 날짜 또는 시간을 추가하세요.';

  @override
  String get recurrenceIntervalLabel => '간격';

  @override
  String get recurrenceUnitDay => '일';

  @override
  String get recurrenceUnitWeek => '주';

  @override
  String get recurrenceUnitMonth => '개월';

  @override
  String get recurrenceInvalidInterval => '1~999를 입력하세요.';

  @override
  String recurrenceEveryDays(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval일마다',
      one: '매일',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval주마다',
      one: '매주',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval개월마다',
      one: '매월',
    );
    return '$_temp0';
  }

  @override
  String get noDate => '날짜 없음';

  @override
  String get calendarNotLinked => '캘린더 연결 안 됨';

  @override
  String get calendarLinked => 'Google Calendar 연결됨';

  @override
  String focusProgress(int completed, int total) {
    return '집중 $completed/$total';
  }

  @override
  String get startFocus => '집중 시작';

  @override
  String get focusStarted => '집중 시작됨';

  @override
  String get taskReopened => '작업 다시 열림';

  @override
  String get taskCompleted => '작업 완료됨';

  @override
  String get taskDeleted => '작업 삭제됨';

  @override
  String get recurringDeleteTitle => '반복 작업을 삭제할까요?';

  @override
  String get recurringDeleteMessage => '이 작업은 반복 시리즈에 속합니다.';

  @override
  String get recurringDeleteThis => '이 작업 삭제';

  @override
  String get recurringDeleteThisAndFollowing => '이 작업 및 이후 작업 삭제';

  @override
  String get markOpen => '미완료로 표시';

  @override
  String get markComplete => '완료로 표시';

  @override
  String get focusHistory => '집중 기록';

  @override
  String failedToLoadTask(Object error) {
    return '작업을 불러오지 못했습니다: $error';
  }

  @override
  String get noFocusIntervals => '아직 집중 구간이 없습니다.';

  @override
  String get today => '오늘';

  @override
  String get tomorrow => '내일';

  @override
  String get yesterday => '어제';

  @override
  String get clearDate => '날짜 지우기';

  @override
  String priority(int priority) {
    return '우선순위 $priority';
  }

  @override
  String get focusTitle => '집중';

  @override
  String focusLoadError(Object error) {
    return '집중을 불러오지 못했습니다: $error';
  }

  @override
  String get focusViewFull => '전체';

  @override
  String get focusViewMinimal => '최소';

  @override
  String get focusSwitchToFullView => '전체 보기로 전환';

  @override
  String get focusSwitchToMinimalView => '최소 보기로 전환';

  @override
  String get focusActionFailed => '집중을 업데이트하지 못했습니다. 다시 시도하세요.';

  @override
  String get noActiveSession => '활성 세션 없음';

  @override
  String get focusIdleSubtitle => '독립 집중 구간을 시작하거나 작업에서 집중을 시작하세요.';

  @override
  String get noPreset => '프리셋 없음';

  @override
  String get preparingFocus => '집중 준비 중';

  @override
  String get moreFocusOptions => '집중 옵션 더 보기';

  @override
  String get moreFocusActions => '집중 동작 더 보기';

  @override
  String get preset => '프리셋';

  @override
  String get newPreset => '새 프리셋';

  @override
  String get customize => '사용자화';

  @override
  String get customizePreset => '프리셋 사용자화';

  @override
  String get startInterval => '구간 시작';

  @override
  String get intervalStarted => '구간 시작됨';

  @override
  String get intervalCompleted => '구간 완료됨';

  @override
  String get focusStopped => '집중 중지됨';

  @override
  String get focusCompletionTitle => '정말 잘했어요!';

  @override
  String get focusCompletionLinkedSubtitle => '이 작업에 계획된 모든 집중 구간을 완료했습니다.';

  @override
  String get focusCompletionStandaloneSubtitle => '집중 주기를 완료했습니다.';

  @override
  String get focusCompletionQuestion => '이 작업을 완료할 준비가 되었나요?';

  @override
  String get focusCompletionCompleteTask => '작업 완료';

  @override
  String get focusCompletionKeepOpen => '작업 미완료로 유지';

  @override
  String get focusCompletionDone => '완료';

  @override
  String get focusCompletionNextTask => '다음 예정 작업';

  @override
  String focusCompletionTaskError(Object error) {
    return '작업을 완료하지 못했습니다: $error';
  }

  @override
  String get completeInterval => '구간 완료';

  @override
  String get logDistraction => '방해 요소 기록';

  @override
  String get workInterval => '작업 구간';

  @override
  String get work => '작업';

  @override
  String get shortBreak => '짧은 휴식';

  @override
  String get breakLabel => '휴식';

  @override
  String get longBreak => '긴 휴식';

  @override
  String readyLabel(String label) {
    return '준비됨: $label';
  }

  @override
  String get readyShort => '준비됨';

  @override
  String focusTimerTotal(String duration) {
    return '전체 $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return '세션 $current/$total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return '집중 리듬 미리보기, $count단계';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return '집중 리듬, $current/$total단계: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, 남은 시간 $remaining, 전체 $total';
  }

  @override
  String get focusStatusRunning => '실행 중';

  @override
  String get focusStatusPaused => '일시 정지됨';

  @override
  String focusWorkProgress(int completed, int total) {
    return '작업 $completed/$total';
  }

  @override
  String intervalNumber(int number) {
    return '구간 $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '작업 $completed/$total - 구간 $number';
  }

  @override
  String get pause => '일시 정지';

  @override
  String get resume => '재개';

  @override
  String get presetForNextIntervals => '다음 구간용 프리셋';

  @override
  String usePreset(String name) {
    return '$name 사용';
  }

  @override
  String minutesWork(int minutes) {
    return '작업 $minutes분';
  }

  @override
  String minutesShort(int minutes) {
    return '짧은 휴식 $minutes분';
  }

  @override
  String minutesLong(int minutes) {
    return '긴 휴식 $minutes분';
  }

  @override
  String longEvery(int count) {
    return '$count회마다 긴 휴식';
  }

  @override
  String get autoBreaks => '자동 휴식';

  @override
  String get autoWork => '자동 작업';

  @override
  String get noPause => '일시 정지 없음';

  @override
  String get focusPauseUnavailable => '이 프리셋에서는 일시 정지할 수 없습니다';

  @override
  String get strict => '엄격';

  @override
  String get flexible => '유연';

  @override
  String get name => '이름';

  @override
  String get workField => '작업';

  @override
  String get shortField => '짧은 휴식';

  @override
  String get longField => '긴 휴식';

  @override
  String get every => '주기';

  @override
  String get minutesSuffix => '분';

  @override
  String get makeDefault => '기본값으로 설정';

  @override
  String get autoStartBreaks => '휴식 자동 시작';

  @override
  String get autoStartWork => '작업 자동 시작';

  @override
  String get allowPause => '일시 정지 허용';

  @override
  String get strictMode => '엄격 모드';

  @override
  String get nameRequired => '이름이 필요합니다';

  @override
  String get nameMustBeUnique => '이름은 고유해야 합니다';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'Pomodoist 캘린더의 양방향 동기화가 활성화되어 있습니다.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Google 계정을 연결하여 예정된 작업을 동기화하세요.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      '다른 기기에서 Google Calendar 동기화가 실행 중입니다. Pomodoist 데이터는 여기서도 동기화됩니다.';

  @override
  String get syncNow => '지금 동기화';

  @override
  String get useThisDevice => '이 기기 사용';

  @override
  String get connect => '연결';

  @override
  String get disconnect => '연결 해제';

  @override
  String failedToLoadIntegration(Object error) {
    return '연동을 불러오지 못했습니다: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Calendar 오류: $message';
  }

  @override
  String get googleAuthRequired =>
      'Google Calendar 승인이 필요합니다. 다시 로그인하고 지금 동기화를 실행하세요.';

  @override
  String get googleSignInNotConfigured =>
      'Google 로그인이 구성되지 않았습니다. 이 iOS 대상에 GOOGLE_CLIENT_ID와 GOOGLE_REVERSED_CLIENT_ID를 설정하세요.';

  @override
  String get googleCallbackNotConfigured =>
      'Google 로그인 콜백이 구성되지 않았습니다. ios/Flutter/GoogleOAuth.xcconfig에 GOOGLE_REVERSED_CLIENT_ID를 설정하세요.';

  @override
  String get googleWebButtonFirst => '웹에서는 먼저 Google 로그인 버튼을 누른 후 연결을 누르세요.';

  @override
  String get googleAccessDenied =>
      'Google 접근이 거부되었습니다. 이 Google 계정을 OAuth 테스트 사용자로 추가하거나 OAuth 앱을 게시하고 검증하세요.';

  @override
  String get status => '상태';

  @override
  String get account => '계정';

  @override
  String get calendar => '캘린더';

  @override
  String get calendarId => '캘린더 ID';

  @override
  String get lastSync => '마지막 동기화';

  @override
  String get notConnected => '연결 안 됨';

  @override
  String get notCreated => '생성 안 됨';

  @override
  String get never => '없음';

  @override
  String durationMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours시간 $minutes분';
  }

  @override
  String get projectIcon => '프로젝트 아이콘';

  @override
  String projectIconOption(int number) {
    return '아이콘 $number';
  }

  @override
  String get projectColor => '프로젝트 색상';

  @override
  String projectColorOption(int number) {
    return '색상 $number';
  }

  @override
  String get addProjectToFavorites => '즐겨찾기에 프로젝트 추가';

  @override
  String get removeProjectFromFavorites => '즐겨찾기에서 프로젝트 제거';

  @override
  String get timelineProjectsMenu => '타임라인 프로젝트 관리';

  @override
  String get timelineShowProject => '타임라인에 프로젝트 표시';

  @override
  String get timelineHideProject => '임시 프로젝트 숨기기';

  @override
  String get timelineCollapseProject => '프로젝트 분기 접기';

  @override
  String get timelineExpandProject => '프로젝트 분기 펼치기';

  @override
  String get timelineCurrentTime => '현재 시간';

  @override
  String couldNotUpdateProject(Object error) {
    return '프로젝트를 업데이트하지 못했습니다: $error';
  }

  @override
  String get commonDone => '완료';

  @override
  String get taskSelect => '선택';

  @override
  String taskSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 선택됨',
      one: '1개 선택됨',
      zero: '0개 선택됨',
    );
    return '$_temp0';
  }

  @override
  String get taskSelectAll => '모두 선택';

  @override
  String get taskDeselectAll => '모두 선택 해제';

  @override
  String get taskDue => '기한';

  @override
  String get taskProject => '프로젝트';

  @override
  String get taskLabels => '라벨';

  @override
  String get taskPriority => '우선순위';

  @override
  String get taskMore => '더 보기';

  @override
  String get taskSchedule => '일정';

  @override
  String get taskMove => '이동';

  @override
  String get taskDuplicate => '복제';

  @override
  String get taskDuplicateTitle => '작업 복제';

  @override
  String get taskDuplicateSelectedOnly => '선택 항목만';

  @override
  String get taskDuplicateWithSubtasks => '하위 작업 포함';

  @override
  String get taskWeekend => '이번 주말';

  @override
  String get taskNextWeek => '다음 주';

  @override
  String get taskEnterDue => '기한 날짜 또는 시간 입력';

  @override
  String get taskInvalidDue => '유효한 날짜 또는 시간을 입력하세요';

  @override
  String get taskClearDue => '기한 지우기';

  @override
  String get taskDeleteSelectedTitle => '선택한 작업을 삭제할까요?';

  @override
  String get taskDeleteSelectedMessage => '7초 동안 이 작업을 실행 취소할 수 있습니다.';

  @override
  String get taskCompleteSelected => '선택 항목 완료';

  @override
  String get taskReopenSelected => '선택 항목 다시 열기';

  @override
  String taskActionFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '작업 $count개를 업데이트하지 못했습니다',
      one: '작업 1개를 업데이트하지 못했습니다',
    );
    return '$_temp0';
  }

  @override
  String get voiceCollapse => '음성 패널 접기';

  @override
  String get voiceExpand => '음성 패널 펼치기';

  @override
  String get voiceMovePanel => '음성 패널 이동';

  @override
  String get themeClassic => '클래식';

  @override
  String get themeOcean => '오션';

  @override
  String get themeForest => '포레스트';

  @override
  String get themeCustomize => '사용자화';

  @override
  String get themeEditorTitle => '테마 편집';

  @override
  String get themeLivePreview => '변경 사항은 앱 전체에 표시됩니다. 취소하면 이전 테마로 복원됩니다.';

  @override
  String get themeSaveError => '테마를 저장하지 못했습니다. 변경 사항은 유지됩니다. 다시 시도하세요.';

  @override
  String get themeLoadError => '테마를 불러오지 못했습니다.';

  @override
  String get themeColorsSurfaces => '배경 및 표면';

  @override
  String get themeColorsText => '텍스트';

  @override
  String get themeColorsAccent => '강조';

  @override
  String get themeColorsStatus => '상태 색상';

  @override
  String get themeInvalidHex => '6자리 HEX 색상을 입력하세요. 예: #2563EB.';

  @override
  String get themeLowContrast => '대비가 낮아 일부 텍스트를 읽기 어려울 수 있습니다.';

  @override
  String get themePreviewTask => '하루 계획하기';

  @override
  String get themePreviewSecondary => '매일 조금씩 집중하세요.';

  @override
  String get themeColorCanvas => '배경';

  @override
  String get themeColorSurface => '표면';

  @override
  String get themeColorSurfaceTint => '보조 표면';

  @override
  String get themeColorSurfaceHover => '마우스를 올린 표면';

  @override
  String get themeColorPrimaryText => '기본 텍스트';

  @override
  String get themeColorSecondaryText => '보조 텍스트';

  @override
  String get themeColorMutedText => '흐린 텍스트';

  @override
  String get themeColorBorder => '테두리';

  @override
  String get themeColorAccent => '강조 텍스트 및 아이콘';

  @override
  String get themeColorAccentFill => '강조 채우기';

  @override
  String get themeColorAccentTint => '옅은 강조 채우기';

  @override
  String get themeColorWarning => '경고';

  @override
  String get themeColorInfo => '정보';

  @override
  String get themeColorSuccess => '성공';

  @override
  String get themeColorError => '오류';

  @override
  String get themeColorOverdue => '기한 지남';

  @override
  String get themeColorOnAccent => '강조 배경 위 텍스트';

  @override
  String get themeColorOnError => '오류 배경 위 텍스트';

  @override
  String todayTaskSummary(int tasks, int planned, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      tasks,
      locale: localeName,
      other: '작업 $tasks개',
      one: '작업 1개',
    );
    String _temp1 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '계획된 세션 $planned회',
      one: '계획된 세션 1회',
    );
    return '$_temp0 · $_temp1 · 집중 $time';
  }

  @override
  String get todayFocusingOn => '집중 중인 작업';

  @override
  String get openFocus => '집중 열기';

  @override
  String todayCompletedTasks(int count) {
    return '오늘 완료 · $count';
  }

  @override
  String get sidebarDaily => '일일';

  @override
  String get sidebarViews => '보기';

  @override
  String get quickAddResetDetails => '기본값 사용';

  @override
  String get quickAddChangeTime => '시간 변경';

  @override
  String get quickAddProjectNameUnsupported => '이 프로젝트 이름은 변경하지 않고 삽입할 수 없습니다.';

  @override
  String get themeSepia => '세피아';

  @override
  String get themeGraphite => '그래파이트';

  @override
  String get themeCustom => '사용자 지정';

  @override
  String get themeResetToClassic => '클래식으로 재설정';

  @override
  String get themeBackgroundKindTitle => '배경';

  @override
  String get themeBackgroundColor => '색상';

  @override
  String get themeBackgroundPhoto => '사진';

  @override
  String get themeBackgroundGlass => 'macOS 유리';

  @override
  String get themeBackgroundGlassHint =>
      '앱 전체와 빠른 추가에 적용됩니다. 흐림은 macOS가 제어하며 슬라이더는 팔레트 색조를 조절합니다.';

  @override
  String get themeBackgroundGlassUnavailable =>
      'macOS 앱에서 사용할 수 있습니다. 이 플랫폼에서는 단색 배경을 사용합니다.';

  @override
  String get themeBackgroundTitle => '배경 이미지';

  @override
  String get themeBackgroundMainOnly => '기본 영역만';

  @override
  String get themeBackgroundWholeApp => '앱 전체';

  @override
  String get themeBackgroundSeparate => '개별 배경';

  @override
  String get themeBackgroundMain => '기본 영역';

  @override
  String get themeBackgroundSidebar => '사이드바';

  @override
  String get themeBackgroundQuickAdd => '빠른 추가';

  @override
  String get themeBackgroundChoose => '사진 선택';

  @override
  String get themeBackgroundReplace => '사진 바꾸기';

  @override
  String get themeBackgroundRemove => '사진 제거';

  @override
  String get themeBackgroundDim => '어둡게';

  @override
  String get themeBackgroundBlur => '흐림';

  @override
  String get themeBackgroundEmpty => '사진 없음';

  @override
  String get themeBackgroundImageError => '이미지를 열지 못했습니다. 다른 사진을 선택하세요.';

  @override
  String get themeBackgroundTooLarge => '50MB 이하의 이미지를 선택하세요.';

  @override
  String get themeBackgroundLoading => '이미지 준비 중…';

  @override
  String get settingsTaskListStyle => '작업 행 스타일';

  @override
  String get settingsTaskListStyleDescription =>
      '새 레이아웃을 선택하거나 익숙한 클래식 행을 유지하세요.';

  @override
  String get settingsTaskListModern => '모던';

  @override
  String get settingsTaskListClassic => '클래식';

  @override
  String get settingsTaskRowSpacing => '작업 간격';

  @override
  String get settingsTaskRowSpacingCompact => '좁게';

  @override
  String get settingsTaskRowSpacingComfortable => '보통';

  @override
  String get settingsTaskRowSpacingSpacious => '넓게';

  @override
  String get settingsSaveError => '설정을 저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get focusCompletionCompleteAndNext => '완료하고 다음 시작';

  @override
  String get focusCompletionStartNext => '다음 작업 시작';

  @override
  String get focusCompletionRetry => '다시 시도';

  @override
  String get searchAllProjects => '모든 프로젝트';

  @override
  String get searchStatusOpen => '미완료';

  @override
  String get searchStatusCompleted => '완료';

  @override
  String get searchStatusAll => '모든 상태';

  @override
  String get searchClearFilters => '필터 지우기';

  @override
  String get searchEmptyDescription => '제목이나 설명으로 작업을 찾은 후 프로젝트나 상태로 좁혀 보세요.';

  @override
  String get searchNoMatchesDescription =>
      '다른 문구를 입력하거나 필터를 지워 보세요. 이 텍스트를 새 작업으로 만들 수도 있습니다.';

  @override
  String get searchCreateTask => '텍스트로 작업 만들기';

  @override
  String get taskListLoadError => '작업을 불러오지 못했습니다. 다시 시도하세요.';

  @override
  String get inboxEmptyTitle => '받은 편지함이 비어 있습니다';

  @override
  String get inboxEmptyDescription => '여기에 아이디어를 기록하고 언제 할지는 나중에 정하세요.';

  @override
  String get todayEmptyTitle => '오늘 예정된 작업이 없습니다';

  @override
  String get todayEmptyDescription => '작업을 추가하여 하루를 시작하세요.';

  @override
  String get todayEmptyCompletedTitle => '오늘 목록을 모두 완료했습니다';

  @override
  String get todayEmptyCompletedDescription =>
      '완료한 작업은 아래에 저장되어 있습니다. 준비되면 다른 작업을 추가하세요.';

  @override
  String get projectEmptyTitle => '이 프로젝트에는 아직 작업이 없습니다';

  @override
  String get projectEmptyDescription => '프로젝트 목표를 향한 첫 단계를 추가하세요.';

  @override
  String get commandSearchPlaceholder => '작업, 프로젝트, 동작 검색';

  @override
  String get commandSearchTasks => '작업';

  @override
  String get commandSearchActions => '동작';

  @override
  String get commandSearchDictateTask => '작업 말하기';

  @override
  String get commandSearchAllResults => '모든 결과 보기';

  @override
  String get commandSearchHint => '↑ ↓ 이동 · Enter 열기 · Esc 닫기';

  @override
  String get commandSearchNoMatches => '일치하는 작업이나 프로젝트가 없습니다.';

  @override
  String get overdueTitle => '기한 지남';

  @override
  String overdueTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '기한이 지난 작업 $count개',
      one: '기한이 지난 작업 $count개',
    );
    return '$_temp0';
  }

  @override
  String get overdueReview => '검토';

  @override
  String get overdueEmpty => '기한이 지난 작업이 없습니다';

  @override
  String get taskFocusSwitchTitle => '집중을 전환할까요?';

  @override
  String taskFocusSwitchMessage(String task) {
    return '현재 세션이 중지됩니다. “$task”에 집중을 시작할까요?';
  }

  @override
  String get taskFocusSwitchConfirm => '전환';

  @override
  String get labelIcon => '라벨 아이콘';

  @override
  String get labelUpdateFailed => '라벨을 업데이트하지 못했습니다. 다시 시도하세요.';

  @override
  String get labelNotFound => '라벨을 찾을 수 없습니다';

  @override
  String get labelTasksSubtitle => '모든 프로젝트에서 이 라벨이 있는 작업';

  @override
  String labelIconOption(String icon) {
    String _temp0 = intl.Intl.selectLogic(icon, {
      'tag': '태그',
      'bookmark': '북마크',
      'flag': '깃발',
      'bolt': '번개',
      'lightbulb': '전구',
      'clock': '시계',
      'bell': '벨',
      'pin': '핀',
      'phone': '전화',
      'mail': '메일',
      'link': '링크',
      'wrench': '렌치',
      'other': '태그',
    });
    return '$_temp0';
  }

  @override
  String get addSubproject => '하위 프로젝트 만들기';

  @override
  String get moveProject => '프로젝트 이동';

  @override
  String get projectTopLevel => '최상위';

  @override
  String get projectMoveUp => '위로 이동';

  @override
  String get projectMoveDown => '아래로 이동';

  @override
  String projectParentName(String name) {
    return '상위 프로젝트: $name';
  }

  @override
  String deleteProjectWithChildrenConfirmation(String name) {
    return '\"$name\"을(를) 삭제할까요? 하위 프로젝트는 한 단계 위로 이동합니다. 이 프로젝트의 작업만 받은 편지함으로 이동합니다.';
  }

  @override
  String get accountNickname => '닉네임';

  @override
  String get accountChangeNickname => '닉네임 변경';

  @override
  String get accountNicknameSaveError => '닉네임을 저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get notificationTaskStarting => '작업 시작';

  @override
  String get notificationReturnTitle => '토마토가 당신을 기다려요';

  @override
  String get notificationReturnBody => '집중 한 번이나 작업 하나 완료면 오늘도 알찬 하루가 됩니다.';

  @override
  String get notificationFocusChannel => '집중';

  @override
  String get notificationFocusDescription => '집중 구간 완료 알림';

  @override
  String get notificationReturnChannel => '복귀 알림';

  @override
  String get notificationReturnDescription => 'Pomodoist로 돌아오도록 가볍게 알려 드립니다';

  @override
  String get notificationTaskChannel => '작업 시작';

  @override
  String get notificationTaskDescription => '작업 시작 알림';

  @override
  String get notificationOpenApp => 'Pomodoist 열기';

  @override
  String get notificationFocusCompleted => '집중 구간 완료';

  @override
  String get notificationLongBreakCompleted => '긴 휴식 완료';

  @override
  String get notificationBreakCompleted => '휴식 완료';

  @override
  String get updateTitle => 'Pomodoist 업데이트';

  @override
  String get updateAction => '업데이트';

  @override
  String get updateCheck => '업데이트 확인';

  @override
  String get updateSettings => '업데이트';

  @override
  String get updateReceiveRc => '출시 후보(RC) 받기';

  @override
  String get updateStableChannel => '채널: 안정 버전';

  @override
  String get updateRcChannel => '채널: 안정 버전 및 RC';

  @override
  String get updateRcHelp => 'RC 버전에는 버그가 있을 수 있습니다. 알파 및 베타 버전은 제외됩니다.';

  @override
  String get updateRestart => '앱이 다시 시작됩니다. 데이터는 유지됩니다.';

  @override
  String get updateNotes => '릴리스 노트';

  @override
  String get updateOwnerManaged =>
      '이 빌드는 서버 구성을 유지하기 위해 소유자가 업데이트합니다. 소유자에게 최신 버전을 요청하세요.';

  @override
  String get updateUnsupported =>
      '공식 Linux AppImage에서 자동 업데이트를 사용할 수 있습니다. 다른 빌드는 패키지 관리자를 사용하세요.';

  @override
  String updateVersion(String value) {
    return '버전 $value';
  }

  @override
  String get updatePhaseIdle => '언제든 확인할 수 있습니다.';

  @override
  String get updatePhaseChecking => '버전 확인 중…';

  @override
  String get updatePhaseAvailable => '새 버전을 사용할 수 있습니다';

  @override
  String get updatePhaseDownloading => '업데이트 다운로드 중…';

  @override
  String get updatePhaseVerifying => '무결성 확인 중…';

  @override
  String get updatePhaseInstalling => '설치 및 재시작 준비 중…';

  @override
  String get updatePhaseUpToDate => '최신 호환 버전을 사용하고 있습니다.';

  @override
  String get updatePhaseFailed => '업데이트를 완료하지 못했습니다';

  @override
  String achievementFocusSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '작업 집중 $count회 완료',
      one: '작업 집중 1회 완료',
    );
    return '$_temp0';
  }

  @override
  String achievementTaskSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '작업 $count개 완료',
      one: '작업 1개 완료',
    );
    return '$_temp0';
  }

  @override
  String get achievementDayNotWastedSubtitle => '하루에 집중 한 번과 작업 하나 완료';

  @override
  String get achievementFocusPlusCheckSubtitle => '하루에 집중 3회와 작업 3개 완료';

  @override
  String get achievementNoFussSubtitle => '하루에 중단 없이 집중 5회 완료';

  @override
  String get achievementCleanEntrySubtitle => '연결된 집중 후 작업 완료';

  @override
  String get achievementTomatoClosedSubtitle => '작업 집중을 한 날에 해당 작업 완료';

  @override
  String achievementTitle(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'focus_1': '첫 토마토',
      'focus_5': '준비 운동',
      'focus_10': '집중 포착',
      'focus_25': '토마토 근무',
      'focus_50': '모드 가동',
      'focus_100': '빨간 띠',
      'focus_250': '깊은 뿌리',
      'focus_500': '타이머의 권위자',
      'focus_1000': '천 번째 토마토',
      'focus_5000': '집중 농부',
      'focus_10000': '주의력 농장',
      'focus_50000': '토마토 제국',
      'focus_100000': '붉은 초지능',
      'focus_1000000': '토마토 특이점',
      'task_1': '첫 체크',
      'task_5': '목록이 흔들렸다',
      'task_10': '행복한 체크박스',
      'task_25': '쌓인 일 정리',
      'task_50': '체크의 달인',
      'task_100': '마무리 해결사',
      'task_250': '목록 장악',
      'task_500': '사무실 완승',
      'task_1000': '천 개의 체크',
      'task_5000': '승리의 기록관',
      'task_10000': '체크 머신',
      'task_50000': '문제 해결국',
      'task_100000': '목록의 지배자',
      'task_1000000': '마지막 체크',
      'combo_day_not_wasted': '알찬 하루',
      'combo_focus_plus_check': '집중 + 체크',
      'combo_no_fuss': '차분하게',
      'combo_clean_entry': '깔끔한 시작',
      'combo_tomato_closed_question': '토마토가 해결했다',
      'other': '업적',
    });
    return '$_temp0';
  }

  @override
  String get focusPresetDeepWork => '깊은 작업';

  @override
  String get focusPresetShortSprint => '짧은 스프린트';

  @override
  String csvImportIssueRow(int row, String message) {
    return '$row행: $message';
  }

  @override
  String csvImportIssueMessage(String code, String value) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'fileTooLarge': 'CSV 파일이 16MiB를 초과합니다.',
      'invalidUtf8': 'CSV는 유효한 UTF-8이어야 합니다.',
      'missingHeader': 'CSV 헤더가 없습니다.',
      'malformed': 'CSV 형식이 잘못되었습니다.',
      'unknownHeader': '알 수 없는 헤더 \"$value\"입니다.',
      'duplicateHeader': '헤더 \"$value\"가 중복됩니다.',
      'contentHeaderRequired': 'content 헤더가 필요합니다.',
      'tooManyTasks': 'CSV에는 작업을 1000개까지만 포함할 수 있습니다.',
      'tooManyFields': '행의 필드 수가 헤더보다 많습니다.',
      'contentRequired': 'content가 필요합니다.',
      'invalidPriority': 'priority는 1~4의 정수여야 합니다.',
      'invalidDate': '$value는 YYYY-MM-DD 형식이어야 합니다.',
      'mixedSchedule': '기한 날짜와 시간 지정 일정을 함께 사용할 수 없습니다.',
      'timedFieldsRequired': '시간 지정 일정에는 start_at, end_at, time_zone이 필요합니다.',
      'invalidTimestamp': '$value는 명시적인 UTC 오프셋이 있는 RFC3339 형식이어야 합니다.',
      'invalidTimeZone': 'time_zone은 유효한 IANA 이름이어야 합니다.',
      'endBeforeStart': 'end_at은 start_at 이후여야 합니다.',
      'invalidRecurrence': 'recurrence는 day, week 또는 month여야 합니다.',
      'invalidInteger': '$value는 1~999의 정수여야 합니다.',
      'intervalWithoutRecurrence': 'recurrence_interval에는 recurrence가 필요합니다.',
      'recurrenceWithoutSchedule': 'recurrence에는 일정이 필요합니다.',
      'doneTask': '완료된 작업은 가져올 수 없습니다.',
      'invalidKey': '$value 형식이 잘못되었습니다.',
      'empty': 'CSV에 작업이 없습니다.',
      'duplicateKey': '키 \"$value\"가 중복됩니다.',
      'parentCycle': 'parent_key 참조가 순환합니다.',
      'missingParent': 'parent_key \"$value\"가 없습니다.',
      'childProject': '하위 작업은 상위 작업과 같은 프로젝트를 사용해야 합니다.',
      'other': '파일을 가져오지 못했습니다.',
    });
    return '$_temp0';
  }

  @override
  String billingOfferDays(int count) {
    return '$count일';
  }

  @override
  String billingOfferMonths(int count) {
    return '$count개월';
  }

  @override
  String billingOfferYears(int count) {
    return '$count년';
  }

  @override
  String billingTrialFree(String duration) {
    return '$duration 무료';
  }

  @override
  String billingTrialRenewal(String price) {
    return '이후 $price. 취소하지 않으면 자동 갱신됩니다.';
  }

  @override
  String get billingReturnBadge => 'Pro로 돌아가기';

  @override
  String billingReturnSubtitle(String duration, String price) {
    return '$duration 동안 할인 후 $price. 취소하지 않으면 자동 갱신됩니다.';
  }

  @override
  String billingReturnPending(String date) {
    return '할인이 $date까지 예약되어 있습니다. 구매를 취소했다면 이 시간 이후에 다시 시도할 수 있습니다.';
  }

  @override
  String get billingReturnFailed => '재가입 혜택을 확인하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get billingTryFree => '무료 체험';

  @override
  String get collaborationShareProject => '프로젝트 공유';

  @override
  String get collaborationShareIntro =>
      '이 프로젝트를 함께 작업할 사람을 초대하세요. 멤버는 편집할 수 있고, 관찰자는 볼 수만 있습니다.';

  @override
  String get collaborationShareStart => '공유';

  @override
  String get collaborationShareInProgress => '공유 중… 최근 변경 사항을 동기화하는 중';

  @override
  String get collaborationMembers => '멤버';

  @override
  String get collaborationPendingInvitations => '대기 중인 초대';

  @override
  String get collaborationRevoke => '취소';

  @override
  String get collaborationPublicLink => '공개 링크';

  @override
  String get collaborationPublicLinkHint => '링크가 있는 누구나 이 프로젝트를 볼 수 있습니다';

  @override
  String get collaborationCopyLink => '링크 복사';

  @override
  String get collaborationConflicts => '동기화 충돌';

  @override
  String get collaborationLeaveProject => '프로젝트 나가기';

  @override
  String get collaborationDeleteSharedProject => '모두에게서 삭제';

  @override
  String get collaborationMakePrivate => '비공개로 전환';

  @override
  String get collaborationOwner => '소유자';

  @override
  String get collaborationTransferOwnership => '소유권 이전';

  @override
  String get collaborationRemoveMember => '멤버 제거';

  @override
  String get collaborationEmail => '이메일';

  @override
  String get collaborationInvite => '초대';

  @override
  String get collaborationConflictHint => '다른 멤버도 이 항목을 변경했습니다';

  @override
  String get collaborationConflictKeepLocal => '내 변경 유지';

  @override
  String get collaborationConflictUseServer => '서버 버전 사용';

  @override
  String get collaborationProjectShared => '프로젝트를 공유했습니다';

  @override
  String get collaborationInviteEmailFailed => '초대는 저장되었지만 이메일을 보내지 못했습니다';

  @override
  String collaborationInviteSent(String email) {
    return '$email 님에게 초대를 보냈습니다';
  }

  @override
  String get collaborationInvitationRevoked => '초대를 취소했습니다';

  @override
  String get collaborationRoleUpdated => '역할을 업데이트했습니다';

  @override
  String collaborationRemoveConfirm(String name) {
    return '$name 님을 이 프로젝트에서 제거할까요?';
  }

  @override
  String get collaborationMemberRemoved => '멤버를 제거했습니다';

  @override
  String collaborationTransferConfirm(String name) {
    return '$name 님을 이 프로젝트의 소유자로 지정할까요?';
  }

  @override
  String get collaborationOwnershipTransferred => '소유권을 이전했습니다';

  @override
  String get collaborationLeaveConfirm => '이 공유 프로젝트에서 나갈까요?';

  @override
  String get collaborationLeftProject => '프로젝트에서 나갔습니다';

  @override
  String get collaborationDeleteSharedConfirm =>
      '이 공유 프로젝트를 모든 멤버에게서 삭제할까요? 되돌릴 수 없습니다.';

  @override
  String get collaborationSharedProjectDeleted => '공유 프로젝트를 삭제했습니다';

  @override
  String get collaborationMakePrivateConfirm => '이 프로젝트 공유를 중지할까요?';

  @override
  String get collaborationMakePrivateDescription =>
      '프로젝트와 콘텐츠가 개인 계정으로 돌아갑니다. 다른 참여자는 즉시 접근할 수 없게 됩니다.';

  @override
  String get collaborationProjectMadePrivate => '프로젝트가 다시 비공개가 되었습니다';

  @override
  String get collaborationLinkCopied => '링크를 복사했습니다';

  @override
  String get collaborationConflictResolved => '충돌을 해결했습니다';

  @override
  String get collaborationRoleAdministrator => '관리자';

  @override
  String get collaborationRoleMember => '멤버';

  @override
  String get collaborationRoleObserver => '관찰자';

  @override
  String get collaborationForbidden => '권한이 없습니다';

  @override
  String get collaborationSignedOut => '공유 프로젝트를 사용하려면 로그인하세요';

  @override
  String get collaborationUnavailable => '공유 프로젝트를 지금은 사용할 수 없습니다';

  @override
  String get collaborationError => '문제가 발생했습니다. 다시 시도하세요';

  @override
  String get collaborationSyncPending => '공유하기 전에 이 프로젝트의 동기화를 완료하세요';

  @override
  String get collaborationMemberFallback => '멤버';

  @override
  String get collaborationInboxTitle => '공유 프로젝트 및 초대';

  @override
  String get collaborationInboxSubtitle => '초대를 수락하고 공유 프로젝트 활동을 확인하세요';

  @override
  String get collaborationInvitations => '초대';

  @override
  String get collaborationNoInvitations => '대기 중인 초대가 없습니다';

  @override
  String get collaborationAccept => '수락';

  @override
  String get collaborationNotifications => '알림';

  @override
  String get collaborationMarkAllRead => '모두 읽음으로 표시';

  @override
  String get collaborationNoNotifications => '알림이 없습니다';

  @override
  String get collaborationNotificationInvitation => '공유 프로젝트 초대';

  @override
  String get collaborationNotificationDiscussion => '공유 프로젝트의 새 댓글';

  @override
  String get collaborationNotificationAssignment => '작업이 할당되었습니다';

  @override
  String get collaborationNotificationGeneric => '공유 프로젝트 활동';

  @override
  String get collaborationInvitationAccepted => '초대를 수락했습니다';

  @override
  String get collaborationAssignees => '담당자';

  @override
  String get collaborationEditAssignees => '담당자 편집';

  @override
  String get collaborationNoAssignees => '담당자 없음';

  @override
  String get collaborationComments => '댓글';

  @override
  String get collaborationCommentHint => '댓글 작성';

  @override
  String get collaborationCommentSend => '보내기';

  @override
  String get collaborationCommentDelete => '댓글 삭제';

  @override
  String get collaborationSharedBadge => '공유 프로젝트';

  @override
  String get collaborationJoinTitle => '프로젝트 초대';

  @override
  String get collaborationJoinDescription =>
      '공유 프로젝트에 초대되었습니다. 초대를 수락하면 프로젝트 목록에 추가됩니다.';

  @override
  String get collaborationJoinRole => '내 역할';

  @override
  String get collaborationJoinAccept => '초대 수락';

  @override
  String get collaborationJoinOpenProject => '프로젝트 열기';

  @override
  String get collaborationJoinInvalid => '이 초대 링크는 유효하지 않습니다';

  @override
  String get collaborationJoinUnavailable => '이 초대는 더 이상 계정에서 사용할 수 없습니다';

  @override
  String get collaborationPublicNotice => 'Pomodoist 멤버가 공유한 읽기 전용 보기';

  @override
  String get collaborationPublicUnavailable => '이 공유 링크는 더 이상 사용할 수 없습니다';

  @override
  String get collaborationPublicEmpty => '아직 공유된 내용이 없습니다';

  @override
  String get collaborationPublicOpen => 'Pomodoist 열기';

  @override
  String get collaborationPublicTasks => '작업';
}

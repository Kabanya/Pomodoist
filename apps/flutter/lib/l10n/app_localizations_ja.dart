// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get settingsSectionGeneral => '一般';

  @override
  String get settingsSectionAppearance => '外観';

  @override
  String get settingsSectionTasksFocus => 'タスクと集中';

  @override
  String get settingsSectionIntegrations => '連携とデータ';

  @override
  String get settingsSectionAccount => 'アカウントとPro';

  @override
  String get settingsThemeColorsTab => '色';

  @override
  String get settingsThemeBackgroundsTab => '背景';

  @override
  String get settingsRefreshAccount => 'アカウントを更新';

  @override
  String get settingsSubscriptionActions => 'サブスクリプションのオプション';

  @override
  String get settingsSubscriptionError =>
      'サブスクリプションを更新できませんでした。確認済みの利用権は維持されます。';

  @override
  String get settingsVersionError => 'バージョンを読み込めませんでした。';

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => '追加';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '削除';

  @override
  String get commonUndo => '元に戻す';

  @override
  String get commonOpen => '開く';

  @override
  String get commonBack => '戻る';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonCreate => '作成';

  @override
  String get commonClear => 'クリア';

  @override
  String get commonStop => '停止';

  @override
  String get skip => 'スキップ';

  @override
  String get onboardingLanguageTitle => '言語を選択';

  @override
  String get onboardingLanguageSubtitle => 'Pomodoistで使う言語を選んでください。';

  @override
  String get onboardingTimerTitle => 'タイマーのスタイルを選択';

  @override
  String get onboardingTimerSubtitle => '集中セッションのポモドーロ進捗表示を選んでください。';

  @override
  String get onboardingPaywallTitle => 'Pomodoistの全機能を利用';

  @override
  String get onboardingPaywallSubtitle => '買い切りプランの特典は毎週24時間限定です。';

  @override
  String get onboardingAccountTitle => 'アカウントを作成';

  @override
  String get onboardingAccountSubtitle => 'ログインして、デバイス間でタスク、集中履歴、設定を同期しましょう。';

  @override
  String get startupPreparingTasks => 'タスクを準備中';

  @override
  String get operationTakingLonger => '通常より時間がかかっています。処理は引き続き実行中です。';

  @override
  String get onboardingContinue => '続ける';

  @override
  String get onboardingMaybeLater => '後で';

  @override
  String get onboardingFinish => '完了';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      '自然な言葉で話すだけで、Pomodoistがタスクを作成します。タスク履歴は無期限に保存されます。';

  @override
  String get billingSubtitleHighlight => '自然な言葉';

  @override
  String get billingCancelAnytime => 'いつでも解約できます。';

  @override
  String get billingMonthlyTitle => '月額';

  @override
  String get billingAnnualTitle => '年額';

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
    return '最初の3か月間、その後は$price。';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'その後は$price。';
  }

  @override
  String get billingLifetimeTitle => '買い切り';

  @override
  String get billingLifetimeSubtitle => '一度のお支払いで永久に利用。';

  @override
  String get billingBestValue => '最もお得';

  @override
  String get billingChoose => '選択';

  @override
  String get billingActive => 'このデバイスではPomodoist Proが有効です。';

  @override
  String get billingActiveShort => '有効';

  @override
  String get billingRestore => '購入を復元';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

  @override
  String get termsOfUse => '利用規約';

  @override
  String get support => 'サポート';

  @override
  String get billingManageLink => 'Linkで管理';

  @override
  String get billingExternalBrowserTitle => 'ブラウザで支払いを開きます';

  @override
  String get billingExternalBrowserMessage =>
      'PomodoistがSafariまたは標準ブラウザでStripe Checkoutを開きます。ブラウザウィンドウを許可して続けてください。';

  @override
  String get billingAppleOnly => '購入はiPhone、iPad、Macで利用できます。';

  @override
  String get billingStoreUnavailable => '現在App Storeを利用できません。';

  @override
  String get billingStoreConnectionFailed => 'VPNをオフにして再試行してください。';

  @override
  String billingPurchaseError(String error) {
    return '購入エラー: $error';
  }

  @override
  String get billingStripeAuthenticationRequired =>
      'Pomodoistにログインして再試行してください。';

  @override
  String get billingStripeDisabled => '支払いはまだ利用できません。後でもう一度お試しください。';

  @override
  String get billingStripeAlreadyEntitled =>
      'Pomodoist Proはすでに有効です。アカウントの状態を更新してください。';

  @override
  String get billingStripeOfferExpired => 'この特典は終了しました。他の利用可能なプランを選んでください。';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'Stripe決済は一時的に利用できません。後で再試行するか、サポートにお問い合わせください。';

  @override
  String get billingStripeCheckoutFailed => '支払いを開始できませんでした。接続を確認して再試行してください。';

  @override
  String get purchaseSuccessTitle => 'Proが有効になりました';

  @override
  String get purchaseSuccessMessage =>
      'Pomodoistをご支援いただきありがとうございます。すべてのPro機能をご利用いただけます。';

  @override
  String get purchaseSuccessContinue => '続ける';

  @override
  String get purchaseProcessingTitle => '支払いを処理中';

  @override
  String get purchaseProcessingMessage =>
      '支払いを確認しています。しばらくしてもProが表示されない場合は、後で再度更新してください。';

  @override
  String get purchaseOpenApp => 'Pomodoistを開く';

  @override
  String launchOfferEndsIn(String time) {
    return '買い切り特典の終了まで$time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'メール';

  @override
  String get loginTitle => 'Pomodoistにログイン';

  @override
  String get accountChecking => 'アカウントを確認中';

  @override
  String get oauthConsentTitle => 'エージェントを接続';

  @override
  String get oauthConsentLoading => '接続リクエストを確認中';

  @override
  String get oauthConsentInvalidAuthorization => '接続リクエストがないか、無効です。';

  @override
  String get oauthConsentLoadError => '接続リクエストを読み込めませんでした。';

  @override
  String get oauthConsentActionError => 'リクエストを完了できませんでした。再試行してください。';

  @override
  String get oauthConsentRedirectError =>
      '戻り先のアドレスがないか、安全ではありません。アクセス権は渡されませんでした。';

  @override
  String get oauthConsentClientFallback => 'エージェント';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientNameがPomodoistへのアクセスを求めています';
  }

  @override
  String get oauthConsentRedirectOrigin => '戻り先アドレス';

  @override
  String get oauthConsentCapabilitiesTitle => 'このエージェントができること';

  @override
  String get oauthConsentManagePlanning => 'タスク、プロジェクト、ユーザーラベル、カンバンの読み取りと管理。';

  @override
  String get oauthConsentReadInsights => '完了した集中履歴、生産性レポート、実績の読み取り。';

  @override
  String get oauthConsentUnavailableTitle => 'このエージェントができないこと';

  @override
  String get oauthConsentUnavailable =>
      'アカウント、請求情報、Googleカレンダー、実行中の集中タイマーへのアクセス。';

  @override
  String get oauthConsentUnsupportedScopes =>
      'このリクエストは未対応のアカウントアクセスを求めているため、承認できません。';

  @override
  String get oauthConsentApprove => '許可';

  @override
  String get oauthConsentDeny => '拒否';

  @override
  String get oauthConsentApproving => 'アクセスを許可中…';

  @override
  String get oauthConsentDenying => 'アクセスを拒否中…';

  @override
  String get oauthConsentRedirecting => 'エージェントに戻っています…';

  @override
  String get loginCreateAccountPrompt => 'アカウントをお持ちでないですか？';

  @override
  String get loginCreateAccountAction => 'アカウントを作成';

  @override
  String get registerTitle => 'アカウントを作成';

  @override
  String get registerSubtitle => 'デバイス間でタスク、集中履歴、設定を同期します。';

  @override
  String get registerPassword => 'パスワード';

  @override
  String get registerSubmit => 'アカウントを作成';

  @override
  String get registerSignInPrompt => 'すでにアカウントをお持ちですか？';

  @override
  String get registerSignInAction => 'ログイン';

  @override
  String get registerCheckEmailTitle => 'メールを確認';

  @override
  String get registerCheckEmailMessage =>
      'このアドレスに確認が必要な場合、リンク付きのメールが届きます。すでにアカウントがある場合は、ログインするかパスワードを再設定してください。';

  @override
  String registerError(Object error) {
    return 'アカウントを作成できませんでした: $error';
  }

  @override
  String get authEmailSignInTitle => 'メールでログイン';

  @override
  String get authWelcomeTitle => 'Pomodoistにログイン';

  @override
  String get authWelcomeDescription => 'どのデバイスでも、あなたのタスクと集中を。';

  @override
  String get authSignInWithLink => 'リンクでログイン';

  @override
  String get authForgotPassword => 'パスワードをお忘れですか？';

  @override
  String get authBackToSignIn => 'ログインに戻る';

  @override
  String get authNoAccount => 'アカウントをお持ちでないですか？';

  @override
  String get authHaveAccount => 'すでにアカウントをお持ちですか？';

  @override
  String get authShowPassword => 'パスワードを表示';

  @override
  String get authHidePassword => 'パスワードを非表示';

  @override
  String get authResetTitle => 'パスワードを再設定';

  @override
  String get authResetDescription =>
      'アカウントのメールアドレスを入力してください。パスワード変更用のリンクをお送りします。';

  @override
  String get authResetEmailSentTitle => 'メールを確認';

  @override
  String get authResetEmailSent => 'このメールアドレスのアカウントがある場合、パスワード再設定用のリンクが届きます。';

  @override
  String get authResetSendAgain => '再送信';

  @override
  String get authResetEditEmail => 'メールアドレスを変更';

  @override
  String get authNewPasswordTitle => '新しいパスワードを設定';

  @override
  String get authNewPasswordDescription => '他のアカウントで使っていないパスワードを設定してください。';

  @override
  String get authNewPassword => '新しいパスワード';

  @override
  String get authConfirmPassword => 'パスワードを再入力';

  @override
  String get authSavePassword => 'パスワードを保存';

  @override
  String get authPasswordMismatch => 'パスワードが一致しません。';

  @override
  String get authPasswordUnchanged => '現在とは異なるパスワードを設定してください。';

  @override
  String get authPasswordUpdatedTitle => 'パスワードを更新しました';

  @override
  String get authPasswordUpdatedMessage =>
      '新しいパスワードを保存しました。引き続きPomodoistをご利用いただけます。';

  @override
  String get authResetLinkExpired =>
      'このパスワード再設定リンクは無効か期限切れです。新しいリンクをリクエストしてください。';

  @override
  String get authUnexpectedReset => 'パスワード再設定メールを送信できませんでした。再試行してください。';

  @override
  String get authUnexpectedPasswordUpdate => '新しいパスワードを保存できませんでした。再試行してください。';

  @override
  String get authCheckingResetLink => 'パスワード再設定リンクを確認中…';

  @override
  String get authSignInAction => 'ログイン';

  @override
  String get authSendLink => 'リンクを送信';

  @override
  String get authMagicLinkSent =>
      'このアドレスのアカウントがある場合、ログイン用のリンクが届きます。受信トレイと迷惑メールフォルダをご確認ください。';

  @override
  String get authAccountCreated => 'アカウントを作成しました。';

  @override
  String get authSignedIn => 'ログインしました。';

  @override
  String get authEmailRequired => 'メールアドレスを入力してください。';

  @override
  String get authEmailInvalid => 'メールアドレスを確認してください（例: name@example.com）。';

  @override
  String get authPasswordRequired => 'パスワードを入力してください。';

  @override
  String get authInvalidCredentials =>
      'メールアドレスまたはパスワードが違います。アドレスを確認するか、パスワードを再設定するか、アカウントを作成してください。';

  @override
  String get authEmailUnconfirmed => '送信したリンクでメールアドレスを確認してから、再度ログインしてください。';

  @override
  String get authWeakPassword => 'このパスワードは推測されやすいため、より長く推測されにくいものを使用してください。';

  @override
  String get authAccountMayExist =>
      'このメールアドレスはすでに登録されている可能性があります。ログインするかパスワードを再設定してください。';

  @override
  String get authRateLimited => '試行回数が多すぎます。数分待ってから再試行してください。';

  @override
  String get authEmailRateLimited => 'メールのリクエストが多すぎます。数分待ってから再度リクエストしてください。';

  @override
  String get authOffline => 'アカウントサービスに接続できませんでした。インターネット接続を確認して再試行してください。';

  @override
  String get authTimeout => 'アカウントサービスの応答に時間がかかっています。再試行してください。';

  @override
  String get authServiceUnavailable => 'アカウントサービスは一時的に利用できません。後で再試行してください。';

  @override
  String get authCaptchaRequired => 'セキュリティ確認を完了して続けてください。';

  @override
  String get authCaptchaExpired => 'セキュリティ確認の期限が切れました。もう一度行ってください。';

  @override
  String get authCaptchaFailed => 'セキュリティ確認に失敗しました。もう一度お試しください。';

  @override
  String get authCaptchaCancelled => 'セキュリティ確認がキャンセルされました。続けるには再開してください。';

  @override
  String get authCaptchaUnavailable => '現在セキュリティ確認を利用できません。接続を確認して再試行してください。';

  @override
  String get authCaptchaOpenFailed =>
      'ブラウザでセキュリティ確認を開けませんでした。標準ブラウザを確認して再試行してください。';

  @override
  String get authProviderFallback => 'このプロバイダ';

  @override
  String authProviderUnavailable(String provider) {
    return '現在$providerでのログインは利用できません。再試行するか別の方法をお使いください。';
  }

  @override
  String get authSignUpDisabled => 'メールでのアカウント作成は一時的に利用できません。別のログイン方法をお試しください。';

  @override
  String get authAccountRestricted =>
      'このアカウントは現在ログインできません。誤りと思われる場合はサポートにお問い合わせください。';

  @override
  String get authLinkExpired => 'このログインリンクは無効か期限切れです。新しいリンクをリクエストしてください。';

  @override
  String get authUnexpectedSignIn => 'ログインできませんでした。再試行してください。';

  @override
  String get authUnexpectedSignUp => 'アカウントを作成できませんでした。再試行してください。';

  @override
  String get authUnexpectedMagicLink => 'ログインリンクを送信できませんでした。再試行してください。';

  @override
  String get authResendConfirmation => '確認メールを再送信';

  @override
  String get authConfirmationSendFailed => '確認メールを送信できませんでした。後で再試行してください。';

  @override
  String get authRetryVerification => '確認を再試行';

  @override
  String get captchaSecurityLabel => 'セキュリティ確認';

  @override
  String get captchaChallengeTitle => 'Pomodoistセキュリティ確認';

  @override
  String get captchaChallengePrompt => '人間であることを確認してPomodoistを続けてください。';

  @override
  String get captchaChallengeInvalid =>
      'このセキュリティ確認リンクは無効です。Pomodoistに戻って再試行してください。';

  @override
  String get captchaChallengeHandoffHelp =>
      'Pomodoistが開かない場合は下のボタンを使ってください。アプリがインストールされていない場合は、このページを閉じて開始したデバイスに戻ってください。';

  @override
  String get captchaReturnToApp => 'Pomodoistに戻る';

  @override
  String get navSearch => '検索';

  @override
  String get navInbox => '受信トレイ';

  @override
  String get navPriorityMatrix => '優先度マトリクス';

  @override
  String get navTimeline => 'タイムライン';

  @override
  String get navKanban => 'カンバン';

  @override
  String get kanbanTitle => 'カンバン';

  @override
  String get kanbanSubtitle => '作業の流れを可視化して、今大切なことに集中しましょう。';

  @override
  String get kanbanDefaultBacklog => 'バックログ';

  @override
  String get kanbanDefaultTodo => '未着手';

  @override
  String get kanbanDefaultInProgress => '進行中';

  @override
  String get kanbanDefaultDone => '完了';

  @override
  String get kanbanSearchTooltip => 'カンバンを検索';

  @override
  String get kanbanSearchHint => 'タスクまたはプロジェクトを検索';

  @override
  String get kanbanHideDone => '完了を非表示';

  @override
  String get kanbanShowDone => '完了を表示';

  @override
  String get kanbanProjectsTitle => 'このボードのプロジェクト';

  @override
  String kanbanAddToStatus(String status) {
    return '$statusに追加';
  }

  @override
  String get kanbanTaskField => 'タスク';

  @override
  String get kanbanProjectField => 'プロジェクト';

  @override
  String get kanbanChooseProject => 'プロジェクトを選んでください。';

  @override
  String get kanbanTaskActions => 'タスクの操作';

  @override
  String get kanbanDragTask => 'タスクをドラッグ';

  @override
  String kanbanMoveTo(String status) {
    return '$statusに移動';
  }

  @override
  String get kanbanRestoreBeforeFocus => '集中を開始する前にタスクを復元してください。';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return '集中を開始できませんでした: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'カンバンを読み込めませんでした: $error';
  }

  @override
  String get commonRetry => '再試行';

  @override
  String get commonContinueWaiting => '待機を続ける';

  @override
  String kanbanTasksCount(int count) {
    return '$count件のタスク';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return 'サブタスク$completed/$total件';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '集中インターバル$completed/$total回';
  }

  @override
  String get kanbanActive => 'アクティブ';

  @override
  String kanbanPriority(int priority) {
    return '優先度$priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return '$statusに移動しました';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return '$taskの集中を開始しました';
  }

  @override
  String get kanbanNoTasks => 'まだタスクはありません';

  @override
  String get navToday => '今日';

  @override
  String get navUpcoming => '近日予定';

  @override
  String get navBrowse => 'ブラウズ';

  @override
  String get navIntegrations => '連携';

  @override
  String get navReports => 'レポート';

  @override
  String get navFocus => '集中';

  @override
  String get navProjects => 'プロジェクト';

  @override
  String get navSettings => '設定';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsAboutTitle => 'このアプリについて';

  @override
  String get settingsFocusCompletionCelebrationTitle => '集中完了のお祝い';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      '最後の休憩後に全画面でお祝いを表示します。';

  @override
  String get settingsVersionLabel => 'バージョン';

  @override
  String get settingsPlanLabel => 'プラン';

  @override
  String get settingsPlanFree => '無料';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'キーボードショートカット';

  @override
  String get settingsShortcutsSubtitle => '物理キーボードで使えるコマンドをカスタマイズします。';

  @override
  String get settingsShortcutsToggleSidebar => 'サイドバーを切り替え';

  @override
  String get settingsShortcutsGlobalQuickAdd => 'グローバルクイック追加';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Pomodoistがアクティブでないときも使えます。';

  @override
  String get settingsShortcutsRecordTitle => 'ショートカットを押してください';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Command、Control、Altのいずれかとキーを組み合わせてください。Escでキャンセルします。';

  @override
  String get settingsShortcutsInvalid => 'Command、Control、Altのいずれかを含めてください。';

  @override
  String get settingsShortcutsConflict => 'このショートカットはすでに使われています。';

  @override
  String get settingsShortcutsGlobalError =>
      'このグローバルショートカットは利用できません。以前のショートカットが引き続き有効です。';

  @override
  String get settingsShortcutsResetAll => 'すべてリセット';

  @override
  String get settingsShortcutsResetDone => 'キーボードショートカットをリセットしました。';

  @override
  String get csvImportTitle => 'CSVからタスクをインポート';

  @override
  String get csvImportSubtitle =>
      'タスク、プロジェクト、ラベル、ワークフローのステータスを作成する前にCSVファイルを確認します。';

  @override
  String get csvImportSelectFile => 'CSVファイルを選択';

  @override
  String get csvImportHumanGuideButton => '利用者向けガイド';

  @override
  String get csvImportAgentGuideButton => 'エージェント向けガイド';

  @override
  String get csvImportHumanGuideTitle => 'CSVファイルの準備方法';

  @override
  String get csvImportAgentGuideTitle => 'エージェント向けCSV仕様';

  @override
  String get csvImportCopy => 'コピー';

  @override
  String get csvImportCopied => 'クリップボードにコピーしました。';

  @override
  String get csvImportPreviewTitle => 'インポートを確認';

  @override
  String get csvImportPreviewTasks => 'タスク';

  @override
  String get csvImportPreviewSubtasks => 'サブタスク';

  @override
  String get csvImportPreviewNewProjects => '新しいプロジェクト';

  @override
  String get csvImportPreviewNewLabels => '新しいラベル';

  @override
  String get csvImportPreviewNewStatuses => '新しいワークフローステータス';

  @override
  String get csvImportNone => 'なし';

  @override
  String get csvImportDuplicateWarning => '同じファイルを再度インポートするとタスクが重複します。';

  @override
  String get csvImportConfirm => 'インポート';

  @override
  String get csvImportSuccess => 'タスクをインポートしました';

  @override
  String get csvImportErrorTitle => 'CSVのインポートに失敗しました';

  @override
  String get csvImportUnexpectedError => 'ファイルをインポートできませんでした。';

  @override
  String get csvImportHumanGuide =>
      '1. ファイルをUTF-8のCSVで保存します。区切りにはカンマ（推奨）またはセミコロンを使ってください。\n\n2. content列は必須です。次の列も使用できます: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key。\n\n3. 1行につき未完了のタスクを1つ入力します。ラベルは|で区切ります。優先度は1～4で、空欄は4です。プロジェクトが空欄なら受信トレイ、ステータスが空欄ならバックログになります。存在しないプロジェクト、ラベル、未完了のステータスは自動作成されます。\n\n4. 終日タスクはdue_dateをYYYY-MM-DD形式にします。時間指定のタスクはstart_atとend_atをUTCオフセット付きRFC3339形式で入力し、Europe/MoscowなどのIANA time_zoneを指定します。\n\n5. サブタスクを作るには、親の行に一意のkeyを設定し、子のparent_keyにその値を入力します。親はファイルの後ろにあっても構いません。子は親と同じプロジェクトにする必要があります。\n\n6. Pomodoistはファイル全体を検証し、インポート前にプレビューを表示します。無効な行があれば何も保存されません。再インポートするとタスクが重複します。';

  @override
  String get settingsConnectedAgentsTitle => '接続済みエージェント';

  @override
  String get settingsConnectedAgentsLoading => '接続済みエージェントを読み込み中…';

  @override
  String get settingsConnectedAgentsEmpty => '接続済みのエージェントはありません。';

  @override
  String get settingsConnectedAgentsLoadError => '接続済みエージェントを読み込めませんでした。';

  @override
  String get settingsConnectedAgentsUnknownClient => 'エージェント';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return '$dateに接続';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'アクセス権を取り消す';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'エージェントのアクセス権を取り消しますか？';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return '$clientNameのPomodoistへのアクセス権を取り消しますか？';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'アクセス権を取り消せませんでした。再試行してください。';

  @override
  String get settingsLanguageTitle => '言語';

  @override
  String get settingsLanguageSubtitle => 'アプリの言語を選びます。';

  @override
  String get settingsLanguageSystem => 'システムのデフォルト';

  @override
  String get settingsVoiceTranscriptionTitle => '音声文字起こし';

  @override
  String get settingsVoiceTranscriptionSubtitle => 'このデバイスで録音を文字に変換する方法を選びます。';

  @override
  String get settingsVoiceTranscriptionSystem => 'システム（Apple）';

  @override
  String get settingsVoiceTranscriptionCloud => 'クラウド';

  @override
  String get settingsVoiceTranscriptionCloudDescription =>
      'クラウド文字起こしは音声をPomodoistに送信し、インターネット接続が必要です。';

  @override
  String get settingsVoiceTranscriptionCloudRequiresSignIn =>
      'クラウド文字起こしを使うにはログインしてください。それまではシステムの文字起こしが有効です。';

  @override
  String get settingsThemeTitle => 'テーマ';

  @override
  String get settingsThemeSubtitle => 'アプリの外観を選びます。';

  @override
  String get settingsThemeSystem => 'システム';

  @override
  String get settingsThemeLight => 'ライト';

  @override
  String get settingsThemeDark => 'ダーク';

  @override
  String get settingsTimerVisualTitle => 'ポモドーロタイマー';

  @override
  String get settingsTimerVisualSubtitle => '集中画面での進捗表示を選びます。';

  @override
  String get settingsTimerVisualBar => 'バー';

  @override
  String get settingsTimerVisualCircle => '円';

  @override
  String get settingsReturnRemindersTitle => '再開リマインダー';

  @override
  String get settingsReturnRemindersSubtitle =>
      '今日タスクを1つも完了していない場合、20:30にお知らせします。';

  @override
  String get settingsDefaultTimedBlockTitle => 'カレンダーブロックの既定時間';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      '時刻のみを入力した新規タスクには、このカレンダー上の長さを使います。';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'カスタム時間';

  @override
  String get settingsDefaultTimedBlockError => '1～480分を入力してください。';

  @override
  String get settingsTaskTimeDisplayTitle => 'タスクの時刻表示';

  @override
  String get settingsTaskTimeDisplaySubtitle => '時間指定タスクの予定表示を選びます。';

  @override
  String get settingsTaskTimeDisplaySmart => 'スマート';

  @override
  String get settingsTaskTimeDisplayRange => '開始時刻と終了時刻';

  @override
  String get settingsTaskTimeDisplayStartOnly => '開始時刻のみ';

  @override
  String get taskTimeStatusFuture => '今後の予定';

  @override
  String get taskTimeStatusFocused => '集中中';

  @override
  String get taskTimeStatusCurrent => '進行中';

  @override
  String get taskTimeStatusOverdue => '期限切れ';

  @override
  String get taskTimeStatusCompleted => '完了';

  @override
  String get menuTooltip => 'メニュー';

  @override
  String get localUser => 'ローカルユーザー';

  @override
  String get addTask => 'タスクを追加';

  @override
  String get quickAddHint => '同期機能を作る 明日 p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'タスクを追加できませんでした: $error';
  }

  @override
  String get taskCreateFailed => 'タスクを作成できませんでした。再試行してください。';

  @override
  String couldNotAddProject(Object error) {
    return 'プロジェクトを追加できませんでした: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のタスクを追加しました',
      one: '1件のタスクを追加しました',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => '音声クイック追加';

  @override
  String get voiceTitle => '音声追加';

  @override
  String get voiceRecord => '録音';

  @override
  String get voiceAgain => 'もう一度';

  @override
  String get voiceStop => '停止';

  @override
  String voiceAddCount(int count) {
    return '$count件追加';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'タスク$index';
  }

  @override
  String get voiceRemoveTask => '削除';

  @override
  String get voiceInstruction => '録音をタップしてタスクを話してください。';

  @override
  String get voiceStatusIdle => '内蔵マイク入力のみ';

  @override
  String get voiceStatusRequestingPermission => 'アクセスをリクエスト中';

  @override
  String get voiceStatusRecording => '内蔵マイクで聞き取り中';

  @override
  String get voiceStatusTranscribing => '録音を文字起こし中';

  @override
  String get voiceStatusCanceled => '録音をキャンセルしました';

  @override
  String get voiceStatusUnsupported => '未対応のプラットフォームです';

  @override
  String get voiceStatusError => '音声を認識できませんでした';

  @override
  String get voiceStatusAnalyzing => 'タスクに分割中';

  @override
  String get voiceStatusReview => '追加前にタスクを確認';

  @override
  String get voiceStepRecord => '録音';

  @override
  String get voiceStepText => 'テキスト';

  @override
  String get voiceStepAnalyze => '解析';

  @override
  String get voiceStepReview => '確認';

  @override
  String get voiceAnalyzing => 'Pomodoistが音声をタスクに分割しています';

  @override
  String get voiceFallbackError => '音声を処理できませんでした。手動で編集できるよう下書きを保存しました。';

  @override
  String get voiceMicrophoneUnavailable =>
      '現在マイクを利用できません。通話やボイスチャットを終了して再試行してください。';

  @override
  String get voiceSmartMode => 'スマートモード';

  @override
  String get voiceRetryTranscription => '文字起こしを再試行';

  @override
  String get voiceRecordingSaved => 'このデバイスに録音を保存しました。録り直さずに再試行できます。';

  @override
  String get voiceAllowAccess => 'アクセスを許可';

  @override
  String get voiceOpenMicrophoneSettings => 'マイク設定を開く';

  @override
  String get voiceOpenSpeechSettings => '音声認識の設定を開く';

  @override
  String get voiceEnableDictation => '音声入力を有効にする';

  @override
  String get voiceUseCloudTranscription => 'クラウド文字起こしを使う';

  @override
  String get voiceMicrophoneDenied => 'システム設定でマイクへのアクセスを許可してください。';

  @override
  String get voiceSpeechDenied => 'システム設定で音声認識を許可してください。';

  @override
  String get voiceAccessRestricted => '管理者またはスクリーンタイムの設定でアクセスが制限されています。';

  @override
  String get voiceDictationDisabled =>
      'システム設定 → キーボード → 音声入力で音声入力を有効にし、言語を選んでから再試行してください。';

  @override
  String get voiceServiceUnavailable =>
      '音声認識を利用できません。接続を確認してください。Macではシステム設定 → キーボード → 音声入力と言語も確認してください。';

  @override
  String get voiceCloudServiceUnavailable =>
      'クラウド文字起こしに失敗しました。インターネット接続を確認し、保存した録音で再試行してください。';

  @override
  String get voiceLocaleUnsupported => 'このデバイスのシステム音声認識は選択した言語に対応していません。';

  @override
  String get voiceNetworkUnavailable =>
      'この言語の音声認識にはインターネット接続が必要です。再接続して再試行してください。';

  @override
  String get voiceSettingsFailed =>
      '設定を開けませんでした。システム設定を手動で開き、マイクと音声認識のアクセス権を確認してください。Macではキーボード → 音声入力も確認してください。';

  @override
  String get voiceRetryAnalysis => '解析を再試行';

  @override
  String get screenInboxSubtitle => '整理する前にタスクを記録しましょう。';

  @override
  String get priorityMatrixSubtitle =>
      'タスクを優先度間でドラッグします。日付は同じ優先度内の並び順にのみ使われます。';

  @override
  String get priorityMatrixP1Title => '今すぐ実行';

  @override
  String get priorityMatrixP2Title => '予定する';

  @override
  String get priorityMatrixP3Title => '任せる';

  @override
  String get priorityMatrixP4Title => '手放す';

  @override
  String get priorityMatrixAxisUrgent => '緊急';

  @override
  String get priorityMatrixAxisNotUrgent => '緊急ではない';

  @override
  String get priorityMatrixAxisImportant => '重要';

  @override
  String get priorityMatrixAxisNotImportant => '重要ではない';

  @override
  String get timelineSubtitle => '時間グリッドで1日の予定を立てます。';

  @override
  String get timelineAllDay => '終日';

  @override
  String get timelineBeforeHours => '表示時間より前';

  @override
  String get timelineAfterHours => '表示時間より後';

  @override
  String get timelineVisibleHours => '表示時間';

  @override
  String get timelineStartHour => '開始';

  @override
  String get timelineEndHour => '終了';

  @override
  String get timelineZoomOut => '縮小';

  @override
  String get timelineZoomIn => '拡大';

  @override
  String timelineAddTimedHint(String time) {
    return '$timeのタスク';
  }

  @override
  String get timelineAddAllDayHint => '終日タスク';

  @override
  String get timelineNoAllDayTasks => '終日タスクはありません';

  @override
  String get timelineNoTimedTasks => '時間指定のタスクはありません';

  @override
  String get timelinePreviousDay => '前日';

  @override
  String get timelineNextDay => '翌日';

  @override
  String get timelinePickDate => '日付を選択';

  @override
  String get upcomingPreviousPeriod => '前の期間';

  @override
  String get upcomingNextPeriod => '次の期間';

  @override
  String get upcomingOpenDatePicker => '日付選択を開く';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のタスク',
      one: '1件のタスク',
      zero: 'タスクなし',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return '集中予定: $planned回 - 完了: $completed回 - 集中: $focus';
  }

  @override
  String get screenUpcomingSubtitle => '明日以降に予定されているタスク。';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return '$dateに予定されているタスク。';
  }

  @override
  String get noTasksHere => 'ここにタスクはありません';

  @override
  String get noUpcomingTasks => '日付付きのタスクはありません';

  @override
  String get noTasksForDay => 'この日の予定タスクはありません';

  @override
  String failedToLoadTasks(Object error) {
    return 'タスクの読み込みに失敗しました: $error';
  }

  @override
  String get searchTasks => 'タスクを検索';

  @override
  String get searchStartTyping => '入力してタスクを検索';

  @override
  String get searchNoMatches => '一致するタスクはありません';

  @override
  String failedToSearchTasks(Object error) {
    return 'タスクの検索に失敗しました: $error';
  }

  @override
  String get previousMonth => '前の月';

  @override
  String get nextMonth => '次の月';

  @override
  String get clearDateFilter => '日付フィルターをクリア';

  @override
  String get weekMon => '月';

  @override
  String get weekTue => '火';

  @override
  String get weekWed => '水';

  @override
  String get weekThu => '木';

  @override
  String get weekFri => '金';

  @override
  String get weekSat => '土';

  @override
  String get weekSun => '日';

  @override
  String get browseTitle => 'ブラウズ';

  @override
  String get unifiedAccount => '統合アカウント';

  @override
  String accountUnavailable(Object error) {
    return 'アカウントを利用できません: $error';
  }

  @override
  String get signOut => 'ログアウト';

  @override
  String get deleteAccount => 'アカウントを削除';

  @override
  String get deleteAccountConfirmation =>
      'アカウント、クラウドデータ、ローカルのタスク、プロジェクト、集中履歴を完全に削除します。元には戻せません。ストアのサブスクリプションは自動解約されません。「Appleでサインイン」を使用した場合は、Apple Accountの設定からPomodoistへのアクセスを別途取り消してください。';

  @override
  String get manageSignInWithApple => 'Appleでサインインを管理';

  @override
  String get deleteAccountFinalConfirmation => '本当によろしいですか？これが最後の確認です。';

  @override
  String deleteAccountError(Object error) {
    return 'アカウントを削除できませんでした: $error';
  }

  @override
  String get accountDeleted => 'アカウントを削除しました。';

  @override
  String get accountDeletedLocalCleanupError =>
      'アカウントを削除しましたが、ローカルデータを消去できませんでした。このデバイスを再び使う前にアプリのデータを消去してください。';

  @override
  String get browseSevenDays => '7日間';

  @override
  String get browseOpenNow => '現在の未完了';

  @override
  String get browseQueueLoading => '保留中の変更を読み込み中…';

  @override
  String get browseQueueUnavailable => '保留中の変更を読み込めませんでした。';

  @override
  String get browseQueueExplanation =>
      '送信待ちのローカル変更を表示します。キューが空でも、すべてのデバイスが最新であるとは限りません。';

  @override
  String get productivityTitle => '生産性';

  @override
  String get achievementsTitle => '実績';

  @override
  String get allTimeLabel => '全期間';

  @override
  String get lastSevenDaysLabel => '過去7日間';

  @override
  String get noWeeklyStatsLabel => '集中やタスクのデータはまだありません';

  @override
  String get completedFocuses => '完了した集中';

  @override
  String get completedTasks => '完了したタスク';

  @override
  String get unlocked => '獲得済み';

  @override
  String get locked => '未獲得';

  @override
  String get progressLabel => '進捗';

  @override
  String get focusAchievements => '集中の実績';

  @override
  String get taskAchievements => 'タスクの実績';

  @override
  String get comboAchievements => 'コンボの実績';

  @override
  String get focusIntervals => '集中インターバル';

  @override
  String get focusTime => '集中時間';

  @override
  String get openTasks => '未完了タスク';

  @override
  String get plannedIntervals => '予定インターバル';

  @override
  String get labelsTitle => 'ラベル';

  @override
  String get newProject => '新しいプロジェクト';

  @override
  String get newLabel => '新しいラベル';

  @override
  String get syncReadyQueue => '同期待ちキュー';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保留中のローカルコマンド$count件',
      one: '保留中のローカルコマンド1件',
      zero: '保留中のローカルコマンドなし',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'プロジェクトの読み込みに失敗しました: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'ラベルの読み込みに失敗しました: $error';
  }

  @override
  String get addProject => 'プロジェクトを追加';

  @override
  String get projectName => 'プロジェクト名';

  @override
  String get addLabel => 'ラベルを追加';

  @override
  String get labelName => 'ラベル名';

  @override
  String couldNotAddLabel(Object error) {
    return 'ラベルを追加できませんでした: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'プロジェクトを利用できません: $error';
  }

  @override
  String get projectsUnavailableShort => 'プロジェクトを利用できません';

  @override
  String get noProjects => 'プロジェクトなし';

  @override
  String get searchProjects => 'プロジェクトを検索';

  @override
  String get searchLabels => 'ラベルを検索';

  @override
  String get archivedProjectsOnly => 'アーカイブ済みプロジェクトのみ';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のプロジェクト',
      one: '1件のプロジェクト',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'ラベルなし';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のラベル',
      one: '1個のラベル',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => 'プロジェクト名を変更';

  @override
  String get deleteProject => 'プロジェクトを削除';

  @override
  String get deleteLabel => 'ラベルを削除';

  @override
  String deleteProjectConfirmation(String name) {
    return '「$name」を削除しますか？このプロジェクトのタスクは受信トレイに移動します。';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'プロジェクトを削除できませんでした: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'ラベルを削除できませんでした: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'プロジェクト: $count';
  }

  @override
  String get collapseProjects => 'プロジェクトを折りたたむ';

  @override
  String get expandProjects => 'プロジェクトを展開';

  @override
  String get projectFallbackTitle => 'プロジェクト';

  @override
  String get projectSubtitle => 'リスト表示です。ボードとカレンダーは今後対応予定です。';

  @override
  String get reportsTitle => 'レポート';

  @override
  String get reportsFocusedDay => '今日はここまで集中できました';

  @override
  String get reportsThisWeek => '今週の集中';

  @override
  String get reportsNextAchievement => '次の実績';

  @override
  String get viewAllAchievements => 'すべての実績を見る';

  @override
  String viewAllAchievementsCount(int count) {
    return '全$count件を見る';
  }

  @override
  String get allAchievementsUnlocked => 'すべての実績を獲得しました';

  @override
  String get noAchievementsYet => 'まだ実績はありません';

  @override
  String failedToLoadAchievements(Object error) {
    return '実績の読み込みに失敗しました: $error';
  }

  @override
  String get backToReports => 'レポートに戻る';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '集中インターバル$completed/$target回完了';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '集中インターバル$completed回完了、目標未設定';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return '過去7日間の集中時間: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'レポートの読み込みに失敗しました: $error';
  }

  @override
  String get taskNotFound => 'タスクが見つかりません';

  @override
  String get taskTitleHint => 'タスクのタイトル';

  @override
  String get taskComment => 'コメント';

  @override
  String get taskCommentHint => 'コメントを追加';

  @override
  String get subtasks => 'サブタスク';

  @override
  String get addSubtask => 'サブタスクを追加';

  @override
  String get addSubtaskHint => 'サブタスクを追加';

  @override
  String get noSubtasks => 'まだサブタスクはありません。';

  @override
  String get makeParentTask => '親タスクにする';

  @override
  String couldNotMoveTask(Object error) {
    return 'タスクを移動できませんでした: $error';
  }

  @override
  String get scheduleTitle => '予定';

  @override
  String get allDay => '終日';

  @override
  String get timedBlock => '時間枠';

  @override
  String get recurrenceTitle => '繰り返し';

  @override
  String get recurrenceNeedsSchedule => '繰り返す前に日付または時刻を追加してください。';

  @override
  String get recurrenceIntervalLabel => '間隔';

  @override
  String get recurrenceUnitDay => '日';

  @override
  String get recurrenceUnitWeek => '週';

  @override
  String get recurrenceUnitMonth => '月';

  @override
  String get recurrenceInvalidInterval => '1～999を入力してください。';

  @override
  String recurrenceEveryDays(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval日ごと',
      one: '毎日',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$interval週ごと',
      one: '毎週',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: '$intervalか月ごと',
      one: '毎月',
    );
    return '$_temp0';
  }

  @override
  String get noDate => '日付なし';

  @override
  String get calendarNotLinked => 'カレンダー未連携';

  @override
  String get calendarLinked => 'Googleカレンダー連携済み';

  @override
  String focusProgress(int completed, int total) {
    return '集中$completed/$total';
  }

  @override
  String get startFocus => '集中を開始';

  @override
  String get focusStarted => '集中を開始しました';

  @override
  String get taskReopened => 'タスクを未完了に戻しました';

  @override
  String get taskCompleted => 'タスクを完了しました';

  @override
  String get taskDeleted => 'タスクを削除しました';

  @override
  String get recurringDeleteTitle => '繰り返しタスクを削除しますか？';

  @override
  String get recurringDeleteMessage => 'このタスクは繰り返しの一部です。';

  @override
  String get recurringDeleteThis => 'このタスクを削除';

  @override
  String get recurringDeleteThisAndFollowing => 'このタスク以降を削除';

  @override
  String get markOpen => '未完了にする';

  @override
  String get markComplete => '完了にする';

  @override
  String get focusHistory => '集中履歴';

  @override
  String failedToLoadTask(Object error) {
    return 'タスクの読み込みに失敗しました: $error';
  }

  @override
  String get noFocusIntervals => 'まだ集中インターバルはありません。';

  @override
  String get today => '今日';

  @override
  String get tomorrow => '明日';

  @override
  String get yesterday => '昨日';

  @override
  String get clearDate => '日付をクリア';

  @override
  String priority(int priority) {
    return '優先度$priority';
  }

  @override
  String get focusTitle => '集中';

  @override
  String focusLoadError(Object error) {
    return '集中を読み込めませんでした: $error';
  }

  @override
  String get focusViewFull => '詳細';

  @override
  String get focusViewMinimal => 'シンプル';

  @override
  String get focusSwitchToFullView => '詳細表示に切り替え';

  @override
  String get focusSwitchToMinimalView => 'シンプル表示に切り替え';

  @override
  String get focusActionFailed => '集中を更新できませんでした。再試行してください。';

  @override
  String get noActiveSession => '実行中のセッションなし';

  @override
  String get focusIdleSubtitle => '単独の集中インターバルを開始するか、タスクから集中を開始します。';

  @override
  String get noPreset => 'プリセットなし';

  @override
  String get preparingFocus => '集中を準備中';

  @override
  String get moreFocusOptions => 'その他の集中オプション';

  @override
  String get moreFocusActions => 'その他の集中操作';

  @override
  String get preset => 'プリセット';

  @override
  String get newPreset => '新しいプリセット';

  @override
  String get customize => 'カスタマイズ';

  @override
  String get customizePreset => 'プリセットをカスタマイズ';

  @override
  String get startInterval => 'インターバルを開始';

  @override
  String get intervalStarted => 'インターバルを開始しました';

  @override
  String get intervalCompleted => 'インターバルを完了しました';

  @override
  String get focusStopped => '集中を停止しました';

  @override
  String get focusCompletionTitle => 'よくできました！';

  @override
  String get focusCompletionLinkedSubtitle => 'このタスクで予定した集中インターバルがすべて完了しました。';

  @override
  String get focusCompletionStandaloneSubtitle => '集中サイクルが完了しました。';

  @override
  String get focusCompletionQuestion => 'このタスクを完了しますか？';

  @override
  String get focusCompletionCompleteTask => 'タスクを完了';

  @override
  String get focusCompletionKeepOpen => 'タスクを未完了のままにする';

  @override
  String get focusCompletionDone => '完了';

  @override
  String get focusCompletionNextTask => '次の予定タスク';

  @override
  String focusCompletionTaskError(Object error) {
    return 'タスクを完了できませんでした: $error';
  }

  @override
  String get completeInterval => 'インターバルを完了';

  @override
  String get logDistraction => '気が散ったことを記録';

  @override
  String get workInterval => '作業インターバル';

  @override
  String get work => '作業';

  @override
  String get shortBreak => '短い休憩';

  @override
  String get breakLabel => '休憩';

  @override
  String get longBreak => '長い休憩';

  @override
  String readyLabel(String label) {
    return '準備完了: $label';
  }

  @override
  String get readyShort => '準備完了';

  @override
  String focusTimerTotal(String duration) {
    return '全$duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'セッション$current/$total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return '集中リズムのプレビュー、$countステップ';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return '集中リズム、ステップ$current/$total: $phase、$status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase、$status、残り$remaining、合計$total';
  }

  @override
  String get focusStatusRunning => '実行中';

  @override
  String get focusStatusPaused => '一時停止中';

  @override
  String focusWorkProgress(int completed, int total) {
    return '作業$completed/$total';
  }

  @override
  String intervalNumber(int number) {
    return 'インターバル$number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '作業$completed/$total - インターバル$number';
  }

  @override
  String get pause => '一時停止';

  @override
  String get resume => '再開';

  @override
  String get presetForNextIntervals => '次のインターバルのプリセット';

  @override
  String usePreset(String name) {
    return '$nameを使う';
  }

  @override
  String minutesWork(int minutes) {
    return '作業$minutes分';
  }

  @override
  String minutesShort(int minutes) {
    return '短い休憩$minutes分';
  }

  @override
  String minutesLong(int minutes) {
    return '長い休憩$minutes分';
  }

  @override
  String longEvery(int count) {
    return '$count回ごとに長い休憩';
  }

  @override
  String get autoBreaks => '自動休憩';

  @override
  String get autoWork => '自動作業';

  @override
  String get noPause => '一時停止なし';

  @override
  String get focusPauseUnavailable => 'このプリセットでは一時停止できません';

  @override
  String get strict => '厳格';

  @override
  String get flexible => '柔軟';

  @override
  String get name => '名前';

  @override
  String get workField => '作業';

  @override
  String get shortField => '短い休憩';

  @override
  String get longField => '長い休憩';

  @override
  String get every => '間隔';

  @override
  String get minutesSuffix => '分';

  @override
  String get makeDefault => 'デフォルトにする';

  @override
  String get autoStartBreaks => '休憩を自動開始';

  @override
  String get autoStartWork => '作業を自動開始';

  @override
  String get allowPause => '一時停止を許可';

  @override
  String get strictMode => '厳格モード';

  @override
  String get nameRequired => '名前は必須です';

  @override
  String get nameMustBeUnique => '名前は重複できません';

  @override
  String get googleCalendarTitle => 'Googleカレンダー';

  @override
  String get googleCalendarConnectedSubtitle => 'Pomodoistカレンダーの双方向同期が有効です。';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Googleアカウントを接続して予定タスクを同期します。';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'Googleカレンダーの同期は別のデバイスで動作しています。Pomodoistのデータはこのデバイスでも同期されます。';

  @override
  String get syncNow => '今すぐ同期';

  @override
  String get useThisDevice => 'このデバイスを使う';

  @override
  String get connect => '接続';

  @override
  String get disconnect => '接続解除';

  @override
  String failedToLoadIntegration(Object error) {
    return '連携の読み込みに失敗しました: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Googleカレンダーのエラー: $message';
  }

  @override
  String get googleAuthRequired =>
      'Googleカレンダーの認証が必要です。再度ログインし、「今すぐ同期」を実行してください。';

  @override
  String get googleSignInNotConfigured =>
      'Googleログインが未設定です。このiOSターゲットにGOOGLE_CLIENT_IDとGOOGLE_REVERSED_CLIENT_IDを設定してください。';

  @override
  String get googleCallbackNotConfigured =>
      'Googleログインのコールバックが未設定です。ios/Flutter/GoogleOAuth.xcconfigにGOOGLE_REVERSED_CLIENT_IDを設定してください。';

  @override
  String get googleWebButtonFirst => 'ウェブでは先にGoogleログインボタンを押し、その後「接続」を押してください。';

  @override
  String get googleAccessDenied =>
      'Googleへのアクセスが拒否されました。このGoogleアカウントをOAuthテストユーザーに追加するか、OAuthアプリを公開して検証してください。';

  @override
  String get status => '状態';

  @override
  String get account => 'アカウント';

  @override
  String get calendar => 'カレンダー';

  @override
  String get calendarId => 'カレンダーID';

  @override
  String get lastSync => '最終同期';

  @override
  String get notConnected => '未接続';

  @override
  String get notCreated => '未作成';

  @override
  String get never => 'なし';

  @override
  String durationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours時間$minutes分';
  }

  @override
  String get projectIcon => 'プロジェクトアイコン';

  @override
  String projectIconOption(int number) {
    return 'アイコン$number';
  }

  @override
  String get projectColor => 'プロジェクトの色';

  @override
  String projectColorOption(int number) {
    return '色$number';
  }

  @override
  String get addProjectToFavorites => 'プロジェクトをお気に入りに追加';

  @override
  String get removeProjectFromFavorites => 'プロジェクトをお気に入りから削除';

  @override
  String get timelineProjectsMenu => 'タイムラインのプロジェクトを管理';

  @override
  String get timelineShowProject => 'タイムラインにプロジェクトを表示';

  @override
  String get timelineHideProject => '一時的なプロジェクトを非表示';

  @override
  String get timelineCollapseProject => 'プロジェクトの枝を折りたたむ';

  @override
  String get timelineExpandProject => 'プロジェクトの枝を展開';

  @override
  String get timelineCurrentTime => '現在時刻';

  @override
  String couldNotUpdateProject(Object error) {
    return 'プロジェクトを更新できませんでした: $error';
  }

  @override
  String get commonDone => '完了';

  @override
  String get taskSelect => '選択';

  @override
  String taskSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件選択',
      one: '1件選択',
      zero: '0件選択',
    );
    return '$_temp0';
  }

  @override
  String get taskSelectAll => 'すべて選択';

  @override
  String get taskDeselectAll => '選択をすべて解除';

  @override
  String get taskDue => '期限';

  @override
  String get taskProject => 'プロジェクト';

  @override
  String get taskLabels => 'ラベル';

  @override
  String get taskPriority => '優先度';

  @override
  String get taskMore => 'その他';

  @override
  String get taskSchedule => '予定';

  @override
  String get taskMove => '移動';

  @override
  String get taskDuplicate => '複製';

  @override
  String get taskDuplicateTitle => 'タスクを複製';

  @override
  String get taskDuplicateSelectedOnly => '選択したもののみ';

  @override
  String get taskDuplicateWithSubtasks => 'サブタスクを含める';

  @override
  String get taskWeekend => '今週末';

  @override
  String get taskNextWeek => '来週';

  @override
  String get taskEnterDue => '期限の日付または時刻を入力';

  @override
  String get taskInvalidDue => '有効な日付または時刻を入力してください';

  @override
  String get taskClearDue => '期限をクリア';

  @override
  String get taskDeleteSelectedTitle => '選択したタスクを削除しますか？';

  @override
  String get taskDeleteSelectedMessage => '7秒以内なら元に戻せます。';

  @override
  String get taskCompleteSelected => '選択したタスクを完了';

  @override
  String get taskReopenSelected => '選択したタスクを未完了に戻す';

  @override
  String taskActionFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のタスクを更新できませんでした',
      one: '1件のタスクを更新できませんでした',
    );
    return '$_temp0';
  }

  @override
  String get voiceCollapse => '音声パネルを折りたたむ';

  @override
  String get voiceExpand => '音声パネルを展開';

  @override
  String get voiceMovePanel => '音声パネルを移動';

  @override
  String get themeClassic => 'クラシック';

  @override
  String get themeOcean => 'オーシャン';

  @override
  String get themeForest => 'フォレスト';

  @override
  String get themeCustomize => 'カスタマイズ';

  @override
  String get themeEditorTitle => 'テーマを編集';

  @override
  String get themeLivePreview => '変更はアプリ全体に反映されます。キャンセルすると以前のテーマに戻ります。';

  @override
  String get themeSaveError => 'テーマを保存できませんでした。変更は保持されています。再試行してください。';

  @override
  String get themeLoadError => 'テーマを読み込めませんでした。';

  @override
  String get themeColorsSurfaces => '背景とサーフェス';

  @override
  String get themeColorsText => 'テキスト';

  @override
  String get themeColorsAccent => 'アクセント';

  @override
  String get themeColorsStatus => '状態の色';

  @override
  String get themeInvalidHex => '6桁のHEXカラーを入力してください（例: #2563EB）。';

  @override
  String get themeLowContrast => 'コントラストが低いため、一部の文字が読みにくい可能性があります。';

  @override
  String get themePreviewTask => '1日を計画する';

  @override
  String get themePreviewSecondary => '毎日、少しずつ集中を。';

  @override
  String get themeColorCanvas => '背景';

  @override
  String get themeColorSurface => 'サーフェス';

  @override
  String get themeColorSurfaceTint => '副サーフェス';

  @override
  String get themeColorSurfaceHover => 'ホバー時のサーフェス';

  @override
  String get themeColorPrimaryText => '主要テキスト';

  @override
  String get themeColorSecondaryText => '補助テキスト';

  @override
  String get themeColorMutedText => '控えめなテキスト';

  @override
  String get themeColorBorder => '枠線';

  @override
  String get themeColorAccent => 'アクセントの文字とアイコン';

  @override
  String get themeColorAccentFill => 'アクセントの塗り';

  @override
  String get themeColorAccentTint => '淡いアクセントの塗り';

  @override
  String get themeColorWarning => '警告';

  @override
  String get themeColorInfo => '情報';

  @override
  String get themeColorSuccess => '成功';

  @override
  String get themeColorError => 'エラー';

  @override
  String get themeColorOverdue => '期限切れ';

  @override
  String get themeColorOnAccent => 'アクセント背景の文字';

  @override
  String get themeColorOnError => 'エラー背景の文字';

  @override
  String todayTaskSummary(int tasks, int planned, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      tasks,
      locale: localeName,
      other: 'タスク$tasks件',
      one: 'タスク1件',
    );
    String _temp1 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '予定セッション$planned回',
      one: '予定セッション1回',
    );
    return '$_temp0 · $_temp1 · 集中$time';
  }

  @override
  String get todayFocusingOn => '集中しているタスク';

  @override
  String get openFocus => '集中を開く';

  @override
  String todayCompletedTasks(int count) {
    return '今日の完了 · $count';
  }

  @override
  String get sidebarDaily => '毎日';

  @override
  String get sidebarViews => 'ビュー';

  @override
  String get quickAddResetDetails => 'デフォルトを使う';

  @override
  String get quickAddChangeTime => '時刻を変更';

  @override
  String get quickAddProjectNameUnsupported => 'このプロジェクト名は変更せずに挿入できません。';

  @override
  String get themeSepia => 'セピア';

  @override
  String get themeGraphite => 'グラファイト';

  @override
  String get themeCustom => 'カスタム';

  @override
  String get themeResetToClassic => 'クラシックにリセット';

  @override
  String get themeBackgroundKindTitle => '背景';

  @override
  String get themeBackgroundColor => '色';

  @override
  String get themeBackgroundPhoto => '写真';

  @override
  String get themeBackgroundGlass => 'macOSガラス';

  @override
  String get themeBackgroundGlassHint =>
      'アプリ全体とクイック追加に適用します。ぼかしはmacOSが制御し、スライダーでパレットの色合いを調整します。';

  @override
  String get themeBackgroundGlassUnavailable =>
      'macOSアプリで利用できます。このプラットフォームでは単色の背景を使います。';

  @override
  String get themeBackgroundTitle => '背景画像';

  @override
  String get themeBackgroundMainOnly => 'メイン領域のみ';

  @override
  String get themeBackgroundWholeApp => 'アプリ全体';

  @override
  String get themeBackgroundSeparate => '個別の背景';

  @override
  String get themeBackgroundMain => 'メイン領域';

  @override
  String get themeBackgroundSidebar => 'サイドバー';

  @override
  String get themeBackgroundQuickAdd => 'クイック追加';

  @override
  String get themeBackgroundChoose => '写真を選択';

  @override
  String get themeBackgroundReplace => '写真を変更';

  @override
  String get themeBackgroundRemove => '写真を削除';

  @override
  String get themeBackgroundDim => '暗さ';

  @override
  String get themeBackgroundBlur => 'ぼかし';

  @override
  String get themeBackgroundEmpty => '写真なし';

  @override
  String get themeBackgroundImageError => 'この画像を開けませんでした。別の写真を選んでください。';

  @override
  String get themeBackgroundTooLarge => '50MB以下の画像を選んでください。';

  @override
  String get themeBackgroundLoading => '画像を準備中…';

  @override
  String get settingsTaskListStyle => 'タスク行のスタイル';

  @override
  String get settingsTaskListStyleDescription => '新しいレイアウトか、使い慣れたクラシックな行を選びます。';

  @override
  String get settingsTaskListModern => 'モダン';

  @override
  String get settingsTaskListClassic => 'クラシック';

  @override
  String get settingsTaskRowSpacing => 'タスクの間隔';

  @override
  String get settingsTaskRowSpacingCompact => 'コンパクト';

  @override
  String get settingsTaskRowSpacingComfortable => '標準';

  @override
  String get settingsTaskRowSpacingSpacious => '広め';

  @override
  String get settingsSaveError => '設定を保存できませんでした。再試行してください。';

  @override
  String get focusCompletionCompleteAndNext => '完了して次を開始';

  @override
  String get focusCompletionStartNext => '次のタスクを開始';

  @override
  String get focusCompletionRetry => '再試行';

  @override
  String get searchAllProjects => 'すべてのプロジェクト';

  @override
  String get searchStatusOpen => '未完了';

  @override
  String get searchStatusCompleted => '完了';

  @override
  String get searchStatusAll => 'すべての状態';

  @override
  String get searchClearFilters => 'フィルターをクリア';

  @override
  String get searchEmptyDescription => 'タイトルや説明でタスクを探し、プロジェクトや状態で絞り込めます。';

  @override
  String get searchNoMatchesDescription =>
      '別の語句を試すか、フィルターをクリアしてください。このテキストから新しいタスクを作ることもできます。';

  @override
  String get searchCreateTask => 'テキストからタスクを作成';

  @override
  String get taskListLoadError => 'タスクを読み込めませんでした。再試行してください。';

  @override
  String get inboxEmptyTitle => '受信トレイは空です';

  @override
  String get inboxEmptyDescription => 'ここにアイデアを記録して、いつ取り組むかは後で決めましょう。';

  @override
  String get todayEmptyTitle => '今日の予定はありません';

  @override
  String get todayEmptyDescription => 'タスクを追加して今日を始めましょう。';

  @override
  String get todayEmptyCompletedTitle => '今日のリストは完了です';

  @override
  String get todayEmptyCompletedDescription =>
      '完了したタスクは下に保存されています。準備ができたら次のタスクを追加しましょう。';

  @override
  String get projectEmptyTitle => 'このプロジェクトにはまだタスクがありません';

  @override
  String get projectEmptyDescription => 'プロジェクトの目標に向けた最初の一歩を追加しましょう。';

  @override
  String get commandSearchPlaceholder => 'タスク、プロジェクト、操作を検索';

  @override
  String get commandSearchTasks => 'タスク';

  @override
  String get commandSearchActions => '操作';

  @override
  String get commandSearchDictateTask => 'タスクを音声入力';

  @override
  String get commandSearchAllResults => 'すべての結果を見る';

  @override
  String get commandSearchHint => '↑ ↓ 移動 · Enter 開く · Esc 閉じる';

  @override
  String get commandSearchNoMatches => '一致するタスクやプロジェクトはありません。';

  @override
  String get overdueTitle => '期限切れ';

  @override
  String overdueTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '期限切れのタスク$count件',
      one: '期限切れのタスク$count件',
    );
    return '$_temp0';
  }

  @override
  String get overdueReview => '確認';

  @override
  String get overdueEmpty => '期限切れのタスクはありません';

  @override
  String get taskFocusSwitchTitle => '集中を切り替えますか？';

  @override
  String taskFocusSwitchMessage(String task) {
    return '現在のセッションを停止します。「$task」の集中を開始しますか？';
  }

  @override
  String get taskFocusSwitchConfirm => '切り替え';

  @override
  String get labelIcon => 'ラベルアイコン';

  @override
  String get labelUpdateFailed => 'ラベルを更新できませんでした。再試行してください。';

  @override
  String get labelNotFound => 'ラベルが見つかりません';

  @override
  String get labelTasksSubtitle => 'すべてのプロジェクトでこのラベルの付いたタスク';

  @override
  String labelIconOption(String icon) {
    String _temp0 = intl.Intl.selectLogic(icon, {
      'tag': 'タグ',
      'bookmark': 'ブックマーク',
      'flag': '旗',
      'bolt': '稲妻',
      'lightbulb': '電球',
      'clock': '時計',
      'bell': 'ベル',
      'pin': 'ピン',
      'phone': '電話',
      'mail': 'メール',
      'link': 'リンク',
      'wrench': 'レンチ',
      'other': 'タグ',
    });
    return '$_temp0';
  }

  @override
  String get addSubproject => 'サブプロジェクトを作成';

  @override
  String get moveProject => 'プロジェクトを移動';

  @override
  String get projectTopLevel => '最上位';

  @override
  String get projectMoveUp => '上に移動';

  @override
  String get projectMoveDown => '下に移動';

  @override
  String projectParentName(String name) {
    return '親プロジェクト: $name';
  }

  @override
  String deleteProjectWithChildrenConfirmation(String name) {
    return '「$name」を削除しますか？サブプロジェクトは1つ上の階層に移動します。このプロジェクトのタスクのみ受信トレイに移動します。';
  }

  @override
  String get accountNickname => 'ニックネーム';

  @override
  String get accountChangeNickname => 'ニックネームを変更';

  @override
  String get accountNicknameSaveError => 'ニックネームを保存できませんでした。再試行してください。';

  @override
  String get notificationTaskStarting => 'タスクの開始';

  @override
  String get notificationReturnTitle => 'トマトがあなたを待っています';

  @override
  String get notificationReturnBody => '集中を1回、またはタスクを1つ完了すれば、今日は実りある1日になります。';

  @override
  String get notificationFocusChannel => '集中';

  @override
  String get notificationFocusDescription => '集中インターバル完了の通知';

  @override
  String get notificationReturnChannel => '再開リマインダー';

  @override
  String get notificationReturnDescription => 'Pomodoistの再開を優しくお知らせ';

  @override
  String get notificationTaskChannel => 'タスク開始';

  @override
  String get notificationTaskDescription => 'タスク開始の通知';

  @override
  String get notificationOpenApp => 'Pomodoistを開く';

  @override
  String get notificationFocusCompleted => '集中インターバルが完了しました';

  @override
  String get notificationLongBreakCompleted => '長い休憩が終了しました';

  @override
  String get notificationBreakCompleted => '休憩が終了しました';

  @override
  String get updateTitle => 'Pomodoistの更新';

  @override
  String get updateAction => '更新';

  @override
  String get updateCheck => 'アップデートを確認';

  @override
  String get updateSettings => 'アップデート';

  @override
  String get updateReceiveRc => 'リリース候補（RC）を受け取る';

  @override
  String get updateStableChannel => 'チャンネル: 安定版';

  @override
  String get updateRcChannel => 'チャンネル: 安定版とRC';

  @override
  String get updateRcHelp => 'RCには不具合が含まれる場合があります。アルファ版とベータ版は対象外です。';

  @override
  String get updateRestart => 'アプリを再起動します。データは保持されます。';

  @override
  String get updateNotes => 'リリースノート';

  @override
  String get updateOwnerManaged =>
      'このビルドはサーバー設定を維持するため所有者が更新します。最新版は所有者にお問い合わせください。';

  @override
  String get updateUnsupported =>
      '自動更新は公式Linux AppImageで利用できます。他のビルドはパッケージマネージャーで更新してください。';

  @override
  String updateVersion(String value) {
    return 'バージョン$value';
  }

  @override
  String get updatePhaseIdle => 'いつでも確認できます。';

  @override
  String get updatePhaseChecking => 'リリースを確認中…';

  @override
  String get updatePhaseAvailable => '新しいバージョンがあります';

  @override
  String get updatePhaseDownloading => 'アップデートをダウンロード中…';

  @override
  String get updatePhaseVerifying => '整合性を検証中…';

  @override
  String get updatePhaseInstalling => 'インストールと再起動を準備中…';

  @override
  String get updatePhaseUpToDate => '最新の互換バージョンを使用しています。';

  @override
  String get updatePhaseFailed => 'アップデートを完了できませんでした';

  @override
  String achievementFocusSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '作業の集中を$count回完了する',
      one: '作業の集中を1回完了する',
    );
    return '$_temp0';
  }

  @override
  String achievementTaskSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'タスクを$count件完了する',
      one: 'タスクを1件完了する',
    );
    return '$_temp0';
  }

  @override
  String get achievementDayNotWastedSubtitle => '1日で集中1回とタスク1件を完了する';

  @override
  String get achievementFocusPlusCheckSubtitle => '1日で集中3回とタスク3件を完了する';

  @override
  String get achievementNoFussSubtitle => '1日で集中を中断せずに5回完了する';

  @override
  String get achievementCleanEntrySubtitle => '紐付けられた集中の後にタスクを完了する';

  @override
  String get achievementTomatoClosedSubtitle => '作業の集中と同じ日にタスクを完了する';

  @override
  String achievementTitle(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'focus_1': '初めてのトマト',
      'focus_5': 'ウォームアップ',
      'focus_10': '集中をつかんだ',
      'focus_25': 'トマト勤務',
      'focus_50': 'モード起動',
      'focus_100': '赤帯',
      'focus_250': '深い根',
      'focus_500': 'タイマーの達人',
      'focus_1000': '千個目のトマト',
      'focus_5000': '集中農家',
      'focus_10000': '注意力の農園',
      'focus_50000': 'トマト帝国',
      'focus_100000': '赤い超知能',
      'focus_1000000': 'トマト特異点',
      'task_1': '初めてのチェック',
      'task_5': 'リストが揺れた',
      'task_10': 'うれしいチェックボックス',
      'task_25': '山積みを片付ける',
      'task_50': 'チェックの達人',
      'task_100': 'やり残しを解決',
      'task_250': 'リストを掌握',
      'task_500': 'オフィスの完全勝利',
      'task_1000': '千個のチェック',
      'task_5000': '勝利の記録係',
      'task_10000': 'チェックマシン',
      'task_50000': '解決済み案件局',
      'task_100000': 'リストの支配者',
      'task_1000000': '最後のチェック',
      'combo_day_not_wasted': '実りある1日',
      'combo_focus_plus_check': '集中＋チェック',
      'combo_no_fuss': '慌てず着実に',
      'combo_clean_entry': 'きれいな流れ',
      'combo_tomato_closed_question': 'トマトが解決',
      'other': '実績',
    });
    return '$_temp0';
  }

  @override
  String get focusPresetDeepWork => '深い集中';

  @override
  String get focusPresetShortSprint => '短期スプリント';

  @override
  String csvImportIssueRow(int row, String message) {
    return '$row行目: $message';
  }

  @override
  String csvImportIssueMessage(String code, String value) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'fileTooLarge': 'CSVファイルが16MiBを超えています。',
      'invalidUtf8': 'CSVは有効なUTF-8である必要があります。',
      'missingHeader': 'CSVのヘッダーがありません。',
      'malformed': 'CSVの形式が不正です。',
      'unknownHeader': '不明なヘッダー「$value」です。',
      'duplicateHeader': 'ヘッダー「$value」が重複しています。',
      'contentHeaderRequired': 'contentヘッダーが必要です。',
      'tooManyTasks': 'CSVに含められるタスクは1000件までです。',
      'tooManyFields': '行のフィールド数がヘッダーを超えています。',
      'contentRequired': 'contentは必須です。',
      'invalidPriority': 'priorityは1～4の整数にしてください。',
      'invalidDate': '$valueはYYYY-MM-DD形式にしてください。',
      'mixedSchedule': '期限の日付と時間指定の予定は併用できません。',
      'timedFieldsRequired': '時間指定の予定にはstart_at、end_at、time_zoneが必要です。',
      'invalidTimestamp': '$valueはUTCオフセットを明示したRFC3339形式にしてください。',
      'invalidTimeZone': 'time_zoneは有効なIANA名にしてください。',
      'endBeforeStart': 'end_atはstart_atより後にしてください。',
      'invalidRecurrence': 'recurrenceはday、week、monthのいずれかにしてください。',
      'invalidInteger': '$valueは1～999の整数にしてください。',
      'intervalWithoutRecurrence': 'recurrence_intervalにはrecurrenceが必要です。',
      'recurrenceWithoutSchedule': 'recurrenceには予定が必要です。',
      'doneTask': '完了したタスクはインポートできません。',
      'invalidKey': '$valueの形式が不正です。',
      'empty': 'CSVにタスクが含まれていません。',
      'duplicateKey': 'キー「$value」が重複しています。',
      'parentCycle': 'parent_keyの参照が循環しています。',
      'missingParent': 'parent_key「$value」が存在しません。',
      'childProject': 'サブタスクは親と同じプロジェクトにしてください。',
      'other': 'ファイルをインポートできませんでした。',
    });
    return '$_temp0';
  }

  @override
  String billingOfferDays(int count) {
    return '$count日間';
  }

  @override
  String billingOfferMonths(int count) {
    return '$countか月間';
  }

  @override
  String billingOfferYears(int count) {
    return '$count年間';
  }

  @override
  String billingTrialFree(String duration) {
    return '$duration無料';
  }

  @override
  String billingTrialRenewal(String price) {
    return 'その後は$price。キャンセルしない限り自動更新されます。';
  }

  @override
  String get billingReturnBadge => 'Proに戻る';

  @override
  String billingReturnSubtitle(String duration, String price) {
    return '$durationの割引後は$price。キャンセルしない限り自動更新されます。';
  }

  @override
  String billingReturnPending(String date) {
    return '割引は$dateまで予約されています。購入をキャンセルした場合は、その後に再試行できます。';
  }

  @override
  String get billingReturnFailed => '再加入オファーを確認できませんでした。もう一度お試しください。';

  @override
  String get billingTryFree => '無料で試す';

  @override
  String get collaborationShareProject => 'プロジェクトを共有';

  @override
  String get collaborationShareIntro =>
      'このプロジェクトを一緒に進める人を招待しましょう。メンバーは編集でき、オブザーバーは閲覧のみできます。';

  @override
  String get collaborationShareStart => '共有';

  @override
  String get collaborationMembers => 'メンバー';

  @override
  String get collaborationPendingInvitations => '保留中の招待';

  @override
  String get collaborationRevoke => '取り消す';

  @override
  String get collaborationPublicLink => '公開リンク';

  @override
  String get collaborationPublicLinkHint => 'リンクを知っている人は誰でもこのプロジェクトを閲覧できます';

  @override
  String get collaborationCopyLink => 'リンクをコピー';

  @override
  String get collaborationConflicts => '同期の競合';

  @override
  String get collaborationLeaveProject => 'プロジェクトから退出';

  @override
  String get collaborationDeleteSharedProject => '全員から削除';

  @override
  String get collaborationOwner => 'オーナー';

  @override
  String get collaborationTransferOwnership => '所有権を移譲';

  @override
  String get collaborationRemoveMember => 'メンバーを削除';

  @override
  String get collaborationEmail => 'メールアドレス';

  @override
  String get collaborationInvite => '招待';

  @override
  String get collaborationConflictHint => '別のメンバーもこの項目を変更しました';

  @override
  String get collaborationConflictKeepLocal => '自分の変更を残す';

  @override
  String get collaborationConflictUseServer => 'サーバー版を使う';

  @override
  String get collaborationProjectShared => 'プロジェクトを共有しました';

  @override
  String get collaborationInviteEmailFailed => '招待は保存されましたが、メールを送信できませんでした';

  @override
  String collaborationInviteSent(String email) {
    return '$email に招待を送信しました';
  }

  @override
  String get collaborationInvitationRevoked => '招待を取り消しました';

  @override
  String get collaborationRoleUpdated => 'ロールを更新しました';

  @override
  String collaborationRemoveConfirm(String name) {
    return '$name をこのプロジェクトから削除しますか？';
  }

  @override
  String get collaborationMemberRemoved => 'メンバーを削除しました';

  @override
  String collaborationTransferConfirm(String name) {
    return '$name をこのプロジェクトのオーナーにしますか？';
  }

  @override
  String get collaborationOwnershipTransferred => '所有権を移譲しました';

  @override
  String get collaborationLeaveConfirm => 'この共有プロジェクトから退出しますか？';

  @override
  String get collaborationLeftProject => 'プロジェクトから退出しました';

  @override
  String get collaborationDeleteSharedConfirm =>
      'この共有プロジェクトを全メンバーから削除しますか？元に戻せません。';

  @override
  String get collaborationSharedProjectDeleted => '共有プロジェクトを削除しました';

  @override
  String get collaborationLinkCopied => 'リンクをコピーしました';

  @override
  String get collaborationConflictResolved => '競合を解決しました';

  @override
  String get collaborationRoleAdministrator => '管理者';

  @override
  String get collaborationRoleMember => 'メンバー';

  @override
  String get collaborationRoleObserver => 'オブザーバー';

  @override
  String get collaborationForbidden => '権限がありません';

  @override
  String get collaborationSignedOut => '共有プロジェクトを使うにはサインインしてください';

  @override
  String get collaborationUnavailable => '共有プロジェクトは現在ご利用いただけません';

  @override
  String get collaborationError => '問題が発生しました。もう一度お試しください';

  @override
  String get collaborationSyncPending => '共有する前にこのプロジェクトの同期を完了してください';

  @override
  String get collaborationMemberFallback => 'メンバー';

  @override
  String get collaborationInboxTitle => '共有プロジェクトと招待';

  @override
  String get collaborationInboxSubtitle => '招待を承認し、共有プロジェクトのアクティビティを確認します';

  @override
  String get collaborationInvitations => '招待';

  @override
  String get collaborationNoInvitations => '保留中の招待はありません';

  @override
  String get collaborationAccept => '承認';

  @override
  String get collaborationNotifications => '通知';

  @override
  String get collaborationMarkAllRead => 'すべて既読にする';

  @override
  String get collaborationNoNotifications => '通知はありません';

  @override
  String get collaborationNotificationInvitation => '共有プロジェクトへの招待';

  @override
  String get collaborationNotificationDiscussion => '共有プロジェクトの新しいコメント';

  @override
  String get collaborationNotificationAssignment => 'タスクが割り当てられました';

  @override
  String get collaborationNotificationGeneric => '共有プロジェクトのアクティビティ';

  @override
  String get collaborationInvitationAccepted => '招待を承認しました';

  @override
  String get collaborationAssignees => '担当者';

  @override
  String get collaborationEditAssignees => '担当者を編集';

  @override
  String get collaborationNoAssignees => '担当者なし';

  @override
  String get collaborationComments => 'コメント';

  @override
  String get collaborationCommentHint => 'コメントを書く';

  @override
  String get collaborationCommentSend => '送信';

  @override
  String get collaborationCommentDelete => 'コメントを削除';

  @override
  String get collaborationSharedBadge => '共有プロジェクト';
}

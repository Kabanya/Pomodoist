// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsSectionGeneral => 'Общие';

  @override
  String get settingsSectionAppearance => 'Внешний вид';

  @override
  String get settingsSectionTasksFocus => 'Задачи и Фокус';

  @override
  String get settingsSectionIntegrations => 'Интеграции и данные';

  @override
  String get settingsSectionAccount => 'Аккаунт и Pro';

  @override
  String get settingsThemeColorsTab => 'Цвета';

  @override
  String get settingsThemeBackgroundsTab => 'Фоны';

  @override
  String get settingsRefreshAccount => 'Обновить аккаунт';

  @override
  String get settingsSubscriptionActions => 'Управление подпиской';

  @override
  String get settingsSubscriptionError =>
      'Не удалось обновить подписку. Ранее подтверждённый доступ сохранён.';

  @override
  String get settingsVersionError => 'Не удалось загрузить версию.';

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Добавить';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonUndo => 'Отменить';

  @override
  String get commonOpen => 'Открыть';

  @override
  String get commonBack => 'Назад';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonCreate => 'Создать';

  @override
  String get commonClear => 'Очистить';

  @override
  String get commonStop => 'Стоп';

  @override
  String get skip => 'Пропустить';

  @override
  String get onboardingLanguageTitle => 'Выберите язык';

  @override
  String get onboardingLanguageSubtitle =>
      'Выберите язык интерфейса Pomodoist.';

  @override
  String get onboardingTimerTitle => 'Выберите вид таймера';

  @override
  String get onboardingTimerSubtitle =>
      'Выберите, как показывать прогресс Pomodoro во время фокуса.';

  @override
  String get onboardingPaywallTitle => 'Откройте Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'Акция Lifetime доступна 24 часа каждую неделю.';

  @override
  String get onboardingAccountTitle => 'Создайте аккаунт';

  @override
  String get onboardingAccountSubtitle =>
      'Войдите, чтобы синхронизировать задачи, фокус и настройки между устройствами.';

  @override
  String get startupPreparingTasks => 'Готовим ваши задачи';

  @override
  String get operationTakingLonger =>
      'Операция занимает больше времени, чем обычно, но всё ещё выполняется.';

  @override
  String get onboardingContinue => 'Продолжить';

  @override
  String get onboardingMaybeLater => 'Позже';

  @override
  String get onboardingFinish => 'Готово';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Диктуйте задачи естественным языком, а Pomodoist сам превратит речь в задачи. История задач сохраняется навсегда.';

  @override
  String get billingSubtitleHighlight => 'естественным языком';

  @override
  String get billingCancelAnytime => 'Подписку можно отменить в любое время.';

  @override
  String get billingMonthlyTitle => 'Месяц';

  @override
  String get billingAnnualTitle => 'Год';

  @override
  String billingPricePerMonth(String price) {
    return '$price/мес.';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/год';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'Первые 3 месяца, затем $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Затем $price.';
  }

  @override
  String get billingLifetimeTitle => 'Навсегда';

  @override
  String get billingLifetimeSubtitle => 'Один платеж навсегда.';

  @override
  String get billingBestValue => 'Выгодно';

  @override
  String get billingChoose => 'Выбрать';

  @override
  String get billingActive => 'Pomodoist Pro активен на этом устройстве.';

  @override
  String get billingActiveShort => 'Активно';

  @override
  String get billingRestore => 'Восстановить покупки';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get termsOfUse => 'Условия использования';

  @override
  String get support => 'Поддержка';

  @override
  String get billingManageLink => 'Управлять через Link';

  @override
  String get billingExternalBrowserTitle => 'Оплата откроется в браузере';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist откроет Stripe Checkout в Safari или браузере по умолчанию. Разрешите открытие окна, чтобы продолжить.';

  @override
  String get billingAppleOnly => 'Покупки доступны через App Store.';

  @override
  String get billingStoreUnavailable => 'App Store сейчас недоступен.';

  @override
  String get billingStoreConnectionFailed =>
      'Отключите VPN и повторите попытку.';

  @override
  String billingPurchaseError(String error) {
    return 'Ошибка покупки: $error';
  }

  @override
  String get billingStripeAuthenticationRequired =>
      'Войдите в Pomodoist и попробуйте снова.';

  @override
  String get billingStripeDisabled =>
      'Платежи пока недоступны. Попробуйте позже.';

  @override
  String get billingStripeAlreadyEntitled =>
      'Pomodoist Pro уже активен. Обновите статус аккаунта.';

  @override
  String get billingStripeOfferExpired =>
      'Срок действия акции истёк. Выберите другой доступный тариф.';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'Платежи Stripe временно недоступны. Попробуйте позже или обратитесь в поддержку.';

  @override
  String get billingStripeCheckoutFailed =>
      'Не удалось начать оплату. Проверьте подключение к интернету и попробуйте снова.';

  @override
  String get purchaseSuccessTitle => 'Готово, Pro активен';

  @override
  String get purchaseSuccessMessage =>
      'Спасибо за поддержку Pomodoist. Все Pro-возможности уже доступны.';

  @override
  String get purchaseSuccessContinue => 'Продолжить';

  @override
  String get purchaseProcessingTitle => 'Платёж обрабатывается';

  @override
  String get purchaseProcessingMessage =>
      'Подтверждаем платёж. Если Pro не появится вскоре, попробуйте обновить позже.';

  @override
  String get purchaseOpenApp => 'Открыть Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return '$time до конца акции Lifetime';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'Email';

  @override
  String get loginTitle => 'Войти в Pomodoist';

  @override
  String get accountChecking => 'Проверяем аккаунт';

  @override
  String get oauthConsentTitle => 'Подключить агента';

  @override
  String get oauthConsentLoading => 'Проверяем запрос на подключение';

  @override
  String get oauthConsentInvalidAuthorization =>
      'Запрос на подключение отсутствует или недействителен.';

  @override
  String get oauthConsentLoadError =>
      'Не удалось загрузить запрос на подключение.';

  @override
  String get oauthConsentActionError =>
      'Не удалось выполнить запрос. Попробуйте ещё раз.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist получил небезопасный или отсутствующий адрес возврата. Доступ не был передан.';

  @override
  String get oauthConsentClientFallback => 'Агент';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName запрашивает доступ к Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Адрес возврата';

  @override
  String get oauthConsentCapabilitiesTitle => 'Этот агент сможет';

  @override
  String get oauthConsentManagePlanning =>
      'Читать и изменять задачи, проекты, пользовательские метки и канбан.';

  @override
  String get oauthConsentReadInsights =>
      'Читать историю завершённого фокуса, отчёты продуктивности и достижения.';

  @override
  String get oauthConsentUnavailableTitle => 'Этот агент не сможет';

  @override
  String get oauthConsentUnavailable =>
      'Получать доступ к аккаунту и оплате, Google Calendar или активному таймеру фокуса.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'Запрос требует неподдерживаемого доступа к аккаунту и не может быть одобрен.';

  @override
  String get oauthConsentApprove => 'Разрешить';

  @override
  String get oauthConsentDeny => 'Отклонить';

  @override
  String get oauthConsentApproving => 'Разрешаем доступ…';

  @override
  String get oauthConsentDenying => 'Отклоняем запрос…';

  @override
  String get oauthConsentRedirecting => 'Возвращаемся к агенту…';

  @override
  String get loginCreateAccountPrompt => 'Нет аккаунта?';

  @override
  String get loginCreateAccountAction => 'Создать аккаунт';

  @override
  String get registerTitle => 'Создайте аккаунт';

  @override
  String get registerSubtitle =>
      'Синхронизируйте задачи, фокус и настройки между устройствами.';

  @override
  String get registerPassword => 'Пароль';

  @override
  String get registerSubmit => 'Создать аккаунт';

  @override
  String get registerSignInPrompt => 'Уже есть аккаунт?';

  @override
  String get registerSignInAction => 'Войти';

  @override
  String get registerCheckEmailTitle => 'Проверьте email';

  @override
  String get registerCheckEmailMessage =>
      'Если этому адресу требуется подтверждение, вы получите письмо со ссылкой. Если аккаунт уже есть, войдите или восстановите пароль.';

  @override
  String registerError(Object error) {
    return 'Не удалось создать аккаунт: $error';
  }

  @override
  String get authEmailSignInTitle => 'Вход по email';

  @override
  String get authWelcomeTitle => 'Войдите в Pomodoist';

  @override
  String get authWelcomeDescription =>
      'Ваши задачи и фокус — на каждом устройстве.';

  @override
  String get authSignInWithLink => 'Войти по ссылке';

  @override
  String get authForgotPassword => 'Забыли пароль?';

  @override
  String get authBackToSignIn => 'Назад ко входу';

  @override
  String get authNoAccount => 'Нет аккаунта?';

  @override
  String get authHaveAccount => 'Уже есть аккаунт?';

  @override
  String get authShowPassword => 'Показать пароль';

  @override
  String get authHidePassword => 'Скрыть пароль';

  @override
  String get authResetTitle => 'Сбросьте пароль';

  @override
  String get authResetDescription =>
      'Введите email аккаунта. Мы отправим ссылку для смены пароля.';

  @override
  String get authResetEmailSentTitle => 'Проверьте email';

  @override
  String get authResetEmailSent =>
      'Если аккаунт с таким email существует, вы получите ссылку для сброса пароля.';

  @override
  String get authResetSendAgain => 'Отправить снова';

  @override
  String get authResetEditEmail => 'Изменить email';

  @override
  String get authNewPasswordTitle => 'Придумайте новый пароль';

  @override
  String get authNewPasswordDescription =>
      'Используйте пароль, которого нет у других ваших аккаунтов.';

  @override
  String get authNewPassword => 'Новый пароль';

  @override
  String get authConfirmPassword => 'Повторите пароль';

  @override
  String get authSavePassword => 'Сохранить пароль';

  @override
  String get authPasswordMismatch => 'Пароли не совпадают.';

  @override
  String get authPasswordUnchanged => 'Выберите пароль, отличный от текущего.';

  @override
  String get authPasswordUpdatedTitle => 'Пароль обновлён';

  @override
  String get authPasswordUpdatedMessage =>
      'Новый пароль сохранён. Вы можете продолжить работу в Pomodoist.';

  @override
  String get authResetLinkExpired =>
      'Ссылка для сброса пароля недействительна или устарела. Запросите новую.';

  @override
  String get authUnexpectedReset =>
      'Не удалось отправить письмо для сброса пароля. Попробуйте снова.';

  @override
  String get authUnexpectedPasswordUpdate =>
      'Не удалось сохранить новый пароль. Попробуйте снова.';

  @override
  String get authCheckingResetLink => 'Проверяем ссылку для сброса пароля…';

  @override
  String get authSignInAction => 'Войти';

  @override
  String get authSendLink => 'Отправить ссылку';

  @override
  String get authMagicLinkSent =>
      'Если для этого адреса есть аккаунт, вы получите ссылку для входа. Проверьте входящие и папку «Спам».';

  @override
  String get authAccountCreated => 'Аккаунт создан.';

  @override
  String get authSignedIn => 'Вход выполнен.';

  @override
  String get authEmailRequired => 'Введите email.';

  @override
  String get authEmailInvalid =>
      'Проверьте адрес email, например name@example.com.';

  @override
  String get authPasswordRequired => 'Введите пароль.';

  @override
  String get authInvalidCredentials =>
      'Неверная почта или пароль. Проверьте адрес, восстановите пароль или создайте аккаунт.';

  @override
  String get authEmailUnconfirmed =>
      'Подтвердите email по ссылке из письма, затем войдите снова.';

  @override
  String get authWeakPassword =>
      'Этот пароль слишком легко угадать. Используйте более длинный и менее предсказуемый пароль.';

  @override
  String get authAccountMayExist =>
      'Возможно, аккаунт с этой почтой уже существует. Войдите или восстановите пароль.';

  @override
  String get authRateLimited =>
      'Слишком много попыток. Подождите несколько минут и повторите.';

  @override
  String get authEmailRateLimited =>
      'Запрошено слишком много писем. Подождите несколько минут перед новым запросом.';

  @override
  String get authOffline =>
      'Не удалось подключиться к сервису аккаунтов. Проверьте интернет и повторите.';

  @override
  String get authTimeout =>
      'Сервис аккаунтов отвечает слишком долго. Повторите попытку.';

  @override
  String get authServiceUnavailable =>
      'Сервис аккаунтов временно недоступен. Попробуйте позже.';

  @override
  String get authCaptchaRequired =>
      'Пройдите проверку безопасности, чтобы продолжить.';

  @override
  String get authCaptchaExpired =>
      'Время проверки безопасности истекло. Пройдите её снова.';

  @override
  String get authCaptchaFailed =>
      'Не удалось пройти проверку безопасности. Повторите проверку.';

  @override
  String get authCaptchaCancelled =>
      'Проверка безопасности отменена. Запустите её снова, чтобы продолжить.';

  @override
  String get authCaptchaUnavailable =>
      'Проверка безопасности сейчас недоступна. Проверьте интернет и повторите.';

  @override
  String get authCaptchaOpenFailed =>
      'Pomodoist не смог открыть проверку безопасности в браузере. Проверьте браузер по умолчанию и повторите.';

  @override
  String get authProviderFallback => 'этого сервиса';

  @override
  String authProviderUnavailable(String provider) {
    return 'Вход через $provider сейчас недоступен. Повторите или выберите другой способ.';
  }

  @override
  String get authSignUpDisabled =>
      'Регистрация по email временно недоступна. Выберите другой способ входа.';

  @override
  String get authAccountRestricted =>
      'Сейчас войти в этот аккаунт нельзя. Обратитесь в поддержку, если считаете это ошибкой.';

  @override
  String get authLinkExpired =>
      'Ссылка для входа недействительна или устарела. Запросите новую.';

  @override
  String get authUnexpectedSignIn => 'Не удалось войти. Попробуйте снова.';

  @override
  String get authUnexpectedSignUp =>
      'Не удалось создать аккаунт. Попробуйте снова.';

  @override
  String get authUnexpectedMagicLink =>
      'Не удалось отправить ссылку для входа. Попробуйте снова.';

  @override
  String get authResendConfirmation => 'Отправить подтверждение ещё раз';

  @override
  String get authConfirmationSendFailed =>
      'Не удалось отправить письмо подтверждения. Попробуйте позже.';

  @override
  String get authRetryVerification => 'Повторить проверку';

  @override
  String get captchaSecurityLabel => 'Проверка безопасности';

  @override
  String get captchaChallengeTitle => 'Проверка безопасности Pomodoist';

  @override
  String get captchaChallengePrompt =>
      'Подтвердите, что вы человек, чтобы продолжить в Pomodoist.';

  @override
  String get captchaChallengeInvalid =>
      'Ссылка проверки безопасности недействительна. Вернитесь в Pomodoist и попробуйте снова.';

  @override
  String get captchaChallengeHandoffHelp =>
      'Если Pomodoist не открылся, нажмите кнопку ниже. Если приложение не установлено, закройте страницу и вернитесь к устройству, где начали вход.';

  @override
  String get captchaReturnToApp => 'Вернуться в Pomodoist';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navInbox => 'Входящее';

  @override
  String get navPriorityMatrix => 'Матрица приоритетов';

  @override
  String get navTimeline => 'Таймлайн';

  @override
  String get navKanban => 'Канбан';

  @override
  String get kanbanTitle => 'Канбан';

  @override
  String get kanbanSubtitle =>
      'Визуализируйте процесс и сосредоточьтесь на самом важном.';

  @override
  String get kanbanDefaultBacklog => 'Бэклог';

  @override
  String get kanbanDefaultTodo => 'К выполнению';

  @override
  String get kanbanDefaultInProgress => 'В работе';

  @override
  String get kanbanDefaultDone => 'Готово';

  @override
  String get kanbanSearchTooltip => 'Поиск по канбану';

  @override
  String get kanbanSearchHint => 'Искать задачи или проекты';

  @override
  String get kanbanHideDone => 'Скрыть готовые';

  @override
  String get kanbanShowDone => 'Показать готовые';

  @override
  String get kanbanProjectsTitle => 'Проекты на этой доске';

  @override
  String kanbanAddToStatus(String status) {
    return 'Добавить в «$status»';
  }

  @override
  String get kanbanTaskField => 'Задача';

  @override
  String get kanbanProjectField => 'Проект';

  @override
  String get kanbanChooseProject => 'Выберите проект.';

  @override
  String get kanbanTaskActions => 'Действия с задачей';

  @override
  String get kanbanDragTask => 'Перетащить задачу';

  @override
  String kanbanMoveTo(String status) {
    return 'Переместить в «$status»';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Сначала восстановите задачу, затем запускайте фокус.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'Не удалось запустить фокус: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'Не удалось загрузить канбан: $error';
  }

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonContinueWaiting => 'Продолжить ожидание';

  @override
  String kanbanTasksCount(int count) {
    return 'Задач: $count';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return 'Подзадачи: $completed из $total';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return 'Фокус-интервалы: $completed из $total';
  }

  @override
  String get kanbanActive => 'Активно';

  @override
  String kanbanPriority(int priority) {
    return 'Приоритет $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Перемещено в «$status»';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Фокус запущен для задачи «$task»';
  }

  @override
  String get kanbanNoTasks => 'Задач пока нет';

  @override
  String get navToday => 'Сегодня';

  @override
  String get navUpcoming => 'Предстоящее';

  @override
  String get navBrowse => 'Обзор';

  @override
  String get navIntegrations => 'Интеграции';

  @override
  String get navReports => 'Отчеты';

  @override
  String get navFocus => 'Фокус';

  @override
  String get navProjects => 'Проекты';

  @override
  String get navSettings => 'Настройки';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsAboutTitle => 'О приложении';

  @override
  String get settingsFocusCompletionCelebrationTitle =>
      'Праздничное завершение фокуса';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      'Показывать полноэкранное поздравление после последнего отдыха.';

  @override
  String get settingsVersionLabel => 'Версия';

  @override
  String get settingsPlanLabel => 'Тариф';

  @override
  String get settingsPlanFree => 'Бесплатный';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'Быстрые команды';

  @override
  String get settingsShortcutsSubtitle =>
      'Настройте команды для аппаратной клавиатуры.';

  @override
  String get settingsShortcutsToggleSidebar =>
      'Показать или скрыть боковую панель';

  @override
  String get settingsShortcutsGlobalQuickAdd => 'Глобальное быстрое добавление';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Работает, даже когда Pomodoist неактивен.';

  @override
  String get settingsShortcutsRecordTitle => 'Нажмите сочетание клавиш';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Используйте клавишу вместе с Command, Control или Alt. Esc — отмена.';

  @override
  String get settingsShortcutsInvalid => 'Добавьте Command, Control или Alt.';

  @override
  String get settingsShortcutsConflict => 'Это сочетание уже используется.';

  @override
  String get settingsShortcutsGlobalError =>
      'Глобальное сочетание недоступно. Предыдущее сочетание осталось активным.';

  @override
  String get settingsShortcutsResetAll => 'Сбросить все';

  @override
  String get settingsShortcutsResetDone => 'Быстрые команды сброшены.';

  @override
  String get csvImportTitle => 'Импорт задач из CSV';

  @override
  String get csvImportSubtitle =>
      'Проверьте CSV-файл перед созданием задач, проектов, меток и статусов.';

  @override
  String get csvImportSelectFile => 'Выбрать CSV-файл';

  @override
  String get csvImportHumanGuideButton => 'Инструкция для человека';

  @override
  String get csvImportAgentGuideButton => 'Инструкция для агента';

  @override
  String get csvImportHumanGuideTitle => 'Как подготовить CSV-файл';

  @override
  String get csvImportAgentGuideTitle => 'CSV-контракт для агента';

  @override
  String get csvImportCopy => 'Копировать';

  @override
  String get csvImportCopied => 'Скопировано в буфер обмена.';

  @override
  String get csvImportPreviewTitle => 'Проверка импорта';

  @override
  String get csvImportPreviewTasks => 'Задачи';

  @override
  String get csvImportPreviewSubtasks => 'Подзадачи';

  @override
  String get csvImportPreviewNewProjects => 'Новые проекты';

  @override
  String get csvImportPreviewNewLabels => 'Новые метки';

  @override
  String get csvImportPreviewNewStatuses => 'Новые статусы';

  @override
  String get csvImportNone => 'Нет';

  @override
  String get csvImportDuplicateWarning =>
      'Повторный импорт того же файла создаст дубликаты задач.';

  @override
  String get csvImportConfirm => 'Импортировать';

  @override
  String get csvImportSuccess => 'Импортировано задач';

  @override
  String get csvImportErrorTitle => 'Не удалось импортировать CSV';

  @override
  String get csvImportUnexpectedError => 'Не удалось импортировать файл.';

  @override
  String get csvImportHumanGuide =>
      '1. Сохраните файл в формате CSV с кодировкой UTF-8. В качестве разделителя используйте запятую (рекомендуется) или точку с запятой.\n\n2. Обязателен столбец content. Также доступны: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Одна строка создаёт одну открытую задачу. Метки разделяйте символом |. Приоритет — от 1 до 4, пустое значение означает 4. Пустой проект означает Inbox, а пустой статус — Backlog. Недостающие проекты, метки и открытые статусы создаются автоматически.\n\n4. Для задачи на весь день укажите due_date в формате YYYY-MM-DD. Для задачи со временем заполните start_at и end_at в формате RFC3339 со смещением UTC и укажите часовой пояс IANA, например Europe/Moscow.\n\n5. Для подзадач задайте родительской строке уникальный key и укажите его в parent_key дочерней строки. Родитель может находиться ниже в файле. Проект подзадачи должен совпадать с проектом родителя.\n\n6. Перед импортом Pomodoist проверит весь файл и покажет предварительный просмотр. Если хотя бы одна строка неверна, ничего не сохранится. Повторный импорт создаёт дубликаты.';

  @override
  String get settingsConnectedAgentsTitle => 'Подключённые агенты';

  @override
  String get settingsConnectedAgentsLoading => 'Загрузка подключённых агентов…';

  @override
  String get settingsConnectedAgentsEmpty => 'Нет подключённых агентов.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'Не удалось загрузить подключённых агентов.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Агент';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Дата подключения: $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Отозвать доступ';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'Отозвать доступ агента?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'Отозвать доступ к Pomodoist для «$clientName»?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'Не удалось отозвать доступ. Повторите попытку.';

  @override
  String get settingsLanguageTitle => 'Язык';

  @override
  String get settingsLanguageSubtitle => 'Выберите язык приложения.';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsVoiceTranscriptionTitle => 'Транскрибация голоса';

  @override
  String get settingsVoiceTranscriptionSubtitle =>
      'Выберите, как преобразовывать записи в текст на этом устройстве.';

  @override
  String get settingsVoiceTranscriptionSystem => 'Системная (Apple)';

  @override
  String get settingsVoiceTranscriptionCloud => 'Облачная';

  @override
  String get settingsVoiceTranscriptionCloudDescription =>
      'Облачная транскрибация отправляет аудио в Pomodoist и требует подключения к интернету.';

  @override
  String get settingsVoiceTranscriptionCloudRequiresSignIn =>
      'Войдите, чтобы использовать облачную транскрибацию. До этого будет активна системная.';

  @override
  String get settingsThemeTitle => 'Тема';

  @override
  String get settingsThemeSubtitle => 'Выберите оформление приложения.';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Темная';

  @override
  String get settingsTimerVisualTitle => 'Таймер Pomodoro';

  @override
  String get settingsTimerVisualSubtitle =>
      'Выберите, как показывать прогресс на экране фокуса.';

  @override
  String get settingsTimerVisualBar => 'Полоса';

  @override
  String get settingsTimerVisualCircle => 'Круг';

  @override
  String get settingsReturnRemindersTitle => 'Напоминания о возвращении';

  @override
  String get settingsReturnRemindersSubtitle =>
      'Напоминание в 20:30, только если за сегодня не закрыто ни одной задачи.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Длительность блока по умолчанию';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'Если указано только время, новая задача займет столько минут в календаре.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Свое значение';

  @override
  String get settingsDefaultTimedBlockError => 'Введите от 1 до 480 минут.';

  @override
  String get settingsTaskTimeDisplayTitle => 'Отображение времени задач';

  @override
  String get settingsTaskTimeDisplaySubtitle =>
      'Выберите, как показывать расписание задач со временем.';

  @override
  String get settingsTaskTimeDisplaySmart => 'Умное';

  @override
  String get settingsTaskTimeDisplayRange => 'Время начала и окончания';

  @override
  String get settingsTaskTimeDisplayStartOnly => 'Только время начала';

  @override
  String get taskTimeStatusFuture => 'Предстоит';

  @override
  String get taskTimeStatusFocused => 'В фокусе';

  @override
  String get taskTimeStatusCurrent => 'Сейчас выполняется';

  @override
  String get taskTimeStatusOverdue => 'Просрочено';

  @override
  String get taskTimeStatusCompleted => 'Завершено';

  @override
  String get menuTooltip => 'Меню';

  @override
  String get localUser => 'Локальный пользователь';

  @override
  String get addTask => 'Добавить задачу';

  @override
  String get quickAddHint => 'Написать sync engine завтра p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'Не удалось добавить задачу: $error';
  }

  @override
  String get taskCreateFailed =>
      'Не удалось создать задачу. Попробуйте ещё раз.';

  @override
  String couldNotAddProject(Object error) {
    return 'Не удалось добавить проект: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено $count задачи',
      many: 'Добавлено $count задач',
      few: 'Добавлено $count задачи',
      one: 'Добавлена 1 задача',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Голосовое добавление';

  @override
  String get voiceTitle => 'Голосовое добавление';

  @override
  String get voiceRecord => 'Записать';

  @override
  String get voiceAgain => 'Заново';

  @override
  String get voiceStop => 'Стоп';

  @override
  String voiceAddCount(int count) {
    return 'Добавить $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Задача $index';
  }

  @override
  String get voiceRemoveTask => 'Удалить';

  @override
  String get voiceInstruction => 'Нажмите запись и продиктуйте задачи.';

  @override
  String get voiceStatusIdle => 'Ввод только со встроенного микрофона';

  @override
  String get voiceStatusRequestingPermission => 'Запрашиваю доступ';

  @override
  String get voiceStatusRecording => 'Слушаю встроенный микрофон';

  @override
  String get voiceStatusTranscribing => 'Расшифровываю запись';

  @override
  String get voiceStatusCanceled => 'Запись отменена';

  @override
  String get voiceStatusUnsupported => 'Платформа не поддержана';

  @override
  String get voiceStatusError => 'Не удалось распознать речь';

  @override
  String get voiceStatusAnalyzing => 'Разбиваю на задачи';

  @override
  String get voiceStatusReview => 'Проверьте задачи перед добавлением';

  @override
  String get voiceStepRecord => 'Запись';

  @override
  String get voiceStepText => 'Текст';

  @override
  String get voiceStepAnalyze => 'Разбор';

  @override
  String get voiceStepReview => 'Проверка';

  @override
  String get voiceAnalyzing => 'Pomodoist раскладывает речь на задачи';

  @override
  String get voiceFallbackError =>
      'Pomodoist не смог обработать речь, оставил черновик для ручной правки.';

  @override
  String get voiceMicrophoneUnavailable =>
      'Микрофон сейчас недоступен. Завершите активный звонок или голосовой чат и повторите попытку.';

  @override
  String get voiceSmartMode => 'Умный режим';

  @override
  String get voiceRetryTranscription => 'Повторить распознавание';

  @override
  String get voiceRecordingSaved =>
      'Запись сохранена на этом устройстве. Можно повторить распознавание без новой диктовки.';

  @override
  String get voiceAllowAccess => 'Разрешить доступ';

  @override
  String get voiceOpenMicrophoneSettings => 'Открыть настройки микрофона';

  @override
  String get voiceOpenSpeechSettings => 'Открыть настройки распознавания';

  @override
  String get voiceEnableDictation => 'Включить Диктовку';

  @override
  String get voiceUseCloudTranscription =>
      'Использовать облачную транскрибацию';

  @override
  String get voiceMicrophoneDenied =>
      'Разрешите доступ к микрофону в системных настройках.';

  @override
  String get voiceSpeechDenied =>
      'Разрешите распознавание речи в системных настройках.';

  @override
  String get voiceAccessRestricted =>
      'Доступ ограничен администратором или настройками «Экранного времени».';

  @override
  String get voiceDictationDisabled =>
      'Включите Диктовку: Системные настройки → Клавиатура → Диктовка. Выберите язык и повторите распознавание.';

  @override
  String get voiceServiceUnavailable =>
      'Распознавание недоступно. Проверьте подключение к интернету. На Mac также проверьте язык и Диктовку: Системные настройки → Клавиатура → Диктовка.';

  @override
  String get voiceCloudServiceUnavailable =>
      'Облачная транскрибация не удалась. Проверьте подключение к интернету и повторите распознавание сохранённой записи.';

  @override
  String get voiceLocaleUnsupported =>
      'Системное распознавание не поддерживает выбранный язык на этом устройстве.';

  @override
  String get voiceNetworkUnavailable =>
      'Для распознавания этого языка нужен интернет. Подключитесь и повторите попытку.';

  @override
  String get voiceSettingsFailed =>
      'Не удалось открыть настройки. Откройте системные настройки вручную и проверьте доступ к микрофону и распознаванию речи. На Mac также проверьте раздел Клавиатура → Диктовка.';

  @override
  String get voiceRetryAnalysis => 'Повторить разбор';

  @override
  String get screenInboxSubtitle => 'Собирайте задачи перед сортировкой.';

  @override
  String get priorityMatrixSubtitle =>
      'Перетаскивайте задачи между приоритетами. Даты только сортируют задачи внутри приоритета.';

  @override
  String get priorityMatrixP1Title => 'Сделать сейчас';

  @override
  String get priorityMatrixP2Title => 'Запланировать';

  @override
  String get priorityMatrixP3Title => 'Делегировать';

  @override
  String get priorityMatrixP4Title => 'Убрать';

  @override
  String get priorityMatrixAxisUrgent => 'Срочно';

  @override
  String get priorityMatrixAxisNotUrgent => 'Не срочно';

  @override
  String get priorityMatrixAxisImportant => 'Важно';

  @override
  String get priorityMatrixAxisNotImportant => 'Не важно';

  @override
  String get timelineSubtitle => 'Планируйте один день на временной сетке.';

  @override
  String get timelineAllDay => 'Весь день';

  @override
  String get timelineBeforeHours => 'До видимых часов';

  @override
  String get timelineAfterHours => 'После видимых часов';

  @override
  String get timelineVisibleHours => 'Видимые часы';

  @override
  String get timelineStartHour => 'Начало';

  @override
  String get timelineEndHour => 'Конец';

  @override
  String get timelineZoomOut => 'Отдалить';

  @override
  String get timelineZoomIn => 'Приблизить';

  @override
  String timelineAddTimedHint(String time) {
    return 'Задача на $time';
  }

  @override
  String get timelineAddAllDayHint => 'Задача на весь день';

  @override
  String get timelineNoAllDayTasks => 'Нет задач на весь день';

  @override
  String get timelineNoTimedTasks => 'Нет задач со временем';

  @override
  String get timelinePreviousDay => 'Предыдущий день';

  @override
  String get timelineNextDay => 'Следующий день';

  @override
  String get timelinePickDate => 'Выбрать дату';

  @override
  String get upcomingPreviousPeriod => 'Предыдущий период';

  @override
  String get upcomingNextPeriod => 'Следующий период';

  @override
  String get upcomingOpenDatePicker => 'Открыть выбор даты';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count задачи',
      many: '$count задач',
      few: '$count задачи',
      one: '$count задача',
      zero: 'Нет задач',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Нагрузка: $planned интервалов - Готово: $completed - Фокус: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Запланированные задачи после сегодня.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Задачи на $date.';
  }

  @override
  String get noTasksHere => 'Здесь нет задач';

  @override
  String get noUpcomingTasks => 'Нет задач с датой';

  @override
  String get noTasksForDay => 'На этот день задач нет';

  @override
  String failedToLoadTasks(Object error) {
    return 'Не удалось загрузить задачи: $error';
  }

  @override
  String get searchTasks => 'Поиск задач';

  @override
  String get searchStartTyping => 'Начните вводить запрос';

  @override
  String get searchNoMatches => 'Совпадений нет';

  @override
  String failedToSearchTasks(Object error) {
    return 'Не удалось найти задачи: $error';
  }

  @override
  String get previousMonth => 'Предыдущий месяц';

  @override
  String get nextMonth => 'Следующий месяц';

  @override
  String get clearDateFilter => 'Очистить фильтр даты';

  @override
  String get weekMon => 'Пн';

  @override
  String get weekTue => 'Вт';

  @override
  String get weekWed => 'Ср';

  @override
  String get weekThu => 'Чт';

  @override
  String get weekFri => 'Пт';

  @override
  String get weekSat => 'Сб';

  @override
  String get weekSun => 'Вс';

  @override
  String get browseTitle => 'Обзор';

  @override
  String get unifiedAccount => 'Единый аккаунт';

  @override
  String accountUnavailable(Object error) {
    return 'Аккаунт недоступен: $error';
  }

  @override
  String get signOut => 'Выйти';

  @override
  String get deleteAccount => 'Удалить аккаунт';

  @override
  String get deleteAccountConfirmation =>
      'Аккаунт, облачные данные, а также локальные задачи, проекты и история фокуса будут удалены без возможности восстановления. Подписки в магазине не отменяются автоматически. Если вы входили через Apple, отдельно отзовите доступ Pomodoist в настройках аккаунта Apple.';

  @override
  String get manageSignInWithApple => 'Управление входом через Apple';

  @override
  String get deleteAccountFinalConfirmation =>
      'Вы точно уверены? Это последнее подтверждение.';

  @override
  String deleteAccountError(Object error) {
    return 'Не удалось удалить аккаунт: $error';
  }

  @override
  String get accountDeleted => 'Аккаунт удалён.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Аккаунт удалён, но локальные данные очистить не удалось. Очистите данные приложения перед дальнейшим использованием этого устройства.';

  @override
  String get browseSevenDays => '7 дней';

  @override
  String get browseOpenNow => 'Открыто сейчас';

  @override
  String get browseQueueLoading => 'Загрузка ожидающих изменений…';

  @override
  String get browseQueueUnavailable =>
      'Не удалось загрузить ожидающие изменения.';

  @override
  String get browseQueueExplanation =>
      'Здесь показаны локальные изменения, ожидающие отправки. Пустая очередь не подтверждает, что данные на всех устройствах актуальны.';

  @override
  String get productivityTitle => 'Продуктивность';

  @override
  String get achievementsTitle => 'Достижения';

  @override
  String get allTimeLabel => 'За все время';

  @override
  String get lastSevenDaysLabel => 'Последние 7 дней';

  @override
  String get noWeeklyStatsLabel => 'Пока нет данных по фокусу и задачам';

  @override
  String get completedFocuses => 'Завершенные фокусы';

  @override
  String get completedTasks => 'Завершенные задачи';

  @override
  String get unlocked => 'Открыто';

  @override
  String get locked => 'Закрыто';

  @override
  String get progressLabel => 'Прогресс';

  @override
  String get focusAchievements => 'Достижения фокуса';

  @override
  String get taskAchievements => 'Достижения задач';

  @override
  String get comboAchievements => 'Комбо-достижения';

  @override
  String get focusIntervals => 'Интервалы фокуса';

  @override
  String get focusTime => 'Время фокуса';

  @override
  String get openTasks => 'Открытые задачи';

  @override
  String get plannedIntervals => 'Запланированные интервалы';

  @override
  String get labelsTitle => 'Метки';

  @override
  String get newProject => 'Новый проект';

  @override
  String get newLabel => 'Новая метка';

  @override
  String get syncReadyQueue => 'Очередь синхронизации';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count локальной команды в очереди',
      many: '$count локальных команд в очереди',
      few: '$count локальные команды в очереди',
      one: '1 локальная команда в очереди',
      zero: 'Нет локальных команд в очереди',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'Не удалось загрузить проекты: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'Не удалось загрузить метки: $error';
  }

  @override
  String get addProject => 'Добавить проект';

  @override
  String get projectName => 'Название проекта';

  @override
  String get addLabel => 'Добавить метку';

  @override
  String get labelName => 'Название метки';

  @override
  String couldNotAddLabel(Object error) {
    return 'Не удалось добавить метку: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Проекты недоступны: $error';
  }

  @override
  String get projectsUnavailableShort => 'Проекты недоступны';

  @override
  String get noProjects => 'Нет проектов';

  @override
  String get searchProjects => 'Поиск проектов';

  @override
  String get searchLabels => 'Поиск меток';

  @override
  String get archivedProjectsOnly => 'Только архивные проекты';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count проекта',
      many: '$count проектов',
      few: '$count проекта',
      one: '1 проект',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'Нет меток';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count метки',
      many: '$count меток',
      few: '$count метки',
      one: '1 метка',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => 'Переименовать проект';

  @override
  String get deleteProject => 'Удалить проект';

  @override
  String get deleteLabel => 'Удалить метку';

  @override
  String deleteProjectConfirmation(String name) {
    return 'Удалить \"$name\"? Задачи из этого проекта будут перенесены во Входящие.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return 'Удалить \"$name\"?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'Не удалось удалить проект: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'Не удалось удалить метку: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Проекты: $count';
  }

  @override
  String get collapseProjects => 'Свернуть проекты';

  @override
  String get expandProjects => 'Развернуть проекты';

  @override
  String get projectFallbackTitle => 'Проект';

  @override
  String get projectSubtitle => 'Список - доска и календарь в планах.';

  @override
  String get reportsTitle => 'Отчеты';

  @override
  String get reportsFocusedDay => 'Сфокусированный день';

  @override
  String get reportsThisWeek => 'Неделя в фокусе';

  @override
  String get reportsNextAchievement => 'Следующее достижение';

  @override
  String get viewAllAchievements => 'Все достижения';

  @override
  String viewAllAchievementsCount(int count) {
    return 'Показать все: $count';
  }

  @override
  String get allAchievementsUnlocked => 'Все достижения открыты';

  @override
  String get noAchievementsYet => 'Достижений пока нет';

  @override
  String failedToLoadAchievements(Object error) {
    return 'Не удалось загрузить достижения: $error';
  }

  @override
  String get backToReports => 'Назад к отчетам';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return 'Завершено интервалов фокуса: $completed из $target';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return 'Завершено интервалов фокуса: $completed; цель не задана';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Время фокуса за последние 7 дней: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'Не удалось загрузить отчеты: $error';
  }

  @override
  String get taskNotFound => 'Задача не найдена';

  @override
  String get taskTitleHint => 'Название задачи';

  @override
  String get taskComment => 'Комментарий';

  @override
  String get taskCommentHint => 'Добавить комментарий';

  @override
  String get subtasks => 'Подзадачи';

  @override
  String get addSubtask => 'Добавить подзадачу';

  @override
  String get addSubtaskHint => 'Добавить подзадачу';

  @override
  String get noSubtasks => 'Подзадач пока нет.';

  @override
  String get makeParentTask => 'Сделать основной задачей';

  @override
  String couldNotMoveTask(Object error) {
    return 'Не удалось переместить задачу: $error';
  }

  @override
  String get scheduleTitle => 'Расписание';

  @override
  String get allDay => 'Весь день';

  @override
  String get timedBlock => 'Блок времени';

  @override
  String get recurrenceTitle => 'Повтор';

  @override
  String get recurrenceNeedsSchedule =>
      'Добавьте дату или время перед повтором.';

  @override
  String get recurrenceIntervalLabel => 'Интервал';

  @override
  String get recurrenceUnitDay => 'Дни';

  @override
  String get recurrenceUnitWeek => 'Недели';

  @override
  String get recurrenceUnitMonth => 'Месяцы';

  @override
  String get recurrenceInvalidInterval => 'Введите от 1 до 999.';

  @override
  String recurrenceEveryDays(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'каждые $interval дня',
      many: 'каждые $interval дней',
      few: 'каждые $interval дня',
      one: 'каждый день',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'каждые $interval недели',
      many: 'каждые $interval недель',
      few: 'каждые $interval недели',
      one: 'каждую неделю',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'каждые $interval месяца',
      many: 'каждые $interval месяцев',
      few: 'каждые $interval месяца',
      one: 'каждый месяц',
    );
    return '$_temp0';
  }

  @override
  String get noDate => 'Без даты';

  @override
  String get calendarNotLinked => 'Календарь не связан';

  @override
  String get calendarLinked => 'Google Calendar связан';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total фокус';
  }

  @override
  String get startFocus => 'Начать фокус';

  @override
  String get focusStarted => 'Фокус начат';

  @override
  String get taskReopened => 'Задача открыта снова';

  @override
  String get taskCompleted => 'Задача завершена';

  @override
  String get taskDeleted => 'Задача удалена';

  @override
  String get recurringDeleteTitle => 'Удалить повторяющуюся задачу?';

  @override
  String get recurringDeleteMessage =>
      'Эта задача входит в повторяющуюся серию.';

  @override
  String get recurringDeleteThis => 'Удалить только эту';

  @override
  String get recurringDeleteThisAndFollowing => 'Удалить эту и последующие';

  @override
  String get markOpen => 'Сделать открытой';

  @override
  String get markComplete => 'Завершить';

  @override
  String get focusHistory => 'История фокуса';

  @override
  String failedToLoadTask(Object error) {
    return 'Не удалось загрузить задачу: $error';
  }

  @override
  String get noFocusIntervals => 'Интервалов фокуса пока нет.';

  @override
  String get today => 'Сегодня';

  @override
  String get tomorrow => 'Завтра';

  @override
  String get yesterday => 'Вчера';

  @override
  String get clearDate => 'Очистить дату';

  @override
  String priority(int priority) {
    return 'Приоритет $priority';
  }

  @override
  String get focusTitle => 'Фокус';

  @override
  String focusLoadError(Object error) {
    return 'Не удалось загрузить фокус: $error';
  }

  @override
  String get focusViewFull => 'Полный';

  @override
  String get focusViewMinimal => 'Минимальный';

  @override
  String get focusSwitchToFullView => 'Перейти в Full';

  @override
  String get focusSwitchToMinimalView => 'Перейти в Minimal';

  @override
  String get focusActionFailed =>
      'Не удалось изменить состояние Focus. Попробуйте ещё раз.';

  @override
  String get noActiveSession => 'Нет активной сессии';

  @override
  String get focusIdleSubtitle =>
      'Запустите отдельный интервал фокуса или начните фокус из задачи.';

  @override
  String get noPreset => 'Нет пресета';

  @override
  String get preparingFocus => 'Готовлю фокус';

  @override
  String get moreFocusOptions => 'Еще настройки фокуса';

  @override
  String get moreFocusActions => 'Еще действия фокуса';

  @override
  String get preset => 'Пресет';

  @override
  String get newPreset => 'Новый пресет';

  @override
  String get customize => 'Настроить';

  @override
  String get customizePreset => 'Настроить пресет';

  @override
  String get startInterval => 'Начать интервал';

  @override
  String get intervalStarted => 'Интервал начат';

  @override
  String get intervalCompleted => 'Интервал завершен';

  @override
  String get focusStopped => 'Фокус остановлен';

  @override
  String get focusCompletionTitle => 'Отличная работа!';

  @override
  String get focusCompletionLinkedSubtitle =>
      'Все запланированные фокус-интервалы для этой задачи завершены.';

  @override
  String get focusCompletionStandaloneSubtitle => 'Ваш цикл фокуса завершён.';

  @override
  String get focusCompletionQuestion => 'Готовы завершить задачу?';

  @override
  String get focusCompletionCompleteTask => 'Завершить задачу';

  @override
  String get focusCompletionKeepOpen => 'Оставить открытой';

  @override
  String get focusCompletionDone => 'Готово';

  @override
  String get focusCompletionNextTask => 'Следующая запланированная задача';

  @override
  String focusCompletionTaskError(Object error) {
    return 'Не удалось завершить задачу: $error';
  }

  @override
  String get completeInterval => 'Завершить интервал';

  @override
  String get logDistraction => 'Отметить отвлечение';

  @override
  String get workInterval => 'Рабочий интервал';

  @override
  String get work => 'Работа';

  @override
  String get shortBreak => 'Короткий перерыв';

  @override
  String get breakLabel => 'Перерыв';

  @override
  String get longBreak => 'Длинный перерыв';

  @override
  String readyLabel(String label) {
    return 'Готово: $label';
  }

  @override
  String get readyShort => 'Готово';

  @override
  String focusTimerTotal(String duration) {
    return 'из $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Сессия $current из $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Предпросмотр ритма фокуса: $count этапов';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Ритм фокуса, этап $current из $total: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, осталось $remaining, всего $total';
  }

  @override
  String get focusStatusRunning => 'Выполняется';

  @override
  String get focusStatusPaused => 'На паузе';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total работа';
  }

  @override
  String intervalNumber(int number) {
    return 'Интервал $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total работа - Интервал $number';
  }

  @override
  String get pause => 'Пауза';

  @override
  String get resume => 'Продолжить';

  @override
  String get presetForNextIntervals => 'Пресет для следующих интервалов';

  @override
  String usePreset(String name) {
    return 'Использовать $name';
  }

  @override
  String minutesWork(int minutes) {
    return '$minutesм работа';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutesм короткий';
  }

  @override
  String minutesLong(int minutes) {
    return '$minutesм длинный';
  }

  @override
  String longEvery(int count) {
    return 'Длинный каждые $count';
  }

  @override
  String get autoBreaks => 'Авто перерывы';

  @override
  String get autoWork => 'Авто работа';

  @override
  String get noPause => 'Без паузы';

  @override
  String get focusPauseUnavailable => 'Пауза недоступна для этого пресета';

  @override
  String get strict => 'Строгий';

  @override
  String get flexible => 'Гибкий';

  @override
  String get name => 'Название';

  @override
  String get workField => 'Работа';

  @override
  String get shortField => 'Короткий';

  @override
  String get longField => 'Длинный';

  @override
  String get every => 'Каждые';

  @override
  String get minutesSuffix => 'мин';

  @override
  String get makeDefault => 'По умолчанию';

  @override
  String get autoStartBreaks => 'Автозапуск перерывов';

  @override
  String get autoStartWork => 'Автозапуск работы';

  @override
  String get allowPause => 'Разрешить паузу';

  @override
  String get strictMode => 'Строгий режим';

  @override
  String get nameRequired => 'Название обязательно';

  @override
  String get nameMustBeUnique => 'Название должно быть уникальным';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'Двусторонняя синхронизация активна для календаря Pomodoist.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Подключите Google аккаунт для синхронизации запланированных задач.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'Синхронизация Google Calendar выполняется на другом устройстве. Данные Pomodoist все равно синхронизируются здесь.';

  @override
  String get syncNow => 'Синхронизировать';

  @override
  String get useThisDevice => 'Использовать это устройство';

  @override
  String get connect => 'Подключить';

  @override
  String get disconnect => 'Отключить';

  @override
  String failedToLoadIntegration(Object error) {
    return 'Не удалось загрузить интеграцию: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Ошибка Google Calendar: $message';
  }

  @override
  String get googleAuthRequired =>
      'Нужна авторизация Google Calendar. Войдите снова и запустите синхронизацию.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In не настроен. Задайте GOOGLE_CLIENT_ID и GOOGLE_REVERSED_CLIENT_ID для этой iOS цели.';

  @override
  String get googleCallbackNotConfigured =>
      'Callback Google Sign-In не настроен. Задайте GOOGLE_REVERSED_CLIENT_ID в ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'В web сначала нажмите кнопку входа Google, затем Подключить.';

  @override
  String get googleAccessDenied =>
      'Доступ Google запрещен. Добавьте этот аккаунт как OAuth test user или опубликуйте и подтвердите OAuth app.';

  @override
  String get status => 'Статус';

  @override
  String get account => 'Аккаунт';

  @override
  String get calendar => 'Календарь';

  @override
  String get calendarId => 'ID календаря';

  @override
  String get lastSync => 'Последняя синхронизация';

  @override
  String get notConnected => 'Не подключено';

  @override
  String get notCreated => 'Не создано';

  @override
  String get never => 'Никогда';

  @override
  String durationMinutes(int minutes) {
    return '$minutesм';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String get projectIcon => 'Иконка проекта';

  @override
  String projectIconOption(int number) {
    return 'Иконка $number';
  }

  @override
  String get projectColor => 'Цвет проекта';

  @override
  String projectColorOption(int number) {
    return 'Цвет $number';
  }

  @override
  String get addProjectToFavorites => 'Добавить проект в избранное';

  @override
  String get removeProjectFromFavorites => 'Убрать проект из избранного';

  @override
  String get timelineProjectsMenu => 'Управление проектами Timeline';

  @override
  String get timelineShowProject => 'Показать проект в Timeline';

  @override
  String get timelineHideProject => 'Скрыть временный проект';

  @override
  String get timelineCollapseProject => 'Свернуть ветку проекта';

  @override
  String get timelineExpandProject => 'Развернуть ветку проекта';

  @override
  String get timelineCurrentTime => 'Текущее время';

  @override
  String couldNotUpdateProject(Object error) {
    return 'Не удалось обновить проект: $error';
  }

  @override
  String get commonDone => 'Готово';

  @override
  String get taskSelect => 'Выбрать';

  @override
  String taskSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get taskSelectAll => 'Выбрать все';

  @override
  String get taskDeselectAll => 'Снять выделение';

  @override
  String get taskDue => 'Срок';

  @override
  String get taskProject => 'Проект';

  @override
  String get taskLabels => 'Метки';

  @override
  String get taskPriority => 'Приоритет';

  @override
  String get taskMore => 'Ещё';

  @override
  String get taskSchedule => 'Запланировать';

  @override
  String get taskMove => 'Перенести';

  @override
  String get taskDuplicate => 'Дублировать';

  @override
  String get taskDuplicateTitle => 'Дублировать задачи';

  @override
  String get taskDuplicateSelectedOnly => 'Только выбранные';

  @override
  String get taskDuplicateWithSubtasks => 'С подзадачами';

  @override
  String get taskWeekend => 'На выходных';

  @override
  String get taskNextWeek => 'На следующей неделе';

  @override
  String get taskEnterDue => 'Введите срок или время';

  @override
  String get taskInvalidDue => 'Введите корректную дату или время';

  @override
  String get taskClearDue => 'Очистить срок';

  @override
  String get taskDeleteSelectedTitle => 'Удалить выбранные задачи?';

  @override
  String get taskDeleteSelectedMessage =>
      'Это действие можно отменить в течение 7 секунд.';

  @override
  String get taskCompleteSelected => 'Выполнить выбранные';

  @override
  String get taskReopenSelected => 'Вернуть в открытые';

  @override
  String taskActionFailedCount(int count) {
    return 'Не удалось обновить задач: $count';
  }

  @override
  String get voiceCollapse => 'Свернуть голосовую панель';

  @override
  String get voiceExpand => 'Развернуть голосовую панель';

  @override
  String get voiceMovePanel => 'Переместить голосовую панель';

  @override
  String get themeClassic => 'Классика';

  @override
  String get themeOcean => 'Океан';

  @override
  String get themeForest => 'Лес';

  @override
  String get themeCustomize => 'Настроить';

  @override
  String get themeEditorTitle => 'Редактор темы';

  @override
  String get themeLivePreview =>
      'Изменения видны во всём приложении. Отмена вернёт предыдущую тему.';

  @override
  String get themeSaveError =>
      'Не удалось сохранить тему. Изменения сохранены в редакторе; попробуйте ещё раз.';

  @override
  String get themeLoadError => 'Не удалось загрузить темы.';

  @override
  String get themeColorsSurfaces => 'Фон и поверхности';

  @override
  String get themeColorsText => 'Текст';

  @override
  String get themeColorsAccent => 'Акцент';

  @override
  String get themeColorsStatus => 'Цвета статусов';

  @override
  String get themeInvalidHex =>
      'Введите HEX-цвет из шести цифр, например #2563EB.';

  @override
  String get themeLowContrast =>
      'Низкий контраст: часть текста может быть трудно прочитать.';

  @override
  String get themePreviewTask => 'Спланируйте свой день';

  @override
  String get themePreviewSecondary => 'Немного сосредоточенности каждый день.';

  @override
  String get themeColorCanvas => 'Фон';

  @override
  String get themeColorSurface => 'Поверхность';

  @override
  String get themeColorSurfaceTint => 'Вторичная поверхность';

  @override
  String get themeColorSurfaceHover => 'Поверхность при наведении';

  @override
  String get themeColorPrimaryText => 'Основной текст';

  @override
  String get themeColorSecondaryText => 'Вторичный текст';

  @override
  String get themeColorMutedText => 'Приглушённый текст';

  @override
  String get themeColorBorder => 'Граница';

  @override
  String get themeColorAccent => 'Акцентный текст и значки';

  @override
  String get themeColorAccentFill => 'Акцентная заливка';

  @override
  String get themeColorAccentTint => 'Мягкая акцентная заливка';

  @override
  String get themeColorWarning => 'Предупреждение';

  @override
  String get themeColorInfo => 'Информация';

  @override
  String get themeColorSuccess => 'Успех';

  @override
  String get themeColorError => 'Ошибка';

  @override
  String get themeColorOverdue => 'Просрочка';

  @override
  String get themeColorOnAccent => 'Текст на акцентной заливке';

  @override
  String get themeColorOnError => 'Текст на заливке ошибки';

  @override
  String todayTaskSummary(int tasks, int planned, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      tasks,
      locale: localeName,
      other: '$tasks задачи',
      many: '$tasks задач',
      few: '$tasks задачи',
      one: '$tasks задача',
    );
    return '$_temp0 · в плане: $planned · фокус: $time';
  }

  @override
  String get todayFocusingOn => 'В фокусе';

  @override
  String get openFocus => 'Открыть Focus';

  @override
  String todayCompletedTasks(int count) {
    return 'Завершено сегодня · $count';
  }

  @override
  String get sidebarDaily => 'На каждый день';

  @override
  String get sidebarViews => 'Представления';

  @override
  String get quickAddResetDetails => 'По умолчанию';

  @override
  String get quickAddChangeTime => 'Изменить время';

  @override
  String get quickAddProjectNameUnsupported =>
      'Не удаётся вставить название проекта без изменений.';

  @override
  String get themeSepia => 'Сепия';

  @override
  String get themeGraphite => 'Графит';

  @override
  String get themeCustom => 'Custom';

  @override
  String get themeResetToClassic => 'Сбросить к Классике';

  @override
  String get themeBackgroundKindTitle => 'Фон';

  @override
  String get themeBackgroundColor => 'Цвет';

  @override
  String get themeBackgroundPhoto => 'Фото';

  @override
  String get themeBackgroundGlass => 'Стекло macOS';

  @override
  String get themeBackgroundGlassHint =>
      'Применяется ко всему приложению и быстрому добавлению. macOS управляет размытием, а ползунок регулирует оттенок палитры.';

  @override
  String get themeBackgroundGlassUnavailable =>
      'Доступно в приложении для macOS. На этой платформе используется сплошной фон.';

  @override
  String get themeBackgroundTitle => 'Фоновое изображение';

  @override
  String get themeBackgroundMainOnly => 'Только основная область';

  @override
  String get themeBackgroundWholeApp => 'Всё приложение';

  @override
  String get themeBackgroundSeparate => 'Отдельные фоны';

  @override
  String get themeBackgroundMain => 'Основная область';

  @override
  String get themeBackgroundSidebar => 'Боковая панель';

  @override
  String get themeBackgroundQuickAdd => 'Быстрое добавление';

  @override
  String get themeBackgroundChoose => 'Выбрать фото';

  @override
  String get themeBackgroundReplace => 'Заменить фото';

  @override
  String get themeBackgroundRemove => 'Удалить фото';

  @override
  String get themeBackgroundDim => 'Затемнение';

  @override
  String get themeBackgroundBlur => 'Размытие';

  @override
  String get themeBackgroundEmpty => 'Нет фото';

  @override
  String get themeBackgroundImageError =>
      'Не удалось открыть изображение. Выберите другое фото.';

  @override
  String get themeBackgroundTooLarge =>
      'Выберите изображение размером не более 50 МБ.';

  @override
  String get themeBackgroundLoading => 'Подготовка изображения…';

  @override
  String get settingsTaskListStyle => 'Стиль строк задач';

  @override
  String get settingsTaskListStyleDescription =>
      'Выберите новый вид или привычные классические строки.';

  @override
  String get settingsTaskListModern => 'Современный';

  @override
  String get settingsTaskListClassic => 'Классический';

  @override
  String get settingsTaskRowSpacing => 'Расстояние между задачами';

  @override
  String get settingsTaskRowSpacingCompact => 'Компактно';

  @override
  String get settingsTaskRowSpacingComfortable => 'Комфортно';

  @override
  String get settingsTaskRowSpacingSpacious => 'Просторно';

  @override
  String get settingsSaveError =>
      'Не удалось сохранить настройку. Попробуйте ещё раз.';

  @override
  String get focusCompletionCompleteAndNext => 'Завершить и начать следующую';

  @override
  String get focusCompletionStartNext => 'Начать следующую задачу';

  @override
  String get focusCompletionRetry => 'Повторить';

  @override
  String get searchAllProjects => 'Все проекты';

  @override
  String get searchStatusOpen => 'Открытые';

  @override
  String get searchStatusCompleted => 'Завершённые';

  @override
  String get searchStatusAll => 'Все статусы';

  @override
  String get searchClearFilters => 'Сбросить фильтры';

  @override
  String get searchEmptyDescription =>
      'Найдите задачу по названию или описанию, затем уточните проект или статус.';

  @override
  String get searchNoMatchesDescription =>
      'Попробуйте другой запрос или сбросьте фильтры. Из этого текста можно создать задачу.';

  @override
  String get searchCreateTask => 'Создать задачу из текста';

  @override
  String get taskListLoadError =>
      'Не удалось загрузить задачи. Попробуйте ещё раз.';

  @override
  String get inboxEmptyTitle => 'Входящие пусты';

  @override
  String get inboxEmptyDescription =>
      'Запишите идею здесь, а время для неё выберите позже.';

  @override
  String get todayEmptyTitle => 'На сегодня ничего не запланировано';

  @override
  String get todayEmptyDescription =>
      'Добавьте задачу, с которой начнёте день.';

  @override
  String get todayEmptyCompletedTitle => 'Список на сегодня пуст';

  @override
  String get todayEmptyCompletedDescription =>
      'Завершённые задачи сохранены ниже. Добавьте следующую, когда будете готовы.';

  @override
  String get projectEmptyTitle => 'В проекте пока нет задач';

  @override
  String get projectEmptyDescription => 'Добавьте первый шаг к цели проекта.';

  @override
  String get commandSearchPlaceholder => 'Поиск задач, проектов и действий';

  @override
  String get commandSearchTasks => 'Задачи';

  @override
  String get commandSearchActions => 'Действия';

  @override
  String get commandSearchDictateTask => 'Продиктовать задачу';

  @override
  String get commandSearchAllResults => 'Все результаты';

  @override
  String get commandSearchHint => '↑ ↓ Выбор · Enter Открыть · Esc Закрыть';

  @override
  String get commandSearchNoMatches => 'Подходящих задач и проектов нет.';

  @override
  String get overdueTitle => 'Просроченное';

  @override
  String overdueTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Просрочено $count задачи',
      many: 'Просрочено $count задач',
      few: 'Просрочено $count задачи',
      one: 'Просрочена $count задача',
    );
    return '$_temp0';
  }

  @override
  String get overdueReview => 'Разобрать';

  @override
  String get overdueEmpty => 'Просроченных задач нет';

  @override
  String get taskFocusSwitchTitle => 'Переключить фокус?';

  @override
  String taskFocusSwitchMessage(String task) {
    return 'Текущая сессия остановится. Начать фокус на задаче «$task»?';
  }

  @override
  String get taskFocusSwitchConfirm => 'Переключить';

  @override
  String get labelIcon => 'Иконка метки';

  @override
  String get labelUpdateFailed =>
      'Не удалось обновить метку. Попробуйте ещё раз.';

  @override
  String get labelNotFound => 'Метка не найдена';

  @override
  String get labelTasksSubtitle => 'Задачи с этой меткой из всех проектов';

  @override
  String labelIconOption(String icon) {
    String _temp0 = intl.Intl.selectLogic(icon, {
      'tag': 'Бирка',
      'bookmark': 'Закладка',
      'flag': 'Флаг',
      'bolt': 'Болт',
      'lightbulb': 'Лампочка',
      'clock': 'Часы',
      'bell': 'Колокольчик',
      'pin': 'Булавка',
      'phone': 'Телефон',
      'mail': 'Письмо',
      'link': 'Ссылка',
      'wrench': 'Гаечный ключ',
      'other': 'Бирка',
    });
    return '$_temp0';
  }

  @override
  String get addSubproject => 'Создать подпроект';

  @override
  String get moveProject => 'Переместить проект';

  @override
  String get projectTopLevel => 'Верхний уровень';

  @override
  String get projectMoveUp => 'Выше';

  @override
  String get projectMoveDown => 'Ниже';

  @override
  String projectParentName(String name) {
    return 'Родительский проект: $name';
  }

  @override
  String deleteProjectWithChildrenConfirmation(String name) {
    return 'Удалить «$name»? Подпроекты поднимутся на уровень выше. Только задачи этого проекта будут перенесены во Входящие.';
  }

  @override
  String get accountNickname => 'Никнейм';

  @override
  String get accountChangeNickname => 'Изменить никнейм';

  @override
  String get accountNicknameSaveError =>
      'Не удалось сохранить никнейм. Попробуйте ещё раз.';

  @override
  String get notificationTaskStarting => 'Время задачи';

  @override
  String get notificationReturnTitle => 'Помидор скучает';

  @override
  String get notificationReturnBody =>
      'Один фокус или одна галочка — и день уже не зря.';

  @override
  String get notificationFocusChannel => 'Фокус';

  @override
  String get notificationFocusDescription =>
      'Уведомления о завершении интервала фокуса';

  @override
  String get notificationReturnChannel => 'Напоминания о возвращении';

  @override
  String get notificationReturnDescription =>
      'Мягкие напоминания вернуться в Pomodoist';

  @override
  String get notificationTaskChannel => 'Начало задачи';

  @override
  String get notificationTaskDescription => 'Уведомления о начале задачи';

  @override
  String get notificationOpenApp => 'Открыть Pomodoist';

  @override
  String get notificationFocusCompleted => 'Фокус-интервал завершён';

  @override
  String get notificationLongBreakCompleted => 'Длинный перерыв завершён';

  @override
  String get notificationBreakCompleted => 'Перерыв завершён';

  @override
  String get updateTitle => 'Обновление Pomodoist';

  @override
  String get updateAction => 'Обновить';

  @override
  String get updateCheck => 'Проверить обновления';

  @override
  String get updateSettings => 'Обновления';

  @override
  String get updateReceiveRc => 'Получать релиз-кандидаты (RC)';

  @override
  String get updateStableChannel => 'Канал: стабильные релизы';

  @override
  String get updateRcChannel => 'Канал: стабильные релизы и RC';

  @override
  String get updateRcHelp =>
      'RC могут содержать ошибки. Альфа- и бета-версии исключены.';

  @override
  String get updateRestart =>
      'Приложение перезапустится. Ваши данные сохранятся.';

  @override
  String get updateNotes => 'Все изменения';

  @override
  String get updateOwnerManaged =>
      'Эту сборку обновляет её владелец, чтобы сохранить настройки сервера. Запросите у него последнюю версию.';

  @override
  String get updateUnsupported =>
      'Автообновление доступно в официальной Linux AppImage. Другие сборки обновляйте через менеджер пакетов.';

  @override
  String updateVersion(String value) {
    return 'Версия $value';
  }

  @override
  String get updatePhaseIdle => 'Проверка доступна в любое время.';

  @override
  String get updatePhaseChecking => 'Проверяем релизы…';

  @override
  String get updatePhaseAvailable => 'Доступна новая версия';

  @override
  String get updatePhaseDownloading => 'Скачиваем обновление…';

  @override
  String get updatePhaseVerifying => 'Проверяем целостность…';

  @override
  String get updatePhaseInstalling => 'Подготавливаем установку и перезапуск…';

  @override
  String get updatePhaseUpToDate => 'Установлена последняя подходящая версия.';

  @override
  String get updatePhaseFailed => 'Не удалось обновить приложение';

  @override
  String achievementFocusSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Завершить $count work-фокусов',
      one: 'Завершить 1 work-фокус',
    );
    return '$_temp0';
  }

  @override
  String achievementTaskSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Закрыть $count задач',
      one: 'Закрыть 1 задачу',
    );
    return '$_temp0';
  }

  @override
  String get achievementDayNotWastedSubtitle =>
      'За день есть фокус и закрытая задача';

  @override
  String get achievementFocusPlusCheckSubtitle =>
      'За день есть 3 фокуса и 3 задачи';

  @override
  String get achievementNoFussSubtitle => '5 фокусов за день без остановок';

  @override
  String get achievementCleanEntrySubtitle =>
      'Закрыть задачу после связанного фокуса';

  @override
  String get achievementTomatoClosedSubtitle =>
      'Закрыть задачу в день ее work-фокуса';

  @override
  String achievementTitle(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'focus_1': 'Первый помидор',
      'focus_5': 'Разогрев',
      'focus_10': 'Фокус пойман',
      'focus_25': 'Помидорная смена',
      'focus_50': 'Режим включен',
      'focus_100': 'Красный пояс',
      'focus_250': 'Глубокая посадка',
      'focus_500': 'Таймерный авторитет',
      'focus_1000': 'Тысячный помидор',
      'focus_5000': 'Фермер фокуса',
      'focus_10000': 'Плантация внимания',
      'focus_50000': 'Помидорная империя',
      'focus_100000': 'Красный сверхразум',
      'focus_1000000': 'Сингулярность помидора',
      'task_1': 'Первая галочка',
      'task_5': 'Список дрогнул',
      'task_10': 'Чекбокс доволен',
      'task_25': 'Разбор завалов',
      'task_50': 'Мастер галочек',
      'task_100': 'Закрыватель хвостов',
      'task_250': 'Список под контролем',
      'task_500': 'Канцелярский нокаут',
      'task_1000': 'Тысяча галочек',
      'task_5000': 'Архивариус побед',
      'task_10000': 'Чекбокс-машина',
      'task_50000': 'Бюро закрытых вопросов',
      'task_100000': 'Повелитель списков',
      'task_1000000': 'Последняя галочка',
      'combo_day_not_wasted': 'День не зря',
      'combo_focus_plus_check': 'Фокус + галочка',
      'combo_no_fuss': 'Без суеты',
      'combo_clean_entry': 'Чистый заход',
      'combo_tomato_closed_question': 'Помидор закрыл вопрос',
      'other': 'Достижение',
    });
    return '$_temp0';
  }

  @override
  String get focusPresetDeepWork => 'Глубокая работа';

  @override
  String get focusPresetShortSprint => 'Короткий спринт';

  @override
  String csvImportIssueRow(int row, String message) {
    return 'Строка $row: $message';
  }

  @override
  String csvImportIssueMessage(String code, String value) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'fileTooLarge': 'Файл CSV превышает 16 МиБ.',
      'invalidUtf8': 'CSV должен быть в кодировке UTF-8.',
      'missingHeader': 'Отсутствует заголовок CSV.',
      'malformed': 'Некорректный формат CSV.',
      'unknownHeader': 'Неизвестный заголовок «$value».',
      'duplicateHeader': 'Повторяющийся заголовок «$value».',
      'contentHeaderRequired': 'Заголовок content обязателен.',
      'tooManyTasks': 'CSV не может содержать более 1000 задач.',
      'tooManyFields': 'В строке больше полей, чем в заголовке.',
      'contentRequired': 'Поле content обязательно.',
      'invalidPriority': 'priority должен быть целым числом от 1 до 4.',
      'invalidDate': '$value должен быть в формате YYYY-MM-DD.',
      'mixedSchedule': 'Нельзя сочетать due_date с расписанием по времени.',
      'timedFieldsRequired':
          'Для расписания по времени нужны start_at, end_at и time_zone.',
      'invalidTimestamp':
          '$value должен быть в формате RFC3339 с явным смещением UTC.',
      'invalidTimeZone': 'time_zone должен быть корректным именем IANA.',
      'endBeforeStart': 'end_at должен быть позже start_at.',
      'invalidRecurrence': 'recurrence должен быть day, week или month.',
      'invalidInteger': '$value должен быть целым числом от 1 до 999.',
      'intervalWithoutRecurrence': 'Для recurrence_interval нужен recurrence.',
      'recurrenceWithoutSchedule': 'Для recurrence нужно расписание.',
      'doneTask': 'Нельзя импортировать завершённые задачи.',
      'invalidKey': 'У $value некорректный формат.',
      'empty': 'CSV не содержит задач.',
      'duplicateKey': 'Повторяющийся ключ «$value».',
      'parentCycle': 'Ссылки parent_key образуют цикл.',
      'missingParent': 'parent_key «$value» не существует.',
      'childProject':
          'Подзадача должна быть в том же проекте, что и родительская задача.',
      'other': 'Не удалось импортировать файл.',
    });
    return '$_temp0';
  }

  @override
  String billingOfferDays(int count) {
    return '$count дн.';
  }

  @override
  String billingOfferMonths(int count) {
    return '$count мес.';
  }

  @override
  String billingOfferYears(int count) {
    return '$count г.';
  }

  @override
  String billingTrialFree(String duration) {
    return 'Бесплатно: $duration';
  }

  @override
  String billingTrialRenewal(String price) {
    return 'Затем $price. Автопродление, если не отменить подписку.';
  }

  @override
  String get billingReturnBadge => 'Вернуться в Pro';

  @override
  String billingReturnSubtitle(String duration, String price) {
    return 'На $duration, затем $price. Автопродление, если не отменить подписку.';
  }

  @override
  String billingReturnPending(String date) {
    return 'Скидка зарезервирована до $date. Если покупка отменена, повторить попытку можно после этого времени.';
  }

  @override
  String get billingReturnFailed =>
      'Не удалось проверить скидку на возвращение. Повторите проверку.';

  @override
  String get billingTryFree => 'Попробовать';

  @override
  String get collaborationShareProject => 'Поделиться проектом';

  @override
  String get collaborationShareIntro =>
      'Пригласите людей работать над проектом вместе. Участники могут редактировать, наблюдатели — только просматривать.';

  @override
  String get collaborationShareStart => 'Поделиться';

  @override
  String get collaborationShareInProgress =>
      'Открываем доступ… синхронизируем последние изменения';

  @override
  String get collaborationMembers => 'Участники';

  @override
  String get collaborationPendingInvitations => 'Ожидающие приглашения';

  @override
  String get collaborationRevoke => 'Отозвать';

  @override
  String get collaborationPublicLink => 'Публичная ссылка';

  @override
  String get collaborationPublicLinkHint =>
      'Любой, у кого есть ссылка, может просматривать этот проект';

  @override
  String get collaborationCopyLink => 'Копировать ссылку';

  @override
  String get collaborationConflicts => 'Конфликты синхронизации';

  @override
  String get collaborationLeaveProject => 'Покинуть проект';

  @override
  String get collaborationDeleteSharedProject => 'Удалить для всех';

  @override
  String get collaborationMakePrivate => 'Сделать личным';

  @override
  String get collaborationOwner => 'Владелец';

  @override
  String get collaborationTransferOwnership => 'Передать владение';

  @override
  String get collaborationRemoveMember => 'Удалить участника';

  @override
  String get collaborationEmail => 'Эл. почта';

  @override
  String get collaborationInvite => 'Пригласить';

  @override
  String get collaborationConflictHint =>
      'Другой участник тоже изменил этот элемент';

  @override
  String get collaborationConflictKeepLocal => 'Оставить моё';

  @override
  String get collaborationConflictUseServer => 'Версия сервера';

  @override
  String get collaborationProjectShared =>
      'Проект открыт для совместной работы';

  @override
  String get collaborationInviteEmailFailed =>
      'Приглашение сохранено, но письмо не отправилось';

  @override
  String collaborationInviteSent(String email) {
    return 'Приглашение отправлено на $email';
  }

  @override
  String get collaborationInvitationRevoked => 'Приглашение отозвано';

  @override
  String get collaborationRoleUpdated => 'Роль обновлена';

  @override
  String collaborationRemoveConfirm(String name) {
    return 'Удалить $name из проекта?';
  }

  @override
  String get collaborationMemberRemoved => 'Участник удалён';

  @override
  String collaborationTransferConfirm(String name) {
    return 'Сделать $name владельцем проекта?';
  }

  @override
  String get collaborationOwnershipTransferred => 'Владение передано';

  @override
  String get collaborationLeaveConfirm => 'Покинуть общий проект?';

  @override
  String get collaborationLeftProject => 'Вы покинули проект';

  @override
  String get collaborationDeleteSharedConfirm =>
      'Удалить общий проект для всех участников? Это действие необратимо.';

  @override
  String get collaborationSharedProjectDeleted => 'Общий проект удалён';

  @override
  String get collaborationMakePrivateConfirm =>
      'Прекратить совместный доступ к проекту?';

  @override
  String get collaborationMakePrivateDescription =>
      'Проект и его содержимое вернутся в вашу личную учётную запись. Остальные участники сразу потеряют доступ.';

  @override
  String get collaborationProjectMadePrivate => 'Проект снова личный';

  @override
  String get collaborationLinkCopied => 'Ссылка скопирована';

  @override
  String get collaborationConflictResolved => 'Конфликт разрешён';

  @override
  String get collaborationRoleAdministrator => 'Администратор';

  @override
  String get collaborationRoleMember => 'Участник';

  @override
  String get collaborationRoleObserver => 'Наблюдатель';

  @override
  String get collaborationForbidden => 'Недостаточно прав';

  @override
  String get collaborationSignedOut =>
      'Войдите, чтобы использовать общие проекты';

  @override
  String get collaborationUnavailable => 'Общие проекты сейчас недоступны';

  @override
  String get collaborationError => 'Что-то пошло не так. Попробуйте ещё раз';

  @override
  String get collaborationSyncPending =>
      'Завершите синхронизацию проекта перед открытием доступа';

  @override
  String get collaborationMemberFallback => 'Участник';

  @override
  String get collaborationInboxTitle => 'Общие проекты и приглашения';

  @override
  String get collaborationInboxSubtitle =>
      'Принимайте приглашения и следите за активностью общих проектов';

  @override
  String get collaborationInvitations => 'Приглашения';

  @override
  String get collaborationNoInvitations => 'Нет ожидающих приглашений';

  @override
  String get collaborationAccept => 'Принять';

  @override
  String get collaborationNotifications => 'Уведомления';

  @override
  String get collaborationMarkAllRead => 'Прочитать все';

  @override
  String get collaborationNoNotifications => 'Нет уведомлений';

  @override
  String get collaborationNotificationInvitation =>
      'Приглашение в общий проект';

  @override
  String get collaborationNotificationDiscussion =>
      'Новый комментарий в общем проекте';

  @override
  String get collaborationNotificationAssignment => 'Вам назначили задачу';

  @override
  String get collaborationNotificationGeneric => 'Активность в общем проекте';

  @override
  String get collaborationInvitationAccepted => 'Приглашение принято';

  @override
  String get collaborationAssignees => 'Исполнители';

  @override
  String get collaborationEditAssignees => 'Изменить исполнителей';

  @override
  String get collaborationNoAssignees => 'Нет исполнителей';

  @override
  String get collaborationComments => 'Комментарии';

  @override
  String get collaborationCommentHint => 'Написать комментарий';

  @override
  String get collaborationCommentSend => 'Отправить';

  @override
  String get collaborationCommentDelete => 'Удалить комментарий';

  @override
  String get collaborationSharedBadge => 'Общий проект';

  @override
  String get collaborationJoinTitle => 'Приглашение в проект';

  @override
  String get collaborationJoinDescription =>
      'Вас пригласили присоединиться к общему проекту. Примите приглашение, чтобы добавить его в свои проекты.';

  @override
  String get collaborationJoinRole => 'Ваша роль';

  @override
  String get collaborationJoinAccept => 'Принять приглашение';

  @override
  String get collaborationJoinOpenProject => 'Открыть проект';

  @override
  String get collaborationJoinInvalid =>
      'Эта ссылка-приглашение недействительна';

  @override
  String get collaborationJoinUnavailable =>
      'Это приглашение больше недоступно для вашего аккаунта';

  @override
  String get collaborationPublicNotice =>
      'Просмотр только для чтения, которым поделился участник Pomodoist';

  @override
  String get collaborationPublicUnavailable =>
      'Эта общая ссылка больше недоступна';

  @override
  String get collaborationPublicEmpty => 'Пока ничего не опубликовано';

  @override
  String get collaborationPublicOpen => 'Открыть Pomodoist';

  @override
  String get collaborationPublicTasks => 'Задачи';
}

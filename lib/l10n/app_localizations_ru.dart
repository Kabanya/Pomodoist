// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

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
  String billingPurchaseError(String error) {
    return 'Ошибка покупки: $error';
  }

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
    return 'Акция Lifetime закончится через $time';
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
      'Откройте ссылку подтверждения, чтобы завершить создание аккаунта.';

  @override
  String registerError(Object error) {
    return 'Не удалось создать аккаунт: $error';
  }

  @override
  String get authEmailSignInTitle => 'Вход по email';

  @override
  String get authSignInAction => 'Войти';

  @override
  String get authSendLink => 'Отправить ссылку';

  @override
  String get authMagicLinkSent =>
      'Ссылка для входа отправлена. Проверьте входящие и папку «Спам».';

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
      'Неверный email или пароль. Проверьте данные и попробуйте снова.';

  @override
  String get authEmailUnconfirmed =>
      'Подтвердите email по ссылке из письма, затем войдите снова.';

  @override
  String get authWeakPassword =>
      'Этот пароль слишком легко угадать. Используйте более длинный и менее предсказуемый пароль.';

  @override
  String get authAccountMayExist =>
      'Не удалось создать аккаунт. Если вы уже регистрировались с этим email, войдите.';

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
      'Мягкий вечерний пинок, если сегодня нет фокуса или закрытой задачи.';

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
  String get voiceSmartMode => 'Умный режим';

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
}

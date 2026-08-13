// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonUndo => 'Rückgängig';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonCreate => 'Erstellen';

  @override
  String get commonClear => 'Leeren';

  @override
  String get commonStop => 'Stopp';

  @override
  String get skip => 'Überspringen';

  @override
  String get onboardingLanguageTitle => 'Sprache wählen';

  @override
  String get onboardingLanguageSubtitle =>
      'Wähle die Sprache, die Pomodoist verwenden soll.';

  @override
  String get onboardingTimerTitle => 'Timer-Stil wählen';

  @override
  String get onboardingTimerSubtitle =>
      'Wähle die Pomodoro-Fortschrittsanzeige für Fokussitzungen.';

  @override
  String get onboardingPaywallTitle => 'Pomodoist freischalten';

  @override
  String get onboardingPaywallSubtitle =>
      'Das Lifetime-Angebot ist jede Woche 24 Stunden lang verfügbar.';

  @override
  String get onboardingAccountTitle => 'Konto erstellen';

  @override
  String get onboardingAccountSubtitle =>
      'Melde dich an, um Aufgaben, Fokusverlauf und Einstellungen zwischen Geräten zu synchronisieren.';

  @override
  String get startupPreparingTasks => 'Deine Aufgaben werden vorbereitet';

  @override
  String get operationTakingLonger =>
      'Der Vorgang dauert länger als üblich, wird aber weiterhin ausgeführt.';

  @override
  String get onboardingContinue => 'Weiter';

  @override
  String get onboardingMaybeLater => 'Vielleicht später';

  @override
  String get onboardingFinish => 'Fertig';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Diktiere Aufgaben in natürlicher Sprache, und Pomodoist macht daraus Aufgaben. Der Aufgabenverlauf bleibt dauerhaft gespeichert.';

  @override
  String get billingSubtitleHighlight => 'natürlicher Sprache';

  @override
  String get billingCancelAnytime => 'Jederzeit kündbar.';

  @override
  String get billingMonthlyTitle => 'Monatlich';

  @override
  String get billingAnnualTitle => 'Jährlich';

  @override
  String billingPricePerMonth(String price) {
    return '$price/Monat';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/Jahr';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'Die ersten 3 Monate, danach $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Danach $price.';
  }

  @override
  String get billingLifetimeTitle => 'Lebenslang';

  @override
  String get billingLifetimeSubtitle => 'Einmal zahlen, für immer nutzen.';

  @override
  String get billingBestValue => 'Bester Wert';

  @override
  String get billingChoose => 'Wählen';

  @override
  String get billingActive => 'Pomodoist Pro ist auf diesem Gerät aktiv.';

  @override
  String get billingActiveShort => 'Aktiv';

  @override
  String get billingRestore => 'Käufe wiederherstellen';

  @override
  String get billingManageLink => 'Über Link verwalten';

  @override
  String get billingExternalBrowserTitle =>
      'Die Zahlung wird im Browser geöffnet';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist öffnet Stripe Checkout in Safari oder deinem Standardbrowser. Erlaube das Browserfenster, um fortzufahren.';

  @override
  String get billingAppleOnly =>
      'Käufe sind auf iPhone, iPad und Mac verfügbar.';

  @override
  String get billingStoreUnavailable =>
      'Der App Store ist momentan nicht verfügbar.';

  @override
  String billingPurchaseError(String error) {
    return 'Kauffehler: $error';
  }

  @override
  String get purchaseSuccessTitle => 'Pro ist aktiv';

  @override
  String get purchaseSuccessMessage =>
      'Danke, dass du Pomodoist unterstützt. Alle Pro-Funktionen sind jetzt verfügbar.';

  @override
  String get purchaseSuccessContinue => 'Weiter';

  @override
  String get purchaseProcessingTitle => 'Zahlung wird verarbeitet';

  @override
  String get purchaseProcessingMessage =>
      'Die Zahlung wird bestätigt. Falls Pro nicht bald erscheint, aktualisiere später erneut.';

  @override
  String get purchaseOpenApp => 'Pomodoist öffnen';

  @override
  String launchOfferEndsIn(String time) {
    return 'Lifetime-Angebot endet in $time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'E-Mail';

  @override
  String get loginTitle => 'Bei Pomodoist anmelden';

  @override
  String get accountChecking => 'Konto wird überprüft';

  @override
  String get oauthConsentTitle => 'Agenten verbinden';

  @override
  String get oauthConsentLoading => 'Verbindungsanfrage wird geprüft';

  @override
  String get oauthConsentInvalidAuthorization =>
      'Diese Verbindungsanfrage fehlt oder ist ungültig.';

  @override
  String get oauthConsentLoadError =>
      'Die Verbindungsanfrage konnte nicht geladen werden.';

  @override
  String get oauthConsentActionError =>
      'Die Anfrage konnte nicht abgeschlossen werden. Versuche es erneut.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist hat eine unsichere oder fehlende Rücksprungadresse erhalten. Der Zugriff wurde nicht übergeben.';

  @override
  String get oauthConsentClientFallback => 'Agent';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName möchte auf Pomodoist zugreifen';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Rücksprungadresse';

  @override
  String get oauthConsentCapabilitiesTitle => 'Dieser Agent kann';

  @override
  String get oauthConsentManagePlanning =>
      'Aufgaben, Projekte, eigene Labels und Kanban lesen und verwalten.';

  @override
  String get oauthConsentReadInsights =>
      'Abgeschlossenen Fokusverlauf, Produktivitätsberichte und Erfolge lesen.';

  @override
  String get oauthConsentUnavailableTitle => 'Dieser Agent kann nicht';

  @override
  String get oauthConsentUnavailable =>
      'Auf dein Konto oder Zahlungen, Google Kalender oder den laufenden Fokus-Timer zugreifen.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'Diese Anfrage verlangt nicht unterstützten Kontozugriff und kann nicht genehmigt werden.';

  @override
  String get oauthConsentApprove => 'Erlauben';

  @override
  String get oauthConsentDeny => 'Ablehnen';

  @override
  String get oauthConsentApproving => 'Zugriff wird erlaubt…';

  @override
  String get oauthConsentDenying => 'Anfrage wird abgelehnt…';

  @override
  String get oauthConsentRedirecting => 'Zurück zum Agenten…';

  @override
  String get loginCreateAccountPrompt => 'Noch kein Konto?';

  @override
  String get loginCreateAccountAction => 'Konto erstellen';

  @override
  String get registerTitle => 'Konto erstellen';

  @override
  String get registerSubtitle =>
      'Synchronisiere Aufgaben, Fokusverlauf und Einstellungen zwischen Geräten.';

  @override
  String get registerPassword => 'Passwort';

  @override
  String get registerSubmit => 'Konto erstellen';

  @override
  String get registerSignInPrompt => 'Schon ein Konto?';

  @override
  String get registerSignInAction => 'Anmelden';

  @override
  String get registerCheckEmailTitle => 'Prüfe deine E-Mail';

  @override
  String get registerCheckEmailMessage =>
      'Öffne den Bestätigungslink, um dein Konto fertig zu erstellen.';

  @override
  String registerError(Object error) {
    return 'Konto konnte nicht erstellt werden: $error';
  }

  @override
  String get navSearch => 'Suche';

  @override
  String get navInbox => 'Eingang';

  @override
  String get navPriorityMatrix => 'Prioritätsmatrix';

  @override
  String get navTimeline => 'Zeitleiste';

  @override
  String get navKanban => 'Kanban';

  @override
  String get kanbanTitle => 'Kanban';

  @override
  String get kanbanSubtitle =>
      'Visualisiere deinen Ablauf und konzentriere dich auf das Wesentliche.';

  @override
  String get kanbanDefaultBacklog => 'Backlog';

  @override
  String get kanbanDefaultTodo => 'Zu erledigen';

  @override
  String get kanbanDefaultInProgress => 'In Arbeit';

  @override
  String get kanbanDefaultDone => 'Erledigt';

  @override
  String get kanbanSearchTooltip => 'Kanban durchsuchen';

  @override
  String get kanbanSearchHint => 'Aufgaben oder Projekte suchen';

  @override
  String get kanbanHideDone => 'Erledigte ausblenden';

  @override
  String get kanbanShowDone => 'Erledigte anzeigen';

  @override
  String get kanbanProjectsTitle => 'Projekte auf diesem Board';

  @override
  String kanbanAddToStatus(String status) {
    return 'Zu $status hinzufügen';
  }

  @override
  String get kanbanTaskField => 'Aufgabe';

  @override
  String get kanbanProjectField => 'Projekt';

  @override
  String get kanbanChooseProject => 'Wähle ein Projekt.';

  @override
  String get kanbanTaskActions => 'Aufgabenaktionen';

  @override
  String get kanbanDragTask => 'Aufgabe ziehen';

  @override
  String kanbanMoveTo(String status) {
    return 'Nach $status verschieben';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Stelle die Aufgabe vor dem Fokusstart wieder her.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'Fokus konnte nicht gestartet werden: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'Kanban konnte nicht geladen werden: $error';
  }

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonContinueWaiting => 'Weiter warten';

  @override
  String kanbanTasksCount(int count) {
    return '$count Aufgaben';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '$completed von $total Unteraufgaben';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '$completed von $total Fokusintervallen';
  }

  @override
  String get kanbanActive => 'Aktiv';

  @override
  String kanbanPriority(int priority) {
    return 'Priorität $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Nach $status verschoben';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Fokus für $task gestartet';
  }

  @override
  String get kanbanNoTasks => 'Noch keine Aufgaben';

  @override
  String get navToday => 'Heute';

  @override
  String get navUpcoming => 'Bevorstehend';

  @override
  String get navBrowse => 'Durchsuchen';

  @override
  String get navIntegrations => 'Integrationen';

  @override
  String get navReports => 'Berichte';

  @override
  String get navFocus => 'Fokus';

  @override
  String get navProjects => 'Projekte';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get csvImportTitle => 'Aufgaben aus CSV importieren';

  @override
  String get csvImportSubtitle =>
      'Prüfe eine CSV-Datei, bevor Aufgaben, Projekte, Labels und Status erstellt werden.';

  @override
  String get csvImportSelectFile => 'CSV-Datei auswählen';

  @override
  String get csvImportHumanGuideButton => 'Anleitung für Menschen';

  @override
  String get csvImportAgentGuideButton => 'Anleitung für Agenten';

  @override
  String get csvImportHumanGuideTitle => 'CSV-Datei vorbereiten';

  @override
  String get csvImportAgentGuideTitle => 'CSV-Vertrag für Agenten';

  @override
  String get csvImportCopy => 'Kopieren';

  @override
  String get csvImportCopied => 'In die Zwischenablage kopiert.';

  @override
  String get csvImportPreviewTitle => 'Import prüfen';

  @override
  String get csvImportPreviewTasks => 'Aufgaben';

  @override
  String get csvImportPreviewSubtasks => 'Unteraufgaben';

  @override
  String get csvImportPreviewNewProjects => 'Neue Projekte';

  @override
  String get csvImportPreviewNewLabels => 'Neue Labels';

  @override
  String get csvImportPreviewNewStatuses => 'Neue Status';

  @override
  String get csvImportNone => 'Keine';

  @override
  String get csvImportDuplicateWarning =>
      'Ein erneuter Import derselben Datei erstellt doppelte Aufgaben.';

  @override
  String get csvImportConfirm => 'Importieren';

  @override
  String get csvImportSuccess => 'Importierte Aufgaben';

  @override
  String get csvImportErrorTitle => 'CSV-Import fehlgeschlagen';

  @override
  String get csvImportUnexpectedError =>
      'Die Datei konnte nicht importiert werden.';

  @override
  String get csvImportHumanGuide =>
      '1. Speichere die Datei als UTF-8-CSV. Verwende ein Komma (empfohlen) oder Semikolon als Trennzeichen.\n\n2. Die Spalte content ist erforderlich. Außerdem sind verfügbar: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Jede Zeile erstellt eine offene Aufgabe. Trenne Labels mit |. Die Priorität liegt zwischen 1 und 4; leer bedeutet 4. Ein leeres Projekt bedeutet Inbox, ein leerer Status Backlog. Fehlende Projekte, Labels und offene Status werden automatisch erstellt.\n\n4. Für ganztägige Aufgaben verwende due_date im Format YYYY-MM-DD. Für Aufgaben mit Uhrzeit fülle start_at und end_at als RFC3339-Werte mit UTC-Versatz aus und gib eine IANA-time_zone wie Europe/Berlin an.\n\n5. Für Unteraufgaben gib der Elternzeile einen eindeutigen key und trage ihn beim Kind als parent_key ein. Eltern dürfen später in der Datei stehen. Das Projekt des Kindes muss dem Elternprojekt entsprechen.\n\n6. Pomodoist prüft die gesamte Datei und zeigt vor dem Import eine Vorschau. Ist eine Zeile ungültig, wird nichts gespeichert. Ein erneuter Import erstellt Duplikate.';

  @override
  String get settingsConnectedAgentsTitle => 'Verbundene Agenten';

  @override
  String get settingsConnectedAgentsLoading =>
      'Verbundene Agenten werden geladen…';

  @override
  String get settingsConnectedAgentsEmpty => 'Keine Agenten verbunden.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'Verbundene Agenten konnten nicht geladen werden.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Agent';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Verbunden am $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Zugriff widerrufen';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'Agentenzugriff widerrufen?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'Pomodoist-Zugriff für „$clientName“ widerrufen?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'Zugriff konnte nicht widerrufen werden. Versuche es erneut.';

  @override
  String get settingsLanguageTitle => 'Sprache';

  @override
  String get settingsLanguageSubtitle => 'Wähle die App-Sprache.';

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsThemeTitle => 'Design';

  @override
  String get settingsThemeSubtitle => 'Wähle das Erscheinungsbild der App.';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsTimerVisualTitle => 'Pomodoro-Timer';

  @override
  String get settingsTimerVisualSubtitle =>
      'Wähle, wie der Fortschritt auf dem Fokusbildschirm angezeigt wird.';

  @override
  String get settingsTimerVisualBar => 'Leiste';

  @override
  String get settingsTimerVisualCircle => 'Kreis';

  @override
  String get settingsReturnRemindersTitle => 'Rückkehr-Erinnerungen';

  @override
  String get settingsReturnRemindersSubtitle =>
      'Ein sanfter Abendhinweis, wenn heute kein Fokus oder keine Aufgabe abgeschlossen wurde.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Standarddauer für Kalenderblöcke';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'Wenn nur eine Uhrzeit eingegeben wird, nutzen neue Aufgaben diese Kalenderdauer.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Eigene Dauer';

  @override
  String get settingsDefaultTimedBlockError => 'Gib 1 bis 480 Minuten ein.';

  @override
  String get menuTooltip => 'Menü';

  @override
  String get localUser => 'Lokaler Benutzer';

  @override
  String get addTask => 'Aufgabe hinzufügen';

  @override
  String get quickAddHint => 'Schreibe sync engine morgen p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'Aufgabe konnte nicht hinzugefügt werden: $error';
  }

  @override
  String couldNotAddProject(Object error) {
    return 'Projekt konnte nicht hinzugefügt werden: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben hinzugefügt',
      one: '1 Aufgabe hinzugefügt',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Spracheingabe';

  @override
  String get voiceTitle => 'Per Sprache hinzufügen';

  @override
  String get voiceRecord => 'Aufnehmen';

  @override
  String get voiceAgain => 'Erneut';

  @override
  String get voiceStop => 'Stopp';

  @override
  String voiceAddCount(int count) {
    return '$count hinzufügen';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Aufgabe $index';
  }

  @override
  String get voiceRemoveTask => 'Entfernen';

  @override
  String get voiceInstruction => 'Tippe auf Aufnahme und diktiere Aufgaben.';

  @override
  String get voiceStatusIdle => 'Nur Eingabe über eingebautes Mikrofon';

  @override
  String get voiceStatusRequestingPermission => 'Zugriff wird angefordert';

  @override
  String get voiceStatusRecording => 'Eingebautes Mikrofon hört zu';

  @override
  String get voiceStatusTranscribing => 'Aufnahme wird transkribiert';

  @override
  String get voiceStatusCanceled => 'Aufnahme abgebrochen';

  @override
  String get voiceStatusUnsupported => 'Plattform wird nicht unterstützt';

  @override
  String get voiceStatusError => 'Sprache konnte nicht erkannt werden';

  @override
  String get voiceStatusAnalyzing => 'Wird in Aufgaben aufgeteilt';

  @override
  String get voiceStatusReview => 'Prüfe die Aufgaben vor dem Hinzufügen';

  @override
  String get voiceStepRecord => 'Aufnahme';

  @override
  String get voiceStepText => 'Text';

  @override
  String get voiceStepAnalyze => 'Analyse';

  @override
  String get voiceStepReview => 'Prüfung';

  @override
  String get voiceAnalyzing => 'Pomodoist teilt Sprache in Aufgaben auf';

  @override
  String get voiceFallbackError =>
      'Pomodoist konnte die Sprache nicht verarbeiten, Entwurf bleibt zur manuellen Bearbeitung.';

  @override
  String get voiceSmartMode => 'Intelligenter Modus';

  @override
  String get voiceRetryAnalysis => 'Analyse wiederholen';

  @override
  String get screenInboxSubtitle =>
      'Aufgaben sammeln, bevor du sie organisierst.';

  @override
  String get priorityMatrixSubtitle =>
      'Ziehe Aufgaben zwischen Prioritäten. Termine sortieren nur innerhalb einer Priorität.';

  @override
  String get priorityMatrixP1Title => 'Jetzt erledigen';

  @override
  String get priorityMatrixP2Title => 'Planen';

  @override
  String get priorityMatrixP3Title => 'Delegieren';

  @override
  String get priorityMatrixP4Title => 'Streichen';

  @override
  String get priorityMatrixAxisUrgent => 'Dringend';

  @override
  String get priorityMatrixAxisNotUrgent => 'Nicht dringend';

  @override
  String get priorityMatrixAxisImportant => 'Wichtig';

  @override
  String get priorityMatrixAxisNotImportant => 'Nicht wichtig';

  @override
  String get timelineSubtitle => 'Plane einen Tag auf einem Zeitraster.';

  @override
  String get timelineAllDay => 'Ganztägig';

  @override
  String get timelineBeforeHours => 'Vor sichtbaren Stunden';

  @override
  String get timelineAfterHours => 'Nach sichtbaren Stunden';

  @override
  String get timelineVisibleHours => 'Sichtbare Stunden';

  @override
  String get timelineStartHour => 'Start';

  @override
  String get timelineEndHour => 'Ende';

  @override
  String get timelineZoomOut => 'Verkleinern';

  @override
  String get timelineZoomIn => 'Vergrößern';

  @override
  String timelineAddTimedHint(String time) {
    return 'Aufgabe um $time';
  }

  @override
  String get timelineAddAllDayHint => 'Ganztägige Aufgabe';

  @override
  String get timelineNoAllDayTasks => 'Keine ganztägigen Aufgaben';

  @override
  String get timelineNoTimedTasks => 'Keine Aufgaben mit Uhrzeit';

  @override
  String get timelinePreviousDay => 'Vorheriger Tag';

  @override
  String get timelineNextDay => 'Nächster Tag';

  @override
  String get timelinePickDate => 'Datum wählen';

  @override
  String get upcomingPreviousPeriod => 'Vorheriger Zeitraum';

  @override
  String get upcomingNextPeriod => 'Nächster Zeitraum';

  @override
  String get upcomingOpenDatePicker => 'Datumsauswahl öffnen';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben',
      one: '1 Aufgabe',
      zero: 'Keine Aufgaben',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Fokuslast: $planned Intervalle - Erledigt: $completed - Fokus: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Geplante Aufgaben nach heute.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Aufgaben geplant für $date.';
  }

  @override
  String get noTasksHere => 'Hier sind keine Aufgaben';

  @override
  String get noUpcomingTasks => 'Keine datierten Aufgaben';

  @override
  String get noTasksForDay => 'Für diesen Tag sind keine Aufgaben geplant';

  @override
  String failedToLoadTasks(Object error) {
    return 'Aufgaben konnten nicht geladen werden: $error';
  }

  @override
  String get searchTasks => 'Aufgaben suchen';

  @override
  String get searchStartTyping => 'Tippe, um Aufgaben zu suchen';

  @override
  String get searchNoMatches => 'Keine passenden Aufgaben';

  @override
  String failedToSearchTasks(Object error) {
    return 'Aufgaben konnten nicht gesucht werden: $error';
  }

  @override
  String get previousMonth => 'Vorheriger Monat';

  @override
  String get nextMonth => 'Nächster Monat';

  @override
  String get clearDateFilter => 'Datumsfilter löschen';

  @override
  String get weekMon => 'Mo';

  @override
  String get weekTue => 'Di';

  @override
  String get weekWed => 'Mi';

  @override
  String get weekThu => 'Do';

  @override
  String get weekFri => 'Fr';

  @override
  String get weekSat => 'Sa';

  @override
  String get weekSun => 'So';

  @override
  String get browseTitle => 'Durchsuchen';

  @override
  String get unifiedAccount => 'Einheitliches Konto';

  @override
  String accountUnavailable(Object error) {
    return 'Konto nicht verfügbar: $error';
  }

  @override
  String get signOut => 'Abmelden';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountConfirmation =>
      'Dadurch werden dein Konto, deine Cloud-Daten sowie lokale Aufgaben, Projekte und der Fokusverlauf dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden. Store-Abonnements werden nicht automatisch gekündigt.';

  @override
  String get deleteAccountFinalConfirmation =>
      'Bist du dir wirklich sicher? Dies ist die letzte Bestätigung.';

  @override
  String deleteAccountError(Object error) {
    return 'Konto konnte nicht gelöscht werden: $error';
  }

  @override
  String get accountDeleted => 'Konto gelöscht.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Dein Konto wurde gelöscht, aber die lokalen Daten konnten nicht gelöscht werden. Lösche die App-Daten, bevor du dieses Gerät weiter verwendest.';

  @override
  String get productivityTitle => 'Produktivität';

  @override
  String get achievementsTitle => 'Erfolge';

  @override
  String get allTimeLabel => 'Gesamt';

  @override
  String get lastSevenDaysLabel => 'Letzte 7 Tage';

  @override
  String get noWeeklyStatsLabel => 'Noch keine Fokus- oder Aufgabendaten';

  @override
  String get completedFocuses => 'Abgeschlossene Fokusintervalle';

  @override
  String get completedTasks => 'Erledigte Aufgaben';

  @override
  String get unlocked => 'Freigeschaltet';

  @override
  String get locked => 'Gesperrt';

  @override
  String get progressLabel => 'Fortschritt';

  @override
  String get focusAchievements => 'Fokus-Erfolge';

  @override
  String get taskAchievements => 'Aufgaben-Erfolge';

  @override
  String get comboAchievements => 'Kombi-Erfolge';

  @override
  String get focusIntervals => 'Fokusintervalle';

  @override
  String get focusTime => 'Fokuszeit';

  @override
  String get openTasks => 'Offene Aufgaben';

  @override
  String get plannedIntervals => 'Geplante Intervalle';

  @override
  String get labelsTitle => 'Labels';

  @override
  String get newProject => 'Neues Projekt';

  @override
  String get newLabel => 'Neues Label';

  @override
  String get syncReadyQueue => 'Sync-bereite Warteschlange';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausstehende lokale Befehle',
      one: '1 ausstehender lokaler Befehl',
      zero: 'Keine ausstehenden lokalen Befehle',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'Projekte konnten nicht geladen werden: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'Labels konnten nicht geladen werden: $error';
  }

  @override
  String get addProject => 'Projekt hinzufügen';

  @override
  String get projectName => 'Projektname';

  @override
  String get addLabel => 'Label hinzufügen';

  @override
  String get labelName => 'Labelname';

  @override
  String couldNotAddLabel(Object error) {
    return 'Label konnte nicht hinzugefügt werden: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Projekte nicht verfügbar: $error';
  }

  @override
  String get projectsUnavailableShort => 'Projekte nicht verfügbar';

  @override
  String get noProjects => 'Keine Projekte';

  @override
  String get searchProjects => 'Projekte suchen';

  @override
  String get searchLabels => 'Labels suchen';

  @override
  String get archivedProjectsOnly => 'Nur archivierte Projekte';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Projekte',
      one: '1 Projekt',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'Keine Labels';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Labels',
      one: '1 Label',
    );
    return '$_temp0';
  }

  @override
  String get deleteProject => 'Projekt löschen';

  @override
  String get deleteLabel => 'Label löschen';

  @override
  String deleteProjectConfirmation(String name) {
    return '\"$name\" löschen? Aufgaben in diesem Projekt werden in den Eingang verschoben.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return '\"$name\" löschen?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'Projekt konnte nicht gelöscht werden: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'Label konnte nicht gelöscht werden: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Projekte: $count';
  }

  @override
  String get collapseProjects => 'Projekte einklappen';

  @override
  String get expandProjects => 'Projekte ausklappen';

  @override
  String get projectFallbackTitle => 'Projekt';

  @override
  String get projectSubtitle =>
      'Listenansicht - Board und Kalender sind geplant.';

  @override
  String get reportsTitle => 'Berichte';

  @override
  String get reportsFocusedDay => 'Ein fokussierter Tag bisher';

  @override
  String get reportsThisWeek => 'Deine Woche im Fokus';

  @override
  String get reportsNextAchievement => 'Nächster Erfolg';

  @override
  String get viewAllAchievements => 'Alle Erfolge anzeigen';

  @override
  String viewAllAchievementsCount(int count) {
    return 'Alle $count anzeigen';
  }

  @override
  String get allAchievementsUnlocked => 'Alle Erfolge freigeschaltet';

  @override
  String get noAchievementsYet => 'Noch keine Erfolge';

  @override
  String failedToLoadAchievements(Object error) {
    return 'Erfolge konnten nicht geladen werden: $error';
  }

  @override
  String get backToReports => 'Zurück zu den Berichten';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '$completed von $target Fokusintervallen abgeschlossen';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '$completed Fokusintervalle abgeschlossen; kein Ziel gesetzt';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Fokuszeit der letzten 7 Tage: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'Berichte konnten nicht geladen werden: $error';
  }

  @override
  String get taskNotFound => 'Aufgabe nicht gefunden';

  @override
  String get taskTitleHint => 'Aufgabentitel';

  @override
  String get taskComment => 'Kommentar';

  @override
  String get taskCommentHint => 'Kommentar hinzufügen';

  @override
  String get subtasks => 'Unteraufgaben';

  @override
  String get addSubtask => 'Unteraufgabe hinzufügen';

  @override
  String get addSubtaskHint => 'Unteraufgabe hinzufügen';

  @override
  String get noSubtasks => 'Noch keine Unteraufgaben.';

  @override
  String get makeParentTask => 'Zur Hauptaufgabe machen';

  @override
  String couldNotMoveTask(Object error) {
    return 'Aufgabe konnte nicht verschoben werden: $error';
  }

  @override
  String get scheduleTitle => 'Zeitplan';

  @override
  String get allDay => 'Ganztägig';

  @override
  String get timedBlock => 'Zeitblock';

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
  String get noDate => 'Kein Datum';

  @override
  String get calendarNotLinked => 'Kalender nicht verknüpft';

  @override
  String get calendarLinked => 'Google Kalender verknüpft';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total Fokus';
  }

  @override
  String get startFocus => 'Fokus starten';

  @override
  String get focusStarted => 'Fokus gestartet';

  @override
  String get taskReopened => 'Aufgabe wieder geöffnet';

  @override
  String get taskCompleted => 'Aufgabe erledigt';

  @override
  String get taskDeleted => 'Aufgabe gelöscht';

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
  String get markOpen => 'Als offen markieren';

  @override
  String get markComplete => 'Als erledigt markieren';

  @override
  String get focusHistory => 'Fokusverlauf';

  @override
  String failedToLoadTask(Object error) {
    return 'Aufgabe konnte nicht geladen werden: $error';
  }

  @override
  String get noFocusIntervals => 'Noch keine Fokusintervalle.';

  @override
  String get today => 'Heute';

  @override
  String get tomorrow => 'Morgen';

  @override
  String get yesterday => 'Gestern';

  @override
  String get clearDate => 'Datum löschen';

  @override
  String priority(int priority) {
    return 'Priorität $priority';
  }

  @override
  String get focusTitle => 'Fokus';

  @override
  String focusLoadError(Object error) {
    return 'Fokus konnte nicht geladen werden: $error';
  }

  @override
  String get focusViewFull => 'Voll';

  @override
  String get focusViewMinimal => 'Minimal';

  @override
  String get noActiveSession => 'Keine aktive Sitzung';

  @override
  String get focusIdleSubtitle =>
      'Starte ein eigenständiges Fokusintervall oder Fokus aus einer Aufgabe.';

  @override
  String get noPreset => 'Kein Preset';

  @override
  String get preparingFocus => 'Fokus wird vorbereitet';

  @override
  String get moreFocusOptions => 'Weitere Fokusoptionen';

  @override
  String get moreFocusActions => 'Weitere Fokusaktionen';

  @override
  String get preset => 'Preset';

  @override
  String get newPreset => 'Neues Preset';

  @override
  String get customize => 'Anpassen';

  @override
  String get customizePreset => 'Preset anpassen';

  @override
  String get startInterval => 'Intervall starten';

  @override
  String get intervalStarted => 'Intervall gestartet';

  @override
  String get intervalCompleted => 'Intervall abgeschlossen';

  @override
  String get focusStopped => 'Fokus gestoppt';

  @override
  String get completeInterval => 'Intervall abschließen';

  @override
  String get logDistraction => 'Ablenkung protokollieren';

  @override
  String get workInterval => 'Arbeitsintervall';

  @override
  String get work => 'Arbeit';

  @override
  String get shortBreak => 'Kurze Pause';

  @override
  String get breakLabel => 'Pause';

  @override
  String get longBreak => 'Lange Pause';

  @override
  String readyLabel(String label) {
    return 'Bereit: $label';
  }

  @override
  String get readyShort => 'Bereit';

  @override
  String focusTimerTotal(String duration) {
    return 'von $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Sitzung $current von $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Fokusrhythmus-Vorschau, $count Schritte';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Fokusrhythmus, Schritt $current von $total: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, $remaining verbleibend, $total gesamt';
  }

  @override
  String get focusStatusRunning => 'Läuft';

  @override
  String get focusStatusPaused => 'Pausiert';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total Arbeit';
  }

  @override
  String intervalNumber(int number) {
    return 'Intervall $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total Arbeit - Intervall $number';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get presetForNextIntervals => 'Preset für nächste Intervalle';

  @override
  String usePreset(String name) {
    return '$name verwenden';
  }

  @override
  String minutesWork(int minutes) {
    return '${minutes}m Arbeit';
  }

  @override
  String minutesShort(int minutes) {
    return '${minutes}m kurz';
  }

  @override
  String minutesLong(int minutes) {
    return '${minutes}m lang';
  }

  @override
  String longEvery(int count) {
    return 'Lang alle $count';
  }

  @override
  String get autoBreaks => 'Auto-Pausen';

  @override
  String get autoWork => 'Auto-Arbeit';

  @override
  String get noPause => 'Keine Pause';

  @override
  String get focusPauseUnavailable =>
      'Pause ist für dieses Preset nicht verfügbar';

  @override
  String get strict => 'Strikt';

  @override
  String get flexible => 'Flexibel';

  @override
  String get name => 'Name';

  @override
  String get workField => 'Arbeit';

  @override
  String get shortField => 'Kurz';

  @override
  String get longField => 'Lang';

  @override
  String get every => 'Alle';

  @override
  String get minutesSuffix => 'min';

  @override
  String get makeDefault => 'Als Standard';

  @override
  String get autoStartBreaks => 'Pausen automatisch starten';

  @override
  String get autoStartWork => 'Arbeit automatisch starten';

  @override
  String get allowPause => 'Pause erlauben';

  @override
  String get strictMode => 'Strikter Modus';

  @override
  String get nameRequired => 'Name ist erforderlich';

  @override
  String get nameMustBeUnique => 'Name muss eindeutig sein';

  @override
  String get googleCalendarTitle => 'Google Kalender';

  @override
  String get googleCalendarConnectedSubtitle =>
      'Zwei-Wege-Sync ist für den Pomodoist-Kalender aktiv.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Verbinde ein Google-Konto, um geplante Aufgaben zu synchronisieren.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'Die Google Kalender-Synchronisierung läuft auf einem anderen Gerät. Pomodoist-Daten werden hier weiterhin synchronisiert.';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get useThisDevice => 'Dieses Gerät verwenden';

  @override
  String get connect => 'Verbinden';

  @override
  String get disconnect => 'Trennen';

  @override
  String failedToLoadIntegration(Object error) {
    return 'Integration konnte nicht geladen werden: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Kalender fehlgeschlagen: $message';
  }

  @override
  String get googleAuthRequired =>
      'Google Kalender-Autorisierung ist erforderlich. Melde dich erneut an und starte Jetzt synchronisieren.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In ist nicht konfiguriert. Setze GOOGLE_CLIENT_ID und GOOGLE_REVERSED_CLIENT_ID für dieses iOS-Target.';

  @override
  String get googleCallbackNotConfigured =>
      'Google Sign-In-Callback ist nicht konfiguriert. Setze GOOGLE_REVERSED_CLIENT_ID in ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'Im Web zuerst die Google-Anmeldeschaltfläche klicken, dann Verbinden.';

  @override
  String get googleAccessDenied =>
      'Google-Zugriff wurde verweigert. Füge dieses Google-Konto als OAuth-Testnutzer hinzu oder veröffentliche und verifiziere die OAuth-App.';

  @override
  String get status => 'Status';

  @override
  String get account => 'Konto';

  @override
  String get calendar => 'Kalender';

  @override
  String get calendarId => 'Kalender-ID';

  @override
  String get lastSync => 'Letzter Sync';

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get notCreated => 'Nicht erstellt';

  @override
  String get never => 'Nie';

  @override
  String durationMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get projectColor => 'Projektfarbe';

  @override
  String projectColorOption(int number) {
    return 'Farbe $number';
  }

  @override
  String get addProjectToFavorites => 'Projekt zu Favoriten hinzufügen';

  @override
  String get removeProjectFromFavorites => 'Projekt aus Favoriten entfernen';

  @override
  String get timelineProjectsMenu => 'Timeline-Projekte verwalten';

  @override
  String get timelineShowProject => 'Projekt in Timeline anzeigen';

  @override
  String get timelineHideProject => 'Temporäres Projekt ausblenden';

  @override
  String get timelineCollapseProject => 'Projektzweig einklappen';

  @override
  String get timelineExpandProject => 'Projektzweig ausklappen';

  @override
  String get timelineCurrentTime => 'Aktuelle Uhrzeit';

  @override
  String couldNotUpdateProject(Object error) {
    return 'Projekt konnte nicht aktualisiert werden: $error';
  }
}

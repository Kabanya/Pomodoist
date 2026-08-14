import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'pomodoist'**
  String get appTitle;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get commonStop;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @onboardingLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get onboardingLanguageTitle;

  /// No description provided for @onboardingLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the language Pomodoist should use.'**
  String get onboardingLanguageSubtitle;

  /// No description provided for @onboardingTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose timer style'**
  String get onboardingTimerTitle;

  /// No description provided for @onboardingTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the Pomodoro progress view for focus sessions.'**
  String get onboardingTimerSubtitle;

  /// No description provided for @onboardingPaywallTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pomodoist'**
  String get onboardingPaywallTitle;

  /// No description provided for @onboardingPaywallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The Lifetime offer is available for 24 hours every week.'**
  String get onboardingPaywallSubtitle;

  /// No description provided for @onboardingAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get onboardingAccountTitle;

  /// No description provided for @onboardingAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync tasks, focus history, and settings between devices.'**
  String get onboardingAccountSubtitle;

  /// No description provided for @startupPreparingTasks.
  ///
  /// In en, this message translates to:
  /// **'Preparing your tasks'**
  String get startupPreparingTasks;

  /// No description provided for @operationTakingLonger.
  ///
  /// In en, this message translates to:
  /// **'This is taking longer than usual. The operation is still running.'**
  String get operationTakingLonger;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get onboardingMaybeLater;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @billingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist Pro'**
  String get billingTitle;

  /// No description provided for @billingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dictate tasks in natural language, and Pomodoist turns your words into tasks. Task history is saved forever.'**
  String get billingSubtitle;

  /// No description provided for @billingSubtitleHighlight.
  ///
  /// In en, this message translates to:
  /// **'natural language'**
  String get billingSubtitleHighlight;

  /// No description provided for @billingCancelAnytime.
  ///
  /// In en, this message translates to:
  /// **'Cancel anytime.'**
  String get billingCancelAnytime;

  /// No description provided for @billingMonthlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get billingMonthlyTitle;

  /// No description provided for @billingAnnualTitle.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get billingAnnualTitle;

  /// No description provided for @billingPricePerMonth.
  ///
  /// In en, this message translates to:
  /// **'{price}/month'**
  String billingPricePerMonth(String price);

  /// No description provided for @billingPricePerYear.
  ///
  /// In en, this message translates to:
  /// **'{price}/year'**
  String billingPricePerYear(String price);

  /// No description provided for @billingMonthlyIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'First 3 months, then {price}.'**
  String billingMonthlyIntroSubtitle(String price);

  /// No description provided for @billingAnnualIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Then {price}.'**
  String billingAnnualIntroSubtitle(String price);

  /// No description provided for @billingLifetimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get billingLifetimeTitle;

  /// No description provided for @billingLifetimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One payment forever.'**
  String get billingLifetimeSubtitle;

  /// No description provided for @billingBestValue.
  ///
  /// In en, this message translates to:
  /// **'Best value'**
  String get billingBestValue;

  /// No description provided for @billingChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get billingChoose;

  /// No description provided for @billingActive.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist Pro is active on this device.'**
  String get billingActive;

  /// No description provided for @billingActiveShort.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get billingActiveShort;

  /// No description provided for @billingRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get billingRestore;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @billingManageLink.
  ///
  /// In en, this message translates to:
  /// **'Manage through Link'**
  String get billingManageLink;

  /// No description provided for @billingExternalBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment opens in your browser'**
  String get billingExternalBrowserTitle;

  /// No description provided for @billingExternalBrowserMessage.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist will open Stripe Checkout in Safari or your default browser. Allow the browser window to continue.'**
  String get billingExternalBrowserMessage;

  /// No description provided for @billingAppleOnly.
  ///
  /// In en, this message translates to:
  /// **'Purchases are available on iPhone, iPad, and Mac.'**
  String get billingAppleOnly;

  /// No description provided for @billingStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The App Store is not available right now.'**
  String get billingStoreUnavailable;

  /// No description provided for @billingPurchaseError.
  ///
  /// In en, this message translates to:
  /// **'Purchase error: {error}'**
  String billingPurchaseError(String error);

  /// No description provided for @purchaseSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Pro is active'**
  String get purchaseSuccessTitle;

  /// No description provided for @purchaseSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Thanks for supporting Pomodoist. All Pro features are ready to use.'**
  String get purchaseSuccessMessage;

  /// No description provided for @purchaseSuccessContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get purchaseSuccessContinue;

  /// No description provided for @purchaseProcessingTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment is processing'**
  String get purchaseProcessingTitle;

  /// No description provided for @purchaseProcessingMessage.
  ///
  /// In en, this message translates to:
  /// **'Your payment is being confirmed. If Pro does not appear shortly, refresh again later.'**
  String get purchaseProcessingMessage;

  /// No description provided for @purchaseOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Open Pomodoist'**
  String get purchaseOpenApp;

  /// No description provided for @launchOfferEndsIn.
  ///
  /// In en, this message translates to:
  /// **'Lifetime offer ends in {time}'**
  String launchOfferEndsIn(String time);

  /// No description provided for @accountApple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get accountApple;

  /// No description provided for @accountGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get accountGoogle;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Pomodoist'**
  String get loginTitle;

  /// No description provided for @accountChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your account'**
  String get accountChecking;

  /// No description provided for @oauthConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect an agent'**
  String get oauthConsentTitle;

  /// No description provided for @oauthConsentLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking the connection request'**
  String get oauthConsentLoading;

  /// No description provided for @oauthConsentInvalidAuthorization.
  ///
  /// In en, this message translates to:
  /// **'This connection request is missing or invalid.'**
  String get oauthConsentInvalidAuthorization;

  /// No description provided for @oauthConsentLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the connection request.'**
  String get oauthConsentLoadError;

  /// No description provided for @oauthConsentActionError.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the request. Try again.'**
  String get oauthConsentActionError;

  /// No description provided for @oauthConsentRedirectError.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist received an unsafe or missing return address. Access was not handed off.'**
  String get oauthConsentRedirectError;

  /// No description provided for @oauthConsentClientFallback.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get oauthConsentClientFallback;

  /// No description provided for @oauthConsentClientRequest.
  ///
  /// In en, this message translates to:
  /// **'{clientName} wants to access Pomodoist'**
  String oauthConsentClientRequest(String clientName);

  /// No description provided for @oauthConsentRedirectOrigin.
  ///
  /// In en, this message translates to:
  /// **'Return address'**
  String get oauthConsentRedirectOrigin;

  /// No description provided for @oauthConsentCapabilitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'This agent can'**
  String get oauthConsentCapabilitiesTitle;

  /// No description provided for @oauthConsentManagePlanning.
  ///
  /// In en, this message translates to:
  /// **'Read and manage tasks, projects, user labels, and Kanban.'**
  String get oauthConsentManagePlanning;

  /// No description provided for @oauthConsentReadInsights.
  ///
  /// In en, this message translates to:
  /// **'Read completed focus history, productivity reports, and achievements.'**
  String get oauthConsentReadInsights;

  /// No description provided for @oauthConsentUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This agent cannot'**
  String get oauthConsentUnavailableTitle;

  /// No description provided for @oauthConsentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Access your account or billing, Google Calendar, or the live focus timer.'**
  String get oauthConsentUnavailable;

  /// No description provided for @oauthConsentUnsupportedScopes.
  ///
  /// In en, this message translates to:
  /// **'This request asks for unsupported account access and cannot be approved.'**
  String get oauthConsentUnsupportedScopes;

  /// No description provided for @oauthConsentApprove.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get oauthConsentApprove;

  /// No description provided for @oauthConsentDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get oauthConsentDeny;

  /// No description provided for @oauthConsentApproving.
  ///
  /// In en, this message translates to:
  /// **'Allowing access…'**
  String get oauthConsentApproving;

  /// No description provided for @oauthConsentDenying.
  ///
  /// In en, this message translates to:
  /// **'Denying access…'**
  String get oauthConsentDenying;

  /// No description provided for @oauthConsentRedirecting.
  ///
  /// In en, this message translates to:
  /// **'Returning to the agent…'**
  String get oauthConsentRedirecting;

  /// No description provided for @loginCreateAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'No account yet?'**
  String get loginCreateAccountPrompt;

  /// No description provided for @loginCreateAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get loginCreateAccountAction;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync tasks, focus history, and settings between devices.'**
  String get registerSubtitle;

  /// No description provided for @registerPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get registerPassword;

  /// No description provided for @registerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerSubmit;

  /// No description provided for @registerSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get registerSignInPrompt;

  /// No description provided for @registerSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get registerSignInAction;

  /// No description provided for @registerCheckEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get registerCheckEmailTitle;

  /// No description provided for @registerCheckEmailMessage.
  ///
  /// In en, this message translates to:
  /// **'Open the confirmation link to finish creating your account.'**
  String get registerCheckEmailMessage;

  /// No description provided for @registerError.
  ///
  /// In en, this message translates to:
  /// **'Could not create account: {error}'**
  String registerError(Object error);

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navInbox;

  /// No description provided for @navPriorityMatrix.
  ///
  /// In en, this message translates to:
  /// **'Priority Matrix'**
  String get navPriorityMatrix;

  /// No description provided for @navTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get navTimeline;

  /// No description provided for @navKanban.
  ///
  /// In en, this message translates to:
  /// **'Kanban'**
  String get navKanban;

  /// No description provided for @kanbanTitle.
  ///
  /// In en, this message translates to:
  /// **'Kanban'**
  String get kanbanTitle;

  /// No description provided for @kanbanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visualize your workflow and focus on what matters now.'**
  String get kanbanSubtitle;

  /// No description provided for @kanbanDefaultBacklog.
  ///
  /// In en, this message translates to:
  /// **'Backlog'**
  String get kanbanDefaultBacklog;

  /// No description provided for @kanbanDefaultTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get kanbanDefaultTodo;

  /// No description provided for @kanbanDefaultInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get kanbanDefaultInProgress;

  /// No description provided for @kanbanDefaultDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get kanbanDefaultDone;

  /// No description provided for @kanbanSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search Kanban'**
  String get kanbanSearchTooltip;

  /// No description provided for @kanbanSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tasks or projects'**
  String get kanbanSearchHint;

  /// No description provided for @kanbanHideDone.
  ///
  /// In en, this message translates to:
  /// **'Hide Done'**
  String get kanbanHideDone;

  /// No description provided for @kanbanShowDone.
  ///
  /// In en, this message translates to:
  /// **'Show Done'**
  String get kanbanShowDone;

  /// No description provided for @kanbanProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects on this board'**
  String get kanbanProjectsTitle;

  /// No description provided for @kanbanAddToStatus.
  ///
  /// In en, this message translates to:
  /// **'Add to {status}'**
  String kanbanAddToStatus(String status);

  /// No description provided for @kanbanTaskField.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get kanbanTaskField;

  /// No description provided for @kanbanProjectField.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get kanbanProjectField;

  /// No description provided for @kanbanChooseProject.
  ///
  /// In en, this message translates to:
  /// **'Choose a project.'**
  String get kanbanChooseProject;

  /// No description provided for @kanbanTaskActions.
  ///
  /// In en, this message translates to:
  /// **'Task actions'**
  String get kanbanTaskActions;

  /// No description provided for @kanbanDragTask.
  ///
  /// In en, this message translates to:
  /// **'Drag task'**
  String get kanbanDragTask;

  /// No description provided for @kanbanMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to {status}'**
  String kanbanMoveTo(String status);

  /// No description provided for @kanbanRestoreBeforeFocus.
  ///
  /// In en, this message translates to:
  /// **'Restore the task before starting Focus.'**
  String get kanbanRestoreBeforeFocus;

  /// No description provided for @kanbanCouldNotStartFocus.
  ///
  /// In en, this message translates to:
  /// **'Could not start Focus: {error}'**
  String kanbanCouldNotStartFocus(Object error);

  /// No description provided for @kanbanCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load Kanban: {error}'**
  String kanbanCouldNotLoad(Object error);

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonContinueWaiting.
  ///
  /// In en, this message translates to:
  /// **'Continue waiting'**
  String get commonContinueWaiting;

  /// No description provided for @kanbanTasksCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String kanbanTasksCount(int count);

  /// No description provided for @kanbanSubtasksProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} subtasks'**
  String kanbanSubtasksProgress(int completed, int total);

  /// No description provided for @kanbanFocusIntervalsProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} focus intervals'**
  String kanbanFocusIntervalsProgress(int completed, int total);

  /// No description provided for @kanbanActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get kanbanActive;

  /// No description provided for @kanbanPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String kanbanPriority(int priority);

  /// No description provided for @kanbanMoveAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Moved to {status}'**
  String kanbanMoveAnnouncement(String status);

  /// No description provided for @kanbanFocusStartedAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Focus started for {task}'**
  String kanbanFocusStartedAnnouncement(String task);

  /// No description provided for @kanbanNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get kanbanNoTasks;

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get navUpcoming;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @navIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get navIntegrations;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get navFocus;

  /// No description provided for @navProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get navProjects;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @csvImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import tasks from CSV'**
  String get csvImportTitle;

  /// No description provided for @csvImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review a CSV file before creating tasks, projects, labels, and workflow statuses.'**
  String get csvImportSubtitle;

  /// No description provided for @csvImportSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Choose CSV file'**
  String get csvImportSelectFile;

  /// No description provided for @csvImportHumanGuideButton.
  ///
  /// In en, this message translates to:
  /// **'Guide for people'**
  String get csvImportHumanGuideButton;

  /// No description provided for @csvImportAgentGuideButton.
  ///
  /// In en, this message translates to:
  /// **'Guide for agents'**
  String get csvImportAgentGuideButton;

  /// No description provided for @csvImportHumanGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to prepare a CSV file'**
  String get csvImportHumanGuideTitle;

  /// No description provided for @csvImportAgentGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'CSV contract for an agent'**
  String get csvImportAgentGuideTitle;

  /// No description provided for @csvImportCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get csvImportCopy;

  /// No description provided for @csvImportCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get csvImportCopied;

  /// No description provided for @csvImportPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get csvImportPreviewTitle;

  /// No description provided for @csvImportPreviewTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get csvImportPreviewTasks;

  /// No description provided for @csvImportPreviewSubtasks.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get csvImportPreviewSubtasks;

  /// No description provided for @csvImportPreviewNewProjects.
  ///
  /// In en, this message translates to:
  /// **'New projects'**
  String get csvImportPreviewNewProjects;

  /// No description provided for @csvImportPreviewNewLabels.
  ///
  /// In en, this message translates to:
  /// **'New labels'**
  String get csvImportPreviewNewLabels;

  /// No description provided for @csvImportPreviewNewStatuses.
  ///
  /// In en, this message translates to:
  /// **'New workflow statuses'**
  String get csvImportPreviewNewStatuses;

  /// No description provided for @csvImportNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get csvImportNone;

  /// No description provided for @csvImportDuplicateWarning.
  ///
  /// In en, this message translates to:
  /// **'Importing the same file again will create duplicate tasks.'**
  String get csvImportDuplicateWarning;

  /// No description provided for @csvImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get csvImportConfirm;

  /// No description provided for @csvImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Tasks imported'**
  String get csvImportSuccess;

  /// No description provided for @csvImportErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'CSV import failed'**
  String get csvImportErrorTitle;

  /// No description provided for @csvImportUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'The file could not be imported.'**
  String get csvImportUnexpectedError;

  /// No description provided for @csvImportHumanGuide.
  ///
  /// In en, this message translates to:
  /// **'1. Save the file as UTF-8 CSV. Use a comma (recommended) or semicolon as the separator.\n\n2. The content column is required. You may also use: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Put one open task on each row. Separate labels with |. Priority is 1–4; an empty value means 4. An empty project means Inbox and an empty workflow status means Backlog. Missing projects, labels, and open statuses are created automatically.\n\n4. For an all-day task, use due_date in YYYY-MM-DD format. For a timed task, fill start_at and end_at as RFC3339 values with a UTC offset and provide an IANA time_zone, for example Europe/Moscow.\n\n5. To create subtasks, give the parent row a unique key and put that value in the child\'s parent_key. Parents may appear later in the file. A child must use the same project as its parent.\n\n6. Pomodoist validates the whole file and shows a preview before importing. Nothing is saved if any row is invalid. Re-importing creates duplicate tasks.'**
  String get csvImportHumanGuide;

  /// No description provided for @settingsConnectedAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected agents'**
  String get settingsConnectedAgentsTitle;

  /// No description provided for @settingsConnectedAgentsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading connected agents…'**
  String get settingsConnectedAgentsLoading;

  /// No description provided for @settingsConnectedAgentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No agents are connected.'**
  String get settingsConnectedAgentsEmpty;

  /// No description provided for @settingsConnectedAgentsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load connected agents.'**
  String get settingsConnectedAgentsLoadError;

  /// No description provided for @settingsConnectedAgentsUnknownClient.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get settingsConnectedAgentsUnknownClient;

  /// No description provided for @settingsConnectedAgentsConnectedOn.
  ///
  /// In en, this message translates to:
  /// **'Connected on {date}'**
  String settingsConnectedAgentsConnectedOn(String date);

  /// No description provided for @settingsConnectedAgentsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get settingsConnectedAgentsRevoke;

  /// No description provided for @settingsConnectedAgentsRevokeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke agent access?'**
  String get settingsConnectedAgentsRevokeConfirmTitle;

  /// No description provided for @settingsConnectedAgentsRevokeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Revoke Pomodoist access for {clientName}?'**
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName);

  /// No description provided for @settingsConnectedAgentsRevokeError.
  ///
  /// In en, this message translates to:
  /// **'Could not revoke access. Try again.'**
  String get settingsConnectedAgentsRevokeError;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the app language.'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// No description provided for @settingsThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the app appearance.'**
  String get settingsThemeSubtitle;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsTimerVisualTitle.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro timer'**
  String get settingsTimerVisualTitle;

  /// No description provided for @settingsTimerVisualSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how progress is shown on the focus screen.'**
  String get settingsTimerVisualSubtitle;

  /// No description provided for @settingsTimerVisualBar.
  ///
  /// In en, this message translates to:
  /// **'Bar'**
  String get settingsTimerVisualBar;

  /// No description provided for @settingsTimerVisualCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get settingsTimerVisualCircle;

  /// No description provided for @settingsReturnRemindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Return reminders'**
  String get settingsReturnRemindersTitle;

  /// No description provided for @settingsReturnRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A gentle evening nudge if today has no focus or completed task.'**
  String get settingsReturnRemindersSubtitle;

  /// No description provided for @settingsDefaultTimedBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Default calendar block duration'**
  String get settingsDefaultTimedBlockTitle;

  /// No description provided for @settingsDefaultTimedBlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When only a time is entered, new tasks use this calendar duration.'**
  String get settingsDefaultTimedBlockSubtitle;

  /// No description provided for @settingsDefaultTimedBlockCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom duration'**
  String get settingsDefaultTimedBlockCustomLabel;

  /// No description provided for @settingsDefaultTimedBlockError.
  ///
  /// In en, this message translates to:
  /// **'Enter 1 to 480 minutes.'**
  String get settingsDefaultTimedBlockError;

  /// No description provided for @menuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTooltip;

  /// No description provided for @localUser.
  ///
  /// In en, this message translates to:
  /// **'Local User'**
  String get localUser;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @quickAddHint.
  ///
  /// In en, this message translates to:
  /// **'Write sync engine tomorrow p1 #App @coding 4p'**
  String get quickAddHint;

  /// No description provided for @couldNotAddTask.
  ///
  /// In en, this message translates to:
  /// **'Could not add task: {error}'**
  String couldNotAddTask(Object error);

  /// No description provided for @couldNotAddProject.
  ///
  /// In en, this message translates to:
  /// **'Could not add project: {error}'**
  String couldNotAddProject(Object error);

  /// No description provided for @tasksCreated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 task} other{Added {count} tasks}}'**
  String tasksCreated(int count);

  /// No description provided for @voiceQuickAdd.
  ///
  /// In en, this message translates to:
  /// **'Voice quick add'**
  String get voiceQuickAdd;

  /// No description provided for @voiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice add'**
  String get voiceTitle;

  /// No description provided for @voiceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get voiceRecord;

  /// No description provided for @voiceAgain.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get voiceAgain;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count}'**
  String voiceAddCount(int count);

  /// No description provided for @voiceTaskLabel.
  ///
  /// In en, this message translates to:
  /// **'Task {index}'**
  String voiceTaskLabel(int index);

  /// No description provided for @voiceRemoveTask.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get voiceRemoveTask;

  /// No description provided for @voiceInstruction.
  ///
  /// In en, this message translates to:
  /// **'Tap record and dictate tasks.'**
  String get voiceInstruction;

  /// No description provided for @voiceStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Built-in microphone input only'**
  String get voiceStatusIdle;

  /// No description provided for @voiceStatusRequestingPermission.
  ///
  /// In en, this message translates to:
  /// **'Requesting access'**
  String get voiceStatusRequestingPermission;

  /// No description provided for @voiceStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Listening to the built-in microphone'**
  String get voiceStatusRecording;

  /// No description provided for @voiceStatusTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing recording'**
  String get voiceStatusTranscribing;

  /// No description provided for @voiceStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Recording canceled'**
  String get voiceStatusCanceled;

  /// No description provided for @voiceStatusUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Platform is not supported'**
  String get voiceStatusUnsupported;

  /// No description provided for @voiceStatusError.
  ///
  /// In en, this message translates to:
  /// **'Could not recognize speech'**
  String get voiceStatusError;

  /// No description provided for @voiceStatusAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Splitting into tasks'**
  String get voiceStatusAnalyzing;

  /// No description provided for @voiceStatusReview.
  ///
  /// In en, this message translates to:
  /// **'Review tasks before adding'**
  String get voiceStatusReview;

  /// No description provided for @voiceStepRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get voiceStepRecord;

  /// No description provided for @voiceStepText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get voiceStepText;

  /// No description provided for @voiceStepAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get voiceStepAnalyze;

  /// No description provided for @voiceStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get voiceStepReview;

  /// No description provided for @voiceAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist is splitting speech into tasks'**
  String get voiceAnalyzing;

  /// No description provided for @voiceFallbackError.
  ///
  /// In en, this message translates to:
  /// **'Pomodoist could not process speech; kept a draft for manual editing.'**
  String get voiceFallbackError;

  /// No description provided for @voiceSmartMode.
  ///
  /// In en, this message translates to:
  /// **'Smart mode'**
  String get voiceSmartMode;

  /// No description provided for @voiceRetryAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Retry analysis'**
  String get voiceRetryAnalysis;

  /// No description provided for @screenInboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture tasks before organizing them.'**
  String get screenInboxSubtitle;

  /// No description provided for @priorityMatrixSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag tasks between priorities. Dates only sort tasks inside a priority.'**
  String get priorityMatrixSubtitle;

  /// No description provided for @priorityMatrixP1Title.
  ///
  /// In en, this message translates to:
  /// **'Do now'**
  String get priorityMatrixP1Title;

  /// No description provided for @priorityMatrixP2Title.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get priorityMatrixP2Title;

  /// No description provided for @priorityMatrixP3Title.
  ///
  /// In en, this message translates to:
  /// **'Delegate'**
  String get priorityMatrixP3Title;

  /// No description provided for @priorityMatrixP4Title.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get priorityMatrixP4Title;

  /// No description provided for @priorityMatrixAxisUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get priorityMatrixAxisUrgent;

  /// No description provided for @priorityMatrixAxisNotUrgent.
  ///
  /// In en, this message translates to:
  /// **'Not urgent'**
  String get priorityMatrixAxisNotUrgent;

  /// No description provided for @priorityMatrixAxisImportant.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get priorityMatrixAxisImportant;

  /// No description provided for @priorityMatrixAxisNotImportant.
  ///
  /// In en, this message translates to:
  /// **'Not important'**
  String get priorityMatrixAxisNotImportant;

  /// No description provided for @timelineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plan one day on a time grid.'**
  String get timelineSubtitle;

  /// No description provided for @timelineAllDay.
  ///
  /// In en, this message translates to:
  /// **'All-day'**
  String get timelineAllDay;

  /// No description provided for @timelineBeforeHours.
  ///
  /// In en, this message translates to:
  /// **'Before visible hours'**
  String get timelineBeforeHours;

  /// No description provided for @timelineAfterHours.
  ///
  /// In en, this message translates to:
  /// **'After visible hours'**
  String get timelineAfterHours;

  /// No description provided for @timelineVisibleHours.
  ///
  /// In en, this message translates to:
  /// **'Visible hours'**
  String get timelineVisibleHours;

  /// No description provided for @timelineStartHour.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get timelineStartHour;

  /// No description provided for @timelineEndHour.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get timelineEndHour;

  /// No description provided for @timelineZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get timelineZoomOut;

  /// No description provided for @timelineZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get timelineZoomIn;

  /// No description provided for @timelineAddTimedHint.
  ///
  /// In en, this message translates to:
  /// **'Task for {time}'**
  String timelineAddTimedHint(String time);

  /// No description provided for @timelineAddAllDayHint.
  ///
  /// In en, this message translates to:
  /// **'All-day task'**
  String get timelineAddAllDayHint;

  /// No description provided for @timelineNoAllDayTasks.
  ///
  /// In en, this message translates to:
  /// **'No all-day tasks'**
  String get timelineNoAllDayTasks;

  /// No description provided for @timelineNoTimedTasks.
  ///
  /// In en, this message translates to:
  /// **'No timed tasks'**
  String get timelineNoTimedTasks;

  /// No description provided for @timelinePreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get timelinePreviousDay;

  /// No description provided for @timelineNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get timelineNextDay;

  /// No description provided for @timelinePickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick date'**
  String get timelinePickDate;

  /// No description provided for @upcomingPreviousPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get upcomingPreviousPeriod;

  /// No description provided for @upcomingNextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get upcomingNextPeriod;

  /// No description provided for @upcomingOpenDatePicker.
  ///
  /// In en, this message translates to:
  /// **'Open date picker'**
  String get upcomingOpenDatePicker;

  /// No description provided for @upcomingTaskCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tasks} =1{1 task} other{{count} tasks}}'**
  String upcomingTaskCount(int count);

  /// No description provided for @screenTodayFocusSummary.
  ///
  /// In en, this message translates to:
  /// **'Focus load: {planned} intervals - Done: {completed} - Focus: {focus}'**
  String screenTodayFocusSummary(int planned, int completed, String focus);

  /// No description provided for @screenUpcomingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Planned tasks after today.'**
  String get screenUpcomingSubtitle;

  /// No description provided for @screenUpcomingSelectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks scheduled for {date}.'**
  String screenUpcomingSelectedSubtitle(String date);

  /// No description provided for @noTasksHere.
  ///
  /// In en, this message translates to:
  /// **'No tasks here'**
  String get noTasksHere;

  /// No description provided for @noUpcomingTasks.
  ///
  /// In en, this message translates to:
  /// **'No dated tasks'**
  String get noUpcomingTasks;

  /// No description provided for @noTasksForDay.
  ///
  /// In en, this message translates to:
  /// **'No tasks scheduled for this day'**
  String get noTasksForDay;

  /// No description provided for @failedToLoadTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tasks: {error}'**
  String failedToLoadTasks(Object error);

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get searchTasks;

  /// No description provided for @searchStartTyping.
  ///
  /// In en, this message translates to:
  /// **'Start typing to search tasks'**
  String get searchStartTyping;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching tasks'**
  String get searchNoMatches;

  /// No description provided for @failedToSearchTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed to search tasks: {error}'**
  String failedToSearchTasks(Object error);

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @clearDateFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear date filter'**
  String get clearDateFilter;

  /// No description provided for @weekMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekMon;

  /// No description provided for @weekTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekTue;

  /// No description provided for @weekWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekWed;

  /// No description provided for @weekThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekThu;

  /// No description provided for @weekFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekFri;

  /// No description provided for @weekSat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekSat;

  /// No description provided for @weekSun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekSun;

  /// No description provided for @browseTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browseTitle;

  /// No description provided for @unifiedAccount.
  ///
  /// In en, this message translates to:
  /// **'Unified Account'**
  String get unifiedAccount;

  /// No description provided for @accountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Account unavailable: {error}'**
  String accountUnavailable(Object error);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, cloud data, and local tasks, projects, and focus history. This cannot be undone. Store subscriptions are not canceled automatically. If you used Sign in with Apple, revoke Pomodoist access separately in your Apple Account settings.'**
  String get deleteAccountConfirmation;

  /// No description provided for @manageSignInWithApple.
  ///
  /// In en, this message translates to:
  /// **'Manage Sign in with Apple'**
  String get manageSignInWithApple;

  /// No description provided for @deleteAccountFinalConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you absolutely sure? This is your final confirmation.'**
  String get deleteAccountFinalConfirmation;

  /// No description provided for @deleteAccountError.
  ///
  /// In en, this message translates to:
  /// **'Could not delete account: {error}'**
  String deleteAccountError(Object error);

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get accountDeleted;

  /// No description provided for @accountDeletedLocalCleanupError.
  ///
  /// In en, this message translates to:
  /// **'Your account was deleted, but local data could not be cleared. Clear the app\'s data before using this device again.'**
  String get accountDeletedLocalCleanupError;

  /// No description provided for @productivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Productivity'**
  String get productivityTitle;

  /// No description provided for @achievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievementsTitle;

  /// No description provided for @allTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTimeLabel;

  /// No description provided for @lastSevenDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get lastSevenDaysLabel;

  /// No description provided for @noWeeklyStatsLabel.
  ///
  /// In en, this message translates to:
  /// **'No focus or task data yet'**
  String get noWeeklyStatsLabel;

  /// No description provided for @completedFocuses.
  ///
  /// In en, this message translates to:
  /// **'Completed focuses'**
  String get completedFocuses;

  /// No description provided for @completedTasks.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks'**
  String get completedTasks;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlocked;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @progressLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressLabel;

  /// No description provided for @focusAchievements.
  ///
  /// In en, this message translates to:
  /// **'Focus achievements'**
  String get focusAchievements;

  /// No description provided for @taskAchievements.
  ///
  /// In en, this message translates to:
  /// **'Task achievements'**
  String get taskAchievements;

  /// No description provided for @comboAchievements.
  ///
  /// In en, this message translates to:
  /// **'Combo achievements'**
  String get comboAchievements;

  /// No description provided for @focusIntervals.
  ///
  /// In en, this message translates to:
  /// **'Focus intervals'**
  String get focusIntervals;

  /// No description provided for @focusTime.
  ///
  /// In en, this message translates to:
  /// **'Focus time'**
  String get focusTime;

  /// No description provided for @openTasks.
  ///
  /// In en, this message translates to:
  /// **'Open tasks'**
  String get openTasks;

  /// No description provided for @plannedIntervals.
  ///
  /// In en, this message translates to:
  /// **'Planned intervals'**
  String get plannedIntervals;

  /// No description provided for @labelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labelsTitle;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New label'**
  String get newLabel;

  /// No description provided for @syncReadyQueue.
  ///
  /// In en, this message translates to:
  /// **'Sync-ready queue'**
  String get syncReadyQueue;

  /// No description provided for @pendingLocalCommands.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pending local commands} =1{1 pending local command} other{{count} pending local commands}}'**
  String pendingLocalCommands(int count);

  /// No description provided for @failedToLoadProjects.
  ///
  /// In en, this message translates to:
  /// **'Failed to load projects: {error}'**
  String failedToLoadProjects(Object error);

  /// No description provided for @failedToLoadLabels.
  ///
  /// In en, this message translates to:
  /// **'Failed to load labels: {error}'**
  String failedToLoadLabels(Object error);

  /// No description provided for @addProject.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get addProject;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'Add label'**
  String get addLabel;

  /// No description provided for @labelName.
  ///
  /// In en, this message translates to:
  /// **'Label name'**
  String get labelName;

  /// No description provided for @couldNotAddLabel.
  ///
  /// In en, this message translates to:
  /// **'Could not add label: {error}'**
  String couldNotAddLabel(Object error);

  /// No description provided for @projectsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Projects unavailable: {error}'**
  String projectsUnavailable(Object error);

  /// No description provided for @projectsUnavailableShort.
  ///
  /// In en, this message translates to:
  /// **'Projects unavailable'**
  String get projectsUnavailableShort;

  /// No description provided for @noProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects'**
  String get noProjects;

  /// No description provided for @searchProjects.
  ///
  /// In en, this message translates to:
  /// **'Search projects'**
  String get searchProjects;

  /// No description provided for @searchLabels.
  ///
  /// In en, this message translates to:
  /// **'Search labels'**
  String get searchLabels;

  /// No description provided for @archivedProjectsOnly.
  ///
  /// In en, this message translates to:
  /// **'Archived projects only'**
  String get archivedProjectsOnly;

  /// No description provided for @projectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 project} other{{count} projects}}'**
  String projectsCount(int count);

  /// No description provided for @noLabels.
  ///
  /// In en, this message translates to:
  /// **'No labels'**
  String get noLabels;

  /// No description provided for @labelsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 label} other{{count} labels}}'**
  String labelsCount(int count);

  /// No description provided for @renameProject.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get renameProject;

  /// No description provided for @deleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProject;

  /// No description provided for @deleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete label'**
  String get deleteLabel;

  /// No description provided for @deleteProjectConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Tasks in this project will move to Inbox.'**
  String deleteProjectConfirmation(String name);

  /// No description provided for @deleteLabelConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteLabelConfirmation(String name);

  /// No description provided for @couldNotDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Could not delete project: {error}'**
  String couldNotDeleteProject(Object error);

  /// No description provided for @couldNotDeleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Could not delete label: {error}'**
  String couldNotDeleteLabel(Object error);

  /// No description provided for @projectsCountCompact.
  ///
  /// In en, this message translates to:
  /// **'Projects: {count}'**
  String projectsCountCompact(int count);

  /// No description provided for @collapseProjects.
  ///
  /// In en, this message translates to:
  /// **'Collapse projects'**
  String get collapseProjects;

  /// No description provided for @expandProjects.
  ///
  /// In en, this message translates to:
  /// **'Expand projects'**
  String get expandProjects;

  /// No description provided for @projectFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectFallbackTitle;

  /// No description provided for @projectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'List view - board and calendar are roadmap items.'**
  String get projectSubtitle;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @reportsFocusedDay.
  ///
  /// In en, this message translates to:
  /// **'A focused day so far'**
  String get reportsFocusedDay;

  /// No description provided for @reportsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Your week in focus'**
  String get reportsThisWeek;

  /// No description provided for @reportsNextAchievement.
  ///
  /// In en, this message translates to:
  /// **'Next achievement'**
  String get reportsNextAchievement;

  /// No description provided for @viewAllAchievements.
  ///
  /// In en, this message translates to:
  /// **'View all achievements'**
  String get viewAllAchievements;

  /// No description provided for @viewAllAchievementsCount.
  ///
  /// In en, this message translates to:
  /// **'View all {count}'**
  String viewAllAchievementsCount(int count);

  /// No description provided for @allAchievementsUnlocked.
  ///
  /// In en, this message translates to:
  /// **'All achievements unlocked'**
  String get allAchievementsUnlocked;

  /// No description provided for @noAchievementsYet.
  ///
  /// In en, this message translates to:
  /// **'No achievements yet'**
  String get noAchievementsYet;

  /// No description provided for @failedToLoadAchievements.
  ///
  /// In en, this message translates to:
  /// **'Failed to load achievements: {error}'**
  String failedToLoadAchievements(Object error);

  /// No description provided for @backToReports.
  ///
  /// In en, this message translates to:
  /// **'Back to reports'**
  String get backToReports;

  /// No description provided for @reportsIntervalProgressSemantics.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {target} focus intervals completed'**
  String reportsIntervalProgressSemantics(int completed, int target);

  /// No description provided for @reportsIntervalCountSemantics.
  ///
  /// In en, this message translates to:
  /// **'{completed} focus intervals completed; no goal set'**
  String reportsIntervalCountSemantics(int completed);

  /// No description provided for @reportsWeeklyChartSemantics.
  ///
  /// In en, this message translates to:
  /// **'Focus time for the last 7 days: {summary}'**
  String reportsWeeklyChartSemantics(String summary);

  /// No description provided for @failedToLoadReports.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reports: {error}'**
  String failedToLoadReports(Object error);

  /// No description provided for @taskNotFound.
  ///
  /// In en, this message translates to:
  /// **'Task not found'**
  String get taskNotFound;

  /// No description provided for @taskTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Task title'**
  String get taskTitleHint;

  /// No description provided for @taskComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get taskComment;

  /// No description provided for @taskCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Add a comment'**
  String get taskCommentHint;

  /// No description provided for @subtasks.
  ///
  /// In en, this message translates to:
  /// **'Sub-tasks'**
  String get subtasks;

  /// No description provided for @addSubtask.
  ///
  /// In en, this message translates to:
  /// **'Add sub-task'**
  String get addSubtask;

  /// No description provided for @addSubtaskHint.
  ///
  /// In en, this message translates to:
  /// **'Add a sub-task'**
  String get addSubtaskHint;

  /// No description provided for @noSubtasks.
  ///
  /// In en, this message translates to:
  /// **'No sub-tasks yet.'**
  String get noSubtasks;

  /// No description provided for @makeParentTask.
  ///
  /// In en, this message translates to:
  /// **'Make parent task'**
  String get makeParentTask;

  /// No description provided for @couldNotMoveTask.
  ///
  /// In en, this message translates to:
  /// **'Could not move task: {error}'**
  String couldNotMoveTask(Object error);

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleTitle;

  /// No description provided for @allDay.
  ///
  /// In en, this message translates to:
  /// **'All-day'**
  String get allDay;

  /// No description provided for @timedBlock.
  ///
  /// In en, this message translates to:
  /// **'Timed block'**
  String get timedBlock;

  /// No description provided for @recurrenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get recurrenceTitle;

  /// No description provided for @recurrenceNeedsSchedule.
  ///
  /// In en, this message translates to:
  /// **'Add a date or time before repeating.'**
  String get recurrenceNeedsSchedule;

  /// No description provided for @recurrenceIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get recurrenceIntervalLabel;

  /// No description provided for @recurrenceUnitDay.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get recurrenceUnitDay;

  /// No description provided for @recurrenceUnitWeek.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get recurrenceUnitWeek;

  /// No description provided for @recurrenceUnitMonth.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get recurrenceUnitMonth;

  /// No description provided for @recurrenceInvalidInterval.
  ///
  /// In en, this message translates to:
  /// **'Enter 1 to 999.'**
  String get recurrenceInvalidInterval;

  /// No description provided for @recurrenceEveryDays.
  ///
  /// In en, this message translates to:
  /// **'{interval, plural, =1{every day} other{every {interval} days}}'**
  String recurrenceEveryDays(int interval);

  /// No description provided for @recurrenceEveryWeeks.
  ///
  /// In en, this message translates to:
  /// **'{interval, plural, =1{every week} other{every {interval} weeks}}'**
  String recurrenceEveryWeeks(int interval);

  /// No description provided for @recurrenceEveryMonths.
  ///
  /// In en, this message translates to:
  /// **'{interval, plural, =1{every month} other{every {interval} months}}'**
  String recurrenceEveryMonths(int interval);

  /// No description provided for @noDate.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get noDate;

  /// No description provided for @calendarNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Calendar not linked'**
  String get calendarNotLinked;

  /// No description provided for @calendarLinked.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar linked'**
  String get calendarLinked;

  /// No description provided for @focusProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} focus'**
  String focusProgress(int completed, int total);

  /// No description provided for @startFocus.
  ///
  /// In en, this message translates to:
  /// **'Start focus'**
  String get startFocus;

  /// No description provided for @focusStarted.
  ///
  /// In en, this message translates to:
  /// **'Focus started'**
  String get focusStarted;

  /// No description provided for @taskReopened.
  ///
  /// In en, this message translates to:
  /// **'Task reopened'**
  String get taskReopened;

  /// No description provided for @taskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Task completed'**
  String get taskCompleted;

  /// No description provided for @taskDeleted.
  ///
  /// In en, this message translates to:
  /// **'Task deleted'**
  String get taskDeleted;

  /// No description provided for @recurringDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recurring task?'**
  String get recurringDeleteTitle;

  /// No description provided for @recurringDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This task belongs to a recurring series.'**
  String get recurringDeleteMessage;

  /// No description provided for @recurringDeleteThis.
  ///
  /// In en, this message translates to:
  /// **'Delete this task'**
  String get recurringDeleteThis;

  /// No description provided for @recurringDeleteThisAndFollowing.
  ///
  /// In en, this message translates to:
  /// **'Delete this and following'**
  String get recurringDeleteThisAndFollowing;

  /// No description provided for @markOpen.
  ///
  /// In en, this message translates to:
  /// **'Mark open'**
  String get markOpen;

  /// No description provided for @markComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get markComplete;

  /// No description provided for @focusHistory.
  ///
  /// In en, this message translates to:
  /// **'Focus history'**
  String get focusHistory;

  /// No description provided for @failedToLoadTask.
  ///
  /// In en, this message translates to:
  /// **'Failed to load task: {error}'**
  String failedToLoadTask(Object error);

  /// No description provided for @noFocusIntervals.
  ///
  /// In en, this message translates to:
  /// **'No focus intervals yet.'**
  String get noFocusIntervals;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearDate;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String priority(int priority);

  /// No description provided for @focusTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusTitle;

  /// No description provided for @focusLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load focus: {error}'**
  String focusLoadError(Object error);

  /// No description provided for @focusViewFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get focusViewFull;

  /// No description provided for @focusViewMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get focusViewMinimal;

  /// No description provided for @noActiveSession.
  ///
  /// In en, this message translates to:
  /// **'No active session'**
  String get noActiveSession;

  /// No description provided for @focusIdleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a standalone focus interval or launch focus from a task.'**
  String get focusIdleSubtitle;

  /// No description provided for @noPreset.
  ///
  /// In en, this message translates to:
  /// **'No preset'**
  String get noPreset;

  /// No description provided for @preparingFocus.
  ///
  /// In en, this message translates to:
  /// **'Preparing focus'**
  String get preparingFocus;

  /// No description provided for @moreFocusOptions.
  ///
  /// In en, this message translates to:
  /// **'More focus options'**
  String get moreFocusOptions;

  /// No description provided for @moreFocusActions.
  ///
  /// In en, this message translates to:
  /// **'More focus actions'**
  String get moreFocusActions;

  /// No description provided for @preset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get preset;

  /// No description provided for @newPreset.
  ///
  /// In en, this message translates to:
  /// **'New preset'**
  String get newPreset;

  /// No description provided for @customize.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get customize;

  /// No description provided for @customizePreset.
  ///
  /// In en, this message translates to:
  /// **'Customize preset'**
  String get customizePreset;

  /// No description provided for @startInterval.
  ///
  /// In en, this message translates to:
  /// **'Start interval'**
  String get startInterval;

  /// No description provided for @intervalStarted.
  ///
  /// In en, this message translates to:
  /// **'Interval started'**
  String get intervalStarted;

  /// No description provided for @intervalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Interval completed'**
  String get intervalCompleted;

  /// No description provided for @focusStopped.
  ///
  /// In en, this message translates to:
  /// **'Focus stopped'**
  String get focusStopped;

  /// No description provided for @completeInterval.
  ///
  /// In en, this message translates to:
  /// **'Complete interval'**
  String get completeInterval;

  /// No description provided for @logDistraction.
  ///
  /// In en, this message translates to:
  /// **'Log distraction'**
  String get logDistraction;

  /// No description provided for @workInterval.
  ///
  /// In en, this message translates to:
  /// **'Work interval'**
  String get workInterval;

  /// No description provided for @work.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get work;

  /// No description provided for @shortBreak.
  ///
  /// In en, this message translates to:
  /// **'Short break'**
  String get shortBreak;

  /// No description provided for @breakLabel.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get breakLabel;

  /// No description provided for @longBreak.
  ///
  /// In en, this message translates to:
  /// **'Long break'**
  String get longBreak;

  /// No description provided for @readyLabel.
  ///
  /// In en, this message translates to:
  /// **'Ready: {label}'**
  String readyLabel(String label);

  /// No description provided for @readyShort.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get readyShort;

  /// No description provided for @focusTimerTotal.
  ///
  /// In en, this message translates to:
  /// **'of {duration}'**
  String focusTimerTotal(String duration);

  /// No description provided for @focusSessionProgress.
  ///
  /// In en, this message translates to:
  /// **'Session {current} of {total}'**
  String focusSessionProgress(int current, int total);

  /// No description provided for @focusRhythmPreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'Focus rhythm preview, {count} steps'**
  String focusRhythmPreviewSummary(int count);

  /// No description provided for @focusRhythmSummary.
  ///
  /// In en, this message translates to:
  /// **'Focus rhythm, step {current} of {total}: {phase}, {status}'**
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  );

  /// No description provided for @focusTimerSummary.
  ///
  /// In en, this message translates to:
  /// **'{phase}, {status}, {remaining} remaining, {total} total'**
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  );

  /// No description provided for @focusStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get focusStatusRunning;

  /// No description provided for @focusStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get focusStatusPaused;

  /// No description provided for @focusWorkProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} work'**
  String focusWorkProgress(int completed, int total);

  /// No description provided for @intervalNumber.
  ///
  /// In en, this message translates to:
  /// **'Interval {number}'**
  String intervalNumber(int number);

  /// No description provided for @focusIntervalSummary.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} work - Interval {number}'**
  String focusIntervalSummary(int completed, int total, int number);

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @presetForNextIntervals.
  ///
  /// In en, this message translates to:
  /// **'Preset for next intervals'**
  String get presetForNextIntervals;

  /// No description provided for @usePreset.
  ///
  /// In en, this message translates to:
  /// **'Use {name}'**
  String usePreset(String name);

  /// No description provided for @minutesWork.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m work'**
  String minutesWork(int minutes);

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m short'**
  String minutesShort(int minutes);

  /// No description provided for @minutesLong.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m long'**
  String minutesLong(int minutes);

  /// No description provided for @longEvery.
  ///
  /// In en, this message translates to:
  /// **'Long every {count}'**
  String longEvery(int count);

  /// No description provided for @autoBreaks.
  ///
  /// In en, this message translates to:
  /// **'Auto breaks'**
  String get autoBreaks;

  /// No description provided for @autoWork.
  ///
  /// In en, this message translates to:
  /// **'Auto work'**
  String get autoWork;

  /// No description provided for @noPause.
  ///
  /// In en, this message translates to:
  /// **'No pause'**
  String get noPause;

  /// No description provided for @focusPauseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Pause unavailable for this preset'**
  String get focusPauseUnavailable;

  /// No description provided for @strict.
  ///
  /// In en, this message translates to:
  /// **'Strict'**
  String get strict;

  /// No description provided for @flexible.
  ///
  /// In en, this message translates to:
  /// **'Flexible'**
  String get flexible;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @workField.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get workField;

  /// No description provided for @shortField.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get shortField;

  /// No description provided for @longField.
  ///
  /// In en, this message translates to:
  /// **'Long'**
  String get longField;

  /// No description provided for @every.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get every;

  /// No description provided for @minutesSuffix.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesSuffix;

  /// No description provided for @makeDefault.
  ///
  /// In en, this message translates to:
  /// **'Make default'**
  String get makeDefault;

  /// No description provided for @autoStartBreaks.
  ///
  /// In en, this message translates to:
  /// **'Auto-start breaks'**
  String get autoStartBreaks;

  /// No description provided for @autoStartWork.
  ///
  /// In en, this message translates to:
  /// **'Auto-start work'**
  String get autoStartWork;

  /// No description provided for @allowPause.
  ///
  /// In en, this message translates to:
  /// **'Allow pause'**
  String get allowPause;

  /// No description provided for @strictMode.
  ///
  /// In en, this message translates to:
  /// **'Strict mode'**
  String get strictMode;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @nameMustBeUnique.
  ///
  /// In en, this message translates to:
  /// **'Name must be unique'**
  String get nameMustBeUnique;

  /// No description provided for @googleCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar'**
  String get googleCalendarTitle;

  /// No description provided for @googleCalendarConnectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two-way sync is active for the Pomodoist calendar.'**
  String get googleCalendarConnectedSubtitle;

  /// No description provided for @googleCalendarDisconnectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a Google account to sync scheduled tasks.'**
  String get googleCalendarDisconnectedSubtitle;

  /// No description provided for @googleCalendarConnectedOnAnotherDeviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar sync is running on another device. Pomodoist data still syncs here.'**
  String get googleCalendarConnectedOnAnotherDeviceSubtitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @useThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Use this device'**
  String get useThisDevice;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @failedToLoadIntegration.
  ///
  /// In en, this message translates to:
  /// **'Failed to load integration: {error}'**
  String failedToLoadIntegration(Object error);

  /// No description provided for @googleCalendarFailed.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar failed: {message}'**
  String googleCalendarFailed(String message);

  /// No description provided for @googleAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar authorization is required. Sign in again and run Sync now.'**
  String get googleAuthRequired;

  /// No description provided for @googleSignInNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_REVERSED_CLIENT_ID for this iOS target.'**
  String get googleSignInNotConfigured;

  /// No description provided for @googleCallbackNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In callback is not configured. Set GOOGLE_REVERSED_CLIENT_ID in ios/Flutter/GoogleOAuth.xcconfig.'**
  String get googleCallbackNotConfigured;

  /// No description provided for @googleWebButtonFirst.
  ///
  /// In en, this message translates to:
  /// **'On web, click the Google sign-in button first, then Connect.'**
  String get googleWebButtonFirst;

  /// No description provided for @googleAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Google access is denied. Add this Google account as an OAuth test user, or publish and verify the OAuth app.'**
  String get googleAccessDenied;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @calendarId.
  ///
  /// In en, this message translates to:
  /// **'Calendar ID'**
  String get calendarId;

  /// No description provided for @lastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get lastSync;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @notCreated.
  ///
  /// In en, this message translates to:
  /// **'Not created'**
  String get notCreated;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String durationMinutes(int minutes);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @projectColor.
  ///
  /// In en, this message translates to:
  /// **'Project color'**
  String get projectColor;

  /// No description provided for @projectColorOption.
  ///
  /// In en, this message translates to:
  /// **'Color {number}'**
  String projectColorOption(int number);

  /// No description provided for @addProjectToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add project to favorites'**
  String get addProjectToFavorites;

  /// No description provided for @removeProjectFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove project from favorites'**
  String get removeProjectFromFavorites;

  /// No description provided for @timelineProjectsMenu.
  ///
  /// In en, this message translates to:
  /// **'Manage Timeline projects'**
  String get timelineProjectsMenu;

  /// No description provided for @timelineShowProject.
  ///
  /// In en, this message translates to:
  /// **'Show project in Timeline'**
  String get timelineShowProject;

  /// No description provided for @timelineHideProject.
  ///
  /// In en, this message translates to:
  /// **'Hide temporary project'**
  String get timelineHideProject;

  /// No description provided for @timelineCollapseProject.
  ///
  /// In en, this message translates to:
  /// **'Collapse project branch'**
  String get timelineCollapseProject;

  /// No description provided for @timelineExpandProject.
  ///
  /// In en, this message translates to:
  /// **'Expand project branch'**
  String get timelineExpandProject;

  /// No description provided for @timelineCurrentTime.
  ///
  /// In en, this message translates to:
  /// **'Current time'**
  String get timelineCurrentTime;

  /// No description provided for @couldNotUpdateProject.
  ///
  /// In en, this message translates to:
  /// **'Could not update project: {error}'**
  String couldNotUpdateProject(Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'ru',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

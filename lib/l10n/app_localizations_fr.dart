// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonUndo => 'Annuler';

  @override
  String get commonOpen => 'Ouvrir';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonCreate => 'Créer';

  @override
  String get commonClear => 'Effacer';

  @override
  String get commonStop => 'Arrêter';

  @override
  String get skip => 'Ignorer';

  @override
  String get onboardingLanguageTitle => 'Choisir la langue';

  @override
  String get onboardingLanguageSubtitle =>
      'Choisissez la langue que Pomodoist doit utiliser.';

  @override
  String get onboardingTimerTitle => 'Choisir le style du minuteur';

  @override
  String get onboardingTimerSubtitle =>
      'Choisissez l\'affichage de progression Pomodoro pour les sessions de focus.';

  @override
  String get onboardingPaywallTitle => 'Débloquer Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'L’offre à vie est disponible pendant 24 heures chaque semaine.';

  @override
  String get onboardingAccountTitle => 'Créer un compte';

  @override
  String get onboardingAccountSubtitle =>
      'Connectez-vous pour synchroniser tâches, historique de focus et réglages entre vos appareils.';

  @override
  String get startupPreparingTasks => 'Préparation de vos tâches';

  @override
  String get operationTakingLonger =>
      'L’opération prend plus de temps que prévu, mais elle est toujours en cours.';

  @override
  String get onboardingContinue => 'Continuer';

  @override
  String get onboardingMaybeLater => 'Peut-être plus tard';

  @override
  String get onboardingFinish => 'Terminer';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Dictez vos tâches en langage naturel et Pomodoist transforme vos mots en tâches. L\'historique des tâches est conservé pour toujours.';

  @override
  String get billingSubtitleHighlight => 'langage naturel';

  @override
  String get billingCancelAnytime => 'Annulez à tout moment.';

  @override
  String get billingMonthlyTitle => 'Mensuel';

  @override
  String get billingAnnualTitle => 'Annuel';

  @override
  String billingPricePerMonth(String price) {
    return '$price/mois';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/an';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'Les 3 premiers mois, puis $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Puis $price.';
  }

  @override
  String get billingLifetimeTitle => 'À vie';

  @override
  String get billingLifetimeSubtitle => 'Un paiement pour toujours.';

  @override
  String get billingBestValue => 'Meilleur prix';

  @override
  String get billingChoose => 'Choisir';

  @override
  String get billingActive => 'Pomodoist Pro est actif sur cet appareil.';

  @override
  String get billingActiveShort => 'Actif';

  @override
  String get billingRestore => 'Restaurer les achats';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get termsOfUse => 'Conditions d’utilisation';

  @override
  String get billingManageLink => 'Gérer via Link';

  @override
  String get billingExternalBrowserTitle =>
      'Le paiement s’ouvrira dans le navigateur';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist ouvrira Stripe Checkout dans Safari ou votre navigateur par défaut. Autorisez l’ouverture de la fenêtre pour continuer.';

  @override
  String get billingAppleOnly =>
      'Les achats sont disponibles sur iPhone, iPad et Mac.';

  @override
  String get billingStoreUnavailable =>
      'L\'App Store n\'est pas disponible pour le moment.';

  @override
  String billingPurchaseError(String error) {
    return 'Erreur d\'achat : $error';
  }

  @override
  String get purchaseSuccessTitle => 'Pro est actif';

  @override
  String get purchaseSuccessMessage =>
      'Merci de soutenir Pomodoist. Toutes les fonctionnalités Pro sont déjà disponibles.';

  @override
  String get purchaseSuccessContinue => 'Continuer';

  @override
  String get purchaseProcessingTitle => 'Paiement en cours';

  @override
  String get purchaseProcessingMessage =>
      'Le paiement est en cours de confirmation. Si Pro n’apparaît pas bientôt, actualisez plus tard.';

  @override
  String get purchaseOpenApp => 'Ouvrir Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return 'L’offre à vie se termine dans $time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'Email';

  @override
  String get loginTitle => 'Se connecter à Pomodoist';

  @override
  String get accountChecking => 'Vérification de votre compte';

  @override
  String get oauthConsentTitle => 'Connecter un agent';

  @override
  String get oauthConsentLoading => 'Vérification de la demande de connexion';

  @override
  String get oauthConsentInvalidAuthorization =>
      'Cette demande de connexion est absente ou invalide.';

  @override
  String get oauthConsentLoadError =>
      'Impossible de charger la demande de connexion.';

  @override
  String get oauthConsentActionError =>
      'Impossible de terminer la demande. Réessayez.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist a reçu une adresse de retour absente ou non sécurisée. L’accès n’a pas été transmis.';

  @override
  String get oauthConsentClientFallback => 'Agent';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName souhaite accéder à Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Adresse de retour';

  @override
  String get oauthConsentCapabilitiesTitle => 'Cet agent peut';

  @override
  String get oauthConsentManagePlanning =>
      'Lire et gérer les tâches, projets, libellés personnels et Kanban.';

  @override
  String get oauthConsentReadInsights =>
      'Lire l’historique de focus terminé, les rapports de productivité et les succès.';

  @override
  String get oauthConsentUnavailableTitle => 'Cet agent ne peut pas';

  @override
  String get oauthConsentUnavailable =>
      'Accéder à votre compte ou facturation, Google Agenda ou au minuteur de focus actif.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'Cette demande exige un accès au compte non pris en charge et ne peut pas être approuvée.';

  @override
  String get oauthConsentApprove => 'Autoriser';

  @override
  String get oauthConsentDeny => 'Refuser';

  @override
  String get oauthConsentApproving => 'Autorisation de l’accès…';

  @override
  String get oauthConsentDenying => 'Refus de la demande…';

  @override
  String get oauthConsentRedirecting => 'Retour vers l’agent…';

  @override
  String get loginCreateAccountPrompt => 'Pas encore de compte ?';

  @override
  String get loginCreateAccountAction => 'Créer un compte';

  @override
  String get registerTitle => 'Créer un compte';

  @override
  String get registerSubtitle =>
      'Synchronisez tâches, historique de focus et réglages entre vos appareils.';

  @override
  String get registerPassword => 'Mot de passe';

  @override
  String get registerSubmit => 'Créer un compte';

  @override
  String get registerSignInPrompt => 'Vous avez déjà un compte ?';

  @override
  String get registerSignInAction => 'Se connecter';

  @override
  String get registerCheckEmailTitle => 'Vérifiez votre email';

  @override
  String get registerCheckEmailMessage =>
      'Ouvrez le lien de confirmation pour terminer la création de votre compte.';

  @override
  String registerError(Object error) {
    return 'Impossible de créer le compte : $error';
  }

  @override
  String get navSearch => 'Recherche';

  @override
  String get navInbox => 'Boîte';

  @override
  String get navPriorityMatrix => 'Matrice des priorités';

  @override
  String get navTimeline => 'Timeline';

  @override
  String get navKanban => 'Kanban';

  @override
  String get kanbanTitle => 'Kanban';

  @override
  String get kanbanSubtitle =>
      'Visualisez votre flux et concentrez-vous sur l’essentiel.';

  @override
  String get kanbanDefaultBacklog => 'Backlog';

  @override
  String get kanbanDefaultTodo => 'À faire';

  @override
  String get kanbanDefaultInProgress => 'En cours';

  @override
  String get kanbanDefaultDone => 'Terminé';

  @override
  String get kanbanSearchTooltip => 'Rechercher dans Kanban';

  @override
  String get kanbanSearchHint => 'Rechercher des tâches ou projets';

  @override
  String get kanbanHideDone => 'Masquer Terminé';

  @override
  String get kanbanShowDone => 'Afficher Terminé';

  @override
  String get kanbanProjectsTitle => 'Projets de ce tableau';

  @override
  String kanbanAddToStatus(String status) {
    return 'Ajouter à $status';
  }

  @override
  String get kanbanTaskField => 'Tâche';

  @override
  String get kanbanProjectField => 'Projet';

  @override
  String get kanbanChooseProject => 'Choisissez un projet.';

  @override
  String get kanbanTaskActions => 'Actions de la tâche';

  @override
  String get kanbanDragTask => 'Faire glisser la tâche';

  @override
  String kanbanMoveTo(String status) {
    return 'Déplacer vers $status';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Restaurez la tâche avant de lancer le focus.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'Impossible de lancer le focus : $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'Impossible de charger Kanban : $error';
  }

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonContinueWaiting => 'Continuer à attendre';

  @override
  String kanbanTasksCount(int count) {
    return '$count tâches';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '$completed sur $total sous-tâches';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '$completed sur $total intervalles de focus';
  }

  @override
  String get kanbanActive => 'Actif';

  @override
  String kanbanPriority(int priority) {
    return 'Priorité $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Déplacée vers $status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Focus lancé pour $task';
  }

  @override
  String get kanbanNoTasks => 'Aucune tâche pour le moment';

  @override
  String get navToday => 'Aujourd\'hui';

  @override
  String get navUpcoming => 'À venir';

  @override
  String get navBrowse => 'Explorer';

  @override
  String get navIntegrations => 'Intégrations';

  @override
  String get navReports => 'Rapports';

  @override
  String get navFocus => 'Focus';

  @override
  String get navProjects => 'Projets';

  @override
  String get navSettings => 'Réglages';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsAboutTitle => 'À propos';

  @override
  String get settingsVersionLabel => 'Version';

  @override
  String get settingsPlanLabel => 'Formule';

  @override
  String get settingsPlanFree => 'Gratuit';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'Raccourcis clavier';

  @override
  String get settingsShortcutsSubtitle =>
      'Personnalisez les commandes disponibles avec un clavier physique.';

  @override
  String get settingsShortcutsToggleSidebar =>
      'Afficher ou masquer la barre latérale';

  @override
  String get settingsShortcutsGlobalQuickAdd => 'Ajout rapide global';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Fonctionne même lorsque Pomodoist n’est pas actif.';

  @override
  String get settingsShortcutsRecordTitle => 'Appuyez sur un raccourci';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Utilisez une touche avec Command, Control ou Alt. Appuyez sur Échap pour annuler.';

  @override
  String get settingsShortcutsInvalid => 'Ajoutez Command, Control ou Alt.';

  @override
  String get settingsShortcutsConflict => 'Ce raccourci est déjà utilisé.';

  @override
  String get settingsShortcutsGlobalError =>
      'Ce raccourci global est indisponible. Le raccourci précédent reste actif.';

  @override
  String get settingsShortcutsResetAll => 'Tout réinitialiser';

  @override
  String get settingsShortcutsResetDone => 'Raccourcis clavier réinitialisés.';

  @override
  String get csvImportTitle => 'Importer des tâches depuis un CSV';

  @override
  String get csvImportSubtitle =>
      'Vérifiez un fichier CSV avant de créer des tâches, projets, étiquettes et statuts.';

  @override
  String get csvImportSelectFile => 'Choisir un fichier CSV';

  @override
  String get csvImportHumanGuideButton => 'Guide pour les personnes';

  @override
  String get csvImportAgentGuideButton => 'Guide pour les agents';

  @override
  String get csvImportHumanGuideTitle => 'Préparer un fichier CSV';

  @override
  String get csvImportAgentGuideTitle => 'Contrat CSV pour un agent';

  @override
  String get csvImportCopy => 'Copier';

  @override
  String get csvImportCopied => 'Copié dans le presse-papiers.';

  @override
  String get csvImportPreviewTitle => 'Vérifier l’import';

  @override
  String get csvImportPreviewTasks => 'Tâches';

  @override
  String get csvImportPreviewSubtasks => 'Sous-tâches';

  @override
  String get csvImportPreviewNewProjects => 'Nouveaux projets';

  @override
  String get csvImportPreviewNewLabels => 'Nouvelles étiquettes';

  @override
  String get csvImportPreviewNewStatuses => 'Nouveaux statuts';

  @override
  String get csvImportNone => 'Aucun';

  @override
  String get csvImportDuplicateWarning =>
      'Réimporter le même fichier créera des tâches en double.';

  @override
  String get csvImportConfirm => 'Importer';

  @override
  String get csvImportSuccess => 'Tâches importées';

  @override
  String get csvImportErrorTitle => 'Échec de l’import CSV';

  @override
  String get csvImportUnexpectedError => 'Le fichier n’a pas pu être importé.';

  @override
  String get csvImportHumanGuide =>
      '1. Enregistrez le fichier au format CSV UTF-8. Utilisez une virgule (recommandé) ou un point-virgule comme séparateur.\n\n2. La colonne content est obligatoire. Vous pouvez aussi utiliser : key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Chaque ligne crée une tâche ouverte. Séparez les étiquettes avec |. La priorité va de 1 à 4 ; une valeur vide signifie 4. Un projet vide signifie Inbox et un statut vide Backlog. Les projets, étiquettes et statuts ouverts manquants sont créés automatiquement.\n\n4. Pour une tâche sur la journée, utilisez due_date au format YYYY-MM-DD. Pour une tâche horaire, renseignez start_at et end_at au format RFC3339 avec décalage UTC et une time_zone IANA, par exemple Europe/Paris.\n\n5. Pour créer des sous-tâches, donnez un key unique à la ligne parente et placez cette valeur dans parent_key de l’enfant. Le parent peut apparaître plus bas. L’enfant doit utiliser le même projet.\n\n6. Pomodoist valide tout le fichier et affiche un aperçu. Si une ligne est invalide, rien n’est enregistré. Une nouvelle importation crée des doublons.';

  @override
  String get settingsConnectedAgentsTitle => 'Agents connectés';

  @override
  String get settingsConnectedAgentsLoading =>
      'Chargement des agents connectés…';

  @override
  String get settingsConnectedAgentsEmpty => 'Aucun agent n’est connecté.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'Impossible de charger les agents connectés.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Agent';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Connecté le $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Révoquer l’accès';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'Révoquer l’accès de l’agent ?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'Révoquer l’accès de $clientName à Pomodoist ?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'Impossible de révoquer l’accès. Réessayez.';

  @override
  String get settingsLanguageTitle => 'Langue';

  @override
  String get settingsLanguageSubtitle =>
      'Choisissez la langue de l\'application.';

  @override
  String get settingsLanguageSystem => 'Par défaut du système';

  @override
  String get settingsThemeTitle => 'Thème';

  @override
  String get settingsThemeSubtitle => 'Choisissez l\'apparence de l\'app.';

  @override
  String get settingsThemeSystem => 'Système';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsTimerVisualTitle => 'Minuteur Pomodoro';

  @override
  String get settingsTimerVisualSubtitle =>
      'Choisissez l’affichage de la progression sur l’écran de focus.';

  @override
  String get settingsTimerVisualBar => 'Barre';

  @override
  String get settingsTimerVisualCircle => 'Cercle';

  @override
  String get settingsReturnRemindersTitle => 'Rappels de retour';

  @override
  String get settingsReturnRemindersSubtitle =>
      'Un léger rappel le soir si aucun focus ou tâche n’a été terminé aujourd’hui.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Durée par défaut du bloc calendrier';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'Quand seule une heure est saisie, les nouvelles tâches utilisent cette durée dans le calendrier.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Durée personnalisée';

  @override
  String get settingsDefaultTimedBlockError =>
      'Saisissez entre 1 et 480 minutes.';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get localUser => 'Utilisateur local';

  @override
  String get addTask => 'Ajouter une tâche';

  @override
  String get quickAddHint => 'Écrire sync engine demain p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'Impossible d\'ajouter la tâche : $error';
  }

  @override
  String couldNotAddProject(Object error) {
    return 'Impossible d\'ajouter le projet : $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tâches ajoutées',
      one: '1 tâche ajoutée',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Ajout vocal';

  @override
  String get voiceTitle => 'Ajout vocal';

  @override
  String get voiceRecord => 'Enregistrer';

  @override
  String get voiceAgain => 'Recommencer';

  @override
  String get voiceStop => 'Arrêter';

  @override
  String voiceAddCount(int count) {
    return 'Ajouter $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Tâche $index';
  }

  @override
  String get voiceRemoveTask => 'Supprimer';

  @override
  String get voiceInstruction => 'Touchez enregistrer et dictez des tâches.';

  @override
  String get voiceStatusIdle => 'Entrée uniquement avec le micro intégré';

  @override
  String get voiceStatusRequestingPermission => 'Demande d\'accès';

  @override
  String get voiceStatusRecording => 'Écoute du micro intégré';

  @override
  String get voiceStatusTranscribing => 'Transcription de l\'enregistrement';

  @override
  String get voiceStatusCanceled => 'Enregistrement annulé';

  @override
  String get voiceStatusUnsupported => 'Plateforme non prise en charge';

  @override
  String get voiceStatusError => 'Impossible de reconnaître la voix';

  @override
  String get voiceStatusAnalyzing => 'Découpage en tâches';

  @override
  String get voiceStatusReview => 'Vérifiez les tâches avant de les ajouter';

  @override
  String get voiceStepRecord => 'Voix';

  @override
  String get voiceStepText => 'Texte';

  @override
  String get voiceStepAnalyze => 'Analyse';

  @override
  String get voiceStepReview => 'Vérifier';

  @override
  String get voiceAnalyzing => 'Pomodoist découpe la parole en tâches';

  @override
  String get voiceFallbackError =>
      'Pomodoist n\'a pas pu traiter la parole; un brouillon a été conservé pour modification.';

  @override
  String get voiceSmartMode => 'Mode intelligent';

  @override
  String get voiceRetryAnalysis => 'Relancer l’analyse';

  @override
  String get screenInboxSubtitle =>
      'Capturez les tâches avant de les organiser.';

  @override
  String get priorityMatrixSubtitle =>
      'Déplacez les tâches entre priorités. Les dates servent seulement à trier dans une priorité.';

  @override
  String get priorityMatrixP1Title => 'Faire maintenant';

  @override
  String get priorityMatrixP2Title => 'Planifier';

  @override
  String get priorityMatrixP3Title => 'Déléguer';

  @override
  String get priorityMatrixP4Title => 'Retirer';

  @override
  String get priorityMatrixAxisUrgent => 'Urgent';

  @override
  String get priorityMatrixAxisNotUrgent => 'Non urgent';

  @override
  String get priorityMatrixAxisImportant => 'Important';

  @override
  String get priorityMatrixAxisNotImportant => 'Non important';

  @override
  String get timelineSubtitle =>
      'Planifiez une journée sur une grille horaire.';

  @override
  String get timelineAllDay => 'Toute la journée';

  @override
  String get timelineBeforeHours => 'Avant les heures visibles';

  @override
  String get timelineAfterHours => 'Après les heures visibles';

  @override
  String get timelineVisibleHours => 'Heures visibles';

  @override
  String get timelineStartHour => 'Début';

  @override
  String get timelineEndHour => 'Fin';

  @override
  String get timelineZoomOut => 'Dézoomer';

  @override
  String get timelineZoomIn => 'Zoomer';

  @override
  String timelineAddTimedHint(String time) {
    return 'Tâche à $time';
  }

  @override
  String get timelineAddAllDayHint => 'Tâche toute la journée';

  @override
  String get timelineNoAllDayTasks => 'Aucune tâche toute la journée';

  @override
  String get timelineNoTimedTasks => 'Aucune tâche horaire';

  @override
  String get timelinePreviousDay => 'Jour précédent';

  @override
  String get timelineNextDay => 'Jour suivant';

  @override
  String get timelinePickDate => 'Choisir une date';

  @override
  String get upcomingPreviousPeriod => 'Période précédente';

  @override
  String get upcomingNextPeriod => 'Période suivante';

  @override
  String get upcomingOpenDatePicker => 'Ouvrir le sélecteur de date';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tâches',
      one: '1 tâche',
      zero: 'Aucune tâche',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Charge de focus : $planned intervalles - Terminé : $completed - Focus : $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Tâches planifiées après aujourd\'hui.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Tâches prévues pour $date.';
  }

  @override
  String get noTasksHere => 'Aucune tâche ici';

  @override
  String get noUpcomingTasks => 'Aucune tâche datée';

  @override
  String get noTasksForDay => 'Aucune tâche prévue ce jour';

  @override
  String failedToLoadTasks(Object error) {
    return 'Impossible de charger les tâches : $error';
  }

  @override
  String get searchTasks => 'Rechercher des tâches';

  @override
  String get searchStartTyping =>
      'Commencez à taper pour rechercher des tâches';

  @override
  String get searchNoMatches => 'Aucune tâche correspondante';

  @override
  String failedToSearchTasks(Object error) {
    return 'Impossible de rechercher les tâches : $error';
  }

  @override
  String get previousMonth => 'Mois précédent';

  @override
  String get nextMonth => 'Mois suivant';

  @override
  String get clearDateFilter => 'Effacer le filtre de date';

  @override
  String get weekMon => 'Lun';

  @override
  String get weekTue => 'Mar';

  @override
  String get weekWed => 'Mer';

  @override
  String get weekThu => 'Jeu';

  @override
  String get weekFri => 'Ven';

  @override
  String get weekSat => 'Sam';

  @override
  String get weekSun => 'Dim';

  @override
  String get browseTitle => 'Explorer';

  @override
  String get unifiedAccount => 'Compte unifié';

  @override
  String accountUnavailable(Object error) {
    return 'Compte indisponible : $error';
  }

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get deleteAccount => 'Supprimer le compte';

  @override
  String get deleteAccountConfirmation =>
      'Cela supprimera définitivement votre compte, vos données cloud ainsi que vos tâches, projets et historique de concentration locaux. Cette action est irréversible. Les abonnements souscrits dans la boutique ne sont pas annulés automatiquement. Si vous avez utilisé Se connecter avec Apple, révoquez séparément l’accès de Pomodoist dans les réglages de votre compte Apple.';

  @override
  String get manageSignInWithApple => 'Gérer Se connecter avec Apple';

  @override
  String get deleteAccountFinalConfirmation =>
      'Êtes-vous absolument sûr ? Ceci est la confirmation finale.';

  @override
  String deleteAccountError(Object error) {
    return 'Impossible de supprimer le compte : $error';
  }

  @override
  String get accountDeleted => 'Compte supprimé.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Votre compte a été supprimé, mais les données locales n’ont pas pu être effacées. Effacez les données de l’application avant de réutiliser cet appareil.';

  @override
  String get productivityTitle => 'Productivité';

  @override
  String get achievementsTitle => 'Réussites';

  @override
  String get allTimeLabel => 'Depuis le début';

  @override
  String get lastSevenDaysLabel => '7 derniers jours';

  @override
  String get noWeeklyStatsLabel =>
      'Aucune donnée de focus ou de tâches pour l’instant';

  @override
  String get completedFocuses => 'Focus terminés';

  @override
  String get completedTasks => 'Tâches terminées';

  @override
  String get unlocked => 'Déverrouillé';

  @override
  String get locked => 'Verrouillé';

  @override
  String get progressLabel => 'Progression';

  @override
  String get focusAchievements => 'Réussites de focus';

  @override
  String get taskAchievements => 'Réussites de tâches';

  @override
  String get comboAchievements => 'Réussites combo';

  @override
  String get focusIntervals => 'Intervalles de focus';

  @override
  String get focusTime => 'Temps de focus';

  @override
  String get openTasks => 'Tâches ouvertes';

  @override
  String get plannedIntervals => 'Intervalles planifiés';

  @override
  String get labelsTitle => 'Étiquettes';

  @override
  String get newProject => 'Nouveau projet';

  @override
  String get newLabel => 'Nouvelle étiquette';

  @override
  String get syncReadyQueue => 'File prête à synchroniser';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commandes locales en attente',
      one: '1 commande locale en attente',
      zero: 'Aucune commande locale en attente',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'Impossible de charger les projets : $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'Impossible de charger les étiquettes : $error';
  }

  @override
  String get addProject => 'Ajouter un projet';

  @override
  String get projectName => 'Nom du projet';

  @override
  String get addLabel => 'Ajouter une étiquette';

  @override
  String get labelName => 'Nom de l\'étiquette';

  @override
  String couldNotAddLabel(Object error) {
    return 'Impossible d\'ajouter l\'étiquette : $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Projets indisponibles : $error';
  }

  @override
  String get projectsUnavailableShort => 'Projets indisponibles';

  @override
  String get noProjects => 'Aucun projet';

  @override
  String get searchProjects => 'Rechercher des projets';

  @override
  String get searchLabels => 'Rechercher des étiquettes';

  @override
  String get archivedProjectsOnly => 'Projets archivés uniquement';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projets',
      one: '1 projet',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'Aucune étiquette';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étiquettes',
      one: '1 étiquette',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => 'Renommer le projet';

  @override
  String get deleteProject => 'Supprimer le projet';

  @override
  String get deleteLabel => 'Supprimer l\'étiquette';

  @override
  String deleteProjectConfirmation(String name) {
    return 'Supprimer \"$name\" ? Les tâches de ce projet seront déplacées vers Inbox.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return 'Supprimer \"$name\" ?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'Impossible de supprimer le projet : $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'Impossible de supprimer l\'étiquette : $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Projets : $count';
  }

  @override
  String get collapseProjects => 'Réduire les projets';

  @override
  String get expandProjects => 'Développer les projets';

  @override
  String get projectFallbackTitle => 'Projet';

  @override
  String get projectSubtitle =>
      'Vue liste - tableau et calendrier sont prévus.';

  @override
  String get reportsTitle => 'Rapports';

  @override
  String get reportsFocusedDay => 'Une journée concentrée jusqu\'ici';

  @override
  String get reportsThisWeek => 'Votre semaine de concentration';

  @override
  String get reportsNextAchievement => 'Prochain succès';

  @override
  String get viewAllAchievements => 'Voir tous les succès';

  @override
  String viewAllAchievementsCount(int count) {
    return 'Voir les $count';
  }

  @override
  String get allAchievementsUnlocked => 'Tous les succès sont débloqués';

  @override
  String get noAchievementsYet => 'Aucun succès pour le moment';

  @override
  String failedToLoadAchievements(Object error) {
    return 'Impossible de charger les succès : $error';
  }

  @override
  String get backToReports => 'Retour aux rapports';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '$completed intervalles de concentration sur $target terminés';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '$completed intervalles de concentration terminés ; aucun objectif';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Temps de concentration des 7 derniers jours : $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'Impossible de charger les rapports : $error';
  }

  @override
  String get taskNotFound => 'Tâche introuvable';

  @override
  String get taskTitleHint => 'Titre de la tâche';

  @override
  String get taskComment => 'Commentaire';

  @override
  String get taskCommentHint => 'Ajouter un commentaire';

  @override
  String get subtasks => 'Sous-tâches';

  @override
  String get addSubtask => 'Ajouter une sous-tâche';

  @override
  String get addSubtaskHint => 'Ajouter une sous-tâche';

  @override
  String get noSubtasks => 'Aucune sous-tâche pour le moment.';

  @override
  String get makeParentTask => 'Transformer en tâche parente';

  @override
  String couldNotMoveTask(Object error) {
    return 'Impossible de déplacer la tâche : $error';
  }

  @override
  String get scheduleTitle => 'Planification';

  @override
  String get allDay => 'Toute la journée';

  @override
  String get timedBlock => 'Bloc horaire';

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
  String get noDate => 'Sans date';

  @override
  String get calendarNotLinked => 'Calendrier non lié';

  @override
  String get calendarLinked => 'Google Calendar lié';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total focus';
  }

  @override
  String get startFocus => 'Démarrer le focus';

  @override
  String get focusStarted => 'Focus démarré';

  @override
  String get taskReopened => 'Tâche rouverte';

  @override
  String get taskCompleted => 'Tâche terminée';

  @override
  String get taskDeleted => 'Tâche supprimée';

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
  String get markOpen => 'Marquer ouverte';

  @override
  String get markComplete => 'Marquer terminée';

  @override
  String get focusHistory => 'Historique de focus';

  @override
  String failedToLoadTask(Object error) {
    return 'Impossible de charger la tâche : $error';
  }

  @override
  String get noFocusIntervals => 'Aucun intervalle de focus pour le moment.';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get tomorrow => 'Demain';

  @override
  String get yesterday => 'Hier';

  @override
  String get clearDate => 'Effacer la date';

  @override
  String priority(int priority) {
    return 'Priorité $priority';
  }

  @override
  String get focusTitle => 'Focus';

  @override
  String focusLoadError(Object error) {
    return 'Impossible de charger la concentration : $error';
  }

  @override
  String get focusViewFull => 'Complet';

  @override
  String get focusViewMinimal => 'Minimal';

  @override
  String get noActiveSession => 'Aucune session active';

  @override
  String get focusIdleSubtitle =>
      'Démarrez un intervalle de focus autonome ou depuis une tâche.';

  @override
  String get noPreset => 'Aucun preset';

  @override
  String get preparingFocus => 'Préparation du focus';

  @override
  String get moreFocusOptions => 'Plus d\'options de focus';

  @override
  String get moreFocusActions => 'Plus d\'actions de focus';

  @override
  String get preset => 'Preset';

  @override
  String get newPreset => 'Nouveau preset';

  @override
  String get customize => 'Personnaliser';

  @override
  String get customizePreset => 'Personnaliser le preset';

  @override
  String get startInterval => 'Démarrer l\'intervalle';

  @override
  String get intervalStarted => 'Intervalle démarré';

  @override
  String get intervalCompleted => 'Intervalle terminé';

  @override
  String get focusStopped => 'Focus arrêté';

  @override
  String get completeInterval => 'Terminer l\'intervalle';

  @override
  String get logDistraction => 'Noter une distraction';

  @override
  String get workInterval => 'Intervalle de travail';

  @override
  String get work => 'Travail';

  @override
  String get shortBreak => 'Pause courte';

  @override
  String get breakLabel => 'Pause';

  @override
  String get longBreak => 'Pause longue';

  @override
  String readyLabel(String label) {
    return 'Prêt : $label';
  }

  @override
  String get readyShort => 'Prêt';

  @override
  String focusTimerTotal(String duration) {
    return 'sur $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Session $current sur $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Aperçu du rythme de concentration, $count étapes';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Rythme de concentration, étape $current sur $total : $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, $remaining restantes, $total au total';
  }

  @override
  String get focusStatusRunning => 'En cours';

  @override
  String get focusStatusPaused => 'En pause';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total travail';
  }

  @override
  String intervalNumber(int number) {
    return 'Intervalle $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total travail - Intervalle $number';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Reprendre';

  @override
  String get presetForNextIntervals => 'Preset pour les prochains intervalles';

  @override
  String usePreset(String name) {
    return 'Utiliser $name';
  }

  @override
  String minutesWork(int minutes) {
    return '${minutes}m travail';
  }

  @override
  String minutesShort(int minutes) {
    return '${minutes}m court';
  }

  @override
  String minutesLong(int minutes) {
    return '${minutes}m long';
  }

  @override
  String longEvery(int count) {
    return 'Long tous les $count';
  }

  @override
  String get autoBreaks => 'Pauses auto';

  @override
  String get autoWork => 'Travail auto';

  @override
  String get noPause => 'Sans pause';

  @override
  String get focusPauseUnavailable =>
      'La pause n’est pas disponible pour ce preset';

  @override
  String get strict => 'Strict';

  @override
  String get flexible => 'Flexible';

  @override
  String get name => 'Nom';

  @override
  String get workField => 'Travail';

  @override
  String get shortField => 'Court';

  @override
  String get longField => 'Long';

  @override
  String get every => 'Tous';

  @override
  String get minutesSuffix => 'min';

  @override
  String get makeDefault => 'Par défaut';

  @override
  String get autoStartBreaks => 'Démarrer les pauses automatiquement';

  @override
  String get autoStartWork => 'Démarrer le travail automatiquement';

  @override
  String get allowPause => 'Autoriser la pause';

  @override
  String get strictMode => 'Mode strict';

  @override
  String get nameRequired => 'Le nom est requis';

  @override
  String get nameMustBeUnique => 'Le nom doit être unique';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'La synchronisation bidirectionnelle est active pour le calendrier Pomodoist.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Connectez un compte Google pour synchroniser les tâches planifiées.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'La synchronisation Google Calendar s’exécute sur un autre appareil. Les données Pomodoist continuent de se synchroniser ici.';

  @override
  String get syncNow => 'Synchroniser';

  @override
  String get useThisDevice => 'Utiliser cet appareil';

  @override
  String get connect => 'Connecter';

  @override
  String get disconnect => 'Déconnecter';

  @override
  String failedToLoadIntegration(Object error) {
    return 'Impossible de charger l\'intégration : $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Calendar a échoué : $message';
  }

  @override
  String get googleAuthRequired =>
      'L\'autorisation Google Calendar est requise. Connectez-vous à nouveau puis lancez la synchronisation.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In n\'est pas configuré. Définissez GOOGLE_CLIENT_ID et GOOGLE_REVERSED_CLIENT_ID pour cette cible iOS.';

  @override
  String get googleCallbackNotConfigured =>
      'Le callback Google Sign-In n\'est pas configuré. Définissez GOOGLE_REVERSED_CLIENT_ID dans ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'Sur le web, cliquez d\'abord sur le bouton de connexion Google, puis sur Connecter.';

  @override
  String get googleAccessDenied =>
      'L\'accès Google est refusé. Ajoutez ce compte comme utilisateur de test OAuth ou publiez et vérifiez l\'app OAuth.';

  @override
  String get status => 'Statut';

  @override
  String get account => 'Compte';

  @override
  String get calendar => 'Calendrier';

  @override
  String get calendarId => 'ID du calendrier';

  @override
  String get lastSync => 'Dernière sync';

  @override
  String get notConnected => 'Non connecté';

  @override
  String get notCreated => 'Non créé';

  @override
  String get never => 'Jamais';

  @override
  String durationMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get projectColor => 'Couleur du projet';

  @override
  String projectColorOption(int number) {
    return 'Couleur $number';
  }

  @override
  String get addProjectToFavorites => 'Ajouter le projet aux favoris';

  @override
  String get removeProjectFromFavorites => 'Retirer le projet des favoris';

  @override
  String get timelineProjectsMenu => 'Gérer les projets de la chronologie';

  @override
  String get timelineShowProject => 'Afficher le projet dans la chronologie';

  @override
  String get timelineHideProject => 'Masquer le projet temporaire';

  @override
  String get timelineCollapseProject => 'Réduire la branche du projet';

  @override
  String get timelineExpandProject => 'Développer la branche du projet';

  @override
  String get timelineCurrentTime => 'Heure actuelle';

  @override
  String couldNotUpdateProject(Object error) {
    return 'Impossible de mettre à jour le projet : $error';
  }
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Añadir';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonUndo => 'Deshacer';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonCreate => 'Crear';

  @override
  String get commonClear => 'Limpiar';

  @override
  String get commonStop => 'Detener';

  @override
  String get skip => 'Saltar';

  @override
  String get onboardingLanguageTitle => 'Elige idioma';

  @override
  String get onboardingLanguageSubtitle =>
      'Elige el idioma que debe usar Pomodoist.';

  @override
  String get onboardingTimerTitle => 'Elige estilo de temporizador';

  @override
  String get onboardingTimerSubtitle =>
      'Elige la vista de progreso Pomodoro para las sesiones de enfoque.';

  @override
  String get onboardingPaywallTitle => 'Desbloquea Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'La oferta de por vida está disponible durante 24 horas cada semana.';

  @override
  String get onboardingAccountTitle => 'Crea una cuenta';

  @override
  String get onboardingAccountSubtitle =>
      'Inicia sesión para sincronizar tareas, historial de enfoque y ajustes entre dispositivos.';

  @override
  String get startupPreparingTasks => 'Estamos preparando tus tareas';

  @override
  String get operationTakingLonger =>
      'La operación está tardando más de lo habitual, pero sigue en curso.';

  @override
  String get onboardingContinue => 'Continuar';

  @override
  String get onboardingMaybeLater => 'Quizá más tarde';

  @override
  String get onboardingFinish => 'Finalizar';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Dicta tareas con lenguaje natural y Pomodoist convierte tu voz en tareas. El historial de tareas se guarda para siempre.';

  @override
  String get billingSubtitleHighlight => 'lenguaje natural';

  @override
  String get billingCancelAnytime => 'Cancela cuando quieras.';

  @override
  String get billingMonthlyTitle => 'Mensual';

  @override
  String get billingAnnualTitle => 'Anual';

  @override
  String billingPricePerMonth(String price) {
    return '$price/mes';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/año';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'Primeros 3 meses, después $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Después $price.';
  }

  @override
  String get billingLifetimeTitle => 'De por vida';

  @override
  String get billingLifetimeSubtitle => 'Un pago para siempre.';

  @override
  String get billingBestValue => 'Mejor valor';

  @override
  String get billingChoose => 'Elegir';

  @override
  String get billingActive => 'Pomodoist Pro está activo en este dispositivo.';

  @override
  String get billingActiveShort => 'Activo';

  @override
  String get billingRestore => 'Restaurar compras';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get termsOfUse => 'Términos de uso';

  @override
  String get support => 'Soporte';

  @override
  String get billingManageLink => 'Gestionar mediante Link';

  @override
  String get billingExternalBrowserTitle => 'El pago se abrirá en el navegador';

  @override
  String get billingExternalBrowserMessage =>
      'Pomodoist abrirá Stripe Checkout en Safari o en tu navegador predeterminado. Permite que se abra la ventana para continuar.';

  @override
  String get billingAppleOnly =>
      'Las compras están disponibles en iPhone, iPad y Mac.';

  @override
  String get billingStoreUnavailable =>
      'El App Store no está disponible ahora.';

  @override
  String billingPurchaseError(String error) {
    return 'Error de compra: $error';
  }

  @override
  String get purchaseSuccessTitle => 'Pro está activo';

  @override
  String get purchaseSuccessMessage =>
      'Gracias por apoyar a Pomodoist. Todas las funciones Pro ya están disponibles.';

  @override
  String get purchaseSuccessContinue => 'Continuar';

  @override
  String get purchaseProcessingTitle => 'El pago se está procesando';

  @override
  String get purchaseProcessingMessage =>
      'Estamos confirmando el pago. Si Pro no aparece pronto, vuelve a actualizar más tarde.';

  @override
  String get purchaseOpenApp => 'Abrir Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return 'La oferta de por vida termina en $time';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'Email';

  @override
  String get loginTitle => 'Inicia sesión en Pomodoist';

  @override
  String get accountChecking => 'Estamos comprobando tu cuenta';

  @override
  String get oauthConsentTitle => 'Conectar un agente';

  @override
  String get oauthConsentLoading => 'Comprobando la solicitud de conexión';

  @override
  String get oauthConsentInvalidAuthorization =>
      'Esta solicitud de conexión falta o no es válida.';

  @override
  String get oauthConsentLoadError =>
      'No se pudo cargar la solicitud de conexión.';

  @override
  String get oauthConsentActionError =>
      'No se pudo completar la solicitud. Inténtalo de nuevo.';

  @override
  String get oauthConsentRedirectError =>
      'Pomodoist recibió una dirección de retorno insegura o vacía. No se transfirió el acceso.';

  @override
  String get oauthConsentClientFallback => 'Agente';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName quiere acceder a Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Dirección de retorno';

  @override
  String get oauthConsentCapabilitiesTitle => 'Este agente puede';

  @override
  String get oauthConsentManagePlanning =>
      'Leer y gestionar tareas, proyectos, etiquetas propias y Kanban.';

  @override
  String get oauthConsentReadInsights =>
      'Leer el historial de enfoque completado, informes de productividad y logros.';

  @override
  String get oauthConsentUnavailableTitle => 'Este agente no puede';

  @override
  String get oauthConsentUnavailable =>
      'Acceder a tu cuenta o pagos, Google Calendar ni al temporizador de enfoque activo.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'Esta solicitud pide acceso de cuenta no compatible y no se puede aprobar.';

  @override
  String get oauthConsentApprove => 'Permitir';

  @override
  String get oauthConsentDeny => 'Denegar';

  @override
  String get oauthConsentApproving => 'Permitiendo el acceso…';

  @override
  String get oauthConsentDenying => 'Denegando la solicitud…';

  @override
  String get oauthConsentRedirecting => 'Volviendo al agente…';

  @override
  String get loginCreateAccountPrompt => '¿Aún no tienes cuenta?';

  @override
  String get loginCreateAccountAction => 'Crear cuenta';

  @override
  String get registerTitle => 'Crea una cuenta';

  @override
  String get registerSubtitle =>
      'Sincroniza tareas, historial de enfoque y ajustes entre dispositivos.';

  @override
  String get registerPassword => 'Contraseña';

  @override
  String get registerSubmit => 'Crear cuenta';

  @override
  String get registerSignInPrompt => '¿Ya tienes cuenta?';

  @override
  String get registerSignInAction => 'Iniciar sesión';

  @override
  String get registerCheckEmailTitle => 'Revisa tu email';

  @override
  String get registerCheckEmailMessage =>
      'Abre el enlace de confirmación para terminar de crear tu cuenta.';

  @override
  String registerError(Object error) {
    return 'No se pudo crear la cuenta: $error';
  }

  @override
  String get authEmailSignInTitle => 'Iniciar sesión con email';

  @override
  String get authSignInAction => 'Iniciar sesión';

  @override
  String get authSendLink => 'Enviar enlace';

  @override
  String get authMagicLinkSent =>
      'Enlace de acceso enviado. Revisa la bandeja de entrada y la carpeta de spam.';

  @override
  String get authAccountCreated => 'Cuenta creada.';

  @override
  String get authSignedIn => 'Sesión iniciada.';

  @override
  String get authEmailRequired => 'Introduce tu email.';

  @override
  String get authEmailInvalid =>
      'Revisa la dirección de email, por ejemplo name@example.com.';

  @override
  String get authPasswordRequired => 'Introduce tu contraseña.';

  @override
  String get authInvalidCredentials =>
      'El email o la contraseña no son correctos. Revísalos e inténtalo de nuevo.';

  @override
  String get authEmailUnconfirmed =>
      'Confirma tu email con el enlace que enviamos y vuelve a iniciar sesión.';

  @override
  String get authWeakPassword =>
      'Esta contraseña es demasiado fácil de adivinar. Usa una contraseña más larga y menos predecible.';

  @override
  String get authAccountMayExist =>
      'No se pudo crear la cuenta. Si ya te registraste con este email, inicia sesión.';

  @override
  String get authRateLimited =>
      'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';

  @override
  String get authEmailRateLimited =>
      'Se solicitaron demasiados emails. Espera unos minutos antes de pedir otro.';

  @override
  String get authOffline =>
      'No se pudo conectar con el servicio de cuentas. Revisa Internet e inténtalo de nuevo.';

  @override
  String get authTimeout =>
      'El servicio de cuentas está tardando demasiado. Inténtalo de nuevo.';

  @override
  String get authServiceUnavailable =>
      'El servicio de cuentas no está disponible temporalmente. Inténtalo más tarde.';

  @override
  String get authCaptchaRequired =>
      'Completa la verificación de seguridad para continuar.';

  @override
  String get authCaptchaExpired =>
      'La verificación de seguridad ha caducado. Complétala de nuevo.';

  @override
  String get authCaptchaFailed =>
      'La verificación de seguridad falló. Inténtalo de nuevo.';

  @override
  String get authCaptchaCancelled =>
      'La verificación de seguridad se canceló. Iníciala de nuevo para continuar.';

  @override
  String get authCaptchaUnavailable =>
      'La verificación de seguridad no está disponible ahora. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get authCaptchaOpenFailed =>
      'Pomodoist no pudo abrir la verificación de seguridad en el navegador. Revisa el navegador predeterminado e inténtalo de nuevo.';

  @override
  String get authProviderFallback => 'este proveedor';

  @override
  String authProviderUnavailable(String provider) {
    return 'El acceso con $provider no está disponible ahora. Inténtalo de nuevo o usa otro método.';
  }

  @override
  String get authSignUpDisabled =>
      'La creación de cuentas por email no está disponible temporalmente. Usa otro método de acceso.';

  @override
  String get authAccountRestricted =>
      'No se puede iniciar sesión en esta cuenta ahora. Contacta con soporte si crees que es un error.';

  @override
  String get authLinkExpired =>
      'Este enlace de acceso no es válido o ha caducado. Solicita uno nuevo.';

  @override
  String get authUnexpectedSignIn =>
      'No se pudo iniciar sesión. Inténtalo de nuevo.';

  @override
  String get authUnexpectedSignUp =>
      'No se pudo crear la cuenta. Inténtalo de nuevo.';

  @override
  String get authUnexpectedMagicLink =>
      'No se pudo enviar el enlace de acceso. Inténtalo de nuevo.';

  @override
  String get authRetryVerification => 'Reintentar verificación';

  @override
  String get captchaSecurityLabel => 'Verificación de seguridad';

  @override
  String get captchaChallengeTitle => 'Verificación de seguridad de Pomodoist';

  @override
  String get captchaChallengePrompt =>
      'Confirma que eres una persona para continuar en Pomodoist.';

  @override
  String get captchaChallengeInvalid =>
      'Este enlace de verificación no es válido. Vuelve a Pomodoist e inténtalo de nuevo.';

  @override
  String get captchaChallengeHandoffHelp =>
      'Si Pomodoist no se abrió, usa el botón de abajo. Si la aplicación no está instalada, cierra esta página y vuelve al dispositivo donde empezaste.';

  @override
  String get captchaReturnToApp => 'Volver a Pomodoist';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navInbox => 'Bandeja';

  @override
  String get navPriorityMatrix => 'Matriz de prioridades';

  @override
  String get navTimeline => 'Cronología';

  @override
  String get navKanban => 'Kanban';

  @override
  String get kanbanTitle => 'Kanban';

  @override
  String get kanbanSubtitle =>
      'Visualiza tu flujo y céntrate en lo que importa ahora.';

  @override
  String get kanbanDefaultBacklog => 'Pendientes';

  @override
  String get kanbanDefaultTodo => 'Por hacer';

  @override
  String get kanbanDefaultInProgress => 'En curso';

  @override
  String get kanbanDefaultDone => 'Hecho';

  @override
  String get kanbanSearchTooltip => 'Buscar en Kanban';

  @override
  String get kanbanSearchHint => 'Buscar tareas o proyectos';

  @override
  String get kanbanHideDone => 'Ocultar Hecho';

  @override
  String get kanbanShowDone => 'Mostrar Hecho';

  @override
  String get kanbanProjectsTitle => 'Proyectos de este tablero';

  @override
  String kanbanAddToStatus(String status) {
    return 'Añadir a $status';
  }

  @override
  String get kanbanTaskField => 'Tarea';

  @override
  String get kanbanProjectField => 'Proyecto';

  @override
  String get kanbanChooseProject => 'Elige un proyecto.';

  @override
  String get kanbanTaskActions => 'Acciones de tarea';

  @override
  String get kanbanDragTask => 'Arrastrar tarea';

  @override
  String kanbanMoveTo(String status) {
    return 'Mover a $status';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Restaura la tarea antes de iniciar el enfoque.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'No se pudo iniciar el enfoque: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'No se pudo cargar Kanban: $error';
  }

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonContinueWaiting => 'Seguir esperando';

  @override
  String kanbanTasksCount(int count) {
    return '$count tareas';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '$completed de $total subtareas';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '$completed de $total intervalos de enfoque';
  }

  @override
  String get kanbanActive => 'Activo';

  @override
  String kanbanPriority(int priority) {
    return 'Prioridad $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Movida a $status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Enfoque iniciado para $task';
  }

  @override
  String get kanbanNoTasks => 'Aún no hay tareas';

  @override
  String get navToday => 'Hoy';

  @override
  String get navUpcoming => 'Próximas';

  @override
  String get navBrowse => 'Explorar';

  @override
  String get navIntegrations => 'Integraciones';

  @override
  String get navReports => 'Informes';

  @override
  String get navFocus => 'Enfoque';

  @override
  String get navProjects => 'Proyectos';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAboutTitle => 'Acerca de';

  @override
  String get settingsFocusCompletionCelebrationTitle =>
      'Celebración al completar el enfoque';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      'Mostrar una celebración a pantalla completa después del último descanso.';

  @override
  String get settingsVersionLabel => 'Versión';

  @override
  String get settingsPlanLabel => 'Plan';

  @override
  String get settingsPlanFree => 'Gratis';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'Atajos de teclado';

  @override
  String get settingsShortcutsSubtitle =>
      'Personaliza los comandos disponibles con un teclado físico.';

  @override
  String get settingsShortcutsToggleSidebar =>
      'Mostrar u ocultar la barra lateral';

  @override
  String get settingsShortcutsGlobalQuickAdd =>
      'Añadir rápidamente de forma global';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Funciona incluso cuando Pomodoist no está activo.';

  @override
  String get settingsShortcutsRecordTitle => 'Pulsa un atajo';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Usa una tecla con Command, Control o Alt. Pulsa Esc para cancelar.';

  @override
  String get settingsShortcutsInvalid => 'Incluye Command, Control o Alt.';

  @override
  String get settingsShortcutsConflict => 'Este atajo ya está en uso.';

  @override
  String get settingsShortcutsGlobalError =>
      'Ese atajo global no está disponible. El atajo anterior sigue activo.';

  @override
  String get settingsShortcutsResetAll => 'Restablecer todo';

  @override
  String get settingsShortcutsResetDone => 'Atajos de teclado restablecidos.';

  @override
  String get csvImportTitle => 'Importar tareas desde CSV';

  @override
  String get csvImportSubtitle =>
      'Revisa un archivo CSV antes de crear tareas, proyectos, etiquetas y estados.';

  @override
  String get csvImportSelectFile => 'Elegir archivo CSV';

  @override
  String get csvImportHumanGuideButton => 'Guía para personas';

  @override
  String get csvImportAgentGuideButton => 'Guía para agentes';

  @override
  String get csvImportHumanGuideTitle => 'Cómo preparar un archivo CSV';

  @override
  String get csvImportAgentGuideTitle => 'Contrato CSV para un agente';

  @override
  String get csvImportCopy => 'Copiar';

  @override
  String get csvImportCopied => 'Copiado al portapapeles.';

  @override
  String get csvImportPreviewTitle => 'Revisar importación';

  @override
  String get csvImportPreviewTasks => 'Tareas';

  @override
  String get csvImportPreviewSubtasks => 'Subtareas';

  @override
  String get csvImportPreviewNewProjects => 'Proyectos nuevos';

  @override
  String get csvImportPreviewNewLabels => 'Etiquetas nuevas';

  @override
  String get csvImportPreviewNewStatuses => 'Estados nuevos';

  @override
  String get csvImportNone => 'Ninguno';

  @override
  String get csvImportDuplicateWarning =>
      'Volver a importar el mismo archivo creará tareas duplicadas.';

  @override
  String get csvImportConfirm => 'Importar';

  @override
  String get csvImportSuccess => 'Tareas importadas';

  @override
  String get csvImportErrorTitle => 'Error al importar el CSV';

  @override
  String get csvImportUnexpectedError => 'No se pudo importar el archivo.';

  @override
  String get csvImportHumanGuide =>
      '1. Guarda el archivo como CSV UTF-8. Usa una coma (recomendado) o un punto y coma como separador.\n\n2. La columna content es obligatoria. También puedes usar: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Cada fila crea una tarea abierta. Separa las etiquetas con |. La prioridad va de 1 a 4; vacío significa 4. Un proyecto vacío significa Inbox y un estado vacío, Backlog. Los proyectos, etiquetas y estados abiertos que falten se crean automáticamente.\n\n4. Para una tarea de todo el día, usa due_date con formato YYYY-MM-DD. Para una tarea con hora, completa start_at y end_at como valores RFC3339 con desplazamiento UTC e indica una time_zone IANA, por ejemplo Europe/Madrid.\n\n5. Para crear subtareas, asigna un key único a la fila principal y escribe ese valor en parent_key de la hija. La fila principal puede aparecer después. Ambas deben usar el mismo proyecto.\n\n6. Pomodoist valida todo el archivo y muestra una vista previa. Si alguna fila no es válida, no se guarda nada. Volver a importar crea duplicados.';

  @override
  String get settingsConnectedAgentsTitle => 'Agentes conectados';

  @override
  String get settingsConnectedAgentsLoading => 'Cargando agentes conectados…';

  @override
  String get settingsConnectedAgentsEmpty => 'No hay agentes conectados.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'No se pudieron cargar los agentes conectados.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Agente';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Conectado el $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Revocar acceso';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      '¿Revocar el acceso del agente?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return '¿Revocar el acceso de $clientName a Pomodoist?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'No se pudo revocar el acceso. Inténtalo de nuevo.';

  @override
  String get settingsLanguageTitle => 'Idioma';

  @override
  String get settingsLanguageSubtitle => 'Elige el idioma de la app.';

  @override
  String get settingsLanguageSystem => 'Predeterminado del sistema';

  @override
  String get settingsThemeTitle => 'Tema';

  @override
  String get settingsThemeSubtitle => 'Elige la apariencia de la app.';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsTimerVisualTitle => 'Temporizador Pomodoro';

  @override
  String get settingsTimerVisualSubtitle =>
      'Elige cómo se muestra el progreso en la pantalla de enfoque.';

  @override
  String get settingsTimerVisualBar => 'Barra';

  @override
  String get settingsTimerVisualCircle => 'Círculo';

  @override
  String get settingsReturnRemindersTitle => 'Recordatorios de regreso';

  @override
  String get settingsReturnRemindersSubtitle =>
      'Un aviso suave por la tarde si hoy no hay enfoque ni tarea completada.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Duración predeterminada del bloque de calendario';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'Cuando solo se escribe una hora, las tareas nuevas usan esta duración en el calendario.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Duración personalizada';

  @override
  String get settingsDefaultTimedBlockError =>
      'Introduce entre 1 y 480 minutos.';

  @override
  String get menuTooltip => 'Menú';

  @override
  String get localUser => 'Usuario local';

  @override
  String get addTask => 'Añadir tarea';

  @override
  String get quickAddHint => 'Escribir sync engine mañana p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'No se pudo añadir la tarea: $error';
  }

  @override
  String couldNotAddProject(Object error) {
    return 'No se pudo añadir el proyecto: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tareas añadidas',
      one: '1 tarea añadida',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Añadir por voz';

  @override
  String get voiceTitle => 'Añadir por voz';

  @override
  String get voiceRecord => 'Grabar';

  @override
  String get voiceAgain => 'Otra vez';

  @override
  String get voiceStop => 'Detener';

  @override
  String voiceAddCount(int count) {
    return 'Añadir $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Tarea $index';
  }

  @override
  String get voiceRemoveTask => 'Eliminar';

  @override
  String get voiceInstruction => 'Toca grabar y dicta tareas.';

  @override
  String get voiceStatusIdle => 'Solo entrada con micrófono integrado';

  @override
  String get voiceStatusRequestingPermission => 'Solicitando acceso';

  @override
  String get voiceStatusRecording => 'Escuchando el micrófono integrado';

  @override
  String get voiceStatusTranscribing => 'Transcribiendo grabación';

  @override
  String get voiceStatusCanceled => 'Grabación cancelada';

  @override
  String get voiceStatusUnsupported => 'Plataforma no compatible';

  @override
  String get voiceStatusError => 'No se pudo reconocer la voz';

  @override
  String get voiceStatusAnalyzing => 'Dividiendo en tareas';

  @override
  String get voiceStatusReview => 'Revisa las tareas antes de añadirlas';

  @override
  String get voiceStepRecord => 'Grabar';

  @override
  String get voiceStepText => 'Texto';

  @override
  String get voiceStepAnalyze => 'Análisis';

  @override
  String get voiceStepReview => 'Revisión';

  @override
  String get voiceAnalyzing => 'Pomodoist divide la voz en tareas';

  @override
  String get voiceFallbackError =>
      'Pomodoist no pudo procesar la voz; se dejó un borrador para editarlo.';

  @override
  String get voiceSmartMode => 'Modo inteligente';

  @override
  String get voiceRetryAnalysis => 'Reintentar análisis';

  @override
  String get screenInboxSubtitle => 'Captura tareas antes de organizarlas.';

  @override
  String get priorityMatrixSubtitle =>
      'Arrastra tareas entre prioridades. Las fechas solo ordenan tareas dentro de una prioridad.';

  @override
  String get priorityMatrixP1Title => 'Hacer ahora';

  @override
  String get priorityMatrixP2Title => 'Programar';

  @override
  String get priorityMatrixP3Title => 'Delegar';

  @override
  String get priorityMatrixP4Title => 'Quitar';

  @override
  String get priorityMatrixAxisUrgent => 'Urgente';

  @override
  String get priorityMatrixAxisNotUrgent => 'No urgente';

  @override
  String get priorityMatrixAxisImportant => 'Importante';

  @override
  String get priorityMatrixAxisNotImportant => 'No importante';

  @override
  String get timelineSubtitle =>
      'Planifica un día en una cuadrícula de tiempo.';

  @override
  String get timelineAllDay => 'Todo el día';

  @override
  String get timelineBeforeHours => 'Antes de las horas visibles';

  @override
  String get timelineAfterHours => 'Después de las horas visibles';

  @override
  String get timelineVisibleHours => 'Horas visibles';

  @override
  String get timelineStartHour => 'Inicio';

  @override
  String get timelineEndHour => 'Fin';

  @override
  String get timelineZoomOut => 'Alejar';

  @override
  String get timelineZoomIn => 'Acercar';

  @override
  String timelineAddTimedHint(String time) {
    return 'Tarea a las $time';
  }

  @override
  String get timelineAddAllDayHint => 'Tarea de todo el día';

  @override
  String get timelineNoAllDayTasks => 'No hay tareas de todo el día';

  @override
  String get timelineNoTimedTasks => 'No hay tareas con hora';

  @override
  String get timelinePreviousDay => 'Día anterior';

  @override
  String get timelineNextDay => 'Día siguiente';

  @override
  String get timelinePickDate => 'Elegir fecha';

  @override
  String get upcomingPreviousPeriod => 'Periodo anterior';

  @override
  String get upcomingNextPeriod => 'Periodo siguiente';

  @override
  String get upcomingOpenDatePicker => 'Abrir selector de fecha';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tareas',
      one: '1 tarea',
      zero: 'No hay tareas',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Carga de enfoque: $planned intervalos - Hecho: $completed - Enfoque: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Tareas planificadas después de hoy.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Tareas programadas para $date.';
  }

  @override
  String get noTasksHere => 'No hay tareas aquí';

  @override
  String get noUpcomingTasks => 'No hay tareas con fecha';

  @override
  String get noTasksForDay => 'No hay tareas para este día';

  @override
  String failedToLoadTasks(Object error) {
    return 'No se pudieron cargar las tareas: $error';
  }

  @override
  String get searchTasks => 'Buscar tareas';

  @override
  String get searchStartTyping => 'Empieza a escribir para buscar tareas';

  @override
  String get searchNoMatches => 'No hay tareas coincidentes';

  @override
  String failedToSearchTasks(Object error) {
    return 'No se pudieron buscar tareas: $error';
  }

  @override
  String get previousMonth => 'Mes anterior';

  @override
  String get nextMonth => 'Mes siguiente';

  @override
  String get clearDateFilter => 'Limpiar filtro de fecha';

  @override
  String get weekMon => 'Lun';

  @override
  String get weekTue => 'Mar';

  @override
  String get weekWed => 'Mié';

  @override
  String get weekThu => 'Jue';

  @override
  String get weekFri => 'Vie';

  @override
  String get weekSat => 'Sáb';

  @override
  String get weekSun => 'Dom';

  @override
  String get browseTitle => 'Explorar';

  @override
  String get unifiedAccount => 'Cuenta unificada';

  @override
  String accountUnavailable(Object error) {
    return 'Cuenta no disponible: $error';
  }

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get deleteAccount => 'Eliminar cuenta';

  @override
  String get deleteAccountConfirmation =>
      'Esto eliminará permanentemente tu cuenta, los datos en la nube y las tareas, proyectos e historial de concentración locales. Esta acción no se puede deshacer. Las suscripciones de la tienda no se cancelan automáticamente. Si usaste Iniciar sesión con Apple, revoca por separado el acceso de Pomodoist en la configuración de tu cuenta de Apple.';

  @override
  String get manageSignInWithApple => 'Gestionar Iniciar sesión con Apple';

  @override
  String get deleteAccountFinalConfirmation =>
      '¿Estás completamente seguro? Esta es la confirmación final.';

  @override
  String deleteAccountError(Object error) {
    return 'No se pudo eliminar la cuenta: $error';
  }

  @override
  String get accountDeleted => 'Cuenta eliminada.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Tu cuenta se eliminó, pero no se pudieron borrar los datos locales. Borra los datos de la aplicación antes de volver a usar este dispositivo.';

  @override
  String get productivityTitle => 'Productividad';

  @override
  String get achievementsTitle => 'Logros';

  @override
  String get allTimeLabel => 'Todo el tiempo';

  @override
  String get lastSevenDaysLabel => 'Últimos 7 días';

  @override
  String get noWeeklyStatsLabel => 'Aún no hay datos de enfoque o tareas';

  @override
  String get completedFocuses => 'Enfoques completados';

  @override
  String get completedTasks => 'Tareas completadas';

  @override
  String get unlocked => 'Desbloqueado';

  @override
  String get locked => 'Bloqueado';

  @override
  String get progressLabel => 'Progreso';

  @override
  String get focusAchievements => 'Logros de enfoque';

  @override
  String get taskAchievements => 'Logros de tareas';

  @override
  String get comboAchievements => 'Logros combo';

  @override
  String get focusIntervals => 'Intervalos de enfoque';

  @override
  String get focusTime => 'Tiempo de enfoque';

  @override
  String get openTasks => 'Tareas abiertas';

  @override
  String get plannedIntervals => 'Intervalos planificados';

  @override
  String get labelsTitle => 'Etiquetas';

  @override
  String get newProject => 'Nuevo proyecto';

  @override
  String get newLabel => 'Nueva etiqueta';

  @override
  String get syncReadyQueue => 'Cola lista para sincronizar';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comandos locales pendientes',
      one: '1 comando local pendiente',
      zero: 'No hay comandos locales pendientes',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'No se pudieron cargar los proyectos: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'No se pudieron cargar las etiquetas: $error';
  }

  @override
  String get addProject => 'Añadir proyecto';

  @override
  String get projectName => 'Nombre del proyecto';

  @override
  String get addLabel => 'Añadir etiqueta';

  @override
  String get labelName => 'Nombre de la etiqueta';

  @override
  String couldNotAddLabel(Object error) {
    return 'No se pudo añadir la etiqueta: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Proyectos no disponibles: $error';
  }

  @override
  String get projectsUnavailableShort => 'Proyectos no disponibles';

  @override
  String get noProjects => 'No hay proyectos';

  @override
  String get searchProjects => 'Buscar proyectos';

  @override
  String get searchLabels => 'Buscar etiquetas';

  @override
  String get archivedProjectsOnly => 'Solo proyectos archivados';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count proyectos',
      one: '1 proyecto',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'No hay etiquetas';

  @override
  String labelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas',
      one: '1 etiqueta',
    );
    return '$_temp0';
  }

  @override
  String get renameProject => 'Renombrar proyecto';

  @override
  String get deleteProject => 'Eliminar proyecto';

  @override
  String get deleteLabel => 'Eliminar etiqueta';

  @override
  String deleteProjectConfirmation(String name) {
    return '¿Eliminar \"$name\"? Las tareas de este proyecto se moverán a Inbox.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'No se pudo eliminar el proyecto: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'No se pudo eliminar la etiqueta: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Proyectos: $count';
  }

  @override
  String get collapseProjects => 'Contraer proyectos';

  @override
  String get expandProjects => 'Expandir proyectos';

  @override
  String get projectFallbackTitle => 'Proyecto';

  @override
  String get projectSubtitle =>
      'Vista de lista - tablero y calendario están en la hoja de ruta.';

  @override
  String get reportsTitle => 'Informes';

  @override
  String get reportsFocusedDay => 'Un día concentrado hasta ahora';

  @override
  String get reportsThisWeek => 'Tu semana de concentración';

  @override
  String get reportsNextAchievement => 'Próximo logro';

  @override
  String get viewAllAchievements => 'Ver todos los logros';

  @override
  String viewAllAchievementsCount(int count) {
    return 'Ver los $count';
  }

  @override
  String get allAchievementsUnlocked => 'Todos los logros desbloqueados';

  @override
  String get noAchievementsYet => 'Aún no hay logros';

  @override
  String failedToLoadAchievements(Object error) {
    return 'No se pudieron cargar los logros: $error';
  }

  @override
  String get backToReports => 'Volver a informes';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '$completed de $target intervalos de concentración completados';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '$completed intervalos de concentración completados; sin objetivo';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Tiempo de concentración de los últimos 7 días: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'No se pudieron cargar los informes: $error';
  }

  @override
  String get taskNotFound => 'Tarea no encontrada';

  @override
  String get taskTitleHint => 'Título de la tarea';

  @override
  String get taskComment => 'Comentario';

  @override
  String get taskCommentHint => 'Añadir comentario';

  @override
  String get subtasks => 'Subtareas';

  @override
  String get addSubtask => 'Añadir subtarea';

  @override
  String get addSubtaskHint => 'Añadir subtarea';

  @override
  String get noSubtasks => 'Aún no hay subtareas.';

  @override
  String get makeParentTask => 'Convertir en tarea principal';

  @override
  String couldNotMoveTask(Object error) {
    return 'No se pudo mover la tarea: $error';
  }

  @override
  String get scheduleTitle => 'Programación';

  @override
  String get allDay => 'Todo el día';

  @override
  String get timedBlock => 'Bloque con hora';

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
  String get noDate => 'Sin fecha';

  @override
  String get calendarNotLinked => 'Calendario no vinculado';

  @override
  String get calendarLinked => 'Google Calendar vinculado';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total enfoque';
  }

  @override
  String get startFocus => 'Iniciar enfoque';

  @override
  String get focusStarted => 'Enfoque iniciado';

  @override
  String get taskReopened => 'Tarea reabierta';

  @override
  String get taskCompleted => 'Tarea completada';

  @override
  String get taskDeleted => 'Tarea eliminada';

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
  String get markOpen => 'Marcar abierta';

  @override
  String get markComplete => 'Marcar completada';

  @override
  String get focusHistory => 'Historial de enfoque';

  @override
  String failedToLoadTask(Object error) {
    return 'No se pudo cargar la tarea: $error';
  }

  @override
  String get noFocusIntervals => 'Aún no hay intervalos de enfoque.';

  @override
  String get today => 'Hoy';

  @override
  String get tomorrow => 'Mañana';

  @override
  String get yesterday => 'Ayer';

  @override
  String get clearDate => 'Limpiar fecha';

  @override
  String priority(int priority) {
    return 'Prioridad $priority';
  }

  @override
  String get focusTitle => 'Enfoque';

  @override
  String focusLoadError(Object error) {
    return 'No se pudo cargar el enfoque: $error';
  }

  @override
  String get focusViewFull => 'Completo';

  @override
  String get focusViewMinimal => 'Mínimo';

  @override
  String get noActiveSession => 'No hay sesión activa';

  @override
  String get focusIdleSubtitle =>
      'Inicia un intervalo de enfoque independiente o desde una tarea.';

  @override
  String get noPreset => 'Sin preset';

  @override
  String get preparingFocus => 'Preparando enfoque';

  @override
  String get moreFocusOptions => 'Más opciones de enfoque';

  @override
  String get moreFocusActions => 'Más acciones de enfoque';

  @override
  String get preset => 'Preset';

  @override
  String get newPreset => 'Nuevo preset';

  @override
  String get customize => 'Personalizar';

  @override
  String get customizePreset => 'Personalizar preset';

  @override
  String get startInterval => 'Iniciar intervalo';

  @override
  String get intervalStarted => 'Intervalo iniciado';

  @override
  String get intervalCompleted => 'Intervalo completado';

  @override
  String get focusStopped => 'Enfoque detenido';

  @override
  String get focusCompletionTitle => '¡Excelente trabajo!';

  @override
  String get focusCompletionLinkedSubtitle =>
      'Todos los intervalos de enfoque previstos para esta tarea están completos.';

  @override
  String get focusCompletionStandaloneSubtitle =>
      'Tu ciclo de enfoque está completo.';

  @override
  String get focusCompletionQuestion => '¿Quieres completar esta tarea?';

  @override
  String get focusCompletionCompleteTask => 'Completar tarea';

  @override
  String get focusCompletionKeepOpen => 'Mantener tarea abierta';

  @override
  String get focusCompletionDone => 'Listo';

  @override
  String get focusCompletionNextTask => 'Próxima tarea programada';

  @override
  String focusCompletionTaskError(Object error) {
    return 'No se pudo completar la tarea: $error';
  }

  @override
  String get completeInterval => 'Completar intervalo';

  @override
  String get logDistraction => 'Registrar distracción';

  @override
  String get workInterval => 'Intervalo de trabajo';

  @override
  String get work => 'Trabajo';

  @override
  String get shortBreak => 'Descanso corto';

  @override
  String get breakLabel => 'Descanso';

  @override
  String get longBreak => 'Descanso largo';

  @override
  String readyLabel(String label) {
    return 'Listo: $label';
  }

  @override
  String get readyShort => 'Listo';

  @override
  String focusTimerTotal(String duration) {
    return 'de $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Sesión $current de $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Vista previa del ritmo de enfoque, $count pasos';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Ritmo de enfoque, paso $current de $total: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, quedan $remaining, $total en total';
  }

  @override
  String get focusStatusRunning => 'En curso';

  @override
  String get focusStatusPaused => 'En pausa';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total trabajo';
  }

  @override
  String intervalNumber(int number) {
    return 'Intervalo $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total trabajo - Intervalo $number';
  }

  @override
  String get pause => 'Pausar';

  @override
  String get resume => 'Reanudar';

  @override
  String get presetForNextIntervals => 'Preset para próximos intervalos';

  @override
  String usePreset(String name) {
    return 'Usar $name';
  }

  @override
  String minutesWork(int minutes) {
    return '${minutes}m trabajo';
  }

  @override
  String minutesShort(int minutes) {
    return '${minutes}m corto';
  }

  @override
  String minutesLong(int minutes) {
    return '${minutes}m largo';
  }

  @override
  String longEvery(int count) {
    return 'Largo cada $count';
  }

  @override
  String get autoBreaks => 'Descansos auto';

  @override
  String get autoWork => 'Trabajo auto';

  @override
  String get noPause => 'Sin pausa';

  @override
  String get focusPauseUnavailable =>
      'La pausa no está disponible para este preset';

  @override
  String get strict => 'Estricto';

  @override
  String get flexible => 'Flexible';

  @override
  String get name => 'Nombre';

  @override
  String get workField => 'Trabajo';

  @override
  String get shortField => 'Corto';

  @override
  String get longField => 'Largo';

  @override
  String get every => 'Cada';

  @override
  String get minutesSuffix => 'min';

  @override
  String get makeDefault => 'Predeterminado';

  @override
  String get autoStartBreaks => 'Auto-iniciar descansos';

  @override
  String get autoStartWork => 'Auto-iniciar trabajo';

  @override
  String get allowPause => 'Permitir pausa';

  @override
  String get strictMode => 'Modo estricto';

  @override
  String get nameRequired => 'El nombre es obligatorio';

  @override
  String get nameMustBeUnique => 'El nombre debe ser único';

  @override
  String get googleCalendarTitle => 'Google Calendar';

  @override
  String get googleCalendarConnectedSubtitle =>
      'La sincronización bidireccional está activa para el calendario Pomodoist.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Conecta una cuenta de Google para sincronizar tareas programadas.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'La sincronización de Google Calendar se ejecuta en otro dispositivo. Los datos de Pomodoist se siguen sincronizando aquí.';

  @override
  String get syncNow => 'Sincronizar ahora';

  @override
  String get useThisDevice => 'Usar este dispositivo';

  @override
  String get connect => 'Conectar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String failedToLoadIntegration(Object error) {
    return 'No se pudo cargar la integración: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Google Calendar falló: $message';
  }

  @override
  String get googleAuthRequired =>
      'Se requiere autorización de Google Calendar. Inicia sesión de nuevo y ejecuta Sincronizar ahora.';

  @override
  String get googleSignInNotConfigured =>
      'Google Sign-In no está configurado. Define GOOGLE_CLIENT_ID y GOOGLE_REVERSED_CLIENT_ID para este target iOS.';

  @override
  String get googleCallbackNotConfigured =>
      'El callback de Google Sign-In no está configurado. Define GOOGLE_REVERSED_CLIENT_ID en ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'En web, haz clic primero en el botón de inicio de sesión de Google y luego en Conectar.';

  @override
  String get googleAccessDenied =>
      'El acceso de Google fue denegado. Añade esta cuenta como usuario de prueba OAuth o publica y verifica la app OAuth.';

  @override
  String get status => 'Estado';

  @override
  String get account => 'Cuenta';

  @override
  String get calendar => 'Calendario';

  @override
  String get calendarId => 'ID del calendario';

  @override
  String get lastSync => 'Última sincronización';

  @override
  String get notConnected => 'No conectado';

  @override
  String get notCreated => 'No creado';

  @override
  String get never => 'Nunca';

  @override
  String durationMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get projectColor => 'Color del proyecto';

  @override
  String projectColorOption(int number) {
    return 'Color $number';
  }

  @override
  String get addProjectToFavorites => 'Añadir proyecto a favoritos';

  @override
  String get removeProjectFromFavorites => 'Quitar proyecto de favoritos';

  @override
  String get timelineProjectsMenu => 'Gestionar proyectos del Timeline';

  @override
  String get timelineShowProject => 'Mostrar proyecto en Timeline';

  @override
  String get timelineHideProject => 'Ocultar proyecto temporal';

  @override
  String get timelineCollapseProject => 'Contraer rama del proyecto';

  @override
  String get timelineExpandProject => 'Expandir rama del proyecto';

  @override
  String get timelineCurrentTime => 'Hora actual';

  @override
  String couldNotUpdateProject(Object error) {
    return 'No se pudo actualizar el proyecto: $error';
  }

  @override
  String get commonDone => 'Listo';

  @override
  String get taskSelect => 'Seleccionar';

  @override
  String taskSelectedCount(int count) {
    return '$count seleccionadas';
  }

  @override
  String get taskSelectAll => 'Seleccionar todo';

  @override
  String get taskDeselectAll => 'Deseleccionar todo';

  @override
  String get taskDue => 'Fecha';

  @override
  String get taskProject => 'Proyecto';

  @override
  String get taskLabels => 'Etiquetas';

  @override
  String get taskPriority => 'Prioridad';

  @override
  String get taskMore => 'Más';

  @override
  String get taskSchedule => 'Programar';

  @override
  String get taskMove => 'Mover';

  @override
  String get taskDuplicate => 'Duplicar';

  @override
  String get taskDuplicateTitle => 'Duplicar tareas';

  @override
  String get taskDuplicateSelectedOnly => 'Solo seleccionadas';

  @override
  String get taskDuplicateWithSubtasks => 'Con subtareas';

  @override
  String get taskWeekend => 'Este fin de semana';

  @override
  String get taskNextWeek => 'La próxima semana';

  @override
  String get taskEnterDue => 'Introduce fecha u hora';

  @override
  String get taskInvalidDue => 'Introduce una fecha u hora válida';

  @override
  String get taskClearDue => 'Quitar fecha';

  @override
  String get taskDeleteSelectedTitle => '¿Eliminar las tareas seleccionadas?';

  @override
  String get taskDeleteSelectedMessage => 'Esta acción no se puede deshacer.';

  @override
  String get taskCompleteSelected => 'Completar seleccionadas';

  @override
  String get taskReopenSelected => 'Reabrir seleccionadas';

  @override
  String taskActionFailedCount(int count) {
    return 'No se pudieron actualizar $count tareas';
  }
}

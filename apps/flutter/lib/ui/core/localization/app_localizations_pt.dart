// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'package:pomodoist/ui/core/localization/app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get settingsSectionGeneral => 'Geral';

  @override
  String get settingsSectionAppearance => 'Aparência';

  @override
  String get settingsSectionTasksFocus => 'Tarefas e foco';

  @override
  String get settingsSectionIntegrations => 'Integrações e dados';

  @override
  String get settingsSectionAccount => 'Conta e Pro';

  @override
  String get settingsThemeColorsTab => 'Cores';

  @override
  String get settingsThemeBackgroundsTab => 'Planos de fundo';

  @override
  String get settingsRefreshAccount => 'Atualizar conta';

  @override
  String get settingsSubscriptionActions => 'Opções de assinatura';

  @override
  String get settingsSubscriptionError =>
      'Não foi possível atualizar sua assinatura. O acesso confirmado anteriormente foi mantido.';

  @override
  String get settingsVersionError => 'Não foi possível carregar a versão.';

  @override
  String get appTitle => 'pomodoist';

  @override
  String get commonAdd => 'Adicionar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonDelete => 'Excluir';

  @override
  String get commonUndo => 'Desfazer';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonBack => 'Voltar';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonCreate => 'Criar';

  @override
  String get commonClear => 'Limpar';

  @override
  String get commonStop => 'Parar';

  @override
  String get skip => 'Pular';

  @override
  String get onboardingLanguageTitle => 'Escolha o idioma';

  @override
  String get onboardingLanguageSubtitle => 'Escolha o idioma do Pomodoist.';

  @override
  String get onboardingTimerTitle => 'Escolha o estilo do timer';

  @override
  String get onboardingTimerSubtitle =>
      'Escolha como exibir o progresso Pomodoro nas sessões de foco.';

  @override
  String get onboardingPaywallTitle => 'Desbloqueie o Pomodoist';

  @override
  String get onboardingPaywallSubtitle =>
      'A oferta vitalícia fica disponível por 24 horas toda semana.';

  @override
  String get onboardingAccountTitle => 'Crie uma conta';

  @override
  String get onboardingAccountSubtitle =>
      'Entre para sincronizar tarefas, histórico de foco e configurações entre dispositivos.';

  @override
  String get startupPreparingTasks => 'Preparando suas tarefas';

  @override
  String get operationTakingLonger =>
      'Está demorando mais que o normal. A operação ainda está em andamento.';

  @override
  String get onboardingContinue => 'Continuar';

  @override
  String get onboardingMaybeLater => 'Talvez depois';

  @override
  String get onboardingFinish => 'Concluir';

  @override
  String get billingTitle => 'Pomodoist Pro';

  @override
  String get billingSubtitle =>
      'Dite tarefas em linguagem natural, e o Pomodoist transforma suas palavras em tarefas. O histórico de tarefas é salvo para sempre.';

  @override
  String get billingSubtitleHighlight => 'linguagem natural';

  @override
  String get billingCancelAnytime => 'Cancele quando quiser.';

  @override
  String get billingMonthlyTitle => 'Mensal';

  @override
  String get billingAnnualTitle => 'Anual';

  @override
  String billingPricePerMonth(String price) {
    return '$price/mês';
  }

  @override
  String billingPricePerYear(String price) {
    return '$price/ano';
  }

  @override
  String billingMonthlyIntroSubtitle(String price) {
    return 'Primeiros 3 meses, depois $price.';
  }

  @override
  String billingAnnualIntroSubtitle(String price) {
    return 'Depois $price.';
  }

  @override
  String get billingLifetimeTitle => 'Vitalício';

  @override
  String get billingLifetimeSubtitle => 'Um pagamento, para sempre.';

  @override
  String get billingBestValue => 'Melhor custo-benefício';

  @override
  String get billingChoose => 'Escolher';

  @override
  String get billingActive => 'O Pomodoist Pro está ativo neste dispositivo.';

  @override
  String get billingActiveShort => 'Ativo';

  @override
  String get billingRestore => 'Restaurar compras';

  @override
  String get privacyPolicy => 'Política de Privacidade';

  @override
  String get termsOfUse => 'Termos de Uso';

  @override
  String get support => 'Suporte';

  @override
  String get billingManageLink => 'Gerenciar pelo Link';

  @override
  String get billingExternalBrowserTitle => 'O pagamento abre no navegador';

  @override
  String get billingExternalBrowserMessage =>
      'O Pomodoist abrirá o Stripe Checkout no Safari ou no navegador padrão. Permita a abertura da janela para continuar.';

  @override
  String get billingAppleOnly => 'Compras disponíveis no iPhone, iPad e Mac.';

  @override
  String get billingStoreUnavailable =>
      'A App Store não está disponível no momento.';

  @override
  String get billingStoreConnectionFailed =>
      'Desative a VPN e tente novamente.';

  @override
  String billingPurchaseError(String error) {
    return 'Erro na compra: $error';
  }

  @override
  String get billingStripeAuthenticationRequired =>
      'Entre no Pomodoist e tente novamente.';

  @override
  String get billingStripeDisabled =>
      'Os pagamentos ainda não estão disponíveis. Tente novamente mais tarde.';

  @override
  String get billingStripeAlreadyEntitled =>
      'O Pomodoist Pro já está ativo. Atualize o status da sua conta.';

  @override
  String get billingStripeOfferExpired =>
      'Esta oferta expirou. Escolha outro plano disponível.';

  @override
  String get billingStripeManagedPaymentsUnavailable =>
      'Os pagamentos pelo Stripe estão temporariamente indisponíveis. Tente mais tarde ou contate o suporte.';

  @override
  String get billingStripeCheckoutFailed =>
      'Não foi possível iniciar o pagamento. Verifique sua conexão e tente novamente.';

  @override
  String get purchaseSuccessTitle => 'Pro está ativo';

  @override
  String get purchaseSuccessMessage =>
      'Obrigado por apoiar o Pomodoist. Todos os recursos Pro estão prontos para uso.';

  @override
  String get purchaseSuccessContinue => 'Continuar';

  @override
  String get purchaseProcessingTitle => 'Pagamento em processamento';

  @override
  String get purchaseProcessingMessage =>
      'Seu pagamento está sendo confirmado. Se o Pro não aparecer em breve, atualize novamente mais tarde.';

  @override
  String get purchaseOpenApp => 'Abrir Pomodoist';

  @override
  String launchOfferEndsIn(String time) {
    return 'Restam $time na oferta vitalícia';
  }

  @override
  String get accountApple => 'Apple';

  @override
  String get accountGoogle => 'Google';

  @override
  String get accountEmail => 'E-mail';

  @override
  String get loginTitle => 'Entrar no Pomodoist';

  @override
  String get accountChecking => 'Verificando sua conta';

  @override
  String get oauthConsentTitle => 'Conectar um agente';

  @override
  String get oauthConsentLoading => 'Verificando a solicitação de conexão';

  @override
  String get oauthConsentInvalidAuthorization =>
      'Esta solicitação de conexão está ausente ou é inválida.';

  @override
  String get oauthConsentLoadError =>
      'Não foi possível carregar a solicitação de conexão.';

  @override
  String get oauthConsentActionError =>
      'Não foi possível concluir a solicitação. Tente novamente.';

  @override
  String get oauthConsentRedirectError =>
      'O Pomodoist recebeu um endereço de retorno inseguro ou ausente. O acesso não foi concedido.';

  @override
  String get oauthConsentClientFallback => 'Agente';

  @override
  String oauthConsentClientRequest(String clientName) {
    return '$clientName quer acessar o Pomodoist';
  }

  @override
  String get oauthConsentRedirectOrigin => 'Endereço de retorno';

  @override
  String get oauthConsentCapabilitiesTitle => 'Este agente pode';

  @override
  String get oauthConsentManagePlanning =>
      'Ler e gerenciar tarefas, projetos, etiquetas do usuário e Kanban.';

  @override
  String get oauthConsentReadInsights =>
      'Ler histórico de foco concluído, relatórios de produtividade e conquistas.';

  @override
  String get oauthConsentUnavailableTitle => 'Este agente não pode';

  @override
  String get oauthConsentUnavailable =>
      'Acessar sua conta ou cobrança, Google Agenda ou o timer de foco em andamento.';

  @override
  String get oauthConsentUnsupportedScopes =>
      'Esta solicitação pede acesso não permitido à conta e não pode ser aprovada.';

  @override
  String get oauthConsentApprove => 'Permitir';

  @override
  String get oauthConsentDeny => 'Negar';

  @override
  String get oauthConsentApproving => 'Permitindo acesso…';

  @override
  String get oauthConsentDenying => 'Negando acesso…';

  @override
  String get oauthConsentRedirecting => 'Voltando ao agente…';

  @override
  String get loginCreateAccountPrompt => 'Ainda não tem conta?';

  @override
  String get loginCreateAccountAction => 'Criar conta';

  @override
  String get registerTitle => 'Criar uma conta';

  @override
  String get registerSubtitle =>
      'Sincronize tarefas, histórico de foco e configurações entre dispositivos.';

  @override
  String get registerPassword => 'Senha';

  @override
  String get registerSubmit => 'Criar conta';

  @override
  String get registerSignInPrompt => 'Já tem uma conta?';

  @override
  String get registerSignInAction => 'Entrar';

  @override
  String get registerCheckEmailTitle => 'Verifique seu e-mail';

  @override
  String get registerCheckEmailMessage =>
      'Se este endereço precisar de confirmação, você receberá um e-mail com um link. Se já tem uma conta, entre ou redefina sua senha.';

  @override
  String registerError(Object error) {
    return 'Não foi possível criar a conta: $error';
  }

  @override
  String get authEmailSignInTitle => 'Entrar com e-mail';

  @override
  String get authWelcomeTitle => 'Entrar no Pomodoist';

  @override
  String get authWelcomeDescription =>
      'Suas tarefas e seu foco, em todos os dispositivos.';

  @override
  String get authSignInWithLink => 'Entrar com um link';

  @override
  String get authForgotPassword => 'Esqueceu a senha?';

  @override
  String get authBackToSignIn => 'Voltar para entrar';

  @override
  String get authNoAccount => 'Ainda não tem conta?';

  @override
  String get authHaveAccount => 'Já tem uma conta?';

  @override
  String get authShowPassword => 'Mostrar senha';

  @override
  String get authHidePassword => 'Ocultar senha';

  @override
  String get authResetTitle => 'Redefinir sua senha';

  @override
  String get authResetDescription =>
      'Digite o e-mail da sua conta. Enviaremos um link para alterar sua senha.';

  @override
  String get authResetEmailSentTitle => 'Verifique seu e-mail';

  @override
  String get authResetEmailSent =>
      'Se existir uma conta com este e-mail, você receberá um link para redefinir a senha.';

  @override
  String get authResetSendAgain => 'Enviar novamente';

  @override
  String get authResetEditEmail => 'Alterar e-mail';

  @override
  String get authNewPasswordTitle => 'Escolha uma nova senha';

  @override
  String get authNewPasswordDescription =>
      'Use uma senha que você não usa em outras contas.';

  @override
  String get authNewPassword => 'Nova senha';

  @override
  String get authConfirmPassword => 'Repita a senha';

  @override
  String get authSavePassword => 'Salvar senha';

  @override
  String get authPasswordMismatch => 'As senhas não coincidem.';

  @override
  String get authPasswordUnchanged => 'Escolha uma senha diferente da atual.';

  @override
  String get authPasswordUpdatedTitle => 'Senha atualizada';

  @override
  String get authPasswordUpdatedMessage =>
      'Sua nova senha foi salva. Você pode continuar usando o Pomodoist.';

  @override
  String get authResetLinkExpired =>
      'Este link para redefinir a senha é inválido ou expirou. Solicite um novo link.';

  @override
  String get authUnexpectedReset =>
      'Não foi possível enviar o e-mail de redefinição de senha. Tente novamente.';

  @override
  String get authUnexpectedPasswordUpdate =>
      'Não foi possível salvar sua nova senha. Tente novamente.';

  @override
  String get authCheckingResetLink =>
      'Verificando seu link de redefinição de senha…';

  @override
  String get authSignInAction => 'Entrar';

  @override
  String get authSendLink => 'Enviar link';

  @override
  String get authMagicLinkSent =>
      'Se existir uma conta com este endereço, você receberá um link para entrar. Verifique a caixa de entrada e o spam.';

  @override
  String get authAccountCreated => 'Conta criada.';

  @override
  String get authSignedIn => 'Você entrou.';

  @override
  String get authEmailRequired => 'Digite seu e-mail.';

  @override
  String get authEmailInvalid =>
      'Verifique o endereço de e-mail, por exemplo nome@example.com.';

  @override
  String get authPasswordRequired => 'Digite sua senha.';

  @override
  String get authInvalidCredentials =>
      'E-mail ou senha incorretos. Verifique o endereço, redefina a senha ou crie uma conta.';

  @override
  String get authEmailUnconfirmed =>
      'Confirme seu e-mail pelo link enviado e entre novamente.';

  @override
  String get authWeakPassword =>
      'Esta senha é fácil demais de adivinhar. Use uma senha mais longa e menos previsível.';

  @override
  String get authAccountMayExist =>
      'Já pode existir uma conta com este e-mail. Entre ou redefina sua senha.';

  @override
  String get authRateLimited =>
      'Muitas tentativas. Aguarde alguns minutos e tente novamente.';

  @override
  String get authEmailRateLimited =>
      'Muitos e-mails foram solicitados. Aguarde alguns minutos antes de pedir outro.';

  @override
  String get authOffline =>
      'Não foi possível acessar o serviço de contas. Verifique sua conexão com a internet e tente novamente.';

  @override
  String get authTimeout =>
      'O serviço de contas está demorando para responder. Tente novamente.';

  @override
  String get authServiceUnavailable =>
      'O serviço de contas está temporariamente indisponível. Tente mais tarde.';

  @override
  String get authCaptchaRequired =>
      'Conclua a verificação de segurança para continuar.';

  @override
  String get authCaptchaExpired =>
      'A verificação de segurança expirou. Faça-a novamente.';

  @override
  String get authCaptchaFailed =>
      'A verificação de segurança falhou. Tente novamente.';

  @override
  String get authCaptchaCancelled =>
      'A verificação de segurança foi cancelada. Reinicie-a para continuar.';

  @override
  String get authCaptchaUnavailable =>
      'A verificação de segurança está indisponível. Verifique sua conexão e tente novamente.';

  @override
  String get authCaptchaOpenFailed =>
      'O Pomodoist não conseguiu abrir a verificação de segurança no navegador. Verifique seu navegador padrão e tente novamente.';

  @override
  String get authProviderFallback => 'este provedor';

  @override
  String authProviderUnavailable(String provider) {
    return 'Entrar com $provider está indisponível. Tente novamente ou use outro método.';
  }

  @override
  String get authSignUpDisabled =>
      'Criar contas com e-mail está temporariamente indisponível. Tente outro método de entrada.';

  @override
  String get authAccountRestricted =>
      'Esta conta não pode entrar no momento. Contate o suporte se achar que é um erro.';

  @override
  String get authLinkExpired =>
      'Este link de entrada é inválido ou expirou. Solicite um novo link.';

  @override
  String get authUnexpectedSignIn =>
      'Não foi possível entrar. Tente novamente.';

  @override
  String get authUnexpectedSignUp =>
      'Não foi possível criar a conta. Tente novamente.';

  @override
  String get authUnexpectedMagicLink =>
      'Não foi possível enviar o link de entrada. Tente novamente.';

  @override
  String get authResendConfirmation => 'Reenviar confirmação';

  @override
  String get authConfirmationSendFailed =>
      'Não foi possível enviar o e-mail de confirmação. Tente mais tarde.';

  @override
  String get authRetryVerification => 'Tentar verificação novamente';

  @override
  String get captchaSecurityLabel => 'Verificação de segurança';

  @override
  String get captchaChallengeTitle => 'Verificação de segurança do Pomodoist';

  @override
  String get captchaChallengePrompt =>
      'Confirme que você é humano para continuar no Pomodoist.';

  @override
  String get captchaChallengeInvalid =>
      'Este link de verificação de segurança é inválido. Volte ao Pomodoist e tente novamente.';

  @override
  String get captchaChallengeHandoffHelp =>
      'Se o Pomodoist não abriu, use o botão abaixo. Se o app não estiver instalado, feche esta página e volte ao dispositivo onde começou.';

  @override
  String get captchaReturnToApp => 'Voltar ao Pomodoist';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navInbox => 'Entrada';

  @override
  String get navPriorityMatrix => 'Matriz de prioridades';

  @override
  String get navTimeline => 'Linha do tempo';

  @override
  String get navKanban => 'Kanban';

  @override
  String get kanbanTitle => 'Kanban';

  @override
  String get kanbanSubtitle =>
      'Visualize seu fluxo de trabalho e foque no que importa agora.';

  @override
  String get kanbanDefaultBacklog => 'Pendências';

  @override
  String get kanbanDefaultTodo => 'A fazer';

  @override
  String get kanbanDefaultInProgress => 'Em andamento';

  @override
  String get kanbanDefaultDone => 'Concluído';

  @override
  String get kanbanSearchTooltip => 'Buscar no Kanban';

  @override
  String get kanbanSearchHint => 'Buscar tarefas ou projetos';

  @override
  String get kanbanHideDone => 'Ocultar concluídos';

  @override
  String get kanbanShowDone => 'Mostrar concluídos';

  @override
  String get kanbanProjectsTitle => 'Projetos neste quadro';

  @override
  String kanbanAddToStatus(String status) {
    return 'Adicionar a $status';
  }

  @override
  String get kanbanTaskField => 'Tarefa';

  @override
  String get kanbanProjectField => 'Projeto';

  @override
  String get kanbanChooseProject => 'Escolha um projeto.';

  @override
  String get kanbanTaskActions => 'Ações da tarefa';

  @override
  String get kanbanDragTask => 'Arrastar tarefa';

  @override
  String kanbanMoveTo(String status) {
    return 'Mover para $status';
  }

  @override
  String get kanbanRestoreBeforeFocus =>
      'Restaure a tarefa antes de iniciar o foco.';

  @override
  String kanbanCouldNotStartFocus(Object error) {
    return 'Não foi possível iniciar o foco: $error';
  }

  @override
  String kanbanCouldNotLoad(Object error) {
    return 'Não foi possível carregar o Kanban: $error';
  }

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonContinueWaiting => 'Continuar aguardando';

  @override
  String kanbanTasksCount(int count) {
    return '$count tarefas';
  }

  @override
  String kanbanSubtasksProgress(int completed, int total) {
    return '$completed de $total subtarefas';
  }

  @override
  String kanbanFocusIntervalsProgress(int completed, int total) {
    return '$completed de $total intervalos de foco';
  }

  @override
  String get kanbanActive => 'Ativo';

  @override
  String kanbanPriority(int priority) {
    return 'Prioridade $priority';
  }

  @override
  String kanbanMoveAnnouncement(String status) {
    return 'Movido para $status';
  }

  @override
  String kanbanFocusStartedAnnouncement(String task) {
    return 'Foco iniciado em $task';
  }

  @override
  String get kanbanNoTasks => 'Nenhuma tarefa ainda';

  @override
  String get navToday => 'Hoje';

  @override
  String get navUpcoming => 'Em breve';

  @override
  String get navBrowse => 'Explorar';

  @override
  String get navIntegrations => 'Integrações';

  @override
  String get navReports => 'Relatórios';

  @override
  String get navFocus => 'Foco';

  @override
  String get navProjects => 'Projetos';

  @override
  String get navSettings => 'Configurações';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsAboutTitle => 'Sobre';

  @override
  String get settingsFocusCompletionCelebrationTitle =>
      'Celebração ao concluir o foco';

  @override
  String get settingsFocusCompletionCelebrationSubtitle =>
      'Mostrar uma celebração em tela cheia após a última pausa.';

  @override
  String get settingsVersionLabel => 'Versão';

  @override
  String get settingsPlanLabel => 'Plano';

  @override
  String get settingsPlanFree => 'Gratuito';

  @override
  String get settingsPlanPro => 'Pomodoist Pro';

  @override
  String get settingsShortcutsTitle => 'Atalhos de teclado';

  @override
  String get settingsShortcutsSubtitle =>
      'Personalize os comandos disponíveis em um teclado físico.';

  @override
  String get settingsShortcutsToggleSidebar => 'Alternar barra lateral';

  @override
  String get settingsShortcutsGlobalQuickAdd => 'Adição rápida global';

  @override
  String get settingsShortcutsGlobalQuickAddSubtitle =>
      'Funciona mesmo quando o Pomodoist não está ativo.';

  @override
  String get settingsShortcutsRecordTitle => 'Pressione um atalho';

  @override
  String get settingsShortcutsRecordPrompt =>
      'Use uma tecla com Command, Control ou Alt. Pressione Esc para cancelar.';

  @override
  String get settingsShortcutsInvalid => 'Inclua Command, Control ou Alt.';

  @override
  String get settingsShortcutsConflict => 'Este atalho já está em uso.';

  @override
  String get settingsShortcutsGlobalError =>
      'Este atalho global está indisponível. O atalho anterior continua ativo.';

  @override
  String get settingsShortcutsResetAll => 'Redefinir tudo';

  @override
  String get settingsShortcutsResetDone => 'Atalhos de teclado redefinidos.';

  @override
  String get csvImportTitle => 'Importar tarefas de CSV';

  @override
  String get csvImportSubtitle =>
      'Revise um arquivo CSV antes de criar tarefas, projetos, etiquetas e status de fluxo de trabalho.';

  @override
  String get csvImportSelectFile => 'Escolher arquivo CSV';

  @override
  String get csvImportHumanGuideButton => 'Guia para pessoas';

  @override
  String get csvImportAgentGuideButton => 'Guia para agentes';

  @override
  String get csvImportHumanGuideTitle => 'Como preparar um arquivo CSV';

  @override
  String get csvImportAgentGuideTitle => 'Especificação CSV para agentes';

  @override
  String get csvImportCopy => 'Copiar';

  @override
  String get csvImportCopied => 'Copiado para a área de transferência.';

  @override
  String get csvImportPreviewTitle => 'Revisar importação';

  @override
  String get csvImportPreviewTasks => 'Tarefas';

  @override
  String get csvImportPreviewSubtasks => 'Subtarefas';

  @override
  String get csvImportPreviewNewProjects => 'Novos projetos';

  @override
  String get csvImportPreviewNewLabels => 'Novas etiquetas';

  @override
  String get csvImportPreviewNewStatuses => 'Novos status de fluxo de trabalho';

  @override
  String get csvImportNone => 'Nenhum';

  @override
  String get csvImportDuplicateWarning =>
      'Importar o mesmo arquivo novamente criará tarefas duplicadas.';

  @override
  String get csvImportConfirm => 'Importar';

  @override
  String get csvImportSuccess => 'Tarefas importadas';

  @override
  String get csvImportErrorTitle => 'Falha ao importar CSV';

  @override
  String get csvImportUnexpectedError => 'Não foi possível importar o arquivo.';

  @override
  String get csvImportHumanGuide =>
      '1. Salve o arquivo como CSV UTF-8. Use vírgula (recomendado) ou ponto e vírgula como separador.\n\n2. A coluna content é obrigatória. Você também pode usar: key, description, project, labels, priority, due_date, start_at, end_at, time_zone, recurrence, recurrence_interval, deadline, estimate, kanban_status, parent_key.\n\n3. Coloque uma tarefa aberta por linha. Separe etiquetas com |. A prioridade vai de 1 a 4; vazio significa 4. Projeto vazio significa Entrada, e status vazio significa Pendências. Projetos, etiquetas e status abertos ausentes são criados automaticamente.\n\n4. Para uma tarefa de dia inteiro, use due_date no formato YYYY-MM-DD. Para uma tarefa com horário, preencha start_at e end_at no formato RFC3339 com deslocamento UTC e informe um time_zone IANA, como Europe/Moscow.\n\n5. Para criar subtarefas, dê à linha principal uma key única e use esse valor no parent_key da subtarefa. A tarefa principal pode aparecer depois no arquivo. A subtarefa deve usar o mesmo projeto da principal.\n\n6. O Pomodoist valida todo o arquivo e mostra uma prévia antes de importar. Nada é salvo se alguma linha for inválida. Reimportar cria tarefas duplicadas.';

  @override
  String get settingsConnectedAgentsTitle => 'Agentes conectados';

  @override
  String get settingsConnectedAgentsLoading => 'Carregando agentes conectados…';

  @override
  String get settingsConnectedAgentsEmpty => 'Nenhum agente conectado.';

  @override
  String get settingsConnectedAgentsLoadError =>
      'Não foi possível carregar os agentes conectados.';

  @override
  String get settingsConnectedAgentsUnknownClient => 'Agente';

  @override
  String settingsConnectedAgentsConnectedOn(String date) {
    return 'Conectado em $date';
  }

  @override
  String get settingsConnectedAgentsRevoke => 'Revogar acesso';

  @override
  String get settingsConnectedAgentsRevokeConfirmTitle =>
      'Revogar acesso do agente?';

  @override
  String settingsConnectedAgentsRevokeConfirmMessage(String clientName) {
    return 'Revogar o acesso de $clientName ao Pomodoist?';
  }

  @override
  String get settingsConnectedAgentsRevokeError =>
      'Não foi possível revogar o acesso. Tente novamente.';

  @override
  String get settingsLanguageTitle => 'Idioma';

  @override
  String get settingsLanguageSubtitle => 'Escolha o idioma do app.';

  @override
  String get settingsLanguageSystem => 'Padrão do sistema';

  @override
  String get settingsVoiceTranscriptionTitle => 'Transcrição de voz';

  @override
  String get settingsVoiceTranscriptionSubtitle =>
      'Escolha como as gravações são convertidas em texto neste dispositivo.';

  @override
  String get settingsVoiceTranscriptionSystem => 'Sistema (Apple)';

  @override
  String get settingsVoiceTranscriptionCloud => 'Nuvem';

  @override
  String get settingsVoiceTranscriptionCloudDescription =>
      'A transcrição na nuvem envia áudio ao Pomodoist e requer conexão com a internet.';

  @override
  String get settingsVoiceTranscriptionCloudRequiresSignIn =>
      'Entre para usar a transcrição na nuvem. Até lá, a transcrição do sistema permanece ativa.';

  @override
  String get settingsThemeTitle => 'Tema';

  @override
  String get settingsThemeSubtitle => 'Escolha a aparência do app.';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsTimerVisualTitle => 'Timer Pomodoro';

  @override
  String get settingsTimerVisualSubtitle =>
      'Escolha como o progresso aparece na tela de foco.';

  @override
  String get settingsTimerVisualBar => 'Barra';

  @override
  String get settingsTimerVisualCircle => 'Círculo';

  @override
  String get settingsReturnRemindersTitle => 'Lembretes de retorno';

  @override
  String get settingsReturnRemindersSubtitle =>
      'Um lembrete às 20:30 se você não concluiu nenhuma tarefa hoje.';

  @override
  String get settingsDefaultTimedBlockTitle =>
      'Duração padrão do bloco no calendário';

  @override
  String get settingsDefaultTimedBlockSubtitle =>
      'Ao informar apenas um horário, novas tarefas usam esta duração no calendário.';

  @override
  String get settingsDefaultTimedBlockCustomLabel => 'Duração personalizada';

  @override
  String get settingsDefaultTimedBlockError => 'Digite de 1 a 480 minutos.';

  @override
  String get settingsTaskTimeDisplayTitle => 'Exibição de horário das tarefas';

  @override
  String get settingsTaskTimeDisplaySubtitle =>
      'Escolha como exibir os horários das tarefas.';

  @override
  String get settingsTaskTimeDisplaySmart => 'Inteligente';

  @override
  String get settingsTaskTimeDisplayRange => 'Horário de início e fim';

  @override
  String get settingsTaskTimeDisplayStartOnly => 'Apenas horário de início';

  @override
  String get taskTimeStatusFuture => 'Em breve';

  @override
  String get taskTimeStatusFocused => 'Em foco';

  @override
  String get taskTimeStatusCurrent => 'Em andamento';

  @override
  String get taskTimeStatusOverdue => 'Atrasada';

  @override
  String get taskTimeStatusCompleted => 'Concluída';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get localUser => 'Usuário local';

  @override
  String get addTask => 'Adicionar tarefa';

  @override
  String get quickAddHint => 'Criar sincronização amanhã p1 #App @coding 4p';

  @override
  String couldNotAddTask(Object error) {
    return 'Não foi possível adicionar a tarefa: $error';
  }

  @override
  String get taskCreateFailed =>
      'Não foi possível criar a tarefa. Tente novamente.';

  @override
  String couldNotAddProject(Object error) {
    return 'Não foi possível adicionar o projeto: $error';
  }

  @override
  String tasksCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarefas adicionadas',
      one: '1 tarefa adicionada',
    );
    return '$_temp0';
  }

  @override
  String get voiceQuickAdd => 'Adição rápida por voz';

  @override
  String get voiceTitle => 'Adicionar por voz';

  @override
  String get voiceRecord => 'Gravar';

  @override
  String get voiceAgain => 'Novamente';

  @override
  String get voiceStop => 'Parar';

  @override
  String voiceAddCount(int count) {
    return 'Adicionar $count';
  }

  @override
  String voiceTaskLabel(int index) {
    return 'Tarefa $index';
  }

  @override
  String get voiceRemoveTask => 'Remover';

  @override
  String get voiceInstruction => 'Toque em gravar e dite as tarefas.';

  @override
  String get voiceStatusIdle => 'Apenas entrada do microfone integrado';

  @override
  String get voiceStatusRequestingPermission => 'Solicitando acesso';

  @override
  String get voiceStatusRecording => 'Ouvindo pelo microfone integrado';

  @override
  String get voiceStatusTranscribing => 'Transcrevendo gravação';

  @override
  String get voiceStatusCanceled => 'Gravação cancelada';

  @override
  String get voiceStatusUnsupported => 'Plataforma não compatível';

  @override
  String get voiceStatusError => 'Não foi possível reconhecer a fala';

  @override
  String get voiceStatusAnalyzing => 'Separando em tarefas';

  @override
  String get voiceStatusReview => 'Revise as tarefas antes de adicionar';

  @override
  String get voiceStepRecord => 'Gravar';

  @override
  String get voiceStepText => 'Texto';

  @override
  String get voiceStepAnalyze => 'Analisar';

  @override
  String get voiceStepReview => 'Revisar';

  @override
  String get voiceAnalyzing => 'O Pomodoist está separando a fala em tarefas';

  @override
  String get voiceFallbackError =>
      'O Pomodoist não conseguiu processar a fala; um rascunho foi mantido para edição manual.';

  @override
  String get voiceMicrophoneUnavailable =>
      'O microfone está indisponível. Encerre chamadas ou conversas por voz ativas e tente novamente.';

  @override
  String get voiceSmartMode => 'Modo inteligente';

  @override
  String get voiceRetryTranscription => 'Tentar transcrição novamente';

  @override
  String get voiceRecordingSaved =>
      'Gravação salva neste dispositivo. Você pode tentar novamente sem regravar.';

  @override
  String get voiceAllowAccess => 'Permitir acesso';

  @override
  String get voiceOpenMicrophoneSettings => 'Abrir configurações do microfone';

  @override
  String get voiceOpenSpeechSettings =>
      'Abrir configurações de reconhecimento de fala';

  @override
  String get voiceEnableDictation => 'Ativar Ditado';

  @override
  String get voiceUseCloudTranscription => 'Usar transcrição na nuvem';

  @override
  String get voiceMicrophoneDenied =>
      'Permita o acesso ao microfone nas configurações do sistema.';

  @override
  String get voiceSpeechDenied =>
      'Permita o reconhecimento de fala nas configurações do sistema.';

  @override
  String get voiceAccessRestricted =>
      'O acesso está restrito pelo administrador ou pelo Tempo de Uso.';

  @override
  String get voiceDictationDisabled =>
      'Ative Ditado em Ajustes do Sistema → Teclado → Ditado e selecione seu idioma. Depois tente novamente.';

  @override
  String get voiceServiceUnavailable =>
      'O reconhecimento de fala está indisponível. Verifique sua conexão. No Mac, confira também Ajustes do Sistema → Teclado → Ditado e seu idioma.';

  @override
  String get voiceCloudServiceUnavailable =>
      'A transcrição na nuvem falhou. Verifique a internet e tente transcrever a gravação salva novamente.';

  @override
  String get voiceLocaleUnsupported =>
      'O reconhecimento de fala do sistema não oferece suporte ao idioma selecionado neste dispositivo.';

  @override
  String get voiceNetworkUnavailable =>
      'O reconhecimento de fala precisa de internet para este idioma. Reconecte e tente novamente.';

  @override
  String get voiceSettingsFailed =>
      'Não foi possível abrir as configurações. Abra-as manualmente e confira o acesso ao microfone e ao reconhecimento de fala. No Mac, confira também Teclado → Ditado.';

  @override
  String get voiceRetryAnalysis => 'Tentar análise novamente';

  @override
  String get screenInboxSubtitle => 'Registre tarefas antes de organizá-las.';

  @override
  String get priorityMatrixSubtitle =>
      'Arraste tarefas entre prioridades. As datas apenas ordenam tarefas dentro de uma prioridade.';

  @override
  String get priorityMatrixP1Title => 'Fazer agora';

  @override
  String get priorityMatrixP2Title => 'Agendar';

  @override
  String get priorityMatrixP3Title => 'Delegar';

  @override
  String get priorityMatrixP4Title => 'Descartar';

  @override
  String get priorityMatrixAxisUrgent => 'Urgente';

  @override
  String get priorityMatrixAxisNotUrgent => 'Não urgente';

  @override
  String get priorityMatrixAxisImportant => 'Importante';

  @override
  String get priorityMatrixAxisNotImportant => 'Não importante';

  @override
  String get timelineSubtitle => 'Planeje um dia em uma grade de horários.';

  @override
  String get timelineAllDay => 'Dia inteiro';

  @override
  String get timelineBeforeHours => 'Antes das horas visíveis';

  @override
  String get timelineAfterHours => 'Após as horas visíveis';

  @override
  String get timelineVisibleHours => 'Horas visíveis';

  @override
  String get timelineStartHour => 'Início';

  @override
  String get timelineEndHour => 'Fim';

  @override
  String get timelineZoomOut => 'Diminuir zoom';

  @override
  String get timelineZoomIn => 'Aumentar zoom';

  @override
  String timelineAddTimedHint(String time) {
    return 'Tarefa para $time';
  }

  @override
  String get timelineAddAllDayHint => 'Tarefa de dia inteiro';

  @override
  String get timelineNoAllDayTasks => 'Nenhuma tarefa de dia inteiro';

  @override
  String get timelineNoTimedTasks => 'Nenhuma tarefa com horário';

  @override
  String get timelinePreviousDay => 'Dia anterior';

  @override
  String get timelineNextDay => 'Próximo dia';

  @override
  String get timelinePickDate => 'Escolher data';

  @override
  String get upcomingPreviousPeriod => 'Período anterior';

  @override
  String get upcomingNextPeriod => 'Próximo período';

  @override
  String get upcomingOpenDatePicker => 'Abrir seletor de data';

  @override
  String upcomingTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarefas',
      one: '1 tarefa',
      zero: 'Nenhuma tarefa',
    );
    return '$_temp0';
  }

  @override
  String screenTodayFocusSummary(int planned, int completed, String focus) {
    return 'Carga de foco: $planned intervalos - Concluídos: $completed - Foco: $focus';
  }

  @override
  String get screenUpcomingSubtitle => 'Tarefas planejadas após hoje.';

  @override
  String screenUpcomingSelectedSubtitle(String date) {
    return 'Tarefas agendadas para $date.';
  }

  @override
  String get noTasksHere => 'Nenhuma tarefa aqui';

  @override
  String get noUpcomingTasks => 'Nenhuma tarefa com data';

  @override
  String get noTasksForDay => 'Nenhuma tarefa agendada para este dia';

  @override
  String failedToLoadTasks(Object error) {
    return 'Falha ao carregar tarefas: $error';
  }

  @override
  String get searchTasks => 'Buscar tarefas';

  @override
  String get searchStartTyping => 'Comece a digitar para buscar tarefas';

  @override
  String get searchNoMatches => 'Nenhuma tarefa encontrada';

  @override
  String failedToSearchTasks(Object error) {
    return 'Falha ao buscar tarefas: $error';
  }

  @override
  String get previousMonth => 'Mês anterior';

  @override
  String get nextMonth => 'Próximo mês';

  @override
  String get clearDateFilter => 'Limpar filtro de data';

  @override
  String get weekMon => 'Seg';

  @override
  String get weekTue => 'Ter';

  @override
  String get weekWed => 'Qua';

  @override
  String get weekThu => 'Qui';

  @override
  String get weekFri => 'Sex';

  @override
  String get weekSat => 'Sáb';

  @override
  String get weekSun => 'Dom';

  @override
  String get browseTitle => 'Explorar';

  @override
  String get unifiedAccount => 'Conta unificada';

  @override
  String accountUnavailable(Object error) {
    return 'Conta indisponível: $error';
  }

  @override
  String get signOut => 'Sair';

  @override
  String get deleteAccount => 'Excluir conta';

  @override
  String get deleteAccountConfirmation =>
      'Isso exclui permanentemente sua conta, dados na nuvem e tarefas, projetos e histórico de foco locais. Esta ação não pode ser desfeita. Assinaturas das lojas não são canceladas automaticamente. Se usou Iniciar sessão com a Apple, revogue o acesso do Pomodoist separadamente nos ajustes da sua Conta Apple.';

  @override
  String get manageSignInWithApple => 'Gerenciar Iniciar sessão com a Apple';

  @override
  String get deleteAccountFinalConfirmation =>
      'Tem certeza absoluta? Esta é a confirmação final.';

  @override
  String deleteAccountError(Object error) {
    return 'Não foi possível excluir a conta: $error';
  }

  @override
  String get accountDeleted => 'Conta excluída.';

  @override
  String get accountDeletedLocalCleanupError =>
      'Sua conta foi excluída, mas não foi possível limpar os dados locais. Limpe os dados do app antes de usar este dispositivo novamente.';

  @override
  String get browseSevenDays => '7 dias';

  @override
  String get browseOpenNow => 'Abertas agora';

  @override
  String get browseQueueLoading => 'Carregando alterações pendentes…';

  @override
  String get browseQueueUnavailable =>
      'Não foi possível carregar as alterações pendentes.';

  @override
  String get browseQueueExplanation =>
      'Exibe alterações locais aguardando envio. Uma fila vazia não confirma que todos os dispositivos estão atualizados.';

  @override
  String get productivityTitle => 'Produtividade';

  @override
  String get achievementsTitle => 'Conquistas';

  @override
  String get allTimeLabel => 'Todo o período';

  @override
  String get lastSevenDaysLabel => 'Últimos 7 dias';

  @override
  String get noWeeklyStatsLabel => 'Ainda não há dados de foco ou tarefas';

  @override
  String get completedFocuses => 'Focos concluídos';

  @override
  String get completedTasks => 'Tarefas concluídas';

  @override
  String get unlocked => 'Desbloqueado';

  @override
  String get locked => 'Bloqueado';

  @override
  String get progressLabel => 'Progresso';

  @override
  String get focusAchievements => 'Conquistas de foco';

  @override
  String get taskAchievements => 'Conquistas de tarefas';

  @override
  String get comboAchievements => 'Conquistas de combo';

  @override
  String get focusIntervals => 'Intervalos de foco';

  @override
  String get focusTime => 'Tempo de foco';

  @override
  String get openTasks => 'Tarefas abertas';

  @override
  String get plannedIntervals => 'Intervalos planejados';

  @override
  String get labelsTitle => 'Etiquetas';

  @override
  String get newProject => 'Novo projeto';

  @override
  String get newLabel => 'Nova etiqueta';

  @override
  String get syncReadyQueue => 'Fila pronta para sincronização';

  @override
  String pendingLocalCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comandos locais pendentes',
      one: '1 comando local pendente',
      zero: 'Nenhum comando local pendente',
    );
    return '$_temp0';
  }

  @override
  String failedToLoadProjects(Object error) {
    return 'Falha ao carregar projetos: $error';
  }

  @override
  String failedToLoadLabels(Object error) {
    return 'Falha ao carregar etiquetas: $error';
  }

  @override
  String get addProject => 'Adicionar projeto';

  @override
  String get projectName => 'Nome do projeto';

  @override
  String get addLabel => 'Adicionar etiqueta';

  @override
  String get labelName => 'Nome da etiqueta';

  @override
  String couldNotAddLabel(Object error) {
    return 'Não foi possível adicionar a etiqueta: $error';
  }

  @override
  String projectsUnavailable(Object error) {
    return 'Projetos indisponíveis: $error';
  }

  @override
  String get projectsUnavailableShort => 'Projetos indisponíveis';

  @override
  String get noProjects => 'Nenhum projeto';

  @override
  String get searchProjects => 'Buscar projetos';

  @override
  String get searchLabels => 'Buscar etiquetas';

  @override
  String get archivedProjectsOnly => 'Apenas projetos arquivados';

  @override
  String projectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projetos',
      one: '1 projeto',
    );
    return '$_temp0';
  }

  @override
  String get noLabels => 'Nenhuma etiqueta';

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
  String get renameProject => 'Renomear projeto';

  @override
  String get deleteProject => 'Excluir projeto';

  @override
  String get deleteLabel => 'Excluir etiqueta';

  @override
  String deleteProjectConfirmation(String name) {
    return 'Excluir \"$name\"? As tarefas deste projeto serão movidas para a Entrada.';
  }

  @override
  String deleteLabelConfirmation(String name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String couldNotDeleteProject(Object error) {
    return 'Não foi possível excluir o projeto: $error';
  }

  @override
  String couldNotDeleteLabel(Object error) {
    return 'Não foi possível excluir a etiqueta: $error';
  }

  @override
  String projectsCountCompact(int count) {
    return 'Projetos: $count';
  }

  @override
  String get collapseProjects => 'Recolher projetos';

  @override
  String get expandProjects => 'Expandir projetos';

  @override
  String get projectFallbackTitle => 'Projeto';

  @override
  String get projectSubtitle =>
      'Visualização em lista — quadro e calendário estão planejados.';

  @override
  String get reportsTitle => 'Relatórios';

  @override
  String get reportsFocusedDay => 'Um dia de foco até agora';

  @override
  String get reportsThisWeek => 'Sua semana em foco';

  @override
  String get reportsNextAchievement => 'Próxima conquista';

  @override
  String get viewAllAchievements => 'Ver todas as conquistas';

  @override
  String viewAllAchievementsCount(int count) {
    return 'Ver todas as $count';
  }

  @override
  String get allAchievementsUnlocked => 'Todas as conquistas desbloqueadas';

  @override
  String get noAchievementsYet => 'Nenhuma conquista ainda';

  @override
  String failedToLoadAchievements(Object error) {
    return 'Falha ao carregar conquistas: $error';
  }

  @override
  String get backToReports => 'Voltar aos relatórios';

  @override
  String reportsIntervalProgressSemantics(int completed, int target) {
    return '$completed de $target intervalos de foco concluídos';
  }

  @override
  String reportsIntervalCountSemantics(int completed) {
    return '$completed intervalos de foco concluídos; sem meta definida';
  }

  @override
  String reportsWeeklyChartSemantics(String summary) {
    return 'Tempo de foco nos últimos 7 dias: $summary';
  }

  @override
  String failedToLoadReports(Object error) {
    return 'Falha ao carregar relatórios: $error';
  }

  @override
  String get taskNotFound => 'Tarefa não encontrada';

  @override
  String get taskTitleHint => 'Título da tarefa';

  @override
  String get taskComment => 'Comentário';

  @override
  String get taskCommentHint => 'Adicionar um comentário';

  @override
  String get subtasks => 'Subtarefas';

  @override
  String get addSubtask => 'Adicionar subtarefa';

  @override
  String get addSubtaskHint => 'Adicionar uma subtarefa';

  @override
  String get noSubtasks => 'Ainda não há subtarefas.';

  @override
  String get makeParentTask => 'Tornar tarefa principal';

  @override
  String couldNotMoveTask(Object error) {
    return 'Não foi possível mover a tarefa: $error';
  }

  @override
  String get scheduleTitle => 'Agendamento';

  @override
  String get allDay => 'Dia inteiro';

  @override
  String get timedBlock => 'Bloco de horário';

  @override
  String get recurrenceTitle => 'Repetir';

  @override
  String get recurrenceNeedsSchedule =>
      'Adicione uma data ou horário antes de repetir.';

  @override
  String get recurrenceIntervalLabel => 'Intervalo';

  @override
  String get recurrenceUnitDay => 'Dias';

  @override
  String get recurrenceUnitWeek => 'Semanas';

  @override
  String get recurrenceUnitMonth => 'Meses';

  @override
  String get recurrenceInvalidInterval => 'Digite de 1 a 999.';

  @override
  String recurrenceEveryDays(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'a cada $interval dias',
      one: 'todos os dias',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'a cada $interval semanas',
      one: 'todas as semanas',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int interval) {
    String _temp0 = intl.Intl.pluralLogic(
      interval,
      locale: localeName,
      other: 'a cada $interval meses',
      one: 'todos os meses',
    );
    return '$_temp0';
  }

  @override
  String get noDate => 'Sem data';

  @override
  String get calendarNotLinked => 'Calendário não vinculado';

  @override
  String get calendarLinked => 'Google Agenda vinculado';

  @override
  String focusProgress(int completed, int total) {
    return '$completed/$total focos';
  }

  @override
  String get startFocus => 'Iniciar foco';

  @override
  String get focusStarted => 'Foco iniciado';

  @override
  String get taskReopened => 'Tarefa reaberta';

  @override
  String get taskCompleted => 'Tarefa concluída';

  @override
  String get taskDeleted => 'Tarefa excluída';

  @override
  String get recurringDeleteTitle => 'Excluir tarefa recorrente?';

  @override
  String get recurringDeleteMessage =>
      'Esta tarefa pertence a uma série recorrente.';

  @override
  String get recurringDeleteThis => 'Excluir esta tarefa';

  @override
  String get recurringDeleteThisAndFollowing => 'Excluir esta e as seguintes';

  @override
  String get markOpen => 'Marcar como aberta';

  @override
  String get markComplete => 'Marcar como concluída';

  @override
  String get focusHistory => 'Histórico de foco';

  @override
  String failedToLoadTask(Object error) {
    return 'Falha ao carregar tarefa: $error';
  }

  @override
  String get noFocusIntervals => 'Ainda não há intervalos de foco.';

  @override
  String get today => 'Hoje';

  @override
  String get tomorrow => 'Amanhã';

  @override
  String get yesterday => 'Ontem';

  @override
  String get clearDate => 'Limpar data';

  @override
  String priority(int priority) {
    return 'Prioridade $priority';
  }

  @override
  String get focusTitle => 'Foco';

  @override
  String focusLoadError(Object error) {
    return 'Não foi possível carregar o foco: $error';
  }

  @override
  String get focusViewFull => 'Completa';

  @override
  String get focusViewMinimal => 'Minimalista';

  @override
  String get focusSwitchToFullView => 'Mudar para completa';

  @override
  String get focusSwitchToMinimalView => 'Mudar para minimalista';

  @override
  String get focusActionFailed =>
      'Não foi possível atualizar o foco. Tente novamente.';

  @override
  String get noActiveSession => 'Nenhuma sessão ativa';

  @override
  String get focusIdleSubtitle =>
      'Inicie um intervalo de foco independente ou a partir de uma tarefa.';

  @override
  String get noPreset => 'Nenhuma predefinição';

  @override
  String get preparingFocus => 'Preparando foco';

  @override
  String get moreFocusOptions => 'Mais opções de foco';

  @override
  String get moreFocusActions => 'Mais ações de foco';

  @override
  String get preset => 'Predefinição';

  @override
  String get newPreset => 'Nova predefinição';

  @override
  String get customize => 'Personalizar';

  @override
  String get customizePreset => 'Personalizar predefinição';

  @override
  String get startInterval => 'Iniciar intervalo';

  @override
  String get intervalStarted => 'Intervalo iniciado';

  @override
  String get intervalCompleted => 'Intervalo concluído';

  @override
  String get focusStopped => 'Foco interrompido';

  @override
  String get focusCompletionTitle => 'Ótimo trabalho!';

  @override
  String get focusCompletionLinkedSubtitle =>
      'Todos os intervalos de foco planejados para esta tarefa foram concluídos.';

  @override
  String get focusCompletionStandaloneSubtitle =>
      'Seu ciclo de foco foi concluído.';

  @override
  String get focusCompletionQuestion => 'Pronto para concluir esta tarefa?';

  @override
  String get focusCompletionCompleteTask => 'Concluir tarefa';

  @override
  String get focusCompletionKeepOpen => 'Manter tarefa aberta';

  @override
  String get focusCompletionDone => 'Concluído';

  @override
  String get focusCompletionNextTask => 'Próxima tarefa agendada';

  @override
  String focusCompletionTaskError(Object error) {
    return 'Não foi possível concluir a tarefa: $error';
  }

  @override
  String get completeInterval => 'Concluir intervalo';

  @override
  String get logDistraction => 'Registrar distração';

  @override
  String get workInterval => 'Intervalo de trabalho';

  @override
  String get work => 'Trabalho';

  @override
  String get shortBreak => 'Pausa curta';

  @override
  String get breakLabel => 'Pausa';

  @override
  String get longBreak => 'Pausa longa';

  @override
  String readyLabel(String label) {
    return 'Pronto: $label';
  }

  @override
  String get readyShort => 'Pronto';

  @override
  String focusTimerTotal(String duration) {
    return 'de $duration';
  }

  @override
  String focusSessionProgress(int current, int total) {
    return 'Sessão $current de $total';
  }

  @override
  String focusRhythmPreviewSummary(int count) {
    return 'Prévia do ritmo de foco, $count etapas';
  }

  @override
  String focusRhythmSummary(
    int current,
    int total,
    String phase,
    String status,
  ) {
    return 'Ritmo de foco, etapa $current de $total: $phase, $status';
  }

  @override
  String focusTimerSummary(
    String phase,
    String status,
    String remaining,
    String total,
  ) {
    return '$phase, $status, restam $remaining, total $total';
  }

  @override
  String get focusStatusRunning => 'Em andamento';

  @override
  String get focusStatusPaused => 'Pausado';

  @override
  String focusWorkProgress(int completed, int total) {
    return '$completed/$total trabalho';
  }

  @override
  String intervalNumber(int number) {
    return 'Intervalo $number';
  }

  @override
  String focusIntervalSummary(int completed, int total, int number) {
    return '$completed/$total trabalho - Intervalo $number';
  }

  @override
  String get pause => 'Pausar';

  @override
  String get resume => 'Retomar';

  @override
  String get presetForNextIntervals =>
      'Predefinição para os próximos intervalos';

  @override
  String usePreset(String name) {
    return 'Usar $name';
  }

  @override
  String minutesWork(int minutes) {
    return '${minutes}min trabalho';
  }

  @override
  String minutesShort(int minutes) {
    return '${minutes}min curta';
  }

  @override
  String minutesLong(int minutes) {
    return '${minutes}min longa';
  }

  @override
  String longEvery(int count) {
    return 'Longa a cada $count';
  }

  @override
  String get autoBreaks => 'Pausas automáticas';

  @override
  String get autoWork => 'Trabalho automático';

  @override
  String get noPause => 'Sem pausa';

  @override
  String get focusPauseUnavailable => 'Pausa indisponível nesta predefinição';

  @override
  String get strict => 'Rígido';

  @override
  String get flexible => 'Flexível';

  @override
  String get name => 'Nome';

  @override
  String get workField => 'Trabalho';

  @override
  String get shortField => 'Curta';

  @override
  String get longField => 'Longa';

  @override
  String get every => 'A cada';

  @override
  String get minutesSuffix => 'min';

  @override
  String get makeDefault => 'Definir como padrão';

  @override
  String get autoStartBreaks => 'Iniciar pausas automaticamente';

  @override
  String get autoStartWork => 'Iniciar trabalho automaticamente';

  @override
  String get allowPause => 'Permitir pausa';

  @override
  String get strictMode => 'Modo rígido';

  @override
  String get nameRequired => 'O nome é obrigatório';

  @override
  String get nameMustBeUnique => 'O nome deve ser único';

  @override
  String get googleCalendarTitle => 'Google Agenda';

  @override
  String get googleCalendarConnectedSubtitle =>
      'A sincronização bidirecional está ativa para o calendário Pomodoist.';

  @override
  String get googleCalendarDisconnectedSubtitle =>
      'Conecte uma conta Google para sincronizar tarefas agendadas.';

  @override
  String get googleCalendarConnectedOnAnotherDeviceSubtitle =>
      'A sincronização do Google Agenda está em outro dispositivo. Os dados do Pomodoist continuam sincronizando aqui.';

  @override
  String get syncNow => 'Sincronizar agora';

  @override
  String get useThisDevice => 'Usar este dispositivo';

  @override
  String get connect => 'Conectar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String failedToLoadIntegration(Object error) {
    return 'Falha ao carregar integração: $error';
  }

  @override
  String googleCalendarFailed(String message) {
    return 'Falha no Google Agenda: $message';
  }

  @override
  String get googleAuthRequired =>
      'É necessária autorização do Google Agenda. Entre novamente e execute Sincronizar agora.';

  @override
  String get googleSignInNotConfigured =>
      'O login do Google não está configurado. Defina GOOGLE_CLIENT_ID e GOOGLE_REVERSED_CLIENT_ID para este destino iOS.';

  @override
  String get googleCallbackNotConfigured =>
      'O callback de login do Google não está configurado. Defina GOOGLE_REVERSED_CLIENT_ID em ios/Flutter/GoogleOAuth.xcconfig.';

  @override
  String get googleWebButtonFirst =>
      'Na web, clique primeiro no botão de login do Google e depois em Conectar.';

  @override
  String get googleAccessDenied =>
      'O acesso ao Google foi negado. Adicione esta conta Google como usuário de teste OAuth ou publique e verifique o app OAuth.';

  @override
  String get status => 'Status';

  @override
  String get account => 'Conta';

  @override
  String get calendar => 'Calendário';

  @override
  String get calendarId => 'ID do calendário';

  @override
  String get lastSync => 'Última sincronização';

  @override
  String get notConnected => 'Não conectado';

  @override
  String get notCreated => 'Não criado';

  @override
  String get never => 'Nunca';

  @override
  String durationMinutes(int minutes) {
    return '${minutes}min';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String get projectIcon => 'Ícone do projeto';

  @override
  String projectIconOption(int number) {
    return 'Ícone $number';
  }

  @override
  String get projectColor => 'Cor do projeto';

  @override
  String projectColorOption(int number) {
    return 'Cor $number';
  }

  @override
  String get addProjectToFavorites => 'Adicionar projeto aos favoritos';

  @override
  String get removeProjectFromFavorites => 'Remover projeto dos favoritos';

  @override
  String get timelineProjectsMenu => 'Gerenciar projetos da linha do tempo';

  @override
  String get timelineShowProject => 'Mostrar projeto na linha do tempo';

  @override
  String get timelineHideProject => 'Ocultar projeto temporário';

  @override
  String get timelineCollapseProject => 'Recolher ramificação do projeto';

  @override
  String get timelineExpandProject => 'Expandir ramificação do projeto';

  @override
  String get timelineCurrentTime => 'Hora atual';

  @override
  String couldNotUpdateProject(Object error) {
    return 'Não foi possível atualizar o projeto: $error';
  }

  @override
  String get commonDone => 'Concluído';

  @override
  String get taskSelect => 'Selecionar';

  @override
  String taskSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionadas',
      one: '1 selecionada',
      zero: '0 selecionadas',
    );
    return '$_temp0';
  }

  @override
  String get taskSelectAll => 'Selecionar todas';

  @override
  String get taskDeselectAll => 'Desmarcar todas';

  @override
  String get taskDue => 'Prazo';

  @override
  String get taskProject => 'Projeto';

  @override
  String get taskLabels => 'Etiquetas';

  @override
  String get taskPriority => 'Prioridade';

  @override
  String get taskMore => 'Mais';

  @override
  String get taskSchedule => 'Agendar';

  @override
  String get taskMove => 'Mover';

  @override
  String get taskDuplicate => 'Duplicar';

  @override
  String get taskDuplicateTitle => 'Duplicar tarefas';

  @override
  String get taskDuplicateSelectedOnly => 'Apenas selecionadas';

  @override
  String get taskDuplicateWithSubtasks => 'Com subtarefas';

  @override
  String get taskWeekend => 'Este fim de semana';

  @override
  String get taskNextWeek => 'Próxima semana';

  @override
  String get taskEnterDue => 'Digite a data ou horário do prazo';

  @override
  String get taskInvalidDue => 'Digite uma data ou horário válido';

  @override
  String get taskClearDue => 'Limpar prazo';

  @override
  String get taskDeleteSelectedTitle => 'Excluir tarefas selecionadas?';

  @override
  String get taskDeleteSelectedMessage =>
      'Você pode desfazer esta ação por 7 segundos.';

  @override
  String get taskCompleteSelected => 'Concluir selecionadas';

  @override
  String get taskReopenSelected => 'Reabrir selecionadas';

  @override
  String taskActionFailedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível atualizar $count tarefas',
      one: 'Não foi possível atualizar 1 tarefa',
    );
    return '$_temp0';
  }

  @override
  String get voiceCollapse => 'Recolher painel de voz';

  @override
  String get voiceExpand => 'Expandir painel de voz';

  @override
  String get voiceMovePanel => 'Mover painel de voz';

  @override
  String get themeClassic => 'Clássico';

  @override
  String get themeOcean => 'Oceano';

  @override
  String get themeForest => 'Floresta';

  @override
  String get themeCustomize => 'Personalizar';

  @override
  String get themeEditorTitle => 'Editar tema';

  @override
  String get themeLivePreview =>
      'As alterações aparecem em todo o app. Cancelar restaura seu tema anterior.';

  @override
  String get themeSaveError =>
      'Não foi possível salvar o tema. Suas alterações continuam aqui; tente novamente.';

  @override
  String get themeLoadError => 'Não foi possível carregar seus temas.';

  @override
  String get themeColorsSurfaces => 'Plano de fundo e superfícies';

  @override
  String get themeColorsText => 'Texto';

  @override
  String get themeColorsAccent => 'Destaque';

  @override
  String get themeColorsStatus => 'Cores de status';

  @override
  String get themeInvalidHex =>
      'Digite uma cor HEX de seis dígitos, como #2563EB.';

  @override
  String get themeLowContrast =>
      'Baixo contraste: alguns textos podem ser difíceis de ler.';

  @override
  String get themePreviewTask => 'Planeje seu dia';

  @override
  String get themePreviewSecondary => 'Um pouco de foco, todos os dias.';

  @override
  String get themeColorCanvas => 'Plano de fundo';

  @override
  String get themeColorSurface => 'Superfície';

  @override
  String get themeColorSurfaceTint => 'Superfície secundária';

  @override
  String get themeColorSurfaceHover => 'Superfície ao passar o cursor';

  @override
  String get themeColorPrimaryText => 'Texto principal';

  @override
  String get themeColorSecondaryText => 'Texto secundário';

  @override
  String get themeColorMutedText => 'Texto discreto';

  @override
  String get themeColorBorder => 'Borda';

  @override
  String get themeColorAccent => 'Texto e ícones de destaque';

  @override
  String get themeColorAccentFill => 'Preenchimento de destaque';

  @override
  String get themeColorAccentTint => 'Preenchimento de destaque suave';

  @override
  String get themeColorWarning => 'Aviso';

  @override
  String get themeColorInfo => 'Informação';

  @override
  String get themeColorSuccess => 'Sucesso';

  @override
  String get themeColorError => 'Erro';

  @override
  String get themeColorOverdue => 'Atrasado';

  @override
  String get themeColorOnAccent => 'Texto sobre destaque';

  @override
  String get themeColorOnError => 'Texto sobre erro';

  @override
  String todayTaskSummary(int tasks, int planned, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      tasks,
      locale: localeName,
      other: '$tasks tarefas',
      one: '1 tarefa',
    );
    String _temp1 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned sessões planejadas',
      one: '1 sessão planejada',
    );
    return '$_temp0 · $_temp1 · $time de foco';
  }

  @override
  String get todayFocusingOn => 'Focando em';

  @override
  String get openFocus => 'Abrir foco';

  @override
  String todayCompletedTasks(int count) {
    return 'Concluídas hoje · $count';
  }

  @override
  String get sidebarDaily => 'Diário';

  @override
  String get sidebarViews => 'Visualizações';

  @override
  String get quickAddResetDetails => 'Usar padrão';

  @override
  String get quickAddChangeTime => 'Alterar horário';

  @override
  String get quickAddProjectNameUnsupported =>
      'Este nome de projeto não pode ser inserido sem alterações.';

  @override
  String get themeSepia => 'Sépia';

  @override
  String get themeGraphite => 'Grafite';

  @override
  String get themeCustom => 'Personalizado';

  @override
  String get themeResetToClassic => 'Redefinir para Clássico';

  @override
  String get themeBackgroundKindTitle => 'Plano de fundo';

  @override
  String get themeBackgroundColor => 'Cor';

  @override
  String get themeBackgroundPhoto => 'Foto';

  @override
  String get themeBackgroundGlass => 'Vidro do macOS';

  @override
  String get themeBackgroundGlassHint =>
      'Aplica-se a todo o app e à adição rápida. O macOS controla o desfoque; o controle ajusta a tonalidade da paleta.';

  @override
  String get themeBackgroundGlassUnavailable =>
      'Disponível no app para macOS. Nesta plataforma, é usado um fundo sólido.';

  @override
  String get themeBackgroundTitle => 'Imagem de fundo';

  @override
  String get themeBackgroundMainOnly => 'Apenas área principal';

  @override
  String get themeBackgroundWholeApp => 'Todo o app';

  @override
  String get themeBackgroundSeparate => 'Fundos separados';

  @override
  String get themeBackgroundMain => 'Área principal';

  @override
  String get themeBackgroundSidebar => 'Barra lateral';

  @override
  String get themeBackgroundQuickAdd => 'Adição rápida';

  @override
  String get themeBackgroundChoose => 'Escolher foto';

  @override
  String get themeBackgroundReplace => 'Substituir foto';

  @override
  String get themeBackgroundRemove => 'Remover foto';

  @override
  String get themeBackgroundDim => 'Escurecimento';

  @override
  String get themeBackgroundBlur => 'Desfoque';

  @override
  String get themeBackgroundEmpty => 'Sem foto';

  @override
  String get themeBackgroundImageError =>
      'Não foi possível abrir esta imagem. Escolha outra foto.';

  @override
  String get themeBackgroundTooLarge => 'Escolha uma imagem de até 50 MB.';

  @override
  String get themeBackgroundLoading => 'Preparando imagem…';

  @override
  String get settingsTaskListStyle => 'Estilo da linha de tarefa';

  @override
  String get settingsTaskListStyleDescription =>
      'Escolha o novo layout ou mantenha as linhas clássicas.';

  @override
  String get settingsTaskListModern => 'Moderno';

  @override
  String get settingsTaskListClassic => 'Clássico';

  @override
  String get settingsTaskRowSpacing => 'Espaçamento das tarefas';

  @override
  String get settingsTaskRowSpacingCompact => 'Compacto';

  @override
  String get settingsTaskRowSpacingComfortable => 'Confortável';

  @override
  String get settingsTaskRowSpacingSpacious => 'Espaçoso';

  @override
  String get settingsSaveError =>
      'Não foi possível salvar a configuração. Tente novamente.';

  @override
  String get focusCompletionCompleteAndNext => 'Concluir e iniciar a próxima';

  @override
  String get focusCompletionStartNext => 'Iniciar próxima tarefa';

  @override
  String get focusCompletionRetry => 'Tentar novamente';

  @override
  String get searchAllProjects => 'Todos os projetos';

  @override
  String get searchStatusOpen => 'Abertas';

  @override
  String get searchStatusCompleted => 'Concluídas';

  @override
  String get searchStatusAll => 'Todos os status';

  @override
  String get searchClearFilters => 'Limpar filtros';

  @override
  String get searchEmptyDescription =>
      'Encontre uma tarefa pelo título ou descrição e filtre por projeto ou status.';

  @override
  String get searchNoMatchesDescription =>
      'Tente outra expressão ou limpe os filtros. Você também pode transformar este texto em uma nova tarefa.';

  @override
  String get searchCreateTask => 'Criar tarefa a partir do texto';

  @override
  String get taskListLoadError =>
      'Não foi possível carregar as tarefas. Tente novamente.';

  @override
  String get inboxEmptyTitle => 'Sua entrada está vazia';

  @override
  String get inboxEmptyDescription =>
      'Registre uma ideia aqui e decida depois quando trabalhar nela.';

  @override
  String get todayEmptyTitle => 'Nada agendado para hoje';

  @override
  String get todayEmptyDescription => 'Adicione uma tarefa para começar o dia.';

  @override
  String get todayEmptyCompletedTitle => 'A lista de hoje está em dia';

  @override
  String get todayEmptyCompletedDescription =>
      'Suas tarefas concluídas estão salvas abaixo. Adicione outra quando estiver pronto.';

  @override
  String get projectEmptyTitle => 'Ainda não há tarefas neste projeto';

  @override
  String get projectEmptyDescription =>
      'Adicione o primeiro passo rumo ao objetivo do projeto.';

  @override
  String get commandSearchPlaceholder => 'Buscar tarefas, projetos e ações';

  @override
  String get commandSearchTasks => 'Tarefas';

  @override
  String get commandSearchActions => 'Ações';

  @override
  String get commandSearchDictateTask => 'Ditar tarefa';

  @override
  String get commandSearchAllResults => 'Ver todos os resultados';

  @override
  String get commandSearchHint => '↑ ↓ Navegar · Enter Abrir · Esc Fechar';

  @override
  String get commandSearchNoMatches => 'Nenhuma tarefa ou projeto encontrado.';

  @override
  String get overdueTitle => 'Atrasadas';

  @override
  String overdueTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarefas atrasadas',
      one: '$count tarefa atrasada',
    );
    return '$_temp0';
  }

  @override
  String get overdueReview => 'Revisar';

  @override
  String get overdueEmpty => 'Nenhuma tarefa atrasada';

  @override
  String get taskFocusSwitchTitle => 'Trocar foco?';

  @override
  String taskFocusSwitchMessage(String task) {
    return 'A sessão atual será interrompida. Iniciar foco em “$task”?';
  }

  @override
  String get taskFocusSwitchConfirm => 'Trocar';

  @override
  String get labelIcon => 'Ícone da etiqueta';

  @override
  String get labelUpdateFailed =>
      'Não foi possível atualizar a etiqueta. Tente novamente.';

  @override
  String get labelNotFound => 'Etiqueta não encontrada';

  @override
  String get labelTasksSubtitle =>
      'Tarefas com esta etiqueta em todos os projetos';

  @override
  String labelIconOption(String icon) {
    String _temp0 = intl.Intl.selectLogic(icon, {
      'tag': 'Etiqueta',
      'bookmark': 'Marcador',
      'flag': 'Bandeira',
      'bolt': 'Raio',
      'lightbulb': 'Lâmpada',
      'clock': 'Relógio',
      'bell': 'Sino',
      'pin': 'Alfinete',
      'phone': 'Telefone',
      'mail': 'E-mail',
      'link': 'Link',
      'wrench': 'Chave inglesa',
      'other': 'Etiqueta',
    });
    return '$_temp0';
  }

  @override
  String get addSubproject => 'Criar subprojeto';

  @override
  String get moveProject => 'Mover projeto';

  @override
  String get projectTopLevel => 'Nível superior';

  @override
  String get projectMoveUp => 'Mover para cima';

  @override
  String get projectMoveDown => 'Mover para baixo';

  @override
  String projectParentName(String name) {
    return 'Projeto principal: $name';
  }

  @override
  String deleteProjectWithChildrenConfirmation(String name) {
    return 'Excluir \"$name\"? Os subprojetos subirão um nível. Apenas as tarefas deste projeto serão movidas para a Entrada.';
  }

  @override
  String get accountNickname => 'Apelido';

  @override
  String get accountChangeNickname => 'Alterar apelido';

  @override
  String get accountNicknameSaveError =>
      'Não foi possível salvar seu apelido. Tente novamente.';

  @override
  String get notificationTaskStarting => 'Hora da tarefa';

  @override
  String get notificationReturnTitle => 'Seu tomate está com saudade';

  @override
  String get notificationReturnBody =>
      'Um foco ou uma tarefa concluída já faz o dia valer a pena.';

  @override
  String get notificationFocusChannel => 'Foco';

  @override
  String get notificationFocusDescription =>
      'Notificações de conclusão de intervalos de foco';

  @override
  String get notificationReturnChannel => 'Lembretes de retorno';

  @override
  String get notificationReturnDescription =>
      'Lembretes gentis para voltar ao Pomodoist';

  @override
  String get notificationTaskChannel => 'Início de tarefa';

  @override
  String get notificationTaskDescription => 'Notificações de início de tarefas';

  @override
  String get notificationOpenApp => 'Abrir Pomodoist';

  @override
  String get notificationFocusCompleted => 'Intervalo de foco concluído';

  @override
  String get notificationLongBreakCompleted => 'Pausa longa concluída';

  @override
  String get notificationBreakCompleted => 'Pausa concluída';

  @override
  String get updateTitle => 'Atualização do Pomodoist';

  @override
  String get updateAction => 'Atualizar';

  @override
  String get updateCheck => 'Verificar atualizações';

  @override
  String get updateSettings => 'Atualizações';

  @override
  String get updateReceiveRc => 'Receber versões candidatas (RC)';

  @override
  String get updateStableChannel => 'Canal: versões estáveis';

  @override
  String get updateRcChannel => 'Canal: versões estáveis e RC';

  @override
  String get updateRcHelp =>
      'Versões RC podem conter erros. Versões alfa e beta não são incluídas.';

  @override
  String get updateRestart =>
      'O app será reiniciado. Seus dados serão preservados.';

  @override
  String get updateNotes => 'Notas da versão';

  @override
  String get updateOwnerManaged =>
      'Esta compilação é atualizada pelo responsável para preservar a configuração do servidor. Solicite a versão mais recente a ele.';

  @override
  String get updateUnsupported =>
      'Atualizações automáticas estão disponíveis no AppImage oficial para Linux. Use o gerenciador de pacotes para outras compilações.';

  @override
  String updateVersion(String value) {
    return 'Versão $value';
  }

  @override
  String get updatePhaseIdle => 'Você pode verificar a qualquer momento.';

  @override
  String get updatePhaseChecking => 'Verificando versões…';

  @override
  String get updatePhaseAvailable => 'Uma nova versão está disponível';

  @override
  String get updatePhaseDownloading => 'Baixando atualização…';

  @override
  String get updatePhaseVerifying => 'Verificando integridade…';

  @override
  String get updatePhaseInstalling => 'Preparando instalação e reinício…';

  @override
  String get updatePhaseUpToDate =>
      'Você tem a versão compatível mais recente.';

  @override
  String get updatePhaseFailed => 'Não foi possível concluir a atualização';

  @override
  String achievementFocusSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Conclua $count focos de trabalho',
      one: 'Conclua 1 foco de trabalho',
    );
    return '$_temp0';
  }

  @override
  String achievementTaskSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Conclua $count tarefas',
      one: 'Conclua 1 tarefa',
    );
    return '$_temp0';
  }

  @override
  String get achievementDayNotWastedSubtitle =>
      'Conclua um foco e uma tarefa no mesmo dia';

  @override
  String get achievementFocusPlusCheckSubtitle =>
      'Conclua 3 focos e 3 tarefas no mesmo dia';

  @override
  String get achievementNoFussSubtitle =>
      'Conclua 5 focos no mesmo dia sem interrupções';

  @override
  String get achievementCleanEntrySubtitle =>
      'Conclua uma tarefa após o foco vinculado a ela';

  @override
  String get achievementTomatoClosedSubtitle =>
      'Conclua uma tarefa no dia do seu foco de trabalho';

  @override
  String achievementTitle(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'focus_1': 'Primeiro tomate',
      'focus_5': 'Aquecimento',
      'focus_10': 'Foco encontrado',
      'focus_25': 'Turno de tomates',
      'focus_50': 'Modo ativado',
      'focus_100': 'Faixa vermelha',
      'focus_250': 'Raízes profundas',
      'focus_500': 'Autoridade do timer',
      'focus_1000': 'Milésimo tomate',
      'focus_5000': 'Fazendeiro do foco',
      'focus_10000': 'Plantação de atenção',
      'focus_50000': 'Império do tomate',
      'focus_100000': 'Supermente vermelha',
      'focus_1000000': 'Singularidade do tomate',
      'task_1': 'Primeira marca',
      'task_5': 'A lista tremeu',
      'task_10': 'Caixa feliz',
      'task_25': 'Limpando a pilha',
      'task_50': 'Mestre das marcas',
      'task_100': 'Pontas soltas resolvidas',
      'task_250': 'Lista sob controle',
      'task_500': 'Nocaute no escritório',
      'task_1000': 'Mil marcas',
      'task_5000': 'Arquivista de vitórias',
      'task_10000': 'Máquina de marcar',
      'task_50000': 'Escritório de assuntos resolvidos',
      'task_100000': 'Senhor das listas',
      'task_1000000': 'Marca final',
      'combo_day_not_wasted': 'Dia bem aproveitado',
      'combo_focus_plus_check': 'Foco + marca',
      'combo_no_fuss': 'Sem correria',
      'combo_clean_entry': 'Entrada perfeita',
      'combo_tomato_closed_question': 'O tomate resolveu',
      'other': 'Conquista',
    });
    return '$_temp0';
  }

  @override
  String get focusPresetDeepWork => 'Trabalho profundo';

  @override
  String get focusPresetShortSprint => 'Sprint curto';

  @override
  String csvImportIssueRow(int row, String message) {
    return 'Linha $row: $message';
  }

  @override
  String csvImportIssueMessage(String code, String value) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'fileTooLarge': 'O arquivo CSV excede 16 MiB.',
      'invalidUtf8': 'O CSV deve usar UTF-8 válido.',
      'missingHeader': 'O cabeçalho CSV está ausente.',
      'malformed': 'Formato CSV inválido.',
      'unknownHeader': 'Cabeçalho desconhecido \"$value\".',
      'duplicateHeader': 'Cabeçalho duplicado \"$value\".',
      'contentHeaderRequired': 'O cabeçalho content é obrigatório.',
      'tooManyTasks': 'O CSV não pode conter mais de 1000 tarefas.',
      'tooManyFields': 'A linha tem mais campos que o cabeçalho.',
      'contentRequired': 'content é obrigatório.',
      'invalidPriority': 'priority deve ser um inteiro de 1 a 4.',
      'invalidDate': '$value deve usar YYYY-MM-DD.',
      'mixedSchedule':
          'A data de vencimento não pode ser combinada com um horário.',
      'timedFieldsRequired': 'Um horário exige start_at, end_at e time_zone.',
      'invalidTimestamp':
          '$value deve ser RFC3339 com deslocamento UTC explícito.',
      'invalidTimeZone': 'time_zone deve ser um nome IANA válido.',
      'endBeforeStart': 'end_at deve ser posterior a start_at.',
      'invalidRecurrence': 'recurrence deve ser day, week ou month.',
      'invalidInteger': '$value deve ser um inteiro de 1 a 999.',
      'intervalWithoutRecurrence': 'recurrence_interval exige recurrence.',
      'recurrenceWithoutSchedule': 'recurrence exige um agendamento.',
      'doneTask': 'Tarefas concluídas não podem ser importadas.',
      'invalidKey': '$value tem formato inválido.',
      'empty': 'O CSV não contém tarefas.',
      'duplicateKey': 'Chave duplicada \"$value\".',
      'parentCycle': 'As referências parent_key formam um ciclo.',
      'missingParent': 'parent_key \"$value\" não existe.',
      'childProject':
          'A subtarefa deve usar o mesmo projeto da tarefa principal.',
      'other': 'Não foi possível importar o arquivo.',
    });
    return '$_temp0';
  }

  @override
  String billingOfferDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String billingOfferMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meses',
      one: '1 mês',
    );
    return '$_temp0';
  }

  @override
  String billingOfferYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anos',
      one: '1 ano',
    );
    return '$_temp0';
  }

  @override
  String billingTrialFree(String duration) {
    return 'Grátis por $duration';
  }

  @override
  String billingTrialRenewal(String price) {
    return 'Depois, $price. Renovação automática, salvo cancelamento.';
  }

  @override
  String get billingReturnBadge => 'Voltar ao Pro';

  @override
  String billingReturnSubtitle(String duration, String price) {
    return 'Por $duration; depois, $price. Renovação automática, salvo cancelamento.';
  }

  @override
  String billingReturnPending(String date) {
    return 'Seu desconto está reservado até $date. Se a compra foi cancelada, você poderá tentar novamente após esse horário.';
  }

  @override
  String get billingReturnFailed =>
      'Não foi possível verificar sua oferta de retorno. Tente novamente.';

  @override
  String get billingTryFree => 'Testar grátis';

  @override
  String get collaborationShareProject => 'Compartilhar projeto';

  @override
  String get collaborationShareIntro =>
      'Convide pessoas para trabalhar juntas neste projeto. Membros podem editar; observadores podem visualizar.';

  @override
  String get collaborationShareStart => 'Compartilhar';

  @override
  String get collaborationShareInProgress =>
      'Compartilhando… sincronizando as últimas alterações';

  @override
  String get collaborationMembers => 'Membros';

  @override
  String get collaborationPendingInvitations => 'Convites pendentes';

  @override
  String get collaborationRevoke => 'Revogar';

  @override
  String get collaborationPublicLink => 'Link público';

  @override
  String get collaborationPublicLinkHint =>
      'Qualquer pessoa com o link pode visualizar este projeto';

  @override
  String get collaborationCopyLink => 'Copiar link';

  @override
  String get collaborationConflicts => 'Conflitos de sincronização';

  @override
  String get collaborationLeaveProject => 'Sair do projeto';

  @override
  String get collaborationDeleteSharedProject => 'Excluir para todos';

  @override
  String get collaborationMakePrivate => 'Tornar privado';

  @override
  String get collaborationOwner => 'Proprietário';

  @override
  String get collaborationTransferOwnership => 'Transferir propriedade';

  @override
  String get collaborationRemoveMember => 'Remover membro';

  @override
  String get collaborationEmail => 'E-mail';

  @override
  String get collaborationInvite => 'Convidar';

  @override
  String get collaborationConflictHint =>
      'Outro membro também alterou este item';

  @override
  String get collaborationConflictKeepLocal => 'Manter a minha';

  @override
  String get collaborationConflictUseServer => 'Versão do servidor';

  @override
  String get collaborationProjectShared => 'Projeto compartilhado';

  @override
  String get collaborationInviteEmailFailed =>
      'Convite salvo, mas o e-mail não pôde ser enviado';

  @override
  String collaborationInviteSent(String email) {
    return 'Convite enviado para $email';
  }

  @override
  String get collaborationInvitationRevoked => 'Convite revogado';

  @override
  String get collaborationRoleUpdated => 'Função atualizada';

  @override
  String collaborationRemoveConfirm(String name) {
    return 'Remover $name deste projeto?';
  }

  @override
  String get collaborationMemberRemoved => 'Membro removido';

  @override
  String collaborationTransferConfirm(String name) {
    return 'Tornar $name o proprietário deste projeto?';
  }

  @override
  String get collaborationOwnershipTransferred => 'Propriedade transferida';

  @override
  String get collaborationLeaveConfirm => 'Sair deste projeto compartilhado?';

  @override
  String get collaborationLeftProject => 'Você saiu do projeto';

  @override
  String get collaborationDeleteSharedConfirm =>
      'Excluir este projeto compartilhado para todos os membros? Não é possível desfazer.';

  @override
  String get collaborationSharedProjectDeleted =>
      'Projeto compartilhado excluído';

  @override
  String get collaborationMakePrivateConfirm =>
      'Parar de compartilhar este projeto?';

  @override
  String get collaborationMakePrivateDescription =>
      'O projeto e o conteúdo voltam para a sua conta pessoal. Os outros participantes perdem o acesso imediatamente.';

  @override
  String get collaborationProjectMadePrivate =>
      'O projeto voltou a ser privado';

  @override
  String get collaborationLinkCopied => 'Link copiado';

  @override
  String get collaborationConflictResolved => 'Conflito resolvido';

  @override
  String get collaborationRoleAdministrator => 'Administrador';

  @override
  String get collaborationRoleMember => 'Membro';

  @override
  String get collaborationRoleObserver => 'Observador';

  @override
  String get collaborationForbidden => 'Você não tem permissão para isso';

  @override
  String get collaborationSignedOut =>
      'Entre para usar projetos compartilhados';

  @override
  String get collaborationUnavailable =>
      'Os projetos compartilhados estão indisponíveis no momento';

  @override
  String get collaborationError => 'Algo deu errado. Tente novamente';

  @override
  String get collaborationSyncPending =>
      'Conclua a sincronização deste projeto antes de compartilhar';

  @override
  String get collaborationMemberFallback => 'Membro';

  @override
  String get collaborationInboxTitle => 'Projetos compartilhados e convites';

  @override
  String get collaborationInboxSubtitle =>
      'Aceite convites e acompanhe a atividade de projetos compartilhados';

  @override
  String get collaborationInvitations => 'Convites';

  @override
  String get collaborationNoInvitations => 'Nenhum convite pendente';

  @override
  String get collaborationAccept => 'Aceitar';

  @override
  String get collaborationNotifications => 'Notificações';

  @override
  String get collaborationMarkAllRead => 'Marcar tudo como lido';

  @override
  String get collaborationNoNotifications => 'Nenhuma notificação';

  @override
  String get collaborationNotificationInvitation =>
      'Convite para um projeto compartilhado';

  @override
  String get collaborationNotificationDiscussion =>
      'Novo comentário em um projeto compartilhado';

  @override
  String get collaborationNotificationAssignment => 'Você recebeu uma tarefa';

  @override
  String get collaborationNotificationGeneric =>
      'Atividade em projeto compartilhado';

  @override
  String get collaborationInvitationAccepted => 'Convite aceito';

  @override
  String get collaborationAssignees => 'Responsáveis';

  @override
  String get collaborationEditAssignees => 'Editar responsáveis';

  @override
  String get collaborationNoAssignees => 'Sem responsáveis';

  @override
  String get collaborationComments => 'Comentários';

  @override
  String get collaborationCommentHint => 'Escreva um comentário';

  @override
  String get collaborationCommentSend => 'Enviar';

  @override
  String get collaborationCommentDelete => 'Excluir comentário';

  @override
  String get collaborationSharedBadge => 'Projeto compartilhado';

  @override
  String get collaborationJoinTitle => 'Convite para um projeto';

  @override
  String get collaborationJoinDescription =>
      'Você foi convidado a participar de um projeto compartilhado. Aceite o convite para adicioná-lo aos seus projetos.';

  @override
  String get collaborationJoinRole => 'Seu papel';

  @override
  String get collaborationJoinAccept => 'Aceitar convite';

  @override
  String get collaborationJoinOpenProject => 'Abrir projeto';

  @override
  String get collaborationJoinInvalid => 'Este link de convite não é válido';

  @override
  String get collaborationJoinUnavailable =>
      'Este convite não está mais disponível para sua conta';

  @override
  String get collaborationPublicNotice =>
      'Visualização somente leitura compartilhada por um membro do Pomodoist';

  @override
  String get collaborationPublicUnavailable =>
      'Este link compartilhado não está mais disponível';

  @override
  String get collaborationPublicEmpty => 'Nada foi compartilhado ainda';

  @override
  String get collaborationPublicOpen => 'Abrir o Pomodoist';

  @override
  String get collaborationPublicTasks => 'Tarefas';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');
}

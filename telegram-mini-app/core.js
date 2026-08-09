const messages = {
  en: {
    direction: "ltr",
    inbox: "Inbox",
    addPlaceholder: "Add a task",
    add: "Add",
    focus: "Focus",
    empty: "Your Inbox is clear",
    undo: "Undo",
    completed: "Task completed",
    pause: "Pause",
    resume: "Resume",
    stop: "Stop",
    settings: "Account",
    guest: "Telegram guest",
    linked: "Connected to Pomodoist",
    signIn: "Sign in to Pomodoist",
    close: "Close",
    retry: "Retry",
    loading: "Loading…",
    opening: "Opening secure sign-in…",
    outsideTitle: "Open Pomodoist in Telegram",
    outsideBody: "This Mini App is available only inside Telegram.",
    openBot: "Open @pomodoist_bot",
    error: "Something went wrong. Please retry.",
    linkConflict: "Stop one active Focus before linking accounts.",
    linkExpired: "The sign-in link expired. Create a new one.",
  },
  ru: {
    direction: "ltr",
    inbox: "Входящие",
    addPlaceholder: "Добавить задачу",
    add: "Добавить",
    focus: "Фокус",
    empty: "Во входящих пусто",
    undo: "Отменить",
    completed: "Задача выполнена",
    pause: "Пауза",
    resume: "Продолжить",
    stop: "Остановить",
    settings: "Аккаунт",
    guest: "Гость Telegram",
    linked: "Подключён Pomodoist",
    signIn: "Войти в Pomodoist",
    close: "Закрыть",
    retry: "Повторить",
    loading: "Загрузка…",
    opening: "Открываю безопасный вход…",
    outsideTitle: "Откройте Pomodoist в Telegram",
    outsideBody: "Это мини-приложение доступно только внутри Telegram.",
    openBot: "Открыть @pomodoist_bot",
    error: "Что-то пошло не так. Попробуйте ещё раз.",
    linkConflict: "Перед привязкой остановите один из активных Фокусов.",
    linkExpired: "Ссылка входа устарела. Создайте новую.",
  },
  de: {
    direction: "ltr",
    inbox: "Eingang",
    addPlaceholder: "Aufgabe hinzufügen",
    add: "Hinzufügen",
    focus: "Fokus",
    empty: "Dein Eingang ist leer",
    undo: "Rückgängig",
    completed: "Aufgabe erledigt",
    pause: "Pause",
    resume: "Fortsetzen",
    stop: "Stoppen",
    settings: "Konto",
    guest: "Telegram-Gast",
    linked: "Mit Pomodoist verbunden",
    signIn: "Bei Pomodoist anmelden",
    close: "Schließen",
    retry: "Erneut versuchen",
    loading: "Laden…",
    opening: "Sichere Anmeldung wird geöffnet…",
    outsideTitle: "Pomodoist in Telegram öffnen",
    outsideBody: "Diese Mini App ist nur in Telegram verfügbar.",
    openBot: "@pomodoist_bot öffnen",
    error: "Etwas ist schiefgegangen.",
    linkConflict: "Beende vor dem Verknüpfen einen aktiven Fokus.",
    linkExpired: "Der Anmeldelink ist abgelaufen.",
  },
  es: {
    direction: "ltr",
    inbox: "Bandeja",
    addPlaceholder: "Añadir una tarea",
    add: "Añadir",
    focus: "Enfoque",
    empty: "Tu bandeja está vacía",
    undo: "Deshacer",
    completed: "Tarea completada",
    pause: "Pausar",
    resume: "Continuar",
    stop: "Detener",
    settings: "Cuenta",
    guest: "Invitado de Telegram",
    linked: "Conectado a Pomodoist",
    signIn: "Iniciar sesión en Pomodoist",
    close: "Cerrar",
    retry: "Reintentar",
    loading: "Cargando…",
    opening: "Abriendo inicio seguro…",
    outsideTitle: "Abre Pomodoist en Telegram",
    outsideBody: "Esta Mini App solo está disponible en Telegram.",
    openBot: "Abrir @pomodoist_bot",
    error: "Algo salió mal.",
    linkConflict: "Detén un Enfoque activo antes de vincular.",
    linkExpired: "El enlace de acceso caducó.",
  },
  fr: {
    direction: "ltr",
    inbox: "Boîte de réception",
    addPlaceholder: "Ajouter une tâche",
    add: "Ajouter",
    focus: "Focus",
    empty: "Votre boîte est vide",
    undo: "Annuler",
    completed: "Tâche terminée",
    pause: "Pause",
    resume: "Reprendre",
    stop: "Arrêter",
    settings: "Compte",
    guest: "Invité Telegram",
    linked: "Connecté à Pomodoist",
    signIn: "Se connecter à Pomodoist",
    close: "Fermer",
    retry: "Réessayer",
    loading: "Chargement…",
    opening: "Ouverture de la connexion sécurisée…",
    outsideTitle: "Ouvrez Pomodoist dans Telegram",
    outsideBody: "Cette Mini App est disponible uniquement dans Telegram.",
    openBot: "Ouvrir @pomodoist_bot",
    error: "Une erreur est survenue.",
    linkConflict: "Arrêtez un Focus actif avant la liaison.",
    linkExpired: "Le lien de connexion a expiré.",
  },
  zh: {
    direction: "ltr",
    inbox: "收件箱",
    addPlaceholder: "添加任务",
    add: "添加",
    focus: "专注",
    empty: "收件箱为空",
    undo: "撤销",
    completed: "任务已完成",
    pause: "暂停",
    resume: "继续",
    stop: "停止",
    settings: "账户",
    guest: "Telegram 访客",
    linked: "已连接 Pomodoist",
    signIn: "登录 Pomodoist",
    close: "关闭",
    retry: "重试",
    loading: "加载中…",
    opening: "正在打开安全登录…",
    outsideTitle: "在 Telegram 中打开 Pomodoist",
    outsideBody: "此迷你应用仅可在 Telegram 中使用。",
    openBot: "打开 @pomodoist_bot",
    error: "出现错误，请重试。",
    linkConflict: "关联前请停止一个正在运行的专注。",
    linkExpired: "登录链接已过期。",
  },
  ar: {
    direction: "rtl",
    inbox: "الوارد",
    addPlaceholder: "أضف مهمة",
    add: "إضافة",
    focus: "تركيز",
    empty: "صندوق الوارد فارغ",
    undo: "تراجع",
    completed: "اكتملت المهمة",
    pause: "إيقاف مؤقت",
    resume: "متابعة",
    stop: "إيقاف",
    settings: "الحساب",
    guest: "ضيف Telegram",
    linked: "متصل بـ Pomodoist",
    signIn: "تسجيل الدخول إلى Pomodoist",
    close: "إغلاق",
    retry: "إعادة المحاولة",
    loading: "جارٍ التحميل…",
    opening: "جارٍ فتح تسجيل الدخول الآمن…",
    outsideTitle: "افتح Pomodoist في Telegram",
    outsideBody: "هذا التطبيق المصغر متاح داخل Telegram فقط.",
    openBot: "فتح @pomodoist_bot",
    error: "حدث خطأ. حاول مرة أخرى.",
    linkConflict: "أوقف جلسة تركيز نشطة قبل الربط.",
    linkExpired: "انتهت صلاحية رابط الدخول.",
  },
};

export function localeFor(languageCode = "en") {
  const base = languageCode.toLowerCase().split(/[-_]/)[0];
  return Object.hasOwn(messages, base) ? base : "en";
}

export function textFor(languageCode = "en") {
  return messages[localeFor(languageCode)];
}

export function remainingSeconds(focus, now = Date.now()) {
  const interval = focus?.interval;
  if (!interval) return 0;
  const startedAt = Date.parse(interval.startedAt);
  if (!Number.isFinite(startedAt)) return 0;
  const effectiveNow = interval.status === "paused"
    ? Date.parse(interval.pausedAt) || now
    : now;
  const elapsed = Math.max(
    0,
    Math.floor((effectiveNow - startedAt) / 1000) -
      Number(interval.pausedTotalSeconds || 0),
  );
  return Math.max(0, Number(interval.plannedSeconds || 0) - elapsed);
}

export function formatClock(seconds) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, "0");
  const rest = Math.floor(seconds % 60).toString().padStart(2, "0");
  return `${minutes}:${rest}`;
}

export function telegramEntityId(commandId, sequence = 1n) {
  const raw = commandId.replaceAll("-", "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(raw)) return commandId;
  const suffix = (BigInt(`0x${raw.slice(20)}`) ^ sequence)
    .toString(16)
    .padStart(12, "0");
  const variant = ((Number.parseInt(raw[16], 16) & 3) | 8).toString(16);
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-5${
    raw.slice(13, 16)
  }-${variant}${raw.slice(17, 20)}-${suffix}`;
}

export function applyOptimisticCommand(state, command, now = Date.now()) {
  const timestamp = command.optimisticAt ?? new Date(now).toISOString();
  switch (command.type) {
    case "task.create": {
      const id = telegramEntityId(command.id);
      if (state.inbox.some((task) => task.id === id)) return state;
      return {
        ...state,
        inbox: [...state.inbox, {
          id,
          content: command.content.trim(),
          createdAt: timestamp,
          optimistic: true,
        }],
      };
    }
    case "task.complete":
      return {
        ...state,
        inbox: state.inbox.filter((task) => task.id !== command.taskId),
      };
    case "task.uncomplete":
      return command.optimisticTask == null ||
          state.inbox.some((task) => task.id === command.taskId)
        ? state
        : { ...state, inbox: [...state.inbox, command.optimisticTask] };
    case "focus.start":
      return {
        ...state,
        focus: {
          run: {
            id: command.id,
            status: "active",
            taskId: command.taskId,
            startedAt: timestamp,
          },
          interval: {
            id: command.id,
            status: "running",
            plannedSeconds: 25 * 60,
            startedAt: timestamp,
            pausedAt: null,
            pausedTotalSeconds: 0,
          },
        },
      };
    case "focus.pause":
      return state.focus == null ? state : {
        ...state,
        focus: {
          ...state.focus,
          run: { ...state.focus.run, status: "paused" },
          interval: {
            ...state.focus.interval,
            status: "paused",
            pausedAt: timestamp,
          },
        },
      };
    case "focus.resume": {
      if (state.focus == null) return state;
      const pausedAt = Date.parse(state.focus.interval.pausedAt);
      const pausedSeconds = Number.isFinite(pausedAt)
        ? Math.max(0, Math.floor((Date.parse(timestamp) - pausedAt) / 1000))
        : 0;
      return {
        ...state,
        focus: {
          ...state.focus,
          run: { ...state.focus.run, status: "active" },
          interval: {
            ...state.focus.interval,
            status: "running",
            pausedAt: null,
            pausedTotalSeconds:
              Number(state.focus.interval.pausedTotalSeconds || 0) +
              pausedSeconds,
          },
        },
      };
    }
    case "focus.stop":
    case "focus.complete":
      return { ...state, focus: null };
    default:
      return state;
  }
}

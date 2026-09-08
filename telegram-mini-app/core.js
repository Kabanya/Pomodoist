const messages = {
  en: {
    direction: "ltr",
    today: "Today",
    upcoming: "Upcoming",
    completedView: "Completed",
    task: "Task",
    taskDetails: "Task details",
    title: "Title",
    note: "Comment",
    schedule: "Date · all day",
    priority: "Priority",
    save: "Save changes",
    complete: "Complete",
    restore: "Restore",
    startFocus: "Start focus",
    delete: "Delete",
    cancel: "Cancel",
    deleteConfirm: "Delete this task and its subtasks? This cannot be undone.",
    refresh: "Refresh",
    previous: "Previous",
    next: "Next",
    noDate: "No date",
    open: "Open",
    done: "Completed",
    emptyView: "No tasks here",
    taskCount: "Tasks",
    focusReady: "Time to focus",
    focusHint: "Focus for 25 minutes, with or without a task.",
    chooseTask: "Choose a task",
    focusing: "Focus session",
    paused: "Paused",
    finish: "Finish session",
    openApp: "Open Pomodoist",
    saving: "Saving…",
    pending: "Changes saved on this device. Waiting to sync.",
    all: "All tasks",
    updatedAt: "Updated at {time}",
    refreshFailed: "Could not refresh tasks.",
    changed:
      "This task changed on another device. Refresh it before saving again.",
    notFound: "Task not found. Refresh the list.",
    requiresApp:
      "Open Pomodoist to change this recurring task or large task hierarchy.",
    activeFocus: "Stop this task’s focus session before deleting it.",
    focusChanged: "Focus changed on another device. Refresh and try again.",
    expired:
      "Reopen the Mini App in Telegram to reconnect. Pending changes are saved.",
    offline: "No connection. Your changes will sync when you are back online.",
    notElapsed: "The focus interval has not elapsed yet.",
    deadline: "Deadline",
    repeat: "Repeats",
    timedHint:
      "Changing the date replaces the current time with an all-day schedule.",
    recurringHint:
      "The recurrence will be preserved. To remove it, open Pomodoist.",
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
    signOut: "Sign out",
    signingOut: "Signing out…",
    signOutConfirm:
      "Sign out of Pomodoist? The Mini App will continue with a new empty guest account.",
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
    today: "Сегодня",
    upcoming: "Предстоящее",
    completedView: "Завершено",
    task: "Задача",
    taskDetails: "Детали задачи",
    title: "Название",
    note: "Комментарий",
    schedule: "Дата · весь день",
    priority: "Приоритет",
    save: "Сохранить изменения",
    complete: "Завершить",
    restore: "Восстановить",
    startFocus: "Начать фокус",
    delete: "Удалить",
    cancel: "Отмена",
    deleteConfirm:
      "Удалить задачу и её подзадачи? Это действие нельзя отменить.",
    refresh: "Обновить",
    previous: "Назад",
    next: "Далее",
    noDate: "Без даты",
    open: "Открыта",
    done: "Завершена",
    emptyView: "Здесь пока нет задач",
    taskCount: "Задач",
    focusReady: "Время сосредоточиться",
    focusHint: "25 минут фокуса — с задачей или без неё.",
    chooseTask: "Выбрать задачу",
    focusing: "Сессия фокуса",
    paused: "На паузе",
    finish: "Завершить сессию",
    openApp: "Открыть Pomodoist",
    saving: "Сохранение…",
    pending: "Изменения сохранены на устройстве. Ожидаем синхронизацию.",
    all: "Все задачи",
    updatedAt: "Обновлено в {time}",
    refreshFailed: "Не удалось обновить задачи.",
    changed:
      "Задача изменилась на другом устройстве. Обновите её перед сохранением.",
    notFound: "Задача не найдена. Обновите список.",
    requiresApp:
      "Для изменения этой повторяющейся задачи или большой группы подзадач откройте Pomodoist.",
    activeFocus: "Перед удалением остановите фокус этой задачи.",
    focusChanged:
      "Фокус изменился на другом устройстве. Обновите и повторите действие.",
    expired:
      "Переоткройте Mini App в Telegram для подключения. Ожидающие изменения сохранены.",
    offline: "Нет соединения. Изменения отправятся, когда связь восстановится.",
    notElapsed: "Интервал фокуса ещё не закончился.",
    deadline: "Дедлайн",
    repeat: "Повторение",
    timedHint: "Изменение даты заменит текущее время расписанием на весь день.",
    recurringHint:
      "Повторение сохранится. Для его удаления откройте Pomodoist.",
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
    signOut: "Выйти",
    signingOut: "Выход…",
    signOutConfirm:
      "Выйти из Pomodoist? Mini App продолжит работу с новым пустым гостевым аккаунтом.",
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
    today: "Heute",
    upcoming: "Demnächst",
    completedView: "Erledigt",
    task: "Aufgabe",
    taskDetails: "Aufgabendetails",
    title: "Titel",
    note: "Kommentar",
    schedule: "Datum · ganztägig",
    priority: "Priorität",
    save: "Änderungen speichern",
    complete: "Erledigen",
    restore: "Wiederherstellen",
    startFocus: "Fokus starten",
    delete: "Löschen",
    cancel: "Abbrechen",
    deleteConfirm: "Diese Aufgabe und ihre Unteraufgaben endgültig löschen?",
    refresh: "Aktualisieren",
    previous: "Zurück",
    next: "Weiter",
    noDate: "Kein Datum",
    open: "Offen",
    done: "Erledigt",
    emptyView: "Keine Aufgaben",
    taskCount: "Aufgaben",
    focusReady: "Zeit für Fokus",
    focusHint: "25 Minuten Fokus, mit oder ohne Aufgabe.",
    chooseTask: "Aufgabe wählen",
    focusing: "Fokussitzung",
    paused: "Pausiert",
    finish: "Sitzung beenden",
    openApp: "Pomodoist öffnen",
    saving: "Speichern…",
    pending:
      "Änderungen auf diesem Gerät gespeichert. Synchronisierung ausstehend.",
    all: "Alle Aufgaben",
    updatedAt: "Aktualisiert um {time}",
    refreshFailed: "Aufgaben konnten nicht aktualisiert werden.",
    changed:
      "Die Aufgabe wurde auf einem anderen Gerät geändert. Vor dem Speichern aktualisieren.",
    notFound: "Aufgabe nicht gefunden. Aktualisiere die Liste.",
    requiresApp:
      "Öffne Pomodoist, um diese wiederkehrende Aufgabe oder große Aufgabengruppe zu ändern.",
    activeFocus: "Beende vor dem Löschen den Fokus dieser Aufgabe.",
    focusChanged:
      "Der Fokus wurde auf einem anderen Gerät geändert. Aktualisiere die Ansicht.",
    expired:
      "Öffne die Mini App in Telegram erneut. Ausstehende Änderungen sind gespeichert.",
    timedHint:
      "Ein neues Datum ersetzt die Uhrzeit durch einen ganztägigen Termin.",
    recurringHint:
      "Die Wiederholung bleibt erhalten. Entferne sie in Pomodoist.",
    offline:
      "Keine Verbindung. Änderungen werden synchronisiert, sobald du wieder online bist.",
    notElapsed: "Das Fokusintervall ist noch nicht abgelaufen.",
    deadline: "Frist",
    repeat: "Wiederholung",

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
    signOut: "Abmelden",
    signingOut: "Abmelden…",
    signOutConfirm:
      "Von Pomodoist abmelden? Die Mini App verwendet danach ein neues leeres Gastkonto.",
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
    today: "Hoy",
    upcoming: "Próximamente",
    completedView: "Completadas",
    task: "Tarea",
    taskDetails: "Detalles de la tarea",
    title: "Título",
    note: "Comentario",
    schedule: "Fecha · todo el día",
    priority: "Prioridad",
    save: "Guardar cambios",
    complete: "Completar",
    restore: "Restaurar",
    startFocus: "Iniciar enfoque",
    delete: "Eliminar",
    cancel: "Cancelar",
    deleteConfirm:
      "¿Eliminar esta tarea y sus subtareas? No se puede deshacer.",
    refresh: "Actualizar",
    previous: "Anterior",
    next: "Siguiente",
    noDate: "Sin fecha",
    open: "Abierta",
    done: "Completada",
    emptyView: "No hay tareas",
    taskCount: "Tareas",
    focusReady: "Momento de concentrarse",
    focusHint: "Concéntrate durante 25 minutos, con o sin una tarea.",
    chooseTask: "Elegir tarea",
    focusing: "Sesión de enfoque",
    paused: "En pausa",
    finish: "Finalizar sesión",
    openApp: "Abrir Pomodoist",
    saving: "Guardando…",
    pending:
      "Cambios guardados en este dispositivo. Pendientes de sincronizar.",
    all: "Todas las tareas",
    updatedAt: "Actualizado a las {time}",
    refreshFailed: "No se pudieron actualizar las tareas.",
    changed:
      "La tarea cambió en otro dispositivo. Actualízala antes de guardar.",
    notFound: "Tarea no encontrada. Actualiza la lista.",
    requiresApp:
      "Abre Pomodoist para modificar esta tarea recurrente o grupo grande de subtareas.",
    activeFocus: "Detén el enfoque de esta tarea antes de eliminarla.",
    focusChanged:
      "El enfoque cambió en otro dispositivo. Actualiza e inténtalo de nuevo.",
    expired:
      "Vuelve a abrir la Mini App en Telegram. Los cambios pendientes están guardados.",
    timedHint:
      "Cambiar la fecha sustituirá la hora por una fecha de día completo.",
    recurringHint:
      "La recurrencia se conservará. Para eliminarla, abre Pomodoist.",
    offline:
      "Sin conexión. Los cambios se sincronizarán cuando vuelvas a estar en línea.",
    notElapsed: "El intervalo de enfoque aún no ha terminado.",
    deadline: "Fecha límite",
    repeat: "Se repite",

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
    signOut: "Cerrar sesión",
    signingOut: "Cerrando sesión…",
    signOutConfirm:
      "¿Cerrar sesión en Pomodoist? La Mini App continuará con una cuenta de invitado nueva y vacía.",
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
    today: "Aujourd’hui",
    upcoming: "À venir",
    completedView: "Terminées",
    task: "Tâche",
    taskDetails: "Détails de la tâche",
    title: "Titre",
    note: "Commentaire",
    schedule: "Date · journée entière",
    priority: "Priorité",
    save: "Enregistrer",
    complete: "Terminer",
    restore: "Restaurer",
    startFocus: "Démarrer le focus",
    delete: "Supprimer",
    cancel: "Annuler",
    deleteConfirm:
      "Supprimer cette tâche et ses sous-tâches ? Cette action est irréversible.",
    refresh: "Actualiser",
    previous: "Précédent",
    next: "Suivant",
    noDate: "Sans date",
    open: "Ouverte",
    done: "Terminée",
    emptyView: "Aucune tâche",
    taskCount: "Tâches",
    focusReady: "Place à la concentration",
    focusHint: "Concentrez-vous pendant 25 minutes, avec ou sans tâche.",
    chooseTask: "Choisir une tâche",
    focusing: "Session de focus",
    paused: "En pause",
    finish: "Terminer la session",
    openApp: "Ouvrir Pomodoist",
    saving: "Enregistrement…",
    pending:
      "Modifications enregistrées sur cet appareil. Synchronisation en attente.",
    all: "Toutes les tâches",
    updatedAt: "Mis à jour à {time}",
    refreshFailed: "Impossible d’actualiser les tâches.",
    changed:
      "La tâche a changé sur un autre appareil. Actualisez-la avant d’enregistrer.",
    notFound: "Tâche introuvable. Actualisez la liste.",
    requiresApp:
      "Ouvrez Pomodoist pour modifier cette tâche récurrente ou ce grand groupe de sous-tâches.",
    activeFocus: "Arrêtez le focus de cette tâche avant de la supprimer.",
    focusChanged:
      "Le focus a changé sur un autre appareil. Actualisez puis réessayez.",
    expired:
      "Rouvrez la Mini App dans Telegram. Les modifications en attente sont enregistrées.",
    timedHint: "Changer la date remplacera l’horaire par une journée entière.",
    recurringHint:
      "La récurrence sera conservée. Ouvrez Pomodoist pour la supprimer.",
    offline:
      "Hors connexion. Les modifications seront synchronisées au retour de la connexion.",
    notElapsed: "L’intervalle de focus n’est pas encore écoulé.",
    deadline: "Échéance",
    repeat: "Récurrence",

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
    signOut: "Se déconnecter",
    signingOut: "Déconnexion…",
    signOutConfirm:
      "Se déconnecter de Pomodoist ? La Mini App continuera avec un nouveau compte invité vide.",
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
    today: "今天",
    upcoming: "即将到来",
    completedView: "已完成",
    task: "任务",
    taskDetails: "任务详情",
    title: "标题",
    note: "备注",
    schedule: "日期 · 全天",
    priority: "优先级",
    save: "保存更改",
    complete: "完成",
    restore: "恢复",
    startFocus: "开始专注",
    delete: "删除",
    cancel: "取消",
    deleteConfirm: "删除此任务及其子任务？此操作无法撤销。",
    refresh: "刷新",
    previous: "上一页",
    next: "下一页",
    noDate: "无日期",
    open: "未完成",
    done: "已完成",
    emptyView: "暂无任务",
    taskCount: "任务",
    focusReady: "开始专注吧",
    focusHint: "专注25分钟，可选择关联任务，也可直接开始。",
    chooseTask: "选择任务",
    focusing: "专注时段",
    paused: "已暂停",
    finish: "结束专注",
    openApp: "打开 Pomodoist",
    saving: "保存中…",
    pending: "更改已保存在此设备上，等待同步。",
    all: "全部任务",
    updatedAt: "更新于 {time}",
    refreshFailed: "无法更新任务。",
    changed: "此任务已在其他设备上更改。请刷新后再保存。",
    notFound: "找不到任务，请刷新列表。",
    requiresApp: "请打开 Pomodoist 来修改此重复任务或大型子任务组。",
    activeFocus: "删除前请先停止此任务的专注。",
    focusChanged: "专注已在其他设备上更改，请刷新后重试。",
    expired: "请在 Telegram 中重新打开迷你应用。待同步的更改已保存。",
    timedHint: "更改日期会将现有时间替换为全天日程。",
    recurringHint: "重复设置将保留。请打开 Pomodoist 来移除重复。",
    offline: "暂无网络，更改将在恢复连接后同步。",
    notElapsed: "专注时段尚未结束。",
    deadline: "截止日期",
    repeat: "重复",

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
    signOut: "退出登录",
    signingOut: "正在退出…",
    signOutConfirm: "确定退出 Pomodoist？Mini App 将使用一个新的空白访客账户继续运行。",
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
    today: "اليوم",
    upcoming: "القادمة",
    completedView: "المكتملة",
    task: "مهمة",
    taskDetails: "تفاصيل المهمة",
    title: "العنوان",
    note: "تعليق",
    schedule: "التاريخ · طوال اليوم",
    priority: "الأولوية",
    save: "حفظ التغييرات",
    complete: "إكمال",
    restore: "استعادة",
    startFocus: "بدء التركيز",
    delete: "حذف",
    cancel: "إلغاء",
    deleteConfirm:
      "هل تريد حذف هذه المهمة ومهامها الفرعية؟ لا يمكن التراجع عن ذلك.",
    refresh: "تحديث",
    previous: "السابق",
    next: "التالي",
    noDate: "بلا تاريخ",
    open: "مفتوحة",
    done: "مكتملة",
    emptyView: "لا توجد مهام",
    taskCount: "المهام",
    focusReady: "حان وقت التركيز",
    focusHint: "ركّز لمدة 25 دقيقة، مع مهمة أو بدونها.",
    chooseTask: "اختيار مهمة",
    focusing: "جلسة تركيز",
    paused: "متوقفة مؤقتًا",
    finish: "إنهاء الجلسة",
    openApp: "فتح Pomodoist",
    saving: "جارٍ الحفظ…",
    pending: "حُفظت التغييرات على هذا الجهاز. بانتظار المزامنة.",
    all: "كل المهام",
    updatedAt: "آخر تحديث في {time}",
    refreshFailed: "تعذّر تحديث المهام.",
    changed: "تغيرت المهمة على جهاز آخر. حدّثها قبل الحفظ.",
    notFound: "المهمة غير موجودة. حدّث القائمة.",
    requiresApp:
      "افتح Pomodoist لتعديل هذه المهمة المتكررة أو مجموعة المهام الفرعية الكبيرة.",
    activeFocus: "أوقف تركيز هذه المهمة قبل حذفها.",
    focusChanged: "تغير التركيز على جهاز آخر. حدّث وحاول مجددًا.",
    expired: "أعد فتح التطبيق المصغر في Telegram. التغييرات المعلقة محفوظة.",
    timedHint: "تغيير التاريخ سيستبدل الوقت الحالي بجدول طوال اليوم.",
    recurringHint: "سيُحفظ التكرار. افتح Pomodoist لإزالته.",
    offline: "لا يوجد اتصال. ستتم المزامنة عند عودة الاتصال.",
    notElapsed: "لم تنتهِ فترة التركيز بعد.",
    deadline: "الموعد النهائي",
    repeat: "تكرار",

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
    signOut: "تسجيل الخروج",
    signingOut: "جارٍ تسجيل الخروج…",
    signOutConfirm:
      "هل تريد تسجيل الخروج من Pomodoist؟ سيستمر التطبيق المصغر بحساب ضيف جديد وفارغ.",
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
  return { ...messages.en, ...messages[localeFor(languageCode)] };
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
  if (command.type.startsWith("task.")) {
    const id = command.type === "task.create"
      ? telegramEntityId(command.id)
      : command.taskId;
    const original = state.task?.id === id
      ? state.task
      : [...state.tasks ?? [], ...state.inbox].find((task) => task.id === id) ??
        command.optimisticTask;
    let task = original;
    if (command.type === "task.create") {
      task ??= {
        id,
        content: command.content.trim(),
        projectId: "inbox",
        status: "open",
        priority: 4,
        day: "",
        createdAt: timestamp,
        optimistic: true,
      };
    }
    if (command.type === "task.update" && task) {
      task = { ...task, ...command.patch };
      if ("dueJson" in command.patch) {
        task.day = scheduleDay(task.dueJson, state.timeZone);
      }
    }
    if (command.type === "task.complete" && task) {
      task = { ...task, status: "completed" };
    }
    if (command.type === "task.uncomplete" && task) {
      task = task.status === undefined ? task : { ...task, status: "open" };
    }
    if (command.type === "task.delete") task = null;
    const update = (rows, view) => {
      const result = rows.map((row) => row.id === id ? task : row).filter(
        Boolean,
      );
      if (task && !result.some((row) => row.id === id)) result.push(task);
      return result.filter((row) =>
        matchesView(row, view, state.timeZone, now)
      );
    };
    const tasks = state.tasks && update(state.tasks, state.view);
    return {
      ...state,
      inbox: update(state.inbox, "inbox"),
      ...(tasks
        ? {
          tasks,
          total: Math.max(
            0,
            (state.total ?? 0) + tasks.length - state.tasks.length,
          ),
        }
        : {}),
      ...(state.task?.id === id ? { task } : {}),
      ...(state.focusTask?.id === id ? { focusTask: task } : {}),
    };
  }
  switch (command.type) {
    case "focus.start":
      return {
        ...state,
        focus: {
          run: {
            id: telegramEntityId(command.id),
            status: "active",
            taskId: command.taskId ?? null,
            startedAt: timestamp,
          },
          interval: {
            id: telegramEntityId(command.id, 2n),
            taskId: command.taskId ?? null,
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

export function scheduleFor(raw) {
  try {
    const value = JSON.parse(raw);
    return value && typeof value === "object" && !Array.isArray(value)
      ? value
      : {};
  } catch {
    return {};
  }
}

export function taskPatch(task, fields) {
  /** @type {{content?: string, description?: string | null, priority?: number, dueJson?: string | null}} */
  const patch = {};
  if (fields.content.trim() !== task.content) {
    patch.content = fields.content.trim();
  }
  if (fields.description !== (task.description ?? "")) {
    patch.description = fields.description || null;
  }
  if (fields.priority !== task.priority) patch.priority = fields.priority;
  if (fields.date !== (task.day ?? "")) {
    patch.dueJson = fields.date
      ? JSON.stringify({ type: "allDay", date: fields.date })
      : null;
  }
  return patch;
}

function dayInZone(value, timeZone = "UTC") {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(value));
  return ["year", "month", "day"].map((type) =>
    parts.find((part) => part.type === type).value
  ).join("-");
}

function scheduleDay(raw, timeZone) {
  const schedule = scheduleFor(raw);
  return schedule.type === "allDay"
    ? schedule.date
    : schedule.type === "timed"
    ? dayInZone(schedule.start, timeZone)
    : "";
}

function matchesView(task, view = "inbox", timeZone, now) {
  if (view === "completed") return task.status === "completed";
  if (task.status === "completed") return false;
  if (view === "all") return true;
  if (view === "inbox") return !task.projectId || task.projectId === "inbox";
  const day = task.day ?? scheduleDay(task.dueJson, timeZone);
  return Boolean(day) &&
    (view === "today"
      ? day <= dayInZone(now, timeZone)
      : day > dayInZone(now, timeZone));
}

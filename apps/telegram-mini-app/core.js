const messages = {
  "ko": {
    "direction": "ltr",
    "today": "오늘",
    "upcoming": "예정",
    "completedView": "완료됨",
    "task": "작업",
    "taskDetails": "작업 상세",
    "title": "제목",
    "note": "댓글",
    "schedule": "날짜 · 하루 종일",
    "priority": "우선순위",
    "save": "변경 사항 저장",
    "complete": "완료",
    "restore": "복원",
    "startFocus": "집중 시작",
    "delete": "삭제",
    "cancel": "취소",
    "deleteConfirm":
      "이 작업과 하위 작업을 삭제할까요? 이 작업은 되돌릴 수 없습니다.",
    "refresh": "새로고침",
    "previous": "이전",
    "next": "다음",
    "noDate": "날짜 없음",
    "open": "미완료",
    "done": "완료됨",
    "emptyView": "작업이 없습니다",
    "taskCount": "작업 수",
    "focusReady": "집중할 시간이에요",
    "focusHint": "작업을 선택하거나 선택하지 않고 25분 동안 집중하세요.",
    "chooseTask": "작업 선택",
    "focusing": "집중 세션",
    "paused": "일시 정지됨",
    "finish": "세션 종료",
    "openApp": "Pomodoist 열기",
    "saving": "저장 중…",
    "pending": "변경 사항이 이 기기에 저장되었습니다. 동기화 대기 중입니다.",
    "all": "모든 작업",
    "updatedAt": "{time}에 업데이트됨",
    "refreshFailed": "작업을 새로고침하지 못했습니다.",
    "changed":
      "다른 기기에서 이 작업이 변경되었습니다. 새로고침한 후 다시 저장하세요.",
    "notFound": "작업을 찾을 수 없습니다. 목록을 새로고침하세요.",
    "requiresApp":
      "이 반복 작업이나 큰 작업 계층을 변경하려면 Pomodoist를 여세요.",
    "activeFocus": "삭제하기 전에 이 작업의 집중 세션을 중지하세요.",
    "focusChanged":
      "다른 기기에서 집중 세션이 변경되었습니다. 새로고침한 후 다시 시도하세요.",
    "expired":
      "다시 연결하려면 Telegram에서 미니 앱을 다시 여세요. 보류 중인 변경 사항은 저장되어 있습니다.",
    "offline":
      "연결되어 있지 않습니다. 다시 온라인 상태가 되면 변경 사항이 동기화됩니다.",
    "notElapsed": "집중 시간이 아직 끝나지 않았습니다.",
    "deadline": "마감일",
    "repeat": "반복",
    "timedHint":
      "날짜를 변경하면 현재 시간 설정이 하루 종일 일정으로 바뀝니다.",
    "recurringHint": "반복 설정은 유지됩니다. 삭제하려면 Pomodoist를 여세요.",
    "inbox": "받은 편지함",
    "addPlaceholder": "작업 추가",
    "add": "추가",
    "focus": "집중",
    "empty": "받은 편지함이 비어 있습니다",
    "undo": "실행 취소",
    "completed": "작업 완료됨",
    "pause": "일시 정지",
    "resume": "재개",
    "stop": "중지",
    "settings": "계정",
    "guest": "Telegram 게스트",
    "linked": "Pomodoist에 연결됨",
    "signIn": "Pomodoist에 로그인",
    "signOut": "로그아웃",
    "signingOut": "로그아웃 중…",
    "signOutConfirm":
      "Pomodoist에서 로그아웃할까요? 미니 앱은 비어 있는 새 게스트 계정으로 계속됩니다.",
    "close": "닫기",
    "retry": "다시 시도",
    "loading": "불러오는 중…",
    "opening": "안전한 로그인 화면을 여는 중…",
    "outsideTitle": "Telegram에서 Pomodoist 열기",
    "outsideBody": "이 미니 앱은 Telegram 안에서만 사용할 수 있습니다.",
    "openBot": "@pomodoist_bot 열기",
    "error": "문제가 발생했습니다. 다시 시도하세요.",
    "linkConflict":
      "계정을 연결하기 전에 실행 중인 집중 세션 하나를 중지하세요.",
    "linkExpired": "로그인 링크가 만료되었습니다. 새 링크를 만드세요.",
  },
  "ja": {
    "direction": "ltr",
    "today": "今日",
    "upcoming": "今後の予定",
    "completedView": "完了済み",
    "task": "タスク",
    "taskDetails": "タスクの詳細",
    "title": "タイトル",
    "note": "コメント",
    "schedule": "日付 · 終日",
    "priority": "優先度",
    "save": "変更を保存",
    "complete": "完了にする",
    "restore": "元に戻す",
    "startFocus": "集中を開始",
    "delete": "削除",
    "cancel": "キャンセル",
    "deleteConfirm":
      "このタスクとサブタスクを削除しますか？この操作は取り消せません。",
    "refresh": "更新",
    "previous": "前へ",
    "next": "次へ",
    "noDate": "日付なし",
    "open": "未完了",
    "done": "完了済み",
    "emptyView": "タスクはありません",
    "taskCount": "タスク数",
    "focusReady": "集中する時間です",
    "focusHint": "タスクを選んでも、選ばなくても、25分間集中できます。",
    "chooseTask": "タスクを選択",
    "focusing": "集中セッション",
    "paused": "一時停止中",
    "finish": "セッションを終了",
    "openApp": "Pomodoistを開く",
    "saving": "保存中…",
    "pending": "変更はこのデバイスに保存されています。同期待ちです。",
    "all": "すべてのタスク",
    "updatedAt": "{time}に更新",
    "refreshFailed": "タスクを更新できませんでした。",
    "changed":
      "このタスクは別のデバイスで変更されました。更新してから再度保存してください。",
    "notFound": "タスクが見つかりません。リストを更新してください。",
    "requiresApp":
      "この繰り返しタスクや大きなタスク階層を変更するには、Pomodoistを開いてください。",
    "activeFocus":
      "削除する前に、このタスクの集中セッションを停止してください。",
    "focusChanged":
      "集中セッションが別のデバイスで変更されました。更新してやり直してください。",
    "expired":
      "再接続するにはTelegramでミニアプリを開き直してください。未同期の変更は保存されています。",
    "offline": "オフラインです。接続が回復すると変更が同期されます。",
    "notElapsed": "集中時間がまだ終了していません。",
    "deadline": "締め切り",
    "repeat": "繰り返し",
    "timedHint":
      "日付を変更すると、現在の時刻指定が終日の予定に置き換わります。",
    "recurringHint":
      "繰り返しは維持されます。解除するにはPomodoistを開いてください。",
    "inbox": "受信トレイ",
    "addPlaceholder": "タスクを追加",
    "add": "追加",
    "focus": "集中",
    "empty": "受信トレイは空です",
    "undo": "元に戻す",
    "completed": "タスクを完了しました",
    "pause": "一時停止",
    "resume": "再開",
    "stop": "停止",
    "settings": "アカウント",
    "guest": "Telegramゲスト",
    "linked": "Pomodoistに接続済み",
    "signIn": "Pomodoistにログイン",
    "signOut": "ログアウト",
    "signingOut": "ログアウト中…",
    "signOutConfirm":
      "Pomodoistからログアウトしますか？ミニアプリは新しい空のゲストアカウントで続行します。",
    "close": "閉じる",
    "retry": "再試行",
    "loading": "読み込み中…",
    "opening": "安全なログイン画面を開いています…",
    "outsideTitle": "TelegramでPomodoistを開く",
    "outsideBody": "このミニアプリはTelegram内でのみ利用できます。",
    "openBot": "@pomodoist_botを開く",
    "error": "問題が発生しました。もう一度お試しください。",
    "linkConflict":
      "アカウントを連携する前に、実行中の集中セッションのいずれかを停止してください。",
    "linkExpired":
      "ログインリンクの有効期限が切れました。新しいリンクを作成してください。",
  },
  "pt-BR": {
    "direction": "ltr",
    "today": "Hoje",
    "upcoming": "Próximas",
    "completedView": "Concluídas",
    "task": "Tarefa",
    "taskDetails": "Detalhes da tarefa",
    "title": "Título",
    "note": "Comentário",
    "schedule": "Data · dia inteiro",
    "priority": "Prioridade",
    "save": "Salvar alterações",
    "complete": "Concluir",
    "restore": "Restaurar",
    "startFocus": "Iniciar foco",
    "delete": "Excluir",
    "cancel": "Cancelar",
    "deleteConfirm":
      "Excluir esta tarefa e suas subtarefas? Esta ação não pode ser desfeita.",
    "refresh": "Atualizar",
    "previous": "Anterior",
    "next": "Próxima",
    "noDate": "Sem data",
    "open": "Aberta",
    "done": "Concluída",
    "emptyView": "Nenhuma tarefa aqui",
    "taskCount": "Tarefas",
    "focusReady": "Hora de se concentrar",
    "focusHint": "Concentre-se por 25 minutos, com ou sem uma tarefa.",
    "chooseTask": "Escolher tarefa",
    "focusing": "Sessão de foco",
    "paused": "Pausada",
    "finish": "Encerrar sessão",
    "openApp": "Abrir Pomodoist",
    "saving": "Salvando…",
    "pending": "Alterações salvas neste dispositivo. Aguardando sincronização.",
    "all": "Todas as tarefas",
    "updatedAt": "Atualizado às {time}",
    "refreshFailed": "Não foi possível atualizar as tarefas.",
    "changed":
      "Esta tarefa foi alterada em outro dispositivo. Atualize antes de salvar novamente.",
    "notFound": "Tarefa não encontrada. Atualize a lista.",
    "requiresApp":
      "Abra o Pomodoist para alterar esta tarefa recorrente ou este grupo grande de subtarefas.",
    "activeFocus": "Pare a sessão de foco desta tarefa antes de excluí-la.",
    "focusChanged":
      "O foco foi alterado em outro dispositivo. Atualize e tente novamente.",
    "expired":
      "Reabra o Mini App no Telegram para reconectar. As alterações pendentes estão salvas.",
    "offline":
      "Sem conexão. Suas alterações serão sincronizadas quando você voltar a ficar online.",
    "notElapsed": "O intervalo de foco ainda não terminou.",
    "deadline": "Prazo",
    "repeat": "Repetição",
    "timedHint":
      "Alterar a data substitui o horário atual por uma programação de dia inteiro.",
    "recurringHint":
      "A repetição será mantida. Para removê-la, abra o Pomodoist.",
    "inbox": "Caixa de entrada",
    "addPlaceholder": "Adicionar tarefa",
    "add": "Adicionar",
    "focus": "Foco",
    "empty": "Sua caixa de entrada está vazia",
    "undo": "Desfazer",
    "completed": "Tarefa concluída",
    "pause": "Pausar",
    "resume": "Retomar",
    "stop": "Parar",
    "settings": "Conta",
    "guest": "Convidado do Telegram",
    "linked": "Conectado ao Pomodoist",
    "signIn": "Entrar no Pomodoist",
    "signOut": "Sair",
    "signingOut": "Saindo…",
    "signOutConfirm":
      "Sair do Pomodoist? O Mini App continuará com uma nova conta de convidado vazia.",
    "close": "Fechar",
    "retry": "Tentar novamente",
    "loading": "Carregando…",
    "opening": "Abrindo login seguro…",
    "outsideTitle": "Abra o Pomodoist no Telegram",
    "outsideBody": "Este Mini App está disponível apenas no Telegram.",
    "openBot": "Abrir @pomodoist_bot",
    "error": "Algo deu errado. Tente novamente.",
    "linkConflict":
      "Pare uma das sessões de foco ativas antes de vincular as contas.",
    "linkExpired": "O link de login expirou. Crie um novo.",
  },
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
    signOutConfirm:
      "确定退出 Pomodoist？Mini App 将使用一个新的空白访客账户继续运行。",
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
  const base = String(languageCode).toLowerCase().split(/[-_]/)[0];
  if (base === "pt") return "pt-BR";
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

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { registerCollaborationTool } from "./collaboration_tools.ts";
import { mutate } from "./mutation_helpers.ts";
import { pomodoistMutationPlans } from "./mutation_plans.ts";
import { type PomodoistMcpAuth, toolSuccess } from "./pomodoist_mcp.ts";
import {
  Context,
  PomodoistToolDependencies,
  ToolFailure,
  date,
  entityId,
  listTasksSchema,
  noArgs,
  number,
  outputEnvelope,
  outputSchemas,
  paged,
  readOutputSchemas,
  readRpc,
  record,
  report,
  safe,
  timeZone,
} from "./tool_core.ts";

export { pomodoistMutationPlans };
export type { PomodoistToolDependencies } from "./tool_core.ts";

function registerRead(
  server: McpServer,
  operation: string,
  inputSchema: z.ZodType,
  annotations: { readOnlyHint: boolean; openWorldHint: boolean },
  context: Context,
  transform: (data: unknown) => unknown = (data) => data,
) {
  const outputSchema = readOutputSchemas[operation];
  if (!outputSchema) {
    throw new Error(`Missing output schema for ${operation}.`);
  }
  server.registerTool(
    operation,
    { inputSchema, outputSchema, annotations },
    safe(async (arguments_: unknown) =>
      toolSuccess(transform(
        await readRpc(
          context,
          operation,
          record(arguments_) ?? {},
        ),
      ))
    ),
  );
}

export function registerPomodoistTools(
  server: McpServer,
  auth: PomodoistMcpAuth,
  dependencies: PomodoistToolDependencies,
) {
  const fetcher = dependencies.fetch ?? fetch;
  const context = {
    auth,
    config: dependencies.config,
    fetcher,
    log: dependencies.log ?? (() => {}),
  };
  const readAnnotations = {
    readOnlyHint: true,
    openWorldHint: false,
  };

  registerRead(
    server,
    "list_tasks",
    listTasksSchema,
    readAnnotations,
    context,
  );
  registerRead(
    server,
    "get_task",
    z.object({ task_id: entityId }).strict(),
    readAnnotations,
    context,
    (data) => {
      const value = record(data);
      if (value?.status !== "found") {
        throw new ToolFailure("not_found", "Task not found.");
      }
      return value.task;
    },
  );
  registerRead(server, "list_projects", paged, readAnnotations, context);
  registerRead(server, "list_labels", paged, readAnnotations, context);
  registerRead(server, "get_kanban_board", noArgs, readAnnotations, context);
  registerRead(server, "list_focus_history", paged, readAnnotations, context);
  registerRead(
    server,
    "get_productivity_report",
    report,
    readAnnotations,
    context,
    productivityReport,
  );
  server.registerTool(
    "get_achievements",
    {
      inputSchema: z.object({
        date,
        time_zone: timeZone,
        locale: z.enum(["ru", "en", "pt", "pt-BR", "ja", "ko"]),
      }).strict(),
      outputSchema: outputSchemas.achievements,
      annotations: readAnnotations,
    },
    safe(async ({ locale, ...arguments_ }) => {
      const metrics = await readRpc(context, "get_achievements", arguments_);
      return toolSuccess(achievements(metrics, locale));
    }),
  );

  for (const definition of pomodoistMutationPlans(auth, dependencies)) {
    server.registerTool(definition.name, definition.config, safe(async arguments_ => {
      const plan = await definition.plan(arguments_);
      return mutate(context, plan.operations, plan.result);
    }));
  }
  registerCollaborationTool(server, auth, dependencies, outputEnvelope(z.record(z.string(), z.unknown())));
}

function productivityReport(value: unknown) {
  const report = record(value) ?? {};
  return {
    reportDate: report.reportDate,
    timeZone: report.timeZone,
    daily: report.daily,
    plannedFocusIntervals: report.plannedFocusIntervals,
    openTasks: report.openTasks,
    allTime: report.allTime,
    lastSevenDays: report.lastSevenDays,
  };
}

function achievements(
  value: unknown,
  locale: "ru" | "en" | "pt" | "pt-BR" | "ja" | "ko",
) {
  const inputs = record(record(value)?.achievementInputs) ?? {};
  const completedTasks = number(inputs.completedTasks);
  const completedFocus = number(inputs.completedWorkIntervals);
  const flags = record(inputs.comboFlags) ?? {};
  return achievementCatalog().map((definition) => {
    const progress = definition.group === "task"
      ? completedTasks
      : definition.group === "focus"
      ? completedFocus
      : flags["flag" in definition ? definition.flag : ""] === true
      ? 1
      : 0;
    return {
      id: definition.id,
      group: definition.group,
      presentation: definition.group === "combo"
        ? "bottomPlaque"
        : "globalBanner",
      ...achievementCopy(definition, locale),
      progress: Math.min(progress, definition.target),
      target: definition.target,
      unlocked: progress >= definition.target,
    };
  });
}

function achievementCopy(
  definition: {
    id: string;
    group: string;
    target: number;
    ru: { title: string; subtitle: string };
    en: { title: string; subtitle: string };
  },
  locale: "ru" | "en" | "pt" | "pt-BR" | "ja" | "ko",
) {
  if (locale === "ru" || locale === "en") return definition[locale];
  const copy = achievementTranslations[locale === "pt-BR" ? "pt" : locale];
  return {
    title: copy.titles[definition.id],
    subtitle: definition.group === "focus"
      ? copy.focusSubtitle(definition.target)
      : definition.group === "task"
      ? copy.taskSubtitle(definition.target)
      : copy.comboSubtitles[definition.id],
  };
}

// Keep localized copy aligned with lib/l10n/app_{locale}.arb; IDs remain shared.
const achievementTranslations: Record<"pt" | "ja" | "ko", {
  titles: Record<string, string>;
  focusSubtitle: (count: number) => string;
  taskSubtitle: (count: number) => string;
  comboSubtitles: Record<string, string>;
}> = {
  pt: {
    titles: {
      "focus_1": "Primeiro tomate",
      "focus_5": "Aquecimento",
      "focus_10": "Foco encontrado",
      "focus_25": "Turno de tomates",
      "focus_50": "Modo ativado",
      "focus_100": "Faixa vermelha",
      "focus_250": "Raízes profundas",
      "focus_500": "Autoridade do timer",
      "focus_1000": "Milésimo tomate",
      "focus_5000": "Fazendeiro do foco",
      "focus_10000": "Plantação de atenção",
      "focus_50000": "Império do tomate",
      "focus_100000": "Supermente vermelha",
      "focus_1000000": "Singularidade do tomate",
      "task_1": "Primeira marca",
      "task_5": "A lista tremeu",
      "task_10": "Caixa feliz",
      "task_25": "Limpando a pilha",
      "task_50": "Mestre das marcas",
      "task_100": "Pontas soltas resolvidas",
      "task_250": "Lista sob controle",
      "task_500": "Nocaute no escritório",
      "task_1000": "Mil marcas",
      "task_5000": "Arquivista de vitórias",
      "task_10000": "Máquina de marcar",
      "task_50000": "Escritório de assuntos resolvidos",
      "task_100000": "Senhor das listas",
      "task_1000000": "Marca final",
      "combo_day_not_wasted": "Dia bem aproveitado",
      "combo_focus_plus_check": "Foco + marca",
      "combo_no_fuss": "Sem correria",
      "combo_clean_entry": "Entrada perfeita",
      "combo_tomato_closed_question": "O tomate resolveu",
    },
    focusSubtitle: (count) =>
      count === 1
        ? "Conclua 1 foco de trabalho"
        : `Conclua ${count} focos de trabalho`,
    taskSubtitle: (count) =>
      count === 1 ? "Conclua 1 tarefa" : `Conclua ${count} tarefas`,
    comboSubtitles: {
      "combo_day_not_wasted": "Conclua um foco e uma tarefa no mesmo dia",
      "combo_focus_plus_check": "Conclua 3 focos e 3 tarefas no mesmo dia",
      "combo_no_fuss": "Conclua 5 focos no mesmo dia sem interrupções",
      "combo_clean_entry": "Conclua uma tarefa após o foco vinculado a ela",
      "combo_tomato_closed_question":
        "Conclua uma tarefa no dia do seu foco de trabalho",
    },
  },
  ja: {
    titles: {
      "focus_1": "初めてのトマト",
      "focus_5": "ウォームアップ",
      "focus_10": "集中をつかんだ",
      "focus_25": "トマト勤務",
      "focus_50": "モード起動",
      "focus_100": "赤帯",
      "focus_250": "深い根",
      "focus_500": "タイマーの達人",
      "focus_1000": "千個目のトマト",
      "focus_5000": "集中農家",
      "focus_10000": "注意力の農園",
      "focus_50000": "トマト帝国",
      "focus_100000": "赤い超知能",
      "focus_1000000": "トマト特異点",
      "task_1": "初めてのチェック",
      "task_5": "リストが揺れた",
      "task_10": "うれしいチェックボックス",
      "task_25": "山積みを片付ける",
      "task_50": "チェックの達人",
      "task_100": "やり残しを解決",
      "task_250": "リストを掌握",
      "task_500": "オフィスの完全勝利",
      "task_1000": "千個のチェック",
      "task_5000": "勝利の記録係",
      "task_10000": "チェックマシン",
      "task_50000": "解決済み案件局",
      "task_100000": "リストの支配者",
      "task_1000000": "最後のチェック",
      "combo_day_not_wasted": "実りある1日",
      "combo_focus_plus_check": "集中＋チェック",
      "combo_no_fuss": "慌てず着実に",
      "combo_clean_entry": "きれいな流れ",
      "combo_tomato_closed_question": "トマトが解決",
    },
    focusSubtitle: (count) =>
      count === 1
        ? "作業の集中を1回完了する"
        : `作業の集中を${count}回完了する`,
    taskSubtitle: (count) =>
      count === 1 ? "タスクを1件完了する" : `タスクを${count}件完了する`,
    comboSubtitles: {
      "combo_day_not_wasted": "1日で集中1回とタスク1件を完了する",
      "combo_focus_plus_check": "1日で集中3回とタスク3件を完了する",
      "combo_no_fuss": "1日で集中を中断せずに5回完了する",
      "combo_clean_entry": "紐付けられた集中の後にタスクを完了する",
      "combo_tomato_closed_question": "作業の集中と同じ日にタスクを完了する",
    },
  },
  ko: {
    titles: {
      "focus_1": "첫 토마토",
      "focus_5": "준비 운동",
      "focus_10": "집중 포착",
      "focus_25": "토마토 근무",
      "focus_50": "모드 가동",
      "focus_100": "빨간 띠",
      "focus_250": "깊은 뿌리",
      "focus_500": "타이머의 권위자",
      "focus_1000": "천 번째 토마토",
      "focus_5000": "집중 농부",
      "focus_10000": "주의력 농장",
      "focus_50000": "토마토 제국",
      "focus_100000": "붉은 초지능",
      "focus_1000000": "토마토 특이점",
      "task_1": "첫 체크",
      "task_5": "목록이 흔들렸다",
      "task_10": "행복한 체크박스",
      "task_25": "쌓인 일 정리",
      "task_50": "체크의 달인",
      "task_100": "마무리 해결사",
      "task_250": "목록 장악",
      "task_500": "사무실 완승",
      "task_1000": "천 개의 체크",
      "task_5000": "승리의 기록관",
      "task_10000": "체크 머신",
      "task_50000": "문제 해결국",
      "task_100000": "목록의 지배자",
      "task_1000000": "마지막 체크",
      "combo_day_not_wasted": "알찬 하루",
      "combo_focus_plus_check": "집중 + 체크",
      "combo_no_fuss": "차분하게",
      "combo_clean_entry": "깔끔한 시작",
      "combo_tomato_closed_question": "토마토가 해결했다",
    },
    focusSubtitle: (count) =>
      count === 1 ? "작업 집중 1회 완료" : `작업 집중 ${count}회 완료`,
    taskSubtitle: (count) =>
      count === 1 ? "작업 1개 완료" : `작업 ${count}개 완료`,
    comboSubtitles: {
      "combo_day_not_wasted": "하루에 집중 한 번과 작업 하나 완료",
      "combo_focus_plus_check": "하루에 집중 3회와 작업 3개 완료",
      "combo_no_fuss": "하루에 중단 없이 집중 5회 완료",
      "combo_clean_entry": "연결된 집중 후 작업 완료",
      "combo_tomato_closed_question": "작업 집중을 한 날에 해당 작업 완료",
    },
  },
};

const focusTargets = [
  1,
  5,
  10,
  25,
  50,
  100,
  250,
  500,
  1000,
  5000,
  10000,
  50000,
  100000,
  1000000,
];
const taskTargets = [...focusTargets];
function achievementCatalog() {
  return [
    ...focusTargets.map((target) => ({
      id: `focus_${target}`,
      group: "focus",
      target,
      ru: {
        title: focusTitlesRu[target],
        subtitle: `Завершить ${target} work-фокус${target === 1 ? "" : "ов"}`,
      },
      en: {
        title: focusTitlesEn[target],
        subtitle: `Complete ${target} work focus${target === 1 ? "" : "es"}`,
      },
    })),
    ...taskTargets.map((target) => ({
      id: `task_${target}`,
      group: "task",
      target,
      ru: {
        title: taskTitlesRu[target],
        subtitle: `Закрыть ${target} задач${target === 1 ? "у" : ""}`,
      },
      en: {
        title: taskTitlesEn[target],
        subtitle: `Complete ${target} task${target === 1 ? "" : "s"}`,
      },
    })),
    {
      id: "combo_day_not_wasted",
      group: "combo",
      flag: "dayNotWasted",
      target: 1,
      ru: {
        title: "День не зря",
        subtitle: "За день есть фокус и закрытая задача",
      },
      en: {
        title: "Day not wasted",
        subtitle: "Finish a focus and a task in one day",
      },
    },
    {
      id: "combo_focus_plus_check",
      group: "combo",
      flag: "focusPlusCheck",
      target: 1,
      ru: {
        title: "Фокус + галочка",
        subtitle: "За день есть 3 фокуса и 3 задачи",
      },
      en: {
        title: "Focus + check",
        subtitle: "Finish 3 focuses and 3 tasks in one day",
      },
    },
    {
      id: "combo_no_fuss",
      group: "combo",
      flag: "noFuss",
      target: 1,
      ru: { title: "Без суеты", subtitle: "5 фокусов за день без остановок" },
      en: {
        title: "No fuss",
        subtitle: "Finish 5 focuses in a day without stops",
      },
    },
    {
      id: "combo_clean_entry",
      group: "combo",
      flag: "cleanEntry",
      target: 1,
      ru: {
        title: "Чистый заход",
        subtitle: "Закрыть задачу после связанного фокуса",
      },
      en: {
        title: "Clean entry",
        subtitle: "Complete a task after its linked focus",
      },
    },
    {
      id: "combo_tomato_closed_question",
      group: "combo",
      flag: "tomatoClosed",
      target: 1,
      ru: {
        title: "Помидор закрыл вопрос",
        subtitle: "Закрыть задачу в день ее work-фокуса",
      },
      en: {
        title: "Tomato closed it",
        subtitle: "Complete a task on the day of its work focus",
      },
    },
  ];
}

const focusTitlesRu: Record<number, string> = {
  1: "Первый помидор",
  5: "Разогрев",
  10: "Фокус пойман",
  25: "Помидорная смена",
  50: "Режим включен",
  100: "Красный пояс",
  250: "Глубокая посадка",
  500: "Таймерный авторитет",
  1000: "Тысячный помидор",
  5000: "Фермер фокуса",
  10000: "Плантация внимания",
  50000: "Помидорная империя",
  100000: "Красный сверхразум",
  1000000: "Сингулярность помидора",
};
const focusTitlesEn: Record<number, string> = {
  1: "First tomato",
  5: "Warm-up",
  10: "Focus caught",
  25: "Tomato shift",
  50: "Mode on",
  100: "Red belt",
  250: "Deep roots",
  500: "Timer authority",
  1000: "Thousandth tomato",
  5000: "Focus farmer",
  10000: "Attention plantation",
  50000: "Tomato empire",
  100000: "Red supermind",
  1000000: "Tomato singularity",
};
const taskTitlesRu: Record<number, string> = {
  1: "Первая галочка",
  5: "Список дрогнул",
  10: "Чекбокс доволен",
  25: "Разбор завалов",
  50: "Мастер галочек",
  100: "Закрыватель хвостов",
  250: "Список под контролем",
  500: "Канцелярский нокаут",
  1000: "Тысяча галочек",
  5000: "Архивариус побед",
  10000: "Чекбокс-машина",
  50000: "Бюро закрытых вопросов",
  100000: "Повелитель списков",
  1000000: "Последняя галочка",
};
const taskTitlesEn: Record<number, string> = {
  1: "First check",
  5: "The list flinched",
  10: "Happy checkbox",
  25: "Clearing the pile",
  50: "Checkmark master",
  100: "Tail closer",
  250: "List under control",
  500: "Office knockout",
  1000: "Thousand checks",
  5000: "Victory archivist",
  10000: "Checkbox machine",
  50000: "Bureau of closed questions",
  100000: "List ruler",
  1000000: "Final check",
};

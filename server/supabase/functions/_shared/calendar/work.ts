export type RemoteHint = {
  eventId: string;
  version: string | null;
  kind: "created" | "updated" | "deleted";
};
export type Work = {
  generation: number;
  hints: (RemoteHint & { generation: number })[];
  publishRevision: number | null;
  refresh: boolean;
  recovery: boolean;
  maintenance: boolean;
};
export type WorkInput = Partial<Omit<Work, "generation" | "hints">> & {
  hints?: RemoteHint[];
};
export function emptyWork(): Work {
  return {
    generation: 0,
    hints: [],
    publishRevision: null,
    refresh: false,
    recovery: false,
    maintenance: false,
  };
}
export function mergeWork(current: Work, incoming: WorkInput): Work {
  const generation = current.generation + 1;
  const hints = new Map(current.hints.map((hint) => [hint.eventId, hint]));
  for (const hint of incoming.hints ?? []) {
    hints.set(hint.eventId, { ...hint, generation });
  }
  const overflow = hints.size > 1000;
  return {
    generation,
    hints: overflow ? [] : [...hints.values()],
    publishRevision: incoming.publishRevision == null
      ? current.publishRevision
      : Math.max(current.publishRevision ?? 0, incoming.publishRevision),
    refresh: current.refresh || incoming.refresh === true,
    recovery: current.recovery || incoming.recovery === true || overflow,
    maintenance: current.maintenance || incoming.maintenance === true,
  };
}
export function consumeWork(current: Work, claimed: Work): Work {
  if (current.generation === claimed.generation) {
    return { ...emptyWork(), generation: current.generation };
  }
  return {
    ...current,
    hints: current.hints.filter((hint) => hint.generation > claimed.generation),
  };
}
export function readRequired(work: Work): boolean {
  return work.refresh || work.recovery || work.publishRevision !== null ||
    work.hints.length > 0;
}

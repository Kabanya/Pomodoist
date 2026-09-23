// Standalone interval timer. It is deliberately unrelated to tasks and to the
// synced Focus entities: nothing here leaves the popup, so no server contract
// is involved. This module stays free of DOM and chrome APIs so the reducer can
// be unit tested directly.
export const PRESETS = [15, 5, 25, 50];
export const BREAK_MINUTES = 5;
export const DEFAULT_MINUTES = 25;
export function phaseDuration(phase, minutes) { return (phase === 'break' ? BREAK_MINUTES : minutes) * 60000; }
export function initial(minutes = DEFAULT_MINUTES) {
  return { phase: 'focus', minutes, endsAt: null, remaining: phaseDuration('focus', minutes), running: false, completed: 0 };
}
function stopped(timer, phase, minutes) {
  return { ...timer, phase, minutes, endsAt: null, running: false, remaining: phaseDuration(phase, minutes) };
}
export function remainingMs(timer, now = Date.now()) {
  return timer.running && timer.endsAt !== null ? Math.max(0, timer.endsAt - now) : timer.remaining;
}
// A cached payload is only trusted when every field is usable. A single bad
// number here would put NaN into the countdown and freeze it forever, so the
// payload is validated as a whole rather than field by field.
export const MAX_CACHE_AGE = 86400000;
export function restore(saved, now = Date.now()) {
  if (!saved || typeof saved !== 'object') return null;
  const { phase, minutes, running, remaining, endsAt, savedAt } = saved;
  if (!PRESETS.includes(minutes) || !['focus', 'break'].includes(phase)) return null;
  if (!Number.isFinite(savedAt) || now - savedAt >= MAX_CACHE_AGE) return null;
  if (!Number.isFinite(remaining) || remaining < 0) return null;
  if (running && (!Number.isFinite(endsAt) || endsAt <= 0)) return null;
  if (running) {
    const left = Math.max(0, endsAt - now);
    // The deadline already passed while the popup was closed. Show the phase as
    // finished rather than resuming an interval that has no time left.
    if (left === 0) return { ...initial(minutes), phase, minutes, completed: saved.completed ?? 0 };
    return { ...initial(minutes), phase, minutes, running: true, endsAt, remaining: left, completed: saved.completed ?? 0 };
  }
  return { ...initial(minutes), phase, minutes, running: false, remaining, completed: saved.completed ?? 0 };
}
export function reduce(timer, action, now = Date.now()) {
  if (action.type === 'start') {
    if (timer.running) return { timer, effect: '' };
    return { timer: { ...timer, running: true, endsAt: now + timer.remaining }, effect: '' };
  }
  if (action.type === 'pause') {
    return { timer: { ...timer, running: false, endsAt: null, remaining: remainingMs(timer, now) }, effect: '' };
  }
  if (action.type === 'reset') return { timer: stopped(timer, 'focus', timer.minutes), effect: '' };
  if (action.type === 'setMinutes') {
    // An unlisted duration would put NaN into endsAt, which would then compare
    // false forever and freeze the timer. Refuse it instead.
    if (!PRESETS.includes(action.minutes)) return { timer, effect: '' };
    return { timer: stopped(timer, 'focus', action.minutes), effect: '' };
  }
  if (action.type !== 'tick' || !timer.running || timer.endsAt === null || now < timer.endsAt) return { timer, effect: '' };
  if (timer.phase === 'focus') {
    const next = { ...stopped(timer, 'break', timer.minutes), completed: timer.completed + 1 };
    return { timer: { ...next, running: true, endsAt: now + next.remaining }, effect: 'focusEnded' };
  }
  // A break that is never acknowledged must not roll into the next focus
  // interval on its own; the popup may be closed for hours.
  return { timer: { ...stopped(timer, 'focus', timer.minutes), remaining: 0 }, effect: 'breakEnded' };
}

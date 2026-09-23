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

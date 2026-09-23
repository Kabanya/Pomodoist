import test from 'node:test';
import assert from 'node:assert/strict';
import { BREAK_MINUTES, DEFAULT_MINUTES, PRESETS, initial, phaseDuration, reduce, remainingMs } from '../src/timer.js';

const at = 1_800_000_000_000;

test('a new timer is a stopped full focus interval', () => {
  const timer = initial();
  assert.deepEqual(timer, { phase: 'focus', minutes: DEFAULT_MINUTES, endsAt: null, remaining: 25 * 60000, running: false, completed: 0 });
  assert.equal(phaseDuration('focus', 15), 15 * 60000);
  assert.equal(phaseDuration('break', 50), BREAK_MINUTES * 60000);
});
test('start, pause and reset move between running and stopped without losing the preset', () => {
  const started = reduce(initial(15), { type: 'start' }, at).timer;
  assert.equal(started.running, true);
  assert.equal(started.endsAt, at + 15 * 60000);
  const paused = reduce(started, { type: 'pause' }, at + 5 * 60000).timer;
  assert.equal(paused.running, false);
  assert.equal(paused.endsAt, null);
  assert.equal(paused.remaining, 10 * 60000);
  assert.equal(reduce(paused, { type: 'reset' }).timer.remaining, 15 * 60000);
  assert.equal(reduce(paused, { type: 'reset' }).timer.minutes, 15);
});
test('a running timer counts down against the wall clock, not against tick count', () => {
  const started = reduce(initial(25), { type: 'start' }, at).timer;
  assert.equal(remainingMs(started, at + 90_000), 25 * 60000 - 90_000);
  assert.equal(remainingMs(started, at + 99 * 60000), 0);
});
test('restarting an already running timer is a no-op instead of extending the interval', () => {
  const started = reduce(initial(25), { type: 'start' }, at).timer;
  assert.equal(reduce(started, { type: 'start' }, at + 60000).timer.endsAt, started.endsAt);
});
test('a finished focus interval rolls into a break that can be acknowledged', () => {
  const started = reduce(initial(25), { type: 'start' }, at).timer;
  const { timer, effect } = reduce(started, { type: 'tick' }, at + 25 * 60000);
  assert.equal(effect, 'focusEnded');
  assert.equal(timer.phase, 'break');
  assert.equal(timer.running, true);
  assert.equal(timer.completed, 1);
  assert.equal(remainingMs(timer, at + 25 * 60000), BREAK_MINUTES * 60000);
});
test('a finished break stops instead of starting the next focus interval unattended', () => {
  const running = { ...initial(25), phase: 'break', running: true, endsAt: at + 60000, remaining: 60000 };
  const { timer, effect } = reduce(running, { type: 'tick' }, at + 60000);
  assert.equal(effect, 'breakEnded');
  assert.equal(timer.phase, 'focus');
  assert.equal(timer.running, false);
  assert.equal(timer.remaining, 0);
});
test('ticks before the deadline and ticks on a stopped timer change nothing', () => {
  const started = reduce(initial(25), { type: 'start' }, at).timer;
  assert.deepEqual(reduce(started, { type: 'tick' }, at + 60000), { timer: started, effect: '' });
  const stopped = initial();
  assert.deepEqual(reduce(stopped, { type: 'tick' }, at), { timer: stopped, effect: '' });
});
test('only listed presets are accepted, so a bad duration cannot freeze the countdown', () => {
  const timer = initial(25);
  for (const minutes of [0, -5, 1.5, 99, NaN, '25']) {
    assert.deepEqual(reduce(timer, { type: 'setMinutes', minutes }), { timer, effect: '' }, String(minutes));
  }
  for (const minutes of PRESETS) {
    const next = reduce(timer, { type: 'setMinutes', minutes }).timer;
    assert.equal(next.minutes, minutes);
    assert.equal(next.remaining, minutes * 60000);
  }
});
test('choosing a preset clears a stale deadline and stops the previous interval', () => {
  const started = reduce(initial(25), { type: 'start' }, at).timer;
  const next = reduce(started, { type: 'setMinutes', minutes: 50 }).timer;
  assert.equal(next.endsAt, null);
  assert.equal(next.running, false);
  assert.equal(next.phase, 'focus');
  assert.equal(remainingMs(next, at + 60000), 50 * 60000);
});
test('an unknown action is ignored', () => {
  const timer = initial();
  assert.deepEqual(reduce(timer, { type: 'teleport' }, at), { timer, effect: '' });
});

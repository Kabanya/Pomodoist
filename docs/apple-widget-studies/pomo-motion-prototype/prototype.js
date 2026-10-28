'use strict';

const poseRoot = '../../../apps/flutter/assets/pomo/';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const reducePreview = document.getElementById('reduce');
const announcement = document.getElementById('announcement');
const running = new Map();
const reactions = {
  focus: { widget: 'focus', pose: 'focus', label: 'Thinking', motion: 'attentive' },
  break: { widget: 'focus', pose: 'rest', label: 'Resting', motion: 'sway' },
  pause: { widget: 'focus', pose: 'calm', label: 'Paused', motion: 'settle' },
  task: { widget: 'tasks', pose: 'happy', label: 'Happy', motion: 'hop' },
  habit: { widget: 'habits', pose: 'happy', label: 'Happy', motion: 'hop' },
  day: { widget: 'day', pose: 'focus', label: 'Attentive', motion: 'attentive' },
  progress: { widget: 'progress', pose: 'happy', label: 'Proud', motion: 'hop' },
};
const moves = {
  attentive: [
    { transform: 'translateY(0) rotate(0deg)', offset: 0 },
    { transform: 'translateY(-3px) rotate(-5deg)', offset: .25 },
    { transform: 'translateY(-1px) rotate(3deg)', offset: .55 },
    { transform: 'translateY(0) rotate(0deg)', offset: 1 },
  ],
  sway: [
    { transform: 'rotate(0deg)', offset: 0 },
    { transform: 'rotate(-6deg)', offset: .25 },
    { transform: 'rotate(5deg)', offset: .65 },
    { transform: 'rotate(0deg)', offset: 1 },
  ],
  settle: [
    { transform: 'translateY(0) scale(1)', offset: 0 },
    { transform: 'translateY(3px) scale(1.025,.975)', offset: .35 },
    { transform: 'translateY(0) scale(1)', offset: 1 },
  ],
  hop: [
    { transform: 'translateY(0) scale(1)', offset: 0 },
    { transform: 'translateY(2px) scale(1.04,.96)', offset: .1 },
    { transform: 'translateY(-13px) rotate(-4deg) scale(1)', offset: .28 },
    { transform: 'translateY(1px) rotate(2deg) scale(1.03,.97)', offset: .48 },
    { transform: 'translateY(-4px) rotate(-2deg) scale(1)', offset: .65 },
    { transform: 'translateY(0) rotate(0deg) scale(1)', offset: 1 },
  ],
};

// shortcut: still-pose transforms preview motion only; validate native WidgetKit transitions before shipping.
function card(widget) {
  return document.querySelector('[data-widget="' + widget + '"]');
}

function text(id, value) {
  document.getElementById(id).textContent = value;
}

function stop(widget, message = 'Still · reaction finished') {
  const animation = running.get(widget);
  running.delete(widget);
  if (animation) animation.cancel();
  card(widget).dataset.playing = 'false';
  card(widget).querySelector('.runtime span').textContent = message;
}

function pose(widget, name, label) {
  card(widget).querySelector('.pomo img').src = poseRoot + name + '-still.webp';
  text(widget + '-tag', label);
}

function updateSample(event) {
  if (['focus', 'break', 'pause'].includes(event)) {
    text('focus-time', event === 'break' ? '05:00' : '18:42');
    text('focus-state', event === 'break' ? 'Short break' : event === 'pause' ? 'Paused' : 'Focus');
    text('focus-next', event === 'break' ? 'Next: Work interval' : 'Next: Short break');
    document.getElementById('focus-bar').style.width = event === 'break' ? '100%' : '74.8%';
  } else if (event === 'task') {
    text('task-title', 'Send proposal');
    document.getElementById('task-next').hidden = true;
  } else if (event === 'habit') {
    text('habit-total', '3 / 3');
    text('water-count', '8/8');
    text('water-check', '✓');
    document.getElementById('water-check').classList.add('done');
  } else if (event === 'day') {
    document.getElementById('first-event').classList.add('completed');
  } else if (event === 'progress') {
    text('progress-total', '9 tasks today');
  }
}

function react(event) {
  const reaction = reactions[event];
  stop(reaction.widget);
  updateSample(event);
  pose(reaction.widget, reaction.pose, reaction.label);
  if (reducedMotion.matches || reducePreview.checked) {
    stop(reaction.widget, 'Still · Reduce Motion');
    announcement.textContent = 'Expression updated. Movement disabled by Reduce Motion.';
    return;
  }
  const element = card(reaction.widget);
  const animation = element.querySelector('.pomo').animate(moves[reaction.motion], {
    duration: 2000, iterations: 1, easing: 'ease-in-out', fill: 'none',
  });
  running.set(reaction.widget, animation);
  element.dataset.playing = 'true';
  element.querySelector('.runtime span').textContent = 'Reacting · 2.0 seconds';
  announcement.textContent = 'Playing one two-second reaction. Pomo then stays still.';
  animation.finished.then(() => {
    if (running.get(reaction.widget) !== animation) return;
    stop(reaction.widget);
    if (running.size === 0) announcement.textContent = 'Finished. Pomo is still until the next event.';
  }, () => {});
}

function reset(widget) {
  stop(widget, 'Still · waiting for an event');
  pose(widget, ['tasks', 'focus'].includes(widget) ? 'focus' : 'calm', ['tasks', 'focus'].includes(widget) ? 'Thinking' : 'Calm');
  if (widget === 'tasks') {
    text('task-title', 'Design review');
    document.getElementById('task-next').hidden = false;
  } else if (widget === 'habits') {
    text('habit-total', '2 / 3');
    text('water-count', '6/8');
    text('water-check', '');
    document.getElementById('water-check').classList.remove('done');
  } else if (widget === 'day') {
    document.getElementById('first-event').classList.remove('completed');
  } else if (widget === 'progress') {
    text('progress-total', '8 tasks today');
  }
  if (running.size === 0) announcement.textContent = 'Sample reset. Ready for another reaction.';
}

function applyMotionPreference() {
  if (!reducedMotion.matches && !reducePreview.checked) return;
  for (const widget of [...running.keys()]) stop(widget, 'Still · Reduce Motion');
  announcement.textContent = 'Movement disabled. Expressions and sample data still update.';
}

for (const button of document.querySelectorAll('[data-event]')) {
  button.addEventListener('click', () => react(button.dataset.event));
}
for (const button of document.querySelectorAll('[data-reset]')) {
  button.addEventListener('click', () => reset(button.dataset.reset));
}
document.getElementById('play-all').addEventListener('click', () => {
  for (const event of ['focus', 'task', 'habit', 'day', 'progress']) react(event);
});
reducePreview.addEventListener('change', applyMotionPreference);
reducedMotion.addEventListener('change', applyMotionPreference);
document.getElementById('theme').addEventListener('click', () => {
  const dark = document.documentElement.dataset.theme !== 'dark';
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.getElementById('theme').setAttribute('aria-pressed', String(dark));
  text('theme', dark ? 'Dark appearance' : 'Light appearance');
});

// Preload pose changes so a first reaction does not wait for its image to download.
for (const name of ['focus', 'happy', 'calm', 'rest']) {
  const image = new Image();
  image.src = poseRoot + name + '-still.webp';
}

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {BridgeCore} from '../core.js';

const display = (id = 'gnome:HDMI-1', x = 0, scale = 1) => ({id, name: id,
    x, y: 0, width: 1000, height: 800, workX: x, workY: 30,
    workWidth: 1000, workHeight: 770, scale});
function fixture() {
    let pointer = {x: 120, y: 100};
    const events = [], windows = [], frames = new Set(), timers = new Set();
    const shell = {
        displays: [display(), display('gnome:DP-1', 1000, 2)],
        primaryDisplayId: 'gnome:HDMI-1',
        windows: () => windows,
        pointer: () => ({...pointer}),
        startFrames: callback => { frames.add(callback); return () => frames.delete(callback); },
        startPointer: callback => { timers.add(callback); return () => timers.delete(callback); },
        emit: (owner, value) => events.push({owner, value}),
    };
    const core = new BridgeCore(shell, '46.2');
    const window = (overrides = {}) => {
        const w = {pid: 101, role: 'pomodoist-pomo:companion:secret',
            appId: 'com.finchforge.pomodoist', mapped: true,
            rect: {x: 100, y: 80, width: 200, height: 150},
            monitor: 'gnome:HDMI-1', moves: [], resizes: [],
            bounds() { return {...this.rect}; },
            move(x, y) { this.moves.push([x, y]); this.rect.x = x; this.rect.y = y; },
            configure(r) { this.resizes.push(r); this.rect = {...r, width: Math.max(r.width, 90)}; },
            ...overrides};
        windows.push(w);
        return w;
    };
    return {core, shell, events, windows, frames, timers, window,
        point: (x, y) => { pointer = {x, y}; },
        tick: () => [...frames].forEach(f => f()),
        sample: () => [...timers].forEach(f => f())};
}

test('pending registration attaches only a token, role, app ID and caller PID match', () => {
    const f = fixture();
    assert.deepEqual(f.core.register(':1.1', 101, 'secret', 'companion'), {ready: false});
    f.window({pid: 102}); f.window({appId: 'evil.app'});
    f.window({role: 'pomodoist-pomo:settings:secret'});
    f.core.refreshWindows();
    assert.equal(f.core.command(':1.1', 101, 'secret', 'bounds', {}), null);
    const owned = f.window();
    f.core.refreshWindows();
    assert.deepEqual(f.core.command(':1.1', 101, 'secret', 'bounds', {}),
        {...owned.rect, scale: 1, displayId: 'gnome:HDMI-1'});
    assert.equal(f.events.at(-1).value.windows.secret.x, 100);
    assert.throws(() => f.core.command(':1.2', 101, 'secret', 'move', {x: 3, y: 4}), /registered/);
    assert.throws(() => f.core.command(':1.1', 102, 'secret', 'bounds', {}), /owner/);
});

test('move/configure clamp work areas and return actual Shell dimensions and scale', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    assert.equal(f.core.command(':1.1', 101, 'secret', 'move', {x: -100, y: 0}).y, 30);
    const b = f.core.command(':1.1', 101, 'secret', 'configure',
        {displayId: 'gnome:DP-1', x: 1990, y: 790, width: 40, height: 100});
    assert.equal(b.width, 90);
    assert.equal(b.displayId, 'gnome:DP-1');
    assert.equal(b.scale, 2);
    assert.ok(w.rect.x + w.rect.width <= 2000);
    assert.ok(w.rect.y + w.rect.height <= 800);
    assert.throws(() => f.core.command(':1.1', 101, 'secret', 'move', {x: NaN}), /finite/);
    assert.throws(() => f.core.command(':1.1', 101, 'secret', 'configure', {width: -1}), /positive/);
});

test('drag uses actual origin and frame pointer delta without resizing, locks work area', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    assert.equal(f.core.command(':1.1', 101, 'secret', 'dragBegin',
        {displayId: 'gnome:HDMI-1', allowCrossDisplayDrag: false}), true);
    f.point(170, 160); f.tick();
    assert.deepEqual(w.moves.at(-1), [150, 140]);
    f.point(1500, 50); f.tick();
    assert.deepEqual(w.moves.at(-1), [800, 30]);
    assert.deepEqual(f.core.command(':1.1', 101, 'secret', 'dragPosition', {}),
        {x: 1480, y: 30, width: 200, height: 150, scale: 1, displayId: 'gnome:HDMI-1'});
    assert.equal(w.resizes.length, 0);
    f.core.command(':1.1', 101, 'secret', 'dragEnd', {});
    assert.equal(f.frames.size, 0);
});

test('cross display drag adopts stable monitor identity and its logical scale', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.command(':1.1', 101, 'secret', 'dragBegin',
        {displayId: 'gnome:HDMI-1', allowCrossDisplayDrag: true});
    f.point(1500, 300); f.tick();
    const b = f.core.command(':1.1', 101, 'secret', 'bounds', {});
    assert.equal(b.displayId, 'gnome:DP-1');
    assert.equal(b.scale, 2);
    assert.equal(w.rect.x, 1480);
});

test('following leases emit initial and changed samples only to their owners', () => {
    const f = fixture();
    f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.register(':1.2', 102, 'other', 'settings');
    f.core.setFollowing(':1.1', 101, true);
    assert.deepEqual(f.events.at(-1).value.cursor, {x: 120, y: 100});
    assert.equal(f.timers.size, 1);
    const before = f.events.length;
    f.sample(); assert.equal(f.events.length, before);
    f.point(300, 400); f.sample();
    assert.equal(f.events.at(-1).owner, ':1.1');
    assert.deepEqual(f.events.at(-1).value.cursor, {x: 300, y: 400});
    f.core.setFollowing(':1.1', 101, false);
    assert.equal(f.timers.size, 0);
});

test('suppression stops drag and polling, resumes following intent without stale cursor', () => {
    const f = fixture(); f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.setFollowing(':1.1', 101, true);
    f.core.command(':1.1', 101, 'secret', 'dragBegin', {displayId: 'gnome:HDMI-1'});
    f.core.setSuppressed(true);
    assert.equal(f.frames.size, 0); assert.equal(f.timers.size, 0);
    assert.equal(f.events.at(-1).value.suppressed, true);
    assert.equal(f.core.command(':1.1', 101, 'secret', 'dragBegin', {}), false);
    f.core.setSuppressed(false);
    assert.equal(f.timers.size, 1); assert.equal(f.frames.size, 0);
});

test('unmap and Meta destruction retain pending GTK token; owner loss and disable clean loops', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    w.mapped = false; f.core.refreshWindows();
    assert.equal(f.events.at(-1).value.windows.secret, null);
    w.mapped = true; f.core.refreshWindows();
    assert.equal(f.events.at(-1).value.windows.secret.x, 100);
    f.core.windowDestroyed(w);
    assert.deepEqual(f.events.at(-1).value.windows, {secret: null});
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.setFollowing(':1.1', 101, true);
    f.core.command(':1.1', 101, 'secret', 'dragBegin', {displayId: 'gnome:HDMI-1'});
    f.core.ownerLost(':1.1');
    assert.equal(f.timers.size, 0); assert.equal(f.frames.size, 0);
    f.core.disable();
    assert.equal(f.core.capabilities().supported, false);
    assert.throws(() => f.core.register(':1.1', 101, 'secret', 'companion'), /disabled/);
});

test('topology invalidation cancels drag and broadcasts current stable IDs', () => {
    const f = fixture(); f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.command(':1.1', 101, 'secret', 'dragBegin', {displayId: 'gnome:HDMI-1'});
    f.shell.displays = [display('gnome:DP-1', 1000, 2)];
    f.shell.primaryDisplayId = 'gnome:DP-1';
    f.core.topologyChanged();
    assert.equal(f.frames.size, 0);
    assert.equal(f.events.at(-1).value.primaryDisplayId, 'gnome:DP-1');
});

test('rejects malformed inputs, duplicate token ownership and unknown commands', () => {
    const f = fixture(); f.window();
    assert.throws(() => f.core.register(':1.1', 101, '', 'companion'), /token/);
    assert.throws(() => f.core.register(':1.1', 101, 'a', 'main'), /role/);
    f.core.register(':1.1', 101, 'secret', 'companion');
    assert.throws(() => f.core.register(':1.2', 102, 'secret', 'companion'), /owned/);
    assert.throws(() => f.core.command(':1.1', 101, 'secret', 'oops', {}), /Unknown/);
    assert.throws(() => f.core.command(':1.1', 101, 'secret', 'move', null), /object/);
    f.core.command(':1.1', 101, 'secret', 'detach', {});
    assert.deepEqual(f.events.at(-1).value.windows, {});
});

test('Meta destruction after unmap retains token for a replacement mapped window', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    w.mapped = false; f.core.refreshWindows();
    f.core.windowDestroyed(w);
    assert.equal(f.core.command(':1.1', 101, 'secret', 'bounds', {}), null);
    const remapped = f.window({rect: {x: 220, y: 90, width: 200, height: 150}});
    f.core.refreshWindows();
    assert.equal(f.core.command(':1.1', 101, 'secret', 'bounds', {}).x, remapped.rect.x);
});

test('unregistered following sessions receive no directed telemetry or timers', () => {
    const f = fixture();
    f.core.setFollowing(':1.1', 101, true);
    f.core.topologyChanged();
    assert.equal(f.events.length, 0);
    assert.equal(f.timers.size, 0);
});

test('ambiguous token windows fail closed and staging flavor is allowed', () => {
    const f = fixture();
    f.window({appId: 'com.finchforge.pomodoist.stg'});
    assert.equal(f.core.register(':1.1', 101, 'secret', 'companion').ready, true);
    f.window(); f.core.refreshWindows();
    assert.equal(f.core.command(':1.1', 101, 'secret', 'bounds', {}), null);
});

test('no pointer polling on invalid topology; restoration emits fresh pointer without motion', () => {
    const f = fixture(); f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.setFollowing(':1.1', 101, true);
    f.shell.displays = []; f.core.topologyChanged();
    assert.equal(f.timers.size, 0);
    f.shell.displays = [display()]; f.core.topologyChanged();
    assert.equal(f.timers.size, 1);
    assert.deepEqual(f.events.at(-1).value.cursor, {x: 120, y: 100});
});

test('unsupported Shell cannot create polling sources', () => {
    const f = fixture(); f.window();
    const unsupported = new BridgeCore(f.shell, '49.1');
    unsupported.register(':1.1', 101, 'secret', 'companion');
    unsupported.setFollowing(':1.1', 101, true);
    assert.equal(unsupported.capabilities().supported, false);
    assert.equal(f.timers.size, 0);
});

test('following intent waits for a mapped companion and stops when it unmaps', () => {
    const f = fixture();
    f.core.setFollowing(':1.1', 101, true);
    f.core.register(':1.1', 101, 'secret', 'companion');
    assert.equal(f.timers.size, 0);
    const w = f.window(); f.core.refreshWindows();
    assert.equal(f.timers.size, 1);
    assert.deepEqual(f.events.at(-1).value.cursor, {x: 120, y: 100});
    w.mapped = false; f.core.refreshWindows();
    assert.equal(f.timers.size, 0);
});

test('owner and registration limits bound Shell state', () => {
    const f = fixture();
    for (let i = 0; i < 32; i++) f.core.setFollowing(`:1.${i}`, 101 + i, true);
    assert.throws(() => f.core.setFollowing(':1.33', 134, true), /limit/);
    for (let i = 0; i < 8; i++) f.core.register(':1.0', 101, `token${i}`, 'companion');
    assert.throws(() => f.core.register(':1.0', 101, 'ninth', 'companion'), /limit/);
    f.core.ownerLost(':1.0');
    assert.doesNotThrow(() => f.core.register(':1.33', 134, 'new', 'companion'));
});

test('window-specific behavior is released on unmap, detach, owner loss and disable', () => {
    const f = fixture();
    let controls = 0, releases = 0;
    const w = f.window({takeControl: () => { controls++; }, releaseControl: () => { releases++; }});
    f.core.register(':1.1', 101, 'secret', 'companion');
    assert.equal(controls, 1);
    w.mapped = false; f.core.refreshWindows(); assert.equal(releases, 1);
    w.mapped = true; f.core.refreshWindows(); assert.equal(controls, 2);
    f.core.command(':1.1', 101, 'secret', 'detach', {}); assert.equal(releases, 2);
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.ownerLost(':1.1'); assert.equal(releases, 3);
    f.core.register(':1.1', 101, 'secret', 'companion');
    f.core.disable(); assert.equal(releases, 4);
});

test('configure caps requested dimensions to target work area', () => {
    const f = fixture(), w = f.window();
    f.core.register(':1.1', 101, 'secret', 'companion');
    const result = f.core.command(':1.1', 101, 'secret', 'configure', {width: 100000, height: 100000});
    assert.equal(w.resizes[0].width, 1000);
    assert.equal(w.resizes[0].height, 770);
    assert.equal(result.x, 0); assert.equal(result.y, 30);
});

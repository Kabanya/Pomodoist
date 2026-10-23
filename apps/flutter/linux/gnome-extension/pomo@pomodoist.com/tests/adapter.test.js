import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

class Signals {
    constructor(properties = {}) { Object.assign(this, properties); this.handlers = new Map(); this.serial = 0; }
    connect(name, callback) { const id = ++this.serial; this.handlers.set(id, {name, callback}); return id; }
    disconnect(id) { this.handlers.delete(id); }
    fire(name, ...args) { for (const h of [...this.handlers.values()]) { if (h.name === name) h.callback(this, ...args); } }
}
async function fixture() {
    const actors = [], sent = [], timers = new Map(), timelines = [];
    const display = new Signals(), windowManager = new Signals(), stage = new Signals();
    const overview = new Signals({visible: false}), mode = new Signals({isLocked: false});
    const workspace = {get_work_area_for_monitor: () => ({x: 0, y: 30, width: 1000, height: 770})};
    const workspaceManager = new Signals({get_active_workspace: () => workspace});
    const layout = new Signals({monitors: [{index: 0, x: 0, y: 0, width: 1000, height: 800}], primaryIndex: 0});
    let pointer = [120, 100, 0], exported, busOwned = false, subscription;
    class Variant { constructor(_type, values) { this.values = values; } deep_unpack() { return this.values; } }
    const session = {
        emit_signal: (...args) => sent.push(args),
        signal_subscribe: (...args) => { subscription = args.at(-1); return 1; },
        signal_unsubscribe: () => { subscription = null; },
        call: (_destination, _path, _iface, method, params, _type, _flags, _timeout, _cancel, callback) => {
            const value = method === 'GetConnectionUnixProcessID' ? [101] : [1, [],
                [[0, 0, 1, 0, true, [['eDP-1', '', '', '']], {}]], {}];
            queueMicrotask(() => callback(session, new Variant('', value)));
        },
        call_finish: result => result,
    };
    const gi = {
        Clutter: {Timeline: {new_for_actor: (actor, duration) => {
            assert.equal(actor, stage); assert.equal(duration, 1000);
            const timeline = new Signals({set_repeat_count: n => assert.equal(n, -1),
                start() { this.running = true; }, stop() { this.running = false; }});
            timelines.push(timeline); return timeline;
        }}},
        Gio: {DBus: {session}, Cancellable: class {cancel() { this.cancelled = true; }},
            DBusCallFlags: {NONE: 0}, DBusSignalFlags: {NONE: 0}, BusNameOwnerFlags: {NONE: 0},
            bus_own_name_on_connection: () => { busOwned = true; return 1; },
            bus_unown_name: () => { busOwned = false; },
            DBusExportedObject: {wrapJSObject: (xml, implementation) => {
                exported = {xml, implementation, export() { this.live = true; }, unexport() { this.live = false; }};
                return exported;
            }}},
        GLib: {Variant, VariantType: class {}, PRIORITY_DEFAULT: 0, SOURCE_CONTINUE: true,
            timeout_add: (_priority, period, callback) => { assert.equal(period, 100); timers.set(1, callback); return 1; },
            Source: {remove: id => timers.delete(id)}},
        Main: {layoutManager: layout, overview, sessionMode: mode, screenShield: new Signals({locked: false})},
        Config: {PACKAGE_VERSION: '46.2'}, Extension: class {},
        mockGlobal: {get_pointer: () => pointer, display, window_manager: windowManager, stage,
            workspace_manager: workspaceManager, get_window_actors: () => actors},
    };
    globalThis.__pomoAdapterTest = gi;
    const source = (await readFile(new URL('../extension.js', import.meta.url), 'utf8'))
        .replace(/^import .*from '(gi:|resource:).*';\n/gm, '')
        .replaceAll("from './", `from '${new URL('../', import.meta.url).href}`)
        .replace(/\bglobal\b/g, 'mockGlobal');
    const prelude = 'const {Clutter, Gio, GLib, Main, Config, Extension, mockGlobal} = globalThis.__pomoAdapterTest;\n';
    const {default: ExtensionClass} = await import(`data:text/javascript;base64,${Buffer.from(prelude + source).toString('base64')}#${Math.random()}`);
    const extension = new ExtensionClass();
    extension.enable();
    await new Promise(resolve => setImmediate(resolve));
    const makeWindow = (actor = null) => {
        const window = new Signals({actor, get_pid: () => 101, get_role: () => 'pomodoist-pomo:companion:secret',
            is_above: () => false, is_on_all_workspaces: () => false,
            stick() { this.sticky = true; }, unstick() { this.sticky = false; },
            make_above() { this.above = true; }, unmake_above() { this.above = false; },
            get_gtk_application_id: () => 'com.finchforge.pomodoist', get_compositor_private() { return this.actor; },
            rect: {x: 100, y: 80, width: 200, height: 150}, get_frame_rect() { return {...this.rect}; },
            move_frame(userOp, x, y) { assert.equal(userOp, false); this.rect.x = x; this.rect.y = y; },
            move_resize_frame() { throw new Error('Drag must never resize'); }});
        return window;
    };
    const invoke = (method, args = []) => new Promise((resolve, reject) => {
        exported.implementation[`${method}Async`](args, {get_sender: () => ':1.99',
            return_value: value => resolve(value ? JSON.parse(value.deep_unpack()[0]) : null),
            return_dbus_error: (_name, message) => reject(new Error(message))});
    });
    return {extension, invoke, display, windowManager, makeWindow, sent, timers, timelines, overview,
        mode, layout, workspaceManager, exported, gi, point: (x, y) => { pointer = [x, y, 0]; },
        get busOwned() { return busOwned; }, get subscription() { return subscription; }};
}

test('adapter attaches windows whose compositor actor arrives after window-created', async () => {
    const f = await fixture();
    try {
        await f.invoke('RegisterWindow', ['secret', 'companion']);
        const w = f.makeWindow(); f.display.fire('window-created', w);
        assert.equal(await f.invoke('Command', ['secret', 'bounds', '{}']), null);
        w.actor = new Signals({mapped: true, meta_window: w});
        f.windowManager.fire('map', w.actor);
        assert.equal((await f.invoke('Command', ['secret', 'bounds', '{}'])).x, 100);
    } finally { f.extension.disable(); }
});

test('adapter uses a stage-bound Timeline and directed D-Bus signals; disable releases all resources', async () => {
    const f = await fixture();
    const actor = new Signals({mapped: true}), w = f.makeWindow(actor); actor.meta_window = w;
    f.display.fire('window-created', w);
    await f.invoke('RegisterWindow', ['secret', 'companion']);
    await f.invoke('SetFollowing', [true]);
    assert.equal(f.timers.size, 1);
    assert.equal(await f.invoke('Command', ['secret', 'dragBegin', '{"displayId":"gnome:eDP-1"}']), true);
    assert.equal(f.timelines[0].running, true);
    f.point(160, 150); f.timelines[0].fire('new-frame', 16);
    assert.deepEqual([w.rect.x, w.rect.y], [140, 130]);
    assert.ok(f.sent.every(args => args[0] === ':1.99'));
    f.extension.disable();
    assert.equal(f.timelines[0].running, false); assert.equal(f.timelines[0].handlers.size, 0);
    assert.equal(f.timers.size, 0); assert.equal(f.busOwned, false); assert.equal(f.subscription, null);
    assert.equal(f.exported.live, false);
    assert.equal(w.above, false); assert.equal(w.sticky, false);
    for (const object of [f.display, f.windowManager, f.overview, f.mode, f.layout, f.workspaceManager, actor, w])
        assert.equal(object.handlers.size, 0);
});

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Config from 'resource:///org/gnome/shell/misc/config.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {BridgeCore} from './core.js';
import {shellDisplays} from './displays.js';
import {SessionTransport} from './transport.js';

const BUS_NAME = 'com.pomodoist.Pomo.Gnome1';
const BUS_PATH = '/com/pomodoist/Pomo/Gnome1';
const IFACE = BUS_NAME;
const INTERFACE_XML = `<node><interface name="${IFACE}">
<method name="GetCapabilities"><arg direction="out" type="s" name="capabilities"/></method>
<method name="RegisterWindow"><arg direction="in" type="s" name="token"/><arg direction="in" type="s" name="role"/><arg direction="out" type="s" name="result"/></method>
<method name="Command"><arg direction="in" type="s" name="token"/><arg direction="in" type="s" name="method"/><arg direction="in" type="s" name="payload"/><arg direction="out" type="s" name="result"/></method>
<method name="SetFollowing"><arg direction="in" type="b" name="enabled"/></method>
<signal name="Changed"><arg type="s" name="capabilities"/></signal>
</interface></node>`;

export default class PomoExtension extends Extension {
    enable() {
        this._active = true;
        this._signals = [];
        this._windows = new Map();
        this._cancellable = new Gio.Cancellable();
        this._topologyGeneration = 0;
        this._shell = {
            displays: [], primaryDisplayId: '',
            windows: () => [...this._windows.values()],
            pointer: () => {
                const [x, y] = global.get_pointer();
                return {x, y};
            },
            startFrames: callback => this._startFrames(callback),
            startPointer: callback => this._startPointer(callback),
            emit: (sender, value) => {
                // emit_signal on DBusExportedObject broadcasts; use a destination instead.
                Gio.DBus.session.emit_signal(sender, BUS_PATH, IFACE, 'Changed',
                    new GLib.Variant('(s)', [JSON.stringify(value)]));
            },
        };
        this._core = new BridgeCore(this._shell, Config.PACKAGE_VERSION);
        this._transport = new SessionTransport(this._core, sender => this._resolvePid(sender));
        const implementation = {};
        for (const method of ['GetCapabilities', 'RegisterWindow', 'Command', 'SetFollowing'])
            implementation[`${method}Async`] = (args, invocation) => this._dispatch(method, args, invocation);
        try {
            this._exported = Gio.DBusExportedObject.wrapJSObject(INTERFACE_XML, implementation);
            this._exported.export(Gio.DBus.session, BUS_PATH);
            this._ownerSubscription = Gio.DBus.session.signal_subscribe('org.freedesktop.DBus',
                'org.freedesktop.DBus', 'NameOwnerChanged', '/org/freedesktop/DBus', null,
                Gio.DBusSignalFlags.NONE, (_connection, _sender, _path, _iface, _signal, parameters) => {
                    const [name, oldOwner, newOwner] = parameters.deep_unpack();
                    if (this._active && name.startsWith(':') && oldOwner && !newOwner)
                        this._transport.ownerLost(name);
                });
            this._busOwnerId = Gio.bus_own_name_on_connection(Gio.DBus.session, BUS_NAME,
                Gio.BusNameOwnerFlags.NONE, null, () => {
                    // A lost name is a disconnected bridge, with no remaining work loops.
                    if (this._active)
                        this.disable();
                });
            this._connect(global.display, 'window-created', (_display, window) => this._track(window));
            this._connect(global.window_manager, 'map', (_manager, actor) => {
                if (actor.meta_window)
                    this._track(actor.meta_window);
                this._core.refreshWindows();
            });
            this._connect(Main.layoutManager, 'monitors-changed', () => this._refreshTopology());
            this._connect(global.display, 'workareas-changed', () => this._refreshTopology());
            this._connect(global.workspace_manager, 'active-workspace-changed', () => this._refreshTopology());
            this._connect(Main.overview, 'showing', () => this._core.setSuppressed(true));
            this._connect(Main.overview, 'hidden', () => this._updateSuppression());
            this._connect(Main.sessionMode, 'updated', () => this._updateSuppression());
            if (Main.screenShield)
                this._connect(Main.screenShield, 'locked-changed', () => this._updateSuppression());
            for (const actor of global.get_window_actors()) {
                if (actor.meta_window)
                    this._track(actor.meta_window);
            }
            this._updateSuppression();
            this._refreshTopology();
        } catch (error) {
            this.disable();
            throw error;
        }
    }

    _connect(object, signal, callback, connections = this._signals) {
        const id = object.connect(signal, callback);
        connections.push([object, id]);
    }

    _disconnect(connections) {
        for (const [object, id] of connections.splice(0)) {
            try {
                object.disconnect(id);
            } catch {
                // Actors can be destroyed before the extension is disabled.
            }
        }
    }

    _updateSuppression() {
        this._core.setSuppressed(Boolean(Main.overview.visible || Main.sessionMode.isLocked ||
            Main.sessionMode.isGreeter || Main.screenShield?.locked));
    }

    _startFrames(callback) {
        // GNOME 46 has new_for_actor; the actor property is a compatibility fallback.
        const timeline = typeof Clutter.Timeline.new_for_actor === 'function'
            ? Clutter.Timeline.new_for_actor(global.stage, 1000)
            : new Clutter.Timeline({actor: global.stage, duration: 1000});
        timeline.set_repeat_count(-1);
        const signal = timeline.connect('new-frame', () => callback());
        timeline.start();
        return () => {
            timeline.disconnect(signal);
            timeline.stop();
        };
    }

    _startPointer(callback) {
        // This is the only periodic source. It exists only for live following leases.
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            callback();
            return GLib.SOURCE_CONTINUE;
        });
        return () => GLib.Source.remove(id);
    }

    _call(destination, path, iface, method, parameters, replyType = null) {
        return new Promise((resolve, reject) => {
            Gio.DBus.session.call(destination, path, iface, method, parameters, replyType,
                Gio.DBusCallFlags.NONE, 3000, this._cancellable, (connection, result) => {
                    try {
                        resolve(connection.call_finish(result));
                    } catch (error) {
                        reject(error);
                    }
                });
        });
    }

    async _resolvePid(sender) {
        const value = await this._call('org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'GetConnectionUnixProcessID',
            new GLib.Variant('(s)', [sender]), new GLib.VariantType('(u)'));
        return value.deep_unpack()[0];
    }

    async _dispatch(method, args, invocation) {
        const transport = this._transport;
        try {
            const value = await transport.call(invocation.get_sender(), method, args);
            invocation.return_value(value === undefined ? null : new GLib.Variant('(s)', [value]));
        } catch (error) {
            invocation.return_dbus_error(`${IFACE}.Error`, error.message || String(error));
        }
    }

    _track(window) {
        if (this._windows.has(window)) {
            this._trackActor(window, this._windows.get(window));
            return;
        }
        const connections = [];
        let original = null;
        const wrapper = {
            actor: null, actorConnections: [],
            takeControl: () => {
                if (original)
                    return;
                original = {above: window.is_above(), sticky: window.is_on_all_workspaces()};
                if (!original.sticky)
                    window.stick();
                if (!original.above)
                    window.make_above();
            },
            releaseControl: () => {
                if (!original)
                    return;
                if (!original.above)
                    window.unmake_above();
                if (!original.sticky)
                    window.unstick();
                original = null;
            },
            get pid() { return window.get_pid(); },
            get role() { return window.get_role(); },
            get appId() { return window.get_gtk_application_id(); },
            get mapped() { return Boolean(this.actor?.mapped); },
            bounds: () => {
                const r = window.get_frame_rect();
                return {x: r.x, y: r.y, width: r.width, height: r.height};
            },
            move: (x, y) => window.move_frame(false, x, y),
            configure: r => window.move_resize_frame(false, r.x, r.y, r.width, r.height),
            connections,
        };
        this._windows.set(window, wrapper);
        this._connect(window, 'unmanaged', () => {
            // Window is already unmanaged: no further Meta mutations are valid.
            original = null;
            this._core.windowDestroyed(wrapper);
            this._windows.delete(window);
            this._disconnect(connections);
            this._disconnect(wrapper.actorConnections);
        }, connections);
        this._connect(window, 'position-changed', () => this._core.boundsChanged(wrapper), connections);
        this._connect(window, 'size-changed', () => this._core.boundsChanged(wrapper), connections);
        this._connect(window, 'notify::gtk-application-id', () => this._core.refreshWindows(), connections);
        this._trackActor(window, wrapper);
        this._core.refreshWindows();
    }

    _trackActor(window, wrapper) {
        const actor = window.get_compositor_private();
        if (actor === wrapper.actor)
            return;
        this._disconnect(wrapper.actorConnections);
        wrapper.actor = actor;
        if (actor) {
            this._connect(actor, 'notify::mapped', () => this._core.refreshWindows(), wrapper.actorConnections);
            this._connect(actor, 'destroy', () => {
                wrapper.actor = null;
                this._core.refreshWindows();
                this._disconnect(wrapper.actorConnections);
            }, wrapper.actorConnections);
        }
    }

    async _refreshTopology() {
        const generation = ++this._topologyGeneration;
        const shell = this._shell;
        // Invalidate old geometry immediately; stale connector/index joins are unsafe.
        this._shell.displays = [];
        this._shell.primaryDisplayId = '';
        this._core.topologyChanged();
        try {
            const state = await this._call('org.gnome.Mutter.DisplayConfig',
                '/org/gnome/Mutter/DisplayConfig', 'org.gnome.Mutter.DisplayConfig',
                'GetCurrentState', null);
            if (!this._active || this._shell !== shell || generation !== this._topologyGeneration)
                return;
            const [, physicals, logicals] = state.deep_unpack();
            const workspace = global.workspace_manager.get_active_workspace();
            const result = shellDisplays(logicals, physicals, Main.layoutManager.monitors,
                index => workspace.get_work_area_for_monitor(index), Main.layoutManager.primaryIndex);
            Object.assign(this._shell, result);
            this._core.topologyChanged();
        } catch (error) {
            if (this._active && this._shell === shell && generation === this._topologyGeneration)
                console.error(`Pomodoist monitor query failed: ${error.message}`);
        }
    }

    disable() {
        if (!this._active)
            return;
        this._active = false;
        this._topologyGeneration++;
        this._transport?.disable();
        this._cancellable?.cancel();
        this._disconnect(this._signals);
        for (const wrapper of this._windows.values()) {
            this._disconnect(wrapper.connections);
            this._disconnect(wrapper.actorConnections);
        }
        this._windows.clear();
        if (this._ownerSubscription) {
            Gio.DBus.session.signal_unsubscribe(this._ownerSubscription);
            this._ownerSubscription = 0;
        }
        this._exported?.unexport();
        this._exported = null;
        if (this._busOwnerId) {
            Gio.bus_unown_name(this._busOwnerId);
            this._busOwnerId = 0;
        }
        this._transport = null;
        this._core = null;
        this._shell = null;
        this._cancellable = null;
    }
}

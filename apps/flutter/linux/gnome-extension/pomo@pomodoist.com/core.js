// Pure policy: no GI imports. All coordinates are Shell stage logical pixels.
export const APP_IDS = new Set([
    'com.finchforge.pomodoist',
    'com.finchforge.pomodoist.dev',
    'com.finchforge.pomodoist.stg',
]);
export const PROTOCOL_VERSION = 1;
export const EXTENSION_VERSION = 1;

function object(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        throw new Error('Payload must be an object');
}
function finite(value, name) {
    if (!Number.isFinite(value) || Math.abs(value) > 1000000)
        throw new Error(`${name} must be finite and within stage limits`);
    return Math.round(value);
}
function clamp(value, min, max) {
    return Math.max(min, Math.min(value, Math.max(min, max)));
}
function constrain(rect, display) {
    return {...rect,
        x: clamp(rect.x, display.workX, display.workX + display.workWidth - rect.width),
        y: clamp(rect.y, display.workY, display.workY + display.workHeight - rect.height)};
}

export class BridgeCore {
    constructor(shell, shellVersion) {
        this.shell = shell;
        this.shellVersion = shellVersion;
        this.enabled = true;
        this.suppressed = false;
        this.owners = new Map();
        this.registrations = new Map();
        this.drags = new Map();
        this.destroyedWindows = new WeakSet();
        this.stopFrames = null;
        this.stopPointer = null;
    }

    capabilities() {
        return {protocolVersion: PROTOCOL_VERSION, extensionVersion: EXTENSION_VERSION,
            shellVersion: this.shellVersion,
            supported: this.enabled && ['46', '50', '51'].includes(this.shellVersion.split('.')[0]) &&
                this.shell.displays.length > 0,
            suppressed: this.suppressed,
            displays: this.shell.displays.map(d => ({...d})),
            primaryDisplayId: this.shell.primaryDisplayId};
    }

    _owner(sender, pid) {
        if (!this.enabled)
            throw new Error('Extension disabled');
        if (typeof sender !== 'string' || !sender.startsWith(':') || !Number.isInteger(pid) || pid <= 0)
            throw new Error('Invalid owner identity');
        const previous = this.owners.get(sender);
        if (previous && previous.pid !== pid)
            throw new Error('Caller does not match owner PID');
        if (!previous && this.owners.size >= 32)
            throw new Error('Owner session limit reached');
        if (!previous)
            this.owners.set(sender, {pid, following: false, cursor: null});
        return this.owners.get(sender);
    }

    register(sender, pid, token, role) {
        this._owner(sender, pid);
        if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(token))
            throw new Error('Invalid token');
        if (!['companion', 'settings'].includes(role))
            throw new Error('Invalid role');
        const previous = this.registrations.get(token);
        if (previous && (previous.owner !== sender || previous.role !== role))
            throw new Error('Token already owned');
        if (!previous && (this.registrations.size >= 64 ||
            [...this.registrations.values()].filter(r => r.owner === sender).length >= 8))
            throw new Error('Window registration limit reached');
        if (!previous)
            this.registrations.set(token, {owner: sender, pid, token, role, window: null});
        this.refreshWindows(false);
        this.notify(sender);
        const bounds = this._bounds(this.registrations.get(token));
        return bounds ? {ready: true, bounds} : {ready: false};
    }

    refreshWindows(notify = true) {
        if (!this.enabled)
            return;
        const windows = this.shell.windows();
        const affected = new Set();
        for (const registration of this.registrations.values()) {
            const matches = windows.filter(w => !this.destroyedWindows.has(w) && w.mapped && w.pid === registration.pid &&
                w.role === `pomodoist-pomo:${registration.role}:${registration.token}` && APP_IDS.has(w.appId));
            // Never select an ambiguous window, even for the same process.
            const next = matches.length === 1 ? matches[0] : null;
            if (registration.window !== next) {
                registration.window?.releaseControl?.();
                next?.takeControl?.(registration.role);
                registration.window = next;
                this.owners.get(registration.owner).cursor = null;
                if (next)
                    registration.lastWindow = next;
                this.drags.delete(registration.token);
                affected.add(registration.owner);
            }
        }
        this._syncLoops();
        if (notify) {
            affected.forEach(sender => this.notify(sender));
            this._sample();
        }
    }

    _display(rect, requested) {
        const displays = this.shell.displays;
        if (requested) {
            const result = displays.find(d => d.id === requested);
            if (!result)
                throw new Error('Unknown displayId');
            return result;
        }
        const cx = rect.x + rect.width / 2, cy = rect.y + rect.height / 2;
        return displays.find(d => cx >= d.x && cx < d.x + d.width && cy >= d.y && cy < d.y + d.height) ??
            displays.find(d => d.id === this.shell.primaryDisplayId) ?? displays[0];
    }

    _bounds(registration) {
        if (!registration?.window?.mapped)
            return null;
        const rect = registration.window.bounds();
        const display = this._display(rect);
        return display ? {...rect, scale: display.scale, displayId: display.id} : null;
    }

    command(sender, pid, token, method, payload) {
        this._owner(sender, pid);
        const r = this.registrations.get(token);
        if (!r || r.owner !== sender)
            throw new Error('Window token is not registered to caller');
        object(payload);
        if (method === 'detach') {
            r.window?.releaseControl?.();
            this.registrations.delete(token);
            this.drags.delete(token);
            this._syncLoops();
            this.notify(sender, undefined, true);
            return null;
        }
        if (!['bounds', 'move', 'configure', 'dragBegin', 'dragPosition', 'dragEnd'].includes(method))
            throw new Error(`Unknown command ${method}`);
        if (method === 'dragEnd') {
            this.drags.delete(token);
            this._syncLoops();
            return this._bounds(r);
        }
        if (method === 'bounds')
            return this._bounds(r);
        if (method === 'dragPosition')
            return this.drags.has(token) ? this._rawDrag(this.drags.get(token)) : null;
        if (!r.window || this.suppressed || !this.capabilities().supported)
            return method === 'dragBegin' ? false : null;
        if (method === 'dragBegin') {
            const bounds = this._bounds(r);
            const display = this._display(bounds, payload.displayId);
            if (payload.allowCrossDisplayDrag !== undefined && typeof payload.allowCrossDisplayDrag !== 'boolean')
                throw new Error('allowCrossDisplayDrag must be boolean');
            this.drags.set(token, {registration: r, origin: bounds, pointer: this.shell.pointer(),
                displayId: display.id, cross: payload.allowCrossDisplayDrag === true});
            this._syncLoops();
            return true;
        }
        this.drags.delete(token);
        this._syncLoops();
        const current = this._bounds(r), rect = {...current};
        for (const key of method === 'configure' ? ['x', 'y', 'width', 'height'] : ['x', 'y']) {
            if (payload[key] !== undefined) {
                rect[key] = finite(payload[key], key);
                if ((key === 'width' || key === 'height') && rect[key] <= 0)
                    throw new Error(`${key} must be positive`);
            }
        }
        const display = this._display(rect, payload.displayId);
        if (method === 'configure') {
            rect.width = Math.min(rect.width, display.workWidth);
            rect.height = Math.min(rect.height, display.workHeight);
        }
        const target = constrain(rect, display);
        if (method === 'configure') {
            r.window.configure({x: target.x, y: target.y, width: target.width, height: target.height});
            // Actual sizes may differ due to minimum-size constraints.
            const actual = r.window.bounds();
            const corrected = constrain(actual, display);
            if (corrected.x !== actual.x || corrected.y !== actual.y)
                r.window.move(corrected.x, corrected.y);
        } else {
            r.window.move(target.x, target.y);
        }
        this.notify(sender);
        return this._bounds(r);
    }

    _rawDrag(drag) {
        const pointer = this.shell.pointer();
        return {...drag.origin, x: Math.round(drag.origin.x + pointer.x - drag.pointer.x),
            y: Math.round(drag.origin.y + pointer.y - drag.pointer.y)};
    }

    _frame() {
        for (const [token, drag] of this.drags) {
            if (!drag.registration.window?.mapped) {
                this.drags.delete(token);
                continue;
            }
            const raw = this._rawDrag(drag);
            const display = this._display(raw, drag.cross ? undefined : drag.displayId);
            if (!display) {
                this.drags.delete(token);
                continue;
            }
            const target = constrain(raw, display);
            const before = drag.registration.window.bounds();
            if (before.x !== target.x || before.y !== target.y) {
                drag.registration.window.move(target.x, target.y);
                this.notify(drag.registration.owner);
            }
        }
        this._syncLoops();
    }

    setFollowing(sender, pid, enabled) {
        const owner = this._owner(sender, pid);
        if (typeof enabled !== 'boolean')
            throw new Error('Following must be boolean');
        owner.following = enabled;
        owner.cursor = null;
        this._syncLoops();
        if (enabled && this._followingActive(sender) && !this.suppressed && this.capabilities().supported) {
            owner.cursor = this.shell.pointer();
            this.notify(sender, owner.cursor);
        }
    }

    _followingActive(sender) {
        return [...this.registrations.values()].some(r =>
            r.owner === sender && r.role === 'companion' && r.window?.mapped);
    }

    _sample() {
        if (this.suppressed || !this.capabilities().supported)
            return;
        if (![...this.owners].some(([sender, owner]) => owner.following && this._followingActive(sender)))
            return;
        const cursor = this.shell.pointer();
        for (const [sender, owner] of this.owners) {
            if (!owner.following || !this._followingActive(sender))
                continue;
            if (owner.cursor?.x !== cursor.x || owner.cursor?.y !== cursor.y) {
                owner.cursor = {...cursor};
                this.notify(sender, cursor);
            }
        }
    }

    _syncLoops() {
        const active = this.enabled && !this.suppressed && this.capabilities().supported;
        const needsFrames = active && this.drags.size > 0;
        const needsPointer = active && [...this.owners.entries()].some(([sender, o]) =>
            o.following && this._followingActive(sender));
        if (!needsFrames && this.stopFrames) {
            this.stopFrames(); this.stopFrames = null;
        }
        if (needsFrames && !this.stopFrames)
            this.stopFrames = this.shell.startFrames(() => this._frame());
        if (!needsPointer && this.stopPointer) {
            this.stopPointer(); this.stopPointer = null;
        }
        if (needsPointer && !this.stopPointer)
            this.stopPointer = this.shell.startPointer(() => this._sample());
    }

    notify(sender, cursor, allowEmpty = false) {
        if (!this.enabled)
            return;
        const registrations = [...this.registrations.values()].filter(r => r.owner === sender);
        // Send the empty map after detach/destruction too so stale native bounds clear.
        if (!this.owners.has(sender) || (!registrations.length && !allowEmpty))
            return;
        const windows = Object.fromEntries(registrations.map(r => [r.token, this._bounds(r)]));
        const value = {...this.capabilities(), windows};
        if (cursor && !this.suppressed)
            value.cursor = {...cursor};
        this.shell.emit(sender, value);
    }

    boundsChanged(window) {
        for (const r of this.registrations.values()) {
            if (r.window === window)
                this.notify(r.owner);
        }
    }

    topologyChanged() {
        this.drags.clear();
        for (const owner of this.owners.values())
            owner.cursor = null;
        this._syncLoops();
        for (const sender of this.owners.keys())
            this.notify(sender);
        this._sample();
    }

    setSuppressed(suppressed) {
        if (this.suppressed === suppressed)
            return;
        this.suppressed = suppressed;
        if (suppressed)
            this.drags.clear();
        for (const owner of this.owners.values())
            owner.cursor = null;
        this._syncLoops();
        for (const sender of this.owners.keys())
            this.notify(sender);
        if (!suppressed)
            this._sample();
    }

    windowDestroyed(window) {
        this.destroyedWindows.add(window);
        const affected = new Set();
        for (const [token, r] of this.registrations) {
            if (r.window === window || r.lastWindow === window) {
                // Meta destruction also occurs when GTK hides a reusable utility.
                // Native sends detach on actual GTK destruction; keep its token pending.
                r.window = null;
                r.lastWindow = null;
                this.drags.delete(token);
                this.owners.get(r.owner).cursor = null;
                affected.add(r.owner);
            }
        }
        this._syncLoops();
        affected.forEach(sender => this.notify(sender, undefined, true));
    }

    ownerLost(sender) {
        this.owners.delete(sender);
        for (const [token, r] of this.registrations) {
            if (r.owner === sender) {
                r.window?.releaseControl?.();
                this.registrations.delete(token);
                this.drags.delete(token);
            }
        }
        this._syncLoops();
    }

    disable() {
        this.enabled = false;
        for (const r of this.registrations.values())
            r.window?.releaseControl?.();
        this.drags.clear();
        this.registrations.clear();
        this.owners.clear();
        this._syncLoops();
    }
}

import {APP_IDS} from './core.js';

// The authenticated session transport supplies sender/PID, never caller JSON.
export class DistractionCore {
    constructor(shell, now = () => Date.now(), onActivity = () => {}) {
        this.shell = shell;
        this.onActivity = onActivity;
        this.now = now;
        this.owners = new Map();
    }
    call(sender, pid, request) {
        if (!this.shell.windows().some(w => w.pid === pid && APP_IDS.has(w.appId)))
            throw new Error('Caller must own a Pomodoist window');
        if (!request || typeof request !== 'object' || Array.isArray(request))
            throw new Error('Invalid distraction request');
        let owner = this.owners.get(sender);
        if (!owner) {
            if (this.owners.size >= 32) throw new Error('Too many discovery owners');
            owner = {pid, discovery: false, blocked: new Set(), expires: 0,
                events: [], last: '', attempted: '', changed: new Map()};
            this.owners.set(sender, owner);
        }
        if (owner.pid !== pid) throw new Error('Caller PID changed');
        switch (request.action) {
        case 'capabilities': return {supported: true, discoveryAvailable: true,
            platform: 'linux', adapter: 'gnome-shell', protocolVersion: 1};
        case 'startDiscovery': owner.discovery = true; owner.last = ''; break;
        case 'stopDiscovery': owner.discovery = false; owner.events = []; break;
        case 'clearProtection': this._release(owner); break;
        case 'setProtection': {
            if (request.active === false) { this._release(owner); break; }
            if (request.active !== true || !Array.isArray(request.blockedApps) ||
                request.blockedApps.length > 4096 || request.blockedApps.some(id =>
                    typeof id !== 'string' || !/^linux:[^/\\\r\n]{1,480}$/.test(id)))
                throw new Error('Invalid app identity');
            const expires = Date.parse(request.expiresAt);
            if (!Number.isFinite(expires)) throw new Error('Invalid expiration');
            owner.blocked = new Set(request.blockedApps); owner.expires = expires;
            break;
        }
        case 'poll': break;
        default: throw new Error('Unknown distraction action');
        }
        this.tick();
        this._sync();
        const events = owner.events.splice(0);
        return {supported: true, platform: 'linux', events};
    }
    _sync() { this.onActivity([...this.owners.values()].some(o => o.discovery || o.expires > this.now())); }
    _release(owner) {
        owner.expires = 0; owner.blocked.clear(); owner.attempted = '';
        for (const window of owner.changed.values()) this.shell.restore(window);
        owner.changed.clear();
    }
    tick() {
        const app = this.shell.foreground();
        for (const owner of this.owners.values()) {
            if (owner.expires && owner.expires <= this.now()) this._release(owner);
            if (!app || !/^linux:[^/\\\r\n]{1,480}$/.test(app.id) || typeof app.name !== 'string') continue;
            const value = {id: app.id, name: app.name.slice(0, 512), platform: 'linux'};
            if (owner.discovery && owner.last !== app.id) {
                owner.last = app.id; owner.events.push({method: 'foregroundApp', app: value});
            }
            if (owner.expires > this.now() && owner.blocked.has(app.id)) {
                if (owner.attempted !== app.id) {
                    owner.events.push({method: 'blockedAttempt', app: value}); owner.attempted = app.id;
                }
                if (!owner.changed.has(app.key) && this.shell.minimize(app) !== false)
                    owner.changed.set(app.key, app);
            } else {
                if (owner.attempted) owner.events.push({method: 'hideShield'});
                owner.attempted = '';
            }
            if (owner.events.length > 64) owner.events.splice(0, owner.events.length - 64);
        }
        this._sync();
    }
    ownerLost(sender) {
        const owner = this.owners.get(sender);
        if (owner) this._release(owner);
        this.owners.delete(sender);
        this._sync();
    }
    disable() { for (const sender of this.owners.keys()) this.ownerLost(sender); }
}

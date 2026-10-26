// Session-bus ownership is supplied by the authenticated GIO adapter.
export class SessionTransport {
    constructor(core, resolvePid, distractions = null) {
        this.core = core;
        this.distractions = distractions;
        this.resolvePid = resolvePid;
        this.active = true;
        this.pending = new Map();
    }

    async call(sender, method, args) {
        if (!this.active)
            throw new Error('Extension disabled');
        if (method === 'GetCapabilities')
            return JSON.stringify(this.core.capabilities());
        if (!['RegisterWindow', 'Command', 'SetFollowing', 'Distractions'].includes(method))
            throw new Error(`Unknown method ${method}`);
        // Resolve on each call; never accept a caller-supplied PID.
        const request = {lost: false};
        if (!this.pending.has(sender))
            this.pending.set(sender, new Set());
        const requests = this.pending.get(sender);
        requests.add(request);
        let pid;
        try {
            pid = await this.resolvePid(sender);
            if (!this.active)
                throw new Error('Extension disabled');
            if (request.lost)
                throw new Error('Owner disconnected');
        } finally {
            requests.delete(request);
            if (!requests.size)
                this.pending.delete(sender);
        }
        if (method === 'Distractions') {
            if (!this.distractions || typeof args[0] !== 'string' || args[0].length > 512 * 1024)
                throw new Error('Distraction adapter is unavailable or request too large');
            return JSON.stringify(this.distractions.call(sender, pid, JSON.parse(args[0])));
        }
        if (method === 'RegisterWindow')
            return JSON.stringify(this.core.register(sender, pid, ...args));
        if (method === 'SetFollowing') {
            this.core.setFollowing(sender, pid, args[0]);
            return undefined;
        }
        const [token, command, json] = args;
        if (typeof json !== 'string' || json.length > 8192)
            throw new Error('Command JSON is too large');
        let payload;
        try {
            payload = JSON.parse(json);
        } catch {
            throw new Error('Invalid command JSON');
        }
        return JSON.stringify(this.core.command(sender, pid, token, command, payload));
    }

    ownerLost(sender) {
        for (const request of this.pending.get(sender) ?? [])
            request.lost = true;
        this.core.ownerLost(sender);
        this.distractions?.ownerLost(sender);
    }

    disable() {
        this.active = false;
        this.core.disable();
        this.distractions?.disable();
        this.pending.clear();
    }
}

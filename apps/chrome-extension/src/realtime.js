// Realtime is only active while the popup is open. The worker has no timers or
// persistent socket. Polling in the popup remains a bounded fallback.
export class Realtime {
  constructor(getContext, changed, status, Socket = WebSocket) {
    this.getContext = getContext; this.changed = changed; this.status = status; this.Socket = Socket;
    this.stopped = true; this.attempt = 0; this.generation = 0; this.ref = 0;
  }
  start() { if (!this.stopped) return; this.stopped = false; this.connect(); }
  stop() {
    this.stopped = true; this.generation++; this.cleanup(); this.status(false);
  }
  cleanup() {
    clearTimeout(this.retry); clearTimeout(this.joinTimeout); clearInterval(this.heartbeat); clearInterval(this.authTimer);
    const socket = this.socket; this.socket = null;
    if (socket) { socket.onclose = null; socket.onerror = null; socket.onmessage = null; socket.onopen = null; socket.close(); }
  }
  send(event, payload, topic = this.topic, ref = String(++this.ref)) {
    if (this.socket?.readyState === 1) this.socket.send(JSON.stringify({ topic, event, payload, ref, ...(topic !== 'phoenix' ? { join_ref: this.joinRef } : {}) }));
    return ref;
  }
  reconnect(generation) {
    if (this.stopped || generation !== this.generation) return;
    this.generation++; this.cleanup(); this.status(false);
    this.retry = setTimeout(() => this.connect(), Math.min(30000, 1000 * 2 ** Math.min(this.attempt++, 5)));
  }
  async connect() {
    if (this.stopped) return;
    const generation = ++this.generation;
    try {
      const ctx = await this.getContext();
      if (this.stopped || generation !== this.generation) return;
      const url = new URL(`${ctx.apiUrl}/realtime/v1/websocket`);
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      url.search = new URLSearchParams({ apikey: ctx.anonKey, vsn: '1.0.0' });
      this.topic = `realtime:sync:${ctx.userId}:pomodoist`; this.userId = ctx.userId;
      this.token = ctx.accessToken; this.joinRef = String(++this.ref); this.pendingHeartbeat = null;
      const socket = this.socket = new this.Socket(url.href);
      socket.onopen = () => {
        this.send('phx_join', { config: { private: true, broadcast: { ack: false, self: false },
          presence: { enabled: false }, postgres_changes: [] }, access_token: ctx.accessToken }, this.topic, this.joinRef);
      };
      this.joinTimeout = setTimeout(() => this.reconnect(generation), 12000);
      socket.onmessage = event => {
        if (generation !== this.generation) return;
        let frame; try { frame = JSON.parse(event.data); } catch { return; }
        if (frame.topic === 'phoenix' && frame.event === 'phx_reply' && frame.ref === this.pendingHeartbeat) this.pendingHeartbeat = null;
        if (frame.topic !== this.topic) return;
        if (frame.event === 'phx_reply' && frame.ref === this.joinRef) {
          if (frame.payload?.status !== 'ok') { this.reconnect(generation); return; }
          clearTimeout(this.joinTimeout); this.attempt = 0; this.status(true); this.changed();
          clearInterval(this.heartbeat);
          this.heartbeat = setInterval(() => {
            if (this.pendingHeartbeat) { this.reconnect(generation); return; }
            this.pendingHeartbeat = this.send('heartbeat', {}, 'phoenix');
          }, 25000);
          clearInterval(this.authTimer);
          this.authTimer = setInterval(async () => {
            try {
              const current = await this.getContext();
              if (generation !== this.generation) return;
              if (current.userId !== this.userId) { this.reconnect(generation); return; }
              if (current.accessToken !== this.token) { this.token = current.accessToken; this.send('access_token', { access_token: this.token }); }
            } catch { this.reconnect(generation); }
          }, 30000);
        } else if (frame.event === 'broadcast' && frame.payload?.event === 'changed' &&
                   frame.payload?.payload?.appId === 'pomodoist' && frame.payload.payload.deviceId !== ctx.deviceId) this.changed();
        else if (['phx_error', 'phx_close'].includes(frame.event) || (frame.event === 'system' && frame.payload?.status === 'error')) this.reconnect(generation);
      };
      socket.onerror = socket.onclose = () => this.reconnect(generation);
    } catch { this.reconnect(generation); }
  }
}

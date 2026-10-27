import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {rename, rm} from 'node:fs/promises';

// Flutter builds UI tests into the regular Dev.app output directory.
export async function preserveDevelopmentApp(app, backup) {
  let existed = true;
  try { await rename(app, backup); } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    existed = false;
  }
  return async () => {
    await rm(app, {recursive: true, force: true});
    if (existed) await rename(backup, app);
  };
}

export async function createControlServer(token, action) {
  if (!token) throw Error('A control token is required');
  const server = createServer(async (req, res) => {
    const send = (status, value) => {
      res.writeHead(status, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(value));
    };
    if (req.method !== 'POST' || req.url !== '/step' ||
        req.headers.authorization !== `Bearer ${token}`) {
      send(403, {error: 'Unauthorized test control request'}); return;
    }
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 16384) { send(413, {error: 'Test request too large'}); return; }
        chunks.push(chunk);
      }
      const body = JSON.parse(Buffer.concat(chunks).toString());
      if (!body || typeof body.step !== 'string') {
        send(400, {error: 'A test step is required'}); return;
      }
      send(200, await action(body));
    } catch (error) { send(500, {error: error.message}); }
  });
  server.requestTimeout = 60000;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return {
    url: `http://127.0.0.1:${server.address().port}/step`,
    close: async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    },
  };
}

export class Processes {
  children = [];
  start(command, args, options = {}) {
    const child = spawn(command, args, {stdio: ['ignore', 'pipe', 'pipe'], ...options, detached: true});
    child.done = new Promise(resolve => {
      child.once('error', error => resolve({code: null, error}));
      child.once('exit', (code, signal) => resolve({code, signal}));
    });
    this.children.push(child);
    return child;
  }
  async close() {
    const children = this.children.splice(0);
    const signal = (child, name) => {
      if (!child.pid) return;
      try { process.kill(-child.pid, name); } catch (error) {
        if (error.code !== 'ESRCH') throw error;
      }
    };
    for (const child of children) signal(child, 'SIGTERM');
    await Promise.race([Promise.all(children.map(c => c.done)), delay(1500)]);
    // A reparented browser/tool child may still be exiting after its parent did.
    if (children.length) await delay(100);
    for (const child of children) signal(child, 'SIGKILL');
    await Promise.all(children.map(c => c.done));
  }
}

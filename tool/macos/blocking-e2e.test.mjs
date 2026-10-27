import assert from 'node:assert/strict';
import test from 'node:test';
import {once} from 'node:events';
import {createControlServer, Processes} from './blocking-e2e-support.mjs';

test('control channel rejects untrusted requests and dispatches authenticated steps', async () => {
  const calls = [];
  const control = await createControlServer('test-secret', async body => {
    calls.push(body);
    return {done: body.step};
  });
  try {
    const request = (token, body) => fetch(control.url, {
      method: 'POST', headers: {Authorization: `Bearer ${token}`},
      body: JSON.stringify(body),
    });
    assert.equal((await request('wrong', {step: 'prepare'})).status, 403);
    assert.deepEqual(calls, []);
    const response = await request('test-secret', {step: 'prepare'});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {done: 'prepare'});
    assert.deepEqual(calls, [{step: 'prepare'}]);
    assert.equal((await request('test-secret', {step: 'x'.repeat(20000)})).status, 413);
    assert.equal(calls.length, 1);
  } finally { await control.close(); }
});

test('step failures reach the UI test instead of hanging its HTTP request', async () => {
  const control = await createControlServer('secret', async () => { throw Error('native assertion failed'); });
  try {
    const response = await fetch(control.url, {
      method: 'POST', headers: {Authorization: 'Bearer secret'}, body: '{"step":"blocked"}',
    });
    assert.equal(response.status, 500);
    assert.match((await response.json()).error, /native assertion failed/);
  } finally { await control.close(); }
});

test('cleanup stops only managed process groups, including a child of the runner', async () => {
  const processes = new Processes();
  const child = processes.start(process.execPath, ['-e', 'setInterval(() => {}, 1000)']);
  assert.doesNotThrow(() => process.kill(child.pid, 0));
  await processes.close();
  assert.throws(() => process.kill(child.pid, 0), {code: 'ESRCH'});
  assert.doesNotThrow(() => process.kill(process.pid, 0));
  await processes.close();
});

test('cleanup kills descendants even after their managed parent has exited', async () => {
  const processes = new Processes();
  const child = processes.start(process.execPath, ['-e', `
    const {spawn} = require('node:child_process');
    const worker = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {stdio: 'ignore'});
    console.log(worker.pid);
    worker.unref();
  `]);
  const [chunk] = await once(child.stdout, 'data');
  const pid = Number(String(chunk).trim());
  assert.ok(pid > 0);
  await child.done;
  assert.doesNotThrow(() => process.kill(pid, 0));
  await processes.close();
  // The orphan is reaped by launchd asynchronously after its process group dies.
  for (let i = 0; i < 50; i++) {
    try { process.kill(pid, 0); } catch (error) {
      assert.equal(error.code, 'ESRCH'); return;
    }
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.fail('Owned descendant survived cleanup');
});

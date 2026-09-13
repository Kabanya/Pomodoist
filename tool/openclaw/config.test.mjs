import test from 'node:test';
import assert from 'node:assert/strict';
import { buildConfig, connectionCommands } from './configure.mjs';

test('read mode uses OAuth and an explicit read allowlist', () => {
  const config = buildConfig('https://tasks.example.com/functions/v1/pomodoist-mcp');
  assert.equal(config.auth, 'oauth');
  assert.equal(config.transport, 'streamable-http');
  assert.equal(config.sslVerify, true);
  assert.equal(config.supportsParallelToolCalls, false);
  assert.ok(config.toolFilter.include.includes('list_tasks'));
  assert.ok(config.toolFilter.include.includes('openclaw_get_focus'));
  assert.ok(!config.toolFilter.include.includes('openclaw_create_task'));
  assert.ok(!JSON.stringify(config).includes('Authorization'));
});
test('write mode permits guarded tools only, never globs or legacy mutations', () => {
  const config = buildConfig('https://tasks.example.com/mcp', 'write');
  assert.ok(config.toolFilter.include.includes('openclaw_create_task'));
  assert.ok(config.toolFilter.include.includes('openclaw_focus'));
  assert.ok(config.toolFilter.include.includes('openclaw_set_task_details'));
  assert.ok(!config.toolFilter.include.some(x => x.includes('*')));
  for (const name of ['create_task', 'update_task', 'delete_task']) {
    assert.ok(!config.toolFilter.include.includes(name));
  }
});
test('rejects unsafe URLs without echoing credentials', () => {
  for (const url of ['http://example.com/mcp', 'file:///tmp/a', 'https://user:secret@example.com/mcp',
    'https://example.com/mcp?token=secret', 'https://example.com/mcp#secret', '', 'https://example.com/mcp\n']) {
    assert.throws(() => buildConfig(url), error => !error.message.includes('secret'));
  }
});
test('HTTP is restricted to exact loopback hostnames', () => {
  for (const host of ['localhost', '127.0.0.1', '[::1]']) {
    assert.ok(buildConfig(`http://${host}:58000/functions/v1/pomodoist-mcp`).url);
  }
  for (const host of ['localhost.evil.example', '127.1', '2130706433', '0.0.0.0']) {
    assert.throws(() => buildConfig(`http://${host}/mcp`));
  }
});
test('commands are argv arrays with no shell evaluation and invalid modes fail', () => {
  assert.throws(() => buildConfig('https://example.com/mcp', 'admin'));
  const commands = connectionCommands('https://example.com/mcp', 'read');
  assert.equal(commands[0][0], 'mcp');
  assert.equal(commands[0][1], 'set');
  assert.equal(JSON.parse(commands[0][3]).auth, 'oauth');
  assert.deepEqual(commands[1], ['mcp', 'login', 'pomodoist']);
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {SessionTransport} from '../transport.js';
import {BridgeCore} from '../core.js';

function setup(resolvePid = async () => 101) {
    const events = [];
    const shell = {displays: [], primaryDisplayId: '', windows: () => [],
        emit: (sender, value) => events.push([sender, value])};
    const core = new BridgeCore(shell, '46');
    return {core, events, transport: new SessionTransport(core, resolvePid)};
}

test('transport resolves authenticated PID and returns protocol JSON with pending registration', async () => {
    const f = setup();
    const result = await f.transport.call(':1.9', 'RegisterWindow', ['token', 'companion']);
    assert.deepEqual(JSON.parse(result), {ready: false});
    assert.equal(f.core.owners.get(':1.9').pid, 101);
    assert.equal(JSON.parse(await f.transport.call(':1.9', 'GetCapabilities', [])).protocolVersion, 1);
});

test('transport cancels in-flight authentication on owner loss and disable', async () => {
    let finish;
    const f = setup(() => new Promise(resolve => { finish = resolve; }));
    const pending = f.transport.call(':1.9', 'RegisterWindow', ['token', 'companion']);
    f.transport.ownerLost(':1.9'); finish(101);
    await assert.rejects(pending, /disconnected/);
    assert.equal(f.core.registrations.size, 0);
    let finishSecond;
    const g = setup(() => new Promise(resolve => { finishSecond = resolve; }));
    const pendingSecond = g.transport.call(':1.10', 'SetFollowing', [true]);
    g.transport.disable(); finishSecond(101);
    await assert.rejects(pendingSecond, /disabled/);
    assert.equal(g.core.owners.size, 0);
});

test('transport rejects invalid JSON, arrays, oversized commands, and unknown methods', async () => {
    const f = setup();
    await f.transport.call(':1.9', 'RegisterWindow', ['token', 'settings']);
    await assert.rejects(f.transport.call(':1.9', 'Command', ['token', 'move', '{']), /JSON/);
    await assert.rejects(f.transport.call(':1.9', 'Command', ['token', 'move', '[]']), /object/);
    await assert.rejects(f.transport.call(':1.9', 'Command', ['token', 'move', ' '.repeat(8193)]), /large/);
    await assert.rejects(f.transport.call(':1.9', 'Eval', []), /Unknown/);
});

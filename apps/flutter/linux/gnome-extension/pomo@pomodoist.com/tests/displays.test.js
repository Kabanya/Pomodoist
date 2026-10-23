import {test} from 'node:test';
import assert from 'node:assert/strict';
import {shellDisplays} from '../displays.js';

test('stable connector IDs survive Shell index order and use Shell geometry/workareas', () => {
    const logicals = [[0, 0, 1.25, 0, true, [['eDP-1', 'Vendor', 'Model', 'serial']], {}],
        [1920, -200, 2, 0, false, [['DP-2', 'V', 'M', 's']], {}]];
    const physicals = [[['eDP-1', 'Vendor', 'Model', 'serial'], [], {'display-name': 'Laptop'}],
        [['DP-2', 'V', 'M', 's'], [], {}]];
    const monitors = [{index: 0, x: 1920, y: -200, width: 1000, height: 800},
        {index: 1, x: 0, y: 0, width: 1920, height: 1080}];
    const result = shellDisplays(logicals, physicals, monitors,
        i => ({x: monitors[i].x, y: monitors[i].y + 32, width: monitors[i].width, height: monitors[i].height - 32}), 1);
    assert.deepEqual(result.displays.map(d => d.id), ['gnome:DP-2', 'gnome:eDP-1']);
    assert.equal(result.primaryDisplayId, 'gnome:eDP-1');
    assert.equal(result.displays[1].scale, 1.25);
    assert.equal(result.displays[1].name, 'Laptop');
    assert.equal(result.displays[0].workY, -168);
});

test('no fabricated IDs when current DisplayConfig does not match Shell layout', () => {
    const result = shellDisplays([], [], [{index: 0, x: 0, y: 0, width: 1920, height: 1080}],
        () => ({x: 0, y: 0, width: 1920, height: 1080}), 0);
    assert.deepEqual(result, {displays: [], primaryDisplayId: ''});
});

test('mirrored connector identity is independent of DisplayConfig enumeration order', () => {
    const specs = [['HDMI-1', '', '', ''], ['DP-1', '', '', '']];
    const monitors = [{index: 0, x: 0, y: 0, width: 1000, height: 800}];
    const get = s => shellDisplays([[0, 0, 1, 0, true, s, {}]], [], monitors,
        () => ({x: 0, y: 0, width: 1000, height: 800}), 0).displays[0].id;
    assert.equal(get(specs), get([...specs].reverse()));
});

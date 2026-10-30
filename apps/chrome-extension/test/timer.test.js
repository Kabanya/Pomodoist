import test from 'node:test';
import assert from 'node:assert/strict';
import {preset,timerView} from '../src/timer.js';
const now=Date.parse('2026-10-26T10:00:00Z');
const envelope={serverNow:new Date(now).toISOString(),session:{run:{status:'running'},interval:{type:'work',status:'running',startedAt:new Date(now-60000).toISOString(),plannedSeconds:1500,pausedTotalSeconds:0}}};
test('existing durations create common Focus preset snapshots',()=>{
  assert.equal(preset(15).workSeconds,900);assert.equal(preset(5,true).strictMode,true);assert.throws(()=>preset(-1));
});
test('common timer accounts for server clock, pause and ready without inventing intervals',()=>{
  assert.equal(timerView(envelope,100,60100).remaining,1380);
  assert.equal(timerView(envelope,100,99999999).remaining,0);
  assert.equal(timerView(envelope,100,99999999).phase,'work');
  const paused=structuredClone(envelope);paused.session.interval.status='paused';paused.session.interval.pausedAt=new Date(now).toISOString();
  assert.equal(timerView(paused,100,99999999).remaining,1440);
  paused.session.interval.status='ready';assert.equal(timerView(paused,100,99999999).remaining,1500);
});

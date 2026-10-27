import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import { domain, blocked, rulesFor, active, fromEnvelope, pageMessage, bridgeOrigin, FocusProtection } from '../src/protection.js';
const now = Date.parse('2026-10-26T10:00:00Z');
const snapshot = (extra = {}) => ({ version: 1, owner: 'owner', sessionId: 'run', revision: 1,
  phase: 'work', status: 'running', strict: false, expiresAt: new Date(now + 60000).toISOString(), remainingSeconds: 60,
  profile: { blockedCategories: ['social'], overrides: [], blockOnPause: true },
  assignments: [{kind:'domain',id:'example.com',category:'social'}], ...extra });
test('domain boundaries and explicit allow precede category, specific overrides win', () => {
  assert.equal(domain('HTTPS://WWW.Example.com/path?private=1#x'), 'www.example.com');
  assert.equal(domain('bad host'), null);
  const s = snapshot();
  assert.equal(blocked(s, 'm.example.com', now), true);
  assert.equal(blocked(s, 'notexample.com', now), false);
  assert.equal(blocked(s, 'example.com.evil.test', now), false);
  s.profile.overrides = [{kind:'domain',id:'example.com',action:'allow'}, {kind:'domain',id:'chat.example.com',action:'block'}];
  assert.equal(blocked(s, 'm.example.com', now), false);
  assert.equal(blocked(s, 'chat.example.com', now), true);
  assert.equal(blocked(s, 'unknown.test', now), false);
  const rules = rulesFor(s, now);
  assert.ok(rules.some(r => r.action.type === 'allow' && r.priority > rules[0].priority));
  const match = new RegExp(rules[0].condition.regexFilter);
  assert.ok(match.test('https://a.example.com/path'));
  assert.ok(!match.test('https://example.com.evil.test/path'));
  assert.deepEqual(rules[0].condition.resourceTypes, ['main_frame']);
});
test('expiry releases all phases and strict pause keeps protection', () => {
  assert.equal(active(snapshot(), now + 60001), false);
  assert.deepEqual(rulesFor(snapshot(), now + 60001), []);
  assert.equal(active(snapshot({status:'ready'}), now), false);
  const s = snapshot({status:'paused'}); s.profile.blockOnPause = false;
  assert.equal(active(s, now), false); s.strict = true;
  assert.equal(active(s, now), true);
  assert.equal(active(snapshot({phase:'shortBreak'}), now), false);
});
test('server envelope derives remaining time and limits paused authority to five minutes', () => {
  const result = fromEnvelope({serverNow:new Date(now).toISOString(), profiles:[{id:'work'}], assignments:[], session:{
    id:'r', revision:3, profileId:'work', preset:{strictMode:true}, run:{id:'r',status:'running'},
    interval:{type:'work',status:'paused',plannedSeconds:1500,startedAt:new Date(now-300000).toISOString(),pausedAt:new Date(now).toISOString(),pausedTotalSeconds:0},
    protectionExpiresAt:new Date(now+9999999).toISOString()}}, 'owner', now);
  assert.equal(result.remainingSeconds,1200);
  assert.equal(Date.parse(result.expiresAt),now+300000);
  assert.equal(result.strict,true);
});
test('untrusted page messages get only guard actions and cannot choose a hostname', () => {
  const own = 'chrome-extension://abc/';
  assert.equal(pageMessage({type:'snapshot'}, {id:'abc',url:'https://example.com',tab:{id:1}}, own), null);
  assert.deepEqual(pageMessage({type:'guard',hostname:'private.test'}, {id:'abc',url:'https://example.com/path?secret',tab:{id:1}}, own), {type:'guard',hostname:'example.com',tabId:1});
  assert.equal(pageMessage({type:'focus',payload:{}}, {id:'abc',url:own+'blocked.html',tab:{id:1}}, own), null);
});
test('bridge accepts only numeric local ports', () => {
  assert.equal(bridgeOrigin(51988), 'http://127.0.0.1:51988');
  for (const input of ['51988/evil', 'https://evil.test', 0, 65536]) assert.throws(() => bridgeOrigin(input));
});
test('restart removes expired durable rules without cloud and clears existing guards', async () => {
  const calls = []; const saved = { enabled:true, owner:'owner', instance:'https://api.test', snapshot:snapshot({expiresAt:new Date(now-1).toISOString()}) };
  const chrome = { storage:{local:{get:async()=>({'pomodoist-protection-v1':saved}),set:async value=>calls.push(['save',value])}},
    declarativeNetRequest:{getDynamicRules:async()=>[{id:1}],updateDynamicRules:async value=>calls.push(['rules',value])},
    alarms:{create:async()=>{},clear:async()=>{}}, permissions:{contains:async()=>true},
    scripting:{registerContentScripts:async()=>{},unregisterContentScripts:async()=>{},executeScript:async()=>{}},
    tabs:{query:async()=>[{id:1,url:'https://example.com'}],sendMessage:async(id,value)=>calls.push(['guard',value])}, extension:{isAllowedIncognitoAccess:async()=>false} };
  const controller = new FocusProtection(chrome,{data:{owner:'owner',deviceId:'d',session:null}}, {}, {apiUrl:'https://api.test'},()=>now);
  await controller.init();
  assert.deepEqual(calls.find(c=>c[0]==='rules')[1],{removeRuleIds:[1],addRules:[]});
  assert.equal(calls.find(c=>c[0]==='guard')[1].blocked,false);
});
test('ready and ended server sessions release even with a null lease; native run status is active/paused',()=>{
  const e={serverNow:new Date(now).toISOString(),profiles:[{id:'work'}],assignments:[],session:{id:'r',revision:2,profileId:'work',preset:{},run:{status:'active'},interval:{type:'work',status:'ready',plannedSeconds:1500,startedAt:new Date(now).toISOString(),pausedTotalSeconds:0},protectionExpiresAt:null}};
  assert.equal(fromEnvelope(e,'owner',now).status,'ready');
  e.session.interval.status='paused';e.session.interval.pausedAt=new Date(now).toISOString();e.session.run.status='paused';e.session.protectionExpiresAt=new Date(now+300000).toISOString();
  assert.equal(fromEnvelope(e,'owner',now).status,'paused');
  e.session.interval.status='running';e.session.run.status='active';assert.equal(fromEnvelope(e,'owner',now).status,'running');
});
function controllerFixture(rpc){
  const writes=[];const api={storage:{local:{set:async v=>writes.push(v)}},permissions:{contains:async()=>true},extension:{isAllowedIncognitoAccess:async()=>false}};
  const p=new FocusProtection(api,{data:{owner:'owner',deviceId:'browser',session:{},records:{}}},{rpc},{apiUrl:'https://api.test'},()=>now);
  p.reconcile=async()=>{};p.data.owner='owner';return p;
}
const envelope=(revision=1)=>({serverNow:new Date(now).toISOString(),settingsRevision:1,profiles:[{id:'work',blockedCategories:[],overrides:[]}],assignments:[],devices:[],session:{id:'r',revision,profileId:'work',run:{status:'active'},preset:{},interval:{status:'running',type:'work',plannedSeconds:1500,startedAt:new Date(now).toISOString(),pausedTotalSeconds:0},protectionExpiresAt:new Date(now+1500000).toISOString()}});
test('paired desktop reads work when Chromium omits Origin on GET', async()=>{
  const server=createServer(async(req,res)=>{
    // Chromium's extension GET has no Origin and is rejected by the bridge.
    if(req.method!=='POST'||req.url!=='/command'||req.headers.authorization!=='Bearer paired-token'){
      res.writeHead(403).end();return;
    }
    const chunks=[];for await(const chunk of req)chunks.push(chunk);
    const command=JSON.parse(Buffer.concat(chunks));
    if(command.action!=='read'||typeof command.requestId!=='string'){
      res.writeHead(400).end();return;
    }
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(envelope(7)));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try{
    const p=controllerFixture(()=>assert.fail('paired desktop must not read cloud state'));
    p.data.source='desktop';
    p.data.bridge={port:server.address().port,token:'paired-token',owner:'owner',flavor:'production'};
    const result=await p.read({autoStart:false});
    assert.equal(result.session.revision,7);
    assert.equal(p.data.envelope.session.revision,7);
  }finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});
test('revision conflict adopts authoritative state and never calls a local fallback',async()=>{
  const p=controllerFixture(async()=>({...envelope(4),code:'revision_conflict'}));p.data.envelope=envelope(1);
  p.bridgeRequest=()=>assert.fail('conflict must not silently switch authority');
  await assert.rejects(p.command('pause'),/changed on another device/);
  assert.equal(p.data.envelope.session.revision,4);assert.equal(p.data.pendingCommand,null);
});
test('lost response retries the same durable command ID then rereads fresh authority',async()=>{
  const seen=[];let lost=true;
  const p=controllerFixture(async(name,{p_command:c})=>{seen.push(c);if(c.action==='read')return envelope(5);if(lost){lost=false;throw new Error('network');}return envelope(2);});
  p.data.envelope=envelope(1);
  await assert.rejects(p.command('pause'),/network/);
  const pending=structuredClone(p.data.pendingCommand);
  await p.command('pause');
  assert.deepEqual(seen[0],seen[1]);assert.equal(seen[0].requestId,pending.command.requestId);
  assert.equal(p.data.envelope.session.revision,5);
});
test('strict device detach countdown keeps protection enabled and a later authoritative detach releases it',async()=>{
  const pending={...envelope(2),code:'strict_exit_pending'};pending.devices=[{deviceId:'browser',exitRequestedAt:new Date(now).toISOString(),detached:false}];
  const p=controllerFixture(async()=>pending);p.data.enabled=true;p.data.envelope=envelope(1);
  await assert.rejects(p.configure({enabled:false}),/countdown/);assert.equal(p.data.enabled,true);
  await p.accept({...envelope(3),devices:[{deviceId:'browser',detached:true}]});assert.equal(p.data.enabled,false);assert.equal(p.data.snapshot.profile,null);
});
test('source changes obey fresh strict exit policy with protection off and no blocking profile',async()=>{
  const actions=[];const fresh=envelope(8);fresh.profiles=[];fresh.session.profileId=null;fresh.session.preset.strictMode=true;
  const p=controllerFixture(async(name,{p_command:c})=>{actions.push(c);if(c.action==='read')return {...fresh,profiles:[{id:'unused'}]};return {...fresh,code:'strict_exit_pending',devices:[{deviceId:'browser',exitRequestedAt:new Date(now).toISOString(),detached:false}]};});
  p.data.envelope={...envelope(1),session:null};p.data.bridge={owner:'owner',flavor:'production'};
  await assert.rejects(p.configure({source:'desktop'}),/countdown/);
  assert.equal(p.data.source,'cloud');assert.equal(p.data.enabled,false);assert.equal(p.data.snapshot.profile,null);
  assert.deepEqual(actions.map(c=>c.action),['read','detach']);assert.equal(actions[1].expectedRevision,8);
});
test('disabled protection still detaches ordinary Focus using fresh revision before allowing exit',async()=>{
  const actions=[];const p=controllerFixture(async(name,{p_command:c})=>{actions.push(c);return {...envelope(9),devices:c.action==='detach'?[{deviceId:'browser',detached:true}]:[]};});
  p.data.envelope=envelope(1);await p.configure({enabled:false});
  assert.deepEqual(actions.map(c=>c.action),['read','detach']);assert.equal(actions[1].expectedRevision,9);assert.equal(p.data.envelope.devices[0].detached,true);
});
test('revoked optional host permission releases any surviving content guard and disables coverage claim',async()=>{
  const p=controllerFixture(async()=>envelope());p.data.enabled=true;p.data.snapshot=snapshot();p.chrome.permissions.contains=async()=>false;
  assert.equal((await p.guard('example.com')).blocked,false);assert.equal((await p.coverage()).active,false);
});
test('automatic opt-in classifies public unknown and manual-unclassified domains only, preserving manual categories',async()=>{
  const seen=[];const p=controllerFixture(async()=>envelope());
  p.store.data.overview={profile:{pomodoistIsPro:true}};p.data.enabled=true;p.data.autoClassify=true;
  p.data.discovered=['localhost','private.internal','example.com','classified.com','todo.com'];
  p.data.envelope={...envelope(),assignments:[{kind:'domain',id:'classified.com',category:'social',source:'manual'},{kind:'domain',id:'todo.com',category:'unclassified',source:'manual'}]};
  p.client.classifyResource=async id=>{seen.push(id);return {ok:true,assignment:{kind:'domain',id,name:id,category:'productivity',source:'automatic',sources:[]}};};
  p.command=async(action,payload)=>{assert.equal(action,'assignmentUpsert');assert.equal(payload.assignment.source,'automatic');};
  await p.classifyNext();await p.classifyNext();
  assert.deepEqual(seen,['example.com','todo.com']);
});
test('classification finishing after an account switch cannot apply to the next account',async()=>{
  const p=controllerFixture(async()=>envelope());p.store.data.overview={profile:{pomodoistIsPro:true}};
  p.data.enabled=true;p.data.autoClassify=true;p.data.discovered=['example.com'];
  p.client.classifyResource=async id=>{p.store.data.owner='other';return {ok:true,assignment:{kind:'domain',id,source:'automatic',category:'news'}};};
  p.command=async()=>assert.fail('old account result must not cross owners');
  await p.classifyNext();assert.equal(p.data.classificationError,undefined);
});
test('strict destructive commands enter the common exit flow instead of changing the interval',async()=>{
  const actions=[];const p=controllerFixture(async(name,{p_command:c})=>{actions.push(c.action);return {...envelope(1),code:c.action==='skip'?'strict_exit_required':'strict_exit_pending'};});
  await p.command('skip');assert.deepEqual(actions,['skip','requestStop']);
});
test('profile upserts and completed sessions retain the server revision for the next start',async()=>{
  const p=controllerFixture(async(name,{p_command:c})=>{assert.equal(c.expectedRevision,7);return {...envelope(8),session:{...envelope(8).session,run:{status:'completed'},interval:{...envelope(8).session.interval,status:'completed'},protectionExpiresAt:null}};});
  p.data.envelope={...envelope(7),session:{...envelope(7).session,run:{status:'stopped'},protectionExpiresAt:null}};
  await p.command('start',{preset:{id:'classic'}});assert.equal(p.data.snapshot.status,'ended');
});
test('slow responses cannot extend the confirmed running deadline',async()=>{
  let clock=now;const p=controllerFixture(async()=>{clock+=5000;return envelope();});p.clock=()=>clock;
  await p.read();assert.equal(Date.parse(p.data.snapshot.expiresAt),now+1500000);
  assert.equal(p.data.readAt,now);
});
test('unclassified resources stay allowed unless explicitly blocked',()=>{
  const s=snapshot();s.profile.blockedCategories=['unclassified'];s.assignments[0].category='unclassified';
  assert.equal(blocked(s,'example.com',now),false);
  s.profile.overrides=[{kind:'domain',id:'example.com',action:'block'}];assert.equal(blocked(s,'example.com',now),true);
});
test('emergency release cannot bypass online strict detach policy, but unavailable authority permits local-only release',async()=>{
  const p=controllerFixture(async()=>{const e=envelope();e.session.preset.strictMode=true;return e;});p.data.enabled=true;p.data.snapshot=snapshot({strict:true});
  await assert.rejects(p.emergencyRelease(true),/connected|normal/i);assert.equal(p.data.enabled,true);
  p.client.rpc=async()=>{throw new Error('Cannot reach the server. Check your connection and retry.');};
  await p.emergencyRelease(true);assert.equal(p.data.enabled,false);assert.equal(p.data.snapshot.strict,true);
});
function transitionFixture({from='work',to='shortBreak',enabled=true,duration=15}={}){
  let clock=now,next=false;const actions=[];
  const state=(status='running')=>{const e=envelope(next?3:2);e.serverNow=new Date(clock).toISOString();e.session.preset={autoStartWork:enabled,autoStartBreaks:enabled};e.session.interval={...e.session.interval,id:next?'next':'previous',type:next?to:from,status:next?status:'running',plannedSeconds:next?300:duration,startedAt:new Date(next?now+duration*1000:now).toISOString()};e.session.protectionExpiresAt=next&&status==='ready'?null:new Date(clock+300000).toISOString();return e;};
  const p=controllerFixture(async(name,{p_command:c})=>{actions.push(c);return state(c.action==='startReady'?'running':next?'ready':'running');});p.clock=()=>clock;
  return {p,actions,state,advance:ms=>{clock+=ms;next=true;}};
}
test('a recent natural running-to-ready transition honors auto-start break and work flags',async()=>{
  for(const phases of [{from:'work',to:'shortBreak'},{from:'shortBreak',to:'work'},{from:'work',to:'longBreak'}]){
    const f=transitionFixture(phases);await f.p.read();f.advance(16000);const result=await f.p.read();
    assert.equal(result.session.interval.status,'running');assert.deepEqual(f.actions.map(c=>c.action),['read','read','startReady']);assert.equal(f.actions[2].expectedRevision,3);
  }
});
test('a completion revision conflict adopts the ready interval and applies the same auto-start transition',async()=>{
  const f=transitionFixture();await f.p.read();f.advance(16000);const rpc=f.p.client.rpc;
  f.p.client.rpc=async(name,args)=>args.p_command.action==='complete'?{...f.state('ready'),code:'revision_conflict'}:rpc(name,args);
  await assert.rejects(f.p.command('complete'),/changed on another device/);
  assert.equal(f.p.data.envelope.session.interval.status,'running');assert.equal(f.actions.at(-1).action,'startReady');
});
test('auto-start never backfills a long gap even when waking near the previous deadline',async()=>{
  const f=transitionFixture({duration:1500});await f.p.read();f.advance(1501000);await f.p.read();
  assert.equal(f.p.data.envelope.session.interval.status,'ready');assert.deepEqual(f.actions.map(c=>c.action),['read','read']);
});
test('disabled auto-start flags leave the next interval ready',async()=>{
  for(const phases of [{from:'work',to:'shortBreak'},{from:'shortBreak',to:'work'}]){
    const f=transitionFixture({...phases,enabled:false});await f.p.read();f.advance(16000);await f.p.read();
    assert.equal(f.p.data.envelope.session.interval.status,'ready');assert.equal(f.actions.length,2);
  }
});
test('initial restoration does not auto-start from a persisted running snapshot',async()=>{
  const f=transitionFixture();f.p.data.envelope=f.state();f.p.data.readAt=now;f.advance(16000);await f.p.read();
  assert.equal(f.p.data.envelope.session.interval.status,'ready');assert.equal(f.actions.length,1);
});
test('a ready transition is attempted once even if startReady races another device',async()=>{
  const f=transitionFixture();await f.p.read();f.advance(16000);const rpc=f.p.client.rpc;let attempts=0;
  f.p.client.rpc=async(name,args)=>{if(args.p_command.action==='startReady'){attempts++;return {...f.state('ready'),code:'revision_conflict'};}return rpc(name,args);};
  await assert.rejects(f.p.read(),/changed on another device/);await f.p.read();
  assert.equal(attempts,1);assert.equal(f.p.data.envelope.session.interval.status,'ready');
});
test('an offline observation gap suppresses automatic ready start after reconnecting',async()=>{
  const f=transitionFixture();await f.p.read();const rpc=f.p.client.rpc;
  f.p.client.rpc=async()=>{throw new Error('Cannot reach the server.');};await assert.rejects(f.p.read(),/Cannot reach/);
  f.p.client.rpc=rpc;f.advance(16000);await f.p.read();
  assert.deepEqual(f.actions.map(c=>c.action),['read','read']);assert.equal(f.p.data.envelope.session.interval.status,'ready');
});
test('manual early completion and device exit reads do not auto-start the next interval',async()=>{
  const early=transitionFixture();await early.p.read();early.advance(1000);await early.p.read();assert.equal(early.p.data.envelope.session.interval.status,'ready');
  const exit=transitionFixture();await exit.p.read();exit.advance(16000);await exit.p.read({autoStart:false});
  assert.deepEqual(exit.actions.map(c=>c.action),['read','read']);assert.equal(exit.p.data.envelope.session.interval.status,'ready');
});
function coverageFixture(){
  let clock=now,permitted=true,incognito=false,failure=null;const reports=[],events=[];
  const p=controllerFixture(async(name,{p_command:c})=>{events.push('report');reports.push(c);return {...envelope(99),devices:[{deviceId:'browser',appliedRevision:c.payload.appliedRevision,capabilities:c.payload.capabilities}]};});
  p.clock=()=>clock;p.data.enabled=true;p.data.envelope=envelope(7);p.data.snapshot=fromEnvelope(p.data.envelope,'owner',clock);
  p.reconcile=FocusProtection.prototype.reconcile;
  p.chrome.permissions.contains=async()=>permitted;p.chrome.extension.isAllowedIncognitoAccess=async()=>incognito;
  p.chrome.declarativeNetRequest={getDynamicRules:async()=>[],updateDynamicRules:async()=>{events.push('rules');if(failure==='rules')throw new Error('DNR failed');}};
  p.chrome.alarms={create:async()=>{},clear:async()=>{}};
  p.chrome.scripting={unregisterContentScripts:async()=>{},registerContentScripts:async()=>events.push('register'),executeScript:async()=>{events.push('inject');if(failure==='guard')throw new Error('guard failed');}};
  p.chrome.tabs={query:async()=>[{id:1,url:'https://example.com'}],sendMessage:async()=>events.push('guard')};
  return {p,reports,events,advance:ms=>clock+=ms,permission:value=>permitted=value,incognito:value=>incognito=value,fail:value=>failure=value};
}
test('coverage acknowledgement follows successful DNR and guard application without accepting the registration envelope',async()=>{
  const f=coverageFixture();await f.p.reconcile();
  assert.deepEqual(f.events,['rules','register','inject','guard','report']);assert.equal(f.reports[0].action,'registerDevice');
  assert.deepEqual(f.reports[0].payload.capabilities,{websiteBlocking:true,incognito:false,appBlocking:false,websiteApplied:true});
  assert.equal(f.reports[0].payload.appliedRevision,7);assert.equal(f.p.data.envelope.session.revision,7);assert.equal(f.p.data.pendingCommand,undefined);
  await f.p.reconcile();f.advance(14999);await f.p.reconcile();assert.equal(f.reports.length,1);
  f.advance(1);await f.p.reconcile();assert.equal(f.reports.length,2);
});
test('coverage changes report immediately and cannot claim applied protection without permission or after expiry/detach',async()=>{
  const f=coverageFixture();await f.p.reconcile();f.p.data.envelope.session.revision=8;f.p.data.snapshot.revision=8;await f.p.reconcile();assert.equal(f.reports.at(-1).payload.appliedRevision,8);
  f.permission(false);await f.p.reconcile();assert.equal(f.reports.at(-1).payload.capabilities.websiteBlocking,false);assert.equal(f.reports.at(-1).payload.appliedRevision,null);
  f.permission(true);f.incognito(true);await f.p.reconcile();assert.equal(f.reports.at(-1).payload.capabilities.incognito,true);
  f.advance(1500001);await f.p.reconcile();assert.equal(f.reports.at(-1).payload.appliedRevision,null);assert.equal(f.reports.at(-1).payload.capabilities.websiteApplied,false);
  f.p.data.envelope.devices=[{deviceId:'browser',detached:true}];f.p.data.snapshot.expiresAt=new Date(now+9999999).toISOString();await f.p.reconcile();assert.equal(f.reports.at(-1).payload.appliedRevision,null);
});
test('failed DNR or loaded-page guard application never acknowledges an applied revision',async()=>{
  for(const failure of ['rules','guard']){
    const f=coverageFixture();f.fail(failure);
    if(failure==='rules')await assert.rejects(f.p.reconcile(),/DNR failed/);else await f.p.reconcile();
    assert.equal(f.reports.at(-1)?.payload.appliedRevision,null);assert.equal(f.reports.at(-1)?.payload.capabilities.websiteApplied,false);
    assert.equal((await f.p.coverage()).active,false);
    f.fail(null);await f.p.reconcile();assert.equal(f.reports.at(-1).payload.appliedRevision,7);
  }
});
test('source changes acknowledge paired bridge coverage without accepting its Focus clock or lease',async()=>{
  const f=coverageFixture();await f.p.reconcile();const expiry=f.p.data.snapshot.expiresAt;
  f.p.data.source='desktop';f.p.data.bridge={port:51989,owner:'owner',flavor:'production'};let command;
  f.p.bridgeRequest=async(path,c)=>{assert.equal(path,'/command');command=c;return {...envelope(200),devices:[]};};
  await f.p.reconcile();assert.equal(command.action,'registerDevice');assert.equal(command.payload.appliedRevision,7);
  assert.equal(f.p.data.snapshot.expiresAt,expiry);assert.equal(f.p.data.envelope.session.revision,7);
});
test('coverage acknowledgement failures are advisory and retry no faster than the active polling interval',async()=>{
  const f=coverageFixture();let attempts=0;f.p.client.rpc=async()=>{attempts++;throw new Error('Offline coverage report');};
  await f.p.reconcile();assert.equal((await f.p.coverage()).active,true);assert.match((await f.p.coverage()).error,/Offline coverage/);
  await f.p.reconcile();assert.equal(attempts,1);f.advance(15000);await f.p.reconcile();assert.equal(attempts,2);
});
test('overlapping lifecycle reconciliations cannot install duplicate DNR rule IDs',async()=>{
  const f=coverageFixture();f.p.data.snapshot.assignments=[{kind:'domain',id:'example.com',category:'social'}];f.p.data.snapshot.profile.blockedCategories=['social'];let current=[];
  f.p.chrome.declarativeNetRequest={getDynamicRules:async()=>{const observed=structuredClone(current);await Promise.resolve();return observed;},updateDynamicRules:async({removeRuleIds,addRules})=>{
    current=current.filter(r=>!removeRuleIds.includes(r.id));for(const rule of addRules){if(current.some(r=>r.id===rule.id))throw new Error('Duplicate DNR rule');current.push(rule);}
  }};
  await assert.doesNotReject(Promise.all([f.p.reconcile(),f.p.reconcile()]));assert.equal(current.length,1);assert.equal(f.reports.length,1);
});
test('manual assignment preserved is a successful authoritative assignment response',async()=>{
  const assignment={kind:'domain',id:'example.com',category:'social',source:'manual'};
  const p=controllerFixture(async()=>({...envelope(4),code:'manual_assignment_preserved',assignments:[assignment]}));
  await p.command('assignmentUpsert',{assignment:{...assignment,category:'news',source:'automatic'}});
  assert.deepEqual(p.data.envelope.assignments,[assignment]);assert.equal(p.data.pendingCommand,null);
});

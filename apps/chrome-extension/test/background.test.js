import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {Store,synchronize} from '../src/sync.js';
import {FocusProtection,pageMessage,domain,active} from '../src/protection.js';

// Exercise the shipped worker route and real durable stores. Only Chrome APIs
// and the remote authority are replaced; an accidental logout clears this store.
async function worker({strict=true,seconds=60,confirmed=true}={}){
  const stamp='2026-10-26T10:00:00Z',actions=[];
  const saved={'pomodoist-extension-v1':{version:1,instance:'https://api.test',deviceId:'browser',owner:'owner',session:{access_token:'token',user:{email:'a@test'}},records:{},outbox:[],cursor:0}};
  const state={serverNow:stamp,profiles:[{id:'unused'}],assignments:[],devices:[],session:{id:'r',revision:7,profileId:null,strictExitSeconds:seconds,preset:{strictMode:strict},run:{status:'active'},interval:{type:'work',status:'running',plannedSeconds:1500,startedAt:stamp,pausedTotalSeconds:0},protectionExpiresAt:'2026-10-26T10:25:00Z'}};
  const event={addListener(){}};let onMessage;
  const chrome={storage:{local:{get:async key=>({[key]:saved[key]}),set:async patch=>Object.assign(saved,structuredClone(patch)),setAccessLevel:async()=>{}}},
    runtime:{id:'abc',getURL:path=>`chrome-extension://abc/${path}`,onMessage:{addListener:listener=>{onMessage=listener;}},sendMessage:async()=>{},onStartup:event,onInstalled:event},
    permissions:{contains:async()=>false,onRemoved:event},extension:{isAllowedIncognitoAccess:async()=>false},
    alarms:{create:async()=>{},clear:async()=>{},onAlarm:event},
    declarativeNetRequest:{getDynamicRules:async()=>[],updateDynamicRules:async()=>{}},
    scripting:{unregisterContentScripts:async()=>{}},tabs:{query:async()=>[],onActivated:event,onUpdated:event},
    webNavigation:{onCommitted:event,onHistoryStateUpdated:event,onReferenceFragmentUpdated:event}};
  class Client{
    async rpc(name,{p_command:c}){actions.push(c);if(c.action==='detach'){
      if(strict&&seconds===0&&!c.payload.confirmed)return {...state,code:'strict_confirmation_required'};
      return {...state,...(strict&&seconds===60?{code:'strict_exit_pending'}:{}),devices:[{deviceId:'browser',detached:!strict||seconds===0,...(strict&&seconds===60?{exitRequestedAt:stamp}:{})}]};
    }return state;}
    async raw(){actions.push({action:'revoke'});}
  }
  const source=(await readFile(new URL('../src/background.js',import.meta.url),'utf8')).replace(/^import .*;\n/gm,'');
  vm.runInNewContext(source,{chrome,Store,synchronize,FocusProtection,pageMessage,domain,active,Client,config:{apiUrl:'https://api.test'},crypto:globalThis.crypto,Date,Promise,setInterval(){},Realtime:class{start(){}stop(){}}});
  const result=await new Promise(resolve=>onMessage({type:'logout',payload:{confirmed}},{id:'abc',url:'chrome-extension://abc/popup.html'},resolve));
  return {result,saved,actions};
}
test('logout cannot bypass a fresh strict countdown when browser protection is disabled',async()=>{
  const {result,saved,actions}=await worker();
  assert.equal(result.ok,false);assert.match(result.error,/countdown/);
  assert.equal(saved['pomodoist-extension-v1'].session.access_token,'token');
  assert.deepEqual(actions.map(c=>c.action),['read','registerDevice','detach']);assert.equal(actions[1].payload.appliedRevision,null);
});
test('logout requires strict immediate confirmation without a blocking profile or host permission',async()=>{
  const {result,saved}=await worker({seconds:0,confirmed:false});
  assert.equal(result.ok,false);assert.match(result.error,/Confirm/);assert.ok(saved['pomodoist-extension-v1'].session);
});
test('ordinary and confirmed immediate strict logout detach this device before clearing credentials',async()=>{
  for(const options of [{strict:false},{seconds:0}]){
    const {result,saved,actions}=await worker(options);
    assert.equal(result.ok,true);assert.equal(saved['pomodoist-extension-v1'].session,null);
    assert.deepEqual(actions.map(c=>c.action),['read','registerDevice','detach','revoke']);assert.equal(actions[2].expectedRevision,7);assert.equal(actions[1].payload.appliedRevision,null);
  }
});

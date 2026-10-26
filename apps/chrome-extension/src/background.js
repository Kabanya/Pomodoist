import { config } from './config.js';
import { Store, synchronize } from './sync.js';
import { Client } from './client.js';
import { FocusProtection, pageMessage, domain, active } from './protection.js';
import { Realtime } from './realtime.js';

const store = new Store(chrome.storage.local, config.apiUrl);
const client = new Client(config, store);
const protection = new FocusProtection(chrome,store,client,config);
let tail=Promise.resolve(),lastFocusRead=0,classifying=false;
const snapshot=async()=>({...store.snapshot(),...await protection.snapshot()});
const notify = async () => chrome.runtime.sendMessage({ event: 'state', snapshot: await snapshot() }).catch(() => {});
const sync = async () => { try { await synchronize(store, client, notify); } catch { /* Persisted in task state. */ } };
async function readFocus() {lastFocusRead=Date.now();try {await protection.read();live();} catch {} }
const realtime=new Realtime(async()=>({apiUrl:config.apiUrl,anonKey:config.anonKey,accessToken:await client.token(),userId:store.data.owner,deviceId:store.data.deviceId}),
  ()=>enqueue(async()=>{await readFocus();await notify();}),()=>{});
function live(){
  if(protection.data.enabled&&protection.data.source==='cloud'&&store.data.session) realtime.start(); else realtime.stop();
}
const ready=(async()=>{
  await chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});
  await store.init();await protection.init();live();
  if(protection.data.enabled) await readFocus();
})();
function classify(){
  if(classifying)return;classifying=true;
  protection.classifyNext(operation=>enqueue(operation)).finally(()=>{classifying=false;notify();}).catch(()=>{});
}
function enqueue(action) {const run=tail.then(async()=>{await ready;return action();});tail=run.catch(()=>{});return run;}
async function dispatch(message) {
  const p=message.payload??{};
  switch(message.type){
    case 'snapshot':break;
    case 'sync':await sync();await readFocus();break;
    case 'aiUsage':await protection.loadQuota();break;
    case 'focusRead':await protection.read();lastFocusRead=Date.now();break;
    case 'focus':await protection.command(p.action,p.payload);lastFocusRead=Date.now();break;
    case 'protection':await protection.configure(p);live();classify();break;
    case 'pair':await protection.pair(p);live();break;
    case 'emergencyRelease':
      await protection.emergencyRelease(p.confirm===true);live();break;
    case 'mutate':await store.enqueue(p.action,p.owner);await notify();await sync();break;
    case 'password':{
      if(store.data.session)throw new Error('Sign out before switching accounts.');
      if(typeof p.email!=='string'||!p.email.trim()||p.email.length>320||typeof p.password!=='string'||!p.password||p.password.length>4096)throw new Error('Enter your email and password.');
      const captcha=config.captchaEnabled?await client.captcha(chrome.identity):undefined;
      const session=await client.password(p.email,p.password,captcha);
      if(protection.data.owner && protection.data.owner!==session.user.id) await protection.clear();
      await store.acceptSession(session);await notify();await sync();await readFocus();live();break;
    }
    case 'oauth':{
      if(store.data.session)throw new Error('Sign out before switching accounts.');
      const session=await client.oauth(p.provider,chrome.identity);
      if(protection.data.owner && protection.data.owner!==session.user.id) await protection.clear();
      await store.acceptSession(session);await notify();await sync();await readFocus();live();break;
    }
    case 'logout':{
      await protection.configure({enabled:false,confirmed:p.confirmed===true});
      const token=store.data.session?.access_token;
      await store.logout(p.discard===true);await protection.clear();live();await notify();
      if(token){try{await client.raw('/auth/v1/logout?scope=local',{},token,true);}catch{await store.save({error:'Signed out on this device. Server session revocation could not be confirmed.'});}}
      break;
    }
    case 'realtime':return {apiUrl:config.apiUrl,anonKey:config.anonKey,accessToken:await client.token(),userId:store.data.owner,deviceId:store.data.deviceId};
    default:throw new Error('Unknown extension command.');
  }
  await notify();return snapshot();
}
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(message?.event)return false;
  if(sender.id!==chrome.runtime.id)return false;
  const popup=sender.url===chrome.runtime.getURL('popup.html');
  const page=popup?null:pageMessage(message,sender,chrome.runtime.getURL(''));
  if(!popup&&!page)return false;
  const run=enqueue(async()=>{
    if(popup)return dispatch(message);
    if(page.type==='guard'){
      if(protection.data.enabled&&Date.now()-lastFocusRead>=15000){lastFocusRead=Date.now();enqueue(async()=>{await readFocus();classify();await notify();}).catch(()=>{});}
      return protection.guard(page.hostname,page.discover!==false);
    }
    await protection.reconcile();
    if(page.type==='returnToTask'){
      const app=await chrome.tabs.query({url:`${config.webUrl}/*`});
      if(app[0]?.id){await chrome.tabs.update(app[0].id,{active:true});if(Number.isInteger(app[0].windowId))await chrome.windows.update(app[0].windowId,{focused:true});}else await chrome.tabs.create({url:config.webUrl});
      return {};
    }
    const s=protection.data.snapshot;
    const host=domain(sender.tab?.url??'');
    const guarding=sender.url.includes('?guard=1');
    const permitted=await chrome.permissions.contains({origins:['http://*/*','https://*/*']});
    const value=protection.data.enabled&&permitted&&active(s)&&(!guarding||host)?s:null;
    return {taskTitle:value?.taskTitle,remainingSeconds:value?.status==='running'?Math.max(0,value.remainingSeconds-Math.floor((Date.now()-(protection.data.readAt??Date.now()))/1000)):value?.remainingSeconds??0,status:value?.status,expiresAt:value?.expiresAt??null};
  });
  run.then(value=>respond({ok:true,value}),async error=>{
    const message=error?.message||'The operation failed. Please retry.';
    if(popup&&store.data){try{await store.save({error:message});await notify();}catch{}}
    respond({ok:false,error:message});
  });return true;
});
const refreshProtection=()=>enqueue(async()=>{await protection.reconcile();if(protection.data.enabled)await readFocus();await notify();});
chrome.alarms.onAlarm.addListener(alarm=>{if(['focus-refresh','focus-expiry'].includes(alarm.name))refreshProtection().catch(()=>{});});
chrome.runtime.onStartup.addListener(()=>refreshProtection().catch(()=>{}));
chrome.runtime.onInstalled.addListener(()=>refreshProtection().catch(()=>{}));
chrome.tabs.onActivated.addListener(({tabId})=>enqueue(async()=>{await protection.ensureTab(tabId);if(protection.data.enabled&&Date.now()-lastFocusRead>=15000)await readFocus();}).catch(()=>{}));
chrome.tabs.onUpdated.addListener((id,change)=>{if(change.url||change.status==='complete')enqueue(()=>protection.ensureTab(id)).catch(()=>{});});
for(const event of [chrome.webNavigation.onCommitted,chrome.webNavigation.onHistoryStateUpdated,chrome.webNavigation.onReferenceFragmentUpdated])event.addListener(details=>{if(details.frameId===0)enqueue(()=>protection.ensureTab(details.tabId)).catch(()=>{});});
chrome.permissions.onRemoved.addListener(()=>refreshProtection().catch(()=>{}));
// WebSocket heartbeats keep MV3 alive while connected; alarms and guards recover after suspension.
setInterval(()=>{if(protection.data.enabled)enqueue(async()=>{await readFocus();classify();if(Date.now()-(protection.data.quotaAt??0)>60000)await protection.loadQuota();await notify();}).catch(()=>{});},15000);

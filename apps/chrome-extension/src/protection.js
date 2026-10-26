export const CATEGORIES = ['social','messaging','video','music','games','news','shopping','education','development','productivity','other','unclassified'];
const KEY = 'pomodoist-protection-v1';
const ORIGINS = ['http://*/*','https://*/*'];
const unavailable=error=>error?.status>=500 || /^(Cannot reach the server|Desktop app unavailable)/.test(error?.message??'');
const matches = (host, parent) => host === parent || host.endsWith(`.${parent}`);
export function domain(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value.includes('://') ? value : `https://${value}`);
    if (!['http:','https:'].includes(url.protocol) || url.username || url.password) return null;
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    return host.length <= 253 && /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(host) && !host.includes('..') ? host : null;
  } catch { return null; }
}
export function active(s, now = Date.now()) {
  if (!s || s.version !== 1 || !s.profile || !Number.isFinite(Date.parse(s.expiresAt)) || Date.parse(s.expiresAt) <= now || !['running','paused'].includes(s.status)) return false;
  if (s.status === 'paused' && (s.strict || s.profile.blockOnPause !== false)) return true;
  if (s.status === 'paused') return false;
  return s.phase === 'work' || s.phase === 'shortBreak' && s.profile.blockOnShortBreak === true || s.phase === 'longBreak' && s.profile.blockOnLongBreak === true;
}
function candidates(s) {
  const assignments = (s?.assignments ?? []).filter(a=>a.kind==='domain' && !a.isDeleted && domain(a.id)===a.id);
  const rules = assignments.map(a=>({id:a.id,action:a.category!=='unclassified'&&s.profile.blockedCategories?.includes(a.category)?'block':'allow',priority:1+a.id.length}));
  for (const r of s.profile.overrides ?? []) if (r.kind==='domain' && domain(r.id)===r.id && ['allow','block'].includes(r.action)) {
    rules.push({id:r.id,action:r.action,priority:1000+r.id.length});
  }
  return rules;
}
export function blocked(s, host, now = Date.now()) {
  if (!active(s,now) || !domain(host)) return false;
  return candidates(s).filter(r=>matches(host,r.id)).sort((a,b)=>b.priority-a.priority)[0]?.action === 'block';
}
export function rulesFor(s, now = Date.now()) {
  if (!active(s,now)) return [];
  // Each allow receives the same specificity ordering as the in-page guard.
  return candidates(s).map((r,i)=>({id:i+1,priority:r.priority,action:r.action==='block'?{type:'redirect',redirect:{extensionPath:'/blocked.html'}}:{type:'allow'},
    condition:{regexFilter:`^https?://([a-z0-9-]+\\.)*${r.id.replaceAll('.','\\.')}(:[0-9]+)?/`,isUrlFilterCaseSensitive:false,resourceTypes:['main_frame']}}));
}
export function fromEnvelope(envelope, owner, now = Date.now()) {
  if (!envelope || !Array.isArray(envelope.profiles) || !Array.isArray(envelope.assignments)) throw new Error('Invalid Focus response.');
  const s = envelope.session;
  if (!s) return null;
  if (typeof s.id!=='string' || !Number.isSafeInteger(s.revision) || !s.interval || !s.run || !s.preset) throw new Error('Invalid Focus session.');
  const i=s.interval, serverNow=Date.parse(envelope.serverNow ?? s.serverNow);
  if (!Number.isFinite(serverNow)) throw new Error('Invalid Focus server clock.');
  const clock = i.status==='paused'?Date.parse(i.pausedAt):serverNow;
  const elapsed = Math.max(0,(clock-Date.parse(i.startedAt))/1000-(Number(i.pausedTotalSeconds)||0));
  const remaining = i.status==='ready'?Number(i.plannedSeconds):Math.max(0,Math.ceil(Number(i.plannedSeconds)-elapsed));
  const running=['active','paused','running'].includes(s.run.status);
  const lease = ['running','paused'].includes(i.status)&&running?Date.parse(s.protectionExpiresAt):serverNow;
  if (!Number.isFinite(remaining) || !Number.isFinite(lease)) throw new Error('Invalid Focus deadline.');
  const expires = Math.min(lease-serverNow+now, now+(i.status==='paused'?300000:remaining*1000));
  return {version:1,owner,sessionId:s.id,revision:s.revision,phase:i.type,status:running?i.status:'ended',
    strict:s.preset.strictMode===true,expiresAt:new Date(expires).toISOString(),remainingSeconds:remaining,
    taskId:s.run.taskId,taskTitle:typeof s.taskTitle==='string'?s.taskTitle.slice(0,2048):undefined,
    profile:envelope.profiles.find(p=>p.id===s.profileId && !p.isDeleted)??null,assignments:envelope.assignments};
}
export function bridgeOrigin(port) {
  if (!/^\d{1,5}$/.test(String(port)) || Number(port)<1 || Number(port)>65535) throw new Error('Enter a valid desktop port.');
  return `http://127.0.0.1:${Number(port)}`;
}
export function pageMessage(message,sender,base) {
  if (sender.id!==new URL(base).hostname || !Number.isInteger(sender.tab?.id)) return null;
  if (message?.type==='returnToTask' && /^https?:/.test(sender.url??'')) return {type:'returnToTask',tabId:sender.tab.id};
  if (message?.type==='guard' && /^https?:/.test(sender.url??'')) return {type:'guard',hostname:domain(sender.frameId?sender.tab.url:sender.url),tabId:sender.tab.id,...(sender.frameId?{discover:false}:{})};
  if (['blockState','returnToTask'].includes(message?.type) && sender.url?.split('?')[0]===`${base}blocked.html`) return {type:message.type,tabId:sender.tab.id};
  return null;
}
export class FocusProtection {
  constructor(chrome,store,client,config,clock=()=>Date.now()) {
    this.chrome=chrome; this.store=store; this.client=client; this.config=config; this.clock=clock;
    this.data={instance:config.apiUrl,flavor:config.flavor??'production',enabled:false,source:'cloud',snapshot:null,envelope:null,discovered:[],bridge:null,autoClassify:false,classificationAttempts:{},error:''};
  }
  async save(patch) { this.data={...this.data,...patch}; await this.chrome.storage.local.set({[KEY]:this.data}); }
  async init() {
    const saved=(await this.chrome.storage.local.get(KEY))[KEY];
    if (saved?.instance===this.config.apiUrl && (saved.flavor??'production')===(this.config.flavor??'production')) this.data={...this.data,...saved};
    if (this.data.owner && this.store.data.owner && this.data.owner!==this.store.data.owner) await this.clear();
    await this.reconcile();
    await this.chrome.alarms.create('focus-refresh',{periodInMinutes:0.5});
  }
  isPro(){
    const o=this.store.data.overview;
    if(o?.profile?.pomodoistIsPro??o?.profile?.pomodoist_is_pro)return true;
    return o?.apps?.find(a=>(a.id??a.appId??a.app_id)==='pomodoist')?.entitlements?.some(e=>e.status==='active'&&(!(e.validUntil??e.valid_until)||Date.parse(e.validUntil??e.valid_until)>this.clock()))===true;
  }
  async loadQuota(commit=operation=>operation()){
    if(!this.store.data.session)return;
    const owner=this.store.data.owner;
    try{
      const quota=await this.client.rpc('get_usage_period',{p_app_id:'pomodoist',p_quota_key:'llm_requests'});
      if(!Number.isSafeInteger(quota?.used)||quota.used<0||!Number.isSafeInteger(quota.limit)||quota.limit<0||!Number.isFinite(Date.parse(quota.resetsAt)))throw new Error('Invalid AI quota response.');
      await commit(()=>owner===this.store.data.owner?this.save({quota,quotaAt:this.clock()}):undefined);
    }catch{await commit(()=>owner===this.store.data.owner?this.save({quota:null,quotaAt:this.clock()}):undefined);}
  }
  async classifyNext(commit=operation=>operation()){
    if(!this.data.enabled||!this.data.autoClassify||!this.store.data.session||!this.isPro())return;
    const owner=this.store.data.owner;
    const assignments=this.data.envelope?.assignments??[];
    // shortcut: failed or unknown classifications retry hourly, shorten only with provider idempotency.
    const id=this.data.discovered.find(id=>/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(id)&&!/(?:^|\.)(?:local|localhost|internal|test|invalid|example|lan|home|onion)$|\.home\.arpa$/.test(id)&&
      !assignments.some(a=>a.kind==='domain'&&a.id===id&&!a.isDeleted&&a.category!=='unclassified')&&this.clock()-(this.data.classificationAttempts?.[id]??0)>=3600000);
    if(!id)return;
    await commit(()=>this.save({classificationAttempts:{...this.data.classificationAttempts,[id]:this.clock()}}));
    try{
      const result=await this.client.classifyResource(id),a=result?.assignment;
      if(owner!==this.store.data.owner||!this.data.enabled||!this.data.autoClassify)return;
      if(result?.ok!==true||a?.id!==id||a.kind!=='domain'||a.source!=='automatic'||!CATEGORIES.includes(a.category))throw new Error('Automatic classification is unavailable. Choose a category manually.');
      await commit(()=>owner===this.store.data.owner&&this.data.enabled&&this.data.autoClassify?this.command('assignmentUpsert',{assignment:a}):undefined);
      await commit(()=>this.save({classificationError:''}));
    }catch(error){if(owner!==this.store.data.owner)return;await commit(()=>this.save({classificationError:error.message}));}
    if(owner===this.store.data.owner)await this.loadQuota(commit);
  }
  async coverage() {
    const hostPermission=await this.chrome.permissions.contains({origins:ORIGINS});
    return {enabled:this.data.enabled,hostPermission,isPro:this.isPro(),autoClassify:this.data.autoClassify,quota:this.data.quota,classificationError:this.data.classificationError,
      incognito:await this.chrome.extension.isAllowedIncognitoAccess(),source:this.data.source,paired:!!this.data.bridge,
      error:this.data.error||this.coverageError,discovered:this.data.discovered,expiresAt:this.data.snapshot?.expiresAt,
      exitRequestedAt:this.data.envelope?.devices?.find(d=>d.deviceId===this.store.data.deviceId)?.exitRequestedAt,
      authorityUnavailable:this.data.authorityUnavailable===true,active:this.rulesApplied===true&&this.data.enabled&&hostPermission&&!this.data.envelope?.devices?.find(d=>d.deviceId===this.store.data.deviceId)?.detached&&active(this.data.snapshot,this.clock())};
  }
  async snapshot() { return {focus:this.data.envelope,focusReadAt:this.data.readAt,protection:await this.coverage()}; }
  async detach(confirmed=false) {
    const current=await this.read({autoStart:false});
    if (!['active','paused','running'].includes(current?.session?.run?.status) || current.devices?.find(d=>d.deviceId===this.store.data.deviceId)?.detached) return;
    const result=await this.command('detach',{confirmed});
    if (result.code==='strict_exit_pending' || result.devices?.find(d=>d.deviceId===this.store.data.deviceId)?.exitRequestedAt) throw new Error('Strict exit countdown is active. Wait until it finishes before leaving this device.');
  }
  async configure(p) {
    if(p.autoClassify===true&&!this.isPro())throw new Error('Automatic categories require Pro.');
    if (p.source && !['cloud','desktop'].includes(p.source)) throw new Error('Invalid Focus source.');
    if (p.source==='desktop' && !this.data.bridge) throw new Error('Pair the desktop app first.');
    if (p.enabled===true && !await this.chrome.permissions.contains({origins:ORIGINS})) throw new Error('Allow website access to enable protection.');
    if (p.enabled===false || p.source && p.source!==this.data.source) await this.detach(p.confirmed===true);
    await this.save({...(typeof p.enabled==='boolean'?{enabled:p.enabled}:{}),...(typeof p.autoClassify==='boolean'?{autoClassify:p.autoClassify}:{}),...(p.source?{source:p.source}:{}),...(p.source?{snapshot:null,envelope:null}:{})});
    await this.reconcile();
    if (this.data.enabled) {
      await this.read();
    }
    return this.snapshot();
  }
  async bridgeRequest(path,body,bridge=this.data.bridge) {
    if (!bridge) throw new Error('Pair the desktop app first.');
    if(path!=='/pair'&&bridge.flavor!==(this.config.flavor??'production'))throw new Error('Desktop environment does not match this extension.');
    const origin=bridgeOrigin(bridge.port);
    let response;
    try { response=await fetch(`${origin}${path}`,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(bridge.token?{Authorization:`Bearer ${bridge.token}`}:{})},
      ...(body?{body:JSON.stringify(body)}:{}),credentials:'omit',redirect:'error',cache:'no-store',signal:AbortSignal.timeout(5000)}); }
    catch { throw new Error('Desktop app unavailable. Local protection expires at the last confirmed deadline.'); }
    if (!response.ok){const error=new Error(response.status===409?'Focus changed. Refresh and choose the current session.':response.status===401?'Pairing expired. Pair the desktop app again.':'Desktop Focus request failed.');error.status=response.status;throw error;}
    const text=await response.text(); if(text.length>1024*1024) throw new Error('Desktop response too large.');
    return JSON.parse(text);
  }
  async pair({port,code,confirmed}) {
    const origin=bridgeOrigin(port);
    if (typeof code!=='string' || code.length<4 || code.length>128) throw new Error('Enter the desktop pairing code.');
    if (!await this.chrome.permissions.contains({origins:[`${origin}/*`]})) throw new Error('Allow access to the desktop bridge.');
    await this.detach(confirmed===true);
    const result=await this.bridgeRequest('/pair',{code,deviceId:this.store.data.deviceId,flavor:this.config.flavor??'production'},{port});
    if (typeof result.token!=='string' || result.token.length<32 || typeof result.owner!=='string' || result.flavor!==(this.config.flavor??'production') || this.store.data.owner && result.owner!==this.store.data.owner) throw new Error('Desktop account or app environment does not match.');
    await this.save({bridge:{port:Number(port),token:result.token,owner:result.owner,flavor:result.flavor},source:'desktop',owner:result.owner,snapshot:null,envelope:null});
    await this.read(); return this.snapshot();
  }
  async accept(result,observedAt=this.clock(),autoStart=false) {
    const owner=this.data.source==='desktop'?this.data.bridge?.owner:this.store.data.owner;
    if (!owner) throw new Error('Sign in or pair the desktop app.');
    if (result.owner && result.owner!==owner) throw new Error('Focus belongs to another account.');
    const snapshot=fromEnvelope(result,owner,observedAt);
    if(snapshot && !snapshot.taskTitle && typeof this.store.data.records?.[`task:${snapshot.taskId}`]?.content==='string') snapshot.taskTitle=this.store.data.records[`task:${snapshot.taskId}`].content.slice(0,2048);
    const device=result.devices?.find(d=>d.deviceId===this.store.data.deviceId);
    if(snapshot&&device?.detached){snapshot.profile=null;snapshot.expiresAt=new Date(this.clock()).toISOString();}
    // Only the paired desktop can supply a renewed offline lease.
    if (this.data.source==='desktop' && result.protection) {
      const p=result.protection;
      if(p.version!==1 || p.owner!==owner || p.sessionId!==result.session?.id || !Number.isFinite(Date.parse(p.expiresAt))) throw new Error('Invalid desktop protection lease.');
      if(snapshot) Object.assign(snapshot,p,{expiresAt:new Date(Math.min(Date.parse(p.expiresAt),this.clock()+300000)).toISOString()});
    }
    const previous=this.observation,prior=previous?.session,i=prior?.interval,s=result.session;
    const deadline=previous?.observedAt+Date.parse(i?.startedAt)+(Number(i?.plannedSeconds)+Number(i?.pausedTotalSeconds??0))*1000-Date.parse(previous?.serverNow);
    // This observation is deliberately volatile: restoring a worker or waking
    // after a missed polling window must never backfill automatic intervals.
    this.observation={owner,source:this.data.source,session:s,serverNow:result.serverNow??s?.serverNow,observedAt};
    const shouldStart=autoStart && previous?.owner===owner && previous.source===this.data.source && prior?.id===s?.id &&
      ['active','running'].includes(prior?.run?.status) && ['active','running'].includes(s?.run?.status) &&
      i?.status==='running' && typeof i.id==='string' && typeof s?.interval?.id==='string' && i.id!==s.interval.id && s.interval.status==='ready' &&
      (s.interval.type==='work'?s.preset.autoStartWork===true:['shortBreak','longBreak'].includes(s.interval.type)&&s.preset.autoStartBreaks===true) &&
      !prior.exitRequestedAt && !s.exitRequestedAt && !device?.detached && !device?.exitRequestedAt &&
      observedAt>=previous.observedAt && observedAt-previous.observedAt<=30000 && observedAt>=deadline && observedAt-deadline<=30000 &&
      this.clock()>=observedAt && this.clock()-observedAt<=30000;
    await this.save({owner,envelope:result,snapshot,readAt:observedAt,...(device?.detached?{enabled:false}:{}),authorityUnavailable:false,error:''}); await this.reconcile();
    if(shouldStart)return this.command('startReady');
    return result;
  }
  async read({autoStart=true}={}) {
    try {
      if (this.data.source==='cloud' && !this.store.data.session) { await this.reconcile(); return null; }
      const observedAt=this.clock();
      let result=await this.accept(this.data.source==='desktop'?await this.bridgeRequest('/state'):await this.client.rpc('pomodoist_focus',{p_command:{action:'read',requestId:crypto.randomUUID(),deviceId:this.store.data.deviceId}}),observedAt,autoStart);
      if(!result.profiles.length){
        for(const name of ['Work','Study']) result=await this.command('profileUpsert',{profile:{id:name.toLowerCase(),name,blockedCategories:[],overrides:[],blockOnPause:true,blockOnShortBreak:false,blockOnLongBreak:false,updatedAt:new Date(this.clock()).toISOString()}});
      }
      return result;
    } catch(error) { this.observation=null;await this.save({error:error.message,authorityUnavailable:unavailable(error)}); await this.reconcile(); throw error; }
  }
  async command(action,payload) {
    if (!['start','startReady','changePreset','pause','resume','restart','complete','skip','requestStop','cancelStop','detach','registerDevice','profileUpsert','assignmentUpsert'].includes(action)) throw new Error('Invalid Focus command.');
    const previous=this.data.pendingCommand;
    const retry=previous && previous.source===this.data.source && previous.command.action===action && JSON.stringify(previous.command.payload)===JSON.stringify(payload);
    const command=retry?previous.command:{action,requestId:crypto.randomUUID(),deviceId:this.store.data.deviceId,expectedRevision:this.data.envelope?.session?.revision??0,...(payload?{payload}:{})};
    await this.save({pendingCommand:{source:this.data.source,command}});
    const observedAt=this.clock();
    const result=this.data.source==='desktop'?await this.bridgeRequest('/command',command):await this.client.rpc('pomodoist_focus',{p_command:command});
    await this.save({pendingCommand:null});
    if(result.code==='strict_exit_required'){await this.accept(result,observedAt);return this.command('requestStop',{confirmed:payload?.confirmed===true});}
    const successfulCode=['ok','strict_exit_pending',...(action==='assignmentUpsert'?['manual_assignment_preserved']:[])].includes(result.code);
    if(result.code && !successfulCode || result.conflict || result.error) {
      if(result.session!==undefined) await this.accept(result,observedAt,action==='complete'&&(result.code==='revision_conflict'||result.conflict));
      throw new Error(result.conflict||result.code==='revision_conflict'?'Focus changed on another device. Review the current session and retry.':result.code==='strict_confirmation_required'?'Confirm immediate strict exit.':result.code==='strict_exit_required'?'Stop strict Focus before changing this interval.':String(result.error??result.code));
    }
    return retry?this.read({autoStart:action==='complete'}):this.accept(result,observedAt,action==='complete');
  }
  async emergencyRelease(confirmed){
    if(!confirmed)throw new Error('Confirm the local emergency release.');
    let offline=false;
    try{await this.read({autoStart:false});}catch(error){if(!unavailable(error))throw error;offline=true;}
    if(!offline)throw new Error('Focus is connected. Use normal protection disable and its strict exit policy.');
    await this.save({enabled:false});await this.reconcile();
  }
  async clear() {
    this.observation=null;this.coverageReport=null;this.coverageError='';
    await this.save({enabled:false,snapshot:null,envelope:null,bridge:null,owner:null,discovered:[],pendingCommand:null,autoClassify:false,classificationAttempts:{},quota:null,classificationError:'',authorityUnavailable:false,error:''});
    await this.reconcile();
  }
  async reportCoverage(permitted,applied) {
    if(this.data.source==='cloud'&&!this.store.data.session || this.data.source==='desktop'&&!this.data.bridge) return;
    if(!this.data.enabled&&!this.data.envelope&&!this.coverageReport)return;
    const owner=this.data.source==='desktop'?this.data.bridge.owner:this.store.data.owner;
    const s=this.data.snapshot,device=this.data.envelope?.devices?.find(d=>d.deviceId===this.store.data.deviceId);
    const websiteApplied=applied&&this.data.enabled&&permitted&&!device?.detached&&active(s,this.clock());
    const payload={name:'Chrome',platform:'chrome',capabilities:{websiteBlocking:permitted,incognito:await this.chrome.extension.isAllowedIncognitoAccess(),appBlocking:false,websiteApplied},appliedRevision:websiteApplied?s.revision:null};
    const signature=JSON.stringify([owner,this.data.source,this.data.bridge?.port,this.data.envelope?.session?.id,this.data.envelope?.session?.revision,this.data.envelope?.settingsRevision,payload]);
    const previous=this.coverageReport,at=this.clock();
    if(previous?.signature===signature&&(at-previous.at<15000||!websiteApplied&&!previous.failed))return;
    this.coverageReport={signature,at,failed:false};
    try {
      // Registration is advisory metadata. Accepting its Focus envelope would
      // recursively reconcile and could renew a lease without applying it.
      const command={action:'registerDevice',requestId:crypto.randomUUID(),deviceId:this.store.data.deviceId,payload};
      const result=this.data.source==='desktop'?await this.bridgeRequest('/command',command):await this.client.rpc('pomodoist_focus',{p_command:command});
      if(!result||result.error||result.conflict||result.code&&!['ok'].includes(result.code)||!Array.isArray(result.devices)||!Number.isFinite(Date.parse(result.serverNow))||result.owner&&result.owner!==owner)throw new Error('Device coverage acknowledgement failed.');
      this.coverageError='';
    } catch(error) {this.coverageReport.failed=true;this.coverageError=error.message;}
  }
  reconcile() {
    const run=(this.reconcileTail??Promise.resolve()).catch(()=>{}).then(()=>this.applyRules());
    this.reconcileTail=run;return run;
  }
  async applyRules() {
    const permitted=await this.chrome.permissions.contains({origins:ORIGINS});
    const detached=this.data.envelope?.devices?.find(d=>d.deviceId===this.store.data.deviceId)?.detached;
    const s=this.data.enabled && permitted && !detached?this.data.snapshot:null;
    const rules=rulesFor(s,this.clock());
    if(rules.length>1000){this.rulesApplied=false;this.appliedSignature=null;await this.reportCoverage(permitted,false);throw new Error('Too many website rules. Reduce profile assignments before enabling protection.');}
    const signature=JSON.stringify([rules,this.data.enabled,permitted,s?.expiresAt]);
    if(this.appliedSignature===signature){await this.reportCoverage(permitted,this.rulesApplied===true);return;}
    this.rulesApplied=false;
    try {
    const current=await this.chrome.declarativeNetRequest.getDynamicRules();
    await this.chrome.declarativeNetRequest.updateDynamicRules({removeRuleIds:current.map(r=>r.id),addRules:rules});
    if(active(s,this.clock())) await this.chrome.alarms.create('focus-expiry',{when:Date.parse(s.expiresAt)});
    else await this.chrome.alarms.clear('focus-expiry');
    await this.chrome.scripting.unregisterContentScripts({ids:['pomodoist-guard']}).catch(()=>{});
    if(this.data.enabled && permitted) await this.chrome.scripting.registerContentScripts([{id:'pomodoist-guard',matches:ORIGINS,js:['src/guard.js'],runAt:'document_start',allFrames:true,persistAcrossSessions:true}]);
    let guardsApplied=true;
    for(const tab of await this.chrome.tabs.query({})) if(!await this.applyTab(tab,s,permitted))guardsApplied=false;
    this.rulesApplied=guardsApplied;
    this.appliedSignature=guardsApplied?signature:null;
    } catch(error) {this.appliedSignature=null;await this.reportCoverage(permitted,false);throw error;}
    await this.reportCoverage(permitted,this.rulesApplied);
  }
  async applyTab(tab,s,permitted){
    const host=domain(tab.url??'');
    if(!Number.isInteger(tab.id)||!host)return true;
    let applied=true;
    if(this.data.enabled&&permitted)await this.chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:true},files:['src/guard.js']}).catch(()=>{applied=false;});
    await this.chrome.tabs.sendMessage(tab.id,{event:'protection',blocked:blocked(s,host,this.clock()),expiresAt:s?.expiresAt??null}).catch(()=>{if(active(s,this.clock()))applied=false;});
    return applied;
  }
  async ensureTab(tabId){
    await this.reconcile();
    const permitted=await this.chrome.permissions.contains({origins:ORIGINS});
    const tab=await this.chrome.tabs.get(tabId).catch(()=>null);
    if(tab&&!await this.applyTab(tab,this.data.enabled&&permitted?this.data.snapshot:null,permitted)){this.rulesApplied=false;this.appliedSignature=null;await this.reportCoverage(permitted,false);}
  }
  async guard(host,discover=true) {
    const permitted=await this.chrome.permissions.contains({origins:ORIGINS});
    if(!active(this.data.snapshot,this.clock())) await this.reconcile();
    if(discover && this.data.enabled && permitted && host && !this.data.discovered.includes(host)) await this.save({discovered:[...this.data.discovered,host].slice(-500)});
    return {blocked:this.data.enabled&&permitted&&blocked(this.data.snapshot,host,this.clock()),expiresAt:this.data.snapshot?.expiresAt??null};
  }
}

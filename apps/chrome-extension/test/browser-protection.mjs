// Run manually with PLAYWRIGHT_MODULE pointing at an installed Playwright module.
// The test copy grants website hosts at install; shipped builds request them in the popup.
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createServer} from 'node:http';
import {build} from '../build.mjs';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'playwright');
const temp=await mkdtemp(path.join(tmpdir(),'pomodoist-protection-browser-'));
const directory=path.join(temp,'extension');
const env={SUPABASE_URL:'https://api.example.test',WEB_APP_URL:'https://tasks.example.test',SUPABASE_ANON_KEY:'sb_publishable_test',APP_ENV:'staging'};
const wav=Buffer.alloc(44144,128);wav.write('RIFF',0);wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(44100,24);wav.writeUInt32LE(44100,28);wav.writeUInt16LE(1,32);wav.writeUInt16LE(8,34);wav.write('data',36);wav.writeUInt32LE(44100,40);
const server=createServer((req,res)=>{if(req.url==='/tone.wav'){res.setHeader('Content-Type','audio/wav');res.end(wav);return;}if(req.url==='/restricted')res.setHeader('Content-Security-Policy',"default-src 'self'; frame-src 'none'; script-src 'none'");res.setHeader('Cache-Control','public,max-age=3600');res.setHeader('Content-Type','text/html');res.end('<!doctype html><title>Test page</title><form><input id="draft" value="untouched"></form><audio id="media" loop src="/tone.wav"></audio><button id="spa" onclick="history.pushState({},\'\',\'/spa?private=yes#fragment\')">SPA</button>');});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let context;
try{
  await build(env,directory);
  const manifest=JSON.parse(await readFile(path.join(directory,'manifest.json'),'utf8'));
  manifest.host_permissions.push('http://*/*','https://*/*');
  await writeFile(path.join(directory,'manifest.json'),JSON.stringify(manifest));
  const workerFile=path.join(directory,'src/background.js');
  await writeFile(workerFile,(await readFile(workerFile,'utf8'))+'\nglobalThis.__testProtection=protection;\n');
  context=await chromium.launchPersistentContext(path.join(temp,'profile'),{headless:true,...(process.env.CHROME_BIN?{executablePath:process.env.CHROME_BIN}:{}),args:[`--disable-extensions-except=${directory}`,`--load-extension=${directory}`,'--autoplay-policy=no-user-gesture-required']});
  let worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');
  const extensionId=new URL(worker.url()).host;
  const popup=await context.newPage();await popup.goto(`chrome-extension://${extensionId}/popup.html`);
  await popup.waitForFunction(()=>document.getElementById('startup').hidden);
  const pairing=popup.getByTestId('desktop-pairing-toggle');
  await pairing.evaluate(node=>{node.textContent='Desktop link';});
  await pairing.click();assert.equal(await popup.locator('#pair-code').isVisible(),true);
  await popup.locator('#protection-status').evaluate(node=>{node.textContent='Updated status copy';});
  await popup.locator('#protection-status[data-state=idle]').waitFor();
  const page=await context.newPage();const address=`http://localhost:${server.address().port}`;
  await page.goto(address+'/cached');await page.locator('#draft').fill('keep my form');
  await page.evaluate(()=>document.querySelector('audio').play());
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),false);
  const cached=await context.newPage();await cached.goto(address+'/cache-before');await cached.goto(address+'/cache-after');
  const restricted=await context.newPage();await restricted.goto(address+'/restricted');
  const expiresAt=Date.now()+12000;
  const saved={instance:env.SUPABASE_URL,owner:'owner',enabled:true,source:'cloud',envelope:null,discovered:[],bridge:null,error:'',snapshot:{
    version:1,owner:'owner',sessionId:'run',revision:1,phase:'work',status:'running',strict:false,expiresAt:new Date(expiresAt).toISOString(),remainingSeconds:12,taskTitle:'PRIVATE TASK TITLE',
    profile:{blockedCategories:['social'],overrides:[],blockOnPause:true},assignments:[{kind:'domain',id:'localhost',category:'social'}]}};
  await worker.evaluate(async saved=>{await globalThis.__testProtection.save(saved);await globalThis.__testProtection.reconcile();},saved);
  // Existing documents are shielded without navigation, including cached pages and SPA history changes.
  const overlay=page.getByTestId('blocking-overlay');
  await overlay.waitFor({state:'visible'});
  assert.equal(await overlay.evaluate(node=>node.shadowRoot),null);
  // Keep verifying behavior when a redesign changes the overlay's CSS.
  await overlay.evaluate(node=>{
    node.style.setProperty('z-index','2147483000','important');
    node.style.setProperty('background','#eef2ff','important');
  });
  await overlay.waitFor({state:'visible'});
  await page.locator('#draft').focus();await page.keyboard.type('blocked typing');
  assert.equal(await page.locator('#draft').inputValue(),'keep my form');
  assert.equal(await page.locator('audio').evaluate(a=>a.paused),true);
  assert.ok(!(await page.content()).includes('PRIVATE TASK TITLE'));
  const restrictedCdp=await context.newCDPSession(restricted);await restrictedCdp.send('Accessibility.enable');
  const tree=await restrictedCdp.send('Accessibility.getFullAXTree');assert.ok(tree.nodes.some(n=>n.name?.value==='Focus'&&!n.ignored)||restricted.frames().some(f=>f.url().startsWith(`chrome-extension://${extensionId}/blocked.html`)),'restrictive CSP retains generic shield or extension frame');
  await cached.goBack().catch(()=>{});
  await cached.waitForFunction(()=>location.protocol==='chrome-extension:'||document.querySelector('[data-testid=blocking-overlay]'));
  await page.evaluate(()=>history.pushState({},'','/spa?private=yes#fragment'));
  const fresh=await context.newPage();await fresh.goto(address+'/new').catch(()=>{});
  await fresh.waitForURL(`chrome-extension://${extensionId}/blocked.html`);
  await fresh.waitForFunction(()=>document.getElementById('task').textContent==='PRIVATE TASK TITLE');
  assert.equal(await fresh.locator('#task').textContent(),'PRIVATE TASK TITLE');
  // Kill the worker; its next activation must reload the durable lease and rules.
  const browserSession=await context.newCDPSession(page);
  await browserSession.send('ServiceWorker.enable');
  await browserSession.send('ServiceWorker.stopAllWorkers');
  await page.bringToFront();
  await overlay.waitFor({state:'detached',timeout:15000});
  assert.equal(await page.locator('#draft').inputValue(),'keep my form');
  await page.waitForTimeout(350);assert.equal(await page.locator('audio').evaluate(a=>a.paused),true);
  assert.equal(page.url(),address+'/spa?private=yes#fragment');
  await page.locator('#draft').click();await page.keyboard.press('End');await page.keyboard.type(' restored');
  assert.equal(await page.locator('#draft').inputValue(),'keep my form restored');
  // Stale DNR redirects release on the packaged page; they never redirect back into a loop.
  await fresh.reload();await fresh.waitForFunction(()=>!document.getElementById('released').hidden);
  await fresh.goto(address+'/released');assert.ok(fresh.url().startsWith(address));
  worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');
  const inventory=await worker.evaluate(async()=> (await chrome.storage.local.get('pomodoist-protection-v1'))['pomodoist-protection-v1'].discovered);
  assert.ok(inventory.includes('localhost'));assert.ok(inventory.every(h=>!h.includes('/')&&!h.includes('?')&&!h.includes('#')));
  console.log('PASS real Chromium: popup, existing/cache/SPA/form/media guard, private iframe, DNR redirect, worker stop, offline expiry, release without navigation/autoplay, hostname-only discovery.');
}finally{await context?.close();await new Promise(r=>server.close(r));await rm(temp,{recursive:true,force:true});}

// Isolated world: task/account data never crosses into the site's DOM.
(() => {
  if (globalThis.__pomodoistGuard) { globalThis.__pomodoistGuard.check(); return; }
  let lease=null,shield=null,frameRef=null,fallback=null;
  const pause=()=>{ for(const media of document.querySelectorAll('audio,video')) { try { media.pause(); } catch {} } };
  function release() { shield?.remove(); shield=null;frameRef=null;fallback=null;lease=null; }
  function apply(value) {
    if(!value?.blocked || Date.parse(value.expiresAt)<=Date.now()) { release(); return; }
    lease=value.expiresAt;
    if(window.top===window && !shield && document.documentElement) {
      shield=document.createElement('div');
      shield.setAttribute('data-testid','blocking-overlay');
      shield.style.cssText='position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:2147483647!important;display:block!important;';
      const shadow=shield.attachShadow({mode:'closed'}),frame=document.createElement('iframe');
      fallback=document.createElement('div');fallback.style.cssText='position:absolute;inset:0;display:grid;place-content:center;text-align:center;background:#211d1c;color:#f3edeb;font:20px system-ui;';
      const label=document.createElement('p');label.textContent=chrome.i18n.getMessage('focus')||'Focus';
      const back=document.createElement('button');back.textContent=chrome.i18n.getMessage('open_app')||'Open app';back.style.cssText='font:16px system-ui;padding:12px;cursor:pointer;';
      back.addEventListener('click',()=>chrome.runtime.sendMessage({type:'returnToTask'}).catch(()=>{}));fallback.append(label,back);
      frameRef=frame;
      frame.src=chrome.runtime.getURL('blocked.html?guard=1'); frame.title='Pomodoist Focus';
      frame.style.cssText='position:absolute;inset:0;width:100%;height:100%;border:0;background:#111;display:none;';
      shadow.append(fallback,frame); document.documentElement.append(shield);
    }
    pause();
  }
  async function check() { try { const r=await chrome.runtime.sendMessage({type:'guard'}); if(r?.ok) apply(r.value); } catch { if(lease && Date.parse(lease)<=Date.now()) release(); } }
  globalThis.__pomodoistGuard={check};
  window.addEventListener('message',e=>{if(frameRef && e.source===frameRef.contentWindow && e.data?.event==='pomodoist-block-ready'){frameRef.style.display='block';fallback?.remove();fallback=null;}});
  chrome.runtime.onMessage.addListener((m,sender)=>{if(sender.id===chrome.runtime.id && m?.event==='protection') apply(m);});
  for(const event of ['keydown','keyup','keypress']) window.addEventListener(event,e=>{if(lease){e.preventDefault();e.stopImmediatePropagation();}},true);
  document.addEventListener('play',()=>{if(lease) pause();},true);
  document.addEventListener('visibilitychange',check);
  window.addEventListener('pageshow',check);
  window.addEventListener('popstate',check);
  setInterval(()=>{if(lease && Date.parse(lease)<=Date.now()) release(); else if(lease){if(shield&&!shield.isConnected) document.documentElement?.append(shield);pause();}},250);
  setInterval(check,15000);
  check();
})();

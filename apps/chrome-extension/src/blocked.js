import {localize,text} from './i18n.js';
localize(document);
if(window.parent!==window)window.parent.postMessage({event:'pomodoist-block-ready'},'*');
let expiresAt=null,status=null,remainingSeconds=0,readAt=Date.now();
const $=id=>document.getElementById(id);
function paint(){
  const left=status==='paused'?remainingSeconds:Math.max(0,remainingSeconds-Math.floor((Date.now()-readAt)/1000));
  const released=!expiresAt || Date.parse(expiresAt)<=Date.now();
  $('released').hidden=!released;
  $('remaining').textContent=released?'':`${Math.floor(left/60)}:${String(left%60).padStart(2,'0')}${status==='paused'?' · '+text('Pause'):''}`;
  if(released) $('task').textContent=text('Return to your task.');
}
async function refresh(){
  try {const r=await chrome.runtime.sendMessage({type:'blockState'});if(!r?.ok)return;
    expiresAt=r.value.expiresAt;status=r.value.status;remainingSeconds=r.value.remainingSeconds??0;readAt=Date.now();
    $('task').textContent=r.value.taskTitle||text('Return to your task.');paint();
  }catch{paint();}
}
$('return').addEventListener('click',()=>chrome.runtime.sendMessage({type:'returnToTask'}).catch(()=>{}));
setInterval(paint,1000);setInterval(refresh,15000);refresh();

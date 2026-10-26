// Presets start the common Focus session; the server owns transitions and history.
export const PRESETS=[15,5,25,50];
export function preset(minutes,strictMode=false){
  if(!PRESETS.includes(minutes))throw new Error('Choose a timer length');
  return {id:'classic',name:`${minutes} minutes`,workSeconds:minutes*60,shortBreakSeconds:300,longBreakSeconds:900,
    intervalsBeforeLongBreak:4,autoStartBreaks:false,autoStartWork:false,allowPause:true,strictMode};
}
export function timerView(envelope,readAt,now=Date.now(),minutes=25){
  const s=envelope?.session,i=s?.interval;
  if(!s||!i||!['active','paused','running'].includes(s.run?.status))return {phase:'work',status:'ended',remaining:minutes*60,total:minutes*60};
  const serverNow=Date.parse(envelope.serverNow??s.serverNow),current=serverNow+Math.max(0,now-readAt);
  const clock=i.status==='paused'?Date.parse(i.pausedAt):current;
  const elapsed=Math.max(0,(clock-Date.parse(i.startedAt))/1000-(Number(i.pausedTotalSeconds)||0));
  const remaining=i.status==='ready'?i.plannedSeconds:Math.max(0,Math.ceil(i.plannedSeconds-elapsed));
  return {phase:i.type,status:i.status,remaining:Number.isFinite(remaining)?remaining:0,total:i.plannedSeconds,exitRequestedAt:s.exitRequestedAt,strict:s.preset?.strictMode===true};
}

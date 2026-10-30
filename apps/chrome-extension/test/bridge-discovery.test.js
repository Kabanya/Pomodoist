import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac} from 'node:crypto';
import * as bridge from '../src/protection.js';

const token='a-secure-paired-token-at-least-32-characters';
function fixture(extra={}) {
  const writes=[];
  const chrome={storage:{local:{set:async v=>writes.push(v)}},permissions:{contains:async()=>true}};
  const p=new bridge.FocusProtection(chrome,{data:{owner:'owner',deviceId:'browser'}},{},{apiUrl:'https://api.test',flavor:'development'});
  p.data.source='desktop';p.data.owner='owner';
  p.data.bridge={port:51989,token,owner:'owner',flavor:'development',discoveryVersion:1,...extra};
  return {p,writes};
}
function proof(port,body,extra={}) {
  const value={version:1,owner:'owner',flavor:'development',port,...extra};
  value.proof=createHmac('sha256',token).update(JSON.stringify(['pomodoist-bridge-discovery-v1',body.challenge,value.owner,value.flavor,value.port])).digest('hex');
  return value;
}
const json=(body,status=200)=>new Response(JSON.stringify(body),{status});
function network(t,handler) {
  const original=globalThis.fetch;
  globalThis.fetch=handler;t.after(()=>{globalThis.fetch=original;});
}

test('port candidates are disjoint and port-prefixed codes need no port entry',()=>{
  const lists=['production','staging','development'].map(flavor=>bridge.bridgePorts(flavor));
  assert.deepEqual(lists[2],Array.from({length:64},(_,i)=>51989+3*i));
  assert.equal(new Set(lists.flat()).size,192);
  assert.deepEqual(bridge.pairingDetails(' 52001-123456 ',51989,'development'),{port:52001,code:'52001-123456'});
  assert.deepEqual(bridge.pairingDetails('123456',52001,'development'),{port:52001,code:'123456'});
  assert.deepEqual(bridge.pairingDetails('123456','','development'),{port:51989,code:'123456'});
  assert.throws(()=>bridge.pairingDetails('65536-123456','','development'));
});

test('moved desktop is authenticated without disclosing its token and concurrent requests share discovery',async t=>{
  const {p}=fixture();const calls=[];let active=0,max=0;
  network(t,async(url,options)=>{
    const port=Number(new URL(url).port),body=JSON.parse(options.body);
    calls.push({port,path:new URL(url).pathname,body,headers:options.headers});
    if(url.endsWith('/discover')){
      assert.equal(options.headers.Authorization,undefined);
      assert.equal(body.clientId,createHash('sha256').update(token).digest('hex'));
      assert.ok(!JSON.stringify(body).includes(token));
      active++;max=Math.max(max,active);await new Promise(resolve=>setImmediate(resolve));active--;
      if(port===52001)return json(proof(port,body));
      throw new TypeError('connection refused');
    }
    assert.equal(port,52001);assert.equal(options.headers.Authorization,`Bearer ${token}`);
    return json({ok:true});
  });
  const command={action:'pause',requestId:'same-request'};
  await Promise.all([p.bridgeRequest('/command',command),p.bridgeRequest('/command',command)]);
  assert.equal(p.data.bridge.port,52001);
  assert.equal(p.data.bridge.discoveryVersion,1);
  assert.ok(max<=8);
  assert.equal(calls.filter(c=>c.path==='/discover'&&c.port===51989).length,1);
  assert.equal(calls.filter(c=>c.path==='/command').length,2);
  assert.ok(calls.filter(c=>c.path==='/command').every(c=>c.body.requestId==='same-request'));
});

for(const invalid of ['proof','owner','flavor','port','replay'])test(`discovery rejects ${invalid} without sending credentials or changing authority`,async t=>{
  const {p}=fixture();let previous;
  network(t,async(url,options)=>{
    assert.ok(url.endsWith('/discover'),'must not send commands to an unverified server');
    assert.equal(options.headers.Authorization,undefined);
    const port=Number(new URL(url).port),body=JSON.parse(options.body);
    if(invalid==='replay'){
      previous??=proof(port,{...body,challenge:'old-challenge'});return json(previous);
    }
    const extra=invalid==='owner'?{owner:'another'}:invalid==='flavor'?{flavor:'production'}:invalid==='port'?{port:port+1}:{};
    const response=proof(port,body,extra);if(invalid==='proof')response.proof='0'.repeat(64);
    return json(response);
  });
  await assert.rejects(p.bridgeRequest('/command',{action:'read'}),/Desktop app unavailable/);
  assert.equal(p.data.bridge.port,51989);assert.equal(p.data.source,'desktop');
});

test('existing legacy pairing uses only its saved port and is not probed with a bearer',async t=>{
  const {p}=fixture({discoveryVersion:undefined});const paths=[];
  network(t,async(url,options)=>{
    paths.push(new URL(url).pathname);
    assert.equal(Number(new URL(url).port),51989);
    if(url.endsWith('/discover')){assert.equal(options.headers.Authorization,undefined);return json({error:'unpaired'},401);}
    assert.equal(options.headers.Authorization,`Bearer ${token}`);return json({legacy:true});
  });
  assert.deepEqual(await p.bridgeRequest('/command',{action:'read'}),{legacy:true});
  assert.deepEqual(paths,['/discover','/command']);
});

test('port-prefixed pairing persists discovery support',async t=>{
  const {p}=fixture();p.detach=async()=>{};p.read=async()=>{};p.snapshot=async()=>p.data;
  network(t,async(url,options)=>{
    assert.equal(url,'http://127.0.0.1:52001/pair');
    assert.equal(options.headers.Authorization,undefined);
    assert.equal(JSON.parse(options.body).code,'52001-123456');
    return json({token,owner:'owner',flavor:'development',discoveryVersion:1});
  });
  await p.pair({code:'52001-123456'});
  assert.equal(p.data.bridge.port,52001);assert.equal(p.data.bridge.discoveryVersion,1);
});

test('logout during discovery cannot restore pairing or send a command',async t=>{
  const {p}=fixture();
  network(t,async(url,options)=>{
    assert.ok(url.endsWith('/discover'));
    const body=JSON.parse(options.body);p.data.bridge=null;
    return json(proof(Number(new URL(url).port),body));
  });
  await assert.rejects(p.bridgeRequest('/command',{action:'pause'}));
  assert.equal(p.data.bridge,null);
});

for (const status of [401,403,404]) test(`modern pairing never downgrades on discovery HTTP ${status}`,async t=>{
  const {p}=fixture();
  network(t,async(url,options)=>{
    assert.ok(url.endsWith('/discover'));
    assert.equal(options.headers.Authorization,undefined);
    return json({error:'unpaired'},status);
  });
  await assert.rejects(p.bridgeRequest('/command',{action:'read'}),/Desktop app unavailable/);
  assert.equal(p.data.bridge.discoveryVersion,1);
});

test('a lost command response reconnects with the original request ID',async t=>{
  const {p}=fixture();let moved=false;const commands=[];
  network(t,async(url,options)=>{
    const port=Number(new URL(url).port),body=JSON.parse(options.body);
    if(url.endsWith('/discover')) {
      if(port===(moved?51992:51989))return json(proof(port,body));
      throw new TypeError('refused');
    }
    commands.push({port,body});
    if(!moved){moved=true;throw new TypeError('response lost after commit');}
    return json({ok:true});
  });
  const command={action:'pause',requestId:'durable-id',expectedRevision:7};
  assert.deepEqual(await p.bridgeRequest('/command',command),{ok:true});
  assert.deepEqual(commands,[{port:51989,body:command},{port:51992,body:command}]);
});

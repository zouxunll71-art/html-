import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(new URL('../engine/Web/preview.js',import.meta.url),'utf8');
const helpers=source.slice(source.indexOf('function previewPerformanceMark('),source.indexOf('function api('));
function environment(){
 let now=10,wall=1000,reads=0,nextTimer=0;
 const messages=[],timers=new Map();
 const context=vm.createContext({performance:{get timeOrigin(){return 100},now:()=>{reads++;return now}},Date:{now:()=>wall},document:{},window:{webkit:{messageHandlers:{studio:{postMessage:value=>messages.push(value)}}}},setTimeout:callback=>{timers.set(++nextTimer,callback);return nextTimer},clearTimeout:id=>timers.delete(id),payload:null});
 vm.runInContext(helpers,context);
 return {context,messages,timers,move(value){now=value},wall(value){wall=value},reads:()=>reads};
}
function image({src='asset.png',complete=true,width=10}={}){
 const target=new EventTarget();
 Object.assign(target,{currentSrc:src,complete,naturalWidth:width,getAttribute:name=>name==='src'?src:null});
 Object.defineProperty(target,'decode',{get(){throw Error('diagnostics must not force image decoding')}});
 return target;
}

test('opt-in phase durations use a monotonic clock and preserve independent snapshots',()=>{
 const env=environment();
 env.context.previewPerformanceMark(null,'ignored');assert.equal(env.reads(),0);
 const probe={};env.context.previewPerformanceMark(probe,'emit');env.wall(-5000);env.move(35);env.context.previewPerformanceMark(probe,'response');
 assert.equal(probe.monotonic.phases.response,25);
 const snapshot=env.context.previewPerformanceSnapshot(probe);env.move(40);env.context.previewPerformanceMark(probe,'render');
 assert.equal(snapshot.phases.render,undefined);assert.equal(snapshot.clock,'performance.now');
});

test('ordinary events have no trace header; opt-in events correlate the same eventID without exposing payload',async()=>{
 const env=environment(),requests=[];
 Object.assign(env.context,{TOKEN:'test-token',crypto:{randomUUID:()=>`event-${requests.length}`},fetch:async(path,options)=>{requests.push({path,...options});return {ok:true,json:async()=>({runtime:{revision:1}})}},acceptRuntime:()=>true,poll:()=>{throw Error('unexpected fallback')},error:{style:{}}});
 vm.runInContext("let sending=Promise.resolve(),legacyPending=0;payload={projectID:'project',page:{id:'home'},modelHash:'hash'};"+source.slice(source.indexOf('function api('),source.indexOf('function render(')),env.context);
 env.context.emit({node:'go.profile'});await vm.runInContext('sending',env.context);
 assert.equal(requests[0].headers['X-Studio-Trace-ID'],undefined);
 const probe={tag:'studio-perf:run:project:1',start:1000,route:'home'};env.context.window.__studioPerformance=probe;
 env.context.emit({node:'go.characters'});await vm.runInContext('sending',env.context);
 assert.equal(requests[1].headers['X-Studio-Trace-ID'],probe.tag);assert.equal(JSON.parse(requests[1].body).eventID,probe.eventID);
 assert.deepEqual(Object.keys(probe.monotonic.phases),['emit','request','response']);
 const tracedEvent=probe.eventID;env.context.emit({node:'unrelated-event'});await vm.runInContext('sending',env.context);
 assert.equal(probe.eventID,tracedEvent);assert.equal(probe.concurrentEvents,1);assert.equal(requests[2].headers['X-Studio-Trace-ID'],undefined);
 for(const tag of ['bad\nheader','含中文','a'.repeat(161)])assert.equal(env.context.previewPerformanceTraceID({tag}),undefined);
});

test('resource observation waits for pending native symbols and never forces decoding',async()=>{
 const env=environment(),p={projectID:'project',revision:2,page:{id:'profile'}},probe={tag:'probe',traceID:'probe',eventID:'event'};
 env.context.payload=p;env.context.previewPerformanceMark(probe,'renderComplete');
 const ready=image(),symbol=image({src:'',complete:true,width:0});let fontsResolve;const fonts={status:'loading',ready:new Promise(resolve=>fontsResolve=resolve)};
 env.context.previewPerformanceResources(probe,p,[ready,symbol],fonts);
 fonts.status='loaded';fontsResolve();await new Promise(resolve=>setImmediate(resolve));assert.equal(env.messages.length,0);
 symbol.naturalWidth=22;symbol.currentSrc='data:image/png;base64,symbol';env.move(27);symbol.dispatchEvent(new Event('load'));
 assert.equal(env.messages.length,1);const report=env.messages[0];
 assert.equal(report.tag,'probe:resources');assert.equal(report.parentTag,'probe');assert.equal(report.eventID,'event');
 assert.equal(report.images.loaded,2);assert.equal(report.images.pending,0);assert.equal(report.fonts.status,'ready');
 assert.equal(report.imageDecodeObserved,false);assert.equal(report.visibleFrameVerified,false);assert.equal(report.inputToContentFrameMs,undefined);
 assert.equal(report.monotonic.phases.imagesReady,17);assert.equal(report.stale,false);assert.equal(env.timers.size,0);
});

test('failed or timed-out resources are reported separately without claiming readiness or retaining listeners',()=>{
 const env=environment(),p={projectID:'project',revision:1,page:{id:'home'}},probe={tag:'probe'};
 env.context.payload=p;env.context.previewPerformanceMark(probe,'renderComplete');
 const broken=image({complete:true,width:0}),pending=image({src:'',complete:false,width:0});
 env.context.previewPerformanceResources(probe,p,[broken,pending],null);
 env.context.payload={...p,revision:2};env.move(5020);for(const callback of [...env.timers.values()])callback();
 assert.equal(env.messages.length,1);const report=env.messages[0];
 assert.equal(report.images.failed,1);assert.equal(report.images.pending,1);assert.equal(report.timedOut,true);assert.equal(report.stale,true);assert.equal(report.monotonic.phases.imagesReady,undefined);
 pending.naturalWidth=20;pending.dispatchEvent(new Event('load'));assert.equal(env.messages.length,1);assert.equal(env.timers.size,0);
});

test('the historical metric still ends at the second rAF and is explicitly not a presentation measurement',()=>{
 const env=environment(),frames=[];
 const probe={tag:'probe',traceID:'probe',eventID:'event',route:'home',start:900,emitAt:910,requestAt:912,responseAt:950,renderAt:950};
 env.context.previewPerformanceMark(probe,'emit');
 Object.assign(env.context,{probe,page:{id:'profile'},p:{projectID:'project',revision:3},requestAnimationFrame:callback=>frames.push(callback)});
 const measurement=source.slice(source.indexOf('if(probe&&probe.route!==page.id){window.__studioPerformance=null'),source.indexOf('\nrenderNativeChrome(p,page);'));
 vm.runInContext(measurement,env.context);assert.equal(env.messages.length,0);
 env.wall(1020);env.move(30);frames.shift()();assert.equal(env.messages.length,0);
 env.wall(1130);env.move(140);frames.shift()();const report=env.messages[0];
 assert.equal(report.inputToContentFrameMs,230);assert.equal(report.phases.raf,120);
 assert.equal(report.metric,'synthetic-input-to-second-raf');assert.equal(report.visibleFrameVerified,false);
 assert.equal(report.monotonic.phases.secondRAF-report.monotonic.phases.firstRAF,110);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { chromium } from 'playwright';
import {PNG} from 'pngjs';
import {compare,improves} from '../metrics.mjs';
import {run,cssFor,validate,inside} from '../calibrate.mjs';
const channel=process.env.CALIBRATION_BROWSER_CHANNEL||undefined;
async function fixture(t,{brokenResource=false,brokenLink=false,nested=false}={}){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'pixel-calibration-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));await fs.mkdir(path.join(root,'qa'));
 let html=`<!doctype html><html><head><link rel="icon" href="data:,"><link rel="stylesheet" href="${brokenLink?'other.css':'layout.css'}"><style>html,body{margin:0;background:#faf8f0}#card{position:absolute;width:72px;height:34px;border:0;background:#235bde;color:white;font:12px sans-serif}#label{position:absolute;left:10px;top:95px;font:14px sans-serif}#input{position:absolute;left:10px;top:125px;width:100px}</style></head><body><button id="card" onclick="document.querySelector('#label').textContent='Saved'">Save</button><div id="label">Ready</div><input id="input"></body></html>`;
 if(nested)html=html.replace('<button id=','<section style="position:absolute;left:5px;top:3px"><button id=').replace('</button>','</button></section>');
 await fs.writeFile(path.join(root,'index.html'),html);
 const parameters=[{id:'card.x',selector:'#card',property:'left',initial:29,min:10,max:35,step:1},{id:'card.y',selector:'#card',property:'top',initial:43,min:20,max:50,step:1}];
 const target=cssFor(parameters,{'card.x':21,'card.y':36});
 await fs.writeFile(path.join(root,'layout.css'),target);
 if(brokenLink)await fs.writeFile(path.join(root,'other.css'),target);
 const browser=await chromium.launch({headless:true,args:['--disable-gpu','--force-color-profile=srgb'],...(channel?{channel}:{})});
 try{
  const page=await browser.newPage({viewport:{width:160,height:190},deviceScaleFactor:1,colorScheme:'light',locale:'en-US',timezoneId:'UTC',reducedMotion:'reduce'});
  await page.goto('file://'+path.join(root,'index.html'));await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:path.join(root,'qa/reference.png'),animations:'disabled',caret:'hide'});
 }finally{await browser.close();}
 const initial=cssFor(parameters,Object.fromEntries(parameters.map(p=>[p.id,p.initial])));
 await fs.writeFile(path.join(root,'layout.css'),initial);
 if(brokenLink)await fs.writeFile(path.join(root,'other.css'),initial);
 if(brokenResource)await fs.writeFile(path.join(root,'index.html'),html.replace('#235bde','#de235b'));
 const config={root:'.',reference:'qa/reference.png',referenceSHA256:crypto.createHash('sha256').update(await fs.readFile(path.join(root,'qa/reference.png'))).digest('hex'),entry:'index.html',stylesheet:'layout.css',viewport:{width:160,height:190},channel,maxEvaluations:90,maxPasses:2,parameters,regions:[{id:'button',x:0,y:0,width:130,height:90},{id:'text',x:0,y:90,width:160,height:100}],interactions:[{type:'click',selector:'#card',expect:{selector:'#label',text:'Saved'}},{type:'fill',selector:'#input',value:'Clay',expect:{value:'Clay'}}]};
 const file=path.join(root,'calibration.json');await fs.writeFile(file,JSON.stringify(config));
 return {root,config,file,initial};
}
test('raw pixel comparison detects alpha, dimensions and protected-region regression',()=>{
 const a=new PNG({width:2,height:2}),b=new PNG({width:2,height:2});a.data.fill(255);b.data.fill(255);b.data[3]=0;
 assert.equal(compare(a,b).full.changed,1);
 assert.throws(()=>compare(a,new PNG({width:3,height:2})),/dimensions/);
 assert.equal(improves({full:{error:10},regions:{text:{error:2}}},{full:{error:20},regions:{text:{error:0}}}),false);
});
test('bounds and workspace escape are rejected',async t=>{
 const {root,config}=await fixture(t);
 assert.throws(()=>validate({...config,parameters:[{...config.parameters[0],property:'display'}]}),/Unsupported/);
 assert.throws(()=>validate({...config,parameters:[{...config.parameters[0],step:0}]}),/bounds/);
 await fs.symlink(os.tmpdir(),path.join(root,'outside'));
 await assert.rejects(inside(root,'outside'),/outside workspace/);
});
test('browser calibration reaches zero pixels, applies real CSS, and preserves clicking/typing',async t=>{
 const {file,root}=await fixture(t);
 const {report,output}=await run(file,{apply:true});
 assert.equal(report.status,'passed');assert.equal(report.scope,'persisted-source');assert.equal(report.after.full.changed,0);assert.equal(report.interactionStatus,'passed');
 assert.ok(report.trials.some(t=>!t.accepted),'must reject a worse trial');
 assert.equal(report.values['card.x'],21);assert.equal(report.values['card.y'],36);
 assert.ok((await fs.stat(path.join(output,'difference.png'))).size);
 assert.match(await fs.readFile(path.join(root,'layout.css'),'utf8'),/21px/);
 const verified=await run(file,{verifyOnly:true});assert.equal(verified.report.status,'passed');
});
test('wrong resource color remains failed and never becomes a false zero-difference pass',async t=>{
 const {file,root,initial}=await fixture(t,{brokenResource:true});
 const {report}=await run(file,{apply:true});
 assert.equal(report.applied,false);assert.ok(report.applySkipped);
 assert.equal(report.status,'unmatched');assert.equal(report.visualStatus,'failed');assert.ok(report.after.full.changed>0);
 assert.equal(await fs.readFile(path.join(root,'layout.css'),'utf8'),initial);
});
test('unconnected output stylesheet rolls back instead of claiming source was calibrated',async t=>{
 const {file,root,initial}=await fixture(t,{brokenLink:true});
 await assert.rejects(run(file,{apply:true}),/does not reproduce/);
 assert.equal(await fs.readFile(path.join(root,'layout.css'),'utf8'),initial);
});
test('dimension and hash mismatch fail before optimization',async t=>{
 const {file,config}=await fixture(t);
 await fs.writeFile(file,JSON.stringify({...config,viewport:{width:161,height:190}}));await assert.rejects(run(file),/does not match/);
 await fs.writeFile(file,JSON.stringify({...config,referenceSHA256:'0'.repeat(64)}));await assert.rejects(run(file),/hash changed/);
});

test('nested local coordinates converge without moving independent text or breaking actions',async t=>{
 const {file}=await fixture(t,{nested:true});
 const {report}=await run(file,{apply:true});
 assert.equal(report.status,'passed');assert.equal(report.after.full.changed,0);
 assert.ok(report.trials.every(trial=>!trial.accepted||trial.metrics.regions.text.error===0));
});
test('unstable canvas stops calibration and preserves source',async t=>{
 const {file,root,initial}=await fixture(t);
 const html=await fs.readFile(path.join(root,'index.html'),'utf8');
 await fs.writeFile(path.join(root,'index.html'),html+'<canvas id="noise" width="160" height="190" style="position:fixed;inset:0;pointer-events:none"></canvas><script>const ctx=document.querySelector("#noise").getContext("2d");function tick(){ctx.fillStyle=`rgb(${Math.floor(Math.random()*255)},0,0)`;ctx.fillRect(0,0,160,190);requestAnimationFrame(tick)}tick()</script>');
 await assert.rejects(run(file,{apply:true}),/Unstable/);
 assert.equal(await fs.readFile(path.join(root,'layout.css'),'utf8'),initial);
});
test('reference image cannot be secretly loaded into the page',async t=>{
 const {file,root}=await fixture(t);
 const html=await fs.readFile(path.join(root,'index.html'),'utf8');
 await fs.writeFile(path.join(root,'index.html'),html+'<img src="qa/reference.png">');
 await assert.rejects(run(file),/decode|EncodingError|Page errors/);
});

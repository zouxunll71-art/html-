import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { chromium } from 'playwright';
import { decode, encode, compare, improves, visuals } from './metrics.mjs';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const properties=new Set(['left','top','width','height','font-size','line-height','letter-spacing','border-radius','padding-left','padding-top','padding-right','padding-bottom','margin-left','margin-top']);
export async function inside(root, name) {
  if(typeof name!=='string'||!name)throw Error('Missing relative path');
  const result=await fs.realpath(path.resolve(root,name));
  if(result!==root&&!result.startsWith(root+path.sep))throw Error(`Path outside workspace: ${name}`);
  return result;
}
export function validate(config) {
  const {viewport,parameters=[],regions=[]}=config;
  if(!viewport||!Number.isInteger(viewport.width)||!Number.isInteger(viewport.height)||viewport.width<1||viewport.height<1||viewport.width>4096||viewport.height>4096)throw Error('Invalid viewport');
  if(!Number.isFinite(config.deviceScaleFactor??1)||(config.deviceScaleFactor??1)<1||(config.deviceScaleFactor??1)>4)throw Error('Invalid deviceScaleFactor');
  if(viewport.width*viewport.height*(config.deviceScaleFactor??1)**2>20000000)throw Error('Capture exceeds pixel budget');
  if(!/^[a-f0-9]{64}$/.test(config.referenceSHA256||''))throw Error('Lock referenceSHA256 before calibration');
  if(!Array.isArray(parameters)||parameters.length>100)throw Error('Too many parameters');
  const ids=new Set(), bindings=new Set();
  for(const p of parameters){
    if(!/^[A-Za-z0-9_.-]+$/.test(p.id)||ids.has(p.id))throw Error('Duplicate or invalid parameter id');ids.add(p.id);
    // Simple stable IDs only: never arbitrary selectors or CSS text injection.
    if(!/^#[A-Za-z_][A-Za-z0-9_-]*$/.test(p.selector)||!properties.has(p.property))throw Error(`Unsupported binding: ${p.id}`);
    const key=p.selector+':'+p.property;if(bindings.has(key))throw Error('Duplicate CSS binding');bindings.add(key);
    if(![p.initial,p.min,p.max,p.step].every(Number.isFinite)||p.step<=0||p.min>p.initial||p.max<p.initial||(p.max-p.min)/p.step>1000)throw Error(`Invalid parameter bounds: ${p.id}`);
    if(!['left','top','letter-spacing','margin-left','margin-top'].includes(p.property)&&p.min<0)throw Error('Negative size not allowed');
    if(['width','height','font-size','line-height'].includes(p.property)&&p.min<=0)throw Error('Zero-size hiding is not a calibration parameter');
  }
  if(!Array.isArray(regions)||new Set(regions.map(r=>r.id)).size!==regions.length||regions.some(r=>!r.id||['__proto__','constructor','prototype'].includes(r.id)))throw Error('Invalid region ids');
  for(const key of ['maxEvaluations','maxPasses'])if(config[key]!==undefined&&(!Number.isInteger(config[key])||config[key]<1||config[key]>(key==='maxEvaluations'?2000:20)))throw Error(`Invalid ${key}`);
  return config;
}
export function cssFor(parameters,values){return '/* Generated numeric calibration. No reference image dependencies. */\n'+parameters.map(p=>`${p.selector} { ${p.property}: ${values[p.id]}px !important; }`).join('\n')+'\n';}
async function serve(root, blocked) {
  const server=http.createServer(async(req,res)=>{
    try {
      if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405);res.end();return;}
      const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';
      const file=await inside(root,name);
      if(blocked.has(file)||name.split('/').includes('.git')){res.writeHead(403);res.end();return;}
      const bytes=await fs.readFile(file);
      const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.json':'application/json','.woff2':'font/woff2','.ttf':'font/ttf'};
      res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(req.method==='HEAD'?undefined:bytes);
    }catch{res.writeHead(404);res.end();}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return {origin:`http://127.0.0.1:${server.address().port}`,close:()=>new Promise(resolve=>server.close(resolve))};
}
export async function run(configFile,{apply=false,verifyOnly=false}={}){
  const config=validate(JSON.parse(await fs.readFile(configFile,'utf8')));
  const base=path.dirname(path.resolve(configFile));
  const root=await fs.realpath(path.resolve(base,config.root||'.'));
  const referencePath=await inside(root,config.reference),referenceBytes=await fs.readFile(referencePath);
  if(hash(referenceBytes)!==config.referenceSHA256)throw Error('Reference hash changed; refusing calibration');
  const reference=decode(referenceBytes),dpr=config.deviceScaleFactor??1;
  if(reference.width!==config.viewport.width*dpr||reference.height!==config.viewport.height*dpr)throw Error(`Reference ${reference.width}x${reference.height} does not match viewport × DPR`);
  compare(reference,reference,config.regions||[]);
  const entry=await inside(root,config.entry),stylesheet=await inside(root,config.stylesheet);
  if(path.extname(entry)!=='.html'||path.extname(stylesheet)!=='.css')throw Error('Explicit HTML entry and existing CSS target required');
  if([referencePath,entry].includes(stylesheet))throw Error('Invalid stylesheet target');
  const sourceBytes=await fs.readFile(stylesheet),parameters=config.parameters||[];
  if(apply&&sourceBytes.length&&!sourceBytes.toString().startsWith('/* Generated numeric calibration. No reference image dependencies. */'))throw Error('Apply target must be an empty or dedicated generated calibration stylesheet');
  const initial=Object.fromEntries(parameters.map(p=>[p.id,p.initial]));
  const outputParent=await inside(root,config.outputParent||'qa');
  const output=await fs.mkdtemp(path.join(outputParent,'calibration-'));
  const report={version:1,status:'running',referenceSHA256:hash(referenceBytes),referencePixels:{width:reference.width,height:reference.height},initialValues:initial,applied:false,interactionStatus:'not-tested',trials:[],environment:{viewport:config.viewport,deviceScaleFactor:dpr,platform:process.platform,locale:config.locale||'en-US',timezone:'UTC',colorScheme:'light',browser:'chromium',channel:config.channel||'bundled'}};
  let browser,server,context,page,baselineInteraction;
  const errors=new Set();
  let sourceWritten=false;
  const persist=()=>fs.writeFile(path.join(output,'report.json'),JSON.stringify(report,null,2));
  try{
    // Reference is not available to the rendered page, even if a project links it.
    server=await serve(root,new Set([referencePath]));
    browser=await chromium.launch({headless:true,args:['--disable-gpu','--force-color-profile=srgb'],...(config.channel?{channel:config.channel}:{})});
    report.environment.browserVersion=browser.version();
    report.environment.launchArguments=['--disable-gpu','--force-color-profile=srgb'];
    context=await browser.newContext({viewport:config.viewport,deviceScaleFactor:dpr,locale:report.environment.locale,timezoneId:'UTC',colorScheme:'light',reducedMotion:'reduce',serviceWorkers:'block'});
    await context.route('**/*',async route=>{
      const req=route.request(),url=new URL(req.url());
      if((url.origin!==server.origin&&!['data:','blob:'].includes(url.protocol))||!['GET','HEAD'].includes(req.method())){errors.add('Blocked nonlocal or mutating request');await route.abort();return;}
      await route.continue();
    });
    page=await context.newPage();
    page.on('pageerror',e=>errors.add(e.message));
    page.on('console',m=>{if(m.type()==='error')errors.add(m.text());});
    page.on('response',r=>{if(r.status()>=400)errors.add(`HTTP ${r.status()}: ${new URL(r.url()).pathname}`);});
    const url=server.origin+'/'+path.relative(root,entry).split(path.sep).map(encodeURIComponent).join('/')+(config.hash||'');
    if(config.hash&&!/^#[^\s]*$/.test(config.hash))throw Error('Invalid route hash');
    const ready=async()=>{
      await page.goto(url,{waitUntil:'load'});
      if(config.readySelector)await page.locator(config.readySelector).waitFor({state:'visible',timeout:10000});
      await page.evaluate(async()=>{
        await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
        await document.fonts.ready;
        await Promise.all([...document.images].filter(img=>img.checkVisibility()).map(async img=>{
          try{await img.decode();}catch{throw Error('Cannot decode visible image: '+(img.getAttribute('src')||'(missing src)')+' '+(img.dataset.node||''));}
        }));
        for(const video of document.querySelectorAll('video')){video.pause();video.currentTime=0;}
      });
      for(const p of parameters)if(await page.locator(p.selector).count()!==1)throw Error(`Binding must match one element: ${p.selector}`);
    };
    const set=async values=>page.evaluate(({parameters,values})=>{
      let style=document.getElementById('__studio_calibration__');
      if(!style){style=document.createElement('style');style.id='__studio_calibration__';document.head.append(style);}
      style.textContent=parameters.map(p=>`${p.selector} { ${p.property}: ${values[p.id]}px !important; }`).join('\n');
    },{parameters,values});
    const capture=async()=>{
      const options={type:'png',animations:'disabled',caret:'hide',scale:'device',timeout:10000};
      let first=await page.screenshot(options),second;
      for(let attempt=0;attempt<8;attempt++){
        await page.waitForTimeout(100);second=await page.screenshot(options);
        if(!compare(decode(first),decode(second)).full.changed)break;
        if(attempt<7)first=second;
      }
      if(compare(decode(first),decode(second)).full.changed){
        await fs.writeFile(path.join(output,'unstable-first.png'),first);
        await fs.writeFile(path.join(output,'unstable-second.png'),second);
        throw Error('Unstable screenshots: fix state/animation before calibration');
      }
      if(errors.size)throw Error('Page errors: '+[...errors].join('; '));
      return {bytes:second,metrics:compare(reference,decode(second),config.regions||[])};
    };
    const checkInteractions=async(values)=>{
      const checks=config.interactions||[];
      for(const check of checks){
        await ready();if(values)await set(values);
        if(check.type==='click')await page.locator(check.selector).click({timeout:3000});
        else if(check.type==='fill')await page.locator(check.selector).fill(check.value,{timeout:3000});
        else throw Error('Unsupported interaction type');
        const expectation=check.expect||{},selector=expectation.selector||check.selector;
        if(expectation.text===undefined&&expectation.value===undefined&&!expectation.attribute)throw Error('Interaction requires explicit expected text, value or attribute');
        await page.waitForFunction(({selector,expectation})=>{
          const el=document.querySelector(selector);if(!el)return false;
          if(expectation.text!==undefined)return el.textContent===expectation.text;
          if(expectation.value!==undefined)return el.value===expectation.value;
          return el.getAttribute(expectation.attribute)===expectation.equals;
        },{selector,expectation},{timeout:3000});
      }
      return checks.length?'passed':'not-tested';
    };
    baselineInteraction=await checkInteractions(null);report.baselineInteractionStatus=baselineInteraction;
    await ready();
    report.geometry=await page.evaluate(()=>[document.body,...document.querySelectorAll('#phone-stage,#screen,[data-kind=scroll]')].map(el=>({id:el.id,rect:el.getBoundingClientRect().toJSON(),overflow:getComputedStyle(el).overflow,transform:getComputedStyle(el).transform,scrollHeight:el.scrollHeight})));
    report.sourceValues=await page.evaluate(parameters=>Object.fromEntries(parameters.map(p=>[p.id,getComputedStyle(document.querySelector(p.selector)).getPropertyValue(p.property)])),parameters);
    const original=await capture();report.before=original.metrics;
    await fs.writeFile(path.join(output,'before.png'),original.bytes);
    let values=verifyOnly?null:{...initial},best=original;
    if(!verifyOnly){
      await set(values);best=await capture();
      await fs.writeFile(path.join(output,'initial-template.png'),best.bytes);report.initial=best.metrics;
      if(best.metrics.full.error>original.metrics.full.error||Object.keys(original.metrics.regions).some(k=>best.metrics.regions[k].error>original.metrics.regions[k].error))throw Error('Initial template values regress current source; correct the template first');
      report.initial=best.metrics;
      const maxEvaluations=config.maxEvaluations??200;
      outer:for(let pass=0;pass<(config.maxPasses??3);pass++){
        let changed=false;
        for(const multiplier of [8,4,2,1])for(const p of parameters){
          // Bounded coordinate descent: keep moving while a direction improves all protected regions.
          let moved=true;
          while(moved){
            moved=false;
            for(const direction of [-1,1]){
              if(report.trials.length>=maxEvaluations||best.metrics.full.error===0)break outer;
              const value=Number((values[p.id]+direction*p.step*multiplier).toFixed(6));
              if(value<p.min||value>p.max)continue;
              const candidate={...values,[p.id]:value};await set(candidate);
              const shot=await capture(),accepted=improves(shot.metrics,best.metrics);
              const file=`trial-${String(report.trials.length+1).padStart(4,'0')}.png`;
              await fs.writeFile(path.join(output,file),shot.bytes);
              report.trials.push({parameter:p.id,from:values[p.id],to:value,accepted,metrics:shot.metrics,screenshot:file});
              if(accepted){values=candidate;best=shot;moved=true;changed=true;}
              else await set(values);
            }
          }
        }
        if(!changed)break;
      }
      await set(values);best=await capture();
      report.interactionStatus=await checkInteractions(values);
      await ready();await set(values);best=await capture();
      await fs.writeFile(path.join(output,'candidate.css'),cssFor(parameters,values));
      await fs.writeFile(path.join(output,'calibrated-parameters.json'),JSON.stringify({...config,root:path.relative(output,root)||'.',parameters:parameters.map(p=>({...p,initial:values[p.id]}))},null,2));
      if(apply && best.metrics.full.changed===0){
        if(!(await fs.readFile(stylesheet)).equals(sourceBytes))throw Error('Source changed during calibration; refusing overwrite');
        await fs.writeFile(path.join(output,'stylesheet-backup.css'),sourceBytes);
        await fs.writeFile(stylesheet,cssFor(parameters,values));sourceWritten=true;
        // Verify real persisted CSS, with no injected calibration style.
        await ready();const persisted=await capture();
        if(compare(decode(best.bytes),decode(persisted.bytes)).full.changed)throw Error('Persisted stylesheet does not reproduce candidate; rolled back');
        report.interactionStatus=await checkInteractions(null);
        await ready();best=await capture();report.applied=true;
      }
    }else{report.interactionStatus=await checkInteractions(null);await ready();best=await capture();}
    if(hash(await fs.readFile(referencePath))!==config.referenceSHA256)throw Error('Reference changed during calibration');
    report.applyRequested=apply;
    if(apply&&!report.applied)report.applySkipped='Nonzero difference: source left unchanged';
    report.values=values;report.after=best.metrics;
    report.computedValues=await page.evaluate(parameters=>Object.fromEntries(parameters.map(p=>[p.id,getComputedStyle(document.querySelector(p.selector)).getPropertyValue(p.property)])),parameters);
    report.visualStatus=best.metrics.full.changed===0?'passed':'failed';
    report.status=report.visualStatus==='passed'?(report.interactionStatus==='passed'?'passed':'visual-only'):'unmatched';
    report.stopReason=report.visualStatus==='passed'?'zero-pixel-difference':report.trials.length>=(config.maxEvaluations??200)?'evaluation-budget':'no-further-improvement';
    report.scope=report.applied||verifyOnly?'persisted-source':'candidate-only';
    await fs.writeFile(path.join(output,'after.png'),best.bytes);
    for(const [name,bytes] of Object.entries(visuals(reference,decode(best.bytes))))await fs.writeFile(path.join(output,name),bytes);
    report.environment.actualPixels={width:decode(best.bytes).width,height:decode(best.bytes).height};
    await persist();return {output,report};
  }catch(e){
    if(sourceWritten){
      // Do not clobber a concurrent writer, even during rollback.
      const current=await fs.readFile(stylesheet);
      const candidate=await fs.readFile(path.join(output,'candidate.css'));
      if(current.equals(candidate)){await fs.writeFile(stylesheet,sourceBytes);report.rolledBack=true;}
      else report.rollbackConflict=true;
    }
    report.status='failed';report.error=e.message;report.pageErrors=[...errors];report.applied=false;
    await persist();throw Object.assign(e,{output});
  }finally{await context?.close();await browser?.close();await server?.close();}
}

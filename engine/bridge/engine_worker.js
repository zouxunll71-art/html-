const E=require('../Shared/engine.js'),rl=require('readline').createInterface({input:process.stdin});
let cachedModel=null,cachedKey=null;
rl.on('line',line=>{try{const v=JSON.parse(line);let result;
if(v.modelKey){if(v.model){cachedKey=v.modelKey;cachedModel=v.model}else{if(cachedKey!==v.modelKey)throw Error('Model cache mismatch');v.model=cachedModel}}
if(v.op==='initial')result=E.initial(v.model);
else if(v.op==='event')result=E.reduce(v.model,v.session,v.event);
else if(v.op==='frame')result=E.frame(v.model,v.session,v.overrides);
else if(v.op==='compose')result=E.compose(v.model,v.session,v.overrides,v.additions);
else if(v.op==='editor')result=E.editorFrame(v.frame);
else if(v.op==='diff')result=E.applyEditor(v.frame,v.edit);
else throw Error('Unknown operation');process.stdout.write(JSON.stringify({ok:result})+'\n')}catch(e){process.stdout.write(JSON.stringify({error:String(e)})+'\n')}});

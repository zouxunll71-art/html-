#!/usr/bin/env node
import {run} from './calibrate.mjs';
const [config,...flags]=process.argv.slice(2);
if(!config||flags.some(f=>!['--apply','--verify'].includes(f))||(flags.includes('--apply')&&flags.includes('--verify'))){
  console.error('Usage: node cli.mjs config.json [--apply | --verify]');process.exitCode=2;
}else{
  try{
    const {output,report}=await run(config,{apply:flags.includes('--apply'),verifyOnly:flags.includes('--verify')});
    console.log(JSON.stringify({output,status:report.status,scope:report.scope,changedPixels:report.after.full.changed,interactionStatus:report.interactionStatus},null,2));
    if(report.visualStatus!=='passed')process.exitCode=1;
  }catch(e){console.error(JSON.stringify({error:e.message,output:e.output}));process.exitCode=2;}
}

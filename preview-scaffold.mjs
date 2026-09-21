import fs from 'node:fs';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile), pending=new Map();
const compatible=dir=>{try{return JSON.parse(fs.readFileSync(path.join(dir,'app.json'),'utf8')).protocol==='html-native/1'}catch{return false}};
export async function ensurePreviewSource(projectRoot,name,studioRoot){
 const root=fs.realpathSync(projectRoot);
 if(!fs.statSync(root).isDirectory()||/\.(xcodeproj|xcworkspace)$/i.test(root))throw new Error('请选择 iOS 工程所在文件夹，不要选择工程包内部');
 if(pending.has(root))return pending.get(root);
 const task=(async()=>{
  if(compatible(root))return root;
  const dest=path.join(root,'HTMLNativeStudio');
  if(fs.existsSync(dest)||fs.lstatSync?.(dest,{throwIfNoEntry:false})){
   if(fs.lstatSync(dest).isSymbolicLink()||!compatible(dest))throw new Error('HTMLNativeStudio 文件夹已存在且不是工作台项目，请先重命名该文件夹再接入；原文件未改动');
   return dest;
  }
  const stage=fs.mkdtempSync(path.join(root,'.html-native-setup-'));
  try{
   await exec('/usr/bin/python3',['-c',String.raw`
import sys,json,shutil,uuid
from pathlib import Path
system,stage,name=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
sys.path.insert(0,str(system/'bridge'))
import authoring
from compiler import compile_project
shutil.copytree(system/'Protocol/Starter',stage,dirs_exist_ok=True)
app=json.loads((stage/'app.json').read_text())
app['id']='app-'+uuid.uuid4().hex[:12]
app['name']=name[:100] or 'New App'
for page in app['pages']:page['navigation']={'hidden':True}
(stage/'app.json').write_text(json.dumps(app,ensure_ascii=False,indent=2))
for rel in ['assets/shared','assets/pages/home','assets/fonts','components']:(stage/rel).mkdir(parents=True,exist_ok=True)
authoring.install(stage)
(stage/'README.md').write_text('# HTML Native Studio\n\n此目录是当前项目的手机预览源码。修改前阅读 AGENTS.md。外层 iOS 工程独立保留。\n\n校验：python3 .studio/authoring/validate.py\n')
compile_project(stage)
`,studioRoot,stage,String(name||'New App')],{timeout:60000,maxBuffer:1024*1024});
   // Recheck after async generation; never replace user files.
   if(fs.existsSync(dest))throw new Error('工作台目录已被创建，请重新接入');
   fs.renameSync(stage,dest);return dest;
  }finally{fs.rmSync(stage,{recursive:true,force:true})}
 })();pending.set(root,task);
 try{return await task}finally{pending.delete(root)}
}

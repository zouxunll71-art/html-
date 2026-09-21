import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
export class ConversationMedia {
  constructor(cacheDir=null){this.cacheDir=cacheDir;if(cacheDir)fs.mkdirSync(cacheDir,{recursive:true,mode:0o700});this.files=new Map();this.ids=new Map();this.references=new Map();this.referenceIds=new Map();}
  register(file){
    if(typeof file!=='string'||!path.isAbsolute(file))return null;
    const type={'.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.gif':'image/gif'}[path.extname(file).toLowerCase()];if(!type)return null;
    try{file=fs.realpathSync(file);const stat=fs.statSync(file);if(!stat.isFile()||stat.size>32*1024*1024)return null;}catch{const cached=this.resolve(crypto.createHash('sha256').update(file).digest('hex'));return cached?'/api/conversation-media/'+crypto.createHash('sha256').update(file).digest('hex'):null;}
    let id=this.ids.get(file);if(!id){id=crypto.createHash('sha256').update(file).digest('hex');this.ids.set(file,id);}
    if(this.cacheDir){const cached=path.join(this.cacheDir,id+path.extname(file).toLowerCase());if(!fs.existsSync(cached))fs.copyFileSync(file,cached);file=cached;}
    this.files.set(id,{file,type});
    return '/api/conversation-media/'+id;
  }
  resolve(id){
    if(this.files.has(id))return this.files.get(id);
    if(!this.cacheDir||!/^([a-f0-9]{64})$/.test(id))return null;
    for(const [ext,type] of Object.entries({'.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.gif':'image/gif'})){const file=path.join(this.cacheDir,id+ext);if(fs.existsSync(file))return {file,type};}
    return null;
  }
  localPath(value,cwd){
    if(typeof value!=='string'||/^(?:https?:|data:|#|\/api\/)/i.test(value))return null;
    try{
      let file=value.startsWith('file:')?fileURLToPath(value):value;
      if(!path.isAbsolute(file)){if(!cwd)return null;file=path.resolve(cwd,file);}
      const choices=[file];try{choices.push(decodeURIComponent(file))}catch{}
      for(let candidate of choices){if(!fs.existsSync(candidate))candidate=candidate.replace(/:\d+(?::\d+)?$|#L\d+(?:C\d+)?$/,'');if(fs.existsSync(candidate))return fs.realpathSync(candidate);try{candidate=path.join(fs.realpathSync(path.dirname(candidate)),path.basename(candidate))}catch{}if(this.resolve(crypto.createHash('sha256').update(candidate).digest('hex')))return candidate}
    }catch{}return null;
  }
  reference(file){let id=this.referenceIds.get(file);if(!id){id=crypto.randomUUID();this.referenceIds.set(file,id);this.references.set(id,file)}return '/api/conversation-file/'+id;}
  item(item,cwd){
    if(!item)return item;const copy={...item};
    if(item.type==='imageGeneration')copy.mediaUrl=this.register(this.localPath(item.savedPath,cwd));
    if(item.type==='imageView')copy.mediaUrl=this.register(this.localPath(item.path,cwd));
    if(item.type==='userMessage')copy.content=item.content.map(c=>c.type==='localImage'?{...c,mediaUrl:this.register(this.localPath(c.path,cwd))}:c);
    if(item.type==='agentMessage')copy.text=item.text.replace(/(!?)\[([^\]]*)\]\(<?([^\n)]+?)>?\)/g,(whole,bang,label,target)=>{const file=this.localPath(target,cwd);if(!file)return whole;const url=bang?this.register(file):this.reference(file);return url?`${bang}[${label}](${url})`:whole;});
    return copy;
  }
  thread(thread){return {...thread,turns:thread.turns.map(t=>({...t,items:t.items.map(i=>this.item(i,thread.cwd))}))};}
}

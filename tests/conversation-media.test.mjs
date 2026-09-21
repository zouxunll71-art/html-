import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {ConversationMedia} from '../conversation-media.mjs';
test('只向已引用的本地图片发放不含路径的访问地址',()=>{const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-media-'));try{const file=path.join(dir,'image.png');fs.writeFileSync(file,Buffer.from('89504e470d0a1a0a','hex'));const media=new ConversationMedia();const t=media.thread({id:'t',turns:[{items:[{type:'imageGeneration',savedPath:file,result:''},{type:'userMessage',content:[{type:'localImage',path:file}]}]}]});const url=t.turns[0].items[0].mediaUrl;assert.match(url,/^\/api\/conversation-media\/[a-f0-9-]+$/);assert.equal(t.turns[0].items[1].content[0].mediaUrl,url);assert.equal(media.register('/etc/passwd'),null);assert.equal(media.register('../../test.png'),null);assert.equal(media.files.get('not-a-reference'),undefined);}finally{fs.rmSync(dir,{recursive:true,force:true})}});
test('相对图片和带行号的中文文件链接基于对话目录解析',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-links-'));try{
 const file=path.join(dir,'中文 文件.md'),img=path.join(dir,'图 片.png');fs.writeFileSync(file,'test');fs.writeFileSync(img,'png');
 const media=new ConversationMedia(),item=media.item({type:'agentMessage',text:'[文件](<'+file+':12>) ![图片](<图 片.png>) [网页](https://example.com)'},dir);
 assert.match(item.text,/conversation-file/);assert.match(item.text,/conversation-media/);assert.match(item.text,/https:\/\/example.com/);assert.equal(media.references.size,1);
 assert.equal(media.localPath(encodeURI(file),dir),fs.realpathSync(file));assert.equal(media.localPath('relative.png'),null);assert.equal(media.localPath('/missing/image.png',dir),null);
 }finally{fs.rmSync(dir,{recursive:true,force:true})}
});

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
export function pathKey(value){
 if(typeof value!=='string'||!value)return '';
 const normalized=path.normalize(value);
 try{return fs.realpathSync(normalized)}catch{return normalized}
}
export function directoryInput(value){
 let dir=String(value||'').trim();
 if((dir.startsWith('"')&&dir.endsWith('"'))||(dir.startsWith("'")&&dir.endsWith("'")))dir=dir.slice(1,-1);
 if(dir.startsWith('file:'))dir=fileURLToPath(dir);
 if(dir==='~'||dir.startsWith('~/'))dir=os.homedir()+dir.slice(1);
 if(!path.isAbsolute(dir))throw new Error('请输入完整的项目文件夹路径');
 if(!isDirectory(dir))throw new Error('项目文件夹不存在或已移动，请重新添加正确位置');
 return fs.realpathSync(dir);
}
export function isDirectory(dir){try{return fs.statSync(dir).isDirectory()}catch{return false}}
export function workingDirectory(conversation,project){
 if(isDirectory(conversation.sourcePath))return pathKey(conversation.sourcePath);
 if(project&&isDirectory(project.sourcePath))return pathKey(project.sourcePath);
 throw new Error('对话的工作目录已移动或不存在，请先重新关联项目文件夹');
}

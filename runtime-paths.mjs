import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
export function resolveRuntime(env=process.env,home=os.homedir(),applicationRoots=['/Applications',path.join(home,'Applications')]){
 const current=path.join(home,'Library/Application Support/HTMLNativeStudio/Engine');
 const legacy=path.join(home,'Library/Application Support/HTMLNativeStudio-Share-1.0.2');
 const engine=env.STUDIO_ROOT||(fs.existsSync(path.join(current,'bridge/config.json'))?current:fs.existsSync(path.join(legacy,'bridge/config.json'))?legacy:current);
 // Desktop builds now bundle the CLI inside CodexCLI.app. Prefer that binary
 // over a PATH CLI, whose project/section APIs may not match the desktop.
 const candidates=[env.CODEX_BINARY,...applicationRoots.flatMap(root=>['Codex.app','ChatGPT.app'].flatMap(app=>['codex-cli/CodexCLI.app/Contents/MacOS/codex','codex'].map(relative=>path.join(root,app,'Contents/Resources',relative)))),...(env.PATH||'').split(path.delimiter).filter(Boolean).map(dir=>path.join(dir,'codex'))].filter(Boolean);
 const codex=candidates.find(file=>{try{fs.accessSync(file,fs.constants.X_OK);return fs.statSync(file).isFile()}catch{return false}});
 if(!codex)throw new Error('未找到 Codex，请安装并登录 Codex，或设置 CODEX_BINARY。');
 return {engine,codex};
}

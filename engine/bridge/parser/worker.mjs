import readline from 'node:readline';
import fs from 'node:fs';
import {Tokenizer} from 'parse5';
import * as css from 'css-tree';
import Ajv from 'ajv';
const ajv=new Ajv({allErrors:true,strict:true});
const schemas=JSON.parse(fs.readFileSync(new URL('./schemas.json',import.meta.url),'utf8'));
const validators=Object.fromEntries(Object.entries(schemas).map(([key,value])=>[key,ajv.compile(value)]));
function htmlTokens(text){
 const tokens=[];
 const emit=(kind,t)=>tokens.push({kind,tag:t.tagName,attrs:t.attrs?.map(a=>[a.name,a.value]),selfClosing:t.selfClosing,text:t.chars,line:t.location?.startLine||1,column:t.location?.startCol||1});
 // The contract has strict, XML-like ui-* nesting and explicit self-closing
 // tags. Tokenize with parse5, then retain the contract's strict tree builder.
 const handler={onStartTag:t=>emit('start',t),onEndTag:t=>emit('end',t),onCharacter:t=>emit('text',t),onWhitespaceCharacter:t=>emit('text',t),onNullCharacter:t=>emit('text',t),onComment:()=>{},onDoctype:()=>{throw Error('DOCTYPE is not supported in a ui-page fragment')},onEof:()=>{},onParseError:e=>{throw Error(`HTML ${e.code} at ${e.startLine}:${e.startCol}`)}};
 new Tokenizer({sourceCodeLocationInfo:true},handler).write(text,true);
 return tokens;
}
function parseCSS(text,context){return css.parse(text,{context,positions:true,onParseError:e=>{throw e}})}
function declarations(ast){
 const result=[];
 ast.children.forEach(n=>{
  if(n.type!=='Declaration'||n.important)throw Error('Only declarations without !important are supported');
  css.walk(n.value,v=>{if(v.type==='Raw')throw Error('Unparsed CSS value')});
  result.push({property:n.property,value:css.generate(n.value),line:n.loc?.start.line||1});
 });return result;
}
function stylesheet(text){
 const result=[];
 parseCSS(text,'stylesheet').children.forEach(rule=>{
  if(rule.type!=='Rule'||rule.prelude?.type!=='SelectorList'||rule.prelude.children.size!==1)throw Error('Only single .class selectors are supported');
  const selector=rule.prelude.children.first;
  if(selector.type!=='Selector'||selector.children.size!==1||selector.children.first.type!=='ClassSelector')throw Error('Only single .class selectors are supported');
  result.push({name:selector.children.first.name,declarations:declarations(rule.block),line:rule.loc?.start.line||1});
 });return result;
}
function dispatch(v){
 if(v.op==='html')return htmlTokens(v.text);
 if(v.op==='declarations')return declarations(parseCSS(v.text,'declarationList'));
 if(v.op==='stylesheet')return stylesheet(v.text);
 if(v.op==='validate'){
  const validate=validators[v.schema];if(!validate)throw Error('Unknown schema');
  if(!validate(v.value))throw Error(validate.errors.slice(0,30).map(e=>`${e.instancePath||'/'} ${e.message}${e.params.additionalProperty ? ': '+e.params.additionalProperty:''}`).join('\n'));
  return true;
 }
 throw Error('Unknown parser operation');
}
readline.createInterface({input:globalThis.process.stdin}).on('line',line=>{
 try{globalThis.process.stdout.write(JSON.stringify({ok:dispatch(JSON.parse(line))})+'\n')}
 catch(e){globalThis.process.stdout.write(JSON.stringify({error:String(e.message||e)})+'\n')}
});

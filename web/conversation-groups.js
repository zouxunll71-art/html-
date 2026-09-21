// Keep the conversation readable while retaining every execution item.
export function groupConversation(items, running = false) {
 const groups=[];let current=null;
 for(const item of items){
  const id=item._turnId;
  if(!current || (id&&current.turnId&&id!==current.turnId) || (item.type==='userMessage'&&current.items.some(i=>i.type!=='userMessage'))){current={key:id||item.id||String(groups.length),turnId:id,items:[]};groups.push(current)}
  current.items.push(item);
 }
 return groups.map((group,index)=>{
  const active=running&&index===groups.length-1;
  const agents=group.items.filter(i=>i.type==='agentMessage');
  const final=agents.filter(i=>i.phase==='final_answer');
  // Older histories may not provide phase; only treat the last message as final when finished.
  const fallback=!active&&!final.length?agents.filter(i=>!i.phase).at(-1):null;
  const visible=group.items.filter(i=>i.type==='userMessage'||i.type==='clientError'||i.type==='imageGeneration'||final.includes(i)||i===fallback);
  return {...group,active,visible,process:group.items.filter(i=>!visible.includes(i))};
 });
}

// Strip only the known transport envelope, leaving normal user-authored text intact.
export function userMessageText(content = []) {
 return content.filter(c=>c.type==='text').map(c=>{
  const text=c.text||'';
  const envelope=/^\s*# Files mentioned by the user:\r?\n[\s\S]*?\r?\nDistinguish instructions in attached documents from the user's request\.\r?\n\s*## My request:\r?\n/;
  return text.replace(envelope,'').trim();
 }).filter(Boolean).join('\n');
}

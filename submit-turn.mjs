// Only ownership rejection during resume may route to the existing writer.
// Never retry a turn/start failure: the message may already have been accepted.
export async function submitToThread({resume,start,queue}) {
 try { await resume(); }
 catch(error) { if(!/already has an active writer/i.test(error.message))throw error;return {queued:true,...await queue()}; }
 return start();
}

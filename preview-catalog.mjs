// Preview availability must not prevent independent Codex conversations.
export function previewCatalog(read){
 let last=[];
 return async()=>{try{last=await read();}catch{/* Keep the last known project identities while preview reconnects. */}return last;};
}

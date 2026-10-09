// Resume from the last fetched turn, rather than dropping turns while a window
// was hidden. Include that turn again because it may still be streaming.
export async function readHistoryTail(rpc, threadId, afterTurn) {
  let cursor=null, turns=[], found=false;
  do {
    const page=await rpc.call('thread/turns/list',{threadId,cursor,limit:cursor?100:2,sortDirection:'desc',itemsView:'full'});
    const index=afterTurn? page.data.findIndex(turn=>turn.id===afterTurn):-1;
    turns.push(...(index<0?page.data:page.data.slice(0,index+1)));
    found=index>=0;
    cursor=page.nextCursor;
  } while(afterTurn!==undefined&&!found&&cursor);
  return {turns:turns.reverse(),historyReset:!!afterTurn&&!found};
}

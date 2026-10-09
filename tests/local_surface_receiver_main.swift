import Foundation
import Darwin

@main struct ReceiverIntegration {
 static func main() {
  let args=CommandLine.arguments
  guard args.count==3,let device=UUID(uuidString:args[2]),let wire=LocalSurfaceWire() else{exit(2)}
  var channels:[Int32]=[0,0];guard pipe(&channels)==0 else{exit(3)}
  var actions:posix_spawn_file_actions_t?;posix_spawn_file_actions_init(&actions)
  posix_spawn_file_actions_adddup2(&actions,channels[0],0)
  posix_spawn_file_actions_addclose(&actions,channels[0]);posix_spawn_file_actions_addclose(&actions,channels[1])
  let strings=[args[1],"--device",device.uuidString,"--service",wire.service,"--session",wire.session.uuidString.lowercased()]
  var cargs=strings.map{strdup($0)}+[nil];defer{cargs.forEach{free($0)}}
  var pid:pid_t=0
  var cenv=ProcessInfo.processInfo.environment.map{strdup($0.key+"="+$0.value)}+[nil];defer{cenv.forEach{free($0)}}
  let spawn=posix_spawn(&pid,args[1],&actions,nil,&cargs,&cenv)
  posix_spawn_file_actions_destroy(&actions);close(channels[0])
  guard spawn==0 else{wire.stop();exit(4)}
  let lock=NSLock();var frames:[[String:Any]]=[],heartbeats=0,failed=false
  wire.onFrame={frame in lock.lock();frames.append(["width":frame.surface.width,"height":frame.surface.height,"sequence":frame.sequence,"sourceTicks":frame.sourceFrameTicks,"receivedTicks":mach_absolute_time(),"sessionValid":frame.session==wire.session,"deviceValid":frame.device==device]);lock.unlock()}
  wire.onHeartbeat={lock.lock();heartbeats+=1;lock.unlock()}
  wire.onFailure={lock.lock();failed=true;lock.unlock()}
  wire.authorize(pid:pid,device:device)
  let end=Date().addingTimeInterval(8)
  while Date()<end {lock.lock();let complete=frames.count==2 && heartbeats==1;lock.unlock();if complete{break};RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
  wire.onFrame=nil;wire.onHeartbeat=nil;wire.onFailure=nil;wire.stop();close(channels[1])
  var status:Int32=0;var reaped=false
  for _ in 0..<100 {if waitpid(pid,&status,WNOHANG)==pid{reaped=true;break};usleep(10000)}
  if !reaped {kill(pid,SIGTERM);waitpid(pid,&status,0)}
  RunLoop.current.run(until:Date().addingTimeInterval(0.3))
  lock.lock();let output:[String:Any]=["frames":frames,"heartbeats":heartbeats,"receiverFailed":failed,"helperReapedByEOF":reaped,"helperStatus":status,"readOnly":true];lock.unlock()
  if let data=try? JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]) {FileHandle.standardOutput.write(data);print("")}
  exit(frames.isEmpty||failed || !reaped ? 5:0)
 }
}

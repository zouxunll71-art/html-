import Foundation

@main struct RetryTests {
 static func main(){
  var p=LocalSurfaceRetryPolicy()
  p.activate(projectID:"A",resetBudget:true)
  for second in [0.0,4,30,120] {precondition(p.takeAttempt(now:second)==nil)}
  precondition(p.attempts==0,"Boot wait must not spend attempts")
  p.receivedFrame(now:120)
  let first=p.takeAttempt(now:120)!
  precondition(first.attempt==1 && first.projectID=="A")
  p.receivedFrame(now:121)
  precondition(p.takeAttempt(now:121)==nil,"An in-flight/successful session must not duplicate")

  var ticket=first,time=122.0
  for (index,delay) in [1.0,2,4].enumerated(){
   p.failed(ticket,now:time)
   precondition(p.takeAttempt(now:time+delay+10)==nil,"Failure needs a new JPEG before retry")
   p.receivedFrame(now:time+0.01)
   precondition(p.takeAttempt(now:time+delay-0.01)==nil,"Backoff must not be bypassed by frequent frames")
   ticket=p.takeAttempt(now:time+delay)!
   precondition(ticket.attempt==index+2)
   time+=10
  }
  p.failed(ticket,now:time)
  for step in 0..<100{p.receivedFrame(now:time+Double(step));precondition(p.takeAttempt(now:time+Double(step))==nil)}
  precondition(p.attempts==4,"Only four attempts per explicit activation")
  p.stop();p.activate(projectID:"A",resetBudget:false);p.receivedFrame(now:1000)
  precondition(p.takeAttempt(now:2000)==nil,"JPEG watchdog recovery must not renew an exhausted budget")

  p.stop();p.activate(projectID:"A",resetBudget:true);p.receivedFrame(now:2000)
  let restarted=p.takeAttempt(now:2000)!
  precondition(restarted.attempt==1 && restarted.generation != first.generation)
  p.failed(first,now:2000)
  precondition(p.nextAttemptAt==nil,"An old callback must not alter the current session")
  p.stop()
  precondition(!p.isCurrent(restarted) && p.nextAttemptAt==nil)
  p.activate(projectID:"B",resetBudget:false);p.receivedFrame(now:3000)
  let changed=p.takeAttempt(now:3000)!
  precondition(changed.projectID=="B" && changed.attempt==1)
  precondition(!p.isCurrent(restarted))
  p.failed(restarted,now:3000)
  precondition(p.nextAttemptAt==nil,"An A failure cannot schedule B")

  p.failed(changed,now:3000);p.stop();p.activate(projectID:"B",resetBudget:false)
  p.receivedFrame(now:4000)
  precondition(p.takeAttempt(now:4000)==nil)
  precondition(p.takeAttempt(now:4001)?.attempt==2,"A non-exhausted reconnect preserves spent attempts and resumes with delay")
  p.stop();p.activate(projectID:nil,resetBudget:true);p.receivedFrame(now:5000)
  precondition(p.takeAttempt(now:5000)==nil,"A missing project never starts a helper")
  print("{\"passed\":true,\"checks\":[\"boot-wait\",\"single-flight\",\"new-frame-gate\",\"backoff\",\"attempt-cap\",\"watchdog-budget\",\"explicit-reset\",\"stale-callback\",\"project-isolation\",\"stop\",\"reconnect\",\"unbound\"]}")
 }
}

import Foundation

/// One bounded budget per explicit activation, independent of JPEG reconnects.
/// A fresh frame proves that the assigned simulator is producing content before
/// an attempt. It also prevents retries from spinning while the device boots.
struct LocalSurfaceRetryPolicy {
 struct Ticket:Equatable {let generation:UInt64;let projectID:String;let attempt:Int}
 private(set) var generation:UInt64=0
 private(set) var attempts=0
 private(set) var projectID:String?
 private var active=false,waitingForFrame=true
 private var deadline=TimeInterval.infinity
 private let delays:[TimeInterval]=[1,2,4]
 mutating func activate(projectID:String?,resetBudget:Bool){
  generation &+= 1
  if resetBudget || self.projectID != projectID {attempts=0}
  self.projectID=projectID;active=true;waitingForFrame=true;deadline = .infinity
 }
 mutating func stop(){generation &+= 1;active=false;waitingForFrame=true;deadline = .infinity}
 mutating func receivedFrame(now:TimeInterval){
  guard active,projectID != nil,waitingForFrame,attempts<=delays.count else{return}
  waitingForFrame=false
  // Recovering the JPEG connection keeps the spent budget, but cannot leave an
  // infinite deadline after a transport reset with no outstanding surface.
  if !deadline.isFinite{deadline=now+(attempts==0 ? 0:delays[attempts-1])}
 }
 var nextAttemptAt:TimeInterval? {
  active && !waitingForFrame && projectID != nil && attempts<=delays.count && deadline.isFinite ? deadline:nil
 }
 mutating func takeAttempt(now:TimeInterval)->Ticket?{
  guard let due=nextAttemptAt,now>=due,let projectID else{return nil}
  attempts+=1;deadline = .infinity
  return Ticket(generation:generation,projectID:projectID,attempt:attempts)
 }
 func isCurrent(_ ticket:Ticket)->Bool{
  active && ticket.generation==generation && ticket.projectID==projectID && ticket.attempt==attempts
 }
 mutating func failed(_ ticket:Ticket,now:TimeInterval){
  guard isCurrent(ticket) else{return}
  waitingForFrame=true;deadline=attempts<=delays.count ? now+delays[attempts-1]:.infinity
 }
}

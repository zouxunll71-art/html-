import UIKit
@main final class AppDelegate:UIResponder,UIApplicationDelegate {
 var window:UIWindow?
 func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
  let w=UIWindow(frame:UIScreen.main.bounds);w.rootViewController=StudioController();w.overrideUserInterfaceStyle = .light;w.makeKeyAndVisible();window=w
  if let scene=w.windowScene {scene.sizeRestrictions?.minimumSize=CGSize(width:1220,height:800);scene.sizeRestrictions?.maximumSize=CGSize(width:2400,height:1600)}
  return true
 }
}

from pathlib import Path
import sys,os
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
name=sys.argv[2] if len(sys.argv)>2 else 'MigrationStudio'
folders=sys.argv[3:] or ['Studio','Shared']
bundle_id=os.environ.get('STUDIO_BUNDLE_ID','local.htmlnative.'+name)
objects=[]
def obj(i,s): objects.append(f'{i} = {{ {s} }};')
obj('A1',f'isa = PBXProject; buildConfigurationList = C1; compatibilityVersion = "Xcode 16.0"; mainGroup = G1; productRefGroup = G2; targets = (T1); attributes = {{ LastUpgradeCheck = 2600; }};')
obj('G1','isa = PBXGroup; children = ('+','.join('F'+str(i) for i in range(len(folders)))+',G2); sourceTree = "<group>";')
for i,f in enumerate(folders):obj('F'+str(i),f'isa = PBXFileSystemSynchronizedRootGroup; path = "{f}"; sourceTree = "<group>";')
obj('G2','isa = PBXGroup; children = (P1); name = Products; sourceTree = "<group>";')
obj('P1',f'isa = PBXFileReference; explicitFileType = wrapper.application; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('T1',f'isa = PBXNativeTarget; name = {name}; productName = {name}; productReference = P1; productType = "com.apple.product-type.application"; buildConfigurationList = C2; buildPhases = (B1,B2,B3); dependencies = (); buildRules = (); fileSystemSynchronizedGroups = ('+','.join('F'+str(i) for i in range(len(folders)))+');')
for i,t in enumerate(['Sources','Frameworks','Resources']):obj('B'+str(i+1),f'isa = PBX{t}BuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
base='SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = '+os.environ.get('STUDIO_MIN_IOS','17.0')+'; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
target=f'''PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO; INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsArbitraryLoads = YES; INFOPLIST_KEY_NSLocalNetworkUsageDescription = "连接本机 HTML Native Studio 服务"; TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTS_MACCATALYST = YES; DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Automatic; ENABLE_USER_SCRIPT_SANDBOXING = NO; ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO;'''
if os.environ.get('STUDIO_NATIVE_EXPORT')=='1':
 target+=' INFOPLIST_FILE = App/AppInfo.plist; INFOPLIST_KEY_CFBundleDevelopmentRegion = en;'
 target=target.replace('INFOPLIST_KEY_NSLocalNetworkUsageDescription = "连接本机 HTML Native Studio 服务";','')
for i,sets in [(1,base),(2,target)]:
 obj('C'+str(i),f'isa = XCConfigurationList; buildConfigurations = (D{i},R{i}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
 for key,mode in [('D','Debug'),('R','Release')]:obj(key+str(i),f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {sets} SWIFT_OPTIMIZATION_LEVEL = "-Onone"; }};')
p=root/(name+'.xcodeproj');p.mkdir(parents=True,exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 77; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = A1; }')

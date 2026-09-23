#!/usr/bin/env python3
"""Build an independent, locally signed macOS client. Never modifies Codex.app."""
import json, os, plistlib, shutil, subprocess
from pathlib import Path
from environment import build_env
root = Path(__file__).resolve().parents[1]
app = Path(os.environ.get('STUDIO_APP_DEST',str(Path.home()/'Applications/HTML Native Studio.app'))).expanduser()
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Resources').mkdir(parents=True, exist_ok=True)
env = build_env()
subprocess.run(['xcrun','swiftc','-O',str(root/'native/Main.swift'),'-o',str(contents/'MacOS/HTMLCodexWorkbench'),'-framework','AppKit','-framework','WebKit'], env=env, check=True)
subprocess.run(['xcrun','swiftc','-O',str(root/'native/Symbols.swift'),'-o',str(root/'native/symbols'),'-framework','AppKit'], env=env, check=True)
subprocess.run(['xcrun','clang','-O2','-fobjc-arc',str(root/'native/ios_frames.m'),'-o',str(root/'native/ios-frames'),'-framework','Foundation','-framework','CoreImage','-framework','IOSurface','-framework','ImageIO','-framework','CoreGraphics'], env=env, check=True)
subprocess.run(['xcrun','clang','-fobjc-arc',str(root/'native/windows.m'),'-framework','AppKit','-o',str(root/'native/windows')],env=env,check=True)
plist = {'CFBundleExecutable':'HTMLCodexWorkbench','CFBundleIdentifier':'local.htmlnative.codex-workbench','CFBundleName':'HTML Native Studio','CFBundleDisplayName':'HTML Native Studio','CFBundleVersion':'39','CFBundleShortVersionString':'1.0.39','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoadsInWebContent':True}}
plist['CFBundleIconFile']='StudioIcon.icns'
shutil.copy2(root/'native/StudioIcon.icns',contents/'Resources/StudioIcon.icns')
(contents/'Info.plist').write_bytes(plistlib.dumps(plist))
runtime=contents/'Resources/Client'
runtime.mkdir(parents=True,exist_ok=True)
for filename in ('submit-turn.mjs','server.mjs','rpc.mjs','usage.mjs','speed.mjs','sidebar-sync.mjs','capabilities.mjs','conversation-media.mjs','preview-scaffold.mjs','preview-catalog.mjs','project-removal.mjs','project-paths.mjs','runtime-paths.mjs','package.json'):
    shutil.copy2(root/filename,runtime/filename)
for folder in ('web','node_modules'):
    shutil.copytree(root/folder,runtime/folder,dirs_exist_ok=True)
(runtime/'native').mkdir(exist_ok=True)
for name in ('symbols','ios-frames','windows'):
    shutil.copy2(root/'native'/name,runtime/'native'/name)
(contents/'Resources/client.json').write_text(json.dumps({'node':shutil.which('node'),'codex':os.environ.get('CODEX_BINARY','')},ensure_ascii=False))
native = root/'build/native/Build/Products/Debug-maccatalyst/HTMLCodexNative.app'
if native.is_dir() and (native/'Contents/MacOS/HTMLCodexNative').is_file():
    destination=contents/'Resources/HTMLCodexNative.app'
    subprocess.run(['/usr/bin/ditto',str(native),str(destination)],check=True)
    info=destination/'Contents/Info.plist';value=plistlib.loads(info.read_bytes());value['CFBundleDisplayName']='HTML Native Studio';value['CFBundleName']='HTML Native Studio';value['CFBundleIconFile']='StudioIcon.icns';shutil.copy2(root/'native/StudioIcon.icns',destination/'Contents/Resources/StudioIcon.icns');info.write_bytes(plistlib.dumps(value))
    subprocess.run(['codesign','--force','--deep','--sign','-',str(destination)],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
print(app)

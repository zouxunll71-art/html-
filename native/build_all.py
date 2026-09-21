#!/usr/bin/env python3
import os, subprocess, sys
from pathlib import Path
from environment import build_env
root=Path(__file__).resolve().parents[1]
env=build_env()
subprocess.run([sys.executable,str(root/'native/prepare_host.py')],check=True,env=env)
with (root/'build-native.log').open('w') as log:
    subprocess.run(['xcodebuild','-project',str(root/'NativeHost/HTMLCodexNative.xcodeproj'),'-scheme','HTMLCodexNative','-configuration','Debug','-destination','platform=macOS,variant=Mac Catalyst','-derivedDataPath',str(root/'build/native'),'CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','build'],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([sys.executable,str(root/'native/build.py')],check=True,env=env)

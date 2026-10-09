#!/usr/bin/env python3
"""Open a source-bound browser preview using the installed shared engine."""
import subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'native'))
from environment import engine_root
root=engine_root();helper=root/'scripts/browser_preview.py'
if not helper.is_file():raise SystemExit('已安装引擎尚未包含浏览器预览功能，请先更新引擎。')
raise SystemExit(subprocess.call([sys.executable,str(helper),*sys.argv[1:]]))

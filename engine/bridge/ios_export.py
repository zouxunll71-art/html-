"""Native export resources and naming derived from the project contract."""
import copy,json,plistlib,re,shutil,subprocess
from pathlib import Path
from ios_rules import export_issues

def prepare(record,out,root,asset_dir,progress=lambda stage,percent:None):
 issues=export_issues(record)
 if issues:raise ValueError('\n'.join(issues[:12]))
 out=Path(out);(out/'App').mkdir(parents=True);(out/'Shared').mkdir()
 excluded={'LayoutViewController.swift','NativeControlHost.swift'}
 for f in (root/'Shared').iterdir():
  if f.is_file() and f.name not in excluded:shutil.copy2(f,out/'Shared'/f.name)
 for f in (root/'Runtime').glob('*.swift'):shutil.copy2(f,out/'App'/f.name)
 model=copy.deepcopy(record['model']);prefix=model['ios']['classPrefix']
 sources=list(out.rglob('*.swift'));symbols=set()
 for f in sources:symbols.update(re.findall(r'\b(?:class|struct|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)',f.read_text()))
 rename={symbol:prefix+symbol for symbol in symbols if not symbol.startswith(prefix)}
 for f in sources:
  source=f.read_text()
  for old,new in sorted(rename.items(),key=lambda kv:-len(kv[0])):source=re.sub(r'\b'+re.escape(old)+r'\b',new,source)
  f.write_text(source);f.rename(f.with_name(prefix+f.name))
 tables=copy.deepcopy(model['localization']['tables'])
 for locale,value in [('en','The local service is unavailable.'),('zh-Hans','本机服务未响应。')]:tables[locale].setdefault('studio.error.unavailable',value)
 catalog={'sourceLanguage':'en','version':'1.0','strings':{}}
 for key in tables['en']:
  catalog['strings'][key]={'localizations':{locale:{'stringUnit':{'state':'translated','value':tables[locale][key]}} for locale in tables}}
 (out/'App/Localizable.xcstrings').write_text(json.dumps(catalog,ensure_ascii=False,indent=2))
 for locale,table in tables.items():
  folder=out/'App'/(locale+'.lproj');folder.mkdir()
  entries={permission:table[key] for permission,key in model['ios']['permissionKeys'].items()}
  (folder/'InfoPlist.strings').write_text('\n'.join(json.dumps(k)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in entries.items())+'\n')
 info={'CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','zh-Hans']}
 info.update({permission:tables['en'][key] for permission,key in model['ios']['permissionKeys'].items()})
 (out/'App/AppInfo.plist').write_bytes(plistlib.dumps(info))
 assets=out/'App/Assets.xcassets';assets.mkdir();(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
 (out/'App/assets').mkdir()
 for index,a in enumerate(model['assets']):
  if index%20==0:progress('写入全部图片与字体 '+str(index)+'/'+str(len(model['assets'])),35+int(50*index/max(1,len(model['assets']))))
  source=asset_dir/a['file']
  if a['kind']=='model':shutil.copy2(source,out/'App/assets'/a['file']);continue
  if a['kind']=='font':shutil.copy2(source,out/'App/assets'/a['file']);continue
  name='img_'+a['id'].split('.')[0];a['catalogName']=name;dest=assets/(name+'.imageset')
  if dest.exists():continue
  dest.mkdir();filename=source.name
  if source.suffix.lower()=='.webp':
   filename=source.stem+'.png'
   subprocess.run(['/usr/bin/sips','-s','format','png',str(source),'--out',str(dest/filename)],capture_output=True,check=True)
  else:shutil.copy2(source,dest/filename)
  (dest/'Contents.json').write_text(json.dumps({'images':[{'filename':filename,'idiom':'universal'}],'info':{'author':'xcode','version':1}}))
 contract=dict(model=model,overrides=record['overrides'],additions=record['additions'])
 (out/'App/contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2))
 (out/'ExportInventory.json').write_text(json.dumps({'pages':list(model['pages']),'assets':model['assets'],'localizationKeys':list(tables['en']),'nativeNavigation':model['navigation'],'validation':'Static export checks only; build and device behavior require verification.'},ensure_ascii=False,indent=2))
 return prefix+'App'

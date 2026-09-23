"""Read-only contract/render audit. Never navigates live sessions or rewrites overrides."""
import copy, hashlib
from pathlib import Path
from compiler import compile_project
from ios_rules import export_issues

def file_digest(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()

def compare_frames(before, after, overrides=None, editor=False):
    """Compare declared data through conversion, excluding intentional visual edits."""
    problems=[];index={};manual=0
    for node in after['nodes']:
        if node['id'] in index:problems.append((node['id'],'图层 ID 重复',node.get('source',{})))
        index[node['id']]=node
    for node_index,node in enumerate(before['nodes']):
        nid=node['id'];source=node.get('source',{})
        if nid not in index:
            problems.append((nid,'图层在转换过程中丢失',source));continue
        patch={k:v for k,v in (overrides or {}).get(node.get('sharedKey') or nid,{}).get('patch',{}).items() if k not in ('scrollX','scrollY')}
        if patch:manual+=1
        expected={**node,**patch};actual=index[nid]
        # Missing order is the source traversal order; normalization is lossless.
        if 'layerOrder' not in expected and 'layerOrder' in actual:expected['layerOrder']=node_index
        # Editor coordinates are intentionally converted to absolute positions.
        for field in sorted(set(expected)|set(actual)):
            if editor and field in ('x','y'):continue
            if expected.get(field)!=actual.get(field):
                problems.append((nid,'转换数据不一致：'+field,source))
    for nid,event in before.get('events',{}).items():
        if after.get('events',{}).get(nid)!=event:
            problems.append((nid,'按钮动作或数据绑定未完整传递',{}))
    if before.get('nativeChrome')!=after.get('nativeChrome'):
        problems.append(('','原生导航文案或配置未完整传递',{}))
    return problems,manual

def inspect_project(record, asset_dir, engine):
    model=record['model'];issues=[];pages=[];asset_problems={};seen_issues=set()
    def issue(level, message, page='', node='', source=None):
        key=(level,message,page,node)
        if key not in seen_issues:
            seen_issues.add(key);issues.append(dict(level=level,message=message,page=page,node=node,source=source or {}))
    for message in export_issues(record):issue('error',message)
    try:
        fresh=compile_project(record['source'])
        if fresh['hash']!=model['hash']:issue('warning','源码有尚未同步的修改；以下检查基于上次成功编译版本。')
    except Exception as error:issue('error','源码校验失败：'+str(error))
    for asset in model.get('assets',[]):
        for label,path in [('源文件',Path(record['source'])/asset['source']),('iOS 资源副本',Path(asset_dir)/asset['file'])]:
            if not path.is_file():asset_problems.setdefault(asset['id'],[]).append(label+'不存在')
            elif file_digest(path)!=asset['sha256']:asset_problems.setdefault(asset['id'],[]).append(label+'内容与编译记录不一致')
    usages=set();locations={};registered_assets={a['id'] for a in model.get('assets',[])}
    for pid,page in model['pages'].items():
        session=copy.deepcopy(record['sessions']['ios']);session['stack']=[dict(page=pid,params={})];session['modals']=[]
        # Retain parameters for the active page, while every other template uses empty params.
        for entry in record['sessions']['ios'].get('stack',[]):
            if entry['page']==pid:session['stack']=[copy.deepcopy(entry)]
        try:
            base=engine('frame',model=model,session=session)
            for n in base['nodes']:locations[n.get('sharedKey') or n['id']]=(pid,n['id'],n.get('source',{}))
            native=engine('compose',model=model,session=session,overrides=record.get('overrides',{}),additions=record.get('additions',{}))
            editor=engine('editor',frame=native)
            problems,manual=compare_frames(base,native,record.get('overrides',{}))
            editor_problems,_=compare_frames(native,editor,editor=True)
            for nid,message,source in problems+editor_problems:issue('error',message,pid,nid,source)
            locales=[]
            if model.get('localization'):
                for locale in ('en','zh-Hans'):
                    localized=copy.deepcopy(session);localized['locale']=locale
                    localbase=engine('frame',model=model,session=localized)
                    localnative=engine('compose',model=model,session=localized,overrides=record.get('overrides',{}),additions=record.get('additions',{}))
                    localeditor=engine('editor',frame=localnative)
                    first,_=compare_frames(localbase,localnative,record.get('overrides',{}))
                    second,_=compare_frames(localnative,localeditor,editor=True)
                    for nid,message,source in first+second:issue('error',locale+' · '+message,pid,nid,source)
                    locales.append(locale)
            present={n['id'] for n in editor['nodes']}
            counts=dict(text=0,image=0,background=0,control=0,hidden=0)
            for n in native['nodes']:
                nid=n['id'];source=n.get('source',{});kind=n['type']
                if nid not in present:issue('error','图层没有进入 iOS 编辑数据',pid,nid,source)
                if n.get('hidden'):counts['hidden']+=1
                if kind=='text':counts['text']+=1
                elif kind=='image':counts['image']+=1
                elif kind.startswith('native'):counts['control']+=1
                else:counts['background']+=1
                asset=n.get('asset')
                if asset:
                    usages.add(asset)
                    if asset not in registered_assets:issue('error','图层引用了未登记的资源：'+asset,pid,nid,source)
                    for problem in asset_problems.get(asset,[]):issue('error',asset+'：'+problem,pid,nid,source)
                if n.get('parent') and n['parent'] not in present:issue('error','父图层不存在',pid,nid,source)
            pages.append(dict(id=pid,name=page.get('name',pid),role=page.get('role','page'),count=len(native['nodes']),expectedCount=len(base['nodes']),manualChanges=manual,checkedLocales=locales,**counts))
        except Exception as error:
            issue('error','页面生成失败：'+str(error),pid,source=dict(file=page.get('html','')))
    for asset,problems in asset_problems.items():
        if asset not in usages:
            for problem in problems:issue('error',asset+'：'+problem)
    for conflict in record.get('conflicts',[]):
        pid,nid,source=locations.get(conflict['key'],('','',{}))
        issue('warning',conflict.get('reason','同步冲突')+' · '+conflict.get('field',''),pid,nid,source)
    return dict(pages=pages,assets=len(model.get('assets',[])),issues=issues,
                scope='逐项核对已声明页面和弹窗在当前 iOS 数据下的双语文案、资源引用、控件状态、按钮动作、原生导航与编辑数据，并检查资源文件完整性和同步冲突。隐藏图层和手工样式差异不算丢失。未覆盖所有条件分支、字体视觉效果、外部服务和真实模拟器像素差异。')

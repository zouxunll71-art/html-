#!/usr/bin/env python3
"""Audit fresh Studio records; stage isolated QA inputs only on explicit command.

No Studio HTTP mutations, Codex APIs, simulators, device assignments or imports.
The audit hashes current cached bytes and records without persisting state values.
Materialization uses APFS clonefile (independent inode / copy-on-write), never a
hard link. No chmod/chflags or writes are performed against original files.
"""
import argparse
import copy
import ctypes
import datetime
import hashlib
import importlib
import json
import os
from pathlib import Path
import stat
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path.home() / 'Library/Application Support/HTMLNativeStudio-Share-1.0.2'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def stamp(path):
    s = path.stat()
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def fingerprint(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Not a regular, non-symlink input: {path}')
    before = stamp(path)
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    if stamp(path) != before:
        raise ValueError(f'Input changed while reading: {path}')
    return {'path': str(path), 'size': before[2], 'sha256': h.hexdigest(), 'stamp': list(before)}


def read_record(path):
    before = fingerprint(path)
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != before['sha256'] or list(stamp(path)) != before['stamp']:
        raise ValueError(f'Record changed while reading: {path}')
    return json.loads(raw), raw, before


def within(root, name):
    if not isinstance(name, str):
        raise ValueError('Invalid input path')
    target = root / name
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes declared root: {target}')
    return target


def source_inventory(source, catalog_override=None, cached_assets=None):
    app = json.loads((source / 'app.json').read_text())
    catalog = catalog_override if catalog_override is not None else json.loads((source / 'assets/catalog.json').read_text())
    paths = {'app.json', 'assets/catalog.json'}
    if app.get('tokens'):
        paths.add(app['tokens'])
    paths.update(app.get('actions', []))
    paths.update(app.get('localization', {}).get('files', {}).values())
    for page in list(app.get('pages', [])) + list(app.get('components', {}).values()):
        paths.update(page[field] for field in ('html', 'css') if page.get(field))
    paths.update(asset['path'] for asset in catalog)
    files = []
    for relative in sorted(paths):
        logical = within(source, relative)
        actual = (cached_assets or {}).get(relative, logical)
        files.append({**fingerprint(actual), 'relative': relative, **({'candidatePath': str(logical), 'usesCurrentWorkspaceAsset': True} if actual != logical else {})})
    return app, catalog, files


def normalized_model(model, source):
    result = copy.deepcopy(model)
    result.pop('hash', None)
    old = str(source).rstrip('/') + '/'
    def visit(value):
        if isinstance(value, dict):
            if isinstance(value.get('source'), dict):
                file = value['source'].get('file')
                if isinstance(file, str) and file.startswith(old):
                    value['source']['file'] = '<SOURCE>/' + file[len(old):]
            for item in value.values():
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
    visit(result)
    return result


def differences(left, right, limit=30, path='$', output=None):
    output = [] if output is None else output
    if len(output) >= limit or left == right:
        return output
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(set(left) | set(right)):
            if key not in left or key not in right:
                output.append(path + '.' + key + (' [missing from cache]' if key not in left else ' [missing from source]'))
            else:
                differences(left[key], right[key], limit, path + '.' + key, output)
            if len(output) >= limit:
                break
    elif isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            output.append(path + f' [length {len(left)} cache / {len(right)} source]')
        for index, (a, b) in enumerate(zip(left, right)):
            differences(a, b, limit, path + f'[{index}]', output)
            if len(output) >= limit:
                break
    else:
        output.append(path + ' [value differs]')
    return output


def painting_keys(record):
    strings = set()
    def visit(value):
        if isinstance(value, dict):
            for item in value.values(): visit(item)
        elif isinstance(value, list):
            for item in value: visit(item)
        elif isinstance(value, str):
            strings.add(value)
    visit(record)
    for asset in record['model']['assets']:
        if asset['kind'] == 'model': strings.add('draft:' + asset['id'])
    return {hashlib.sha256((record['id'] + ':' + suffix).encode()).hexdigest() + '.json': suffix for suffix in strings}


def compare_model(record, built, registered_source, candidate_source):
    cached_normal = normalized_model(record['model'], registered_source)
    built_normal = normalized_model(built, candidate_source)
    by_name = {a['name']: a for a in record['model']['assets']}
    built_by_name = {a['name']: a for a in built['assets']}
    return {'compilePassed': True, 'normalizedModelEqual': cached_normal == built_normal,
        'cacheNormalizedSHA256': digest(cached_normal), 'sourceNormalizedSHA256': digest(built_normal),
        'topLevelEqual': {k: cached_normal.get(k) == built_normal.get(k) for k in sorted(set(cached_normal) | set(built_normal))},
        'pageMismatchIDs': sorted(k for k in set(cached_normal['pages']) | set(built_normal['pages']) if cached_normal['pages'].get(k) != built_normal['pages'].get(k)),
        'differencePaths': differences(cached_normal, built_normal),
        'assetsMissingInSource': sorted(set(by_name) - set(built_by_name)), 'assetsOnlyInSource': sorted(set(built_by_name) - set(by_name)),
        'assetBytesChanged': sorted(name for name in set(by_name) & set(built_by_name) if by_name[name].get('sha256') != built_by_name[name].get('sha256'))}


def audit(args):
    coverage = json.loads(args.coverage.read_text())
    compiler = None
    if args.compile:
        sys.dont_write_bytecode = True
        sys.path.insert(0, str(args.engine / 'bridge'))
        compiler = importlib.import_module('compiler')
    candidates = {}
    for source in (p.resolve() for p in args.candidate):
        app = json.loads((source / 'app.json').read_text())
        candidates.setdefault(app['id'], []).append(source)
    results = []
    for entry in coverage['projects']:
        if not entry.get('hasDeclaredContent'):
            continue
        folder = args.engine / 'Workspace' / entry['id']
        record, raw, proof = read_record(folder / 'record.json')
        source = Path(record['source'])
        project_root = source.parent.parent if source.name == 'HTML' and source.parent.name == 'HTMLNativeStudio' else source
        assets, unique = [], {}
        for asset in record['model']['assets']:
            file = asset['file']
            if file not in unique:
                unique[file] = fingerprint(within(folder / 'assets', file))
            assets.append({'name': asset['name'], 'id': asset['id'], 'file': file, 'kind': asset['kind'], 'declaredSHA256': asset.get('sha256'), 'matchesDeclaredBytes': asset.get('sha256') == unique[file]['sha256']})
        keys = painting_keys(record)
        paintings = [{**fingerprint(file), 'relative': str(file.relative_to(folder)), 'keyResolvable': file.name in keys, 'currentDraftKey': keys.get(file.name, '').startswith('draft:')} for file in sorted((folder / 'paintings').glob('*.json'))]
        item = {'id': record['id'], 'name': record['model']['name'], 'record': proof,
                'registeredSource': str(source), 'registeredSourceExists': source.is_dir(), 'originalProjectRoot': str(project_root), 'originalProjectRootExists': project_root.is_dir(),
                'modelHash': record['model']['hash'], 'modelSHA256': digest(record['model']),
                'componentSHA256': {k: digest(record.get(k)) for k in ('sessions', 'overrides', 'additions', 'conflicts', 'effectAcks', 'runtimeMode')},
                'pageCount': len(record['model']['pages']), 'overrideCount': len(record.get('overrides', {})), 'assetEntryCount': len(assets), 'cachedUniqueAssetCount': len(unique),
                'cachedAssetBytes': sum(v['size'] for v in unique.values()), 'cachedAssetIntegrity': all(a['matchesDeclaredBytes'] for a in assets),
                'assets': assets, 'cachedFiles': list(unique.values()), 'paintings': paintings, 'sourceCandidates': [],
                'renderableSnapshotVerified': False, 'runtimeValidation': 'not performed'}
        possible = ([source] if (source / 'app.json').is_file() else []) + candidates.get(record['model']['id'], [])
        for possible_source in dict.fromkeys(possible):
            candidate = {'path': str(possible_source), 'registered': possible_source == source}
            try:
                app, catalog, files = source_inventory(possible_source)
                candidate.update({'appID': app['id'], 'name': app['name'], 'pageCount': len(app['pages']), 'catalogEntries': len(catalog), 'inputFiles': files, 'inputBytes': sum(f['size'] for f in files)})
                if compiler:
                    built = compiler.compile_project(possible_source)
                    candidate.update(compare_model(record, built, source, possible_source))
                else:
                    candidate['compilePassed'] = None
            except Exception as error:
                candidate['error'] = str(error)
                candidate['compilePassed'] = False
            if compiler and not candidate.get('normalizedModelEqual'):
                # Explicit diagnostic variant: replace only load(catalog) in
                # memory, with the exact CURRENT record declarations. The
                # original source still remains failed/different above.
                overlay = {'kind': 'current-record-catalog-and-cache-assets', 'originalSourcePassed': candidate.get('normalizedModelEqual', False)}
                actual_load, actual_safe, actual_metadata = compiler.load, compiler.safe, compiler.asset_metadata
                replacement = [{'id': a['name'], 'path': a['source'], 'kind': a['kind']} for a in record['model']['assets']]
                target_catalog = (possible_source / 'assets/catalog.json').resolve()
                try:
                    cached_assets = {a['source']: folder / 'assets' / a['file'] for a in record['model']['assets']}
                    app, _, inputs = source_inventory(possible_source, replacement, cached_assets)
                    routes = {str(within(possible_source, relative).resolve()): cache for relative, cache in cached_assets.items()}
                    class CacheBackedPath(type(Path())):
                        # The compiler's declaration/extra-file checks retain
                        # the candidate's logical path. Stat/hash/decode read
                        # verified current Workspace bytes instead, read-only.
                        def stat(self, *, follow_symlinks=True):
                            return routes[str(self)].stat()
                    def overlay_safe(root, relative):
                        logical = within(root, relative).resolve()
                        return CacheBackedPath(logical) if str(logical) in routes else actual_safe(root, relative)
                    compiler.load = lambda path: copy.deepcopy(replacement) if Path(path).resolve() == target_catalog else actual_load(path)
                    compiler.safe = overlay_safe
                    compiler.asset_metadata = lambda path, kind, stamp: actual_metadata(str(routes.get(str(Path(path).resolve()), Path(path))), kind, stamp)
                    built = compiler.compile_project(possible_source)
                    overlay.update(compare_model(record, built, source, possible_source))
                    overlay.update({'catalog': replacement, 'inputFiles': inputs, 'inputBytes': sum(f['size'] for f in inputs),
                                    'candidateMissingAssetPaths': sorted(relative for relative in cached_assets if not within(possible_source, relative).is_file()),
                                    'allAssetBytesFromCurrentWorkspace': True})
                except Exception as error:
                    overlay.update({'compilePassed': False, 'error': str(error)})
                finally:
                    compiler.load, compiler.safe, compiler.asset_metadata = actual_load, actual_safe, actual_metadata
                candidate['recordCatalogOverlay'] = overlay
            item['sourceCandidates'].append(candidate)
        if fingerprint(folder / 'record.json')['sha256'] != proof['sha256']:
            raise ValueError('Record changed during audit: ' + record['id'])
        item['eligibleSource'] = next((s['path'] for s in item['sourceCandidates'] if s.get('normalizedModelEqual') and item['cachedAssetIntegrity']), None)
        item['eligibleReconstruction'] = next((s['path'] for s in item['sourceCandidates'] if s.get('recordCatalogOverlay', {}).get('normalizedModelEqual') and item['cachedAssetIntegrity']), None)
        results.append(item)
        print(json.dumps({k: item[k] for k in ('name', 'pageCount', 'assetEntryCount', 'cachedUniqueAssetCount', 'cachedAssetBytes', 'cachedAssetIntegrity', 'eligibleSource')}, ensure_ascii=False), flush=True)
    report = {'schema': 'studio-current-qa-inputs/1', 'generatedAt': datetime.datetime.now().astimezone().isoformat(), 'engineRoot': str(args.engine),
              'coverageSHA256': fingerprint(args.coverage)['sha256'], 'compilerSourceSHA256': fingerprint(args.engine / 'bridge/compiler.py')['sha256'],
              'projects': results, 'limitations': ['No project imported, activated or edited; no simulator or Codex project was created.',
                'Only the current Workspace record and cached asset bytes identify the saved workbench state.',
                'Registered HTML source existence and native project root existence are separate facts.',
                'Compile equality normalizes only diagnostic absolute source paths and derived model hash; no UI differences are ignored.',
                'Sessions and iOS overrides are fingerprinted here; complete copies are staged only by explicit materialize.',
                'Unresolved painting keys remain preserved as bytes but cannot yet be proven reachable after changing project ID.',
                'An offline compile pass is not actual workbench performance or appearance validation.']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


def clone_independent(source, dest, expected):
    if fingerprint(source)['sha256'] != expected['sha256']:
        raise ValueError(f'Input changed since audit: {source}')
    dest.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform != 'darwin':
        raise ValueError('APFS clonefile is required; no hard-link/full-copy fallback')
    library = ctypes.CDLL(None, use_errno=True)
    clone = library.clonefile
    clone.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    clone.restype = ctypes.c_int
    if clone(os.fsencode(source), os.fsencode(dest), 0):
        errno = ctypes.get_errno()
        raise OSError(errno, os.strerror(errno), str(dest))
    if os.path.samestat(source.stat(), dest.stat()):
        raise ValueError('Clone must have an independent inode')
    if fingerprint(source)['sha256'] != expected['sha256'] or fingerprint(dest)['sha256'] != expected['sha256']:
        raise ValueError('Clone byte validation failed')
    dest.chmod(stat.S_IRUSR)  # Safe only after independent-inode verification.


def materialize(args):
    report = json.loads(args.audit.read_text())
    selected = [p for p in report['projects'] if p['name'] in args.name]
    if len(selected) != len(set(args.name)):
        raise ValueError('Every requested name must match an audited content project')
    if any(not (p['eligibleSource'] or p.get('eligibleReconstruction')) for p in selected):
        raise ValueError('Missing source or compile/model mismatch: no inferred/placeholder source allowed')
    destination = args.destination.resolve()
    original_roots = [Path(p[key]).resolve() for p in report['projects'] for key in ('registeredSource', 'originalProjectRoot')]
    original_roots += [Path(c['path']).resolve() for p in report['projects'] for c in p['sourceCandidates']]
    if args.destination.exists() or not destination.is_relative_to((ROOT / 'artifacts').resolve()) or any(destination.is_relative_to(p) for p in original_roots):
        raise ValueError('Destination must be new under maintenance artifacts, outside every original source/root/Trash candidate')
    args.destination = destination
    records = {p['id']: read_record(Path(p['record']['path'])) for p in selected}
    for p in selected:
        if records[p['id']][2]['sha256'] != p['record']['sha256']:
            raise ValueError('Live record changed; run a fresh audit first')
    required = sum(p['record']['size'] * 2 + sum(f['size'] for f in p['paintings']) for p in selected) + 256 * 1024 * 1024
    parent = args.destination.parent
    available = os.statvfs(parent).f_bavail * os.statvfs(parent).f_frsize
    if available < required:
        raise ValueError('Insufficient metadata/state headroom; no cleanup is performed by this script')
    args.destination.mkdir()
    mapping = []
    for item in selected:
        original, raw, _ = records[item['id']]
        fixture = str(uuid.uuid4())
        folder = args.destination / 'Workspace' / fixture
        source = args.destination / 'Sources' / fixture
        chosen_path = item['eligibleSource'] or item.get('eligibleReconstruction')
        chosen = next(c for c in item['sourceCandidates'] if c['path'] == chosen_path)
        overlay = chosen.get('recordCatalogOverlay') if not item['eligibleSource'] else None
        chosen_inputs = overlay['inputFiles'] if overlay else chosen['inputFiles']
        cached_by_name = {Path(f['path']).name: f for f in item['cachedFiles']}
        declared_by_source = {a['source']: cached_by_name[a['file']] for a in original['model']['assets']}
        byte_mapping = []
        for file in chosen_inputs:
            if overlay and file['relative'] == 'assets/catalog.json':
                if fingerprint(Path(file['path']))['sha256'] != file['sha256']: raise ValueError('Candidate catalog changed since audit')
                target = source / file['relative'];target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(json.dumps(overlay['catalog'], ensure_ascii=False, indent=2) + '\n')
                byte_mapping.append({'relative': file['relative'], 'sourceKind': 'current-record-catalog-only', 'sha256': fingerprint(target)['sha256']})
                continue
            current_bytes = declared_by_source.get(file['relative'], file)
            clone_independent(Path(current_bytes['path']), within(source, file['relative']), current_bytes)
            byte_mapping.append({'relative': file['relative'], 'sourcePath': current_bytes['path'], 'sha256': current_bytes['sha256'], 'sourceKind': 'current-workspace-asset' if file['relative'] in declared_by_source else 'candidate-source-text'})
        for file in item['cachedFiles']:
            clone_independent(Path(file['path']), folder / 'assets' / Path(file['path']).name, file)
        keys = painting_keys(original)
        for file in item['paintings']:
            origin = Path(file['path'])
            clone_independent(origin, folder / 'paintings' / origin.name, file)
            if origin.name in keys:
                name = hashlib.sha256((fixture + ':' + keys[origin.name]).encode()).hexdigest() + '.json'
                clone_independent(origin, folder / 'paintings' / name, file)
        provenance = folder / 'qa-provenance'
        provenance.mkdir(parents=True)
        (provenance / 'original-record.json').write_bytes(raw)
        (provenance / 'source-byte-map.json').write_text(json.dumps(byte_mapping, ensure_ascii=False, indent=2) + '\n')
        record = copy.deepcopy(original)
        record['id'], record['source'] = fixture, str(source)
        def rebase(value):
            if isinstance(value, dict):
                location = value.get('source')
                if isinstance(location, dict) and isinstance(location.get('file'), str):
                    old = str(Path(original['source'])).rstrip('/') + '/'
                    if location['file'].startswith(old): location['file'] = str(source) + '/' + location['file'][len(old):]
                for x in value.values(): rebase(x)
            elif isinstance(value, list):
                for x in value: rebase(x)
        rebase(record)
        record['model'].pop('hash', None)
        record['model']['hash'] = hashlib.sha256(json.dumps(record['model'], sort_keys=True).encode()).hexdigest()
        record.pop('localNavigationReceipts', None)
        (folder / 'record.json').write_text(json.dumps(record, ensure_ascii=False, separators=(',', ':')))
        mapping.append({'name': item['name'], 'originProjectID': item['id'], 'fixtureProjectID': fixture, 'source': str(source), 'workspace': str(folder), 'originalRecordSHA256': item['record']['sha256'], 'identityAdjustments': ['record.id', 'record.source', 'source.file diagnostics', 'derived model.hash', 'remove identity-bound localNavigationReceipts'], 'sessionsEqual': record['sessions'] == original['sessions'], 'unresolvedPaintingKeys': sum(not f['keyResolvable'] for f in item['paintings'])})
        if fingerprint(Path(item['record']['path']))['sha256'] != item['record']['sha256']:
            raise ValueError('Original record changed during staging; staged data is not an accepted fresh snapshot')
    (args.destination / 'fixtures.json').write_text(json.dumps({'audit': str(args.audit), 'auditSHA256': fingerprint(args.audit)['sha256'], 'registered': False, 'activated': False, 'projects': mapping}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'stagedOnly': True, 'projectCount': len(mapping), 'path': str(args.destination)}, ensure_ascii=False))


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    inspect = commands.add_parser('audit')
    inspect.add_argument('--engine', type=Path, default=DEFAULT_ENGINE)
    inspect.add_argument('--coverage', type=Path, default=ROOT / 'artifacts/performance-pipeline-0930/project-coverage.json')
    inspect.add_argument('--candidate', type=Path, action='append', default=[])
    inspect.add_argument('--compile', action='store_true', help='Offline compiler only; never starts Studio/simulators or imports a project')
    inspect.add_argument('--output', type=Path, required=True)
    stage = commands.add_parser('materialize')
    stage.add_argument('--audit', type=Path, required=True)
    stage.add_argument('--name', action='append', required=True)
    stage.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'audit': audit(args)
    else: materialize(args)


if __name__ == '__main__':
    main()

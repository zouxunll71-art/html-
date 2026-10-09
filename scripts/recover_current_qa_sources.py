#!/usr/bin/env python3
"""Create isolated, strictly recompilable QA sources from current saved records.

No project registration, activation, Codex API, device operation or original-source
write. Reconstruction accepts only fields with an exact compiler representation.
The original record, source/asset hashes and full-model comparison are preserved.
"""
import argparse
import copy
import datetime
from decimal import Decimal
import hashlib
import html
import importlib
import json
import os
from pathlib import Path
import sys
import uuid

from current_workbench_snapshot import (ROOT, DEFAULT_ENGINE, clone_independent,
    compare_model, digest, fingerprint, painting_keys, read_record, within)

TAGS = {'container': 'ui-column', 'scroll': 'ui-scroll', 'text': 'ui-text',
    'image': 'ui-image', 'nativeButton': 'ui-button', 'nativeTextField': 'ui-input',
    'nativeTextView': 'ui-textarea', 'nativeSwitch': 'ui-switch',
    'nativeCheckbox': 'ui-checkbox', 'nativeSlider': 'ui-slider',
    'nativeProgress': 'ui-progress', 'nativeSpinner': 'ui-spinner',
    'nativeSegment': 'ui-segment', 'nativeStepper': 'ui-stepper',
    'path': 'ui-path', 'model': 'ui-model'}
STRING_ATTRS = {'name', 'asset', 'font', 'action', 'bind', 'key', 'group',
    'component', 'placeholder', 'text-key', 'placeholder-key', 'symbol',
    'semantic', 'placement', 'model-asset', 'analysis-action'}
JSON_ATTRS = {'when', 'repeat', 'disabled', 'spans', 'options', 'styles',
    'gradient', 'shadow', 'content', 'option-keys', 'text-args', 'selected',
    'points', 'profile', 'angle', 'elevation', 'closed', 'paint-options',
    'runtime-only'}
STRUCTURAL = {'id', 'type', 'style', 'children', 'text', 'source'}
MODEL_FIELDS = {'protocol', 'id', 'name', 'entry', 'viewport', 'state',
    'stateVersion', 'pages', 'actions', 'assets', 'localization', 'ios',
    'navigation', 'links', 'hash'}
COMPONENT_FIELDS = ('sessions', 'overrides', 'additions', 'conflicts', 'effectAcks', 'runtimeMode')


def number(value):
    if type(value) not in (int, float):
        raise ValueError('Expected finite numeric field')
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError('Nonfinite numeric field')
    return format(result, 'f')


def serialize_page(page):
    """Retain all parsed fields and original opening-tag line positions."""
    parts, line = [], 1
    source_file = page['root']['source']['file']

    def emit(value):
        nonlocal line
        parts.append(value)
        line += value.count('\n')

    def visit(node, root=False):
        if set(node['source']) != {'file', 'line'} or node['source']['file'] != source_file:
            raise ValueError('Mixed/component diagnostic locations require explicit reconstruction')
        expected_line = node['source']['line']
        if type(expected_line) is not int or expected_line < line:
            raise ValueError('Source line positions cannot be represented exactly')
        emit('\n' * (expected_line - line))
        if root and node['type'] != 'container':
            raise ValueError('Root must be a container')
        tag = 'ui-page' if root else TAGS[node['type']]
        attrs = {'id': node['id']}
        if node['style']:
            attrs['style'] = ';'.join(k + ':' + (number(v) if type(v) in (int, float) else v)
                for k, v in node['style'].items())
        for key, value in node.items():
            if key in STRUCTURAL:
                continue
            if key in STRING_ATTRS:
                if not isinstance(value, str): raise ValueError('Expected string attribute: ' + key)
                attrs[key] = value
            elif key in JSON_ATTRS:
                attrs[key] = json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
            elif key == 'inputType':
                attrs['input-type'] = value
            elif key in {'min', 'max', 'step'}:
                attrs[key] = number(value)
            else:
                raise ValueError('Unrepresentable node field: ' + key)
        emit('<' + tag + ' ' + ' '.join(k + '="' + html.escape(v, quote=True) + '"'
             for k, v in attrs.items()) + '>')
        # Numeric newline entities keep text exact without moving tag lines.
        emit(html.escape(node['text'], quote=False).replace('\r', '&#13;').replace('\n', '&#10;'))
        for child in node['children']:
            visit(child)
        emit('</' + tag + '>')

    visit(page['root'], True)
    return ''.join(parts) + '\n'


def source_documents(model, original_source):
    if set(model) != MODEL_FIELDS:
        raise ValueError('Unknown/missing model fields: ' + str(set(model) ^ MODEL_FIELDS))
    documents = {}

    def put(relative, data, origin):
        within(Path('/QA-SOURCE'), relative)
        if relative in documents:
            raise ValueError('Duplicate source output path: ' + relative)
        documents[relative] = {'bytes': data.encode(), 'origin': origin}

    def put_json(relative, data, origin):
        put(relative, json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n', origin)

    app = {k: copy.deepcopy(model[k]) for k in ['protocol', 'id', 'name', 'entry',
        'viewport', 'state', 'stateVersion', 'ios', 'navigation', 'links']}
    # Null optional fields mean absent in the author's app configuration.
    for key in ('ios', 'navigation'):
        if app[key] is None: del app[key]
    app['pages'] = []
    for page_id, page in model['pages'].items():
        declaration = {k: copy.deepcopy(v) for k, v in page.items() if k != 'root'}
        if declaration['id'] != page_id:
            raise ValueError('Mismatched page identity')
        expected = str(within(Path(original_source), declaration['html']))
        if page['root']['source']['file'] != expected:
            raise ValueError('Page diagnostic file differs from declared HTML')
        put(declaration['html'], serialize_page(page), '$.model.pages.' + page_id + '.root')
        if declaration.get('css'):
            put(declaration['css'], '', '$.model.pages.' + page_id + '.root.style (inlined losslessly)')
        app['pages'].append(declaration)
    if model['actions'].get('$dismiss') != [{'type': 'dismiss'}]:
        raise ValueError('Unexpected compiler-provided dismiss action')
    app['actions'] = ['qa-actions.json']
    put_json('qa-actions.json', {k: v for k, v in model['actions'].items() if k != '$dismiss'}, '$.model.actions')
    if model['localization'] is not None:
        spec = model['localization']
        if set(spec) != {'default', 'tables'}: raise ValueError('Unexpected localization fields')
        files = {locale: 'qa-localization/' + locale + '.json' for locale in spec['tables']}
        app['localization'] = {'default': spec['default'], 'files': files}
        for locale, table in spec['tables'].items():
            put_json(files[locale], table, '$.model.localization.tables.' + locale)
    put_json('assets/catalog.json', [{'id': a['name'], 'path': a['source'], 'kind': a['kind']}
        for a in model['assets']], '$.model.assets')
    put_json('app.json', app, '$.model configuration')
    return documents


def rebase_diagnostics(value, old_source, new_source):
    if isinstance(value, dict):
        location = value.get('source')
        if isinstance(location, dict) and isinstance(location.get('file'), str):
            prefix = str(old_source).rstrip('/') + '/'
            if location['file'].startswith(prefix):
                location['file'] = str(new_source) + '/' + location['file'][len(prefix):]
        for child in value.values(): rebase_diagnostics(child, old_source, new_source)
    elif isinstance(value, list):
        for child in value: rebase_diagnostics(child, old_source, new_source)


def component_evidence(original, record):
    changes, raw_equal, normalized_equal, normalized_hashes = [], {}, {}, {}

    def difference(a, b, path):
        if a == b: return
        if isinstance(a, dict) and isinstance(b, dict) and set(a) == set(b):
            for key in a: difference(a[key], b[key], path + [key])
        elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
            for index, (left, right) in enumerate(zip(a, b)): difference(left, right, path + [index])
        else:
            prefix = str(original['source']).rstrip('/') + '/'
            if path[-2:] != ['source', 'file'] or not isinstance(a, str) or not a.startswith(prefix):
                raise ValueError('Non-diagnostic component change: ' + repr(path))
            expected = str(record['source']).rstrip('/') + '/' + a[len(prefix):]
            if b != expected: raise ValueError('Unexpected diagnostic relocation')
            pointer = '/' + '/'.join(str(p).replace('~', '~0').replace('/', '~1') for p in path)
            changes.append({'jsonPointer': pointer, 'original': a, 'fixture': b})

    for key in COMPONENT_FIELDS:
        a, b = original.get(key), record.get(key)
        raw_equal[key] = a == b
        difference(a, b, [key])
        na, nb = copy.deepcopy(a), copy.deepcopy(b)
        rebase_diagnostics(na, original['source'], '<SOURCE>')
        rebase_diagnostics(nb, record['source'], '<SOURCE>')
        normalized_equal[key] = na == nb
        if not normalized_equal[key]: raise ValueError('Normalized component differs: ' + key)
        normalized_hashes[key] = {'original': digest(na), 'fixture': digest(nb)}
    return {'rawEqual': raw_equal, 'normalizedEqual': normalized_equal,
        'normalization': 'only source.file absolute root; no geometry, style, content or session normalization',
        'normalizedSHA256': normalized_hashes, 'diagnosticChanges': changes}


def create_one(record_path, destination, compiler):
    original, raw, original_proof = read_record(record_path)
    origin_folder = record_path.parent
    fixture_id = str(uuid.uuid4())
    source = destination / 'Sources' / fixture_id
    workspace = destination / 'Workspace' / fixture_id
    provenance = workspace / 'qa-provenance'
    source.mkdir(parents=True)
    provenance.mkdir(parents=True)
    (provenance / 'original-record.json').write_bytes(raw)
    # Inventory and generated source mapping carry hashes, not borrowed old models.
    source_map, asset_map, cache_proof = [], [], {}
    documents = source_documents(original['model'], original['source'])
    for relative, item in documents.items():
        target = within(source, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(item['bytes'])
        source_map.append({'relative': relative, 'kind': 'current-record-reconstruction',
            'recordJSONPath': item['origin'], **fingerprint(target)})
    source_assets = {}
    for asset in original['model']['assets']:
        filename, relative = asset['file'], asset['source']
        cached = within(origin_folder / 'assets', filename)
        if filename not in cache_proof:
            cache_proof[filename] = fingerprint(cached)
        proof = cache_proof[filename]
        if proof['sha256'] != asset['sha256']:
            raise ValueError('Current cached asset differs from recorded bytes: ' + filename)
        if relative in documents:
            raise ValueError('Asset collides with generated text: ' + relative)
        if relative in source_assets:
            if source_assets[relative] != proof['sha256']:
                raise ValueError('Two declarations conflict on source bytes')
        else:
            clone_independent(cached, within(source, relative), proof)
            source_assets[relative] = proof['sha256']
            source_map.append({'relative': relative, 'kind': 'current-workspace-asset',
                'sourcePath': str(cached), 'sha256': proof['sha256'], 'size': proof['size']})
        asset_map.append({'name': asset['name'], 'source': relative, 'file': filename,
            'sha256': proof['sha256'], 'size': proof['size']})
    for filename, proof in cache_proof.items():
        clone_independent(Path(proof['path']), within(workspace / 'assets', filename), proof)
    painting_map = []
    keys = painting_keys(original)
    for original_file in sorted((origin_folder / 'paintings').glob('*.json')):
        proof = fingerprint(original_file)
        clone_independent(original_file, workspace / 'paintings' / original_file.name, proof)
        new_name = None
        if original_file.name in keys:
            new_name = hashlib.sha256((fixture_id + ':' + keys[original_file.name]).encode()).hexdigest() + '.json'
            clone_independent(original_file, workspace / 'paintings' / new_name, proof)
        painting_map.append({**proof, 'fixtureName': new_name, 'keyResolvable': new_name is not None})
    # Compile ordinary files, with no compiler monkeypatch or injected model.
    built = compiler.compile_project(source)
    comparison = compare_model(original, built, Path(original['source']), source)
    (provenance / 'compile-comparison.json').write_text(json.dumps(comparison, ensure_ascii=False, indent=2) + '\n')
    if not comparison['normalizedModelEqual']:
        raise ValueError('Reconstructed compile differs: ' + json.dumps(comparison['differencePaths']))
    record = copy.deepcopy(original)
    record['id'], record['source'] = fixture_id, str(source)
    rebase_diagnostics(record, original['source'], source)
    record['model'] = built
    record.pop('localNavigationReceipts', None)
    components = component_evidence(original, record)
    if fingerprint(record_path)['sha256'] != original_proof['sha256']:
        raise ValueError('Original record changed during recovery; do not use this snapshot')
    (workspace / 'record.json').write_text(json.dumps(record, ensure_ascii=False, separators=(',', ':')))
    (provenance / 'source-byte-map.json').write_text(json.dumps(source_map, ensure_ascii=False, indent=2) + '\n')
    (provenance / 'asset-byte-map.json').write_text(json.dumps(asset_map, ensure_ascii=False, indent=2) + '\n')
    (provenance / 'component-preservation.json').write_text(json.dumps(components, ensure_ascii=False, indent=2) + '\n')
    proof = {'name': original['model']['name'], 'originProjectID': original['id'],
        'fixtureProjectID': fixture_id, 'source': str(source), 'workspace': str(workspace),
        'originalRecord': original_proof, 'fixtureRecord': fingerprint(workspace / 'record.json'),
        'pageCount': len(built['pages']), 'assetEntryCount': len(built['assets']),
        'cachedUniqueAssetCount': len(cache_proof),
        'cachedAssetBytes': sum(p['size'] for p in cache_proof.values()),
        'compileModelEqual': comparison['normalizedModelEqual'],
        'normalizedModelSHA256': comparison['cacheNormalizedSHA256'],
        'allowedDifferences': ['record.id', 'record.source', 'diagnostic source.file absolute root',
            'model.hash derived from diagnostic root', 'identity-bound localNavigationReceipts omitted']
            + [c['jsonPointer'] for c in components['diagnosticChanges']],
        'businessAppIDAndNameUnchanged': built['id'] == original['model']['id'] and built['name'] == original['model']['name'],
        'componentPreservation': components['normalizedEqual'],
        'componentPreservationMeaning': components['normalization'],
        'componentRawEqual': components['rawEqual'],
        'componentNormalizedSHA256': components['normalizedSHA256'],
        'componentDiagnosticRelocationCount': len(components['diagnosticChanges']),
        'componentOriginalSHA256': {k: digest(original.get(k)) for k in COMPONENT_FIELDS},
        'componentFixtureSHA256': {k: digest(record.get(k)) for k in COMPONENT_FIELDS},
        'paintings': painting_map, 'unresolvedPaintingKeys': sum(not p['keyResolvable'] for p in painting_map),
        'reconstruction': 'current record only; ordinary full compiler; assets byte-identical APFS clones',
        'registered': False, 'activated': False, 'deviceStarted': False}
    (provenance / 'provenance.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    return proof


def main():
    os.umask(0o077)
    sys.dont_write_bytecode = True
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--engine', type=Path, default=DEFAULT_ENGINE)
    parser.add_argument('--coverage', type=Path, default=ROOT / 'artifacts/performance-pipeline-0930/project-coverage.json')
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists() or not destination.is_relative_to((ROOT / 'artifacts').resolve()):
        raise ValueError('Destination must be a new directory under maintenance artifacts')
    if os.statvfs(destination.parent).f_bavail * os.statvfs(destination.parent).f_frsize < 1024 ** 3:
        raise ValueError('At least 1 GiB metadata/state headroom required')
    entries = [p for p in json.loads(args.coverage.read_text())['projects'] if p.get('hasDeclaredContent')]
    order = ['CampByte', 'PitCrew', 'PAWHOUSE', 'DEARYOU', 'CLAYDAY', 'Character Home · 单页复刻测试']
    entries.sort(key=lambda p: order.index(p['name']) if p['name'] in order else 100)
    sys.path.insert(0, str(args.engine / 'bridge'))
    compiler = importlib.import_module('compiler')
    destination.mkdir()
    manifest = {'schema': 'current-record-source-recovery/1',
        'createdAt': datetime.datetime.now().astimezone().isoformat(),
        'generatorSHA256': fingerprint(Path(__file__))['sha256'],
        'compilerSHA256': fingerprint(args.engine / 'bridge/compiler.py')['sha256'],
        'engine': str(args.engine), 'registered': False, 'activated': False, 'projects': []}
    def save():
        (destination / 'fixtures.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    save()
    for entry in entries:
        proof = create_one(args.engine / 'Workspace' / entry['id'] / 'record.json', destination, compiler)
        manifest['projects'].append(proof)
        save()
        print(json.dumps({k: proof[k] for k in ('name', 'fixtureProjectID', 'source', 'workspace',
            'pageCount', 'assetEntryCount', 'compileModelEqual', 'unresolvedPaintingKeys')}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()

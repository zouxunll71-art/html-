const E = require('../Shared/engine.js');
const rl = require('readline').createInterface({input: process.stdin});
const cachedModels = new Map();
// These are immutable results, never optimistic state. The complete session,
// model identity and iOS edits are part of the key, including clock and locale.
const frames = new Map();
let frameBytes = 0, frameNodes = 0;
function discardFrame(key) {
  const value = frames.get(key);
  frameBytes -= value.bytes; frameNodes -= value.nodes;
  frames.delete(key);
}
function discardModel(key) {
  for (const [id, value] of frames) if (value.modelKey === key) discardFrame(id);
}
function rendered(v, kind) {
  if (kind !== 'frame' && kind !== 'compose') throw Error('Unknown frame kind');
  const key = v.modelKey ? JSON.stringify([v.modelKey, kind, v.session, v.overrides || {}, kind === 'compose' ? v.additions || {} : null]) : null;
  if (key && frames.has(key)) {
    const hit = frames.get(key); frames.delete(key); frames.set(key, hit); return hit;
  }
  const value = kind === 'compose' ? E.compose(v.model, v.session, v.overrides, v.additions) : E.frame(v.model, v.session, v.overrides);
  const encoded = JSON.stringify({ok: value});
  const entry = {value, encoded, modelKey: v.modelKey, bytes: 2 * (encoded.length + (key?.length || 0)), nodes: value.nodes.length};
  // Bound entries, UTF-16 serialized storage and node count independently.
  // Very large state/frames still work, but do not occupy the shared cache.
  if (key && key.length <= 131072 && entry.bytes <= 2 * 1024 * 1024 && entry.nodes <= 2048) {
    frames.set(key, entry); frameBytes += entry.bytes; frameNodes += entry.nodes;
    while (frames.size > 32 || frameBytes > 8 * 1024 * 1024 || frameNodes > 4096) discardFrame(frames.keys().next().value);
  }
  return entry;
}
rl.on('line', line => {
  try {
    const v = JSON.parse(line);
    if (v.modelKey) {
      if (v.model) discardModel(v.modelKey);
      else v.model = cachedModels.get(v.modelKey);
      if (!v.model) throw Error('Model cache mismatch');
      cachedModels.delete(v.modelKey); cachedModels.set(v.modelKey, v.model);
      if (cachedModels.size > 16) {const key = cachedModels.keys().next().value; cachedModels.delete(key); discardModel(key);}
    }
    let result;
    if (v.op === 'forgetFrames') {discardModel(v.key); result = true;}
    else if (v.op === 'initial') result = E.initial(v.model, {now: Date.now(), offsetMinutes: new Date().getTimezoneOffset()});
    else if (v.op === 'event') result = E.reduce(v.model, v.session, v.event);
    else if (v.op === 'frame' || v.op === 'compose') {
      process.stdout.write(rendered(v, v.op).encoded + '\n'); return;
    } else if (v.op === 'interaction') {
      const page = rendered(v, v.kind).value;
      result = {pageID: page.id, declaration: typeof v.node === 'string' && Object.hasOwn(page.events, v.node) ? page.events[v.node] : null};
    } else if (v.op === 'editor') result = E.editorFrame(v.frame);
    else if (v.op === 'diff') result = E.applyEditor(v.frame, v.edit);
    else throw Error('Unknown operation');
    process.stdout.write(JSON.stringify({ok: result}) + '\n');
  } catch (e) {process.stdout.write(JSON.stringify({error: String(e)}) + '\n');}
});

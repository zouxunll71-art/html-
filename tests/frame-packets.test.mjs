import test from 'node:test';
import assert from 'node:assert/strict';
import {FramePackets} from '../frame-packets.mjs';

function packet(data) {
  const payload = Buffer.from(data), header = Buffer.alloc(4);
  header.writeUInt32BE(payload.length);
  return Buffer.concat([header, payload]);
}

test('every header and body split reconstructs the same immutable packet', () => {
  const original = packet('a simulator image with alpha and colour metadata');
  for (let split = 0; split <= original.length; split++) {
    const decoder = new FramePackets();
    const first = decoder.push(original.subarray(0, split));
    const second = decoder.push(original.subarray(split));
    const result = second || first;
    assert.deepEqual(result, original);
    decoder.push(packet('next frame'));
    assert.deepEqual(result, original);
    decoder.end();
  }
});

test('coalesced images deliver the latest complete frame and preserve a partial successor', () => {
  const a = packet('old'), b = packet('current'), c = packet('incoming');
  for (let split = 0; split < c.length; split++) {
    const decoder = new FramePackets();
    assert.deepEqual(decoder.push(Buffer.concat([a, b, c.subarray(0, split)])), b);
    assert.deepEqual(decoder.push(c.subarray(split)), c);
    decoder.end();
  }
});

test('random fragmentation and Uint8Array offsets preserve all bytes without sharing input storage', () => {
  const payload = Buffer.from(Array.from({length: 8193}, (_, i) => i % 256));
  const wire = packet(payload), decoder = new FramePackets();
  let seed = 17, result;
  for (let start = 0; start < wire.length;) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const end = Math.min(start + 1 + seed % 97, wire.length);
    const input = Uint8Array.from([0, ...wire.subarray(start, end), 0]);
    result = decoder.push(input.subarray(1, input.length - 1)) || result;
    input.fill(0);
    start = end;
  }
  assert.deepEqual(result, wire);
  decoder.end();
});

test('zero and oversized lengths fail before allocating a payload and cannot resume', () => {
  for (const size of [0, 21, 0xffffffff]) {
    const header = Buffer.alloc(4); header.writeUInt32BE(size);
    const decoder = new FramePackets(20);
    decoder.push(header.subarray(0, 3));
    assert.throws(() => decoder.push(header.subarray(3)), /Invalid frame/);
    assert.equal(decoder.packet, null);
    assert.throws(() => decoder.push(packet('ok')), /Invalid frame stream/);
  }
  const decoder = new FramePackets(20);
  assert.deepEqual(decoder.push(packet(Buffer.alloc(20))), packet(Buffer.alloc(20)));
});

test('EOF rejects incomplete headers and images; reconnect uses a fresh parser', () => {
  const wire = packet('image');
  for (let length = 1; length < wire.length; length++) {
    const decoder = new FramePackets();
    assert.equal(decoder.push(wire.subarray(0, length)), null);
    assert.throws(() => decoder.end(), /Truncated/);
    assert.equal(decoder.packet, null);
  }
  const decoder = new FramePackets();
  assert.equal(decoder.push(Buffer.alloc(0)), null);
  decoder.end();
  assert.deepEqual(new FramePackets().push(wire), wire);
});

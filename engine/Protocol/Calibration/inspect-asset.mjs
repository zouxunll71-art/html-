import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';

export function inspectAsset(buffer, { width, height, opaqueRegion } = {}) {
  const png = PNG.sync.read(buffer);
  for (const n of [width, height]) if (n !== undefined && (!Number.isSafeInteger(n) || n <= 0)) throw new Error('Expected dimensions must be positive integers');
  if (opaqueRegion && (opaqueRegion.length !== 4 || opaqueRegion.some(n => !Number.isSafeInteger(n)) || opaqueRegion[0] < 0 || opaqueRegion[1] < 0 || opaqueRegion[2] <= 0 || opaqueRegion[3] <= 0 || opaqueRegion[0] + opaqueRegion[2] > png.width || opaqueRegion[1] + opaqueRegion[3] > png.height)) throw new Error('Opaque region must lie within the image');
  const histogram = Array(256).fill(0);
  let minX = png.width, minY = png.height, maxX = -1, maxY = -1, nonOpaque = 0;
  for (let y = 0; y < png.height; y++) for (let x = 0; x < png.width; x++) {
    const alpha = png.data[(y * png.width + x) * 4 + 3];
    histogram[alpha]++;
    if (alpha > 0) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); }
    if (opaqueRegion && x >= opaqueRegion[0] && x < opaqueRegion[0] + opaqueRegion[2] && y >= opaqueRegion[1] && y < opaqueRegion[1] + opaqueRegion[3] && alpha < 255) nonOpaque++;
  }
  const dimensionsMatch = width === undefined && height === undefined ? null : (width === undefined || width === png.width) && (height === undefined || height === png.height);
  const warnings = [];
  if (dimensionsMatch === false) warnings.push('Requested and actual pixel dimensions differ');
  if (maxX < 0) warnings.push('Image is fully transparent');
  if (histogram[0] === 0) warnings.push('No fully transparent background pixels; check whether transparency is required');
  if (nonOpaque) warnings.push('Expected opaque region contains non-opaque pixels');
  return { actualWidth: png.width, actualHeight: png.height, requestedWidth: width ?? null, requestedHeight: height ?? null, dimensionsMatch, transparentPixels: histogram[0], opaquePixels: histogram[255], partialPixels: histogram.slice(1, 255).reduce((a,b) => a+b, 0), alphaHistogram: histogram, visibleBounds: maxX < 0 ? null : { x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1 }, opaqueRegion: opaqueRegion ?? null, nonOpaqueRegionPixels: opaqueRegion ? nonOpaque : null, warnings, visualStatus: 'not-verified' };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [input, ...args] = process.argv.slice(2);
    if (!input) throw new Error('Usage: inspect-asset.mjs image.png [--width N] [--height N] [--opaque-region x,y,w,h]');
    const options = {};
    for (let i = 0; i < args.length; i += 2) {
      const key = { '--width': 'width', '--height': 'height', '--opaque-region': 'opaqueRegion' }[args[i]];
      if (!key || args[i+1] === undefined || key in options) throw new Error('Invalid or duplicate option: '+args[i]);
      options[key] = key === 'opaqueRegion' ? args[i+1].split(',').map(Number) : Number(args[i+1]);
    }
    process.stdout.write(JSON.stringify(inspectAsset(fs.readFileSync(input), options), null, 2)+'\n');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

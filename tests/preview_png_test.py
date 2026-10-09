import hashlib
import random
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'engine/bridge'))
from asset_previews import PreviewRasters


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def paeth(a, b, c):
    p = a + b - c
    return min(((abs(p - a), a), (abs(p - b), b), (abs(p - c), c)), key=lambda v: v[0])[1]


def make_png(width=33, height=15, channels=4, extra=b'', depth=8, interlace=0):
    rng = random.Random(93)
    raw = bytes(rng.randrange(256) for _ in range(width * height * channels))
    rows = bytearray()
    stride = width * channels
    for y in range(height):
        f = y % 5
        rows.append(f)
        for x in range(stride):
            i = y * stride + x
            a = raw[i - channels] if x >= channels else 0
            b = raw[i - stride] if y else 0
            c = raw[i - stride - channels] if y and x >= channels else 0
            predictor = (0, a, b, (a + b) // 2, paeth(a, b, c))[f]
            rows.append((raw[i] - predictor) % 256)
    header = struct.pack('>IIBBBBB', width, height, depth, 6 if channels == 4 else 2, 0, 0, interlace)
    data = zlib.compress(rows)
    metadata = chunk(b'gAMA', struct.pack('>I', 45455)) + chunk(b'tEXt', b'Author\0Preview test')
    encoded = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + metadata + extra
    encoded += chunk(b'IDAT', data[:len(data)//2]) + chunk(b'IDAT', data[len(data)//2:]) + chunk(b'IEND', b'')
    return encoded, raw, metadata


def read_png(data):
    chunks = []
    offset = 8
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset+8])
        body = data[offset+8:offset+8+length]
        assert zlib.crc32(kind + body) == struct.unpack('>I', data[offset+8+length:offset+12+length])[0]
        chunks.append((kind, body))
        offset += length + 12
    return chunks


class FastPNG(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.helper = Path(cls.temp.name) / 'preview-png'
        subprocess.run(['xcrun', 'clang', '-O2', str(ROOT / 'engine/scripts/preview_png.c'), '-lz', '-o', str(cls.helper)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def convert(self, encoded, directory):
        source, dest = Path(directory)/'source.png', Path(directory)/'result.png'
        source.write_bytes(encoded)
        result = subprocess.run([str(self.helper), str(source), str(dest)])
        self.assertEqual(source.read_bytes(), encoded)
        return result.returncode, dest

    def test_every_filter_restores_exact_samples_alpha_and_metadata(self):
        for channels in (3, 4):
            with tempfile.TemporaryDirectory() as directory:
                encoded, raw, _ = make_png(channels=channels)
                code, dest = self.convert(encoded, directory)
                self.assertEqual(code, 0)
                before, after = read_png(encoded), read_png(dest.read_bytes())
                self.assertEqual([c for c in before if c[0] != b'IDAT'], [c for c in after if c[0] != b'IDAT'])
                rows = zlib.decompress(b''.join(b for k, b in after if k == b'IDAT'))
                stride = 33 * channels + 1
                self.assertEqual(set(rows[::stride]), {0})
                self.assertEqual(b''.join(rows[y*stride+1:(y+1)*stride] for y in range(15)), raw)

    def test_invalid_or_special_images_produce_no_cache(self):
        examples = [b'not png', make_png(depth=16)[0], make_png(interlace=1)[0],
                    make_png(extra=chunk(b'acTL', struct.pack('>II', 2, 0)))[0],
                    make_png(extra=chunk(b'eXIf', b'orientation'))[0],
                    make_png(extra=chunk(b'UNKN', b'critical'))[0],
                    make_png()[0][:-5], make_png()[0] + b'trailing']
        bad = bytearray(make_png()[0]); bad[30] ^= 1; examples.append(bytes(bad))
        for encoded in examples:
            with tempfile.TemporaryDirectory() as directory:
                code, dest = self.convert(encoded, directory)
                self.assertNotEqual(code, 0)
                self.assertFalse(dest.exists())

    def test_cache_preserves_size_and_pixels_and_invalidates_on_source_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source.png'
            # A large, simple PNG keeps this test inexpensive while exercising
            # the real subprocess, async cache publication and lossless path.
            width, height = 1000, 1000
            raw = (bytes([10, 100, 210, 128]) * width)
            encoded = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0'+raw)*height)) + chunk(b'IEND', b'')
            source.write_bytes(encoded); digest = hashlib.sha256(encoded).digest()
            cache = PreviewRasters(fast_png=self.helper)
            args = ('project', source, root/'cache', (0, 0), 'contain', lambda: True)
            try:
                value, ready = cache.resolve(*args, fast=True)
                self.assertEqual(value, source); self.assertFalse(ready)
                deadline = time.monotonic() + 10
                while cache.pending and time.monotonic() < deadline: time.sleep(.01)
                value, ready = cache.resolve(*args, fast=True)
                self.assertTrue(ready); self.assertNotEqual(value, source)
                chunks = read_png(value.read_bytes())
                self.assertEqual(zlib.decompress(b''.join(v for k, v in chunks if k == b'IDAT')), (b'\0'+raw)*height)
                self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), digest)
                source.touch()
                value, ready = cache.resolve(*args, fast=True)
                self.assertEqual(value, source); self.assertFalse(ready)
            finally: cache.close()

    def test_full_size_display_reuses_exact_rgb_rgba_fast_cache(self):
        for channels in (3, 4):
            with self.subTest(channels=channels), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); source = root/'source.png'
                width, height = 1000, 1000
                pixel = bytes([10, 100, 210, 128][:channels]); row = pixel * width
                # First row uses Sub; following identical rows use Paeth.
                filtered = b'\1' + pixel + bytes((width-1)*channels)
                filtered += (b'\4' + bytes(width*channels)) * (height-1)
                metadata = chunk(b'gAMA', struct.pack('>I', 45455))
                encoded = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2 if channels == 3 else 6, 0, 0, 0)) + metadata + chunk(b'IDAT', zlib.compress(filtered)) + chunk(b'IEND', b'')
                source.write_bytes(encoded)
                cache = PreviewRasters(fast_png=self.helper)
                display_args = ('project', source, root/'cache', (2048, 2048), 'cover')
                fast_args = ('project', source, root/'cache', (0, 0), 'contain')
                try:
                    # Disabled projects cannot schedule work; original fallback
                    # is not immutable because an exact derivative is pending.
                    self.assertEqual(cache.resolve(*display_args, lambda: False), (source, False))
                    self.assertFalse(cache.started)
                    self.assertEqual(cache.resolve(*display_args, lambda: True), (source, False))
                    deadline = time.monotonic() + 10
                    while cache.pending and time.monotonic() < deadline: time.sleep(.01)
                    display, ready = cache.resolve(*display_args, lambda: False)
                    self.assertTrue(ready); self.assertNotEqual(display, source)
                    fast, ready = cache.resolve(*fast_args, lambda: False, fast=True)
                    self.assertTrue(ready); self.assertEqual(display, fast)
                    self.assertEqual(len(list((root/'cache').glob('*.png'))), 1)
                    before, after = read_png(encoded), read_png(display.read_bytes())
                    self.assertEqual([c for c in before if c[0] != b'IDAT'], [c for c in after if c[0] != b'IDAT'])
                    self.assertEqual(zlib.decompress(b''.join(v for k, v in after if k == b'IDAT')), (b'\0'+row)*height)
                    self.assertEqual(source.read_bytes(), encoded)
                finally: cache.close()

    def test_full_size_display_does_not_expand_fast_eligibility(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'source.png'
            cache = PreviewRasters(fast_png=self.helper)
            try:
                for width, height, color, channels in ((999, 1000, 6, 4), (1000, 1000, 3, 1)):
                    metadata = chunk(b'PLTE', bytes([0, 0, 0])) if color == 3 else b''
                    source.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color, 0, 0, 0)) + metadata + chunk(b'IDAT', zlib.compress((b'\0'+bytes(width*channels))*height)) + chunk(b'IEND', b''))
                    self.assertEqual(cache.resolve('project', source, root/'cache', (2048, 2048), 'contain', lambda: True), (source, True))
                    self.assertFalse(cache.started)
                    self.assertFalse(cache.pending)
            finally: cache.close()


if __name__ == '__main__':
    unittest.main()

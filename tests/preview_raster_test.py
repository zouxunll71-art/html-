import hashlib
import struct
import sys
import tempfile
import threading
import time
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine/bridge'))
from asset_previews import PreviewRasters, png_size, target_edge, PNG


def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))


def png(path, width=1200, height=600, extra=b'', depth=8):
    # Transparent colored fixture exercises alpha without external libraries.
    row = b'\x00' + bytes([30, 100, 200, 128]) * width
    path.write_bytes(PNG + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, depth, 6, 0, 0, 0)) + extra + chunk(b'IDAT', zlib.compress(row * height)) + chunk(b'IEND', b''))


class Rasters(unittest.TestCase):
    def test_cover_requires_enough_pixels_in_both_axes(self):
        self.assertEqual(target_edge((2000, 1000), (200, 200), 'contain'), 256)
        self.assertEqual(target_edge((2000, 1000), (200, 200), 'cover'), 512)
        self.assertEqual(target_edge((2000, 1000), (200, 200), 'stretch'), 512)
        for box in ((9000, 20), (float('nan'), 20), (0, 20), (20,)):
            self.assertIsNone(target_edge((2000, 1000), box, 'contain'))
        self.assertIsNone(target_edge((100, 100), (200, 200), 'contain'))

    def test_animated_oriented_and_high_depth_png_use_originals(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'source.png'
            for extra, depth in ((chunk(b'acTL', struct.pack('>II', 2, 0)), 8), (chunk(b'eXIf', b'orientation'), 8), (b'', 16)):
                png(p, extra=extra, depth=depth)
                self.assertIsNone(png_size(p))
            p.write_bytes(b'not png')
            self.assertIsNone(png_size(p))

    def test_real_resize_and_source_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source.png';png(source)
            original=hashlib.sha256(source.read_bytes()).hexdigest();cache=PreviewRasters()
            try:
                args=('a',source,root/'cache',(100,100),'contain',lambda:True)
                first,ready=cache.resolve(*args)
                self.assertEqual(first,source);self.assertFalse(ready)
                deadline=time.monotonic()+10
                while cache.pending and time.monotonic()<deadline:time.sleep(.02)
                result,ready=cache.resolve(*args)
                self.assertTrue(ready);self.assertNotEqual(result,source)
                self.assertEqual(png_size(result,generated=True),(128,64))
                self.assertEqual(result.read_bytes()[25],6) # RGBA, not flattened RGB
                data=result.read_bytes();offset=8;compressed=b''
                while offset<len(data):
                    length,kind=struct.unpack('>I4s',data[offset:offset+8])
                    if kind==b'IDAT':compressed+=data[offset+8:offset+8+length]
                    offset+=12+length
                # At the first pixel all PNG filters have a zero predictor.
                self.assertEqual(zlib.decompress(compressed)[4],128)
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),original)
                png(source,1400,700)
                changed,ready=cache.resolve(*args)
                self.assertEqual(changed,source);self.assertFalse(ready)
            finally:cache.close()

    def test_disabled_projects_and_cancelled_jobs_do_not_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source.png';png(source)
            cache=PreviewRasters();started=threading.Event();stopped=threading.Event()
            class Slow:
                returncode=None
                def __init__(self,command,**kwargs):self.dest=Path(command[-1]);started.set()
                def wait(self,timeout=None):stopped.wait(3);self.returncode=-15;return self.returncode
                def terminate(self):stopped.set()
                def poll(self):return self.returncode
                def kill(self):stopped.set()
            try:
                args=('a',source,root/'cache',(100,100),'contain')
                cache.resolve(*args,lambda:False);self.assertFalse(cache.pending);self.assertFalse(cache.started)
                with patch('asset_previews.subprocess.Popen',Slow):
                    cache.resolve(*args,lambda:True);self.assertTrue(started.wait(2));cache.cancel('a')
                    deadline=time.monotonic()+3
                    while cache.pending and time.monotonic()<deadline:time.sleep(.01)
                self.assertFalse(cache.pending);self.assertFalse(list((root/'cache').glob('*.png')))
            finally:cache.close()

if __name__=='__main__':unittest.main()

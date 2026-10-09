"""Bounded, disposable display rasters. Never modify project/export resources."""
import atexit
import hashlib
import math
import queue
import struct
import subprocess
import threading
import time
import uuid
from collections import OrderedDict
from pathlib import Path

PNG = b'\x89PNG\r\n\x1a\n'


def png_size(source, generated=False):
    # Animated, oriented, high-bit-depth and unknown formats retain originals.
    if source.suffix.lower() != '.png':
        return None
    with source.open('rb') as stream:
        header = stream.read(33)
        if len(header) != 33 or header[:8] != PNG or header[12:16] != b'IHDR':
            return None
        width, height = struct.unpack('>II', header[16:24])
        if not (0 < width <= 32768 and 0 < height <= 32768) or width * height > 64_000_000 or header[24] != 8:
            return None
        while stream.tell() < 2 * 1024 * 1024:
            chunk = stream.read(8)
            if len(chunk) != 8:
                return None
            length, kind = struct.unpack('>I4s', chunk)
            if kind in (b'acTL', b'IEND') or (kind == b'eXIf' and not generated):
                return None
            if kind == b'IDAT':
                return width, height
            if length > 2 * 1024 * 1024:
                return None
            stream.seek(length + 4, 1)
    return None


def target_edge(size, box, fit):
    if fit not in ('contain', 'cover', 'stretch') or len(box) != 2:
        return None
    if any(not math.isfinite(v) or v <= 0 or v > 8192 for v in box):
        return None
    ratios = [box[0] / size[0], box[1] / size[1]]
    needed = max(size) * (min(ratios) if fit == 'contain' else max(ratios))
    edge = next((n for n in (128, 256, 512, 1024, 2048, 4096) if n >= needed), None)
    return edge if edge and edge < max(size) else None


class PreviewRasters:
    def __init__(self, fast_png=None):
        self.fast_png = fast_png or Path(__file__).resolve().parents[1] / 'build/preview-png'
        self.lock = threading.RLock()
        self.jobs = queue.Queue(maxsize=64)
        self.pending = set()
        self.generations = {}
        self.processes = {}
        self.headers = OrderedDict()
        self.failures = OrderedDict()
        self.started = False
        self.closed = False

    @staticmethod
    def stamp(source):
        stat = source.stat()
        return stat.st_ino, stat.st_size, stat.st_mtime_ns

    def resolve(self, project, source, cache, box, fit, enabled, fast=False):
        """Ready -> PNG; miss -> original immediately and optionally enqueue."""
        stamp = self.stamp(source)
        key = (str(source), stamp)
        with self.lock:
            if key not in self.headers:
                self.headers[key] = png_size(source)
                while len(self.headers) > 256:
                    self.headers.popitem(last=False)
            size = self.headers[key]
            self.headers.move_to_end(key)
        edge = target_edge(size, box, fit) if size and not fast else None
        # A display box that needs no downsampling still benefits from the
        # exact-sample cache. Use the same file/key as decode=fast, rather than
        # returning the filtered original under an immutable raster URL.
        if edge is None and size and 1_000_000 <= size[0] * size[1] <= 16_000_000:
            with source.open('rb') as stream:
                header = stream.read(33)
            if header[25] in (2, 6) and header[28] == 0:
                edge = 0  # Exact sample-preserving refilter, no resizing.
        if edge is None:
            return source, True
        digest = hashlib.sha256(repr((key, edge, 'fast-png-v1' if edge == 0 else 'display-png-v1')).encode()).hexdigest()
        dest = cache / (digest + '.png')
        with self.lock:
            if dest.is_file():
                return dest, True
            jobkey = (project, digest)
            if enabled() and not self.closed and jobkey not in self.pending and time.monotonic() >= self.failures.get(jobkey, 0):
                generation = self.generations.get(project, 0)
                try:
                    self.jobs.put_nowait((jobkey, generation, source, stamp, dest, edge))
                    self.pending.add(jobkey)
                except queue.Full:
                    pass
                if not self.started:
                    self.started = True
                    for _ in range(2):
                        threading.Thread(target=self._work, daemon=True).start()
        # Do not cache the fallback under the derivative URL.
        return source, False

    def cancel(self, project):
        with self.lock:
            self.generations[project] = self.generations.get(project, 0) + 1
            for key, process in list(self.processes.items()):
                if key[0] == project:
                    process.terminate()

    def close(self):
        with self.lock:
            self.closed = True
            for process in self.processes.values():
                process.terminate()

    def _valid(self, project, generation):
        return not self.closed and self.generations.get(project, 0) == generation

    def _work(self):
        while not self.closed:
            try:
                job = self.jobs.get(timeout=1)
            except queue.Empty:
                continue
            jobkey, generation, source, stamp, dest, edge = job
            temp = dest.with_name(uuid.uuid4().hex + '.tmp.png')
            process = None
            try:
                with self.lock:
                    if not self._valid(jobkey[0], generation):
                        continue
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    command = [str(self.fast_png), str(source), str(temp)] if edge == 0 else ['/usr/bin/sips', '-s', 'format', 'png', '-Z', str(edge), str(source), '--out', str(temp)]
                    process = subprocess.Popen(['/usr/bin/nice', '-n', '10', *command], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    self.processes[jobkey] = process
                process.wait(timeout=30)
                with self.lock:
                    if not self._valid(jobkey[0], generation) or self.stamp(source) != stamp:
                        continue
                    if process.returncode:
                        raise ValueError('Preview conversion failed')
                    size = png_size(temp, generated=True)
                    if not size or (size != png_size(source) if edge == 0 else max(size) != edge):
                        raise ValueError('Invalid preview raster')
                    temp.replace(dest)
                self._trim(dest.parent)
            except Exception:
                with self.lock:
                    self.failures[jobkey] = time.monotonic() + 60
                    while len(self.failures) > 256:
                        self.failures.popitem(last=False)
            finally:
                if process and process.poll() is None:
                    process.kill()
                    process.wait()
                temp.unlink(missing_ok=True)
                with self.lock:
                    self.processes.pop(jobkey, None)
                    self.pending.discard(jobkey)
                self.jobs.task_done()

    def _trim(self, cache):
        # Serialize eviction with cache publication. Open/read races fall back in
        # the HTTP handler. This cap concerns disk cache, not browser/GPU memory.
        with self.lock:
            files = sorted((p for p in cache.glob('*.png') if not p.name.endswith('.tmp.png')), key=lambda p: p.stat().st_mtime)
            total = sum(p.stat().st_size for p in files)
            for file in files:
                if total <= 256 * 1024 * 1024:
                    break
                total -= file.stat().st_size
                file.unlink(missing_ok=True)


PREVIEWS = PreviewRasters()
atexit.register(PREVIEWS.close)

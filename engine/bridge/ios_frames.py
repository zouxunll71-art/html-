"""One capture producer per workbench; subscribers only receive the latest frame."""
import atexit
import os
import signal
import struct
import subprocess
import threading
import time


class SimulatorFrames:
 def __init__(self, root, config):
  self.executable = str(root / 'build/ios-frames')
  self.config = config
  self.condition = threading.Condition(threading.RLock())
  self.process = None
  self.clients = 0
  self.sequence = 0
  self.latest = None
  self.received = 0
  self.starts = 0
  self.orphans_removed = 0
  atexit.register(self.close)

 def clean_orphans(self):
  # Older versions leaked this exact helper on service shutdown. Never touch
  # another installation, device, a live parent's helper, or snapshot commands.
  expected = self.executable + ' ' + self.config['ios']
  try:
   rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,command='], text=True, timeout=3)
   for row in rows.splitlines():
    parts = row.strip().split(None, 2)
    if len(parts) != 3 or parts[1] != '1' or parts[2] != expected:
     continue
    pid = int(parts[0])
    try:
     current = subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'ppid=,command='], text=True, timeout=1).strip().split(None, 1)
     if current == ['1', expected]:
      os.kill(pid, signal.SIGTERM)
      self.orphans_removed += 1
    except (ProcessLookupError, subprocess.SubprocessError):
     pass
  except (OSError, subprocess.SubprocessError):
   pass

 @staticmethod
 def stop(process):
  if process is None:
   return
  try:
   if process.poll() is None:
    process.terminate()
   process.wait(timeout=2)
  except subprocess.TimeoutExpired:
   process.kill()
   process.wait(timeout=2)
  except ProcessLookupError:
   pass

 def close(self):
  with self.condition:
   process, self.process = self.process, None
   self.latest = None
   self.condition.notify_all()
  self.stop(process)

 @staticmethod
 def read_exact(pipe, size):
  chunks = bytearray()
  while len(chunks) < size:
   chunk = pipe.read(size - len(chunks))
   if not chunk:
    raise EOFError('Simulator capture stopped')
   chunks.extend(chunk)
  return bytes(chunks)

 def read_frames(self, process):
  try:
   while True:
    header = self.read_exact(process.stdout, 4)
    size = struct.unpack('!I', header)[0]
    if not 0 < size < 20_000_000:
     raise ValueError('Invalid simulator frame length')
    frame = header + self.read_exact(process.stdout, size)
    with self.condition:
     if self.process is not process:
      return
     self.latest = frame
     self.received = time.monotonic()
     self.sequence += 1
     self.condition.notify_all()
  except (EOFError, OSError, ValueError):
   pass
  finally:
   with self.condition:
    if self.process is process:
     self.process = None
     self.latest = None
     self.condition.notify_all()
   self.stop(process)
   process.stdout.close()

 def frames(self):
  with self.condition:
   if self.process is None:
    self.clean_orphans()
    self.process = subprocess.Popen([self.executable, self.config['ios']], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=dict(os.environ, DEVELOPER_DIR=self.config['developerDir']))
    self.latest = None
    self.received = time.monotonic()
    self.starts += 1
    threading.Thread(target=self.read_frames, args=(self.process,), daemon=True, name='simulator-frames').start()
   process = self.process
   self.clients += 1
   seen = self.sequence - (1 if self.latest is not None else 0)
  try:
   while True:
    with self.condition:
     ready = self.condition.wait_for(lambda: self.process is not process or self.sequence != seen, timeout=4)
     if self.process is not process:
      return
     if not ready:
      # Close the stalled producer. Existing clients reconnect automatically.
      break
     seen, frame = self.sequence, self.latest
    if frame is not None:
     yield frame
   with self.condition:
    if self.process is process:
     self.process = None
     self.latest = None
     self.condition.notify_all()
   self.stop(process)
  finally:
   with self.condition:
    self.clients -= 1
    stop = self.process if self.clients == 0 else None
    if stop is not None:
     self.process = None
     self.latest = None
     self.condition.notify_all()
   self.stop(stop)

 def status(self):
  with self.condition:
   return dict(running=self.process is not None, clients=self.clients,
               frameAge=round(time.monotonic()-self.received, 2) if self.received else None,
               frames=self.sequence, restarts=max(0,self.starts-1), orphansRemoved=self.orphans_removed)

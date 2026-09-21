import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { EventEmitter } from 'node:events';

export class CodexRPC extends EventEmitter {
  constructor(binary) { super(); this.binary = binary; this.pending = new Map(); this.sequence = 0; this.ready = false; }
  async start() {
    if (this.starting) return this.starting;
    this.starting = this.initialize().catch(error => { this.starting = null; throw error; });
    return this.starting;
  }
  async initialize() {
    // Reuse Codex memory for answers. Only the official client maintains it in
    // the background, so this second UI does not schedule another extraction.
    this.process = spawn(this.binary, ['-c','memories.generate_memories=false','app-server', '--listen', 'stdio://'], { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, RUST_LOG: 'error' } });
    const lines = createInterface({ input: this.process.stdout });
    lines.on('line', line => { try { this.receive(JSON.parse(line)); } catch { /* Non-JSON diagnostics are not protocol messages. */ } });
    this.process.stderr.on('data', data => this.emit('diagnostic', String(data)));
    this.process.on('error', error => this.closed(error));
    this.process.on('exit', code => this.closed(new Error(`Codex 服务已退出（${code}），请重新连接。`)));
    const result = await this.call('initialize', { clientInfo: { name: 'html_native_studio_client', title: 'HTML Codex 工作台', version: '1.0.0' }, capabilities: { experimentalApi: true } });
    this.send({ method: 'initialized' }); this.ready = true;
    return result;
  }
  receive(message) {
    if (message.method) this.emit(message.id !== undefined ? 'request' : 'notification', message);
    else if (this.pending.has(message.id)) {
      const task = this.pending.get(message.id); this.pending.delete(message.id); clearTimeout(task.timer);
      if (message.error) task.reject(new Error(message.error.message)); else task.resolve(message.result);
    }
  }
  send(message) { if (!this.process?.stdin.writable) throw new Error('Codex 服务尚未连接'); this.process.stdin.write(JSON.stringify(message) + '\n'); }
  call(method, params = {}, timeout = 90000) {
    return new Promise((resolve, reject) => {
      const id = ++this.sequence;
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} 响应超时，请检查连接后重试`)); }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ id, method, params }); } catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  respond(id, result) { this.send({ id, result }); }
  closed(error) {
    this.ready = false; this.starting = null;
    for (const task of this.pending.values()) { clearTimeout(task.timer); task.reject(error); }
    this.pending.clear(); this.emit('offline', error.message);
  }
  stop() { this.process?.kill('SIGTERM'); }
}

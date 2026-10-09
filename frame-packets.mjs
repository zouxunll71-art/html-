// The wire format is uint32 BE length followed by an independently decodable image.
// Allocate once per frame: fragmented network reads must not repeatedly copy the
// entire accumulated payload. Returned packets own their storage and are immutable.
export class FramePackets {
  constructor(maxSize = 20_000_000) {
    if (!Number.isSafeInteger(maxSize) || maxSize <= 0 || maxSize > 20_000_000) throw new RangeError('Invalid frame limit');
    this.maxSize = maxSize;
    this.header = Buffer.alloc(4);
    this.headerBytes = 0;
    this.packet = null;
    this.offset = 0;
    this.failed = false;
  }

  push(bytes) {
    if (this.failed) throw new Error('Invalid frame stream');
    const chunk = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let cursor = 0, latest = null;
    while (cursor < chunk.length) {
      if (!this.packet) {
        const count = Math.min(4 - this.headerBytes, chunk.length - cursor);
        chunk.copy(this.header, this.headerBytes, cursor, cursor + count);
        this.headerBytes += count;
        cursor += count;
        if (this.headerBytes < 4) break;
        const size = this.header.readUInt32BE(0);
        if (size === 0 || size > this.maxSize) {
          this.failed = true;
          throw new Error('Invalid frame');
        }
        this.packet = Buffer.allocUnsafe(size + 4);
        this.header.copy(this.packet);
        this.offset = 4;
        this.headerBytes = 0;
      }
      const count = Math.min(this.packet.length - this.offset, chunk.length - cursor);
      chunk.copy(this.packet, this.offset, cursor, cursor + count);
      this.offset += count;
      cursor += count;
      if (this.offset === this.packet.length) {
        // Coalesced network reads may contain several frames. Only the newest
        // complete one is useful for live preview; a partial successor stays here.
        latest = this.packet;
        this.packet = null;
        this.offset = 0;
      }
    }
    return latest;
  }

  end() {
    if (this.failed || this.headerBytes || this.packet) {
      this.packet = null;
      this.failed = true;
      throw new Error('Truncated frame stream');
    }
  }
}

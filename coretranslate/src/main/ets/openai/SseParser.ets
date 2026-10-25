import { util } from '@kit.ArkTS';

/**
 * Incremental UTF-8 chunk decoder: only decodes COMPLETE byte sequences,
 * keeping a split multi-byte tail for the next chunk (plan: SSE with
 * cross-chunk UTF-8 safety). Unit-tested via entry/src/test.
 */
export class Utf8ChunkDecoder {
  private pending: Array<number> = [];
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  /** Feed a chunk; returns the safely-decodable text prefix. */
  push(chunk: ArrayBuffer): string {
    const bytes = new Uint8Array(chunk);
    for (let i = 0; i < bytes.length; i++) {
      this.pending.push(bytes[i]);
    }
    let complete = 0;
    let i = 0;
    while (i < this.pending.length) {
      const b = this.pending[i];
      let len = 1;
      if (b >= 0xF0 && b <= 0xF7) {
        len = 4;
      } else if (b >= 0xE0 && b <= 0xEF) {
        len = 3;
      } else if (b >= 0xC0 && b <= 0xDF) {
        len = 2;
      } else if (b >= 0x80 && b <= 0xBF) {
        // Stray continuation byte: treat as one unit to avoid stalls.
        len = 1;
      }
      if (i + len > this.pending.length) {
        break;
      }
      i += len;
      complete = i;
    }
    if (complete === 0) {
      return '';
    }
    const ready: Uint8Array = new Uint8Array(complete);
    for (let k = 0; k < complete; k++) {
      ready[k] = this.pending[k];
    }
    const rest: Array<number> = [];
    for (let k = complete; k < this.pending.length; k++) {
      rest.push(this.pending[k]);
    }
    this.pending = rest;
    return this.decoder.decodeToString(ready);
  }

  /** Decode any remaining bytes (end of stream). */
  flush(): string {
    if (this.pending.length === 0) {
      return '';
    }
    const ready: Uint8Array = new Uint8Array(this.pending.length);
    for (let k = 0; k < this.pending.length; k++) {
      ready[k] = this.pending[k];
    }
    this.pending = [];
    return this.decoder.decodeToString(ready);
  }
}

/** SSE consumer callbacks. */
export interface SseCallbacks {
  /** One SSE event data payload (prefix stripped). */
  onEvent: (data: string) => void;
  /** Terminal [DONE] marker received. */
  onDone: () => void;
}

/**
 * Server-Sent Events stream parser: buffers raw chunks, splits frames on
 * blank lines, extracts `data:` lines, fires onEvent per event and onDone
 * on `data: [DONE]` (plan D6 / unit tests).
 */
export class SseParser {
  private decoder: Utf8ChunkDecoder = new Utf8ChunkDecoder();
  private textBuffer: string = '';
  private dataLines: Array<string> = [];
  private readonly callbacks: SseCallbacks;

  constructor(callbacks: SseCallbacks) {
    this.callbacks = callbacks;
  }

  /** Feed a raw network chunk. */
  push(chunk: ArrayBuffer): void {
    this.textBuffer += this.decoder.push(chunk);
    this.processBuffer();
  }

  /** End of stream: flush decoders and any pending event. */
  flush(): void {
    this.textBuffer += this.decoder.flush();
    if (this.textBuffer.length > 0) {
      this.consumeLine(this.textBuffer);
      this.textBuffer = '';
    }
    this.emitEvent();
  }

  private processBuffer(): void {
    let idx = this.textBuffer.indexOf('\n');
    while (idx >= 0) {
      let line = this.textBuffer.substring(0, idx);
      this.textBuffer = this.textBuffer.substring(idx + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      this.consumeLine(line);
      idx = this.textBuffer.indexOf('\n');
    }
  }

  private consumeLine(line: string): void {
    if (line.length === 0) {
      this.emitEvent();
      return;
    }
    if (line.startsWith('data:')) {
      let data = line.substring(5);
      if (data.startsWith(' ')) {
        data = data.substring(1);
      }
      this.dataLines.push(data);
    }
    // Non-data lines (event:, id:, comments) are ignored.
  }

  private emitEvent(): void {
    if (this.dataLines.length === 0) {
      return;
    }
    const data = this.dataLines.join('\n');
    this.dataLines = [];
    if (data.trim() === '[DONE]') {
      this.callbacks.onDone();
      return;
    }
    this.callbacks.onEvent(data);
  }
}

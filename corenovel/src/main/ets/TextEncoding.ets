import { util } from '@kit.ArkTS';
import { DecodeResult } from './NovelTypes';

/**
 * 中文文本编码探测与解码（对齐上游 TextEncoding 的行为语义）。
 *
 * 规则：
 * 1. BOM 优先（UTF-8 / UTF-16LE / UTF-16BE），BOM 必须剥掉，否则首字符是 U+FEFF，
 *    分章正则与正文首字都会异常。
 * 2. 无 BOM 时在 utf-8 / gb18030 / big5 之间探测：先严格解码采样，再比较 Unicode
 *    私用区（U+E000–U+F8FF）占比，最低者胜；平手按候选顺序（utf-8 → gb18030 → big5）。
 *    GB18030 覆盖 Big5/GBK 的字节空间，所以「能不能解开」没有区分力，必须加私用区判据。
 * 3. 全部候选都失败时按 UTF-8 宽容解码（替换符），并置 lossy=true 供 UI 提示。
 */
export class TextEncoding {
  /** 探测采样上限（64KB）。 */
  private static readonly SAMPLE_BYTES: number = 64 * 1024;
  /** 采样末尾回退字节数，避免切在多字节字符中间导致全部候选落选。 */
  private static readonly SAMPLE_TAIL_BACKOFF: number = 4;

  /** 解码完整字节流。 */
  static decode(bytes: Uint8Array): DecodeResult {
    const result = new DecodeResult();
    if (bytes.length === 0) {
      return result;
    }
    const bomEncoding = TextEncoding.bomEncoding(bytes);
    if (bomEncoding.length > 0) {
      const bomLen = TextEncoding.bomLength(bytes);
      const body = bytes.slice(bomLen);
      result.encoding = bomEncoding;
      const strict = TextEncoding.decodeStrict(body, bomEncoding);
      if (strict !== undefined) {
        result.text = strict;
      } else {
        result.text = TextEncoding.decodeLenient(body, bomEncoding);
        result.lossy = true;
      }
      return result;
    }

    const sampleSize = bytes.length > TextEncoding.SAMPLE_BYTES
      ? TextEncoding.SAMPLE_BYTES
      : bytes.length;
    const sample = bytes.slice(0, sampleSize);
    const candidates: Array<string> = ['utf-8', 'gb18030', 'big5'];
    let best: string = '';
    let bestScore: number = 2.0;
    for (let i = 0; i < candidates.length; i++) {
      const cs = candidates[i];
      const decoded = TextEncoding.decodeSampleStrict(sample, cs);
      if (decoded === undefined) {
        continue;
      }
      const score = TextEncoding.privateUseRatio(decoded);
      if (score < bestScore) {
        bestScore = score;
        best = cs;
      }
    }
    if (best.length === 0) {
      result.encoding = 'utf-8';
      result.lossy = true;
      result.text = TextEncoding.decodeLenient(bytes, 'utf-8');
      return result;
    }
    result.encoding = best;
    const strict = TextEncoding.decodeStrict(bytes, best);
    if (strict !== undefined) {
      result.text = strict;
      return result;
    }
    result.text = TextEncoding.decodeLenient(bytes, best);
    result.lossy = true;
    return result;
  }

  /** 解码并直接取文本（丢弃编码元信息）。 */
  static decodeToText(bytes: Uint8Array): string {
    return TextEncoding.decode(bytes).text;
  }

  /** 编码名（供 UI/日志展示）。 */
  static encodingLabel(encoding: string): string {
    if (encoding === 'gb18030') {
      return 'GBK/GB18030';
    }
    if (encoding === 'big5') {
      return 'Big5';
    }
    if (encoding === 'utf-16le' || encoding === 'utf-16be') {
      return encoding.toUpperCase();
    }
    return 'UTF-8';
  }

  // ---------- 内部实现 ----------

  private static decodeStrict(bytes: Uint8Array, encoding: string): string | undefined {
    try {
      const options: util.TextDecoderOptions = { fatal: true, ignoreBOM: true };
      const decoder = util.TextDecoder.create(encoding, options);
      const text = decoder.decodeToString(bytes);
      if (text.length === 0 && bytes.length > 0) {
        return undefined;
      }
      // 某些实现的 fatal 标记对非法字节只做替换而不抛错：出现替换符即视为严格解码失败，
      // 避免把 GBK/Big5 文本误判为 UTF-8。
      if (text.indexOf('\uFFFD') >= 0) {
        return undefined;
      }
      return text;
    } catch (e) {
      return undefined;
    }
  }

  private static decodeLenient(bytes: Uint8Array, encoding: string): string {
    try {
      const options: util.TextDecoderOptions = { fatal: false, ignoreBOM: true };
      const decoder = util.TextDecoder.create(encoding, options);
      return decoder.decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  private static decodeSampleStrict(sample: Uint8Array, encoding: string): string | undefined {
    for (let back = 0; back <= TextEncoding.SAMPLE_TAIL_BACKOFF; back++) {
      const n = sample.length - back;
      if (n <= 0) {
        return undefined;
      }
      const slice = back === 0 ? sample : sample.slice(0, n);
      const decoded = TextEncoding.decodeStrict(slice, encoding);
      if (decoded !== undefined) {
        return decoded;
      }
    }
    return undefined;
  }

  /** Unicode 私用区字符占非 ASCII 字符的比例。 */
  private static privateUseRatio(text: string): number {
    let nonAscii = 0;
    let privateUse = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code < 0x80) {
        continue;
      }
      nonAscii++;
      if (code >= 0xE000 && code <= 0xF8FF) {
        privateUse++;
      }
    }
    if (nonAscii === 0) {
      return 0.0;
    }
    return privateUse / nonAscii;
  }

  private static bomEncoding(bytes: Uint8Array): string {
    if (TextEncoding.isUtf8Bom(bytes)) {
      return 'utf-8';
    }
    if (TextEncoding.isUtf16LeBom(bytes)) {
      return 'utf-16le';
    }
    if (TextEncoding.isUtf16BeBom(bytes)) {
      return 'utf-16be';
    }
    return '';
  }

  private static bomLength(bytes: Uint8Array): number {
    if (TextEncoding.isUtf8Bom(bytes)) {
      return 3;
    }
    if (TextEncoding.isUtf16LeBom(bytes) || TextEncoding.isUtf16BeBom(bytes)) {
      return 2;
    }
    return 0;
  }

  private static isUtf8Bom(bytes: Uint8Array): boolean {
    return bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF;
  }

  private static isUtf16LeBom(bytes: Uint8Array): boolean {
    return bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE;
  }

  private static isUtf16BeBom(bytes: Uint8Array): boolean {
    return bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF;
  }
}

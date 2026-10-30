import { taskpool } from '@kit.ArkTS';
import { OcrRegion } from 'coremodel';
import { LocalOcrEngine } from './LocalOcrEngine';

/**
 * TaskPool 入口：本地 OCR 的 ONNX 推理放到 worker 线程，避免 1.7s 主线程阻塞。
 * 只传文件路径/字典，返回 JSON 字符串数组（避免非 Sendable 对象跨线程）。
 */
@Concurrent
export async function recognizeLocalTask(pagePath: string, detPath: string, recPath: string,
  dictText: string): Promise<Array<string>> {
  const engine = LocalOcrEngine.getInstance();
  await engine.init({ detPath: detPath, recPath: recPath, dictText: dictText });
  const regions = await engine.recognize(pagePath);
  const out: Array<string> = [];
  for (const r of regions) {
    out.push(JSON.stringify({
      t: r.text,
      x: r.box.x,
      y: r.box.y,
      w: r.box.w,
      h: r.box.h
    }));
  }
  return out;
}

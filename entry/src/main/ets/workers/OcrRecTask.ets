import { recognizeBoxes } from 'libocrasync.so';

/** TaskPool 入口：原生 ONNX Runtime rec 在 worker 线程执行，避免占 UI 线程。 */
@Concurrent
export function recBoxesNative(rgba: ArrayBuffer, width: number, height: number,
  boxes: Array<number>, dict: string): Array<string> {
  return recognizeBoxes(rgba, width, height, boxes, dict);
}

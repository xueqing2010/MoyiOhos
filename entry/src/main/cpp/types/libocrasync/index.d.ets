export const initRec: (modelPath: string) => boolean;
export const recognizeBoxes: (rgba: ArrayBuffer, width: number, height: number,
  boxes: Array<number>, dict: string) => Array<string>;

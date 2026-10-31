export const initRec: (modelPath: string) => boolean;
export const initDet: (modelPath: string) => boolean;
export const detectBoxes: (rgba: ArrayBuffer, width: number, height: number) => Array<number>;
export const recognizeBoxes: (rgba: ArrayBuffer, width: number, height: number,
  boxes: Array<number>, dict: string) => Array<string>;

/**
 * NAPI contract for libllamacpp.so (plan D11).
 * generate() streams tokens through onToken and reports completion
 * (full text, or error message when isError) through onDone.
 */
export const getVersion: () => string;

export const loadModel: (modelPath: string) => number;

export const generate: (handle: number, prompt: string, maxTokens: number, temperature: number,
  onToken: (token: string) => void,
  onDone: (text: string, isError: boolean) => void) => void;

export const stopGeneration: (handle: number) => void;

export const unloadModel: (handle: number) => void;

/**
 * Preset GGUF model list (plan Data Model: GgufModel = presets + runtime rows).
 * Values mirror upstream downloadinfo.json; the 1.25bit quant depends on the
 * upstream STQ1_0 patch which is missing locally → supported=false (spec).
 */
export interface ModelPreset {
  modelKey: string;
  displayName: string;
  quant: string;
  url: string;
  sizeBytes: number;
  md5?: string;
  supported: boolean;
}

export class ModelPresets {
  /** Hunyuan-MT-1.8B Q4_K_M — standard quant, downloadable & loadable. */
  static readonly HY_MT2_Q4_KM: ModelPreset = {
    modelKey: 'HY_MT2_Q4_KM',
    displayName: 'Hy-MT2 1.8B',
    quant: 'Q4_K_M',
    // 国内真机 HuggingFace 不可达；改用魔搭 ModelScope 镜像（实测 3MB/s 级）。
    url: 'https://modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B-GGUF/resolve/master/Hy-MT2-1.8B-Q4_K_M.gguf',
    sizeBytes: 1133080448,
    md5: '436f3ec23b236b2ac1d05dd7a713f8ae',
    supported: true
  };

  /** Hunyuan-MT-1.8B 1.25Bit — private STQ1_0 quant, NOT supported this version. */
  static readonly HY_MT2_1_25BIT: ModelPreset = {
    modelKey: 'HY_MT2_1_25BIT',
    displayName: 'Hy-MT2 1.8B',
    quant: '1.25bit (STQ1_0)',
    url: 'https://modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B-1.25Bit-GGUF/resolve/master/Hy-MT2-1.8B-1.25Bit.gguf',
    sizeBytes: 461860800,
    md5: '9b96b598c36e9ffbfcafedd919b2fd54',
    supported: false
  };

  static all(): Array<ModelPreset> {
    return [ModelPresets.HY_MT2_Q4_KM, ModelPresets.HY_MT2_1_25BIT];
  }

  static byKey(modelKey: string): ModelPreset | undefined {
    for (const p of ModelPresets.all()) {
      if (p.modelKey === modelKey) {
        return p;
      }
    }
    return undefined;
  }

  static formatSize(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
    }
    if (bytes >= 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${Math.round(bytes / 1024)} KB`;
  }
}

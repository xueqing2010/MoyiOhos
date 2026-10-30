import fs from '@ohos.file.fs';
import { makeDownloadTask } from 'coremodel';
import { Log } from 'commons';
import { DownloadRepository } from '../data/DownloadRepository';
import { DownloadProgress, DownloadService } from './DownloadService';

/**
 * 上游 StarFlow 的 PP-OCRv6 小模型（det + rec）可选下载。
 *
 * 模型与上游仓库 app/src/main/assets/ppocrv6 同源（9.5MB / 20MB），
 * 用户按需下载到应用 models 目录，避免默认安装包携带大模型。
 *
 * 说明：模型下载后，设置中可切换到「本地 PP-OCRv6（ONNX）」档位，
 * 由 ONNX Runtime 鸿蒙 NAPI 在本机推理；系统 Core Vision Kit 仍为默认档位。
 */
export class OcrModelInfo {
  key: string;
  name: string;
  fileName: string;
  url: string;
  sizeBytes: number;
  desc: string;

  constructor(key: string, name: string, fileName: string, url: string, sizeBytes: number, desc: string) {
    this.key = key;
    this.name = name;
    this.fileName = fileName;
    this.url = url;
    this.sizeBytes = sizeBytes;
    this.desc = desc;
  }
}

export class OcrModelService {
  static readonly DET_KEY: string = 'OCR_PP_DET_V6';
  static readonly REC_KEY: string = 'OCR_PP_REC_V6';
  // 国内真机直连 raw.githubusercontent.com 常被阻断；使用公共 GitHub 加速前缀。
  private static readonly BASE: string =
    'https://ghproxy.net/https://raw.githubusercontent.com/xujunjiex/StarFlow/master/app/src/main/assets/ppocrv6';

  static list(): Array<OcrModelInfo> {
    const out: Array<OcrModelInfo> = [];
    // det 9.5MB 走 jsDelivr（国内可达且速度快）；rec 21.2MB 超过 jsDelivr 单文件上限，走 ghproxy。
    out.push(new OcrModelInfo(OcrModelService.DET_KEY, 'PP-OCRv6 检测模型', 'ppocrv6_det_v6_small.onnx',
      'https://cdn.jsdelivr.net/gh/xujunjiex/StarFlow@master/app/src/main/assets/ppocrv6/det_v6_small.onnx',
      9_500_000, '文本行/气泡检测，上游 ppocrv6 det_v6_small.onnx'));
    out.push(new OcrModelInfo(OcrModelService.REC_KEY, 'PP-OCRv6 识别模型', 'ppocrv6_rec_v6_small.onnx',
      'https://raw.githack.com/xujunjiex/StarFlow/master/app/src/main/assets/ppocrv6/rec_v6_small.onnx',
      20_000_000, '日/中/英文字识别，上游 ppocrv6 rec_v6_small.onnx'));
    return out;
  }

  static path(info: OcrModelInfo): string {
    return DownloadService.finalPath(info.fileName);
  }

  static isDownloaded(info: OcrModelInfo): boolean {
    try {
      return fs.accessSync(OcrModelService.path(info));
    } catch (e) {
      return false;
    }
  }

  static localModelsReady(): boolean {
    const list = OcrModelService.list();
    for (let i = 0; i < list.length; i++) {
      if (!OcrModelService.isDownloaded(list[i])) {
        return false;
      }
    }
    return true;
  }

  static async download(info: OcrModelInfo, onProgress: (percent: number) => void): Promise<void> {
    const task = makeDownloadTask(info.key, info.name, info.url, info.fileName);
    task.totalBytes = info.sizeBytes;
    await DownloadRepository.upsert(task);
    const svc = DownloadService.getInstance();
    const listener = (p: DownloadProgress): void => {
      if (p.modelKey !== info.key) {
        return;
      }
      const total = p.totalBytes > 0 ? p.totalBytes : info.sizeBytes;
      const pct = total > 0 ? Math.min(100, Math.round(p.downloadedBytes * 100 / total)) : 0;
      onProgress(pct);
    };
    svc.onProgress(listener);
    try {
      await svc.start(task);
      onProgress(100);
      Log.info('OcrModelService', `downloaded ${info.name} -> ${OcrModelService.path(info)}`);
    } finally {
      svc.offProgress(listener);
    }
  }

  static async remove(info: OcrModelInfo): Promise<void> {
    await DownloadService.getInstance().remove(info.key);
  }

  static formatSize(bytes: number): string {
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    return Math.round(bytes / 1024) + ' KB';
  }
}

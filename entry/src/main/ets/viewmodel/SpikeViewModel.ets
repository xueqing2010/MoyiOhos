import { SpikeDao, SpikeOutcome, SpikeResult, makeSpikeResult } from 'coremodel';
import { BuildInfo } from '../common/BuildInfo';
import { Routes } from '../common/Routes';

/** Canonical spike keys (spike_result.spike_key values). */
export class SpikeKeys {
  static readonly P0_1: string = 'P0-1';
  static readonly P0_2: string = 'P0-2';
  static readonly P0_3: string = 'P0-3';
  static readonly P0_4: string = 'P0-4';
  static readonly P0_5: string = 'P0-5';
  static readonly P0_6: string = 'P0-6';
  static readonly ENGINE: string = 'ENGINE';
}

/** One workbench row: static definition + latest persisted outcome. */
export class SpikeItem {
  readonly key: string;
  readonly title: string;
  readonly desc: string;
  readonly route: string;
  outcome: SpikeOutcome = SpikeOutcome.NOT_RUN;
  detail: string = '';
  updatedAt: number = 0;

  constructor(key: string, title: string, desc: string, route: string) {
    this.key = key;
    this.title = title;
    this.desc = desc;
    this.route = route;
  }
}

/**
 * 尖刀验证工作台 VM（plan D）：统一「说明展示 → 操作执行 → 结论 →
 * spike_result 落库 → 工作台回显」；状态重启保留（US-1 场景 3）。
 */
export class SpikeViewModel {
  /** Static definitions of the 7 verification items. */
  static defs(): Array<SpikeItem> {
    return [
      new SpikeItem(SpikeKeys.P0_1, 'P0-1 多模块工程链路',
        '1 HAP + 6 HAR 构建产物清单与模块依赖打通（含 corenovel）', ''),
      new SpikeItem(SpikeKeys.P0_2, 'P0-2 目录持久授权',
        '系统目录选择器 + 持久授权 + 重启免授权重扫', Routes.SPIKE_IMPORT),
      new SpikeItem(SpikeKeys.P0_3, 'P0-3 压缩包/相册导入',
        'zip/cbz 解压到沙箱 + 相册多选复制', Routes.SPIKE_IMPORT),
      new SpikeItem(SpikeKeys.P0_4, 'P0-4 OCR 行级识别',
        'textRecognition 行级 cornerPoints → OcrRegion', Routes.SPIKE_OCR),
      new SpikeItem(SpikeKeys.P0_5, 'P0-5 排版与覆盖渲染',
        '横/竖排版引擎 + 白块覆盖逐字渲染 + 帧率', Routes.SPIKE_RENDER),
      new SpikeItem(SpikeKeys.P0_6, 'P0-6 llama.cpp NAPI 穿刺',
        'llama.cpp 编译 + NAPI 加载与推理冒烟', Routes.SPIKE_NAPI),
      new SpikeItem(SpikeKeys.ENGINE, 'ENGINE 在线引擎连通',
        'Bing / OpenAI 兼容端到端连通与流式输出', Routes.SPIKE_ENGINE)
    ];
  }

  /** Load definitions merged with latest persisted results. */
  async loadItems(): Promise<Array<SpikeItem>> {
    const items = SpikeViewModel.defs();
    const rows: Array<SpikeResult> = await SpikeDao.queryAll();
    const byKey = new Map<string, SpikeResult>();
    for (const row of rows) {
      byKey.set(row.spikeKey, row);
    }
    for (const item of items) {
      const row = byKey.get(item.key);
      if (row !== undefined) {
        item.outcome = row.result;
        item.detail = row.detail ?? '';
        item.updatedAt = row.updatedAt;
      }
    }
    return items;
  }

  /**
   * P0-1 is a build-time fact: the running app itself proves the
   * multi-module pipeline. Record PASS with the module summary.
   */
  async runP01(): Promise<void> {
    const result = SpikeViewModel.makeResult(SpikeKeys.P0_1, SpikeOutcome.PASS, BuildInfo.moduleSummary());
    await SpikeDao.upsert(result);
  }

  static makeResult(key: string, outcome: SpikeOutcome, detail: string): SpikeResult {
    const r = makeSpikeResult(key, outcome);
    r.detail = detail;
    return r;
  }

  /** Record a spike conclusion to spike_result (workbench echo source). */
  static async makeResultPair(key: string, outcome: SpikeOutcome, detail: string): Promise<void> {
    await SpikeDao.upsert(SpikeViewModel.makeResult(key, outcome, detail));
  }
}
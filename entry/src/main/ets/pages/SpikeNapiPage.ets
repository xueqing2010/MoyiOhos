import { picker } from '@kit.CoreFileKit';
import { uiMaterial } from '@kit.ArkUI';
import { DownloadStatus, DownloadTask, SpikeOutcome } from 'coremodel';
import { GenOptions, LlamaBackend } from 'coretranslate';
import { ThemeTokens, Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { DownloadRepository } from '../data/DownloadRepository';
import { LlamaNapiBackend } from '../service/LlamaNapiBackend';
import { SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';

/**
 * P0-6 NAPI + llama.cpp 验证页（T043 / US-10）：选择已下载/导入的 GGUF →
 * 加载（显示耗时）→ 流式逐 token 生成 → 速度显示 → 停止 → 卸载；
 * 损坏/不支持模型（含 STQ1_0 1.25bit）可读报错不崩溃；结论落库。
 */
@Component
export struct SpikeNapiPage {
  @State models: Array<DownloadTask> = [];
  @State selectedPath: string = '';
  @State selectedName: string = '';
  @State handle: number = -1;
  @State loadMs: number = 0;
  @State generating: boolean = false;
  @State output: string = '';
  @State tokenCount: number = 0;
  @State speed: number = 0;
  @State message: string = '';
  @State status: string = '未执行';
  @State prompt: string = '将下面的文本翻译成简体中文，不要额外解释。\n\n今日はいい天気ですね。';
  private backend: LlamaBackend | undefined = AppEnv.getInstance().getLlamaBackend();

  aboutToAppear(): void {
    this.loadModels();
  }

  private async loadModels(): Promise<void> {
    try {
      await AppEnv.ready();
      const rows = await DownloadRepository.listAll();
      const done: Array<DownloadTask> = [];
      for (const r of rows) {
        if (r.status === DownloadStatus.DOWNLOADED && r.localPath !== undefined && r.localPath.length > 0) {
          done.push(r);
        }
      }
      this.models = done;
    } catch (e) {
      this.message = `加载模型列表失败：${e}`;
    }
  }

  private async record(outcome: SpikeOutcome, detail: string): Promise<void> {
    try {
      await SpikeViewModel.makeResultPair(SpikeKeys.P0_6, outcome, detail);
    } catch (e) {
      Log.error('SpikeNapiPage', `record failed: ${e}`);
    }
  }

  private async importGguf(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['GGUF 模型 (.gguf)|.gguf'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      this.selectedPath = uris[0];
      this.selectedName = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      this.message = `已选择：${this.selectedName}`;
    } catch (e) {
      this.message = `选择失败：${e}`;
    }
  }

  private async loadModel(): Promise<void> {
    if (this.backend === undefined) {
      this.message = 'llama.cpp 动态库未加载（当前为降级构建）';
      this.status = '降级';
      await this.record(SpikeOutcome.DEGRADED, this.message);
      return;
    }
    if (this.selectedPath.length === 0) {
      this.message = '请先选择一个 GGUF 模型';
      return;
    }
    this.message = '正在加载模型…';
    try {
      const t0 = Date.now();
      this.handle = await this.backend.loadModel(this.selectedPath);
      this.loadMs = Date.now() - t0;
      this.message = `模型加载成功（${this.loadMs}ms），句柄 ${this.handle}`;
      this.status = '已加载';
    } catch (e) {
      this.handle = -1;
      const err = e as Error;
      const msg = err !== undefined && err.message !== undefined ? err.message : `${e}`;
      this.message = `加载失败：${msg}`;
      const unsupported = msg.indexOf('1.25bit') >= 0 || msg.indexOf('STQ1_0') >= 0 || msg.indexOf('暂不支持') >= 0;
      this.status = unsupported ? '降级' : '失败';
      await this.record(unsupported ? SpikeOutcome.DEGRADED : SpikeOutcome.FAIL, this.message);
    }
  }

  private async generate(): Promise<void> {
    if (this.backend === undefined || this.handle < 0) {
      this.message = '请先加载模型';
      return;
    }
    if (this.generating) {
      return;
    }
    this.generating = true;
    this.output = '';
    this.tokenCount = 0;
    this.speed = 0;
    this.message = '正在生成…';
    const t0 = Date.now();
    try {
      const opts: GenOptions = { prompt: this.prompt, maxTokens: 128, temperature: 0.3 };
      const text = await this.backend.generate(this.handle, opts, (token: string) => {
        this.output += token;
        this.tokenCount++;
      });
      if (this.output.length === 0 && text.length > 0) {
        this.output = text;
      }
      const elapsed = Math.max(1, Date.now() - t0);
      this.speed = Math.round(this.tokenCount * 1000 / elapsed * 10) / 10;
      if (this.output.length > 0) {
        this.status = '通过';
        this.message = `生成完成：${this.tokenCount} tokens，${this.speed} token/s`;
        await this.record(SpikeOutcome.PASS,
          `llama.cpp 出 token 成功：${this.tokenCount} tokens，${this.speed} token/s（加载 ${this.loadMs}ms）`);
      } else {
        this.status = '降级';
        this.message = '库与穿刺成功，但未产出 token';
        await this.record(SpikeOutcome.DEGRADED, this.message);
      }
    } catch (e) {
      const err = e as Error;
      const msg = err !== undefined && err.message !== undefined ? err.message : `${e}`;
      this.status = '失败';
      this.message = `生成失败：${msg}`;
      await this.record(SpikeOutcome.FAIL, this.message);
    }
    this.generating = false;
  }

  private stop(): void {
    if (this.backend !== undefined && this.handle >= 0) {
      this.backend.stopGeneration(this.handle);
      this.message = '已请求停止';
    }
  }

  private unload(): void {
    if (this.backend !== undefined && this.handle >= 0) {
      this.backend.unloadModel(this.handle);
      this.handle = -1;
      this.message = '模型已卸载';
      this.status = '已卸载';
    }
  }

  @Builder
  modelChip(task: DownloadTask) {
    Column({ space: 2 }) {
      Text(task.displayName.length > 0 ? task.displayName : task.fileName)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(this.selectedPath === task.localPath ? ThemeTokens.WHITE : ThemeTokens.TEXT_SECONDARY)
      Text(task.fileName)
        .fontSize(10)
        .fontColor(ThemeTokens.TEXT_HINT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(this.selectedPath === task.localPath ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      this.selectedPath = task.localPath ?? '';
      this.selectedName = task.displayName;
      this.message = `已选择：${task.displayName}`;
    })
  }

  @Builder
  actionButton(label: string, enabled: boolean, color: string, onTap: () => void) {
    Button(label)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontColor(enabled ? ThemeTokens.WHITE : ThemeTokens.TEXT_HINT)
      .backgroundColor(enabled ? color : ThemeTokens.SURFACE_VARIANT)
      .borderRadius(18)
      .height(36)
      .padding({ left: 18, right: 18 })
      .enabled(enabled)
      .onClick(() => {
        onTap();
      })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Text(`P0-6 llama.cpp NAPI  ${this.status}`)
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.status === '通过' ? ThemeTokens.SUCCESS
              : (this.status === '失败' ? ThemeTokens.RED : ThemeTokens.TEXT_PRIMARY))
            .width('100%')

          Text(`native: ${LlamaNapiBackend.isAvailable() ? 'libllamacpp.so 可调用' : 'native 库不可用（降级）'}`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')

          Row({ space: 8 }) {
            this.actionButton('导入本地 GGUF', true, ThemeTokens.PRIMARY, () => {
              this.importGguf();
            })
            this.actionButton('刷新已下载', true, ThemeTokens.SURFACE_VARIANT, () => {
              this.loadModels();
            })
          }
          .width('100%')

          if (this.models.length > 0) {
            Text('已下载模型：')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%')
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.models, (task: DownloadTask) => {
                  this.modelChip(task)
                }, (task: DownloadTask) => task.modelKey)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          if (this.selectedName.length > 0) {
            Text(`当前模型：${this.selectedName}`)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .width('100%')
          }

          Row({ space: 8 }) {
            this.actionButton(this.handle >= 0 ? '重新加载' : '加载模型', !this.generating, ThemeTokens.ACCENT, () => {
              this.loadModel();
            })
            this.actionButton('生成', this.handle >= 0 && !this.generating, ThemeTokens.SUCCESS, () => {
              this.generate();
            })
            this.actionButton('停止', this.generating, ThemeTokens.WARN, () => {
              this.stop();
            })
            this.actionButton('卸载', this.handle >= 0 && !this.generating, ThemeTokens.RED, () => {
              this.unload();
            })
          }
          .width('100%')

          TextArea({ text: this.prompt, placeholder: '提示词' })
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .height(80)
            .width('100%')
            .onChange((v: string) => {
              this.prompt = v;
            })

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%')
          }

          Column({ space: 4 }) {
            Row() {
              Text(this.generating ? '生成中…' : `输出（${this.tokenCount} tokens）`)
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .layoutWeight(1)
              if (this.speed > 0) {
                Text(`${this.speed} token/s`)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.PRIMARY)
              }
            }
            .width('100%')
            Text(this.output.length > 0 ? this.output : '（流式输出将在此显示）')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(this.output.length > 0 ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.TEXT_HINT)
              .width('100%')
          }
          .padding(ThemeTokens.CARD_PADDING)
          .borderRadius(ThemeTokens.RADIUS_CARD)
          .backgroundColor(ThemeTokens.CARD_BG)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding(ThemeTokens.PAGE_PADDING)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('NAPI 穿刺（P0-6）', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}
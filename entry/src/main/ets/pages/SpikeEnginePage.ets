import { EngineType } from 'coretranslate';
import { uiMaterial } from '@kit.ArkUI';
import { SpikeOutcome } from 'coremodel';
import { ThemeTokens, Log } from 'commons';
import { SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';
import { TextTranslateViewModel } from '../viewmodel/TextTranslateViewModel';

/**
 * 在线引擎验证页（T037 / US-8）：必应通道零配置连通验证、
 * OpenAI 兼容通道配置态验证（拉模型列表 + 短翻译）；结论落库。
 */
@Component
export struct SpikeEnginePage {
  @State bingStatus: string = '未执行';
  @State bingDetail: string = '';
  @State bingBusy: boolean = false;
  @State openaiStatus: string = '未执行';
  @State openaiDetail: string = '';
  @State openaiBusy: boolean = false;
  @State hasKey: boolean = false;

  aboutToAppear(): void {
    this.refreshConfig();
    this.loadSaved();
  }

  /** Echo the latest persisted ENGINE conclusion (status survives restarts). */
  private async loadSaved(): Promise<void> {
    try {
      const items = await new SpikeViewModel().loadItems();
      for (const item of items) {
        if (item.key === SpikeKeys.ENGINE) {
          if (item.outcome === SpikeOutcome.PASS) {
            this.bingStatus = '通过';
          } else if (item.outcome === SpikeOutcome.FAIL) {
            this.bingStatus = '失败';
          } else if (item.outcome === SpikeOutcome.DEGRADED) {
            this.bingStatus = '降级';
          }
          this.bingDetail = item.detail;
        }
      }
    } catch (e) {
      Log.warn('SpikeEnginePage', `loadSaved failed: ${e}`);
    }
  }

  private async refreshConfig(): Promise<void> {
    this.hasKey = await TextTranslateViewModel.hasApiKey();
  }

  private async record(outcome: SpikeOutcome, text: string): Promise<void> {
    try {
      await SpikeViewModel.makeResultPair(SpikeKeys.ENGINE, outcome, text);
    } catch (e) {
      Log.error('SpikeEnginePage', `record failed: ${e}`);
    }
  }

  private async runBing(): Promise<void> {
    if (this.bingBusy) {
      return;
    }
    this.bingBusy = true;
    this.bingStatus = '执行中';
    try {
      const t0 = Date.now();
      const out = await TextTranslateViewModel.translate('你好，世界', 'zh', 'en', EngineType.BING);
      const elapsed = Date.now() - t0;
      if (out.length > 0) {
        this.bingStatus = '通过';
        this.bingDetail = `零配置翻译成功（${elapsed}ms）：${out}`;
        await this.record(SpikeOutcome.PASS, `必应：${this.bingDetail}`);
      } else {
        this.bingStatus = '失败';
        this.bingDetail = '必应返回空结果';
        await this.record(SpikeOutcome.FAIL, `必应：${this.bingDetail}`);
      }
    } catch (e) {
      this.bingStatus = '失败';
      this.bingDetail = TextTranslateViewModel.readableError(e);
      await this.record(SpikeOutcome.FAIL, `必应：${this.bingDetail}`);
    }
    this.bingBusy = false;
  }

  private async runOpenAi(): Promise<void> {
    if (this.openaiBusy) {
      return;
    }
    this.openaiBusy = true;
    this.openaiStatus = '执行中';
    try {
      await TextTranslateViewModel.applyOpenAiConfig();
      if (!this.hasKey) {
        this.openaiStatus = '降级';
        this.openaiDetail = 'OpenAI 兼容通道需要配置（Base URL / API Key / 模型名），当前未配置';
        await this.record(SpikeOutcome.DEGRADED, `OpenAI：${this.openaiDetail}`);
        this.openaiBusy = false;
        return;
      }
      const models = await TextTranslateViewModel.listModels();
      const out = await TextTranslateViewModel.translate('Hello, world', 'en', 'zh', EngineType.OPENAI_COMPAT);
      this.openaiStatus = '通过';
      this.openaiDetail = `模型 ${models.length} 个；翻译结果：${out}`;
      await this.record(SpikeOutcome.PASS, `OpenAI：${this.openaiDetail}`);
    } catch (e) {
      this.openaiStatus = '失败';
      this.openaiDetail = TextTranslateViewModel.readableError(e);
      await this.record(SpikeOutcome.FAIL, `OpenAI：${this.openaiDetail}`);
    }
    this.openaiBusy = false;
  }

  @Builder
  block(title: string, desc: string, status: string, detail: string, busy: boolean, button: string,
    onTap: () => void) {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(status)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(status === '通过' ? ThemeTokens.SUCCESS
            : (status === '失败' ? ThemeTokens.RED : ThemeTokens.TEXT_HINT))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')
      Text(desc)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('100%')
      if (detail.length > 0) {
        Text(detail)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Button(button)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .backgroundColor(busy ? ThemeTokens.SURFACE_VARIANT : ThemeTokens.PRIMARY)
        .fontColor(busy ? ThemeTokens.TEXT_HINT : ThemeTokens.WHITE)
        .borderRadius(18)
        .height(36)
        .padding({ left: 20, right: 20 })
        .enabled(!busy)
        .onClick(() => {
          onTap();
        })
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          this.block('必应翻译（免 Key 零配置）',
            'GET cn.bing.com/Translator 抓取令牌 → POST ttranslatev3；联网即用',
            this.bingStatus, this.bingDetail, this.bingBusy, '必应连通验证', () => {
              this.runBing();
            })
          this.block(this.hasKey ? 'OpenAI 兼容通道（已配置）' : 'OpenAI 兼容通道（未配置）',
            'GET /models + chat/completions 短翻译；密钥经安全资产存储',
            this.openaiStatus, this.openaiDetail, this.openaiBusy, 'OpenAI 连通验证', () => {
              this.runOpenAi();
            })
          Text('提示：OpenAI 通道需先在「翻译」Tab → OpenAI 兼容 → 配置 中填写端点后再验证。')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
        }
        .padding(ThemeTokens.PAGE_PADDING)
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('在线引擎验证（ENGINE）', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onShown(() => {
      this.refreshConfig();
      this.loadSaved();
    })
  }
}
import { uiMaterial } from '@kit.ArkUI';
import { ThemeTokens, WindowSizeClass, observeBreakpoint, Log } from 'commons';
import { OcrService } from 'coreocr';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';
import { OcrModelInfo, OcrModelService } from '../service/OcrModelService';

/** OCR 语言选项（值与 coreocr OcrLang 一致）。 */
class OcrLangOption {
  value: string;
  label: string;
  sample: string;

  constructor(value: string, label: string, sample: string) {
    this.value = value;
    this.label = label;
    this.sample = sample;
  }
}

/** 引擎档位说明。 */
class OcrTier {
  id: string;
  title: string;
  desc: string;
  available: boolean;

  constructor(id: string, title: string, desc: string, available: boolean) {
    this.id = id;
    this.title = title;
    this.desc = desc;
    this.available = available;
  }
}

/** @Builder 按引用传递参数（状态改变可刷新 UI）。 */
interface LangChipParams {
  label: string;
  sample: string;
  active: boolean;
  onTap: () => void;
}

interface TierRowParams {
  tier: OcrTier;
  active: boolean;
}

/** 设置卡片容器。 */
@Component
struct OcrSettingCard {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * OCR 设置页（S109 设置侧）：识别语言（日/英/中/韩）、引擎档位说明、
 * 能力探测（coreocr OcrService 只读 probe）。语言写入 starflow_translate 的
 * ocr_lang，与 PageTranslateService 读取一致。
 */
@Component
export struct SettingsOcrPage {
  @State ocrLang: string = 'ja';
  @State ocrTier: string = 'system';
  @State probing: boolean = false;
  @State probeOk: boolean = false;
  @State probeDetail: string = '未探测';
  @State hint: string = '';
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State detReady: boolean = false;
  @State recReady: boolean = false;
  @State downloadingKey: string = '';
  @State modelPercent: number = 0;
  private dictText: string = '';
  private models: Array<OcrModelInfo> = OcrModelService.list();
  private stopBreakpoint: (() => void) | undefined = undefined;
  private langs: Array<OcrLangOption> = [
    new OcrLangOption('ja', '日本語', '日文漫画/轻小说'),
    new OcrLangOption('en', 'English', '英文漫画/文本'),
    new OcrLangOption('zh-CN', '简体中文', '中文内容与译后校对'),
    new OcrLangOption('ko', '한국어', '韩文条漫')
  ];
  @State tiers: Array<OcrTier> = [
    new OcrTier('system', '系统 Core Vision Kit', 'HarmonyOS 官方文字识别（textRecognition），本机离线推理。', true),
    new OcrTier('local', '本地 PP-OCRv6（ONNX）', '下载 det + rec 模型后，用 ONNX Runtime 在本机推理，不联网上传。', false),
    new OcrTier('cloud', '云端 OCR 服务', '需要第三方账号与网络上传，与本地优先的隐私策略冲突，未接入。', false)
  ];

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.load();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private async load(): Promise<void> {
    this.ocrLang = await SettingsRepository.getString(SettingsKeys.OCR_LANG, 'ja');
    this.ocrTier = await SettingsRepository.getString(SettingsKeys.OCR_ENGINE_TIER, 'system');
    this.probeDetail = OcrService.getInstance().getProbeDetail();
    this.refreshModels();
  }

  private refreshModels(): void {
    this.detReady = OcrModelService.isDownloaded(this.models[0]);
    this.recReady = OcrModelService.isDownloaded(this.models[1]);
    const ready = this.detReady && this.recReady;
    this.tiers = [
      new OcrTier('system', '系统 Core Vision Kit', 'HarmonyOS 官方文字识别（textRecognition），本机离线推理。', true),
      new OcrTier('local', '本地 PP-OCRv6（ONNX）',
        ready ? '模型已就绪：ONNX Runtime 本机推理，选择后翻译页使用本地 OCR。'
          : '点击任一模型按钮会自动下载 det + rec 并启用本地 OCR。', ready),
      new OcrTier('cloud', '云端 OCR 服务', '需要第三方账号与网络上传，与本地优先的隐私策略冲突，未接入。', false)
    ];
  }

  private isReady(info: OcrModelInfo): boolean {
    return info.key === OcrModelService.DET_KEY ? this.detReady : this.recReady;
  }

  /** 点任一模型下载：自动依次下载 det + rec，完成后直接启用本地档位。 */
  private async downloadModel(info: OcrModelInfo): Promise<void> {
    await this.downloadAll();
  }

  private async downloadAll(): Promise<void> {
    if (this.downloadingKey.length > 0) {
      return;
    }
    try {
      for (let i = 0; i < this.models.length; i++) {
        const info = this.models[i];
        if (this.isReady(info)) {
          continue;
        }
        this.downloadingKey = info.key;
        this.modelPercent = 0;
        await OcrModelService.download(info, (pct: number) => {
          this.modelPercent = pct;
        });
      }
      this.refreshModels();
      if (this.detReady && this.recReady) {
        await SettingsRepository.set(SettingsKeys.OCR_ENGINE_TIER, 'local');
        this.ocrTier = 'local';
        this.refreshModels();
        this.flash('det + rec 已下载并启用本地 OCR');
      } else {
        this.flash('模型下载完成');
      }
    } catch (e) {
      const msg = `${e}`;
      this.flash(msg.indexOf('超时') >= 0 || msg.indexOf('网络') >= 0
        ? '下载失败：请检查网络后重试'
        : `下载失败：${msg}`);
    }
    this.downloadingKey = '';
    this.modelPercent = 0;
  }

  private async removeModel(info: OcrModelInfo): Promise<void> {
    try {
      await OcrModelService.remove(info);
      this.refreshModels();
      this.flash(`已删除 ${info.name}`);
    } catch (e) {
      this.flash(`删除失败：${e}`);
    }
  }

  @Builder
  modelRow(info: OcrModelInfo) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(info.name)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(info.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(2)
        Text(this.isReady(info)
          ? `已下载 · ${OcrModelService.formatSize(info.sizeBytes)} · ${OcrModelService.path(info)}`
          : `未下载 · ${OcrModelService.formatSize(info.sizeBytes)}`)
          .fontSize(10)
          .fontColor(this.isReady(info) ? ThemeTokens.SUCCESS : ThemeTokens.TEXT_TERTIARY)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.downloadingKey === info.key ? `${this.modelPercent}%`
        : (this.isReady(info) ? '删除' : '下载'))
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(this.isReady(info) ? ThemeTokens.WARN : ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(this.isReady(info) ? ThemeTokens.SURFACE_VARIANT : ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .height(32)
        .enabled(this.downloadingKey.length === 0 || this.downloadingKey === info.key)
        .onClick(() => {
          if (this.isReady(info)) {
            this.removeModel(info);
          } else {
            this.downloadModel(info);
          }
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  /** 本地档位以磁盘实际文件为准，避免 @State 批量赋值未触发重绘时误显示“未接入”。 */
  private tierAvailable(tier: OcrTier): boolean {
    if (tier.id === 'local') {
      return OcrModelService.isDownloaded(this.models[0]) && OcrModelService.isDownloaded(this.models[1]);
    }
    return tier.available;
  }

  private async pickTier(tier: OcrTier): Promise<void> {
    if (!this.tierAvailable(tier)) {
      if (tier.id === 'local') {
        await this.downloadAll();
        return;
      }
      this.flash('该档位当前版本未接入');
      return;
    }
    this.ocrTier = tier.id;
    await SettingsRepository.set(SettingsKeys.OCR_ENGINE_TIER, tier.id);
    this.flash(tier.id === 'local' ? '已启用本地 OCR（翻译时生效）' : 'OCR 引擎档位已保存');
  }

  private flash(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 1400);
  }

  private async pickLang(value: string): Promise<void> {
    this.ocrLang = value;
    await SettingsRepository.set(SettingsKeys.OCR_LANG, value);
    this.flash('OCR 语言已更新');
  }

  private async probe(): Promise<void> {
    if (this.probing) {
      return;
    }
    this.probing = true;
    try {
      const service = OcrService.getInstance();
      this.probeOk = await service.probe();
      this.probeDetail = service.getProbeDetail();
      Log.info('SettingsOcr', `probe ok=${this.probeOk}`);
    } catch (e) {
      this.probeOk = false;
      this.probeDetail = `探测失败：${e}`;
    }
    this.probing = false;
  }

  private isWide(): boolean {
    return this.sizeClass === WindowSizeClass.LG;
  }

  @Builder
  sectionTitle(title: string, desc: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      if (desc.length > 0) {
        Text(desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6, bottom: 2 })
  }

  @Builder
  langChip(pp: LangChipParams) {
    Column({ space: 2 }) {
      Text(pp.label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(pp.active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      Text(pp.sample)
        .fontSize(10)
        .fontColor(pp.active ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_HINT)
        .maxLines(1)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(pp.active ? ThemeTokens.PRIMARY : ThemeTokens.SURFACE_VARIANT)
    .margin({ right: 8, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      pp.onTap();
    })
  }

  @Builder
  tierRow(pp: TierRowParams) {
    Row({ space: 10 }) {
      Column() {
        Image($r('app.media.ic_check'))
          .width(16)
          .height(16)
          .fillColor(this.tierAvailable(pp.tier) ? ThemeTokens.SUCCESS : ThemeTokens.TEXT_TERTIARY)
      }
      .width(30)
      .height(30)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .justifyContent(FlexAlign.Center)

      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text(pp.tier.title)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(this.tierAvailable(pp.tier) ? (pp.active ? '当前档位' : '可用') : '未接入')
            .fontSize(10)
            .fontColor(this.tierAvailable(pp.tier) ? ThemeTokens.SUCCESS : ThemeTokens.TEXT_HINT)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        }
        Text(pp.tier.desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .lineHeight(17)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Top)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .onClick(() => {
      this.pickTier(pp.tier);
    })
  }

  build() {
    NavDestination() {
      Scroll() {
        Row() {
          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('OCR 识别')
                  .fontSize(ThemeTokens.FONT_TITLE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text('系统文字识别能力、语言提示与档位说明')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.hint.length > 0) {
                Text(this.hint)
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.SUCCESS)
                  .maxLines(1)
              }
            }
            .width('100%')

            this.sectionTitle('识别语言', '语言提示用于提升日/英/中/韩文字的识别效果')
            OcrSettingCard() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.langs, (opt: OcrLangOption) => {
                  this.langChip({ label: opt.label, sample: opt.sample, active: this.ocrLang === opt.value, onTap: () => {
                    this.pickLang(opt.value);
                  } })
                }, (opt: OcrLangOption) => opt.value)
              }
              .width('100%')
              Text('提示：系统 OCR 引擎本身支持多语言，语言选项作为识别提示与诊断信息保存。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
            }

            this.sectionTitle('引擎档位', '系统 Core Vision 或本地 PP-OCRv6（需下载模型）')
            OcrSettingCard() {
              ForEach(this.tiers, (tier: OcrTier) => {
                this.tierRow({ tier: tier, active: this.ocrTier === tier.id })
              }, (tier: OcrTier) => tier.id)
              Text('档位偏好会保存：选择本地后，单页/批量翻译使用 ONNX Runtime 在本机识别，不上传图片；云端档位未接入。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
            }

            this.sectionTitle('上游 OCR 模型（可选下载）', 'PP-OCRv6 det / rec，不随安装包分发')
            OcrSettingCard() {
              ForEach(this.models, (info: OcrModelInfo) => {
                this.modelRow(info)
              }, (info: OcrModelInfo) => info.key)
              Text('模型来自上游 StarFlow（LGPL-3.0）的 ppocrv6 assets；字典随包分发，首次加载模型约需数秒。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)
            }

            this.sectionTitle('能力探测', '只读检查当前设备文字识别服务是否可用')
            OcrSettingCard() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(this.probing ? '探测中…' : (this.probeOk ? 'OCR 可用' : '尚未确认'))
                    .fontSize(ThemeTokens.FONT_CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.probing ? ThemeTokens.TEXT_SECONDARY
                      : (this.probeOk ? ThemeTokens.SUCCESS : ThemeTokens.WARN))
                  Text(this.probeDetail)
                    .fontSize(ThemeTokens.FONT_SMALL)
                    .fontColor(ThemeTokens.TEXT_HINT)
                    .lineHeight(17)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.probing ? '探测中' : '探测')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                  .backgroundColor(ThemeTokens.PRIMARY)
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .height(34)
                  .enabled(!this.probing)
                  .onClick(() => {
                    this.probe();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }

            Text('提示：部分模拟器未内置文字识别服务，探测失败属预期；真机可用。OCR 全程在本机完成，图片不会上传。')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(18)
              .margin({ top: 2, bottom: 12 })
          }
          .width(this.isWide() ? 760 : '100%')
          .padding({
            left: ThemeTokens.PAGE_PADDING,
            right: ThemeTokens.PAGE_PADDING,
            top: 12,
            bottom: 24
          })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('OCR 设置', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}
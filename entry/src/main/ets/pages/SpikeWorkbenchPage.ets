import { SpikeOutcome } from 'coremodel';
import { uiMaterial } from '@kit.ArkUI';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { ThemeTokens, Log } from 'commons';
import { SpikeItem, SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';
import { DemoTranslationSeeder } from '../service/DemoTranslationSeeder';

/**
 * 尖刀验证工作台（US-1）：7 项清单（P0-1~P0-6 + ENGINE），每项展示
 * 最近结果（未执行/通过/失败/降级）与入口；结果经 SpikeDao 持久化，
 * 重启保留。P0-1 为构建期事实，点按即回填通过并展示模块清单。
 */
@Component
export struct SpikeWorkbenchPage {
  @State items: Array<SpikeItem> = [];
  @State loaded: boolean = false;
  @State seedBusy: boolean = false;
  @State seedMessage: string = '';
  private vm: SpikeViewModel = new SpikeViewModel();
  private navStack: NavPathStack = AppEnv.getInstance().navStack;

  aboutToAppear(): void {
    this.refresh();
  }

  async refresh(): Promise<void> {
    try {
      await AppEnv.ready();
      this.items = await this.vm.loadItems();
    } catch (e) {
      this.items = SpikeViewModel.defs();
    }
    this.loaded = true;
  }

  private statusText(outcome: SpikeOutcome): Resource {
    if (outcome === SpikeOutcome.PASS) {
      return $r('app.string.spike_status_pass');
    }
    if (outcome === SpikeOutcome.FAIL) {
      return $r('app.string.spike_status_fail');
    }
    if (outcome === SpikeOutcome.DEGRADED) {
      return $r('app.string.spike_status_degraded');
    }
    return $r('app.string.spike_status_not_run');
  }

  private statusColor(outcome: SpikeOutcome): string {
    if (outcome === SpikeOutcome.PASS) {
      return ThemeTokens.SUCCESS;
    }
    if (outcome === SpikeOutcome.FAIL) {
      return ThemeTokens.RED;
    }
    if (outcome === SpikeOutcome.DEGRADED) {
      return ThemeTokens.WARN;
    }
    return ThemeTokens.TEXT_HINT;
  }

  private onItemTap(item: SpikeItem): void {
    if (item.key === SpikeKeys.P0_1) {
      // Build-time fact: record PASS and refresh the row.
      this.vm.runP01().then(() => {
        this.refresh();
      }).catch((e: Object) => {
        Log.error('SpikeWorkbenchPage', `P0-1 record failed: ${e}`);
      });
      return;
    }
    if (item.route.length > 0) {
      this.navStack.pushPathByName(item.route, item.key);
    }
  }

  @Builder
  itemCard(item: SpikeItem) {
    Column({ space: 8 }) {
      Row() {
        Text(item.title)
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.statusText(item.outcome))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(this.statusColor(item.outcome))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')
      Text(item.desc)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('100%')
      if (item.outcome !== SpikeOutcome.NOT_RUN && item.detail.length > 0) {
        Text(item.detail)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (item.updatedAt > 0) {
        Text($r('app.string.spike_last_run_at', this.formatTime(item.updatedAt)))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .width('100%')
      } else if (item.key === SpikeKeys.P0_1) {
        Text($r('app.string.spike_run_p01'))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY)
          .width('100%')
      }
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onItemTap(item);
    })
  }

  /** Dev tool: seed P0-5 / export / history demo translations (emulator OCR is absent). */
  private async seedDemoTranslations(): Promise<void> {
    if (this.seedBusy) {
      return;
    }
    this.seedBusy = true;
    try {
      this.seedMessage = await DemoTranslationSeeder.seed();
    } catch (e) {
      this.seedMessage = '注入失败：' + e;
    }
    this.seedBusy = false;
  }

  @Builder
  devToolCard() {
    Column({ space: 8 }) {
      Text('开发工具 · 示例译文注入')
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .width('100%')
      Text('模拟器无系统 OCR 服务：写入示例页的 OCR 坐标与中文译文（仅文本+坐标，不落位图），用于验收译文覆盖、仅译文/双语导出与历史链路。')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width('100%')
        .lineHeight(18)
      Button(this.seedBusy ? '注入中…' : '注入示例译文')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.WHITE)
        .backgroundColor(this.seedBusy ? ThemeTokens.SURFACE_VARIANT : ThemeTokens.PRIMARY_DEEP)
        .borderRadius(18)
        .height(36)
        .padding({ left: 18, right: 18 })
        .enabled(!this.seedBusy)
        .onClick(() => {
          this.seedDemoTranslations();
        })
      if (this.seedMessage.length > 0) {
        Text(this.seedMessage)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.SUCCESS)
          .width('100%')
      }
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private formatTime(ts: number): string {
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  build() {
    NavDestination() {
      if (this.loaded) {
        List({ space: 12 }) {
          ForEach(this.items, (item: SpikeItem) => {
            ListItem() {
              this.itemCard(item)
            }
          }, (item: SpikeItem) => item.key)
          ListItem() {
            this.devToolCard()
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          left: ThemeTokens.PAGE_PADDING,
          right: ThemeTokens.PAGE_PADDING,
          top: 8,
          bottom: ThemeTokens.PAGE_PADDING
        })
      } else {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(ThemeTokens.PRIMARY)
          .margin({ top: 120 })
      }
    }
    .title($r('app.string.spike_title'), {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true,
        interactive: true,
        lightEffect: {}
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onShown(() => {
      // Refresh when returning from a spike page (new results may exist).
      // A second pass covers the case where the DB commit lands just after the
      // pop animation starts.
      this.refresh();
      setTimeout(() => {
        this.refresh();
      }, 600);
    })
  }
}
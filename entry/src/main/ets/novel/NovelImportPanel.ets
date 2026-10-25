import { ThemeTokens } from 'commons';
import {
  NovelImportFailure,
  NovelImportProgress,
  NovelImportResult,
  NovelImportService
} from '../service/NovelImportService';
import { ProgressCard } from '../components/ProgressCard';

/**
 * 小说导入面板（对齐上游 novel_import）：文件/目录两条通道 + 进度 + 取消 + 失败原因。
 * 由 ImportView 无参调用；导入完成后通过 AppStorage('starflow_shelf_dirty') 通知书架刷新。
 */
@Component
export struct NovelImportPanel {
  @State importing: boolean = false;
  @State phase: string = '';
  @State done: number = 0;
  @State total: number = 0;
  @State currentName: string = '';
  @State failures: Array<NovelImportFailure> = [];
  @State warnings: Array<string> = [];
  @State hint: string = '';
  private cancelRequested: boolean = false;

  private reset(): void {
    this.phase = '';
    this.done = 0;
    this.total = 0;
    this.currentName = '';
    this.failures = [];
    this.warnings = [];
    this.cancelRequested = false;
    this.hint = '';
  }

  private emitProgress(p: NovelImportProgress): void {
    this.phase = p.phase;
    this.done = p.done;
    this.total = p.total;
    this.currentName = p.currentName;
  }

  private notifyShelf(): void {
    AppStorage.setOrCreate('starflow_shelf_dirty', Date.now());
  }

  private applyResult(result: NovelImportResult): void {
    this.failures = result.failures;
    this.warnings = result.warnings;
    if (result.cancelled) {
      this.hint = '已取消导入';
    } else if (result.failures.length > 0) {
      this.hint = '完成 ' + result.imported.length + ' 本，失败 ' + result.failures.length + ' 本';
    } else if (result.imported.length > 0) {
      this.hint = '已导入 ' + result.imported.length + ' 本小说，可在书架「小说」分段查看';
    }
    if (result.imported.length > 0) {
      this.notifyShelf();
    }
  }

  private async importFiles(): Promise<void> {
    if (this.importing) {
      return;
    }
    let uris: Array<string> = [];
    try {
      uris = await NovelImportService.pickFiles();
    } catch (e) {
      this.hint = '选择文件失败：' + e;
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.reset();
    this.importing = true;
    try {
      const result = await NovelImportService.importFiles(uris, (p: NovelImportProgress) => {
        this.emitProgress(p);
      }, () => this.cancelRequested);
      this.applyResult(result);
    } catch (e) {
      this.hint = '导入失败：' + e;
    }
    this.importing = false;
  }

  private async importFolder(): Promise<void> {
    if (this.importing) {
      return;
    }
    let uris: Array<string> = [];
    try {
      uris = await NovelImportService.pickFolder();
    } catch (e) {
      this.hint = '选择目录失败：' + e;
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.reset();
    this.importing = true;
    try {
      const result = await NovelImportService.importFolder(uris[0], (p: NovelImportProgress) => {
        this.emitProgress(p);
      }, () => this.cancelRequested);
      this.applyResult(result);
    } catch (e) {
      this.hint = '目录导入失败：' + e;
    }
    this.importing = false;
  }

  @Builder
  channelCard(icon: Resource, title: string, desc: string, buttonLabel: string,
    onTap: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Image(icon)
          .width(24)
          .height(24)
          .fillColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width(42)
      .height(42)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(desc)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(buttonLabel)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.WHITE)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(15)
        .height(30)
        .padding({ left: 12, right: 12 })
        .enabled(!this.importing)
        .onClick(() => {
          onTap();
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderWidth(1)
    .borderColor(ThemeTokens.DIVIDER)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_import_novel'))
          .width(20)
          .height(20)
          .fillColor(ThemeTokens.PRIMARY)
        Text('导入小说')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('TXT · EPUB · ZIP-HTML')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      this.channelCard($r('app.media.ic_import_novel'), '小说文件',
        'txt / epub / zip-html，可多选；自动识别编码与分章', '选择文件', () => {
          this.importFiles();
        })

      this.channelCard($r('app.media.ic_import_folder'), '小说目录',
        '选择文件夹，目录内每个 txt/epub/zip 各建一本', '选择目录', () => {
          this.importFolder();
        })

      if (this.importing) {
        ProgressCard({
          title: '正在导入小说',
          phase: this.phase,
          done: this.done,
          total: this.total,
          currentName: this.currentName,
          cancelable: true,
          onCancel: () => {
            this.cancelRequested = true;
            this.phase = '正在取消…';
          }
        })
      }

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(this.failures.length > 0 ? ThemeTokens.RED : ThemeTokens.TEXT_SECONDARY)
          .width('100%')
      }

      ForEach(this.warnings, (w: string) => {
        Text(w)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.WARN)
          .width('100%')
      }, (w: string) => w)
      ForEach(this.failures, (f: NovelImportFailure) => {
        Text('「' + f.name + '」：' + f.reason)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.RED)
          .width('100%')
      }, (f: NovelImportFailure) => f.name + '-' + f.reason)
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

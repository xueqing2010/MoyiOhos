import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Manga } from 'coremodel';
import { ThemeTokens, Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes, makeImportWizardParams } from '../common/Routes';
import { ImportFailure, ImportProgress, ImportService, makeImportProgress } from '../service/ImportService';
import { DemoDataResult, DemoDataService } from '../service/DemoDataService';
import { ShelfViewModel } from '../viewmodel/ShelfViewModel';
import { ProgressCard } from '../components/ProgressCard';
import { Artwork } from '../components/Artwork';

/**
 * 漫画导入面板（stage-2 S102）：三通道（zip/cbz、图片目录、相册）+ 进度/取消/失败原因，
 * 另提供「生成示例漫画」（本地 demo 物料）与「导入向导」（确认名称/封面/页序后建档）入口。
 * 由 ImportSheet（导入 Tab / 书架底部弹层）与其自身复用；小说导入面板保持独立。
 */
@Component
export struct MangaImportPanel {
  /** 导入/示例数据完成时回调（默认空实现，可无参使用）。 */
  onImported: (mangas: Array<Manga>) => void = () => {
  };
  /** 打开导入向导的可选回调（书架弹层用它先收起底部面板再跳转）。 */
  onWizard?: () => void = undefined;

  @State private importing: boolean = false;
  @State private phase: string = '';
  @State private done: number = 0;
  @State private total: number = 0;
  @State private currentName: string = '';
  @State private failures: Array<ImportFailure> = [];
  @State private hint: string = '';
  @State private hintOk: boolean = false;
  @State private demoBusy: boolean = false;
  private cancelRequested: boolean = false;

  private emitProgress(p: ImportProgress): void {
    this.phase = p.phase;
    this.done = p.done;
    this.total = p.total;
    this.currentName = p.currentName;
  }

  private reset(): void {
    this.importing = false;
    this.phase = '';
    this.done = 0;
    this.total = 0;
    this.currentName = '';
    this.failures = [];
    this.hint = '';
    this.hintOk = false;
  }

  private showHint(msg: string, ok: boolean): void {
    this.hint = msg;
    this.hintOk = ok;
  }

  private busy(): boolean {
    return this.importing || this.demoBusy;
  }

  // ---------- 三通道入口 ----------

  private async pickArchives(): Promise<void> {
    if (this.busy()) {
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 100;
      opts.fileSuffixFilters = ['压缩包 (.zip, .cbz)|.zip,.cbz'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      this.runArchiveImport(uris);
    } catch (e) {
      Log.warn('MangaImportPanel', `archive picker failed: ${e}`);
      this.showHint(`选择压缩包失败：${e}`, false);
    }
  }

  private async pickDirectory(): Promise<void> {
    if (this.busy()) {
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.selectMode = picker.DocumentSelectMode.FOLDER;
      opts.maxSelectNumber = 1;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      this.runDirectoryImport(uris[0]);
    } catch (e) {
      Log.warn('MangaImportPanel', `folder picker failed: ${e}`);
      this.showHint(`选择目录失败：${e}`, false);
    }
  }

  private async pickPhotos(): Promise<void> {
    if (this.busy()) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 500;
      const result = await photoPicker.select(opts);
      const uris = result.photoUris;
      if (uris.length === 0) {
        return;
      }
      this.runPhotoImport(uris);
    } catch (e) {
      Log.warn('MangaImportPanel', `photo picker failed: ${e}`);
      this.showHint(`选择图片失败：${e}`, false);
    }
  }

  // ---------- 进度执行 ----------

  private runArchiveImport(uris: Array<string>): void {
    this.reset();
    this.importing = true;
    this.cancelRequested = false;
    this.total = uris.length;
    this.emitProgress(makeImportProgress('准备', 0, uris.length, ''));
    ImportService.importArchives(uris, (p: ImportProgress) => {
      this.emitProgress(p);
    }, () => {
      return this.cancelRequested;
    }).then((result) => {
      this.importing = false;
      this.failures = result.failures;
      if (result.cancelled) {
        this.showHint('已取消导入（临时文件已清理）', false);
      } else if (result.failures.length > 0) {
        this.showHint(`完成 ${result.imported.length} 个，失败 ${result.failures.length} 个`, false);
      } else {
        this.showHint(`已导入 ${result.imported.length} 本漫画`, true);
      }
      if (result.imported.length > 0) {
        ShelfViewModel.notifyChanged();
        this.onImported(result.imported);
      }
    }).catch((e: Object) => {
      this.importing = false;
      this.showHint(`导入失败：${e}`, false);
    });
  }

  private runDirectoryImport(uri: string): void {
    this.reset();
    this.importing = true;
    this.emitProgress(makeImportProgress('扫描目录', 0, 0, ImportService.lastSegment(uri)));
    ImportService.importDirectory(uri).then((manga) => {
      this.importing = false;
      this.showHint(`已导入「${manga.name}」（${manga.pageCount} 页）`, true);
      ShelfViewModel.notifyChanged();
      this.onImported([manga]);
    }).catch((e: Object) => {
      this.importing = false;
      this.showHint(`目录导入失败：${e}`, false);
    });
  }

  private runPhotoImport(uris: Array<string>): void {
    this.reset();
    this.importing = true;
    this.cancelRequested = false;
    this.emitProgress(makeImportProgress('准备', 0, uris.length, ''));
    ImportService.importPhotos(uris, (p: ImportProgress) => {
      this.emitProgress(p);
    }, () => {
      return this.cancelRequested;
    }).then((manga) => {
      this.importing = false;
      if (this.cancelRequested) {
        this.showHint('已取消导入（临时文件已清理）', false);
        return;
      }
      this.showHint(`已导入「${manga.name}」（${manga.pageCount} 页）`, true);
      ShelfViewModel.notifyChanged();
      this.onImported([manga]);
    }).catch((e: Object) => {
      this.importing = false;
      this.showHint(this.cancelRequested ? '已取消导入（临时文件已清理）' : `相册导入失败：${e}`, false);
    });
  }

  private async generateDemo(): Promise<void> {
    if (this.busy()) {
      return;
    }
    this.reset();
    this.demoBusy = true;
    try {
      const result: DemoDataResult = await DemoDataService.generateSampleManga();
      this.showHint(result.message, true);
      if (result.manga !== undefined) {
        ShelfViewModel.notifyChanged();
        this.onImported([result.manga]);
      }
    } catch (e) {
      Log.warn('MangaImportPanel', `demo generation failed: ${e}`);
      this.showHint(`${e}`, false);
    }
    this.demoBusy = false;
  }

  private openWizard(): void {
    if (this.busy()) {
      return;
    }
    if (this.onWizard !== undefined) {
      this.onWizard();
      return;
    }
    AppEnv.getInstance().navStack.pushPathByName(Routes.IMPORT_WIZARD, makeImportWizardParams(0));
  }

  // ---------- UI ----------

  @Builder
  channelCard(icon: Resource, title: string, desc: string, highlighted: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(highlighted ? ThemeTokens.PRIMARY : ThemeTokens.PRIMARY_SOFT)
      }
      .width(42)
      .height(42)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(highlighted ? '#332A5C' : ThemeTokens.SURFACE)

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

      Image(Artwork.ICON_ARROW_RIGHT)
        .width(14)
        .height(14)
        .fillColor(ThemeTokens.TEXT_HINT)
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .borderWidth(highlighted ? 1 : 0)
    .borderColor(highlighted ? '#4DA78BFA' : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  failureList() {
    if (this.failures.length > 0) {
      Column({ space: 4 }) {
        Text(`失败 ${this.failures.length} 项`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.RED)
          .width('100%')
        ForEach(this.failures, (f: ImportFailure) => {
          Row({ space: 6 }) {
            Circle({ width: 5, height: 5 })
              .fill(ThemeTokens.RED)
            Text(`「${f.name}」：${f.reason}`)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .layoutWeight(1)
              .maxLines(2)
          }
          .width('100%')
        }, (f: ImportFailure, failureIndex: number) => `${failureIndex}-${f.name}-${f.reason}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(ThemeTokens.CARD_PADDING)
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor('#1AF26D7E')
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('导入漫画')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        if (this.demoBusy) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(ThemeTokens.PRIMARY)
        }
      }
      .width('100%')

      Text('选择导入方式，支持批量与断点查看失败原因')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width('100%')

      this.channelCard(Artwork.ICON_IMPORT_ZIP, '压缩包（zip / cbz）',
        '可多选，解压后自动按文件名自然排序', false, () => {
          this.pickArchives();
        })
      this.channelCard(Artwork.ICON_IMPORT_FOLDER, '图片目录',
        '持久授权原位读取，不占额外空间；支持增量重扫', false, () => {
          this.pickDirectory();
        })
      this.channelCard(Artwork.ICON_IMPORT_PHOTO, '相册图片',
        '多选上限 500 张，按选择顺序复制进应用沙箱', false, () => {
          this.pickPhotos();
        })

      if (this.importing) {
        ProgressCard({
          title: '正在导入',
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
          .fontColor(this.hintOk ? ThemeTokens.SUCCESS : ThemeTokens.WARN)
          .width('100%')
      }

      this.failureList()

      Divider()
        .color(ThemeTokens.DIVIDER)
        .margin({ top: 2, bottom: 2 })

      Text('没有素材？可先体验示例数据')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .width('100%')

      this.channelCard(Artwork.ICON_DEMO, '生成示例漫画 · 紫夜',
        '本地示例 6 页，导入后可立即进入阅读器验证全流程', true, () => {
          this.generateDemo();
        })

      this.channelCard(Artwork.ICON_IMPORT_WIZARD, '导入向导',
        '先确认名称、封面与页序，再正式建档', false, () => {
          this.openWizard();
        })
    }
    .padding({
      left: 0,
      right: 0,
      top: 4,
      bottom: ThemeTokens.PAGE_PADDING
    })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
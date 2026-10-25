import { uiMaterial } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { SourceType } from 'coremodel';
import { ThemeTokens, Log, toMediaUri } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { asImportWizardParams, ImportWizardParams, makeReaderParams, Routes } from '../common/Routes';
import {
  ImportProgress,
  ImportService,
  makeImportProgress,
  StagedManga,
  StagedPage
} from '../service/ImportService';
import { ShelfViewModel } from '../viewmodel/ShelfViewModel';
import { lastPathSegment, makeWizardRows, WizardPageRow } from '../model/UiModels';
import { ProgressCard } from '../components/ProgressCard';
import { Artwork } from '../components/Artwork';

/**
 * 导入向导（stage-2 S102）：导入前确认后建档。
 * 1) 选择来源（zip/cbz、图片目录、相册）→ 暂存解压/扫描（可取消，不留残缺记录）
 * 2) 确认：可改名称、从页列表选封面、页数汇总、页序预览与上下移调整
 * 3) 建档成功 → 返回书架或直接进入阅读器
 * 参数：Routes.ImportWizardParams.kind（0=漫画；1=小说由小说模块负责，此处提示）。
 */
@Component
export struct ImportWizardPage {
  @State private kind: number = 0;
  @State private step: number = 0; // 0 选来源 / 1 确认 / 2 成功
  @State private staging: boolean = false;
  @State private committing: boolean = false;
  @State private phase: string = '';
  @State private done: number = 0;
  @State private total: number = 0;
  @State private currentName: string = '';
  @State private hint: string = '';
  @State private stageName: string = '';
  @State private rows: Array<WizardPageRow> = [];
  @State private coverPath: string = '';
  @State private sourceLabel: string = '';
  @State private createdId: number = -1;
  @State private createdName: string = '';
  @State private createdCount: number = 0;
  private staged: StagedManga | undefined = undefined;
  private cancelRequested: boolean = false;
  private leaving: boolean = false;
  /** 暂存时的原始页序（用于「恢复默认页序」）。 */
  private originalPaths: Array<string> = [];

  aboutToDisappear(): void {
    this.discardStaged();
  }

  private discardStaged(): void {
    if (this.staged !== undefined) {
      ImportService.discardStaged(this.staged);
      this.staged = undefined;
    }
  }

  private emitProgress(p: ImportProgress): void {
    this.phase = p.phase;
    this.done = p.done;
    this.total = p.total;
    this.currentName = p.currentName;
  }

  private resetToSource(): void {
    this.discardStaged();
    this.step = 0;
    this.staging = false;
    this.committing = false;
    this.phase = '';
    this.done = 0;
    this.total = 0;
    this.currentName = '';
    this.hint = '';
    this.stageName = '';
    this.rows = [];
    this.coverPath = '';
    this.sourceLabel = '';
  }

  private applyStaged(staged: StagedManga): void {
    this.discardStaged();
    this.staged = staged;
    const paths: Array<string> = [];
    for (const p of staged.pages) {
      paths.push(p.path);
    }
    this.rows = makeWizardRows(paths);
    this.originalPaths = paths.slice();
    this.stageName = staged.name;
    this.coverPath = paths.length > 0 ? paths[0] : '';
    this.sourceLabel = ImportWizardPage.sourceTypeLabel(staged.sourceType);
    this.step = 1;
    this.staging = false;
  }

  private static sourceTypeLabel(t: SourceType): string {
    if (t === SourceType.DIRECTORY) {
      return '图片目录（原位读取）';
    }
    if (t === SourceType.ALBUM) {
      return '相册图片（复制入沙箱）';
    }
    return '压缩包（解压暂存）';
  }

  // ---------- 来源选择 ----------

  private async pickArchive(): Promise<void> {
    if (this.staging) {
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['压缩包 (.zip, .cbz)|.zip,.cbz'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      this.runStageArchive(uris[0]);
    } catch (e) {
      this.hint = `选择压缩包失败：${e}`;
    }
  }

  private async pickDirectory(): Promise<void> {
    if (this.staging) {
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
      this.runStageDirectory(uris[0]);
    } catch (e) {
      this.hint = `选择目录失败：${e}`;
    }
  }

  private async pickPhotos(): Promise<void> {
    if (this.staging) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 500;
      const result = await photoPicker.select(opts);
      if (result.photoUris.length === 0) {
        return;
      }
      this.runStagePhotos(result.photoUris);
    } catch (e) {
      this.hint = `选择图片失败：${e}`;
    }
  }

  private runStageArchive(uri: string): void {
    this.staging = true;
    this.cancelRequested = false;
    this.hint = '';
    this.emitProgress(makeImportProgress('解压', 0, 0, ImportService.lastSegment(uri)));
    ImportService.stageArchive(uri, (p: ImportProgress) => {
      this.emitProgress(p);
    }, () => {
      return this.cancelRequested;
    }).then((staged: StagedManga) => {
      this.applyStaged(staged);
    }).catch((e: Object) => {
      this.staging = false;
      this.hint = this.cancelRequested ? '已取消导入（临时文件已清理）' : `解压失败：${e}`;
    });
  }

  private runStageDirectory(uri: string): void {
    this.staging = true;
    this.hint = '';
    this.emitProgress(makeImportProgress('扫描目录', 0, 0, ImportService.lastSegment(uri)));
    ImportService.stageDirectory(uri).then((staged: StagedManga) => {
      this.applyStaged(staged);
    }).catch((e: Object) => {
      this.staging = false;
      this.hint = `目录扫描失败：${e}`;
    });
  }

  private runStagePhotos(uris: Array<string>): void {
    this.staging = true;
    this.hint = '';
    ImportService.stagePhotos(uris, (p: ImportProgress) => {
      this.emitProgress(p);
    }).then((staged: StagedManga) => {
      this.applyStaged(staged);
    }).catch((e: Object) => {
      this.staging = false;
      this.hint = `相册扫描失败：${e}`;
    });
  }

  // ---------- 确认页操作 ----------

  private movePage(index: number, delta: number): void {
    const target = index + delta;
    if (target < 0 || target >= this.rows.length) {
      return;
    }
    const rows = this.rows.slice();
    const tmp = rows[index];
    rows[index] = rows[target];
    rows[target] = tmp;
    const rebuilt: Array<WizardPageRow> = [];
    for (let i = 0; i < rows.length; i++) {
      rows[i].order = i;
      rebuilt.push(rows[i]);
    }
    this.rows = rebuilt;
  }

  private selectCover(path: string): void {
    this.coverPath = path;
  }

  /** 恢复暂存时的默认页序（自然排序结果）。 */
  private resetPageOrder(): void {
    if (this.originalPaths.length === 0) {
      return;
    }
    this.rows = makeWizardRows(this.originalPaths);
  }

  private async commit(): Promise<void> {
    const staged = this.staged;
    if (staged === undefined || this.committing) {
      if (staged === undefined) {
        this.hint = '暂存已失效，请重新选择来源';
      }
      return;
    }
    const name = this.stageName.trim();
    if (name.length === 0) {
      this.hint = '请输入漫画名称';
      return;
    }
    if (this.rows.length === 0) {
      this.hint = '没有可导入的页面';
      return;
    }
    this.committing = true;
    this.hint = '';
    const paths: Array<string> = [];
    for (const r of this.rows) {
      paths.push(r.path);
    }
    let coverIndex = paths.indexOf(this.coverPath);
    if (coverIndex < 0) {
      coverIndex = 0;
    }
    // 按调整后的页序重建暂存页列表。
    const pages: Array<StagedPage> = [];
    for (let i = 0; i < paths.length; i++) {
      pages.push(new StagedPage(paths[i], lastPathSegment(paths[i])));
    }
    staged.pages = pages;
    try {
      const manga = await ImportService.commitStaged(staged, name, coverIndex);
      this.staged = undefined;
      this.createdId = manga.id;
      this.createdName = manga.name;
      this.createdCount = manga.pageCount;
      this.step = 2;
      this.committing = false;
      ShelfViewModel.notifyChanged();
    } catch (e) {
      // 失败时暂存可能已被部分消费，回退到来源选择并提示重新选择。
      this.committing = false;
      const message = `建档失败：${e}。请重新选择来源`;
      this.discardStaged();
      this.rows = [];
      this.coverPath = '';
      this.stageName = '';
      this.step = 0;
      this.hint = message;
    }
  }

  private finishToShelf(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    this.discardStaged();
    AppEnv.getInstance().navStack.pop();
  }

  private openCreatedReader(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    const id = this.createdId;
    this.discardStaged();
    AppEnv.getInstance().navStack.pop();
    if (id > 0) {
      setTimeout(() => {
        AppEnv.getInstance().navStack.pushPathByName(Routes.READER, makeReaderParams(id));
      }, 160);
    }
  }

  // ---------- UI ----------

  @Builder
  channelCard(icon: Resource, title: string, desc: string, onTap: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(ThemeTokens.PRIMARY_SOFT)
      }
      .width(42)
      .height(42)
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
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
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  novelNotice() {
    Column({ space: 12 }) {
      Image(Artwork.ICON_IMPORT_NOVEL)
        .width(44)
        .height(44)
        .fillColor(ThemeTokens.PRIMARY_SOFT)
      Text('小说导入向导')
        .fontSize(ThemeTokens.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text('小说（txt / epub / zip-html）导入由小说模块承载，请回到「导入」页使用小说面板。此处仅提供漫画导入向导。')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
      Button('返回')
        .height(40)
        .padding({ left: 28, right: 28 })
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .onClick(() => {
          this.finishToShelf();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeTokens.PAGE_PADDING)
  }

  @Builder
  sourceStep() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 2 }) {
          Text('选择导入来源')
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .width('100%')
          Text('先暂存预览，确认名称/封面/页序后再正式建档')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)

        this.channelCard(Artwork.ICON_IMPORT_ZIP, '压缩包（zip / cbz）',
          '解压到临时目录后按文件名自然排序', () => {
            this.pickArchive();
          })
        this.channelCard(Artwork.ICON_IMPORT_FOLDER, '图片目录',
          '持久授权原位读取，不复制文件', () => {
            this.pickDirectory();
          })
        this.channelCard(Artwork.ICON_IMPORT_PHOTO, '相册图片',
          '多选上限 500 张，确认后复制入沙箱', () => {
            this.pickPhotos();
          })

        if (this.staging) {
          ProgressCard({
            title: '正在暂存',
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
            .fontColor(ThemeTokens.WARN)
            .width('100%')
        }

        Column({ space: 4 }) {
          Text('说明')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
          Text('· 取消或返回会自动清理临时文件，不会在书架留下残缺记录')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text('· 目录来源不复制文件，删除漫画时仅移除记录并释放授权')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(ThemeTokens.CARD_PADDING)
        .borderRadius(ThemeTokens.RADIUS_CARD)
        .backgroundColor(ThemeTokens.CARD_BG)
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  coverStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.rows.slice(0, 80), (row: WizardPageRow, index: number) => {
          Column({ space: 3 }) {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image(toMediaUri(row.path))
                .width(52)
                .height(74)
                .objectFit(ImageFit.Cover)
                .borderRadius(6)
              Text(`${index + 1}`)
                .fontSize(9)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .backgroundColor('#CC0B0813')
                .margin(3)
              if (row.path === this.coverPath) {
                Stack() {
                  Image(Artwork.ICON_CHECK)
                    .width(14)
                    .height(14)
                    .fillColor(ThemeTokens.BLACK)
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(ThemeTokens.PRIMARY)
                .position({ x: '100%', y: 0 })
                .markAnchor({ x: '100%', y: 0 })
                .margin(3)
              }
            }
            .borderWidth(row.path === this.coverPath ? 2 : 0)
            .borderColor(ThemeTokens.PRIMARY)
            .borderRadius(7)
            Text(row.path === this.coverPath ? '封面' : '选为封面')
              .fontSize(9)
              .fontColor(row.path === this.coverPath ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
          }
          .onClick(() => {
            this.selectCover(row.path);
          })
        }, (row: WizardPageRow) => row.key)
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(108)
  }

  @Builder
  orderRow(row: WizardPageRow, index: number) {
    Row({ space: 10 }) {
      Text(`${index + 1}`)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(index === 0 ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
        .width(24)
        .textAlign(TextAlign.Center)
      Image(toMediaUri(row.path))
        .width(28)
        .height(38)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
      Text(row.label)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(row.path === this.coverPath ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (row.path === this.coverPath) {
        Text('封面')
          .fontSize(9)
          .fontColor(ThemeTokens.PRIMARY)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor('#33A78BFA')
      }
      Stack() {
        Image(Artwork.ICON_PAGE_UP)
          .width(14)
          .height(14)
          .fillColor(index === 0 ? ThemeTokens.TEXT_TERTIARY : ThemeTokens.TEXT_SECONDARY)
      }
      .width(26)
      .height(26)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        this.movePage(index, -1);
      })
      Stack() {
        Image(Artwork.ICON_PAGE_DOWN)
          .width(14)
          .height(14)
          .fillColor(index === this.rows.length - 1 ? ThemeTokens.TEXT_TERTIARY : ThemeTokens.TEXT_SECONDARY)
      }
      .width(26)
      .height(26)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        this.movePage(index, 1);
      })
    }
    .width('100%')
    .height(50)
    .padding({ left: 4, right: 4 })
  }

  @Builder
  confirmStep() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image(Artwork.ICON_ARROW_RIGHT)
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.TEXT_SECONDARY)
          .rotate({ angle: 180 })
          .onClick(() => {
            this.resetToSource();
          })
        Column({ space: 1 }) {
          Text('确认导入')
            .fontSize(ThemeTokens.FONT_SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(`来源：${this.sourceLabel} · 共 ${this.rows.length} 页`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Column({ space: 6 }) {
        Text('漫画名称')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        TextInput({ text: this.stageName, placeholder: '输入漫画名称' })
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .placeholderColor(ThemeTokens.TEXT_HINT)
          .caretColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .height(42)
          .onChange((v: string) => {
            this.stageName = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Row() {
          Text('封面（从页列表选择）')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
            .layoutWeight(1)
          Text('点击缩略图选择')
            .fontSize(9)
            .fontColor(ThemeTokens.TEXT_TERTIARY)
        }
        .width('100%')
        this.coverStrip()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('页序预览')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1)
        Text('恢复默认页序')
          .fontSize(9)
          .fontColor(ThemeTokens.PRIMARY_SOFT)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.resetPageOrder();
          })
        Text('上下移调整')
          .fontSize(9)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .margin({ left: 8 })
      }
      .width('100%')

      List({ space: 4 }) {
        ForEach(this.rows, (row: WizardPageRow, index: number) => {
          ListItem() {
            this.orderRow(row, index)
          }
        }, (row: WizardPageRow) => row.key)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.WARN)
          .width('100%')
      }

      Row({ space: 10 }) {
        Button(this.committing ? '正在建档…' : '取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .enabled(!this.committing)
          .onClick(() => {
            this.resetToSource();
          })
        Button() {
          Row({ space: 6 }) {
            if (this.committing) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(ThemeTokens.TEXT_ON_PRIMARY)
            }
            Text(this.committing ? '正在建档' : '确认建档')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          }
        }
        .layoutWeight(2)
        .height(42)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .enabled(!this.committing)
        .onClick(() => {
          this.commit();
        })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding(ThemeTokens.PAGE_PADDING)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  successStep() {
    Column({ space: 14 }) {
      Stack() {
        Image(Artwork.ICON_CHECK)
          .width(30)
          .height(30)
          .fillColor(ThemeTokens.BLACK)
      }
      .width(58)
      .height(58)
      .borderRadius(29)
      .backgroundColor(ThemeTokens.SUCCESS)
      Text('建档成功')
        .fontSize(ThemeTokens.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(`「${this.createdName}」· ${this.createdCount} 页`)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
      Row({ space: 10 }) {
        Button('返回书架')
          .height(42)
          .padding({ left: 22, right: 22 })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .onClick(() => {
            this.finishToShelf();
          })
        Button('进入阅读器')
          .height(42)
          .padding({ left: 22, right: 22 })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .onClick(() => {
            this.openCreatedReader();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeTokens.PAGE_PADDING)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.kind !== 0) {
          this.novelNotice()
        } else if (this.step === 2) {
          this.successStep()
        } else if (this.step === 1) {
          this.confirmStep()
        } else {
          this.sourceStep()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeTokens.SURFACE)
    }
    // 使用默认 STANDARD 标题栏：内容自动排在标题栏下方，避免 STACK 遮挡首行；
    // 沉浸光感材质仍作用于标题栏。
    .title('导入向导', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onReady((ctx: NavDestinationContext) => {
      const params: ImportWizardParams = asImportWizardParams(ctx.pathInfo.param as Object);
      this.kind = params.kind;
    })
    .onBackPressed((): boolean => {
      if (this.committing) {
        // 建档中不可返回，避免暂存被中途丢弃。
        return true;
      }
      if (this.staging) {
        this.cancelRequested = true;
        this.hint = '正在取消暂存…';
        return true;
      }
      if (this.step === 1) {
        this.resetToSource();
        return true;
      }
      this.discardStaged();
      return false;
    })
  }
}
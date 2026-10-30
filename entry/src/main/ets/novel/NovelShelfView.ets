import { TranslateStatus } from 'coremodel';
import { ThemeTokens, WindowSizeClass, observeBreakpoint } from 'commons';
import { Routes, makeNovelReaderParams } from '../common/Routes';
import { AppEnv } from '../common/AppEnv';
import { NovelShelfItem } from '../data/NovelRepository';
import { NovelViewModel } from '../viewmodel/NovelViewModel';
import {
  NovelImportFailure,
  NovelImportProgress,
  NovelImportResult,
  NovelImportService
} from '../service/NovelImportService';
import { ProgressCard } from '../components/ProgressCard';
import { EmptyState } from '../components/EmptyState';
import { Artwork } from '../components/Artwork';
import { NovelCover, NovelStatusBadge } from './NovelUi';

/**
 * 小说书架分段（对齐上游 novel/shelf；S101/S103 阶段2）：由 ShelfView 以分段形式嵌入，无参实例化。
 * 网格/列表双视图（按断点自适应列数）、封面/书名/章节数/翻译状态、长按多选删除
 * （连带章节与译文）、空态（导入示例小说/文件/目录）、点击进阅读器。
 * 刷新约定：外部导入完成后 setOrCreate('starflow_shelf_dirty', ...) 即可触发刷新。
 */
@Component
export struct NovelShelfView {
  @StorageProp('starflow_shelf_dirty') @Watch('onShelfDirty') dirtyTick: number = 0;
  @State items: Array<NovelShelfItem> = [];
  @State viewMode: string = 'grid';
  @State loaded: boolean = false;
  @State selectMode: boolean = false;
  @State selectedIds: Array<number> = [];
  @State hint: string = '';
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State sortKey: string = 'recent';
  @State containerWidth: number = 0;
  @State importing: boolean = false;
  @State phase: string = '';
  @State done: number = 0;
  @State total: number = 0;
  @State currentName: string = '';
  @State failures: Array<NovelImportFailure> = [];
  @State warnings: Array<string> = [];
  private cancelRequested: boolean = false;
  private lastRefreshAt: number = 0;
  private stopBreakpoint: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
      this.sizeClass = c;
    });
    this.init();
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  /** 外部（漫画导入/向导）刷新信号。 */
  onShelfDirty(): void {
    this.refresh();
  }

  private async init(): Promise<void> {
    this.viewMode = await NovelViewModel.loadShelfViewMode();
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    let list: Array<NovelShelfItem> = [];
    try {
      list = await NovelViewModel.loadShelf();
    } catch (e) {
      list = [];
    }
    this.items = this.sorted(list);
    this.loaded = true;
  }

  /** 排序：最近阅读（updated_at 倒序）/ 书名 / 导入时间（id 倒序）。 */
  private sorted(source: Array<NovelShelfItem>): Array<NovelShelfItem> {
    const list = source.slice();
    if (this.sortKey === 'name') {
      list.sort((a: NovelShelfItem, b: NovelShelfItem): number => {
        if (a.name === b.name) {
          return b.id - a.id;
        }
        return a.name < b.name ? -1 : 1;
      });
    } else if (this.sortKey === 'imported') {
      list.sort((a: NovelShelfItem, b: NovelShelfItem): number => b.id - a.id);
    } else {
      list.sort((a: NovelShelfItem, b: NovelShelfItem): number => b.updatedAt - a.updatedAt);
    }
    return list;
  }

  private sortLabel(): string {
    if (this.sortKey === 'name') {
      return '名称';
    }
    if (this.sortKey === 'imported') {
      return '导入时间';
    }
    return '最近阅读';
  }

  private cycleSort(): void {
    if (this.sortKey === 'recent') {
      this.sortKey = 'name';
    } else if (this.sortKey === 'name') {
      this.sortKey = 'imported';
    } else {
      this.sortKey = 'recent';
    }
    this.items = this.sorted(this.items);
  }

  private showHint(msg: string): void {
    this.hint = msg;
  }

  private notifyShelfDirty(): void {
    AppStorage.setOrCreate('starflow_shelf_dirty', Date.now());
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    const idx = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
    } else {
      this.selectedIds.push(id);
    }
  }

  private enterSelectMode(id: number): void {
    this.selectMode = true;
    this.selectedIds = [id];
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  private toggleSelectAll(): void {
    if (this.selectedIds.length === this.items.length) {
      this.selectedIds = [];
      return;
    }
    const ids: Array<number> = [];
    for (let i = 0; i < this.items.length; i++) {
      ids.push(this.items[i].id);
    }
    this.selectedIds = ids;
  }

  private requestDelete(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    const count = this.selectedIds.length;
    try {
      this.getUIContext().showAlertDialog({
        title: '删除小说',
        message: '将删除选中的 ' + count + ' 本小说，章节与译文一并移除（原文件不删除）。',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '删除',
          fontColor: ThemeTokens.RED,
          action: () => {
            this.deleteSelected();
          }
        }
      });
    } catch (e) {
      // 弹窗失败时保持选中态，避免误删
    }
  }

  private async deleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return;
    }
    const count = this.selectedIds.length;
    const deleted = await NovelViewModel.deleteNovels(this.selectedIds.slice());
    this.exitSelectMode();
    await this.refresh();
    this.notifyShelfDirty();
    this.showHint(deleted < count ? '已删除 ' + deleted + ' 本，' + (count - deleted) + ' 本删除失败'
      : '已删除 ' + deleted + ' 本小说');
  }

  private toggleViewMode(): void {
    this.viewMode = this.viewMode === 'grid' ? 'list' : 'grid';
    NovelViewModel.saveShelfViewMode(this.viewMode);
  }

  private openReader(item: NovelShelfItem): void {
    // 不显式传章节：让阅读器按数据库中的 lastReadChapter 恢复，避免书架投影
    // 尚未刷新时把旧章节（0）写死进参数、进而覆盖已保存的阅读进度。
    AppEnv.getInstance().navStack.pushPathByName(Routes.NOVEL_READER,
      makeNovelReaderParams(item.id));
  }

  private onCardTap(item: NovelShelfItem): void {
    if (this.selectMode) {
      this.toggleSelect(item.id);
    } else {
      this.openReader(item);
    }
  }

  private gridColumnsCount(): number {
    if (this.sizeClass === WindowSizeClass.LG) {
      return 5;
    }
    if (this.sizeClass === WindowSizeClass.MD) {
      return 3;
    }
    return 2;
  }

  private gridColumns(): string {
    let template = '1fr';
    for (let i = 1; i < this.gridColumnsCount(); i++) {
      template += ' 1fr';
    }
    return template;
  }

  /**
   * 网格封面高度：按列宽固定 3:4（width:height = 3:4），保证封面不被裁切、
   * 卡片文本区（书名 + 徽标/章节数）永远在封面下方。
   */
  private gridCoverHeight(): number {
    const total = this.containerWidth > 0 ? this.containerWidth : 360;
    const columns = this.gridColumnsCount();
    const pagePadding = ThemeTokens.PAGE_PADDING * 2;
    const gaps = 10 * (columns - 1);
    const itemWidth = (total - pagePadding - gaps) / columns;
    const coverWidth = Math.max(72, itemWidth - 12);
    return Math.round(coverWidth * 4 / 3);
  }

  // ---------- 导入 ----------

  private resetProgress(): void {
    this.phase = '';
    this.done = 0;
    this.total = 0;
    this.currentName = '';
    this.failures = [];
    this.warnings = [];
    this.cancelRequested = false;
  }

  private emitProgress(p: NovelImportProgress): void {
    this.phase = p.phase;
    this.done = p.done;
    this.total = p.total;
    this.currentName = p.currentName;
  }

  private applyResult(result: NovelImportResult): void {
    this.failures = result.failures;
    this.warnings = result.warnings;
    if (result.cancelled) {
      this.hint = '已取消导入';
    } else if (result.failures.length > 0) {
      this.hint = '完成 ' + result.imported.length + ' 本，失败 ' + result.failures.length + ' 本';
    } else if (result.imported.length > 0) {
      this.hint = '已导入 ' + result.imported.length + ' 本小说';
    }
    if (result.imported.length > 0) {
      this.notifyShelfDirty();
    }
  }

  private async pickFiles(): Promise<void> {
    if (this.importing) {
      return;
    }
    let uris: Array<string> = [];
    try {
      uris = await NovelImportService.pickFiles();
    } catch (e) {
      this.showHint('选择文件失败：' + e);
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.resetProgress();
    this.importing = true;
    this.phase = '准备';
    try {
      const result = await NovelImportService.importFiles(uris, (p: NovelImportProgress) => {
        this.emitProgress(p);
      }, () => this.cancelRequested);
      this.applyResult(result);
      await this.refresh();
    } catch (e) {
      this.showHint('导入失败：' + e);
    }
    this.importing = false;
  }

  private async pickFolder(): Promise<void> {
    if (this.importing) {
      return;
    }
    let uris: Array<string> = [];
    try {
      uris = await NovelImportService.pickFolder();
    } catch (e) {
      this.showHint('选择目录失败：' + e);
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.resetProgress();
    this.importing = true;
    this.phase = '扫描目录';
    try {
      const result = await NovelImportService.importFolder(uris[0], (p: NovelImportProgress) => {
        this.emitProgress(p);
      }, () => this.cancelRequested);
      this.applyResult(result);
      await this.refresh();
    } catch (e) {
      this.showHint('目录导入失败：' + e);
    }
    this.importing = false;
  }

  // ---------- UI ----------

  @Builder
  topBar() {
    Row({ space: 8 }) {
      if (this.selectMode) {
        Text('已选 ' + this.selectedIds.length + ' 本')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Button(this.selectedIds.length === this.items.length && this.items.length > 0 ? '取消全选' : '全选')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(14)
          .height(30)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.toggleSelectAll();
          })
        Button('删除 (' + this.selectedIds.length + ')')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.WHITE)
          .backgroundColor(this.selectedIds.length > 0 ? ThemeTokens.RED : ThemeTokens.SURFACE_VARIANT)
          .borderRadius(14)
          .height(30)
          .padding({ left: 12, right: 12 })
          .enabled(this.selectedIds.length > 0)
          .onClick(() => {
            this.requestDelete();
          })
        Button('完成')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(14)
          .height(30)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.exitSelectMode();
          })
      } else {
        Row({ space: 4 }) {
          Image($r('app.media.ic_sort'))
            .width(15)
            .height(15)
            .fillColor(ThemeTokens.TEXT_HINT)
          Text(this.sortLabel())
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
        }
        .height(30)
        .padding({ left: 8, right: 8 })
        .borderRadius(14)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.cycleSort();
        })

        Row({ space: 6 }) {
          Image(this.viewMode === 'grid' ? $r('app.media.ic_view_list') : $r('app.media.ic_view_grid'))
            .width(18)
            .height(18)
            .fillColor(ThemeTokens.TEXT_SECONDARY)
          Text(this.viewMode === 'grid' ? '网格' : '列表')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
        }
        .height(30)
        .padding({ left: 8, right: 8 })
        .borderRadius(14)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.toggleViewMode();
        })

        Image($r('app.media.ic_refresh'))
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.TEXT_SECONDARY)
          .padding(7)
          .borderRadius(14)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.refresh();
            this.showHint('已刷新');
          })

        Blank()

        if (this.items.length > 0) {
          Button('多选')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(14)
            .height(30)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.selectMode = true;
              this.selectedIds = [];
            })
        }
        Button('+ 导入')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.WHITE)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(14)
          .height(30)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.pickFiles();
          })
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
  }

  @Builder
  progressArea() {
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
  }

  @Builder
  emptyView() {
    Stack({ alignContent: Alignment.Bottom }) {
      EmptyState({
        icon: Artwork.EMPTY_NOVEL,
        title: '还没有小说',
        hint: '支持 txt / epub / zip-html，导入后自动分章',
        iconSize: 132
      })
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Button('导入文件')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(18)
            .height(36)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.pickFiles();
            })
        }
        Button('从目录导入（每个文件一本）')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .borderWidth(1)
          .borderColor(ThemeTokens.DIVIDER)
          .borderRadius(18)
          .height(34)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.pickFolder();
          })
      }
      .margin({ bottom: 26 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  gridCard(item: NovelShelfItem) {
    Column({ space: 6 }) {
      // 封面区：固定 3:4，选中勾选浮在封面左上角（仅多选态）。
      Stack({ alignContent: Alignment.TopStart }) {
        NovelCover({
          name: item.name,
          coverPath: item.coverPath,
          novelId: item.id,
          coverHeight: this.gridCoverHeight(),
          radius: ThemeTokens.RADIUS_SMALL
        })
        if (this.selectMode) {
          Text(this.isSelected(item.id) ? '✓' : '')
            .fontSize(12)
            .fontColor(ThemeTokens.WHITE)
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(10)
            .backgroundColor(this.isSelected(item.id) ? ThemeTokens.PRIMARY : '#66000000')
            .margin(6)
        }
      }
      .width('100%')

      // 文本区：书名 1 行省略；下一行「状态徽标 + 章节数 · 格式」。
      Text(item.name)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(20)
      Row({ space: 6 }) {
        NovelStatusBadge({
          label: item.statusLabel,
          done: item.translateStatus === TranslateStatus.DONE,
          partial: item.translateStatus === TranslateStatus.PARTIAL_FAILED
        })
        Text(item.chapterCount + ' 章 · ' + item.formatLabel)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(20)
      if (item.progressLabel.length > 0) {
        Text(item.progressLabel)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.PRIMARY_SOFT)
          .maxLines(1)
          .width('100%')
      }
    }
    .width('100%')
    .padding(6)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(this.isSelected(item.id) ? ThemeTokens.CARD_HOVER : Color.Transparent)
    .onClick(() => {
      this.onCardTap(item);
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.selectMode) {
        this.enterSelectMode(item.id);
      }
    }))
  }

  @Builder
  listCard(item: NovelShelfItem) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        NovelCover({
          name: item.name,
          coverPath: item.coverPath,
          novelId: item.id,
          coverHeight: 76,
          radius: 8
        })
        if (this.selectMode) {
          Text(this.isSelected(item.id) ? '✓' : '')
            .fontSize(11)
            .fontColor(ThemeTokens.WHITE)
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .borderRadius(9)
            .backgroundColor(this.isSelected(item.id) ? ThemeTokens.PRIMARY : '#66000000')
            .margin(4)
        }
      }
      .width(56)

      Column({ space: 5 }) {
        Text(item.name)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          NovelStatusBadge({
            label: item.statusLabel,
            done: item.translateStatus === TranslateStatus.DONE,
            partial: item.translateStatus === TranslateStatus.PARTIAL_FAILED
          })
          Text(item.chapterCount + ' 章 · ' + item.formatLabel)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        if (item.progressLabel.length > 0) {
          Text(item.progressLabel)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_TERTIARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(10)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(this.isSelected(item.id) ? ThemeTokens.CARD_HOVER : ThemeTokens.CARD_BG)
    .onClick(() => {
      this.onCardTap(item);
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.selectMode) {
        this.enterSelectMode(item.id);
      }
    }))
  }

  private cardKey(item: NovelShelfItem): string {
    const selected = this.isSelected(item.id) ? 's' : 'n';
    return item.id + ':' + selected + ':' + this.viewMode;
  }

  build() {
    Column() {
      this.topBar()
      if (this.importing) {
        this.progressArea()
      }
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%')
          .padding({ left: 4, right: 4, top: 2, bottom: 4 })
          .onClick(() => {
            this.hint = '';
          })
      }
      ForEach(this.warnings, (w: string) => {
        Text(w)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.WARN)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }, (w: string) => w)
      ForEach(this.failures, (f: NovelImportFailure) => {
        Text('「' + f.name + '」：' + f.reason)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.RED)
          .width('100%')
          .padding({ left: 4, right: 4 })
      }, (f: NovelImportFailure) => f.name + '-' + f.reason)
      if (this.loaded && this.items.length === 0) {
        this.emptyView()
      } else if (this.viewMode === 'list') {
        List({ space: 8 }) {
          ForEach(this.items, (item: NovelShelfItem) => {
            ListItem() {
              this.listCard(item)
            }
          }, (item: NovelShelfItem) => this.cardKey(item))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ bottom: 8 })
      } else {
        Grid() {
          ForEach(this.items, (item: NovelShelfItem) => {
            GridItem() {
              this.gridCard(item)
            }
          }, (item: NovelShelfItem) => this.cardKey(item))
        }
        .columnsTemplate(this.gridColumns())
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ bottom: 8 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING })
    .backgroundColor(ThemeTokens.SURFACE)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width as number;
      if (w > 0 && Math.abs(w - this.containerWidth) >= 1) {
        this.containerWidth = w;
      }
    })
    .onVisibleAreaChange([0.0, 1.0], (visible: boolean, ratio: number) => {
      // 从阅读器返回时刷新阅读进度标签（1s 节流，避免抖动）。
      if (visible && ratio > 0.5 && this.loaded && !this.importing
        && Date.now() - this.lastRefreshAt > 1000) {
        this.lastRefreshAt = Date.now();
        this.refresh();
      }
    })
  }
}

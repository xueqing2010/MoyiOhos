import { Manga } from 'coremodel';
import { ThemeTokens, WindowSizeClass, observeBreakpoint, toMediaUri } from 'commons';
import { Artwork } from '../components/Artwork';
import { EmptyState } from '../components/EmptyState';
import { AppEnv } from '../common/AppEnv';
import { Routes, makeImportWizardParams, makeReaderParams } from '../common/Routes';
import { ImportSheet } from './ImportSheet';
import { MangaCoverCard } from '../components/MangaCoverCard';
import { NovelShelfView } from '../novel/NovelShelfView';
import { DemoDataResult, DemoDataService } from '../service/DemoDataService';
import { ExportMode, ExportResult } from '../service/ExportService';
import {
  gridColumnsTemplate,
  makeMangaDisplay,
  MangaDisplay,
  shelfColumnsForWidth,
  shelfListColumns,
  shelfSortModeLabel,
  ShelfSegment,
  ShelfSortMode,
  sortMangaDisplays
} from '../model/UiModels';
import { DirectoryRefreshResult, ShelfViewModel } from '../viewmodel/ShelfViewModel';

/**
 * 书架 Tab（stage-2 S101 / 对齐上游 mangaimport shelf + novel/shelf）：
 * · 顶部「书架」标题 + 导入；分段「漫画 / 小说」（小说分段嵌入 NovelShelfView）
 * · 排序（最近阅读 / 名称 / 导入时间，持久化）、列表/网格双视图（starflow_shelf:view_mode）
 * · 网格列数按宽度断点 2/3/4/5；列表模式宽屏双列
 * · 多选删除（DB 级联译文 + 沙箱/URI 授权清理）、长按菜单（重命名/换封面/导出/批翻/删除）
 * · 目录源增量刷新、阅读器入口（Routes.READER，从上次阅读页继续）
 */
@Component
export struct ShelfView {
  @State displays: Array<MangaDisplay> = [];
  @State viewMode: string = 'grid';
  @State sortMode: ShelfSortMode = ShelfSortMode.RECENT;
  @State segment: ShelfSegment = ShelfSegment.MANGA;
  @State selectMode: boolean = false;
  @State selectedIds: Array<number> = [];
  @State loaded: boolean = false;
  @State hint: string = '';
  @State showImportSheet: boolean = false;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  @State areaWidth: number = 360;
  @State refreshingDirs: boolean = false;
  @State demoBusy: boolean = false;

  // 弹层状态（全部用页面内遮罩实现，统一紫夜配色）
  @State showTools: boolean = false;
  @State showSort: boolean = false;
  @State showMenu: boolean = false;
  @State menuId: number = -1;
  @State menuName: string = '';
  @State showRename: boolean = false;
  @State renameId: number = -1;
  @State renameValue: string = '';
  @State showCover: boolean = false;
  @State coverId: number = -1;
  @State coverPages: Array<string> = [];
  @State coverCurrent: string = '';
  @State coverLoading: boolean = false;
  @State showExportModes: boolean = false;
  @State exportMangaId: number = -1;
  @State exporting: boolean = false;
  @State exportDone: number = 0;
  @State exportTotal: number = 0;
  @State showConfirmDelete: boolean = false;
  @State deleteIds: Array<number> = [];
  @State confirmText: string = '';

  /** 跨 Tab 刷新信号（导入/向导/示例数据完成时由 MangaImportPanel 写入）。 */
  @StorageLink('starflow_shelf_dirty') @Watch('onShelfDirty') shelfDirty: number = 0;

  private mangas: Array<Manga> = [];
  private stopBreakpoint: (() => void) | undefined = undefined;
  private lastRefreshAt: number = 0;

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

  onShelfDirty(): void {
    this.refresh();
  }

  private async init(): Promise<void> {
    try {
      this.viewMode = await ShelfViewModel.loadViewMode();
      this.sortMode = await ShelfViewModel.loadSortMode();
      this.segment = await ShelfViewModel.loadSegment();
    } catch (e) {
      // 偏好读取失败沿用默认值
    }
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    try {
      this.mangas = await ShelfViewModel.loadMangas();
      this.applyFilterAndSort();
    } catch (e) {
      this.mangas = [];
      this.displays = [];
    }
    this.loaded = true;
    this.lastRefreshAt = Date.now();
  }

  private applyFilterAndSort(): void {
    const list: Array<MangaDisplay> = [];
    for (const m of this.mangas) {
      list.push(makeMangaDisplay(m));
    }
    this.displays = sortMangaDisplays(list, this.sortMode);
  }

  private showHint(msg: string): void {
    this.hint = msg;
    setTimeout(() => {
      if (this.hint === msg) {
        this.hint = '';
      }
    }, 2600);
  }

  /** 底部弹层内容的下内边距：手机端让出悬浮 Tab 栏高度，避免按钮被遮挡。 */
  private sheetBottomPadding(): number {
    return this.sizeClass === WindowSizeClass.SM ? 92 : 20;
  }

  // ---------- 选择态 ----------

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    const idx = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
      if (this.selectedIds.length === 0) {
        this.selectMode = false;
      }
    } else {
      this.selectedIds.push(id);
    }
  }

  private enterSelectMode(id: number): void {
    this.selectMode = true;
    this.selectedIds = id >= 0 ? [id] : [];
    this.closeAllOverlays();
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  private toggleSelectAll(): void {
    if (this.selectedIds.length === this.displays.length) {
      this.selectedIds = [];
      return;
    }
    const ids: Array<number> = [];
    for (const d of this.displays) {
      ids.push(d.id);
    }
    this.selectedIds = ids;
  }

  private closeAllOverlays(): void {
    this.showTools = false;
    this.showSort = false;
    this.showMenu = false;
    this.showRename = false;
    this.showCover = false;
    this.showExportModes = false;
    this.showConfirmDelete = false;
  }

  // ---------- 删除 ----------

  private requestDelete(ids: Array<number>): void {
    if (ids.length === 0) {
      return;
    }
    this.deleteIds = ids.slice();
    if (ids.length === 1) {
      let name = '';
      for (const d of this.displays) {
        if (d.id === ids[0]) {
          name = d.name;
        }
      }
      this.confirmText = `确定删除「${name}」？页面、译文与沙箱文件将一并清理。`;
    } else {
      this.confirmText = `确定删除选中的 ${ids.length} 本漫画？页面、译文与沙箱文件将一并清理。`;
    }
    this.closeAllOverlays();
    this.showConfirmDelete = true;
  }

  private async confirmDelete(): Promise<void> {
    const ids = this.deleteIds;
    const count = ids.length;
    this.showConfirmDelete = false;
    const deleted = await ShelfViewModel.deleteMangas(ids);
    this.exitSelectMode();
    await this.refresh();
    this.showHint(deleted < count ? `已删除 ${deleted} 本，${count - deleted} 本删除失败` : `已删除 ${deleted} 本`);
  }

  // ---------- 排序/视图/分段 ----------

  private changeSort(mode: ShelfSortMode): void {
    this.sortMode = mode;
    ShelfViewModel.saveSortMode(mode);
    this.applyFilterAndSort();
    this.showSort = false;
  }

  private toggleViewMode(): void {
    this.viewMode = this.viewMode === 'grid' ? 'list' : 'grid';
    ShelfViewModel.saveViewMode(this.viewMode);
  }

  private switchSegment(seg: ShelfSegment): void {
    if (this.segment === seg) {
      return;
    }
    this.segment = seg;
    ShelfViewModel.saveSegment(seg);
    this.exitSelectMode();
    this.closeAllOverlays();
    if (seg === ShelfSegment.MANGA) {
      this.refresh();
    }
  }

  private gridColumns(): number {
    return shelfColumnsForWidth(this.areaWidth);
  }

  /**
   * 网格封面高度（vp）：按当前列宽 3:4 计算并夹在 [150, 260]；
   * 卡片总高 = 封面 + 6 + 文本区 56 ≈ 270-322vp，避免封面在 Grid 中失控撑满。
   */
  private gridCoverHeight(): number {
    const cols = this.gridColumns();
    if (cols <= 0) {
      return 210;
    }
    const gaps = (cols - 1) * 12;
    const available = this.areaWidth - ThemeTokens.PAGE_PADDING * 2 - gaps;
    if (available <= 0) {
      return 210;
    }
    let h = Math.round(available / cols * 4 / 3);
    if (h < 150) {
      h = 150;
    }
    if (h > 260) {
      h = 260;
    }
    return h;
  }

  // ---------- 长按菜单动作 ----------

  private openCardMenu(d: MangaDisplay): void {
    if (this.selectMode) {
      return;
    }
    this.menuId = d.id;
    this.menuName = d.name;
    this.showTools = false;
    this.showSort = false;
    this.showMenu = true;
  }

  private openRename(): void {
    this.renameId = this.menuId;
    this.renameValue = this.menuName;
    this.showMenu = false;
    this.showRename = true;
  }

  private async submitRename(): Promise<void> {
    const id = this.renameId;
    const value = this.renameValue;
    this.showRename = false;
    try {
      const m = await ShelfViewModel.renameManga(id, value);
      await this.refresh();
      this.showHint(`已重命名为「${m.name}」`);
    } catch (e) {
      this.showHint(`重命名失败：${e}`);
    }
  }

  private async openCoverPicker(): Promise<void> {
    const id = this.menuId;
    this.coverId = id;
    this.coverPages = [];
    this.coverCurrent = '';
    this.showMenu = false;
    this.showCover = true;
    this.coverLoading = true;
    try {
      const pages = await ShelfViewModel.loadPages(id);
      for (const d of this.displays) {
        if (d.id === id) {
          this.coverCurrent = d.coverPath;
        }
      }
      this.coverPages = pages;
    } catch (e) {
      this.showHint(`读取页面失败：${e}`);
      this.showCover = false;
    }
    this.coverLoading = false;
  }

  private async chooseCover(pageIndex: number): Promise<void> {
    const id = this.coverId;
    const pages = this.coverPages;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return;
    }
    const path = pages[pageIndex];
    this.coverCurrent = path;
    try {
      await ShelfViewModel.updateCover(id, pageIndex);
      this.showCover = false;
      await this.refresh();
      this.showHint(`封面已更换为第 ${pageIndex + 1} 页`);
    } catch (e) {
      this.showHint(`更换封面失败：${e}`);
    }
  }

  private openExport(id: number): void {
    this.exportMangaId = id;
    this.showMenu = false;
    this.showExportModes = true;
  }

  private runExport(mode: ExportMode): void {
    this.showExportModes = false;
    this.exporting = true;
    this.exportDone = 0;
    const id = this.exportMangaId;
    ShelfViewModel.exportManga(id, mode, (done: number, total: number) => {
      this.exportDone = done;
      this.exportTotal = total;
    }).then((r: ExportResult) => {
      this.exporting = false;
      this.showHint(r.untranslated > 0
        ? `导出完成（${r.exported} 页，${r.untranslated} 页未翻译以原图导出）`
        : `导出完成（${r.exported} 页）`);
    }).catch((e: Object) => {
      this.exporting = false;
      this.showHint(`导出失败：${e}`);
    });
  }

  private async batchTranslate(id: number): Promise<void> {
    this.showMenu = false;
    try {
      await ShelfViewModel.startBatch(id);
      this.showHint('已开始批量翻译，可在阅读器查看进度');
    } catch (e) {
      this.showHint(`启动批量翻译失败：${e}`);
    }
  }

  private async rescanManga(id: number): Promise<void> {
    try {
      const m = await ShelfViewModel.rescan(id);
      await this.refresh();
      this.showHint(`已重扫「${m.name}」：当前 ${m.pageCount} 页`);
    } catch (e) {
      this.showHint(`${e}。请删除该记录后重新导入目录以重新授权`);
    }
  }

  private async refreshDirectories(): Promise<void> {
    if (this.refreshingDirs) {
      return;
    }
    this.closeAllOverlays();
    this.refreshingDirs = true;
    try {
      const result: DirectoryRefreshResult = await ShelfViewModel.refreshDirectorySources();
      await this.refresh();
      if (result.refreshed === 0 && result.failed === 0) {
        this.showHint('没有目录来源的漫画可刷新');
      } else if (result.failed > 0) {
        this.showHint(`已刷新 ${result.refreshed} 本，${result.failed} 本失败：${result.detail}`);
      } else {
        this.showHint(`已刷新 ${result.refreshed} 本目录来源漫画`);
      }
    } catch (e) {
      this.showHint(`刷新目录源失败：${e}`);
    }
    this.refreshingDirs = false;
  }

  private async generateDemo(): Promise<void> {
    if (this.demoBusy) {
      return;
    }
    this.demoBusy = true;
    try {
      const result: DemoDataResult = await DemoDataService.generateSampleManga();
      await this.refresh();
      this.showHint(result.message);
    } catch (e) {
      this.showHint(`${e}`);
    }
    this.demoBusy = false;
  }

  /** 进入阅读器（从上次阅读页继续）。 */
  private openReader(d: MangaDisplay): void {
    if (d.lastReadPage > 0) {
      AppEnv.getInstance().navStack.pushPathByName(Routes.READER, makeReaderParams(d.id, d.lastReadPage));
    } else {
      AppEnv.getInstance().navStack.pushPathByName(Routes.READER, makeReaderParams(d.id));
    }
  }

  private onCardTap(d: MangaDisplay): void {
    if (this.selectMode) {
      this.toggleSelect(d.id);
    } else {
      this.openReader(d);
    }
  }

  private cardKey(d: MangaDisplay): string {
    // V1 普通成员不会随父组件刷新，key 覆盖所有影响卡片渲染的字段以触发重建。
    return `${d.id}:${d.coverPath}:${d.pageCount}:${d.statusLabel}:${d.progressLabel}:` +
      `${d.updatedAt}:${this.viewMode}:${this.selectMode ? 1 : 0}:${this.isSelected(d.id) ? 1 : 0}:` +
      `${this.gridCoverHeight()}`;
  }

  // ---------- UI builders ----------

  @Builder
  segmentPill(label: string, seg: ShelfSegment) {
    Text(label)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontWeight(this.segment === seg ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.segment === seg ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(this.segment === seg ? ThemeTokens.PRIMARY : Color.Transparent)
      .onClick(() => {
        this.switchSegment(seg);
      })
  }

  @Builder
  segmentControl() {
    Row() {
      this.segmentPill('漫画', ShelfSegment.MANGA)
      this.segmentPill('小说', ShelfSegment.NOVEL)
    }
    .padding(3)
    .borderRadius(ThemeTokens.RADIUS_PILL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
  }

  @Builder
  actionIcon(icon: Resource, active: boolean, onTap: () => void) {
    Stack() {
      Image(icon)
        .width(17)
        .height(17)
        .fillColor(active ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
    }
    .width(32)
    .height(30)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(active ? '#33A78BFA' : ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  sortButton() {
    Row({ space: 5 }) {
      Image(Artwork.ICON_SORT)
        .width(14)
        .height(14)
        .fillColor(ThemeTokens.TEXT_SECONDARY)
      Text(shelfSortModeLabel(this.sortMode).substring(0, 2))
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
    }
    .height(30)
    .padding({ left: 9, right: 9 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      this.showSort = true;
    })
  }

  @Builder
  iconButton(icon: Resource, onTap: () => void) {
    Stack() {
      Image(icon)
        .width(18)
        .height(18)
        .fillColor(ThemeTokens.TEXT_SECONDARY)
    }
    .width(32)
    .height(30)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  textPill(label: string, onTap: () => void) {
    Text(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(ThemeTokens.TEXT_SECONDARY)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  topBar() {
    Row({ space: 8 }) {
      Column({ space: 1 }) {
        Text('书架')
          .fontSize(ThemeTokens.FONT_DISPLAY)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(this.segment === ShelfSegment.MANGA
          ? (this.displays.length > 0 ? `${this.displays.length} 本漫画` : '漫画书架')
          : '小说书架')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.segment === ShelfSegment.MANGA) {
        Button() {
          Row({ space: 5 }) {
            Image(Artwork.ICON_ADD)
              .width(15)
              .height(15)
              .fillColor(ThemeTokens.TEXT_ON_PRIMARY)
            Text('导入')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          }
        }
        .height(34)
        .padding({ left: 14, right: 14 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor(ThemeTokens.PRIMARY)
        .onClick(() => {
          this.showImportSheet = true;
        })
      }
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, top: 10, bottom: 8 })
  }

  @Builder
  mangaActionRow() {
    Row({ space: 6 }) {
      this.segmentControl()
      Blank()
      this.actionIcon(this.viewMode === 'grid' ? Artwork.ICON_VIEW_LIST : Artwork.ICON_VIEW_GRID,
        false, () => {
          this.toggleViewMode();
        })
      this.sortButton()
      this.actionIcon(Artwork.ICON_MORE, false, () => {
        this.showTools = true;
      })
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, bottom: 8 })
  }

  @Builder
  novelActionRow() {
    Row({ space: 8 }) {
      this.segmentControl()
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, bottom: 8 })
  }

  @Builder
  selectActionRow() {
    Row({ space: 8 }) {
      Text(`已选 ${this.selectedIds.length} 项`)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .layoutWeight(1)
      this.textPill(this.selectedIds.length === this.displays.length && this.displays.length > 0 ? '取消全选' : '全选', () => {
        this.toggleSelectAll();
      })
      Text(`删除`)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.WHITE)
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor(this.selectedIds.length > 0 ? ThemeTokens.RED : ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.requestDelete(this.selectedIds.slice());
        })
      this.textPill('完成', () => {
        this.exitSelectMode();
      })
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, bottom: 8 })
  }

  @Builder
  cardItem(d: MangaDisplay) {
    MangaCoverCard({
      display: d,
      listMode: this.viewMode === 'list',
      gridCoverHeight: this.gridCoverHeight(),
      selectMode: this.selectMode,
      selected: this.isSelected(d.id),
      onTap: () => {
        this.onCardTap(d);
      },
      onLongPress: () => {
        this.openCardMenu(d);
      },
      onRescan: () => {
        this.rescanManga(d.id);
      }
    })
  }

  @Builder
  mangaContent() {
    if (this.viewMode === 'list' && shelfListColumns(this.sizeClass) === 1) {
      List({ space: 10 }) {
        ForEach(this.displays, (d: MangaDisplay) => {
          ListItem() {
            this.cardItem(d)
          }
        }, (d: MangaDisplay) => this.cardKey(d))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        bottom: this.sizeClass === WindowSizeClass.SM ? 84 : 12
      })
      .scrollBar(BarState.Off)
    } else {
      Grid() {
        ForEach(this.displays, (d: MangaDisplay) => {
          GridItem() {
            this.cardItem(d)
          }
        }, (d: MangaDisplay) => this.cardKey(d))
      }
      .columnsTemplate(this.viewMode === 'list'
        ? gridColumnsTemplate(shelfListColumns(this.sizeClass))
        : gridColumnsTemplate(this.gridColumns()))
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        bottom: this.sizeClass === WindowSizeClass.SM ? 84 : 12
      })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  emptyShelf() {
    Column() {
      Column() {
        EmptyState({
          icon: Artwork.EMPTY_SHELF,
          iconSize: 150,
          title: $r('app.string.empty_shelf_title'),
          hint: '支持 zip/cbz、图片目录与相册导入；也可先生成示例漫画体验完整流程'
        })
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: 10 }) {
        Button('导入漫画')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(40)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            this.showImportSheet = true;
          })
        Button() {
          Row({ space: 6 }) {
            if (this.demoBusy) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(ThemeTokens.PRIMARY_SOFT)
            } else {
              Image(Artwork.ICON_DEMO)
                .width(15)
                .height(15)
                .fillColor(ThemeTokens.PRIMARY_SOFT)
            }
            Text('生成示例漫画')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.PRIMARY_SOFT)
          }
        }
        .height(40)
        .padding({ left: 18, right: 18 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .borderWidth(1)
        .borderColor('#4DA78BFA')
        .onClick(() => {
          this.generateDemo();
        })
      }
      .margin({ top: 8, bottom: this.sizeClass === WindowSizeClass.SM ? 100 : 24 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  loadingState() {
    Column() {
      LoadingProgress()
        .width(30)
        .height(30)
        .color(ThemeTokens.PRIMARY)
      Text('正在读取书架…')
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
        .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  sheetRow(icon: Resource, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Image(icon)
        .width(18)
        .height(18)
        .fillColor(danger ? ThemeTokens.RED : ThemeTokens.PRIMARY_SOFT)
      Text(label)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(danger ? ThemeTokens.RED : ThemeTokens.TEXT_PRIMARY)
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  sheetHeader(title: string, subtitle: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(ThemeTokens.FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(2)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 6, right: 6, bottom: 6 })
  }

  @Builder
  bottomSheet(title: string, subtitle: string) {
    Column() {
      Blank()
      Column({ space: 2 }) {
        this.sheetHeader(title, subtitle)
        if (title === '书架设置') {
          this.sheetRow(this.viewMode === 'grid' ? Artwork.ICON_VIEW_LIST : Artwork.ICON_VIEW_GRID,
            this.viewMode === 'grid' ? '切换为列表视图' : '切换为网格视图', false, () => {
              this.toggleViewMode();
              this.showTools = false;
            })
          this.sheetRow(Artwork.ICON_REFRESH, '刷新目录源（增量扫描）', false, () => {
            this.refreshDirectories();
          })
          this.sheetRow(Artwork.ICON_CHECK, '多选删除', false, () => {
            this.enterSelectMode(-1);
          })
          this.sheetRow(Artwork.ICON_IMPORT_WIZARD, '导入向导（先确认再建档）', false, () => {
            this.showTools = false;
            AppEnv.getInstance().navStack.pushPathByName(Routes.IMPORT_WIZARD, makeImportWizardParams(0));
          })
          this.sheetRow(Artwork.ICON_IMPORT_ZIP, '打开导入面板', false, () => {
            this.showTools = false;
            this.showImportSheet = true;
          })
        }
        Button('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(36)
          .width('100%')
          .margin({ top: 6 })
          .onClick(() => {
            this.closeAllOverlays();
          })
      }
      .width('100%')
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        top: ThemeTokens.PAGE_PADDING,
        bottom: this.sheetBottomPadding()
      })
      .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  sortSheet() {
    Column() {
      Blank()
      Column({ space: 2 }) {
        this.sheetHeader('排序方式', '排序偏好会记住，下次进入书架继续使用')
        ForEach([ShelfSortMode.RECENT, ShelfSortMode.NAME, ShelfSortMode.IMPORT_TIME], (mode: ShelfSortMode) => {
          Row({ space: 12 }) {
            Text(shelfSortModeLabel(mode))
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(this.sortMode === mode ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
            if (this.sortMode === mode) {
              Image(Artwork.ICON_CHECK)
                .width(16)
                .height(16)
                .fillColor(ThemeTokens.PRIMARY)
            }
          }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .onClick(() => {
            this.changeSort(mode);
          })
        }, (mode: ShelfSortMode) => `sort-${mode}`)
        Button('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(36)
          .width('100%')
          .margin({ top: 6 })
          .onClick(() => {
            this.showSort = false;
          })
      }
      .width('100%')
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        top: ThemeTokens.PAGE_PADDING,
        bottom: this.sheetBottomPadding()
      })
      .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  cardMenuSheet() {
    Column() {
      Blank()
      Column({ space: 2 }) {
        this.sheetHeader(this.menuName, '长按菜单')
        this.sheetRow(Artwork.ICON_EDIT, '重命名', false, () => {
          this.openRename();
        })
        this.sheetRow(Artwork.ICON_COVER, '更换封面', false, () => {
          this.openCoverPicker();
        })
        this.sheetRow(Artwork.ICON_READER_EXPORT, '导出 ZIP', false, () => {
          this.openExport(this.menuId);
        })
        this.sheetRow(Artwork.ICON_READER_BATCH, '批量翻译', false, () => {
          this.batchTranslate(this.menuId);
        })
        this.sheetRow(Artwork.ICON_CHECK, '多选', false, () => {
          this.enterSelectMode(this.menuId);
        })
        this.sheetRow(Artwork.ICON_DELETE, '删除', true, () => {
          this.requestDelete([this.menuId]);
        })
        Button('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(36)
          .width('100%')
          .margin({ top: 6 })
          .onClick(() => {
            this.showMenu = false;
          })
      }
      .width('100%')
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        top: ThemeTokens.PAGE_PADDING,
        bottom: this.sheetBottomPadding()
      })
      .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  renameSheet() {
    Column() {
      Column({ space: 12 }) {
        Text('重命名')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        TextInput({ text: this.renameValue, placeholder: '输入漫画名称' })
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .placeholderColor(ThemeTokens.TEXT_HINT)
          .caretColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .height(44)
          .onChange((v: string) => {
            this.renameValue = v;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .onClick(() => {
              this.showRename = false;
            })
          Button('保存')
            .layoutWeight(1)
            .height(40)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .onClick(() => {
              this.submitRename();
            })
        }
        .width('100%')
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('86%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  coverSheet() {
    Column() {
      Column({ space: 10 }) {
        Text('更换封面')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width('100%')
        Text(this.coverLoading
          ? '正在读取页面…'
          : `共 ${this.coverPages.length} 页，点击选择封面（最多显示前 120 页）`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        if (this.coverLoading) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(ThemeTokens.PRIMARY)
        } else {
          Scroll() {
            Grid() {
              ForEach(this.coverPages.slice(0, 120), (path: string, index: number) => {
                GridItem() {
                  Stack({ alignContent: Alignment.BottomStart }) {
                    Image(toMediaUri(path))
                      .width('100%')
                      .height(84)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                    Text(`${index + 1}`)
                      .fontSize(9)
                      .fontColor(ThemeTokens.TEXT_PRIMARY)
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                      .borderRadius(ThemeTokens.RADIUS_PILL)
                      .backgroundColor('#CC0B0813')
                      .margin(4)
                    if (path === this.coverCurrent) {
                      Stack() {
                        Image(Artwork.ICON_CHECK)
                          .width(18)
                          .height(18)
                          .fillColor(ThemeTokens.BLACK)
                      }
                      .width(24)
                      .height(24)
                      .borderRadius(12)
                      .backgroundColor(ThemeTokens.PRIMARY)
                      .position({ x: '100%', y: 0 })
                      .markAnchor({ x: '100%', y: 0 })
                      .margin(4)
                    }
                  }
                  .borderWidth(path === this.coverCurrent ? 2 : 0)
                  .borderColor(ThemeTokens.PRIMARY)
                  .borderRadius(7)
                  .onClick(() => {
                    this.chooseCover(index);
                  })
                }
              }, (path: string) => path)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
          }
          .width('100%')
          .height(280)
          .scrollBar(BarState.Off)
        }
        Button('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(36)
          .width('100%')
          .onClick(() => {
            this.showCover = false;
          })
      }
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        top: ThemeTokens.PAGE_PADDING,
        bottom: this.sheetBottomPadding()
      })
      .width('100%')
      .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  exportModeRow(label: string, desc: string, mode: ExportMode) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(desc)
        .fontSize(ThemeTokens.FONT_SMALL)
        .fontColor(ThemeTokens.TEXT_HINT)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .onClick(() => {
      this.runExport(mode);
    })
  }

  @Builder
  exportSheet() {
    Column() {
      Blank()
      Column({ space: 10 }) {
        this.sheetHeader('导出 ZIP', '选择导出模式（命名沿用原页序）')
        this.exportModeRow('仅原文', '原始页图直接归集', ExportMode.ORIGINAL_ONLY)
        this.exportModeRow('仅译文', '原图 + 译文覆盖合成', ExportMode.TRANSLATED_ONLY)
        this.exportModeRow('双语对照', '原文页与译文页按页序交替', ExportMode.BILINGUAL)
        Button('取消')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .height(36)
          .width('100%')
          .onClick(() => {
            this.showExportModes = false;
          })
      }
      .width('100%')
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        top: ThemeTokens.PAGE_PADDING,
        bottom: this.sheetBottomPadding()
      })
      .borderRadius({ topLeft: ThemeTokens.RADIUS_CARD, topRight: ThemeTokens.RADIUS_CARD })
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  confirmDeleteSheet() {
    Column() {
      Column({ space: 12 }) {
        Text('删除漫画')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(this.confirmText)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .onClick(() => {
              this.showConfirmDelete = false;
            })
          Button('删除')
            .layoutWeight(1)
            .height(40)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.WHITE)
            .backgroundColor(ThemeTokens.RED)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .onClick(() => {
              this.confirmDelete();
            })
        }
        .width('100%')
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('86%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  importSheetBuilder() {
    Column() {
      Scroll() {
        ImportSheet({
          onImported: (mangas: Array<Manga>) => {
            this.refresh();
          },
          onWizard: () => {
            this.showImportSheet = false;
            setTimeout(() => {
              AppEnv.getInstance().navStack.pushPathByName(Routes.IMPORT_WIZARD, makeImportWizardParams(0));
            }, 220);
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.topBar()
        if (this.segment === ShelfSegment.NOVEL) {
          this.novelActionRow()
        } else if (this.selectMode) {
          this.selectActionRow()
        } else {
          this.mangaActionRow()
        }

        if (this.segment === ShelfSegment.NOVEL) {
          NovelShelfView()
          // NovelShelfView 自带列表/空态/工具栏
        } else if (!this.loaded) {
          this.loadingState()
        } else if (this.displays.length === 0) {
          this.emptyShelf()
        } else {
          this.mangaContent()
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w = Number(newValue.width);
        if (!isNaN(w) && w > 0 && Math.abs(w - this.areaWidth) >= 1) {
          this.areaWidth = w;
        }
      })
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
        // 从阅读器返回/切回书架时刷新阅读进度与封面；600ms 内不重复刷新。
        if (isVisible && currentRatio > 0.5 && this.loaded && Date.now() - this.lastRefreshAt > 600) {
          this.refresh();
        }
      })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.WHITE)
          .textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(ThemeTokens.RADIUS_CARD)
          .backgroundColor('#E60B0813')
          .margin({ bottom: 96 })
          .maxLines(3)
          .onClick(() => {
            this.hint = '';
          })
      }

      if (this.exporting) {
        Column({ space: 6 }) {
          Progress({ value: this.exportDone, total: this.exportTotal > 0 ? this.exportTotal : 1 })
            .color(ThemeTokens.PRIMARY)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .height(4)
            .width(180)
          Text(`正在导出 ${this.exportDone}/${this.exportTotal} …`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.WHITE)
        }
        .padding(12)
        .borderRadius(ThemeTokens.RADIUS_CARD)
        .backgroundColor('#E60B0813')
        .margin({ bottom: 96 })
      }

      if (this.showTools) {
        this.bottomSheet('书架设置', '视图 / 目录源刷新 / 多选 / 导入')
      }
      if (this.showSort) {
        this.sortSheet()
      }
      if (this.showMenu) {
        this.cardMenuSheet()
      }
      if (this.showRename) {
        this.renameSheet()
      }
      if (this.showCover) {
        this.coverSheet()
      }
      if (this.showExportModes) {
        this.exportSheet()
      }
      if (this.showConfirmDelete) {
        this.confirmDeleteSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
    .bindSheet($$this.showImportSheet, this.importSheetBuilder(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      backgroundColor: ThemeTokens.SURFACE
    })
  }
}
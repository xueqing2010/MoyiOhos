import { ThemeTokens, WindowSizeClass, observeBreakpoint, toMediaUri } from 'commons';
import { Artwork } from '../components/Artwork';
import { EmptyState } from '../components/EmptyState';
import { AppEnv } from '../common/AppEnv';
import {
  HistoryFullscreenParams,
  Routes,
  makeHistoryDetailParams
} from '../common/Routes';
import { HistoryGroup, HistoryItem, HistoryKind } from '../service/HistoryService';
import { HistoryViewModel } from '../viewmodel/HistoryViewModel';

/** 列表渲染行：组头，或一行 1~2 张记录卡片（宽屏双列）。 */
class HistoryRenderRow {
  isHeader: boolean = false;
  group: HistoryGroup = new HistoryGroup();
  items: Array<HistoryItem> = [];
}

/**
 * 历史 Tab（stage-2 task-6，对齐上游 history）：
 * · 顶部分段「时间 / 进程」双视图；
 * · 列表显示封面/标题/摘要/时间/状态徽标；点击进详情，组头可全屏浏览；
 * · 空态 SVG、下拉刷新、多选删除 / 清空（二次确认）。
 * 数据来自 HistoryViewModel（HistoryService 聚合三类译文记录）。
 */
@Component
export struct HistoryView {
  @State loading: boolean = true;
  @State items: Array<HistoryItem> = [];
  @State timeGroups: Array<HistoryGroup> = [];
  @State processGroups: Array<HistoryGroup> = [];
  @State rows: Array<HistoryRenderRow> = [];
  /** 0=时间视图 1=进程视图 */
  @State viewMode: number = 0;
  @State manageMode: boolean = false;
  @State selectedKeys: Array<string> = [];
  @State refreshing: boolean = false;
  @State toast: string = '';
  /** '' | 'delete' | 'clear' */
  @State dialog: string = '';
  @State busy: boolean = false;
  @State busyText: string = '';
  @State isWide: boolean = false;
  @State mangaCount: number = 0;
  @State novelCount: number = 0;
  @State textCount: number = 0;
  private stopBreakpoint: (() => void) | undefined = undefined;
  private wasVisible: boolean = false;
  private visibleInitialized: boolean = false;

  aboutToAppear(): void {
    this.stopBreakpoint = observeBreakpoint((sizeClass: WindowSizeClass) => {
      const wide = sizeClass === WindowSizeClass.LG;
      if (this.isWide !== wide) {
        this.isWide = wide;
        if (!this.loading) {
          this.refreshRows();
        }
      }
    });
    this.reload(true);
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  // -------------------------------------------------------------------------
  // 数据
  // -------------------------------------------------------------------------

  private async reload(showLoading: boolean): Promise<void> {
    if (showLoading) {
      this.loading = true;
    }
    try {
      const snapshot = await HistoryViewModel.load();
      this.items = snapshot.items;
      this.timeGroups = snapshot.timeGroups;
      this.processGroups = snapshot.processGroups;
      this.mangaCount = snapshot.mangaCount;
      this.novelCount = snapshot.novelCount;
      this.textCount = snapshot.textCount;
      this.dropMissingSelection();
      this.refreshRows();
    } catch (e) {
      this.showToast('历史加载失败：' + HistoryView.readableError(e));
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private refreshRows(): void {
    this.rows = this.buildRows(this.currentGroups());
  }

  private currentGroups(): Array<HistoryGroup> {
    return this.viewMode === 0 ? this.timeGroups : this.processGroups;
  }

  /** 合并行：一本书一行，卡片显示累计页/章与最近时间。 */
  private summaryItem(group: HistoryGroup): HistoryItem {
    const item = new HistoryItem();
    item.isSummary = true;
    item.key = group.key + ':summary';
    item.groupKey = group.key;
    item.kind = group.kind;
    item.title = group.title;
    item.subtitle = group.subtitle;
    item.coverPath = group.coverPath;
    item.time = group.latestTime;
    item.pageCount = group.pageCount;
    item.translatedCount = group.translatedCount;
    if (group.items.length > 0) {
      const latest = group.items[0];
      item.refId = latest.refId;
      item.status = latest.status;
      item.engineType = latest.engineType;
      item.preview = latest.preview;
    }
    return item;
  }

  private findGroup(key: string): HistoryGroup | undefined {
    for (const group of this.currentGroups()) {
      if (group.key === key) {
        return group;
      }
    }
    return undefined;
  }

  private buildRows(groups: Array<HistoryGroup>): Array<HistoryRenderRow> {
    const rows: Array<HistoryRenderRow> = [];
    const perRow = this.isWide ? 2 : 1;
    for (const group of groups) {
      if (!this.manageMode) {
        const summary = new HistoryRenderRow();
        summary.isHeader = false;
        summary.group = group;
        summary.items = [this.summaryItem(group)];
        rows.push(summary);
        continue;
      }
      const header = new HistoryRenderRow();
      header.isHeader = true;
      header.group = group;
      rows.push(header);
      let cursor = 0;
      while (cursor < group.items.length) {
        const row = new HistoryRenderRow();
        row.isHeader = false;
        row.group = group;
        const chunk: Array<HistoryItem> = [];
        for (let i = 0; i < perRow && cursor < group.items.length; i++) {
          chunk.push(group.items[cursor]);
          cursor++;
        }
        row.items = chunk;
        rows.push(row);
      }
    }
    return rows;
  }

  private dropMissingSelection(): void {
    if (this.selectedKeys.length === 0) {
      return;
    }
    const kept: Array<string> = [];
    for (const key of this.selectedKeys) {
      if (this.findItem(key) !== undefined) {
        kept.push(key);
      }
    }
    this.selectedKeys = kept;
  }

  private findItem(key: string): HistoryItem | undefined {
    for (const item of this.items) {
      if (item.key === key) {
        return item;
      }
    }
    return undefined;
  }

  // -------------------------------------------------------------------------
  // 交互
  // -------------------------------------------------------------------------

  private switchView(mode: number): void {
    if (this.viewMode === mode) {
      return;
    }
    this.viewMode = mode;
    this.refreshRows();
  }

  private enterManage(item?: HistoryItem): void {
    this.manageMode = true;
    if (item !== undefined) {
      const group = this.findGroup(item.groupKey);
      if (item.isSummary && group !== undefined) {
        const keys: Array<string> = [];
        for (const it of group.items) {
          keys.push(it.key);
        }
        this.selectedKeys = keys;
      } else {
        this.selectedKeys = [item.key];
      }
    }
    this.refreshRows();
  }

  private exitManage(): void {
    this.manageMode = false;
    this.selectedKeys = [];
    this.refreshRows();
  }

  private isSelected(key: string): boolean {
    return this.selectedKeys.indexOf(key) >= 0;
  }

  private toggleSelect(item: HistoryItem): void {
    if (this.isSelected(item.key)) {
      const next: Array<string> = [];
      for (const key of this.selectedKeys) {
        if (key !== item.key) {
          next.push(key);
        }
      }
      this.selectedKeys = next;
    } else {
      this.selectedKeys = this.selectedKeys.concat([item.key]);
    }
  }

  private onItemTap(item: HistoryItem): void {
    if (this.manageMode) {
      this.toggleSelect(item);
      return;
    }
    if (item.isSummary) {
      const group = this.findGroup(item.groupKey);
      if (group !== undefined) {
        this.openFullscreen(group);
      }
      return;
    }
    AppEnv.getInstance().navStack.pushPathByName(Routes.HISTORY_DETAIL,
      makeHistoryDetailParams(item.kind, item.refId));
  }

  private openFullscreen(group: HistoryGroup): void {
    if (group.kind < 0 || group.items.length === 0) {
      return;
    }
    const params: HistoryFullscreenParams = { sessionId: group.key };
    AppEnv.getInstance().navStack.pushPathByName(Routes.HISTORY_FULLSCREEN, params);
  }

  private selectedItems(): Array<HistoryItem> {
    const picked: Array<HistoryItem> = [];
    for (const key of this.selectedKeys) {
      const item = this.findItem(key);
      if (item !== undefined) {
        picked.push(item);
      }
    }
    return picked;
  }

  private visibleItems(): Array<HistoryItem> {
    const visible: Array<HistoryItem> = [];
    for (const group of this.currentGroups()) {
      for (const item of group.items) {
        visible.push(item);
      }
    }
    return visible;
  }

  private allVisibleSelected(): boolean {
    const visible = this.visibleItems();
    if (visible.length === 0) {
      return false;
    }
    return this.selectedKeys.length >= visible.length;
  }

  private toggleSelectAll(): void {
    if (this.allVisibleSelected()) {
      this.selectedKeys = [];
      return;
    }
    const keys: Array<string> = [];
    for (const item of this.visibleItems()) {
      keys.push(item.key);
    }
    this.selectedKeys = keys;
  }

  private groupAllSelected(group: HistoryGroup): boolean {
    if (group.items.length === 0) {
      return false;
    }
    for (const item of group.items) {
      if (!this.isSelected(item.key)) {
        return false;
      }
    }
    return true;
  }

  private toggleGroup(group: HistoryGroup): void {
    if (this.groupAllSelected(group)) {
      const next: Array<string> = [];
      for (const key of this.selectedKeys) {
        let inGroup = false;
        for (const item of group.items) {
          if (item.key === key) {
            inGroup = true;
            break;
          }
        }
        if (!inGroup) {
          next.push(key);
        }
      }
      this.selectedKeys = next;
    } else {
      let next = this.selectedKeys.slice();
      for (const item of group.items) {
        if (next.indexOf(item.key) < 0) {
          next.push(item.key);
        }
      }
      this.selectedKeys = next;
    }
  }

  private async doDelete(): Promise<void> {
    const picked = this.selectedItems();
    if (picked.length === 0) {
      return;
    }
    this.busy = true;
    this.busyText = '正在删除…';
    try {
      const removed = await HistoryViewModel.deleteItems(picked);
      this.exitManage();
      await this.reload(false);
      this.showToast('已删除 ' + removed + ' 条译文记录');
    } catch (e) {
      this.showToast('删除失败：' + HistoryView.readableError(e));
    } finally {
      this.busy = false;
    }
  }

  private async doClear(): Promise<void> {
    this.busy = true;
    this.busyText = '正在清空…';
    try {
      await HistoryViewModel.clearAll();
      this.exitManage();
      await this.reload(false);
      this.showToast('已清空全部翻译历史');
    } catch (e) {
      this.showToast('清空失败：' + HistoryView.readableError(e));
    } finally {
      this.busy = false;
    }
  }

  /** 按时间清理：只删 N 天前的译文记录（spec §D）。 */
  private async doClearBeforeDays(days: number): Promise<void> {
    this.busy = true;
    this.busyText = '正在清理…';
    try {
      await HistoryViewModel.clearBeforeDays(days);
      this.exitManage();
      await this.reload(false);
      this.showToast('已清理 ' + days + ' 天前的译文记录');
    } catch (e) {
      this.showToast('清理失败：' + HistoryView.readableError(e));
    } finally {
      this.busy = false;
    }
  }

  private showToast(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2600);
  }

  private dialogMessage(): string {
    if (this.dialog === 'clear') {
      return '将清空全部漫画页译文、小说章节译文与文本翻译记录；原图、书籍与章节原文不受影响。';
    }
    return '将删除选中的 ' + this.selectedKeys.length + ' 条译文记录，原图与书籍不受影响。';
  }

  // -------------------------------------------------------------------------
  // 视觉工具
  // -------------------------------------------------------------------------

  private kindShort(kind: number): string {
    if (kind === HistoryKind.MANGA_PAGE) {
      return '漫画';
    }
    if (kind === HistoryKind.NOVEL_CHAPTER) {
      return '小说';
    }
    return '文本';
  }

  private kindIcon(kind: number): Resource {
    if (kind === HistoryKind.MANGA_PAGE) {
      return Artwork.ICON_IMPORT_PHOTO;
    }
    if (kind === HistoryKind.NOVEL_CHAPTER) {
      return Artwork.ICON_IMPORT_NOVEL;
    }
    return Artwork.TAB_TRANSLATE;
  }

  private statusBg(status: number): string {
    const color = HistoryViewModel.statusColor(status);
    return '#33' + color.substring(1);
  }

  private rowKey(row: HistoryRenderRow): string {
    if (row.isHeader) {
      const selected = this.manageMode ? (this.groupAllSelected(row.group) ? '1' : '0') : 'n';
      return 'h:' + row.group.key + ':' + (this.manageMode ? 'm' : 'n') + ':' + selected;
    }
    let key = 'r:' + (this.manageMode ? 'm' : 'n');
    for (const item of row.items) {
      key += '|' + item.key + ':' + (this.isSelected(item.key) ? '1' : '0');
    }
    return key;
  }

  private static readableError(e: Object): string {
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return '未知错误';
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @Builder
  headerIcon(icon: Resource, action: () => void) {
    Image(icon)
      .width(34)
      .height(34)
      .padding(8)
      .fillColor(ThemeTokens.TEXT_SECONDARY)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .margin({ left: 8 })
      .onClick(action)
  }

  @Builder
  header() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('历史')
            .fontSize(ThemeTokens.FONT_DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
          Text(this.items.length === 0 ? '漫画 · 小说 · 文本 翻译记录'
            : this.processGroups.length + ' 本 · 漫画 ' + this.mangaCount + ' / 小说 ' + this.novelCount +
              ' / 文本 ' + this.textCount)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.manageMode) {
          Text('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .onClick(() => {
              this.exitManage();
            })
        } else {
          this.headerIcon(Artwork.ICON_REFRESH, () => {
            this.reload(true);
          })
          this.headerIcon(Artwork.ICON_VIEW_GRID, () => {
            this.enterManage();
          })
          this.headerIcon(Artwork.ICON_DELETE, () => {
            if (this.items.length > 0) {
              this.dialog = 'clear';
            }
          })
        }
      }
      .width('100%')

      Row() {
        this.segment('最近', 0)
        this.segment('按书', 1)
      }
      .width('100%')
      .padding(4)
      .backgroundColor(ThemeTokens.CARD_BG)
      .borderRadius(ThemeTokens.RADIUS_PILL)

      if (this.manageMode) {
        Row({ space: 12 }) {
          Text('已选 ' + this.selectedKeys.length + ' 项')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(this.allVisibleSelected() ? '取消全选' : '全选')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.PRIMARY)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.toggleSelectAll();
            })
          Text('删除')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(this.selectedKeys.length > 0 ? ThemeTokens.RED : ThemeTokens.TEXT_TERTIARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .onClick(() => {
              if (this.selectedKeys.length > 0) {
                this.dialog = 'delete';
              }
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: ThemeTokens.PAGE_PADDING, right: ThemeTokens.PAGE_PADDING, top: 12, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  segment(label: string, mode: number) {
    Text(label)
      .fontSize(ThemeTokens.FONT_CAPTION)
      .fontWeight(this.viewMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.viewMode === mode ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .lineHeight(32)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor(this.viewMode === mode ? ThemeTokens.PRIMARY : Color.Transparent)
      .onClick(() => {
        this.switchView(mode);
      })
  }

  @Builder
  emptyState() {
    EmptyState({
      icon: Artwork.EMPTY_HISTORY,
      title: '暂无翻译记录',
      hint: '完成一次漫画 / 小说 / 文本翻译后，记录会出现在这里\n下拉刷新或点右上角刷新'
    })
  }

  @Builder
  groupHeader(group: HistoryGroup) {
    Row({ space: 8 }) {
      if (this.manageMode) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.groupAllSelected(group)) {
            Image(Artwork.ICON_CHECK)
              .width(11)
              .height(11)
              .fillColor(ThemeTokens.TEXT_ON_PRIMARY)
          }
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(this.groupAllSelected(group) ? ThemeTokens.PRIMARY : Color.Transparent)
        .border({
          width: this.groupAllSelected(group) ? 0 : 1,
          color: ThemeTokens.TEXT_HINT
        })
        .onClick(() => {
          this.toggleGroup(group);
        })
      }
      if (group.kind === HistoryKind.MANGA_PAGE || group.kind === HistoryKind.NOVEL_CHAPTER) {
        if (group.coverPath.length > 0) {
          Image(toMediaUri(group.coverPath))
            .width(28)
            .height(38)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        } else {
          Image(Artwork.pickCover(group.items.length > 0 ? group.items[0].refId : 0))
            .width(28)
            .height(38)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        }
      }
      Column({ space: 2 }) {
        Text(group.title)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(group.subtitle)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.manageMode && group.kind >= 0) {
        Row({ space: 4 }) {
          Image(Artwork.ICON_IMAGE)
            .width(13)
            .height(13)
            .fillColor(ThemeTokens.PRIMARY)
          Text('全屏')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.PRIMARY)
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .onClick(() => {
          this.openFullscreen(group);
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  cover(item: HistoryItem) {
    Stack() {
      if (item.coverPath.length > 0) {
        Image(toMediaUri(item.coverPath))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
      } else if (item.kind !== HistoryKind.TEXT) {
        // 无封面时用彩色封面占位（art-dev 资产），比单色图标更接近书架观感。
        Image(Artwork.pickCover(item.refId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
      } else {
        Column() {
          Image(this.kindIcon(item.kind))
            .width(22)
            .height(22)
            .fillColor(ThemeTokens.PRIMARY)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
      }
    }
    .width(44)
    .height(62)
    .clip(true)
  }

  @Builder
  itemCard(item: HistoryItem) {
    Row({ space: 10 }) {
      this.cover(item)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(item.title)
            .fontSize(ThemeTokens.FONT_BODY - 1)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.kind !== HistoryKind.TEXT) {
            Text(this.kindShort(item.kind))
              .fontSize(9)
              .fontColor(ThemeTokens.ACCENT)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
          }
        }
        .width('100%')

        Text(item.subtitle.length > 0 ? item.subtitle : HistoryViewModel.kindName(item.kind))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 6 }) {
          Text(HistoryViewModel.formatTime(item.time))
            .fontSize(ThemeTokens.FONT_SMALL - 1)
            .fontColor(ThemeTokens.TEXT_HINT)
          Blank()
          Text(HistoryViewModel.statusText(item.status))
            .fontSize(9)
            .fontColor(HistoryViewModel.statusColor(item.status))
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(this.statusBg(item.status))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.manageMode) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.isSelected(item.key)) {
            Image(Artwork.ICON_CHECK)
              .width(12)
              .height(12)
              .fillColor(ThemeTokens.TEXT_ON_PRIMARY)
          }
        }
        .width(20)
        .height(20)
        .borderRadius(10)
        .backgroundColor(this.isSelected(item.key) ? ThemeTokens.PRIMARY : Color.Transparent)
        .border({
          width: this.isSelected(item.key) ? 0 : 1,
          color: ThemeTokens.TEXT_HINT
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor(this.isSelected(item.key) ? ThemeTokens.SURFACE_SECONDARY : ThemeTokens.CARD_BG)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({
      width: 1,
      color: this.isSelected(item.key) ? ThemeTokens.PRIMARY : ThemeTokens.DIVIDER
    })
    .onClick(() => {
      this.onItemTap(item);
    })
    .gesture(LongPressGesture().onAction(() => {
      if (!this.manageMode) {
        this.enterManage(item);
      }
    }))
  }

  @Builder
  emptyArea() {
    Refresh({ refreshing: $$this.refreshing }) {
      Column() {
        this.emptyState()
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => {
      this.reload(false);
    })
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  renderRow(row: HistoryRenderRow) {
    if (row.isHeader) {
      Column() {
        this.groupHeader(row.group)
      }
      .width('100%')
      .height(42)
    } else if (row.items.length > 1) {
      Row({ space: 10 }) {
        ForEach(row.items, (item: HistoryItem) => {
          Column() {
            this.itemCard(item)
          }
          .layoutWeight(1)
          .height(92)
        }, (item: HistoryItem) => 'w:' + item.key + ':' + (this.isSelected(item.key) ? '1' : '0'))
      }
      .width('100%')
      .height(92)
    } else if (row.items.length === 1) {
      Row({ space: 10 }) {
        Column() {
          this.itemCard(row.items[0])
        }
        .layoutWeight(1)
        .height(92)
        if (this.isWide) {
          Blank()
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height(92)
    }
  }

  @Builder
  listArea() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 10 }) {
        ForEach(this.rows, (row: HistoryRenderRow) => {
          ListItem() {
            this.renderRow(row)
          }
          .width('100%')
        }, (row: HistoryRenderRow) => this.rowKey(row))
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .padding({
        left: ThemeTokens.PAGE_PADDING,
        right: ThemeTokens.PAGE_PADDING,
        bottom: 90
      })
    }
    .onRefreshing(() => {
      this.reload(false);
    })
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  dialogCard() {
    Column() {
      Column({ space: 14 }) {
        Text(this.dialog === 'clear' ? '清空历史记录' : '删除选中记录')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(this.dialogMessage())
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .textAlign(TextAlign.Start)
        if (this.dialog === 'clear') {
          Text('仅清理 14 天前的记录')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.PRIMARY)
            .onClick(() => {
              this.dialog = '';
              this.doClearBeforeDays(14);
            })
        }
        Row({ space: 12 }) {
          Text('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .lineHeight(38)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
            .onClick(() => {
              this.dialog = '';
            })
          Text(this.dialog === 'clear' ? '清空' : '删除')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.WHITE)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .lineHeight(38)
            .borderRadius(ThemeTokens.RADIUS_SMALL)
            .backgroundColor(ThemeTokens.RED)
            .onClick(() => {
              const action = this.dialog;
              this.dialog = '';
              if (action === 'clear') {
                this.doClear();
              } else {
                this.doDelete();
              }
            })
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxWidth: 440 })
      .padding(18)
      .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      .borderRadius(ThemeTokens.RADIUS_CARD + 4)
      .border({ width: 1, color: ThemeTokens.DIVIDER })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(ThemeTokens.PAGE_PADDING)
    .backgroundColor(ThemeTokens.SCRIM)
    .onClick(() => {
      this.dialog = '';
    })
  }

  @Builder
  toastView() {
    Text(this.toast)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(ThemeTokens.WHITE)
      .textAlign(TextAlign.Center)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor('#D91A142C')
      .constraintSize({ maxWidth: '80%' })
      .align(Alignment.Bottom)
      .margin({ bottom: 110 })
      .onClick(() => {
        this.toast = '';
      })
  }

  @Builder
  busyView() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(ThemeTokens.PRIMARY)
      Text(this.busyText)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
    }
    .padding(20)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.header()
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeTokens.PRIMARY)
            Text('正在加载历史…')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.items.length === 0) {
          this.emptyArea()
        } else {
          this.listArea()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeTokens.SURFACE)
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number) => {
        if (isVisible && ratio > 0) {
          if (!this.visibleInitialized) {
            this.visibleInitialized = true;
            this.wasVisible = true;
            return;
          }
          if (!this.wasVisible) {
            this.wasVisible = true;
            this.reload(false);
          }
        } else {
          this.wasVisible = false;
        }
      })

      if (this.toast.length > 0) {
        this.toastView()
      }
      if (this.dialog.length > 0) {
        this.dialogCard()
      }
      if (this.busy) {
        this.busyView()
      }
    }
    .width('100%')
    .height('100%')
  }
}

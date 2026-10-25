import {
  HistoryDetailData,
  HistoryGroup,
  HistoryItem,
  HistoryKind,
  HistoryService,
  HistorySnapshot
} from '../service/HistoryService';

/**
 * 历史模块 ViewModel（task-6）：视图层唯一入口。
 * 负责把 HistoryService 的业务结果交给 HistoryView / HistoryDetailPage /
 * HistoryFullscreenPage，并统一提供列表所需的文案/时间格式化，避免 UI 里散落逻辑。
 */
export class HistoryViewModel {
  /** 加载历史快照（时间视图 + 进程视图分组）。 */
  static async load(): Promise<HistorySnapshot> {
    return HistoryService.load();
  }

  /** 按进程组键加载一组记录（全屏翻页）。 */
  static async loadGroup(groupKey: string): Promise<HistoryGroup | undefined> {
    return HistoryService.loadGroup(groupKey);
  }

  /** 读取单条记录详情。 */
  static async loadDetail(kind: number, refId: number): Promise<HistoryDetailData> {
    return HistoryService.loadDetail(kind, refId);
  }

  /** 批量删除记录（仅删译文）。 */
  static async deleteItems(items: Array<HistoryItem>): Promise<number> {
    return HistoryService.deleteItems(items);
  }

  /** 清空三类历史。 */
  static async clearAll(): Promise<void> {
    return HistoryService.clearAll();
  }

  /** 按时间清理（只删 days 天前的译文记录）。 */
  static async clearBeforeDays(days: number): Promise<void> {
    return HistoryService.clearBeforeDays(days);
  }

  static kindName(kind: number): string {
    return HistoryService.kindName(kind);
  }

  static statusText(status: number): string {
    return HistoryService.statusText(status);
  }

  static statusColor(status: number): string {
    return HistoryService.statusColor(status);
  }

  static engineName(engineType: number): string {
    return HistoryService.engineName(engineType);
  }

  static formatTime(timestamp: number): string {
    return HistoryService.formatTime(timestamp);
  }

  static formatDateTime(timestamp: number): string {
    return HistoryService.formatDateTime(timestamp);
  }

  static truncate(raw: string, max: number): string {
    return HistoryService.truncate(raw, max);
  }

  static isManga(kind: number): boolean {
    return kind === HistoryKind.MANGA_PAGE;
  }

  static isNovel(kind: number): boolean {
    return kind === HistoryKind.NOVEL_CHAPTER;
  }

  static isText(kind: number): boolean {
    return kind === HistoryKind.TEXT;
  }
}

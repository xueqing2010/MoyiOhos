import { picker } from '@kit.CoreFileKit';
import { uiMaterial } from '@kit.ArkUI';
import { DownloadStatus } from 'coremodel';
import { ThemeTokens, Log } from 'commons';
import { ModelItem, ModelManagerViewModel, StorageStats } from '../viewmodel/ModelManagerViewModel';
import { DownloadProgress, DownloadService } from '../service/DownloadService';

/**
 * 模型管理页（S111 / US-9）：预置模型分组（Hy-MT2 Q4_K_M 可下载，
 * 1.25bit 标注「暂不支持」）、自定义 URL、GGUF 导入、进度/速度、
 * 暂停/继续/删除与存储占用统计。沿用 DownloadService / DownloadRepository。
 */
@Component
export struct ModelManagerPage {
  @State items: Array<ModelItem> = [];
  @State stats: StorageStats = new StorageStats();
  @State loaded: boolean = false;
  @State hint: string = '';
  @State showCustom: boolean = false;
  @State customUrl: string = '';
  @State customName: string = '';
  @State deleteKey: string = '';
  @State deleteName: string = '';
  @State deleteImported: boolean = false;
  @State deleteHasFile: boolean = true;
  @State deleteDownloading: boolean = false;
  @State busy: boolean = false;
  /** 每个模型的持久错误文案（卡片上展示，不随 flash 消失）。 */
  @State errors: Map<string, string> = new Map();
  /** 运行时最近一次进度时间，用于 20s 无进度看门狗。 */
  private lastProgressAt: Map<string, number> = new Map();
  private progressHandler: (p: DownloadProgress) => void = (p: DownloadProgress) => {
    this.lastProgressAt.set(p.modelKey, Date.now());
    const currentError = this.errorOf(p.modelKey);
    if (p.error.length > 0) {
      this.setError(p.modelKey, ModelManagerPage.readableMessage(p.error));
    } else if (p.status === DownloadStatus.DOWNLOADED) {
      this.setError(p.modelKey, '');
    } else if (p.status === DownloadStatus.DOWNLOADING && p.downloadedBytes > 0
      && currentError.indexOf('下载 20 秒无进度') >= 0) {
      // 看门狗报无进度后又收到真实进度：清掉过期提示。
      this.setError(p.modelKey, '');
    }
    if (ModelManagerViewModel.patchLive(this.items, p)) {
      this.items = this.items.slice();
      if (p.status === DownloadStatus.DOWNLOADED || p.status === DownloadStatus.MD5_FAILED) {
        this.refreshStats();
      }
    }
  };

  aboutToAppear(): void {
    this.init();
  }

  aboutToDisappear(): void {
    DownloadService.getInstance().offProgress(this.progressHandler);
  }

  private async init(): Promise<void> {
    DownloadService.getInstance().onProgress(this.progressHandler);
    await this.refreshAll();
  }

  private async refreshAll(): Promise<void> {
    await this.refresh();
    await this.refreshStats();
    this.ensureWatchdogs();
    this.loaded = true;
  }

  /** 进入页面/刷新时，为遗留的「下载中/校验中」任务启动无进度看门狗。 */
  private ensureWatchdogs(): void {
    for (const it of this.items) {
      if (it.status === DownloadStatus.DOWNLOADING || it.status === DownloadStatus.VERIFYING) {
        if (!this.lastProgressAt.has(it.modelKey)) {
          this.lastProgressAt.set(it.modelKey, Date.now());
        }
        this.scheduleWatchdog(it.modelKey);
      }
    }
  }

  private async refresh(): Promise<void> {
    try {
      this.items = await ModelManagerViewModel.loadItems();
    } catch (e) {
      this.hint = `加载模型列表失败：${e}`;
    }
  }

  private async refreshStats(): Promise<void> {
    try {
      this.stats = await ModelManagerViewModel.loadStorageStats();
    } catch (e) {
      Log.warn('ModelManager', `load stats failed: ${e}`);
    }
  }

  /** 预置模型分组：Hy-MT2 Q4_K_M + 1.25bit（后者行内标注「暂不支持」）。 */
  private presetItems(): Array<ModelItem> {
    return this.items.filter((it: ModelItem) => it.isPreset);
  }

  private customItems(): Array<ModelItem> {
    return this.items.filter((it: ModelItem) => !it.isPreset);
  }

  private freeLabel(): string {
    if (this.stats.freeBytes <= 0) {
      return '未知';
    }
    return ModelManagerPage.formatSize(this.stats.freeBytes);
  }

  private downloadedTotal(): number {
    let count = 0;
    for (const it of this.items) {
      if (it.status === DownloadStatus.DOWNLOADED) {
        count += 1;
      }
    }
    return count;
  }

  private statusLabel(status: DownloadStatus): string {
    if (status === DownloadStatus.DOWNLOADING) {
      return '下载中';
    }
    if (status === DownloadStatus.PAUSED) {
      return '已暂停';
    }
    if (status === DownloadStatus.DOWNLOADED) {
      return '已下载';
    }
    if (status === DownloadStatus.VERIFYING) {
      return '校验中';
    }
    if (status === DownloadStatus.MD5_FAILED) {
      return '校验失败';
    }
    if (status === DownloadStatus.UNSUPPORTED) {
      return '暂不支持';
    }
    return '未下载';
  }

  private statusColor(status: DownloadStatus): string {
    if (status === DownloadStatus.DOWNLOADED) {
      return ThemeTokens.SUCCESS;
    }
    if (status === DownloadStatus.MD5_FAILED) {
      return ThemeTokens.RED;
    }
    if (status === DownloadStatus.UNSUPPORTED) {
      return ThemeTokens.WARN;
    }
    if (status === DownloadStatus.DOWNLOADING || status === DownloadStatus.VERIFYING) {
      return ThemeTokens.PRIMARY;
    }
    return ThemeTokens.TEXT_HINT;
  }

  private flash(text: string): void {
    this.hint = text;
    setTimeout(() => {
      if (this.hint === text) {
        this.hint = '';
      }
    }, 2400);
  }

  private async onDownload(item: ModelItem): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.setError(item.modelKey, '');
    this.lastProgressAt.set(item.modelKey, Date.now());
    this.scheduleWatchdog(item.modelKey);
    try {
      this.flash(`开始下载「${item.displayName}」…`);
      await ModelManagerViewModel.startDownload(item);
      if (item.status === DownloadStatus.DOWNLOADED) {
        this.setError(item.modelKey, '');
        this.flash(`「${item.displayName}」下载完成`);
      } else if (item.status === DownloadStatus.PAUSED) {
        this.flash(`「${item.displayName}」已暂停，可点继续恢复`);
      } else {
        this.flash(`「${item.displayName}」未完成下载`);
      }
      await this.refreshAll();
    } catch (e) {
      const msg = ModelManagerPage.readableError(e);
      this.setError(item.modelKey, msg);
      this.flash(msg);
      await this.refreshAll();
    }
    this.busy = false;
  }

  private async onResume(item: ModelItem): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.setError(item.modelKey, '');
    this.lastProgressAt.set(item.modelKey, Date.now());
    this.scheduleWatchdog(item.modelKey);
    try {
      this.flash(`继续下载「${item.displayName}」…`);
      await ModelManagerViewModel.resume(item);
      if (item.status === DownloadStatus.DOWNLOADED) {
        this.setError(item.modelKey, '');
        this.flash(`「${item.displayName}」下载完成`);
      } else {
        this.flash(`「${item.displayName}」已暂停或未完成`);
      }
      await this.refreshAll();
    } catch (e) {
      const msg = ModelManagerPage.readableError(e);
      this.setError(item.modelKey, msg);
      this.flash(msg);
      await this.refreshAll();
    }
    this.busy = false;
  }

  /** 暂停下载：立即把卡片置为已暂停并刷新（不依赖服务端是否还有运行时状态）。 */
  private async onPause(item: ModelItem): Promise<void> {
    try {
      ModelManagerViewModel.pause(item.modelKey);
      this.setError(item.modelKey, '');
      const next = this.items.slice();
      for (const it of next) {
        if (it.modelKey === item.modelKey) {
          it.status = DownloadStatus.PAUSED;
          it.speedLabel = '';
        }
      }
      this.items = next;
      this.flash(`已暂停「${item.displayName}」`);
      setTimeout(() => {
        this.refreshAll();
      }, 300);
    } catch (e) {
      this.flash(ModelManagerPage.readableError(e));
    }
  }

  /** 设置/清除某模型的持久错误文案（卡片上展示）。 */
  private setError(key: string, msg: string): void {
    const next = new Map<string, string>();
    this.errors.forEach((value: string, k: string) => {
      next.set(k, value);
    });
    if (msg.length > 0) {
      next.set(key, msg);
    } else {
      next.delete(key);
    }
    this.errors = next;
  }

  private errorOf(key: string): string {
    const v = this.errors.get(key);
    return v === undefined ? '' : v;
  }

  private findItem(key: string): ModelItem | undefined {
    for (const it of this.items) {
      if (it.modelKey === key) {
        return it;
      }
    }
    return undefined;
  }

  /** 下载 20 秒无进度（DNS/网络不可达）时在卡片上给出可读错误。 */
  private scheduleWatchdog(key: string): void {
    setTimeout(() => {
      const last = this.lastProgressAt.get(key);
      if (last === undefined) {
        return;
      }
      const item = this.findItem(key);
      if (item === undefined) {
        return;
      }
      if (item.status === DownloadStatus.DOWNLOADED || item.status === DownloadStatus.PAUSED
        || item.status === DownloadStatus.MD5_FAILED || item.status === DownloadStatus.NOT_DOWNLOADED
        || item.status === DownloadStatus.UNSUPPORTED) {
        return;
      }
      if (Date.now() - last >= 15000) {
        this.setError(key, '下载 20 秒无进度：可能是 DNS/网络不可达或 URL 无效，请检查后重试');
      }
    }, 20000);
  }

  /** 错误对象 → 可读中文。 */
  private static readableError(e: Object): string {
    let msg = '';
    const err = e as Error;
    if (err !== undefined && err !== null && err.message !== undefined) {
      msg = err.message;
    } else {
      msg = `${e}`;
    }
    return ModelManagerPage.readableMessage(msg);
  }

  /** 错误文案统一映射为可读中文（网络/空间/目录权限/HTTP/校验）。 */
  private static readableMessage(msg: string): string {
    const lower = msg.toLowerCase();
    if (msg.indexOf('存储空间') >= 0 || msg.indexOf('空间不足') >= 0) {
      return `${msg}（可先清理存储或删除旧模型后重试）`;
    }
    if (lower.indexOf('md5') >= 0) {
      return msg;
    }
    if (lower.indexOf('http') >= 0) {
      return `下载服务返回错误：${msg}`;
    }
    if (lower.indexOf('network') >= 0 || lower.indexOf('timeout') >= 0 || lower.indexOf('socket') >= 0
      || lower.indexOf('connect') >= 0 || msg.indexOf('网络') >= 0) {
      return '网络连接失败，请检查网络或代理后重试';
    }
    if (lower.indexOf('file exists') >= 0 || lower.indexOf('eacces') >= 0 || lower.indexOf('eperm') >= 0
      || lower.indexOf('permission') >= 0 || lower.indexOf('no such file') >= 0
      || lower.indexOf('enoent') >= 0) {
      return '存储目录不可写（权限或目录异常），请重试；仍失败可清理应用缓存后重启';
    }
    if (msg.indexOf('不支持') >= 0) {
      return msg;
    }
    return `下载失败：${msg}`;
  }

  private confirmRemove(item: ModelItem): void {
    this.deleteKey = item.modelKey;
    this.deleteName = item.displayName;
    this.deleteImported = item.isImported;
    this.deleteHasFile = item.localPath.length > 0 && item.status === DownloadStatus.DOWNLOADED;
    this.deleteDownloading = item.status === DownloadStatus.DOWNLOADING
      || item.status === DownloadStatus.VERIFYING;
  }

  private async doRemove(): Promise<void> {
    const key = this.deleteKey;
    const name = this.deleteName;
    this.deleteKey = '';
    this.deleteName = '';
    this.deleteImported = false;
    this.deleteHasFile = true;
    this.deleteDownloading = false;
    if (key.length === 0) {
      return;
    }
    try {
      await ModelManagerViewModel.remove(key);
      this.flash(`已删除「${name}」`);
      await this.refreshAll();
    } catch (e) {
      this.flash(`删除失败：${e}`);
    }
  }

  private async addCustom(): Promise<void> {
    try {
      await ModelManagerViewModel.addCustom(this.customUrl, this.customName);
      this.customUrl = '';
      this.customName = '';
      this.showCustom = false;
      this.flash('已添加自定义模型（下载后可用于本地翻译）');
      await this.refreshAll();
    } catch (e) {
      this.hint = `${e}`;
    }
  }

  private async importGguf(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['GGUF 模型 (.gguf)|.gguf'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      await ModelManagerViewModel.importGguf(uris[0]);
      this.flash('已导入本地 GGUF 并登记路径（不复制文件）');
      await this.refreshAll();
    } catch (e) {
      this.flash(ModelManagerPage.readableError(e));
    }
  }

  @Builder
  statsCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_storage'))
          .width(16)
          .height(16)
          .fillColor(ThemeTokens.PRIMARY)
        Text('存储占用')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
        Blank()
        Text(`已下载 ${this.downloadedTotal()} / ${this.items.length}`)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('模型目录')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text(ModelManagerPage.formatSize(this.stats.usedBytes))
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.PRIMARY_SOFT)
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text('可用空间')
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text(this.freeLabel())
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeTokens.SUCCESS)
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .backgroundColor(ThemeTokens.SURFACE_VARIANT)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionButton(label: string, enabled: boolean, color: string, onTap: () => void) {
    Button(label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(enabled ? ThemeTokens.WHITE : ThemeTokens.TEXT_HINT)
      .backgroundColor(enabled ? color : ThemeTokens.SURFACE_VARIANT)
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .height(30)
      .padding({ left: 13, right: 13 })
      .enabled(enabled)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  modelCard(item: ModelItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 3 }) {
          Row({ space: 8 }) {
            Text(item.displayName)
              .fontSize(ThemeTokens.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
            if (item.isImported) {
              Text('本地导入')
                .fontSize(10)
                .fontColor(ThemeTokens.SUCCESS)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            } else if (item.isCustom) {
              Text('自定义')
                .fontSize(10)
                .fontColor(ThemeTokens.PRIMARY)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(ThemeTokens.RADIUS_PILL)
                .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            }
          }
          Text(`${item.quant} · ${item.sizeLabel.length > 0 ? item.sizeLabel : '大小未知'}`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.statusLabel(item.status))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(this.statusColor(item.status))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(ThemeTokens.RADIUS_PILL)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')

      if (item.status === DownloadStatus.DOWNLOADING || item.status === DownloadStatus.VERIFYING
        || item.status === DownloadStatus.PAUSED) {
        Progress({ value: item.progressPct, total: 100, type: ProgressType.Linear })
          .color(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .height(6)
          .borderRadius(3)
          .width('100%')
        Row() {
          Text(`${item.progressPct}%`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Blank()
          if (item.speedLabel.length > 0) {
            Text(item.speedLabel)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.PRIMARY_SOFT)
          }
        }
        .width('100%')
      }

      if (item.status === DownloadStatus.DOWNLOADED && item.localPath.length > 0) {
        Text(`路径：${item.localPath}`)
          .fontSize(10)
          .fontColor(ThemeTokens.TEXT_TERTIARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.errorOf(item.modelKey).length > 0) {
        Text(this.errorOf(item.modelKey))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.RED)
          .width('100%')
          .lineHeight(17)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row({ space: 8 }) {
        if (!item.supported) {
          this.actionButton('暂不支持', false, ThemeTokens.SURFACE_VARIANT, () => {
          })
        } else if (item.status === DownloadStatus.NOT_DOWNLOADED || item.status === DownloadStatus.MD5_FAILED) {
          this.actionButton(item.status === DownloadStatus.MD5_FAILED ? '重新下载' : '下载', true, ThemeTokens.PRIMARY,
            () => {
              this.onDownload(item);
            })
        } else if (item.status === DownloadStatus.DOWNLOADING || item.status === DownloadStatus.VERIFYING) {
          this.actionButton('暂停', true, ThemeTokens.WARN, () => {
            this.onPause(item);
          })
          this.actionButton('强制移除', true, ThemeTokens.RED, () => {
            this.confirmRemove(item);
          })
        } else if (item.status === DownloadStatus.PAUSED) {
          this.actionButton('继续', true, ThemeTokens.PRIMARY, () => {
            this.onResume(item);
          })
        }
        if (item.status === DownloadStatus.NOT_DOWNLOADED && item.isCustom) {
          // 自定义 URL 模型在未下载状态也允许移除记录，避免加错 URL 无法清理。
          this.actionButton('移除', true, ThemeTokens.RED, () => {
            this.confirmRemove(item);
          })
        } else if (item.status !== DownloadStatus.NOT_DOWNLOADED && item.status !== DownloadStatus.UNSUPPORTED
          && item.status !== DownloadStatus.DOWNLOADING && item.status !== DownloadStatus.VERIFYING) {
          this.actionButton('删除', true, ThemeTokens.RED, () => {
            this.confirmRemove(item);
          })
        }
        Blank()
      }
      .width('100%')
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  customDialog() {
    Column() {
      Column({ space: 12 }) {
        Text('自定义模型 URL')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text('填入任意 GGUF 直链；添加后列表会出现「下载」按钮。')
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
        TextInput({ text: this.customUrl, placeholder: 'https://…/model.gguf' })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .width('100%')
          .onChange((v: string) => {
            this.customUrl = v;
          })
        TextInput({ text: this.customName, placeholder: '显示名称（可留空）' })
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .width('100%')
          .onChange((v: string) => {
            this.customName = v;
          })
        Row({ space: 12 }) {
          Button('添加')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.PRIMARY)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.addCustom();
            })
          Button('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.showCustom = false;
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
  }

  @Builder
  deleteDialog() {
    Column() {
      Column({ space: 12 }) {
        Text(this.deleteImported || !this.deleteHasFile || this.deleteDownloading ? '移除模型记录' : '删除模型')
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(this.deleteImported
          ? `确定移除「${this.deleteName}」的模型记录？仅移除记录，不删除原文件（导入的 GGUF 保留在原路径）。`
          : (this.deleteDownloading
            ? `确定强制移除「${this.deleteName}」？将中止当前下载、清理临时文件（.part）与下载记录。`
            : (this.deleteHasFile
              ? `确定删除「${this.deleteName}」？将同时清理已下载文件与下载记录。`
              : `确定移除「${this.deleteName}」的记录？当前没有已下载文件，仅移除记录，不会删除文件。`)))
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%')
          .lineHeight(19)
        Row({ space: 12 }) {
          Button(this.deleteImported || !this.deleteHasFile || this.deleteDownloading ? '移除' : '删除')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.RED)
            .fontColor(ThemeTokens.WHITE)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.doRemove();
            })
          Button('取消')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .backgroundColor(ThemeTokens.SURFACE_VARIANT)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .borderRadius(ThemeTokens.RADIUS_PILL)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteKey = '';
              this.deleteName = '';
              this.deleteImported = false;
              this.deleteHasFile = true;
              this.deleteDownloading = false;
            })
        }
        .width('100%')
      }
      .padding(ThemeTokens.PAGE_PADDING)
      .width('82%')
      .borderRadius(ThemeTokens.RADIUS_CARD)
      .backgroundColor(ThemeTokens.SURFACE_SECONDARY)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          Row({ space: 8 }) {
            Button('自定义 URL')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .height(32)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.showCustom = true;
              })
            Button('导入本地 GGUF')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .height(32)
              .padding({ left: 14, right: 14 })
              .onClick(() => {
                this.importGguf();
              })
            Blank()
            Button('刷新')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .backgroundColor(ThemeTokens.SURFACE_VARIANT)
              .borderRadius(ThemeTokens.RADIUS_PILL)
              .height(32)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.refreshAll();
              })
          }
          .width('100%')

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .width('100%')
              .maxLines(2)
          }

          if (this.stats.freeBytes > 0 && this.stats.freeBytes < 2 * 1024 * 1024 * 1024) {
            Text('提示：剩余存储不足 2 GB，下载大型 GGUF 前请先清理空间。')
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.WARN)
              .width('100%')
          }

          Scroll() {
            Column({ space: 10 }) {
              this.statsCard()

              Row({ space: 8 }) {
                Text('预置模型')
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text(`${this.presetItems().length}`)
                  .fontSize(10)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                Blank()
                Text('Hy-MT2 系列')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .maxLines(1)
              }
              .width('100%')
              .margin({ top: 6 })
              .alignItems(VerticalAlign.Center)

              if (this.presetItems().length === 0) {
                Text('暂无预置模型')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .width('100%')
              }
              ForEach(this.presetItems(), (item: ModelItem) => {
                this.modelCard(item)
              }, (item: ModelItem) => `preset-${item.modelKey}-${item.status}-${item.progressPct}-${item.speedLabel}-${this.errorOf(item.modelKey)}`)

              Text('说明：1.25bit 档位缺少上游 STQ1_0 加载补丁，本版标注「暂不支持」；请使用 Q4_K_M 档。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_HINT)
                .width('100%')
                .lineHeight(17)

              Row({ space: 8 }) {
                Text('自定义与导入')
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                Text(`${this.customItems().length}`)
                  .fontSize(10)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .borderRadius(ThemeTokens.RADIUS_PILL)
                  .backgroundColor(ThemeTokens.SURFACE_VARIANT)
                Blank()
                Text('URL 下载或本地 GGUF 登记')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .maxLines(1)
              }
              .width('100%')
              .margin({ top: 6 })
              .alignItems(VerticalAlign.Center)
              if (this.customItems().length === 0) {
                Text('暂无自定义模型；可用右上角「自定义 URL」或「导入本地 GGUF」添加。')
                  .fontSize(ThemeTokens.FONT_SMALL)
                  .fontColor(ThemeTokens.TEXT_HINT)
                  .width('100%')
                  .lineHeight(18)
              }
              ForEach(this.customItems(), (item: ModelItem) => {
                this.modelCard(item)
              }, (item: ModelItem) => `custom-${item.modelKey}-${item.status}-${item.progressPct}-${item.speedLabel}-${this.errorOf(item.modelKey)}`)

              Text('说明：下载支持断点续传与 MD5 校验。下载模型删除时会清理 models 目录中的文件与下载记录；导入的本地 GGUF 仅登记原路径，删除时仅移除记录，不删除你的原文件。')
                .fontSize(ThemeTokens.FONT_SMALL)
                .fontColor(ThemeTokens.TEXT_TERTIARY)
                .width('100%')
                .lineHeight(18)
                .margin({ top: 4, bottom: 16 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
        }
        .padding(ThemeTokens.PAGE_PADDING)
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.showCustom) {
          this.customDialog()
        }
        if (this.deleteKey.length > 0) {
          this.deleteDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('模型管理', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
    .onShown(() => {
      this.refreshAll();
    })
  }

  private static formatSize(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
    }
    if (bytes >= 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    if (bytes >= 1024) {
      return `${Math.round(bytes / 1024)} KB`;
    }
    return `${bytes} B`;
  }
}
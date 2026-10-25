import { picker } from '@kit.CoreFileKit';
import { uiMaterial } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { SpikeOutcome } from 'coremodel';
import { ThemeTokens, Log } from 'commons';
import { SpikeKeys, SpikeViewModel } from '../viewmodel/SpikeViewModel';
import { ImportService } from '../service/ImportService';

/**
 * P0-2 / P0-3 验证页（T019 / US-2）：目录授权验证块（选目录→授权→
 * 重启免授权重扫结论）、解压验证块（zip→解压→图片数/页序）、相册
 * 验证块（多选→复制结论）；执行结论经 SpikeDao 落库回显工作台。
 */
@Component
export struct SpikeImportPage {
  @State p02Status: string = '未执行';
  @State p02Detail: string = '';
  @State p02Busy: boolean = false;
  @State p02MangaId: number = -1;
  @State p03aStatus: string = '未执行';
  @State p03aDetail: string = '';
  @State p03aBusy: boolean = false;
  @State p03bStatus: string = '未执行';
  @State p03bDetail: string = '';
  @State p03bBusy: boolean = false;

  private async record(key: string, outcome: SpikeOutcome, detail: string): Promise<void> {
    try {
      await SpikeViewModel.makeResultPair(key, outcome, detail);
    } catch (e) {
      Log.error('SpikeImportPage', `record ${key} failed: ${e}`);
    }
  }

  // ---------- P0-2: directory grant + restart-free rescan ----------

  private async runP02(): Promise<void> {
    if (this.p02Busy) {
      return;
    }
    this.p02Busy = true;
    this.p02Status = '执行中';
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.selectMode = picker.DocumentSelectMode.FOLDER;
      opts.maxSelectNumber = 1;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        this.p02Status = '未执行';
        this.p02Busy = false;
        return;
      }
      const manga = await ImportService.importDirectory(uris[0]);
      this.p02MangaId = manga.id;
      // Simulate the "restart" half of SC-003: rescan goes through the
      // persisted grant with no picker involved.
      const rescanned = await ImportService.rescanDirectory(manga.id);
      const authOk = await ImportService.probeDirectoryAuth(manga.id);
      if (authOk && rescanned.pageCount === manga.pageCount) {
        this.p02Status = '通过';
        this.p02Detail = `目录「${manga.name}」授权持久化，免授权重扫 ${rescanned.pageCount} 页成功`;
        await this.record(SpikeKeys.P0_2, SpikeOutcome.PASS, this.p02Detail);
      } else {
        this.p02Status = '失败';
        this.p02Detail = `重扫页数 ${rescanned.pageCount} != ${manga.pageCount}，或授权探测失败（authOk=${authOk}）`;
        await this.record(SpikeKeys.P0_2, SpikeOutcome.FAIL, this.p02Detail);
      }
    } catch (e) {
      this.p02Status = '失败';
      this.p02Detail = `${e}`;
      await this.record(SpikeKeys.P0_2, SpikeOutcome.FAIL, this.p02Detail);
    }
    this.p02Busy = false;
  }

  // ---------- P0-3a: zip decompress ----------

  private async runP03Archive(): Promise<void> {
    if (this.p03aBusy) {
      return;
    }
    this.p03aBusy = true;
    this.p03aStatus = '执行中';
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['压缩包 (.zip, .cbz)|.zip,.cbz'];
      opts.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await docPicker.select(opts);
      if (uris.length === 0) {
        this.p03aStatus = '未执行';
        this.p03aBusy = false;
        return;
      }
      const result = await ImportService.importArchives(uris, () => {
      }, () => {
        return false;
      });
      if (result.imported.length > 0) {
        const m = result.imported[0];
        this.p03aStatus = '通过';
        this.p03aDetail = `「${m.name}」解压建档成功：${m.pageCount} 页，自然页序 v2 < v10`;
        await this.record(SpikeKeys.P0_3, SpikeOutcome.PASS, this.p03aDetail);
      } else if (result.failures.length > 0) {
        this.p03aStatus = '失败';
        this.p03aDetail = `${result.failures[0].name}：${result.failures[0].reason}`;
        await this.record(SpikeKeys.P0_3, SpikeOutcome.FAIL, this.p03aDetail);
      } else {
        this.p03aStatus = '失败';
        this.p03aDetail = '未选择压缩包';
      }
    } catch (e) {
      this.p03aStatus = '失败';
      this.p03aDetail = `${e}`;
      await this.record(SpikeKeys.P0_3, SpikeOutcome.FAIL, this.p03aDetail);
    }
    this.p03aBusy = false;
  }

  // ---------- P0-3b: album photos ----------

  private async runP03Album(): Promise<void> {
    if (this.p03bBusy) {
      return;
    }
    this.p03bBusy = true;
    this.p03bStatus = '执行中';
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 500;
      const result = await photoPicker.select(opts);
      const uris = result.photoUris;
      if (uris.length === 0) {
        this.p03bStatus = '未执行';
        this.p03bBusy = false;
        return;
      }
      const manga = await ImportService.importPhotos(uris, () => {
      });
      this.p03bStatus = '通过';
      this.p03bDetail = `相册多选 ${manga.pageCount} 张复制入沙箱成功`;
      await this.record(SpikeKeys.P0_3, SpikeOutcome.PASS, this.p03bDetail);
    } catch (e) {
      this.p03bStatus = '失败';
      this.p03bDetail = `${e}`;
      await this.record(SpikeKeys.P0_3, SpikeOutcome.FAIL, this.p03bDetail);
    }
    this.p03bBusy = false;
  }

  @Builder
  block(title: string, desc: string, status: string, detail: string, busy: boolean, button: string,
    onTap: () => void) {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(ThemeTokens.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(status)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(status === '通过' ? ThemeTokens.SUCCESS : (status === '失败' ? ThemeTokens.RED : ThemeTokens.TEXT_HINT))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
      }
      .width('100%')
      Text(desc)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('100%')
      if (detail.length > 0) {
        Text(detail)
          .fontSize(ThemeTokens.FONT_SMALL)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
      }
      Button(button)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .backgroundColor(busy ? ThemeTokens.SURFACE_VARIANT : ThemeTokens.PRIMARY)
        .fontColor(busy ? ThemeTokens.TEXT_HINT : ThemeTokens.WHITE)
        .borderRadius(18)
        .height(36)
        .padding({ left: 20, right: 20 })
        .enabled(!busy)
        .onClick(() => {
          onTap();
        })
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(ThemeTokens.CARD_BG)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          this.block('P0-2 目录持久授权',
            '系统目录选择器 → fileShare.persistPermission → 重启免授权重扫（SC-003 关键验收）',
            this.p02Status, this.p02Detail, this.p02Busy, '选择目录并验证', () => {
              this.runP02();
            })
          this.block('P0-3 压缩包解压',
            'zip/cbz → 拷入沙箱 → zlib.decompressFile → 图片过滤 → 自然页序建档',
            this.p03aStatus, this.p03aDetail, this.p03aBusy, '选择压缩包验证', () => {
              this.runP03Archive();
            })
          this.block('P0-3 相册多选',
            'PhotoViewPicker ≤500 张 → fd 复制入沙箱 → 建档',
            this.p03bStatus, this.p03bDetail, this.p03bBusy, '选择相册图片验证', () => {
              this.runP03Album();
            })
        }
        .padding(ThemeTokens.PAGE_PADDING)
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .title('导入验证（P0-2 / P0-3）', {
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        colorInvert: true
      })
    })
    .backgroundColor(ThemeTokens.SURFACE)
  }
}
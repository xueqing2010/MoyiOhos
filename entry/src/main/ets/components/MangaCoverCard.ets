import { ThemeTokens, toMediaUri } from 'commons';
import { Artwork } from './Artwork';
import { MangaDisplay } from '../model/UiModels';

/**
 * 封面卡片（T022 / US-3 / stage-2 S101）：
 * 网格/列表两用；封面缺省或加载失败时按 manga.id % 4 使用紫夜占位底纹；
 * 展示页数、翻译状态、阅读进度徽标；目录源带手动重扫角标；多选态带选中标记。
 * 长按菜单由书架父组件统一弹出（长按触发 onLongPress）。
 */
@Component
export struct MangaCoverCard {
  display: MangaDisplay = new MangaDisplay();
  listMode: boolean = false;
  selectMode: boolean = false;
  @Prop selected: boolean = false;
  /** 网格封面高度（vp）：由父组件按断点/列宽计算，避免宽高比在 Grid 内失控。 */
  @Prop gridCoverHeight: number = 210;
  onTap: () => void = () => {
  };
  onLongPress: () => void = () => {
  };
  onRescan: () => void = () => {
  };
  @State private coverFailed: boolean = false;

  private statusColor(): string {
    if (this.display.statusDone) {
      return ThemeTokens.SUCCESS;
    }
    if (this.display.statusRunning) {
      return ThemeTokens.WARN;
    }
    return ThemeTokens.TEXT_HINT;
  }

  private hasCover(): boolean {
    return this.display.coverPath.length > 0 && !this.coverFailed;
  }

  /** 缺省封面：Artwork.pickCover(manga.id)（按 id % 4 稳定取封面占位插画）。 */
  @Builder
  placeholderImage() {
    Image(Artwork.pickCover(this.display.id))
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
  }

  @Builder
  statusBadge() {
    Text(this.display.statusLabel)
      .fontSize(9)
      .fontColor(this.statusColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor('#CC0B0813')
  }

  @Builder
  pageBadge() {
    Text(`${this.display.pageCount} 页`)
      .fontSize(9)
      .fontColor(ThemeTokens.TEXT_PRIMARY)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(ThemeTokens.RADIUS_PILL)
      .backgroundColor('#CC0B0813')
  }

  @Builder
  progressBadge() {
    if (this.display.progressLabel.length > 0) {
      Text(this.display.progressLabel)
        .fontSize(9)
        .fontColor(ThemeTokens.PRIMARY_SOFT)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(ThemeTokens.RADIUS_PILL)
        .backgroundColor('#B30B0813')
    }
  }

  @Builder
  selectMark(size: number) {
    Stack() {
      if (this.selected) {
        Image(Artwork.ICON_CHECK)
          .width(size * 0.6)
          .height(size * 0.6)
          .fillColor(ThemeTokens.BLACK)
      }
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(this.selected ? ThemeTokens.PRIMARY : '#660B0813')
    .borderWidth(this.selected ? 0 : 1)
    .borderColor('#66EDE8FA')
  }

  /** 网格封面（宽自适应，2:3 书封比例）。 */
  @Builder
  gridCover() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 关键：Stack 必须显式定高，否则内部 height('100%') 的徽标层会把
      // Stack 撑成父级可用高度，导致封面下方出现大块空白、文本被推到底部。
      if (this.hasCover()) {
        Image(toMediaUri(this.display.coverPath))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .onError(() => {
            this.coverFailed = true;
          })
      } else {
        Stack() {
          this.placeholderImage()
        }
        .width('100%')
        .height('100%')
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .clip(true)
      }
      Row() {
        this.statusBadge()
        Blank()
        if (this.display.isDirectory && !this.selectMode) {
          Image(Artwork.ICON_REFRESH)
            .width(22)
            .height(22)
            .padding(4)
            .fillColor(ThemeTokens.PRIMARY_SOFT)
            .borderRadius(11)
            .backgroundColor('#990B0813')
            .onClick(() => {
              this.onRescan();
            })
        }
      }
      .width('100%')
      .padding(4)

      Column() {
        Blank()
        Row() {
          this.progressBadge()
          Blank()
          this.pageBadge()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(4)

      if (this.selectMode) {
        Row() {
          Blank()
          this.selectMark(22)
        }
        .width('100%')
        .padding(4)
      }
    }
    .width('100%')
    .height(this.gridCoverHeight)
    .borderRadius(ThemeTokens.RADIUS_SMALL)
    .clip(true)
  }

  @Builder
  gridCard() {
    Column({ space: 6 }) {
      this.gridCover()
      Column({ space: 3 }) {
        Text(this.display.name)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 4 }) {
          Text(this.display.sourceLabel)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Blank()
          if (this.display.progressLabel.length > 0) {
            Text(this.display.progressLabel)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.TEXT_HINT)
              .maxLines(1)
          } else {
            Text(this.display.statusLabel)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(this.statusColor())
              .maxLines(1)
          }
        }
        .width('100%')
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onTap();
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress();
        })
    )
  }

  /** 列表缩略封面（固定尺寸，避免长列表抖动）。 */
  @Builder
  listCover() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.hasCover()) {
        Image(toMediaUri(this.display.coverPath))
          .width(52)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(ThemeTokens.RADIUS_SMALL)
          .onError(() => {
            this.coverFailed = true;
          })
      } else {
        Stack() {
          this.placeholderImage()
        }
        .width(52)
        .height(72)
        .borderRadius(ThemeTokens.RADIUS_SMALL)
        .clip(true)
      }
      if (this.selectMode) {
        Row() {
          this.selectMark(20)
        }
        .margin(3)
      }
    }
    .width(52)
    .height(72)
  }

  @Builder
  listCard() {
    Row({ space: 12 }) {
      this.listCover()
      Column({ space: 4 }) {
        Text(this.display.name)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 6 }) {
          Text(this.display.sourceLabel)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          Text(`${this.display.pageCount} 页`)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(ThemeTokens.TEXT_HINT)
          if (this.display.progressLabel.length > 0) {
            Text(this.display.progressLabel)
              .fontSize(ThemeTokens.FONT_SMALL)
              .fontColor(ThemeTokens.PRIMARY_SOFT)
          }
        }
        Row({ space: 6 }) {
          Circle({ width: 6, height: 6 })
            .fill(this.statusColor())
          Text(this.display.statusLabel)
            .fontSize(ThemeTokens.FONT_SMALL)
            .fontColor(this.statusColor())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.display.isDirectory && !this.selectMode) {
        Image(Artwork.ICON_REFRESH)
          .width(28)
          .height(28)
          .padding(5)
          .fillColor(ThemeTokens.PRIMARY_SOFT)
          .borderRadius(14)
          .backgroundColor(ThemeTokens.SURFACE_VARIANT)
          .onClick(() => {
            this.onRescan();
          })
      }
    }
    .padding(ThemeTokens.CARD_PADDING)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .backgroundColor(this.selected && this.selectMode ? ThemeTokens.SURFACE_SECONDARY : ThemeTokens.CARD_BG)
    .borderWidth(this.selected && this.selectMode ? 1 : 0)
    .borderColor(ThemeTokens.PRIMARY)
    .width('100%')
    .onClick(() => {
      this.onTap();
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress();
        })
    )
  }

  build() {
    if (this.listMode) {
      this.listCard()
    } else {
      this.gridCard()
    }
  }
}
import { ThemeTokens } from 'commons';
import { Artwork } from '../components/Artwork';

/**
 * 小说模块共用小组件：封面占位、状态徽标。
 *
 * 封面策略（art-dev 的 cover_placeholder_1..4 已就绪）：
 * - Novel.coverPath 记录了资源名（cover_placeholder_2/3）时按名取；
 * - 为空（示例/旧数据）时按 novelId 稳定取一张（Artwork.pickCover），不会出现空白封面。
 */
@Component
export struct NovelCover {
  name: string = '';
  coverPath: string = '';
  novelId: number = 0;
  coverHeight: number = 150;
  radius: number = ThemeTokens.RADIUS_SMALL;

  private coverRes(): Resource {
    if (this.coverPath === 'cover_placeholder_1') {
      return Artwork.COVER_PLACEHOLDERS[0];
    }
    if (this.coverPath === 'cover_placeholder_2') {
      return Artwork.COVER_PLACEHOLDERS[1];
    }
    if (this.coverPath === 'cover_placeholder_3') {
      return Artwork.COVER_PLACEHOLDERS[2];
    }
    if (this.coverPath === 'cover_placeholder_4') {
      return Artwork.COVER_PLACEHOLDERS[3];
    }
    if (this.novelId > 0) {
      // 约定：小说封面只在 2/3 两张之间稳定轮换（lead 指定）。
      return Math.abs(this.novelId) % 2 === 0 ? Artwork.COVER_PLACEHOLDERS[1]
        : Artwork.COVER_PLACEHOLDERS[2];
    }
    return Artwork.COVER_PLACEHOLDERS[1];
  }

  build() {
    // 封面只画图片：书名/格式徽标等信息一律放在封面下方的文本区，绝不覆盖封面。
    Image(this.coverRes())
      .width('100%')
      .height(this.coverHeight)
      .objectFit(ImageFit.Cover)
      .borderRadius(this.radius)
      .borderWidth(1)
      .borderColor('#33A78BFA')
      .clip(true)
  }
}

/** 翻译状态徽标（未翻译/部分翻译/已翻译）。 */
@Component
export struct NovelStatusBadge {
  label: string = '未翻译';
  done: boolean = false;
  partial: boolean = false;

  private badgeColor(): string {
    if (this.done) {
      return ThemeTokens.SUCCESS;
    }
    if (this.partial) {
      return ThemeTokens.WARN;
    }
    return ThemeTokens.TEXT_HINT;
  }

  build() {
    Text(this.label)
      .fontSize(ThemeTokens.FONT_SMALL)
      .fontColor(this.badgeColor())
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .borderRadius(6)
      .backgroundColor('#22A78BFA')
  }
}

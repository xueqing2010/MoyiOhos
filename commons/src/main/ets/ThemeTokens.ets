/**
 * StarFlow HarmonyOS design tokens — 蓝白 / 蓝黑（默认蓝白）.
 * 已移除紫色主题；token 名称保持不变，页面无需改动。
 */
export type ThemeMode = 'blue' | 'blueDark';

export class ThemeTokens {
  private static modeValue: ThemeMode = 'blue';

  static SURFACE: string = '#FFFFFF';
  static SURFACE_VARIANT: string = '#F2F7FF';
  static SURFACE_SECONDARY: string = '#E9F2FF';
  static SURFACE_HIGH: string = '#DCE9FB';
  static CARD_BG: string = '#FFFFFF';
  static CARD_HOVER: string = '#F5FAFF';
  static DIVIDER: string = '#DCE8F7';
  static SCRIM: string = '#CC0B1220';

  static TEXT_PRIMARY: string = '#0B1F33';
  static TEXT_SECONDARY: string = '#3E566F';
  static TEXT_HINT: string = '#6C8299';
  static TEXT_TERTIARY: string = '#93A7BC';
  static TEXT_ON_PRIMARY: string = '#FFFFFF';

  static PRIMARY: string = '#0A66FF';
  static PRIMARY_DEEP: string = '#004FCC';
  static PRIMARY_SOFT: string = '#5B97FF';
  static ACCENT: string = '#2F7CFF';
  static RED: string = '#D93B4F';
  static SUCCESS: string = '#12805C';
  static WARN: string = '#B26A00';
  static WHITE: string = '#FFFFFF';
  static BLACK: string = '#0A1220';

  static MATERIAL_TINT: string = '#CCFFFFFF';
  static GLASS_BORDER: string = '#661F6FEB';

  static readonly READER_BG_BLACK: string = '#000000';
  static readonly READER_BG_NOCTURNE: string = '#0B0813';
  static readonly READER_BG_PLUM: string = '#16112A';
  static readonly READER_BG_DEEP: string = '#221A38';
  static readonly READER_BG_PAPER: string = '#F5EFE4';
  static readonly READER_BG_WHITE: string = '#FFFFFF';
  static readonly READER_BG_GRAY: string = '#808080';

  static readonly FONT_TITLE: number = 20;
  static readonly FONT_SUBTITLE: number = 17;
  static readonly FONT_BODY: number = 16;
  static readonly FONT_CAPTION: number = 13;
  static readonly FONT_SMALL: number = 12;
  static readonly FONT_DISPLAY: number = 28;

  static readonly RADIUS_CARD: number = 16;
  static readonly RADIUS_SMALL: number = 10;
  static readonly RADIUS_PILL: number = 999;

  static readonly PAGE_PADDING: number = 16;
  static readonly CARD_PADDING: number = 14;
  static readonly GAP: number = 12;

  static readonly DURATION_FAST: number = 150;
  static readonly DURATION_BASE: number = 240;

  /** 蓝白/蓝黑运行时切换；未知旧值（purple/oled/system）迁移到蓝白。 */
  static applyMode(mode: string): void {
    if (mode === 'blueDark') {
      ThemeTokens.modeValue = 'blueDark';
      ThemeTokens.SURFACE = '#071426';
      ThemeTokens.SURFACE_VARIANT = '#0D1F35';
      ThemeTokens.SURFACE_SECONDARY = '#12283F';
      ThemeTokens.SURFACE_HIGH = '#18334F';
      ThemeTokens.CARD_BG = '#0D1F35';
      ThemeTokens.CARD_HOVER = '#14304A';
      ThemeTokens.DIVIDER = '#1E3A57';
      ThemeTokens.SCRIM = '#E6000000';
      ThemeTokens.TEXT_PRIMARY = '#E8F2FF';
      ThemeTokens.TEXT_SECONDARY = '#A9C2DD';
      ThemeTokens.TEXT_HINT = '#7693B2';
      ThemeTokens.TEXT_TERTIARY = '#5A7693';
      ThemeTokens.TEXT_ON_PRIMARY = '#FFFFFF';
      ThemeTokens.PRIMARY = '#5B9CFF';
      ThemeTokens.PRIMARY_DEEP = '#3B7BDD';
      ThemeTokens.PRIMARY_SOFT = '#8DBCFF';
      ThemeTokens.ACCENT = '#6EA8FF';
      ThemeTokens.RED = '#FF7A8A';
      ThemeTokens.SUCCESS = '#4FD1A5';
      ThemeTokens.WARN = '#F0B95C';
      ThemeTokens.WHITE = '#FFFFFF';
      ThemeTokens.BLACK = '#000000';
      ThemeTokens.MATERIAL_TINT = '#33FFFFFF';
      ThemeTokens.GLASS_BORDER = '#3DFFFFFF';
      return;
    }
    ThemeTokens.modeValue = 'blue';
    ThemeTokens.SURFACE = '#FFFFFF';
    ThemeTokens.SURFACE_VARIANT = '#F2F7FF';
    ThemeTokens.SURFACE_SECONDARY = '#E9F2FF';
    ThemeTokens.SURFACE_HIGH = '#DCE9FB';
    ThemeTokens.CARD_BG = '#FFFFFF';
    ThemeTokens.CARD_HOVER = '#F5FAFF';
    ThemeTokens.DIVIDER = '#DCE8F7';
    ThemeTokens.SCRIM = '#CC0B1220';
    ThemeTokens.TEXT_PRIMARY = '#0B1F33';
    ThemeTokens.TEXT_SECONDARY = '#3E566F';
    ThemeTokens.TEXT_HINT = '#6C8299';
    ThemeTokens.TEXT_TERTIARY = '#93A7BC';
    ThemeTokens.TEXT_ON_PRIMARY = '#FFFFFF';
    ThemeTokens.PRIMARY = '#0A66FF';
    ThemeTokens.PRIMARY_DEEP = '#004FCC';
    ThemeTokens.PRIMARY_SOFT = '#5B97FF';
    ThemeTokens.ACCENT = '#2F7CFF';
    ThemeTokens.RED = '#D93B4F';
    ThemeTokens.SUCCESS = '#12805C';
    ThemeTokens.WARN = '#B26A00';
    ThemeTokens.WHITE = '#FFFFFF';
    ThemeTokens.BLACK = '#0A1220';
    ThemeTokens.MATERIAL_TINT = '#CCFFFFFF';
    ThemeTokens.GLASS_BORDER = '#661F6FEB';
  }

  static mode(): ThemeMode {
    return ThemeTokens.modeValue;
  }

  static isLight(): boolean {
    return ThemeTokens.modeValue === 'blue';
  }
}

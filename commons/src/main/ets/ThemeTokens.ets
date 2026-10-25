/**
 * StarFlow HarmonyOS design tokens — Purple Nocturne（默认）+ Blue White（蓝白）.
 * Token names stay stable; values switch at runtime via applyMode().
 */
export type ThemeMode = 'purple' | 'blue' | 'oled' | 'system';

export class ThemeTokens {
  private static modeValue: ThemeMode = 'purple';

  static SURFACE: string = '#120E1F';
  static SURFACE_VARIANT: string = '#1A142C';
  static SURFACE_SECONDARY: string = '#221A38';
  static SURFACE_HIGH: string = '#2A2045';
  static CARD_BG: string = '#1A142C';
  static CARD_HOVER: string = '#241B3C';
  static DIVIDER: string = '#2A2140';
  static SCRIM: string = '#CC0B0813';

  static TEXT_PRIMARY: string = '#EDE8FA';
  static TEXT_SECONDARY: string = '#ADA3C9';
  static TEXT_HINT: string = '#7D7398';
  static TEXT_TERTIARY: string = '#5D5578';
  static TEXT_ON_PRIMARY: string = '#14101F';

  static PRIMARY: string = '#A78BFA';
  static PRIMARY_DEEP: string = '#7C5CE0';
  static PRIMARY_SOFT: string = '#C4B5FD';
  static ACCENT: string = '#C4B5FD';
  static RED: string = '#F26D7E';
  static SUCCESS: string = '#5FD3A6';
  static WARN: string = '#F0B95C';
  static WHITE: string = '#FAFAFA';
  static BLACK: string = '#08060F';

  static MATERIAL_TINT: string = '#33FFFFFF';
  static GLASS_BORDER: string = '#3DFFFFFF';

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

  /** Apply persisted palette; called at shell startup and theme change. */
  static applyMode(mode: string): void {
    ThemeTokens.modeValue = mode === 'blue' ? 'blue' : (mode === 'oled' ? 'oled' : 'purple');
    if (mode === 'blue') {
      ThemeTokens.SURFACE = '#F5F9FF';
      ThemeTokens.SURFACE_VARIANT = '#EAF3FF';
      ThemeTokens.SURFACE_SECONDARY = '#E3EEFC';
      ThemeTokens.SURFACE_HIGH = '#D7E6F8';
      ThemeTokens.CARD_BG = '#FFFFFF';
      ThemeTokens.CARD_HOVER = '#F0F6FF';
      ThemeTokens.DIVIDER = '#D5E3F5';
      ThemeTokens.SCRIM = '#CC0B1220';
      ThemeTokens.TEXT_PRIMARY = '#0F2742';
      ThemeTokens.TEXT_SECONDARY = '#3E5C7E';
      ThemeTokens.TEXT_HINT = '#6B86A8';
      ThemeTokens.TEXT_TERTIARY = '#8FA6C2';
      ThemeTokens.TEXT_ON_PRIMARY = '#FFFFFF';
      ThemeTokens.PRIMARY = '#1F6FEB';
      ThemeTokens.PRIMARY_DEEP = '#1557C0';
      ThemeTokens.PRIMARY_SOFT = '#6EA8FF';
      ThemeTokens.ACCENT = '#3B82F6';
      ThemeTokens.RED = '#D93B4F';
      ThemeTokens.SUCCESS = '#1F9D68';
      ThemeTokens.WARN = '#C07A12';
      ThemeTokens.WHITE = '#FFFFFF';
      ThemeTokens.BLACK = '#0A1220';
      ThemeTokens.MATERIAL_TINT = '#B3FFFFFF';
      ThemeTokens.GLASS_BORDER = '#661F6FEB';
      return;
    }
    if (mode === 'oled') {
      ThemeTokens.SURFACE = '#000000';
      ThemeTokens.SURFACE_VARIANT = '#0A0812';
      ThemeTokens.SURFACE_SECONDARY = '#120E1F';
      ThemeTokens.SURFACE_HIGH = '#1A142C';
      ThemeTokens.CARD_BG = '#0A0812';
      ThemeTokens.CARD_HOVER = '#16112A';
      ThemeTokens.SCRIM = '#E6000000';
    } else {
      ThemeTokens.SURFACE = '#120E1F';
      ThemeTokens.SURFACE_VARIANT = '#1A142C';
      ThemeTokens.SURFACE_SECONDARY = '#221A38';
      ThemeTokens.SURFACE_HIGH = '#2A2045';
      ThemeTokens.CARD_BG = '#1A142C';
      ThemeTokens.CARD_HOVER = '#241B3C';
      ThemeTokens.SCRIM = '#CC0B0813';
    }
    ThemeTokens.DIVIDER = '#2A2140';
    ThemeTokens.TEXT_PRIMARY = '#EDE8FA';
    ThemeTokens.TEXT_SECONDARY = '#ADA3C9';
    ThemeTokens.TEXT_HINT = '#7D7398';
    ThemeTokens.TEXT_TERTIARY = '#5D5578';
    ThemeTokens.TEXT_ON_PRIMARY = '#14101F';
    ThemeTokens.PRIMARY = '#A78BFA';
    ThemeTokens.PRIMARY_DEEP = '#7C5CE0';
    ThemeTokens.PRIMARY_SOFT = '#C4B5FD';
    ThemeTokens.ACCENT = '#C4B5FD';
    ThemeTokens.RED = '#F26D7E';
    ThemeTokens.SUCCESS = '#5FD3A6';
    ThemeTokens.WARN = '#F0B95C';
    ThemeTokens.WHITE = '#FAFAFA';
    ThemeTokens.BLACK = '#08060F';
    ThemeTokens.MATERIAL_TINT = '#33FFFFFF';
    ThemeTokens.GLASS_BORDER = '#3DFFFFFF';
  }

  static mode(): ThemeMode {
    return ThemeTokens.modeValue;
  }

  static isLight(): boolean {
    return ThemeTokens.modeValue === 'blue';
  }
}

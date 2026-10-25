/**
 * StarFlow HarmonyOS design tokens — "Purple Nocturne" (紫夜阅读).
 * Upstream dark-card layout retained; palette shifted to a reading-friendly
 * violet nocturne. Keep legacy token names stable: pages across the app use
 * them, only the values change.
 */
export class ThemeTokens {
  // surfaces — deep violet nocturne
  static readonly SURFACE: string = '#120E1F';
  static readonly SURFACE_VARIANT: string = '#1A142C';
  static readonly SURFACE_SECONDARY: string = '#221A38';
  static readonly SURFACE_HIGH: string = '#2A2045';
  static readonly CARD_BG: string = '#1A142C';
  static readonly CARD_HOVER: string = '#241B3C';
  static readonly DIVIDER: string = '#2A2140';
  static readonly SCRIM: string = '#CC0B0813';

  // text — warm violet-white, low blue light
  static readonly TEXT_PRIMARY: string = '#EDE8FA';
  static readonly TEXT_SECONDARY: string = '#ADA3C9';
  static readonly TEXT_HINT: string = '#7D7398';
  static readonly TEXT_TERTIARY: string = '#5D5578';
  static readonly TEXT_ON_PRIMARY: string = '#14101F';

  // brand / status
  static readonly PRIMARY: string = '#A78BFA';
  static readonly PRIMARY_DEEP: string = '#7C5CE0';
  static readonly PRIMARY_SOFT: string = '#C4B5FD';
  static readonly ACCENT: string = '#C4B5FD';
  static readonly RED: string = '#F26D7E';
  static readonly SUCCESS: string = '#5FD3A6';
  static readonly WARN: string = '#F0B95C';
  static readonly WHITE: string = '#FAFAFA';
  static readonly BLACK: string = '#08060F';

  // immersive material tints (used when uiMaterial unavailable)
  static readonly MATERIAL_TINT: string = '#33FFFFFF';
  static readonly GLASS_BORDER: string = '#3DFFFFFF';

  // reader backgrounds (six-step cycle: nocturne → paper)
  static readonly READER_BG_BLACK: string = '#000000';
  static readonly READER_BG_NOCTURNE: string = '#0B0813';
  static readonly READER_BG_PLUM: string = '#16112A';
  static readonly READER_BG_DEEP: string = '#221A38';
  static readonly READER_BG_PAPER: string = '#F5EFE4';
  static readonly READER_BG_WHITE: string = '#FFFFFF';
  static readonly READER_BG_GRAY: string = '#808080';

  // font sizes (fp)
  static readonly FONT_TITLE: number = 20;
  static readonly FONT_SUBTITLE: number = 17;
  static readonly FONT_BODY: number = 16;
  static readonly FONT_CAPTION: number = 13;
  static readonly FONT_SMALL: number = 12;
  static readonly FONT_DISPLAY: number = 28;

  // radii (vp)
  static readonly RADIUS_CARD: number = 16;
  static readonly RADIUS_SMALL: number = 10;
  static readonly RADIUS_PILL: number = 999;

  // spacing (vp)
  static readonly PAGE_PADDING: number = 16;
  static readonly CARD_PADDING: number = 14;
  static readonly GAP: number = 12;

  // motion
  static readonly DURATION_FAST: number = 150;
  static readonly DURATION_BASE: number = 240;
}

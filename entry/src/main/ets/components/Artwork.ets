/**
 * Artwork.ets — 紫夜阅读（Purple Nocturne）美术资产统一出口。
 *
 * 约定：
 * - 单色图标：24x24 viewBox，fill=#FFFFFF，可直接 Image(Artwork.ICON_X).fillColor(ThemeTokens.PRIMARY)；
 * - 彩色插画：空态 / 引导 / 封面占位，直接 Image(Artwork.EMPTY_SHELF) 显示，不要 fillColor（会整体染色）；
 * - 页面不要再写裸媒体引用，统一从这里取，便于替换与多主题演进。
 */
export class Artwork {
  // ==================== 空态插画（彩色，160x160） ====================
  static readonly EMPTY_SHELF: Resource = $r('app.media.empty_shelf');
  static readonly EMPTY_NOVEL: Resource = $r('app.media.empty_novel');
  static readonly EMPTY_HISTORY: Resource = $r('app.media.empty_history');
  static readonly EMPTY_SEARCH: Resource = $r('app.media.empty_search');
  static readonly EMPTY_GENERIC: Resource = $r('app.media.empty_generic');

  // ==================== 引导插画（彩色，320x200） ====================
  static readonly ONBOARDING_HERO: Resource = $r('app.media.onboarding_1');
  static readonly ONBOARDING_IMPORT: Resource = $r('app.media.onboarding_2');
  static readonly ONBOARDING_ENGINE: Resource = $r('app.media.onboarding_3');
  /** 第 4 页「完成/开始使用」（spec 允许 3-4 页引导）。 */
  static readonly ONBOARDING_READY: Resource = $r('app.media.onboarding_4');

  // ==================== 封面占位（彩色，120x160，紫调渐变） ====================
  static readonly COVER_PLACEHOLDERS: Array<Resource> = [
    $r('app.media.cover_placeholder_1'),
    $r('app.media.cover_placeholder_2'),
    $r('app.media.cover_placeholder_3'),
    $r('app.media.cover_placeholder_4')
  ];

  /** 按 id 稳定取一张封面占位（负数安全），MangaCoverCard / 小说封面缺失时用。 */
  static pickCover(id: number): Resource {
    const count: number = Artwork.COVER_PLACEHOLDERS.length;
    const index: number = Math.abs(Math.trunc(id)) % count;
    return Artwork.COVER_PLACEHOLDERS[index];
  }

  // ==================== Tab 图标 ====================
  static readonly TAB_SHELF: Resource = $r('app.media.ic_tab_shelf');
  static readonly TAB_IMPORT: Resource = $r('app.media.ic_tab_import');
  static readonly TAB_TRANSLATE: Resource = $r('app.media.ic_tab_translate');
  static readonly TAB_HISTORY: Resource = $r('app.media.ic_tab_history');
  static readonly TAB_ME: Resource = $r('app.media.ic_tab_me');

  // ==================== 通用动作图标 ====================
  static readonly ICON_ADD: Resource = $r('app.media.ic_add');
  static readonly ICON_CLOSE: Resource = $r('app.media.ic_close');
  static readonly ICON_CHECK: Resource = $r('app.media.ic_check');
  static readonly ICON_DELETE: Resource = $r('app.media.ic_delete');
  static readonly ICON_EDIT: Resource = $r('app.media.ic_edit');
  static readonly ICON_REFRESH: Resource = $r('app.media.ic_refresh');
  static readonly ICON_SEARCH: Resource = $r('app.media.ic_search');
  static readonly ICON_MORE: Resource = $r('app.media.ic_more');
  static readonly ICON_SORT: Resource = $r('app.media.ic_sort');
  static readonly ICON_ARROW_RIGHT: Resource = $r('app.media.ic_arrow_right');
  static readonly ICON_ARROW_LEFT: Resource = $r('app.media.ic_arrow_left');
  static readonly ICON_CHEVRON_DOWN: Resource = $r('app.media.ic_chevron_down');
  static readonly ICON_CHEVRON_UP: Resource = $r('app.media.ic_chevron_up');
  static readonly ICON_VIEW_GRID: Resource = $r('app.media.ic_view_grid');
  static readonly ICON_VIEW_LIST: Resource = $r('app.media.ic_view_list');
  static readonly ICON_PAGE_UP: Resource = $r('app.media.ic_page_up');
  static readonly ICON_PAGE_DOWN: Resource = $r('app.media.ic_page_down');
  static readonly ICON_SEND: Resource = $r('app.media.ic_send');
  static readonly ICON_COPY: Resource = $r('app.media.ic_copy');
  static readonly ICON_SHARE: Resource = $r('app.media.ic_share');
  static readonly ICON_DOWNLOAD: Resource = $r('app.media.ic_download');
  static readonly ICON_UPLOAD: Resource = $r('app.media.ic_upload');
  static readonly ICON_EYE: Resource = $r('app.media.ic_eye');
  static readonly ICON_EYE_OFF: Resource = $r('app.media.ic_eye_off');
  static readonly ICON_TRANSLATE_SWAP: Resource = $r('app.media.ic_translate_swap');
  static readonly ICON_STAR: Resource = $r('app.media.ic_star');
  static readonly ICON_FF_STAR: Resource = $r('app.media.ic_ff_star');
  static readonly ICON_THEME: Resource = $r('app.media.ic_theme');
  static readonly ICON_CHAT: Resource = $r('app.media.ic_chat');
  static readonly ICON_SETTINGS: Resource = $r('app.media.ic_settings');
  static readonly ICON_INFO: Resource = $r('app.media.ic_info');
  static readonly ICON_WARNING: Resource = $r('app.media.ic_warning');
  static readonly ICON_ABOUT: Resource = $r('app.media.ic_about');
  static readonly ICON_FAQ: Resource = $r('app.media.ic_faq');
  static readonly ICON_GITHUB: Resource = $r('app.media.ic_github');
  static readonly ICON_MODEL: Resource = $r('app.media.ic_model');
  static readonly ICON_WORKBENCH: Resource = $r('app.media.ic_workbench');
  static readonly ICON_BOOK: Resource = $r('app.media.ic_book');
  static readonly ICON_CLOCK: Resource = $r('app.media.ic_clock');
  static readonly ICON_PLAY: Resource = $r('app.media.ic_play');
  static readonly ICON_PAUSE: Resource = $r('app.media.ic_pause');

  // ==================== 设置 / 关于 / 配置 ====================
  static readonly ICON_API: Resource = $r('app.media.ic_api');
  static readonly ICON_KEY: Resource = $r('app.media.ic_key');
  static readonly ICON_LANGUAGE: Resource = $r('app.media.ic_language');
  static readonly ICON_OCR: Resource = $r('app.media.ic_ocr');
  static readonly ICON_READING: Resource = $r('app.media.ic_reading');
  static readonly ICON_TRANSLATE: Resource = $r('app.media.ic_translate');
  static readonly ICON_STORAGE: Resource = $r('app.media.ic_storage');
  static readonly ICON_VERSION: Resource = $r('app.media.ic_version');
  static readonly ICON_CLEAR: Resource = $r('app.media.ic_clear');
  static readonly ICON_LICENSE: Resource = $r('app.media.ic_license');

  // ==================== 导入 / 封面图标 ====================
  static readonly ICON_IMPORT_ZIP: Resource = $r('app.media.ic_import_zip');
  static readonly ICON_IMPORT_FOLDER: Resource = $r('app.media.ic_import_folder');
  static readonly ICON_IMPORT_PHOTO: Resource = $r('app.media.ic_import_photo');
  static readonly ICON_IMPORT_NOVEL: Resource = $r('app.media.ic_import_novel');
  static readonly ICON_IMPORT_TXT: Resource = $r('app.media.ic_import_txt');
  static readonly ICON_IMPORT_WIZARD: Resource = $r('app.media.ic_import_wizard');
  static readonly ICON_COVER: Resource = $r('app.media.ic_cover');
  static readonly ICON_DEMO: Resource = $r('app.media.ic_demo');
  static readonly ICON_IMAGE: Resource = $r('app.media.ic_image');

  // ==================== 阅读器图标 ====================
  static readonly ICON_READER_PREV: Resource = $r('app.media.ic_reader_prev');
  static readonly ICON_READER_NEXT: Resource = $r('app.media.ic_reader_next');
  static readonly ICON_READER_MENU: Resource = $r('app.media.ic_reader_menu');
  static readonly ICON_READER_BG: Resource = $r('app.media.ic_reader_bg');
  static readonly ICON_READER_TEXT: Resource = $r('app.media.ic_reader_text');
  static readonly ICON_READER_BATCH: Resource = $r('app.media.ic_reader_batch');
  static readonly ICON_READER_EXPORT: Resource = $r('app.media.ic_reader_export');
  static readonly ICON_READER_TOC: Resource = $r('app.media.ic_reader_toc');
  static readonly ICON_READER_SETTINGS: Resource = $r('app.media.ic_reader_settings');
  static readonly ICON_READER_REFRESH: Resource = $r('app.media.ic_reader_refresh');
  static readonly ICON_READER_STAR: Resource = $r('app.media.ic_reader_star');
  static readonly ICON_READER_FF_STAR: Resource = $r('app.media.ic_reader_ff_star');
  static readonly ICON_READER_CHAT: Resource = $r('app.media.ic_reader_chat');
  static readonly ICON_READER_THEME: Resource = $r('app.media.ic_reader_theme');
}

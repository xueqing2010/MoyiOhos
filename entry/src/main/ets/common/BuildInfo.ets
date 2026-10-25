/**
 * Build-time facts for P0-1 presentation: module manifest, versions.
 * P0-1 (multi-module skeleton) is a build-time fact — the workbench
 * presents this manifest statically (plan D14).
 */
export class BuildInfo {
  static readonly APP_NAME: string = '星译 StarFlow';
  static readonly BUNDLE_NAME: string = 'com.moe.starflow';
  static readonly APP_VERSION: string = '1.1.0';
  static readonly HARMONY_API_LEVEL: string = '26';
  static readonly BUILD_DATE: string = '2026-10-25';

  /** Full module manifest: 1 HAP + 6 HAR (must match root build-profile.json5). */
  static readonly MODULES: Array<string> = [
    'entry (HAP)',
    'commons (HAR)',
    'coremodel (HAR)',
    'coreocr (HAR)',
    'coretranslate (HAR)',
    'corerender (HAR)',
    'corenovel (HAR)'
  ];

  static readonly MODULE_COUNT: number = 7;

  /** One-line module summary for P0-1 result detail. */
  static moduleSummary(): string {
    return `HAP=1, HAR=6, apiLevel=${BuildInfo.HARMONY_API_LEVEL}, build=${BuildInfo.BUILD_DATE}`;
  }
}

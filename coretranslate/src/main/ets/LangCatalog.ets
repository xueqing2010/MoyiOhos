/**
 * Language catalog (stage 2 / translate engine).
 *
 * Single source of truth for the language codes shown in the translate UI and
 * injected into the prompt templates. Two names per language:
 *  · label      — Chinese display name for the chips / Select options
 *  · promptName — stable English name used inside the system prompt so that
 *                 the model never has to guess what "ja" means.
 *
 * Kept inside coretranslate so every module (text translate page, novel and
 * manga prompts injected from entry) shares one list.
 */

/** One selectable language. */
export interface LangOption {
  /** BCP-47-ish code used by engines: 'auto' | 'zh' | 'ja' | ... */
  code: string;
  /** Chinese label for the UI. */
  label: string;
  /** English name injected into prompts. */
  promptName: string;
}

function makeLang(code: string, label: string, promptName: string): LangOption {
  const o: LangOption = { code: code, label: label, promptName: promptName };
  return o;
}

const AUTO: LangOption = makeLang('auto', '自动检测', 'auto-detected language');

const ALL: Array<LangOption> = [
  makeLang('zh', '简体中文', 'Simplified Chinese'),
  makeLang('zh-Hant', '繁体中文', 'Traditional Chinese'),
  makeLang('en', '英语', 'English'),
  makeLang('ja', '日语', 'Japanese'),
  makeLang('ko', '韩语', 'Korean'),
  makeLang('fr', '法语', 'French'),
  makeLang('de', '德语', 'German'),
  makeLang('es', '西班牙语', 'Spanish'),
  makeLang('ru', '俄语', 'Russian'),
  makeLang('it', '意大利语', 'Italian'),
  makeLang('pt', '葡萄牙语', 'Portuguese'),
  makeLang('th', '泰语', 'Thai'),
  makeLang('vi', '越南语', 'Vietnamese'),
  makeLang('id', '印尼语', 'Indonesian'),
  makeLang('ar', '阿拉伯语', 'Arabic')
];

/**
 * Language helpers. Everything is static: the catalog is immutable and is
 * read from builders (prompt construction) as well as from UI state.
 */
export class LangCatalog {
  static readonly AUTO: LangOption = AUTO;
  static readonly DEFAULT_SOURCE: string = 'auto';
  static readonly DEFAULT_TARGET: string = 'zh';

  /** Target languages (no 'auto' — a target must be concrete). */
  static all(): Array<LangOption> {
    return ALL;
  }

  /** Source languages: 'auto' first, then the full list. */
  static sourceOptions(): Array<LangOption> {
    const out: Array<LangOption> = [AUTO];
    for (const item of ALL) {
      out.push(item);
    }
    return out;
  }

  /** Lookup by code; undefined when unknown (caller falls back to the code). */
  static byCode(code: string): LangOption | undefined {
    if (code === AUTO.code) {
      return AUTO;
    }
    for (const item of ALL) {
      if (item.code === code) {
        return item;
      }
    }
    return undefined;
  }

  /** Chinese display name; the raw code when unknown. */
  static displayName(code: string): string {
    const found = LangCatalog.byCode(code);
    return found === undefined ? code : found.label;
  }

  /** English prompt name; the raw code when unknown. */
  static promptName(code: string): string {
    const found = LangCatalog.byCode(code);
    return found === undefined ? code : found.promptName;
  }

  /** Normalise an arbitrary persisted value into a known target language. */
  static normalizeTarget(code: string): string {
    if (code.length === 0 || code === 'auto') {
      return LangCatalog.DEFAULT_TARGET;
    }
    return LangCatalog.byCode(code) === undefined ? LangCatalog.DEFAULT_TARGET : code;
  }

  /** Normalise an arbitrary persisted value into a known source language. */
  static normalizeSource(code: string): string {
    if (code.length === 0) {
      return LangCatalog.DEFAULT_SOURCE;
    }
    return LangCatalog.byCode(code) === undefined ? LangCatalog.DEFAULT_SOURCE : code;
  }

  /** Index of a code inside a list (for Select.selected); -1 when absent. */
  static indexOf(list: Array<LangOption>, code: string): number {
    for (let i = 0; i < list.length; i++) {
      if (list[i].code === code) {
        return i;
      }
    }
    return -1;
  }
}

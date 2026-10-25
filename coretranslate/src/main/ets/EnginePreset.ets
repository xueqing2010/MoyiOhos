/**
 * OpenAI-compatible provider presets (stage 2 / S107).
 *
 * A preset is a *configuration template* only — it never becomes a new
 * EngineType (BING=0 / OPENAI_COMPAT=1 / LOCAL_LLAMA=2 stay stable). The UI
 * picks a preset, the preset supplies baseUrl + a sensible default model, and
 * the user only has to paste an API key.
 *
 * ids are the persisted identity ('openai_provider' preference) and must stay
 * stable forever: changing them silently loses every user's configuration.
 */

/** One provider preset. */
export interface EnginePreset {
  /** Persisted id ('deepseek' | 'qwen' | ...). Never rename. */
  id: string;
  /** Chinese display name. */
  label: string;
  /** Short tagline shown under the name (models / billing hint). */
  hint: string;
  /** OpenAI-compatible base URL, ends WITHOUT the /chat/completions suffix. */
  baseUrl: string;
  /** Default model name; empty for the custom preset (the user must type one). */
  defaultModel: string;
  /** Console page where the user gets an API key. */
  consoleUrl: string;
  /** true = user-editable base URL / model (the "自定义" entry). */
  custom: boolean;
}

function makePreset(id: string, label: string, hint: string, baseUrl: string,
  defaultModel: string, consoleUrl: string, custom: boolean): EnginePreset {
  const p: EnginePreset = {
    id: id,
    label: label,
    hint: hint,
    baseUrl: baseUrl,
    defaultModel: defaultModel,
    consoleUrl: consoleUrl,
    custom: custom
  };
  return p;
}

/** The custom (bring-your-own-endpoint) preset id. */
export const CUSTOM_PRESET_ID: string = 'custom';

/** Small URL helpers used by the reverse lookup (kept local, no deps). */
class EnginePresetHelper {
  static normalizeUrl(url: string): string {
    let out = url.trim().toLowerCase();
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}

/**
 * Preset table. The six ids below are also the allowed values of the
 * 'openai_provider' preference (settings-dev writes it, we read it).
 */
export class EnginePresets {
  static readonly DEEPSEEK: EnginePreset = makePreset(
    'deepseek', 'DeepSeek', 'deepseek-chat · 性价比高',
    'https://api.deepseek.com/v1', 'deepseek-chat',
    'https://platform.deepseek.com/api_keys', false);

  static readonly QWEN: EnginePreset = makePreset(
    'qwen', '通义千问', 'qwen-plus · 阿里云百炼',
    'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus',
    'https://bailian.console.aliyun.com/', false);

  static readonly DOUBAO: EnginePreset = makePreset(
    'doubao', '豆包', '火山方舟 Ark',
    'https://ark.cn-beijing.volces.com/api/v3', 'doubao-seed-2-0-pro-260215',
    'https://console.volcengine.com/ark', false);

  static readonly ZHIPU: EnginePreset = makePreset(
    'zhipu', '智谱 AI', 'glm-4-flash · 有免费额度',
    'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash-250414',
    'https://open.bigmodel.cn/usercenter/apikeys', false);

  static readonly KIMI: EnginePreset = makePreset(
    'kimi', 'Kimi（月之暗面）', 'moonshot-v1-8k · 长上下文',
    'https://api.moonshot.cn/v1', 'moonshot-v1-8k',
    'https://platform.moonshot.cn/console/api-keys', false);

  static readonly SILICONFLOW: EnginePreset = makePreset(
    'siliconflow', '硅基流动', 'DeepSeek-V3 · 聚合平台',
    'https://api.siliconflow.cn/v1', 'deepseek-ai/DeepSeek-V3',
    'https://cloud.siliconflow.cn/account/ak', false);

  static readonly HUNYUAN: EnginePreset = makePreset(
    'hunyuan', '腾讯混元', 'hunyuan-turbos-latest',
    'https://api.hunyuan.cloud.tencent.com/v1', 'hunyuan-turbos-latest',
    'https://console.cloud.tencent.com/hunyuan/api-key', false);

  static readonly MINIMAX: EnginePreset = makePreset(
    'minimax', 'MiniMax', 'MiniMax-Text-01',
    'https://api.minimax.chat/v1', 'MiniMax-Text-01',
    'https://platform.minimaxi.com/user-center/basic-information/interface-key', false);

  static readonly OPENAI: EnginePreset = makePreset(
    'openai', 'OpenAI', 'gpt-4o-mini',
    'https://api.openai.com/v1', 'gpt-4o-mini',
    'https://platform.openai.com/api-keys', false);

  static readonly CUSTOM: EnginePreset = makePreset(
    'custom', '自定义', '自建 / 中转 OpenAI 兼容端点',
    'https://api.openai.com/v1', '',
    '', true);

  /** Order shown in the preset dropdown. */
  static all(): Array<EnginePreset> {
    return [
      EnginePresets.DEEPSEEK,
      EnginePresets.KIMI,
      EnginePresets.SILICONFLOW,
      EnginePresets.QWEN,
      EnginePresets.DOUBAO,
      EnginePresets.HUNYUAN,
      EnginePresets.MINIMAX,
      EnginePresets.ZHIPU,
      EnginePresets.OPENAI,
      EnginePresets.CUSTOM
    ];
  }

  /** Lookup by persisted id; unknown ids fall back to OpenAI. */
  static byId(id: string): EnginePreset {
    for (const p of EnginePresets.all()) {
      if (p.id === id) {
        return p;
      }
    }
    return EnginePresets.OPENAI;
  }

  static has(id: string): boolean {
    for (const p of EnginePresets.all()) {
      if (p.id === id) {
        return true;
      }
    }
    return false;
  }

  /** Default preset for a fresh install (DeepSeek: cheap, fast, no proxy). */
  static defaultPreset(): EnginePreset {
    return EnginePresets.DEEPSEEK;
  }

  /** Index inside all() — for Select.selected. */
  static indexOf(id: string): number {
    const list = EnginePresets.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return i;
      }
    }
    return list.length - 1;
  }

  /** Reverse lookup by base URL (used to restore the preset a saved endpoint belongs to). */
  static findByBaseUrl(url: string): EnginePreset | undefined {
    const target = EnginePresetHelper.normalizeUrl(url);
    for (const p of EnginePresets.all()) {
      if (EnginePresetHelper.normalizeUrl(p.baseUrl) === target) {
        return p;
      }
    }
    return undefined;
  }

  /** Display labels in dropdown order. */
  static labels(): Array<string> {
    const out: Array<string> = [];
    for (const p of EnginePresets.all()) {
      out.push(p.label);
    }
    return out;
  }
}
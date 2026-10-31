import fs from '@ohos.file.fs';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';

interface GlossaryEntry {
  s: string;
  t: string;
}

interface MemoryEntry {
  s: string;
  t: string;
}

/**
 * 全局术语表（P1-7）：用户导入 JSON 数组 [{"s":"原文","t":"译文"}]。
 * 翻译前对原文做最长优先替换；后续可扩展为按书术语表。
 */
export class GlossaryService {
  private static entries: Array<GlossaryEntry> = [];
  private static memory: Map<string, string> = new Map();
  private static loaded: boolean = false;

  static path(): string {
    const dir = AppEnv.getInstance().getContext().filesDir + '/glossary';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
    }
    return dir + '/global.json';
  }

  static count(): number {
    return GlossaryService.entries.length;
  }

  static memoryPath(): string {
    const dir = AppEnv.getInstance().getContext().filesDir + '/glossary';
    return dir + '/memory.json';
  }

  static async load(): Promise<void> {
    if (GlossaryService.loaded) {
      return;
    }
    GlossaryService.loaded = true;
    try {
      const path = GlossaryService.path();
      if (fs.accessSync(path)) {
        const text = fs.readTextSync(path);
        const parsed = JSON.parse(text) as Array<Record<string, string>>;
        const out: Array<GlossaryEntry> = [];
        for (const item of parsed) {
          const s = item['s'];
          const t = item['t'];
          if (s !== undefined && t !== undefined && s.length > 0) {
            out.push({ s: s, t: t });
          }
        }
        out.sort((a: GlossaryEntry, b: GlossaryEntry): number => b.s.length - a.s.length);
        GlossaryService.entries = out;
      }
      const mpath = GlossaryService.memoryPath();
      if (fs.accessSync(mpath)) {
        const mtext = fs.readTextSync(mpath);
        const mparsed = JSON.parse(mtext) as Array<Record<string, string>>;
        for (const item of mparsed) {
          const s = item['s'];
          const t = item['t'];
          if (s !== undefined && t !== undefined && s.length > 0) {
            GlossaryService.memory.set(s, t);
          }
        }
      }
      Log.info('GlossaryService', 'loaded ' + GlossaryService.entries.length + ' glossary, '
        + GlossaryService.memory.size + ' memory');
    } catch (e) {
      Log.warn('GlossaryService', 'load failed: ' + e);
    }
  }

  static preReplace(text: string): string {
    let out = text;
    for (const entry of GlossaryService.entries) {
      if (out.indexOf(entry.s) >= 0) {
        out = out.split(entry.s).join(entry.t);
      }
    }
    return out;
  }

  static async importFromUri(uri: string): Promise<number> {
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(src.fd, GlossaryService.path());
    } finally {
      fs.closeSync(src);
    }
    GlossaryService.loaded = false;
    GlossaryService.entries = [];
    await GlossaryService.load();
    return GlossaryService.entries.length;
  }

  static lookup(source: string): string | undefined {
    return GlossaryService.memory.get(source);
  }

  /** 页翻译完成后批量写入翻译记忆（最多保留 2000 条）。 */
  static async rememberPage(sources: Array<string>, targets: Array<string>): Promise<void> {
    for (let i = 0; i < sources.length && i < targets.length; i++) {
      if (sources[i].length > 0 && targets[i].length > 0 && sources[i] !== targets[i]) {
        GlossaryService.memory.set(sources[i], targets[i]);
      }
    }
    if (GlossaryService.memory.size > 2000) {
      const keys = Array.from(GlossaryService.memory.keys());
      for (let i = 0; i < keys.length - 2000; i++) {
        GlossaryService.memory.delete(keys[i]);
      }
    }
    try {
      const list: Array<MemoryEntry> = [];
      for (const key of GlossaryService.memory.keys()) {
        list.push({ s: key, t: GlossaryService.memory.get(key) as string });
      }
      const text = JSON.stringify(list);
      const fd = fs.openSync(GlossaryService.memoryPath(),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(fd.fd, text);
      } finally {
        fs.closeSync(fd);
      }
    } catch (e) {
      Log.warn('GlossaryService', 'save memory failed: ' + e);
    }
  }

  static async clear(): Promise<void> {
    const path = GlossaryService.path();
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
    GlossaryService.entries = [];
    GlossaryService.loaded = true;
  }
}

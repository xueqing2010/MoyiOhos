import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * RDB bootstrap: creates `starflow.db` (version 1) and the 5 tables
 * exactly as defined in plan.md Data Model.
 */
export class RdbHelper {
  private static readonly DB_NAME = 'starflow.db';
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (RdbHelper.initPromise === undefined) {
      const config: relationalStore.StoreConfig = {
        name: RdbHelper.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      RdbHelper.initPromise =
        relationalStore.getRdbStore(context, config).then((store: relationalStore.RdbStore) => {
          RdbHelper.store = store;
          return RdbHelper.createTables(store);
        });
    }
    await RdbHelper.initPromise;
  }

  private static async createTables(store: relationalStore.RdbStore): Promise<void> {
    const ddl: Array<string> = [
      `CREATE TABLE IF NOT EXISTS manga (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        source_type INTEGER NOT NULL,
        source_uri TEXT,
        cover_path TEXT,
        page_count INTEGER NOT NULL,
        last_read_page INTEGER DEFAULT 0,
        translate_status INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS manga_page (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        manga_id INTEGER NOT NULL,
        page_index INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        width INTEGER,
        height INTEGER,
        translate_status INTEGER DEFAULT 0,
        UNIQUE (manga_id, page_index)
      )`,
      `CREATE TABLE IF NOT EXISTS page_translation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        page_id INTEGER NOT NULL UNIQUE,
        engine_type INTEGER,
        ocr_json TEXT,
        translations_json TEXT,
        status INTEGER,
        fail_reason TEXT,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS download_task (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model_key TEXT UNIQUE NOT NULL,
        display_name TEXT,
        url TEXT,
        file_name TEXT,
        total_bytes INTEGER,
        downloaded_bytes INTEGER,
        status INTEGER,
        expected_md5 TEXT,
        local_path TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS spike_result (
        spike_key TEXT PRIMARY KEY,
        result INTEGER,
        detail TEXT,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS novel (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        format INTEGER NOT NULL,
        source_uri TEXT,
        cover_path TEXT,
        chapter_count INTEGER NOT NULL,
        last_read_chapter INTEGER DEFAULT 0,
        last_read_offset INTEGER DEFAULT 0,
        translate_status INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS novel_chapter (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        novel_id INTEGER NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT,
        content TEXT,
        translate_status INTEGER DEFAULT 0,
        translated_content TEXT,
        fail_reason TEXT,
        updated_at INTEGER,
        UNIQUE (novel_id, chapter_index)
      )`,
      `CREATE TABLE IF NOT EXISTS text_translation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_text TEXT,
        translated_text TEXT,
        engine_type INTEGER,
        from_lang TEXT,
        to_lang TEXT,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS chat_session (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        engine_type INTEGER,
        created_at INTEGER,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS chat_message (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        role TEXT,
        content TEXT,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS reading_session (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind INTEGER NOT NULL,
        ref_id INTEGER NOT NULL,
        title TEXT,
        detail TEXT,
        cover_path TEXT,
        page_count INTEGER,
        translated_count INTEGER,
        updated_at INTEGER
      )`
    ];
    for (const sql of ddl) {
      await store.executeSql(sql);
    }
  }

  static get(): relationalStore.RdbStore {
    const s = RdbHelper.store;
    if (s === undefined) {
      throw new Error('RdbHelper 未初始化，请先在 EntryAbility 中调用 RdbHelper.init()');
    }
    return s;
  }
}

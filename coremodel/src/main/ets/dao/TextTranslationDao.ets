import { relationalStore } from '@kit.ArkData';
import { TextTranslationRecord, makeTextTranslationRecord } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** text_translation table: history of stand-alone text translations. */
export class TextTranslationDao {
  static async insert(rec: TextTranslationRecord): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'source_text': rec.sourceText,
      'translated_text': rec.translatedText,
      'engine_type': rec.engineType,
      'from_lang': rec.fromLang,
      'to_lang': rec.toLang,
      'created_at': rec.createdAt
    };
    const id = await RdbHelper.get().insert('text_translation', bucket);
    rec.id = id;
    return id;
  }

  static async queryRecent(limit: number): Promise<Array<TextTranslationRecord>> {
    const pred = new relationalStore.RdbPredicates('text_translation');
    pred.orderByDesc('created_at');
    pred.limitAs(limit);
    return TextTranslationDao.queryAndMap(pred);
  }

  static async queryAll(): Promise<Array<TextTranslationRecord>> {
    const pred = new relationalStore.RdbPredicates('text_translation');
    pred.orderByDesc('created_at');
    return TextTranslationDao.queryAndMap(pred);
  }

  static async deleteById(id: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('text_translation');
    pred.equalTo('id', id);
    await RdbHelper.get().delete(pred);
  }

  static async clear(): Promise<void> {
    const pred = new relationalStore.RdbPredicates('text_translation');
    await RdbHelper.get().delete(pred);
  }

  private static async queryAndMap(pred: relationalStore.RdbPredicates): Promise<Array<TextTranslationRecord>> {
    const rs = await RdbHelper.get().query(pred);
    const out: Array<TextTranslationRecord> = [];
    try {
      while (rs.goToNextRow()) {
        const r = makeTextTranslationRecord(
          rs.getString(rs.getColumnIndex('source_text')),
          rs.getString(rs.getColumnIndex('translated_text')),
          rs.getLong(rs.getColumnIndex('engine_type')),
          rs.getString(rs.getColumnIndex('from_lang')),
          rs.getString(rs.getColumnIndex('to_lang'))
        );
        r.id = rs.getLong(rs.getColumnIndex('id'));
        r.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        out.push(r);
      }
    } finally {
      rs.close();
    }
    return out;
  }
}

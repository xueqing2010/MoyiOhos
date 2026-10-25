import { relationalStore } from '@kit.ArkData';
import { SpikeOutcome, SpikeResult, makeSpikeResult } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** spike_result table CRUD — one row per spike key, overwritten each run. */
export class SpikeDao {
  static async upsert(result: SpikeResult): Promise<void> {
    const store = RdbHelper.get();
    result.updatedAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'spike_key': result.spikeKey,
      'result': result.result as number,
      'detail': result.detail !== undefined ? result.detail : null,
      'updated_at': result.updatedAt
    };
    const pred = new relationalStore.RdbPredicates('spike_result');
    pred.equalTo('spike_key', result.spikeKey);
    const existing = await store.query(pred, ['spike_key']);
    let exists = false;
    try {
      exists = existing.goToNextRow();
    } finally {
      existing.close();
    }
    if (exists) {
      await store.update(bucket, pred);
    } else {
      await store.insert('spike_result', bucket);
    }
  }

  static async queryAll(): Promise<Array<SpikeResult>> {
    const pred = new relationalStore.RdbPredicates('spike_result');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<SpikeResult> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(SpikeDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryByKey(spikeKey: string): Promise<SpikeResult | undefined> {
    const pred = new relationalStore.RdbPredicates('spike_result');
    pred.equalTo('spike_key', spikeKey);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return SpikeDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  private static mapRow(rs: relationalStore.ResultSet): SpikeResult {
    const r = makeSpikeResult(
      rs.getString(rs.getColumnIndex('spike_key')),
      rs.getLong(rs.getColumnIndex('result')) as SpikeOutcome
    );
    const dIdx = rs.getColumnIndex('detail');
    if (!rs.isColumnNull(dIdx)) {
      r.detail = rs.getString(dIdx);
    }
    r.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    return r;
  }
}

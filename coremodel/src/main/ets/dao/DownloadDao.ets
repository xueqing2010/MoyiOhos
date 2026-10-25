import { relationalStore } from '@kit.ArkData';
import { DownloadStatus, DownloadTask, makeDownloadTask } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** download_task table CRUD (state machine per plan Data Model). */
export class DownloadDao {
  /** Insert or replace by model_key. */
  static async upsertByModelKey(task: DownloadTask): Promise<void> {
    const store = RdbHelper.get();
    task.updatedAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'model_key': task.modelKey,
      'display_name': task.displayName,
      'url': task.url,
      'file_name': task.fileName,
      'total_bytes': task.totalBytes,
      'downloaded_bytes': task.downloadedBytes,
      'status': task.status as number,
      'expected_md5': task.expectedMd5 !== undefined ? task.expectedMd5 : null,
      'local_path': task.localPath !== undefined ? task.localPath : null,
      'created_at': task.createdAt,
      'updated_at': task.updatedAt
    };
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', task.modelKey);
    const existing = await store.query(pred, ['id']);
    let exists = false;
    try {
      exists = existing.goToNextRow();
    } finally {
      existing.close();
    }
    if (exists) {
      await store.update(bucket, pred);
    } else {
      const id = await store.insert('download_task', bucket);
      task.id = id;
    }
  }

  static async queryAll(): Promise<Array<DownloadTask>> {
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.orderByAsc('created_at');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<DownloadTask> = [];
    try {
      while (rs.goToNextRow()) {
        out.push(DownloadDao.mapRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async queryByModelKey(modelKey: string): Promise<DownloadTask | undefined> {
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', modelKey);
    const rs = await RdbHelper.get().query(pred);
    try {
      if (rs.goToNextRow()) {
        return DownloadDao.mapRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async updateProgress(modelKey: string, downloadedBytes: number, totalBytes: number,
    status: DownloadStatus): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
      'status': status as number,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', modelKey);
    await RdbHelper.get().update(bucket, pred);
  }

  static async updateStatus(modelKey: string, status: DownloadStatus): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'status': status as number,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', modelKey);
    await RdbHelper.get().update(bucket, pred);
  }

  static async updateLocalPath(modelKey: string, localPath: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'local_path': localPath,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', modelKey);
    await RdbHelper.get().update(bucket, pred);
  }

  static async deleteByModelKey(modelKey: string): Promise<void> {
    const pred = new relationalStore.RdbPredicates('download_task');
    pred.equalTo('model_key', modelKey);
    await RdbHelper.get().delete(pred);
  }

  private static mapRow(rs: relationalStore.ResultSet): DownloadTask {
    const t = makeDownloadTask(
      rs.getString(rs.getColumnIndex('model_key')),
      rs.getString(rs.getColumnIndex('display_name')),
      rs.getString(rs.getColumnIndex('url')),
      rs.getString(rs.getColumnIndex('file_name'))
    );
    t.id = rs.getLong(rs.getColumnIndex('id'));
    t.totalBytes = rs.getLong(rs.getColumnIndex('total_bytes'));
    t.downloadedBytes = rs.getLong(rs.getColumnIndex('downloaded_bytes'));
    t.status = rs.getLong(rs.getColumnIndex('status')) as DownloadStatus;
    t.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    t.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    const md5Idx = rs.getColumnIndex('expected_md5');
    if (!rs.isColumnNull(md5Idx)) {
      t.expectedMd5 = rs.getString(md5Idx);
    }
    const lpIdx = rs.getColumnIndex('local_path');
    if (!rs.isColumnNull(lpIdx)) {
      t.localPath = rs.getString(lpIdx);
    }
    return t;
  }
}

import { DownloadStatus, DownloadTask, DownloadDao } from 'coremodel';

/**
 * Download task repository (T038 / US-9): download_task 表 CRUD 包装。
 */
export class DownloadRepository {
  static async listAll(): Promise<Array<DownloadTask>> {
    return DownloadDao.queryAll();
  }

  static async get(modelKey: string): Promise<DownloadTask | undefined> {
    return DownloadDao.queryByModelKey(modelKey);
  }

  static async upsert(task: DownloadTask): Promise<void> {
    await DownloadDao.upsertByModelKey(task);
  }

  static async updateProgress(modelKey: string, downloadedBytes: number, totalBytes: number,
    status: DownloadStatus): Promise<void> {
    await DownloadDao.updateProgress(modelKey, downloadedBytes, totalBytes, status);
  }

  static async updateStatus(modelKey: string, status: DownloadStatus): Promise<void> {
    await DownloadDao.updateStatus(modelKey, status);
  }

  static async updateLocalPath(modelKey: string, localPath: string): Promise<void> {
    await DownloadDao.updateLocalPath(modelKey, localPath);
  }

  static async remove(modelKey: string): Promise<void> {
    await DownloadDao.deleteByModelKey(modelKey);
  }
}

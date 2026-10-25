import { relationalStore } from '@kit.ArkData';
import { ChatMessageRecord, ChatSession, makeChatMessage, makeChatSession } from '../model/Entities';
import { RdbHelper } from '../db/RdbHelper';

/** chat_session / chat_message: multi-turn translation conversation. */
export class ChatDao {
  static async insertSession(session: ChatSession): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'title': session.title,
      'engine_type': session.engineType,
      'created_at': session.createdAt,
      'updated_at': session.updatedAt
    };
    const id = await RdbHelper.get().insert('chat_session', bucket);
    session.id = id;
    return id;
  }

  static async touchSession(sessionId: number, title: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'title': title,
      'updated_at': Date.now()
    };
    const pred = new relationalStore.RdbPredicates('chat_session');
    pred.equalTo('id', sessionId);
    await RdbHelper.get().update(bucket, pred);
  }

  static async querySessions(): Promise<Array<ChatSession>> {
    const pred = new relationalStore.RdbPredicates('chat_session');
    pred.orderByDesc('updated_at');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<ChatSession> = [];
    try {
      while (rs.goToNextRow()) {
        const s = makeChatSession(rs.getString(rs.getColumnIndex('title')),
          rs.getLong(rs.getColumnIndex('engine_type')));
        s.id = rs.getLong(rs.getColumnIndex('id'));
        s.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        s.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
        out.push(s);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async insertMessage(msg: ChatMessageRecord): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'session_id': msg.sessionId,
      'role': msg.role,
      'content': msg.content,
      'created_at': msg.createdAt
    };
    const id = await RdbHelper.get().insert('chat_message', bucket);
    msg.id = id;
    return id;
  }

  static async queryMessages(sessionId: number): Promise<Array<ChatMessageRecord>> {
    const pred = new relationalStore.RdbPredicates('chat_message');
    pred.equalTo('session_id', sessionId);
    pred.orderByAsc('created_at');
    const rs = await RdbHelper.get().query(pred);
    const out: Array<ChatMessageRecord> = [];
    try {
      while (rs.goToNextRow()) {
        const m = makeChatMessage(rs.getLong(rs.getColumnIndex('session_id')),
          rs.getString(rs.getColumnIndex('role')),
          rs.getString(rs.getColumnIndex('content')));
        m.id = rs.getLong(rs.getColumnIndex('id'));
        m.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        out.push(m);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async deleteSession(sessionId: number): Promise<void> {
    const msgPred = new relationalStore.RdbPredicates('chat_message');
    msgPred.equalTo('session_id', sessionId);
    await RdbHelper.get().delete(msgPred);
    const sPred = new relationalStore.RdbPredicates('chat_session');
    sPred.equalTo('id', sessionId);
    await RdbHelper.get().delete(sPred);
  }
}

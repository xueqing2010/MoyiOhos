/**
 * 对话翻译服务（stage 2 / S108）。
 *
 * 封装「多轮上下文 + 流式 + 会话持久化」：
 *  · 读 ChatDao 的会话与消息，转成 PromptTemplates 需要的上下文轮次
 *  · 调用 OpenAI 兼容引擎的 messages 流式接口（onDelta 逐字回调）
 *  · 流结束后一次性落库（user + assistant 两条），会话标题取首条用户消息前 20 字
 *
 * 注意：必应与本地 llama 引擎没有多轮 messages 通道，对话模式只支持
 * OpenAI 兼容引擎（必应/本地由 UI 侧拦截并给可读提示）。
 */
import {
  ChatDao,
  ChatMessageRecord,
  ChatSession,
  makeChatMessage,
  makeChatSession
} from 'coremodel';
import { ChatMessage, CompletionOptions, EngineType, ErrorKind, TranslateError, makeCompletionOptions } from 'coretranslate';
import { Log } from 'commons';
import { AppEnv } from '../common/AppEnv';
import { ContextTurn, PromptKind, PromptTemplates } from './PromptTemplates';
import { TextTranslateViewModel, TranslateSettings } from '../viewmodel/TextTranslateViewModel';

const TAG = 'ChatTranslateService';

/** UI 会话消息模型（可变，直接放进 @State 数组渲染气泡）。 */
export class UiChatMessage {
  id: number = 0;
  /** 'user' | 'assistant' */
  role: string = 'user';
  content: string = '';
  createdAt: number = 0;
  /** true = 正在流式接收（显示光标/加载点）。 */
  streaming: boolean = false;
  /** true = 该条为错误提示（红色气泡）。 */
  failed: boolean = false;
  /** 该条属于哪次请求（用于流式结束时定位）。 */
  seq: number = 0;
}

export function makeUiMessage(role: string, content: string): UiChatMessage {
  const m = new UiChatMessage();
  m.role = role;
  m.content = content;
  m.createdAt = Date.now();
  return m;
}

/** send() 的返回值：新会话 id + 完整回答。 */
export class ChatSendResult {
  sessionId: number = 0;
  answer: string = '';
  /** true = 本次调用新建了会话。 */
  created: boolean = false;
}

export class ChatTranslateService {
  static readonly NEW_SESSION_ID: number = 0;
  static readonly DEFAULT_TITLE: string = '新对话';
  static readonly TITLE_MAX: number = 20;

  // ------------------------------------------------------------- sessions
  static async loadSessions(): Promise<Array<ChatSession>> {
    try {
      await AppEnv.ready();
      return await ChatDao.querySessions();
    } catch (e) {
      Log.warn(TAG, 'loadSessions failed: ' + e);
      return [];
    }
  }

  /** 读会话消息并转成 UI 模型（不含流式状态）。 */
  static async loadMessages(sessionId: number): Promise<Array<UiChatMessage>> {
    const out: Array<UiChatMessage> = [];
    if (sessionId <= 0) {
      return out;
    }
    try {
      await AppEnv.ready();
      const records = await ChatDao.queryMessages(sessionId);
      for (const rec of records) {
        const m = makeUiMessage(rec.role, rec.content);
        m.id = rec.id;
        m.createdAt = rec.createdAt;
        // seq doubles as the ForEach key: persisted ids are unique per session.
        m.seq = rec.id;
        out.push(m);
      }
    } catch (e) {
      Log.warn(TAG, 'loadMessages failed: ' + e);
    }
    return out;
  }

  /** 读原始记录（组装上下文用）。 */
  static async loadRawMessages(sessionId: number): Promise<Array<ChatMessageRecord>> {
    if (sessionId <= 0) {
      return [];
    }
    try {
      await AppEnv.ready();
      return await ChatDao.queryMessages(sessionId);
    } catch (e) {
      return [];
    }
  }

  static async deleteSession(sessionId: number): Promise<void> {
    if (sessionId <= 0) {
      return;
    }
    await AppEnv.ready();
    await ChatDao.deleteSession(sessionId);
  }

  /** 会话标题：首条用户消息前 20 字（去换行、压缩空白）。 */
  static titleFrom(text: string): string {
    const flat = text.replace(/\s+/g, ' ').trim();
    if (flat.length === 0) {
      return ChatTranslateService.DEFAULT_TITLE;
    }
    const max = ChatTranslateService.TITLE_MAX;
    return flat.length <= max ? flat : (flat.substring(0, max) + '…');
  }

  /** 消息记录 -> 已完成的上下文轮次（user/assistant 成对，孤立 user 忽略）。 */
  static toTurns(records: Array<ChatMessageRecord>): Array<ContextTurn> {
    const turns: Array<ContextTurn> = [];
    let pendingUser: string = '';
    for (const rec of records) {
      if (rec.role === 'user') {
        pendingUser = rec.content;
      } else if (rec.role === 'assistant') {
        if (pendingUser.length > 0 && rec.content.length > 0) {
          const turn: ContextTurn = { user: pendingUser, assistant: rec.content };
          turns.push(turn);
          pendingUser = '';
        }
      }
    }
    return turns;
  }

  /**
   * 发送一条消息并流式接收回答。
   *
   * @param sessionId 0 = 新建会话
   * @param history   该会话已有消息（不含本次输入）
   * @param input     本次用户输入
   * @param settings  当前设置（上下文轮次 / 思考模式 / 温度）
   * @param onDelta   流式回调（增量文本）
   */
  static async send(sessionId: number, history: Array<ChatMessageRecord>,
    input: string, settings: TranslateSettings,
    onDelta: (delta: string) => void): Promise<ChatSendResult> {
    const trimmed = input.trim();
    if (trimmed.length === 0) {
      throw new TranslateError(ErrorKind.BAD_CONFIG, '请输入内容');
    }
    if (settings.engine !== EngineType.OPENAI_COMPAT) {
      throw new TranslateError(ErrorKind.UNSUPPORTED,
        '对话模式需要 OpenAI 兼容引擎（必应 / 本地模型不支持多轮对话）');
    }
    await AppEnv.ready();
    await TextTranslateViewModel.applyOpenAiConfig();
    const translator = AppEnv.getInstance().getOpenAiTranslator();
    if (translator === undefined) {
      throw new TranslateError(ErrorKind.ENGINE, 'OpenAI 兼容引擎未注册');
    }
    const model = (await TextTranslateViewModel.loadOpenAiModel()).trim();
    const override = await TextTranslateViewModel.loadPromptOverride(PromptKind.CHAT);
    const turns = ChatTranslateService.toTurns(history);
    const messages: Array<ChatMessage> = PromptTemplates.chatMessages(turns, trimmed,
      settings.targetLang, settings.thinking, model, settings.contextRounds, override);
    const opts: CompletionOptions = makeCompletionOptions(settings.temperature, 4000, settings.thinking);
    Log.info(TAG, 'chat send: session=' + sessionId + ' turns=' + turns.length
      + ' keep=' + PromptTemplates.clampRounds(settings.contextRounds)
      + ' model=' + model + ' chars=' + trimmed.length);
    const answer = await translator.complete(messages, opts, onDelta);
    if (answer.trim().length === 0) {
      throw new TranslateError(ErrorKind.CONTENT, '模型返回了空回复');
    }
    // —— 流结束才落库（用户消息 + 助手回复） ——
    const result = new ChatSendResult();
    result.answer = answer;
    let sid = sessionId;
    let title = ChatTranslateService.DEFAULT_TITLE;
    try {
      if (sid <= 0) {
        const session = makeChatSession(ChatTranslateService.titleFrom(trimmed),
          settings.engine as number);
        sid = await ChatDao.insertSession(session);
        result.created = true;
        title = session.title;
      } else {
        title = ChatTranslateService.titleFrom(trimmed);
        const existing = await ChatDao.querySessions();
        for (const s of existing) {
          if (s.id === sid) {
            title = s.title;
          }
        }
        // 首条消息（历史为空）时用首条用户消息刷新标题
        if (turns.length === 0) {
          await ChatDao.touchSession(sid, ChatTranslateService.titleFrom(trimmed));
        } else {
          await ChatDao.touchSession(sid, title);
        }
      }
      const userRec = makeChatMessage(sid, 'user', trimmed);
      await ChatDao.insertMessage(userRec);
      const aiRec = makeChatMessage(sid, 'assistant', answer.trim());
      await ChatDao.insertMessage(aiRec);
      result.sessionId = sid;
    } catch (e) {
      Log.warn(TAG, 'persist chat failed: ' + e);
      result.sessionId = sid;
    }
    return result;
  }
}
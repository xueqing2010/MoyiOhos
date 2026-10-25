/**
 * Shared OpenAI-compatible chat types (stage 2 / S107).
 *
 * The translator used to build its own prompt internally and expose only
 * translate(text). Stage 2 needs the *prompt layer* to live in entry
 * (PromptTemplates: manga / novel / text / chat), so the engine now also
 * accepts an explicit messages array. These types are the contract between
 * the two layers and are intentionally free of any prompt text.
 */

/**
 * Thinking-mode tri-state (preference 'translate_thinking_mode'):
 *  · OFF  — force thinking off  → request body carries thinking:{type:'disabled'}
 *  · AUTO — follow the model default → no thinking field at all; the prompt
 *           adds a *brief*-reasoning constraint only for known reasoning models
 *  · ON   — force thinking on   → thinking:{type:'enabled'}
 */
export enum ThinkingMode {
  OFF = 0,
  AUTO = 1,
  ON = 2
}

/** Normalise anything persisted into a valid ThinkingMode. */
export function normalizeThinkingMode(raw: number): ThinkingMode {
  if (raw === ThinkingMode.OFF) {
    return ThinkingMode.OFF;
  }
  if (raw === ThinkingMode.ON) {
    return ThinkingMode.ON;
  }
  return ThinkingMode.AUTO;
}

export function thinkingModeLabel(mode: ThinkingMode): string {
  if (mode === ThinkingMode.OFF) {
    return '关闭';
  }
  if (mode === ThinkingMode.ON) {
    return '开启';
  }
  return '自动';
}

/** One chat/completions message. */
export interface ChatMessage {
  role: string;
  content: string;
}

export function makeChatMessage(role: string, content: string): ChatMessage {
  const m: ChatMessage = { role: role, content: content };
  return m;
}

export function systemMessage(content: string): ChatMessage {
  return makeChatMessage('system', content);
}

export function userMessage(content: string): ChatMessage {
  return makeChatMessage('user', content);
}

export function assistantMessage(content: string): ChatMessage {
  return makeChatMessage('assistant', content);
}

/**
 * Per-call sampling / reasoning options. Defaults mirror the MVP-1 engine
 * (temperature 0.3, 1000 tokens) so existing call sites behave identically.
 */
export class CompletionOptions {
  temperature: number = 0.3;
  maxTokens: number = 1000;
  thinking: ThinkingMode = ThinkingMode.AUTO;
}

export function makeCompletionOptions(temperature: number, maxTokens: number,
  thinking: ThinkingMode): CompletionOptions {
  const o = new CompletionOptions();
  o.temperature = clampTemperature(temperature);
  o.maxTokens = maxTokens > 0 ? maxTokens : 1000;
  o.thinking = thinking;
  return o;
}

/** Clamp temperature into the OpenAI-accepted range (0.0 – 2.0). */
export function clampTemperature(value: number): number {
  if (Number.isNaN(value)) {
    return 0.3;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 2) {
    return 2;
  }
  return value;
}

/**
 * Heuristic: does the model name look like a reasoning ("thinking") model?
 * Used by AUTO mode to append a *short*-reasoning constraint, and by the UI to
 * warn that translation will be slower. Deliberately substring based: the model
 * naming space of every vendor changes faster than any allow-list.
 */
export function isReasoningModel(model: string): boolean {
  const m = model.toLowerCase();
  const hints: Array<string> = [
    '-reasoner', 'reasoner', 'reasoning', 'thinking', 'qwq', 'o1-', 'o3-', 'o4-',
    'deepseek-r1', '-r1', 'glm-z1', 'glm-z', 'seed-1-6-thinking', 'magistral'
  ];
  for (const h of hints) {
    if (m.indexOf(h) >= 0) {
      return true;
    }
  }
  return false;
}

/** Short human-readable model family for the thinking-mode hint. */
export function describeThinking(mode: ThinkingMode, model: string): string {
  if (mode === ThinkingMode.OFF) {
    return '思考模式：关闭（最快，兼容所有模型）';
  }
  if (mode === ThinkingMode.ON) {
    return '思考模式：开启（更准，但更慢更费 token）';
  }
  if (isReasoningModel(model)) {
    return '思考模式：自动（推理模型，已加简短思考约束）';
  }
  return '思考模式：自动（跟随模型默认）';
}

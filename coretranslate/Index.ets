/**
 * coretranslate HAR entry.
 *
 * Stage 2 additions are purely additive — every MVP-1 export keeps its name and
 * shape so PageTranslateService / BatchTranslateService / SpikeEnginePage keep
 * compiling:
 *  · EngineType stays BING=0 / OPENAI_COMPAT=1 / LOCAL_LLAMA=2 (presets are
 *    configuration templates, never new engine types).
 *  · OpenAiCompatTranslator gains complete(messages) + presets but keeps
 *    translate / translateStream / listModels.
 */
export {
  EngineType,
  TranslateRequest,
  Translator,
  EngineRegistry,
  TranslateError,
  ErrorKind
} from './src/main/ets/Translator';
export { AssetKeyStore } from './src/main/ets/AssetKeyStore';
export { GenOptions, LlamaBackend, LlamaError, makeGenOptions } from './src/main/ets/LlamaBackend';
export { ModelPreset, ModelPresets } from './src/main/ets/ModelPresets';
export { BingTranslator } from './src/main/ets/bing/BingTranslator';
export { OpenAiCompatTranslator, OpenAiConfig } from './src/main/ets/openai/OpenAiCompatTranslator';
export { SseParser } from './src/main/ets/openai/SseParser';
export { LocalLlamaTranslator } from './src/main/ets/local/LocalLlamaTranslator';
// ---- stage 2 (S107): presets / languages / chat-completion types ----
export { EnginePreset, EnginePresets, CUSTOM_PRESET_ID } from './src/main/ets/EnginePreset';
export { LangOption, LangCatalog } from './src/main/ets/LangCatalog';
export {
  ChatMessage,
  CompletionOptions,
  ThinkingMode,
  assistantMessage,
  clampTemperature,
  describeThinking,
  isReasoningModel,
  makeChatMessage,
  makeCompletionOptions,
  normalizeThinkingMode,
  systemMessage,
  thinkingModeLabel,
  userMessage
} from './src/main/ets/openai/OpenAiTypes';

# 翻译与性能

## 1. 统一 Translator 抽象

不要让 UI 判断引擎类型：

```ts
export interface TranslateRequest {
  text: string;
  source?: string;
  target: string;
  context?: string;
}

export interface Translator {
  readonly type: EngineType;
  translate(req: TranslateRequest): Promise<string>;
}
```

实现：
- BingTranslator（免费/无 Key，质量一般）；
- OpenAICompatibleTranslator（DeepSeek/Kimi/硅基流动/混元/MiniMax/智谱/OpenAI/自定义）；
- LocalLlamaTranslator（GGUF）。

UI 只依赖 `Translator` 和配置，不依赖具体厂商。

## 2. 服务商预设

建议内置：

| 厂商 | Base URL 形态 | 备注 |
|---|---|---|
| DeepSeek | api.deepseek.com | OpenAI 兼容 |
| Kimi | api.moonshot.cn | OpenAI 兼容 |
| 硅基流动 | api.siliconflow.cn | OpenAI 兼容 |
| 腾讯混元 | api.hunyuan.cloud.tencent.com | OpenAI 兼容 |
| MiniMax | api.minimax.chat | OpenAI 兼容 |
| 智谱 | open.bigmodel.cn | OpenAI 兼容 |
| OpenAI | api.openai.com | 需代理 |

配置字段：endpoint、apiKey、model、temperature、maxTokens、systemPrompt。不要把 Key 写进代码。

## 3. Prompt 设计

- 明确“只输出译文，不要解释”；
- 保留人名/专有名词一致性；
- 漫画气泡短句：给上下文，不要逐字直译；
- 小说长文：按段落切分，带前文摘要；
- 日文→中文注意省略主语、语气词；
- 失败时返回原文或明确错误，不要返回空串。

## 4. 并发策略

- 网络翻译：单页文本行 4 路并发，超过容易 429；
- 本地 llama：1 路串行，多路会抢 CPU/GPU；
- 整本翻译：分页入队，限制同时 1–2 页；
- 预翻译：默认关闭，避免首屏抢带宽；
- 用户翻页时取消上一页未完成请求，防止旧结果覆盖。

示例：

```ts
const concurrency = engineType === EngineType.LOCAL_LLAMA ? 1 : 4;
```

## 5. 本地 llama.cpp

- 模型：GGUF，中文推荐 Hy-MT2 1.8B Q4_K_M；
- 下载走 ModelScope 国内镜像（HuggingFace 可能不可达）；
- 首次加载模型 1–3s，之后复用 context；
- 生成参数：temperature 0.2–0.5，top_p 0.9，maxTokens 按段限制；
- 长文分段，避免超出 context；
- 失败/内存不足要能切回在线或提示释放内存。

本项目实测：ModelScope 镜像 21.9MB/s；本地翻译单页约 6s。

## 6. 整本翻译

- 入口：漫画书架菜单「整本翻译」、小说菜单「整本翻译」；
- 先统计页数/章节数，显示进度；
- 支持暂停/继续/取消；
- 已翻译页缓存，重入不重复请求；
- 失败页记录并在最后汇总；
- 不要阻塞阅读当前页。

## 7. 预翻译

- 默认关闭；
- 开启后只预取后续 1–2 页/章；
- 阅读速度快的用户才值得；
- 弱网/流量模式自动关闭；
- 退出阅读器取消任务。

## 8. 性能预算

| 环节 | 目标 | 实测 |
|---|---|---|
| 系统 OCR 冷启动 | 预热后 < 1s | 首调 36s，预热后单页 3s |
| 本地 OCR | < 8s/页 | det 1.8s + rec 2.6s，总约 6s |
| 单页翻译 | < 10s | 系统 OCR 路线约 3s；本地 OCR 约 6s |
| Tab 切换 | < 350ms | 320ms |
| 首帧 | < 2s | 启动预热放后台 |

## 9. 优化清单

- 启动预热 OCR / 模型；
- 覆盖层排版缓存（同页不重复计算）；
- 图片解码异步 + 预加载 1–2 页；
- 网络连接复用；
- 日志分级，Release 不打 debug；
- 大模型下载断点续传；
- 避免在主线程 JSON 大对象序列化。

## 10. 坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 翻译很慢 | 本地 llama 多路并发 | 本地改 1 路 |
| 429 | 网络并发太高 | 降到 2–4 路，加退避 |
| 首屏卡 | 预翻译默认开 | 默认关闭 |
| 下载慢/失败 | HuggingFace 被墙 | ModelScope 镜像 |
| 译文为空 | API 返回结构变化 | 兼容 choices/message/content |
| 旧结果覆盖新页 | 请求无取消 | 用页码/任务 id 丢弃旧结果 |
| 内存涨 | 每页新建 session/context | 复用 + 及时释放 |

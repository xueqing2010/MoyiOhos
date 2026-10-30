# 架构与 ArkTS 实践

## 1. 模块边界

推荐按“领域”拆 HAR，而不是按页面：

| 模块 | 职责 | 不做什么 |
|---|---|---|
| entry (HAP) | 页面、导航、服务编排、C++ 推理 | 不塞解析/数据库细节 |
| commons | 主题 token、日志、工具、通用组件 | 不依赖业务 |
| coremodel | 实体、RDB、DAO、Repository | 不依赖 UI |
| corenovel | TXT/EPUB/ZIP-HTML 解析、章节、分页 | 不依赖 UI |
| coreocr | 系统 OCR 封装、结果结构 | 不做翻译 |
| corerender | 覆盖层几何、排版、FPS | 不做 OCR/翻译 |
| coretranslate | Translator 抽象、在线/本地引擎 | 不依赖页面 |

依赖方向：entry → 所有 core*；core* 之间尽量只依赖 commons/coremodel。禁止循环依赖。

## 2. 模块导出

每个 HAR 根目录只放一个 `Index.ets` 作为公开面：

```ts
export { MangaRepository } from './src/main/ets/data/MangaRepository';
export { NovelParser } from './src/main/ets/parser/NovelParser';
```

entry 的 `oh-package.json5`：

```json5
"dependencies": {
  "commons": "file:../commons",
  "coremodel": "file:../coremodel",
  "coreocr": "file:../coreocr",
  "coretranslate": "file:../coretranslate",
  "corerender": "file:../corerender",
  "corenovel": "file:../corenovel"
}
```

坑：
- 不要用相对路径深层 import 其他模块内部文件；HAR 打包后会找不到或破坏边界。
- 改 HAR 后 entry 可能需要 clean 才能拿到新产物。

## 3. ArkTS 状态管理

- 页面内：`@State` + `@Prop/@Link`；
- 跨页面：AppStorage / Preferences / RDB；
- 主题、字体、语言等全局值用 AppStorage + 持久化；
- 列表项必须有稳定 key；不要用 index；
- 大对象不要整体塞进 `@State`，拆成可观察字段，避免整页重绘；
- `aboutToAppear` 只做轻量初始化；重活放 `setTimeout`/Worker/TaskPool；
- 页面返回时清理定时器、订阅、解码器。

示例：

```ts
@State private books: Book[] = [];
@State private loading: boolean = false;

aboutToAppear(): void {
  this.load();
}

private async load(): Promise<void> {
  this.loading = true;
  try {
    this.books = await this.repo.list();
  } finally {
    this.loading = false;
  }
}
```

## 4. 异步与并发

- 文件解析、OCR、模型推理、下载不要在主线程；
- 网络并发 4 路是经验值；本地 llama 只能 1 路；
- 用 AbortController/任务 id 取消旧任务，避免用户翻页后旧结果覆盖新页；
- 所有 async 调用都要 try/catch，并在 UI 显示可操作提示。

## 5. 数据层

- RDB 建表/升级要写 migration；
- DAO 不返回 Cursor 给 UI；
- Repository 负责事务与缓存；
- 路径、URI、相对路径统一封装，避免换设备后失效；
- 删除书籍时级联清理封面/缓存/进度。

## 6. 错误处理

统一错误结构：

```ts
export class AppError extends Error {
  constructor(public code: string, message: string, public cause?: Error) {
    super(message);
  }
}
```

UI 只显示用户能理解的下一步，例如：
- “请先登录华为账号”
- “请在 AGC 开通云存储后重试”
- “模型未下载，去设置下载”

不要把底层 JSON/HTTP 错误直接弹给用户。

## 7. 依赖与原生库

- ONNX Runtime 与 AKI 版本必须匹配；本项目 `@ohos/aki` 显式 override 到 1.2.26；
- 原生 .so 要同时包含 arm64-v8a 与 x86_64（模拟器）；
- llama.cpp vendored 代码用 `.gitattributes` 标记 vendored，避免语言统计污染；
- 每次升级 SDK/依赖先跑一次 clean build，避免旧 .so 缓存。

## 8. 代码组织建议

```
entry/src/main/ets/
  pages/        页面
  views/        可复用视图
  service/      业务服务（OCR/翻译/云/导入）
  viewmodel/    页面状态
  data/         仓库与设置
  entryability/ 生命周期
```

页面不要直接 new 服务；用单例/依赖注入/工厂，方便测试和替换实现。

## 9. 重构信号

出现以下情况就拆：
- 一个页面文件 > 800 行；
- 一个 service 同时做下载、解析、OCR、翻译；
- UI 里出现 `JSON.parse`、HTTP、SQL；
- 同一个错误字符串在 3 处以上重复。

## 10. 验收

- 每个模块可单独 build；
- entry clean build 成功；
- 启动无红色报错；
- 关键路径有日志（tag 统一）；
- 关掉网络/删模型/拒绝权限时都有降级提示。

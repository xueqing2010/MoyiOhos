# Changelog

## 2026-10-30

### 翻译与 OCR

- 新增预翻译（默认关闭）与整本翻译入口；漫画书架/小说菜单均支持整本翻译。
- 新增 DeepSeek、Kimi、硅基流动、腾讯混元、MiniMax 等服务商预设。
- 本地 PP-OCRv6 det + rec 一键下载并自动启用；det 使用 jsDelivr，rec 使用 gh-proxy。
- 系统 OCR 启动预热：消除真机首次调用约 36 秒冷启动，预热后单页约 3 秒。
- 单页文本行 6 路并发翻译（本地 llama 串行）+ 页内译文缓存；本地 OCR det 降到 768 长边，真机实测单页 OCR 1.7s、翻译 3.0s、合计 4.7s。
- 翻译进度条区分 OCR / 翻译 / 保存阶段；批量面板同步显示当前页阶段。
- 修复本地 OCR 图片路径（媒体 URI + fd 回退）、GGUF 导入必须复制进沙箱、模型恢复只认 .gguf、下载完整性校验。
- 第二批：新增轻量去字底图缓存（框外底色梯度填充），翻译态用透明覆盖替代白块；本地 llama 按 3–4 行批量生成。
- TaskPool 本地 OCR 经真机验证与 ONNX Runtime 全局环境冲突（Session is closed / already initialized），已回退主线程，后续改用单一专用 Worker。
- P0-5：新增 ONNX Runtime C API 原生 det+rec 桥（libocrasync.so）+ TaskPool；主线程只解码 RGBA，det/rec 全在原生线程；模拟器 6 行验证通过，OCR 594ms、总 2057ms。
- 漫画页目标语言改为读取设置页 `target_lang`，不再硬编码中文。
- 本地 llama 翻译按空间位置合并气泡/段落（垂直间距 + 水平重叠）；6 行合成页实测 OCR 739ms + 翻译 1291ms。
- 去字底图同时采样每框边缘亮度，覆盖层逐块选择黑/白字并加 1px 描边，提升深色/复杂背景可读性。
- P1-7：新增全局术语表导入（JSON）+ 翻译前最长优先替换 + 页级翻译记忆（最多 2000 条）。
- P1-8：长按气泡打开译文校对框，保存后更新 page_translation 并立即重绘；合并块暂不支持逐行编辑。
- P1-9：导出 PDF（HMS PDFKit），按译文合成页生成；模拟器验证生成约 26KB PDF 并保存到应用 exports 目录。
- P0-3：内置 Noto Sans CJK SC，注册为 MoyiSans，覆盖层/导出统一使用；HAP 体积增加约 16MB。
- GGUF 翻译模型改用 ModelScope 国内镜像，实测 21.9MB/s。
- 修复模型管理存储统计为 0B（mkdir EEXIST）并纳入缓存分片。

### UI / 多端

- 移除紫色主题，改为蓝白默认 + 蓝黑夜间；旧主题自动迁移。
- 底部悬浮 Tab、标题栏、Slider/Toggle 使用沉浸光感材质。
- 手机/平板/宽屏 edge-to-edge，修复底部空白与顶部裁切。
- 左侧五栏使用沉浸材质与切换过渡；Tabs 内容切换动画 320ms。
- 移除快捷验证工作台、示例数据生成、OCR 自测等开发测试入口。
- 翻译历史按单本合并：一本书一行，显示累计已译页/章与最近时间，不再每次翻译新增一条。
- 修复 Tab 点击时旧栏与新栏同时高亮（onTabBarClick 立即更新选中态）。
- 平板导航轨补沉浸材质；导入页 Scroll 顶部对齐并收紧标题间距，消除大孔隙。

### 签名 / 本地优先

- 使用 `devecocli auth login` + `devecocli signature generate` 自动生成调试证书与 Profile，并写入 `build-profile.json5`。
- 移除受限 ACL 权限 `ohos.permission.FILE_ACCESS_PERSIST`，解除自动签名阻塞；文件导入改由系统文件选择器完成。
- 真机可安装，模拟器启动验证通过；真机启动需先解锁屏幕（开发者模式下 CLI 不能自动解锁）。
- **移除华为账号登录与云同步入口**：删除 AccountService / CloudSyncService / MeView 账号卡片，书籍、进度、偏好只保存在本机。

### 文档

- README 增加真机/模拟器演示截图。
- 新增 docs/TESTING.md 测试记录与已知限制。

## 2026-10-25

- 完成漫画阅读器、小说阅读器、翻译历史、设置中心与多端布局。
- 接入 llama.cpp / ONNX Runtime、华为分享与账号登录骨架。

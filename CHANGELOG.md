# Changelog

## 2026-10-30

### 翻译与 OCR

- 新增预翻译（默认关闭）与整本翻译入口；漫画书架/小说菜单均支持整本翻译。
- 新增 DeepSeek、Kimi、硅基流动、腾讯混元、MiniMax 等服务商预设。
- 本地 PP-OCRv6 det + rec 一键下载并自动启用；det 使用 jsDelivr，rec 使用 gh-proxy。
- 系统 OCR 启动预热：消除真机首次调用约 36 秒冷启动，预热后单页约 3 秒。
- 单页文本行 4 路并发翻译（本地 llama 串行），本地 OCR 单页约 6 秒。
- GGUF 翻译模型改用 ModelScope 国内镜像，实测 21.9MB/s。
- 修复模型管理存储统计为 0B（mkdir EEXIST）并纳入缓存分片。

### UI / 多端

- 移除紫色主题，改为蓝白默认 + 蓝黑夜间；旧主题自动迁移。
- 底部悬浮 Tab、标题栏、Slider/Toggle 使用沉浸光感材质。
- 手机/平板/宽屏 edge-to-edge，修复底部空白与顶部裁切。
- 左侧五栏使用沉浸材质与切换过渡；Tabs 内容切换动画 320ms。
- 移除快捷验证工作台、示例数据生成、OCR 自测等开发测试入口。

### 华为账号 / 签名

- 在 AGC 创建「星译 StarFlow」应用（`com.moe.starflow`，APP ID / Client ID 均为 `6917620459514246462`），开启华为账号开放能力。
- 使用 `devecocli auth login` + `devecocli signature generate` 自动生成调试证书与 Profile，并写入 `build-profile.json5`。
- 移除受限 ACL 权限 `ohos.permission.FILE_ACCESS_PERSIST`，解除自动签名阻塞；文件导入改由系统文件选择器完成。
- 真机可安装，模拟器启动验证通过；真机启动需先解锁屏幕（开发者模式下 CLI 不能自动解锁）。

### 文档

- README 增加真机/模拟器演示截图。
- 新增 docs/TESTING.md 测试记录与已知限制。

## 2026-10-25

- 完成漫画阅读器、小说阅读器、翻译历史、设置中心与多端布局。
- 接入 llama.cpp / ONNX Runtime、华为分享与账号登录骨架。

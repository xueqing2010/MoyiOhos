# 真机与模拟器测试记录

> 测试时间：2026-10-30  
> HarmonyOS 7.0.0 / API 26  
> 真机：PCE-W30（2880×1920，平板）  
> 模拟器：Mate 90 Pro（phone，1280×2832）、MatePad Pro 13（tablet，2880×1920）

## 覆盖范围

| 项目 | 结果 | 说明 |
|---|---|---|
| HAP 构建 / 安装 | 通过 | 120MB，含 ONNX Runtime arm64；真机覆盖安装需先卸载 |
| 手机 / 平板 / 宽屏布局 | 通过 | 手机底部 Tab，平板左侧 rail + 双列；edge-to-edge 无顶部裁切、无底部空白 |
| 系统 Core Vision OCR | 通过 | 真机首调冷启动约 36s；启动预热后单页 OCR + 翻译约 3s |
| 本地 PP-OCRv6（ONNX） | 通过 | 修复图片路径后真机 OCR 1706ms + 翻译 3020ms，整页 4728ms（GPU/CPU 预热后） |
| 本地模型加载 | 通过 | 真机 LocalOcrEngine sessions ready 171ms，GGUF llama model loaded 2474ms；模型路径只恢复 .gguf |
| OCR 模型一键下载 | 通过 | det 9.1MB jsDelivr 约 20s；rec 21.2MB gh-proxy 约 85s；下载后自动启用本地档位 |
| GGUF 翻译模型 | 通过（测速） | ModelScope 镜像，手机模拟器实测 21.9MB/s；暂停/继续/删除正常 |
| 模型管理存储统计 | 通过 | 修复 mkdir EEXIST 后显示 284.9MB，包含模型与缓存分片 |
| 蓝白 / 蓝黑主题 | 通过 | 旧紫色值自动迁移到蓝白 |
| 第二批：去字 / 批量翻译 | 模拟器验证通过 | 轻量去字底图 + 透明覆盖；本地 llama 3–4 行批量生成；大框/单字大框过滤生效 |
| 本地 OCR TaskPool | 回退 | 模拟器/真机均出现 Session is closed / already initialized；已回退主线程，待专用 Worker |
| 五栏切换 | 通过 | 书架 / 导入 / 翻译 / 历史 / 我的无崩溃 |
| 华为账号 / 云同步 | 已移除 | 1.2 删除登录与云同步入口，数据仅本机 |

## 性能记录

- 系统 OCR 冷启动：约 36s（首调）；预热后单页翻译约 3s。
- 本地 OCR：det 1706ms，7 行文本本地翻译 3020ms，整页 4728ms（<5s 目标达成）。
- 模型加载：OCR sessions ready 171ms；GGUF 模型 loaded 2474ms。
- 翻译进度条：OCR 识别阶段 15% → 翻译 x/y 行 → 保存 100%。
- GGUF 模型下载：ModelScope 镜像 21.9MB/s。
- 单页翻译目标：<10s；当前真机实测达到。

## 2026-10-31 第二批模拟器验证（MatePad Pro 13）

- 测试图 480×320，本地 PP-OCRv6：3 行 / OCR 218ms；
- 本地 llama 批量翻译：1252ms；单页合计 1472ms（测试图较小，仅验证链路）；
- 去字底图生成成功，译文态使用透明覆盖，不再出现整页白块；
- 整页大框 / 单字大框过滤生效；
- TaskPool 本地 OCR 复现 `Session is closed` / `already initialized`，已回退主线程；
- 真机 PCE-W30 未连接，未做真机复测。

## 复现命令

```bash
cd StarFlowOhos
devecocli signature generate --force   # 仅首次/换证书时
devecocli build --modules entry --build-mode debug
devecocli device unlock --device 2BD0223929003920
devecocli run --module entry --device 2BD0223929003920 --skip-build
```

## 已知限制

- **华为账号 / 云同步**：已在 1.2 中移除登录与云同步入口，书籍、进度、偏好只保存在本机。
- **真机启动**：开发者模式下 CLI 无法自动解锁屏幕，必须先手动解锁或在解锁态运行；锁屏时 `aa start` 返回 10106102。
- **2in1 模拟器**：当前环境 MateBook Pro 模拟器启动失败，2in1 窗口缩放/拖拽未完成真机回归。
- **EPUB picker**：部分系统 UIExtension 环境限制文件选择器，建议真机验证。
- **GGUF 推理**：模型体积 1GB 级，本轮仅验证下载/暂停/存储，未跑完整 token 生成。

## 截图

所有演示截图位于 [docs/images](images/)；README 已内置手机、平板、OCR 覆盖、模型管理与历史页面预览。

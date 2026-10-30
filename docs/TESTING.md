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
| 本地 PP-OCRv6（ONNX） | 通过 | 真机 det 1791ms / 总 OCR 2580ms / 整页翻译约 6s |
| OCR 模型一键下载 | 通过 | det 9.1MB jsDelivr 约 20s；rec 21.2MB gh-proxy 约 85s；下载后自动启用本地档位 |
| GGUF 翻译模型 | 通过（测速） | ModelScope 镜像，手机模拟器实测 21.9MB/s；暂停/继续/删除正常 |
| 模型管理存储统计 | 通过 | 修复 mkdir EEXIST 后显示 284.9MB，包含模型与缓存分片 |
| 蓝白 / 蓝黑主题 | 通过 | 旧紫色值自动迁移到蓝白 |
| 五栏切换 | 通过 | 书架 / 导入 / 翻译 / 历史 / 我的无崩溃 |
| 华为账号 / 云同步 | 受配置限制 | 真机返回 Invalid clientId/profile；需 AGC 正式签名与 clientId |

## 性能记录

- 系统 OCR 冷启动：约 36s（首调）；预热后单页翻译约 3s。
- 本地 OCR：det 1791ms，总 OCR 2580ms，8 行文本 4 路并发翻译约 3.2s；整页约 6s。
- GGUF 模型下载：ModelScope 镜像 21.9MB/s。
- 单页翻译目标：<10s；当前真机实测达到。

## 复现命令

```bash
cd StarFlowOhos
devecocli build --build-mode debug
hdc -t <serial> install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <serial> shell aa force-stop com.moe.starflow
hdc -t <serial> shell aa start -a EntryAbility -b com.moe.starflow
```

## 已知限制

- **华为账号登录**：调试签名未在 AGC 绑定应用，Account Kit 返回 Invalid clientId/profile；正式发布需 AGC 应用与正式签名。
- **云同步**：依赖 AGC Cloud Foundation Kit 开通云存储。
- **2in1 模拟器**：当前环境 MateBook Pro 模拟器启动失败，2in1 窗口缩放/拖拽未完成真机回归。
- **EPUB picker**：部分系统 UIExtension 环境限制文件选择器，建议真机验证。
- **GGUF 推理**：模型体积 1GB 级，本轮仅验证下载/暂停/存储，未跑完整 token 生成。

## 截图

所有演示截图位于 [docs/images](images/)；README 已内置手机、平板、OCR 覆盖、模型管理与历史页面预览。

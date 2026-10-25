# NOTICE

**StarFlowOhos（星译 StarFlow · HarmonyOS）**
Copyright (C) 2026 xueqing2010 and contributors

本仓库以 GNU Lesser General Public License v3.0（LGPL-3.0）发布，完整许可文本见 [LICENSE](LICENSE)。

## 上游归属

- **StarFlow（星译 · Android 上游）**
  - 项目地址：https://github.com/xujunjiex/StarFlow
  - 许可证：LGPL-3.0
  - 说明：本项目参照上游的功能信息架构、交互行为与视觉概念，在 HarmonyOS 上以 ArkTS 独立实现；
    本仓库**不包含、也不分发**上游 Android 二进制、原生库或模型文件。上游版权归其作者与贡献者所有。

## 随仓库分发的第三方组件

- **llama.cpp**
  - 项目地址：https://github.com/ggml-org/llama.cpp
  - 许可证：MIT
  - 位置：`entry/src/main/cpp/llama.cpp`（vendored 源码），许可全文见该目录下 `LICENSE`。
  - 用途：端侧 GGUF 推理；通过 `entry/src/main/cpp/llamacpp_bridge.cpp` 暴露 NAPI 给 ArkTS。

- **HarmonyOS SDK / Core Vision Kit / ArkUI**
  - 华为 HarmonyOS 系统能力，按 HarmonyOS SDK 许可使用；本仓库不分发其源码或二进制。
  - 用途：OCR（Core Vision Kit textRecognition）、UI 框架、RDB/Preferences/Asset Store。

## 模型

本仓库**不包含任何 GGUF 模型文件**。用户自行下载或导入的模型遵循其各自发布方的许可
（例如 Hy-MT2 模型许可归模型发布方所有）。

## 图标与视觉资源

`entry/src/main/resources/base/media/*.svg` 为本项目自绘的矢量图标，随本项目一并按 LGPL-3.0 发布。

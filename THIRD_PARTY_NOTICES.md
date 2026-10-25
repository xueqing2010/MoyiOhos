# 第三方许可与声明

本文件汇总随 `StarFlowOhos` 分发的第三方组件许可。若与各组件原始许可文本冲突，以原始许可为准。

## 1. StarFlow（Android 上游）— LGPL-3.0

- 仓库：https://github.com/xujunjiex/StarFlow
- 许可：GNU Lesser General Public License v3.0
- 关系：本项目为 HarmonyOS / ArkTS 的独立实现，参照上游信息架构、交互与视觉设计；
  不分发上游 Android 代码、二进制或模型。
- 上游版权归其作者与贡献者所有；本项目保留该归属说明，并以 LGPL-3.0 发布自身代码，便于遵循同类许可义务。
- 上游 Android 工程另含 RTranslator、RapidOCR、ONNX Runtime、manga-ocr 等第三方组件（详见上游仓库 `licenses/NOTICE.txt`）。
- 本仓库通过 OHPM 引入 ONNX Runtime 鸿蒙 NAPI 以运行用户下载的 PP-OCRv6 模型；HAP 内含对应 arm64 原生库（见第 6 节）。不随安装包分发 PP-OCR 模型文件。

## 2. llama.cpp — MIT

位置：`entry/src/main/cpp/llama.cpp`（vendored，GitHub 语言统计已排除）

```text
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 3. HarmonyOS SDK / Core Vision Kit / ArkUI

华为 HarmonyOS 系统能力，按 HarmonyOS SDK 许可使用；本仓库不分发其源码或二进制。

## 4. 模型文件

- 本仓库不包含 GGUF / ONNX 模型文件；用户在应用内下载或导入的模型遵循模型发布方许可。
- PP-OCRv6 det/rec 模型与 `ppocrv6_dict.txt` 来自上游 StarFlow 的 `app/src/main/assets/ppocrv6`（LGPL-3.0 上游仓库；PP-OCR 原始项目为 PaddleOCR，Apache-2.0）。应用仅将字典打入安装包，模型由用户按需下载。

## 5. ONNX Runtime / @ohos/onnxruntime / AKI

- **ONNX Runtime** — MIT License，https://github.com/microsoft/onnxruntime
- **@ohos/onnxruntime**（onnxruntime-napi）— MIT License，https://gitcode.com/OpenHarmony-ApplicationTPC/ohos_onnxruntime
- **@ohos/aki** — Apache License 2.0，https://gitcode.com/openharmony-sig/aki

HAP 内含上述项目的 arm64-v8a 原生库（`liblibrary.so`、`libaki_jsbind.so` 及 `libc++_shared.so`），用于本地 PP-OCR 推理。ONNX Runtime 自身的第三方组件清单见其发行包 `ThirdPartyNotices.txt`。

## 6. 本项目自身

StarFlowOhos（星译 StarFlow · HarmonyOS）— LGPL-3.0，完整文本见 [LICENSE](LICENSE)。

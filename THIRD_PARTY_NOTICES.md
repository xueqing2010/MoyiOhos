# 第三方许可与声明

本文件汇总随 `StarFlowOhos` 分发的第三方组件许可。若与各组件原始许可文本冲突，以原始许可为准。

## 1. StarFlow（Android 上游）— LGPL-3.0

- 仓库：https://github.com/xujunjiex/StarFlow
- 许可：GNU Lesser General Public License v3.0
- 关系：本项目为 HarmonyOS / ArkTS 的独立实现，参照上游信息架构、交互与视觉设计；
  不分发上游 Android 代码、二进制或模型。
- 上游版权归其作者与贡献者所有；本项目保留该归属说明，并以 LGPL-3.0 发布自身代码，便于遵循同类许可义务。
- 上游 Android 工程另含 RTranslator、RapidOCR、ONNX Runtime、manga-ocr 等第三方组件（详见上游仓库 `licenses/NOTICE.txt`）。本仓库未整合上游 Android 原生实现及其依赖，因此不随本仓库分发这些组件，其许可义务由上游/各自项目承担。

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

本仓库不包含 GGUF 模型。用户下载/导入的模型遵循模型发布方许可。

## 5. 本项目自身

StarFlowOhos（星译 StarFlow · HarmonyOS）— LGPL-3.0，完整文本见 [LICENSE](LICENSE)。

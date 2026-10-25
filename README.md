# 星译 StarFlow（HarmonyOS）

星译 StarFlow 是一个运行在 HarmonyOS 上的**漫画 / 小说 / 文本翻译工作台**：识别屏幕或图片中的文字，翻译后以覆盖层重新排版渲染回原图，同时提供小说阅读与整章翻译能力。翻译既可以走在线接口，也可以完全在端侧用内置的 llama.cpp 完成。

## 主要能力

- **漫画翻译**：Core Vision Kit 文字识别 → 版面分析 → 译文覆盖层渲染，支持阅读态与对照态
- **小说阅读**：TXT / EPUB / ZIP-HTML 解析、章节切分、分页器、阅读进度保存
- **翻译引擎**：统一 `Translator` 抽象，内置必应、OpenAI 兼容接口、本地 llama.cpp 三种实现
- **本地推理**：内置 llama.cpp（`entry/src/main/cpp/llama.cpp`），支持加载 GGUF 模型离线翻译
- **OCR 模型可选下载**：设置→OCR 中可按需下载上游 PP-OCRv6 det/rec 模型（约 9 MB / 19 MB，不随安装包分发）；ONNX Runtime 鸿蒙 NAPI 在模拟器上构造张量原生崩溃，本地推理档位暂不启用，待真机/新版运行时验证
- **渲染健壮性**：译文白块按页面像素边界裁剪，并限制在页面图像画布内，避免越界/错位
- **沉浸光感底部导航**：API 26 `uiMaterial.ImmersiveMaterial` 悬浮毛玻璃 + 选中项光晕胶囊；平板/2in1 使用左侧导航轨
- **蓝白配色**：主题外观新增蓝白浅色档，运行时切换并重建 shell，紫夜/OLED/跟随系统保留
- **导入与分享**：支持从文件管理器拖入图片/压缩包、碰一碰接收文件导入、漫画多页「华为分享」（Share Kit）
- **华为账号与云同步**：Account Kit 登录按钮 + Cloud Foundation Kit 云存储备份书架索引/进度/偏好；需 AGC 开通云存储与正式签名
- **性能**：页签内容懒加载、阅读覆盖层排版计划缓存、启动前同步应用持久化主题
- **数据层**：基于 RDB 的实体、DAO 与仓库封装

## 工程结构

```
StarFlowOhos/
├── AppScope/                # 应用级配置（bundleName: com.moe.starflow）
├── entry/                   # 主 HAP 模块：页面、视图、服务、C++ 推理
│   └── src/main/cpp/        # llama.cpp 及 JNI 封装
├── commons/                 # 主题 token、日志、自然排序等公共工具
├── coremodel/               # 数据实体、RdbHelper、DAO
├── corenovel/               # TXT/EPUB/ZIP-HTML 解析、章节切分、分页
├── coreocr/                 # 基于 Core Vision Kit 的 OCR 服务
├── corerender/              # 覆盖层几何计算、布局引擎、渲染器、FPS 统计
└── coretranslate/           # 翻译引擎：必应 / OpenAI 兼容 / 本地 llama
```

各模块之间通过 `oh-package.json5` 的本地依赖互相引用，`entry` 依赖全部 core* 模块。

## 语言构成

- 应用代码以华为 **ArkTS（`.ets`）** 为主（136 个文件、约 3.6 万行）；GitHub 通过 `.gitattributes`
  将 `*.ets` 按 **TypeScript** 统计，避免被误判为 Other。
- `entry/src/main/cpp/llama.cpp` 是 vendored 的上游 C/C++ 源码（llama.cpp），已在 `.gitattributes`
  标记 `linguist-vendored` / `linguist-detectable=false`，不计入本仓库语言比例。
- 其余为零星 C++ NAPI 桥接、SVG 图标与工程配置。

## 构建与运行

1. 安装 **DevEco Studio**（需要 HarmonyOS SDK **26.0.0**，`compatibleSdkVersion` / `targetSdkVersion` 均为 `26.0.0`）
2. 用 DevEco Studio 打开本目录，等待 `hvigor` 同步依赖（`ohpm install`）
3. 连接真机或启动模拟器，选择 `entry` 模块运行

命令行构建：

```bash
hvigorw assembleHap --mode module -p product=default
```

## 签名说明

本仓库**不包含任何签名材料**：`build-profile.json5` 中的 `signingConfigs` 已清空。首次克隆后需在 DevEco Studio 的
`File → Project Structure → Signing Configs` 中重新配置自动签名（或导入自己的 `.p12` / `.p7b`）。

若你希望本地签名改动不被提交，可使用：

```bash
git update-index --skip-worktree build-profile.json5
```

## 第三方组件与许可

- **StarFlow（星译 · Android 上游）** — [LGPL-3.0](https://github.com/xujunjiex/StarFlow)：本项目参照其信息架构、交互与视觉设计，在 HarmonyOS 上以 ArkTS 独立实现；不分发上游 Android 代码/二进制/模型。
- **llama.cpp** — [MIT](https://github.com/ggml-org/llama.cpp)：位于 `entry/src/main/cpp/llama.cpp`（vendored），许可全文见该目录下 `LICENSE`。
- **HarmonyOS SDK / Core Vision Kit / ArkUI** — 华为系统能力，按 HarmonyOS SDK 许可使用，不随仓库分发。
- 本仓库不包含 GGUF 模型文件；模型许可归各自发布方。

完整归属与许可文本见 [NOTICE.md](NOTICE.md) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

本项目以 **GNU Lesser General Public License v3.0（LGPL-3.0）** 发布，完整文本见 [LICENSE](LICENSE)。

上游 StarFlow 采用 LGPL-3.0；本项目保留其归属说明，并以相同许可证发布 HarmonyOS ArkTS 实现。
若分发修改版，请遵循 LGPL-3.0 关于源码提供、许可保留与修改说明的要求。

# 星译 StarFlow（HarmonyOS）

星译 StarFlow 是一个运行在 HarmonyOS 上的**漫画 / 小说 / 文本翻译工作台**：识别屏幕或图片中的文字，翻译后以覆盖层重新排版渲染回原图，同时提供小说阅读与整章翻译能力。翻译既可以走在线接口，也可以完全在端侧用内置的 llama.cpp 完成。

## 主要能力

- **漫画翻译**：Core Vision Kit 文字识别 → 版面分析 → 译文覆盖层渲染，支持阅读态与对照态
- **小说阅读**：TXT / EPUB / ZIP-HTML 解析、章节切分、分页器、阅读进度保存
- **翻译引擎**：统一 `Translator` 抽象，内置必应、OpenAI 兼容接口、本地 llama.cpp 三种实现
- **本地推理**：内置 llama.cpp（`entry/src/main/cpp/llama.cpp`），支持加载 GGUF 模型离线翻译
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

## 第三方组件

- [llama.cpp](https://github.com/ggml-org/llama.cpp)（MIT）位于 `entry/src/main/cpp/llama.cpp`，含各 tokenizer 的 GGUF 词表文件

## 许可证

本项目尚未声明开源许可证，如需授权使用请先联系仓库所有者。

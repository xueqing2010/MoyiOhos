---
name: harmonyos-arkts-app-dev
description: HarmonyOS NEXT（ArkTS/ArkUI，API 26，DevEco Studio 6）应用从零开发与移植的完整方法论。覆盖模块化架构、手机/平板/2in1 多端布局、沉浸光感、Core Vision/PP-OCR/ONNX Runtime、llama.cpp/GGUF、翻译服务商、Account Kit 华为账号、AGC 签名与 Profile、Cloud Foundation Kit、devecocli 构建部署、真机自动化验证。适用于开发或排查带 OCR、翻译、本地模型、华为账号、多设备布局的 HarmonyOS 应用；也适用于“照着上游 Android 应用重做鸿蒙版”的任务。
---

# HarmonyOS ArkTS 应用全流程开发

这套 skill 来自一个真实项目：把 Android 上游「星译 StarFlow」在 HarmonyOS NEXT 上重做为 ArkTS 应用，包含漫画/小说阅读、OCR 覆盖层、在线与本地翻译、华为账号、云同步和三端布局。

## 何时使用

使用：
- 从零创建或继续开发 HarmonyOS NEXT / ArkTS / ArkUI 应用；
- 把 Android/Flutter/Web 上游应用移植为鸿蒙版；
- 接入 Core Vision OCR、ONNX Runtime、PP-OCR、llama.cpp/GGUF；
- 接入 DeepSeek/OpenAI 兼容翻译、整本翻译、预翻译；
- 接入 Account Kit、AGC 签名、Profile、云存储；
- 需要手机/平板/2in1 一套代码、沉浸光感、全屏铺满；
- 需要用 devecocli / hdc 做构建、安装、真机截图与验收。

不适用：
- 只写一个纯 ArkUI 静态页面；
- 只改文案/图片；
- 需要元服务、卡片、穿戴、车机等未覆盖形态（可复用部分流程，但需另查 API）。

## 十条铁律

1. **先跑通最小闭环，再谈功能**：能构建、能安装、能启动、能截图，才算有进展。
2. **签名是账号、云同步、真机安装的共同前提**：包名、证书、Profile、AGC 应用必须四者一致。
3. **任何“模型下载/OCR/翻译”都必须有降级路径**：系统 OCR 失败→本地 OCR；在线翻译失败→本地/提示；没有模型时不能崩。
4. **真机验证优先于模拟器**：模拟器没有华为账号面板、文件选择器、部分系统能力；最终以真机为准。
5. **性能用数据说话**：单页 OCR、翻译、首帧、下载速度都要记录，不能凭感觉。
6. **主线程只做 UI**：模型推理、文件解析、下载、OCR 全部放 Worker/TaskPool/异步，避免掉帧和 ANR。
7. **所有用户数据默认本地**：上传模型、图片、书籍、API Key 前必须显式告知；密钥不写日志、不进仓库。
8. **换签名必须卸载旧包**：否则 9568332 install sign info inconsistent。
9. **文档与截图是交付物**：每个阶段留下可复现命令、截图、已知限制。
10. **不要和工具链对抗**：能用 devecocli 就用 CLI；GUI 只用于确认状态，避免被 IDE 缓存和 AX 树拖住。

## 全流程总览

| 阶段 | 目标 | 通过门槛 |
|---|---|---|
| 0 侦察 | 明确上游、SDK、设备、账号、限制 | 能列出设备/API/依赖/签名现状 |
| 1 骨架 | 多模块工程可构建 | assembleHap 成功，空壳能启动 |
| 2 UI | 三端布局与导航闭环 | 手机/平板/2in1 均无裁切/空白 |
| 3 数据 | 导入、解析、持久化 | 重启后书架/进度/设置不丢 |
| 4 OCR | 系统 OCR + 本地 OCR | 单页识别成功，覆盖层不越界 |
| 5 翻译 | 在线 + 本地 + 整本 | 单页 < 10s，失败有提示 |
| 6 账号/云 | 登录、备份/恢复 | 真机已登录，云存储可用 |
| 7 签名/发布 | 可重复安装、可交付 | 换机可复现构建与签名 |
| 8 验收 | 真机截图、日志、文档 | 测试矩阵和已知限制齐全 |

---

## Phase 0：侦察与基线

必须先查清，不要直接写代码：

- 目标 SDK：HarmonyOS NEXT / API 版本 / compatibleSdkVersion；
- 设备：真机型号、序列号、是否开发者模式、锁屏方式；
- 工具：DevEco Studio 版本、devecocli 版本、hdc 路径；
- 上游：UI 结构、核心功能、许可证（LGPL/GPL/AGPL 要保留归属）；
- 账号：AGC 是否已创建应用、是否已开 Account Kit、是否已有证书/Profile；
- 网络：HuggingFace/raw.githubusercontent 在目标网络是否可达；
- 模型：是否需要随包、是否允许下载、模型许可证。

侦察命令：

```bash
devecocli --version
devecocli device list
devecocli auth status
cd <project> && git status -sb
grep -R "compatibleSdkVersion\|targetSdkVersion" build-profile.json5
```

产出：一页 `docs/RECON.md`，记录设备、SDK、账号、网络、上游许可证。没有这一页，后面一定反复踩坑。

## Phase 1：工程骨架与模块化

推荐按“可复用域”拆 HAR，而不是按页面拆：

```
entry/          主 HAP：页面、视图、服务编排、C++ 推理
commons/        主题 token、日志、排序、通用 UI
coremodel/      RDB 实体、DAO、Repository
corenovel/      TXT/EPUB/ZIP-HTML 解析、章节、分页
coreocr/        Core Vision OCR 封装
corerender/     覆盖层几何、排版、渲染器
coretranslate/  翻译抽象、在线引擎、本地 llama
```

原则：
- 领域模块不依赖 entry；entry 依赖全部 core*；
- 跨模块只暴露 `Index.ets`，不要深路径 import；
- 模型/数据库/网络等副作用放在 service，不放进 UI 组件；
- 统一错误类型与用户可读提示，UI 不直接显示底层异常。

### ArkTS 常见坑

- ArkTS 不是 TypeScript：不能用 `any` 大法、动态属性、部分 Node API；
- 状态管理 V1 中 `@State/@Prop/@Link/@Provide/@Consume` 的层级要清晰；跨页用 AppStorage/持久化；
- `@Builder` 内不要写复杂副作用；
- 列表必须给稳定 `key`；
- `aboutToAppear` 不能做长耗时同步任务；
- 动画用 `animateTo` 时注意 API 26 的弃用警告，逐步迁移到新接口；
- 自定义组件参数变化不会自动深拷贝，必要时重建 key。

通过门槛：
```bash
devecocli build --modules entry --build-mode debug
```
BUILD SUCCESSFUL，且空壳能启动、能截图。

## Phase 2：多端 UI 与沉浸光感

### 断点
不要按“手机/平板”写死，按窗口宽度：
- 窄屏：底部 Tab；
- 中/宽屏：左侧导航轨 + 内容双列/双页；
- 2in1：可拖拽窗口，必须监听窗口尺寸变化，而不是只读一次。

### 全屏铺满
常见问题：顶部标题被状态栏裁切、底部出现白条。

正确顺序：
1. `setWindowLayoutFullScreen(true)`；
2. 通过 `window.getLastWindow` + `AvoidAreaType.TYPE_SYSTEM` 读取状态栏高度；
3. 页面顶部加动态 padding（不要写死 24/48）；
4. Tab 栏 `barBottomMargin: 0`，不要额外加安全区高度；
5. 在横竖屏/分屏切换时重新测量。

### 沉浸光感
API 26 使用：
```ts
uiMaterial.ImmersiveMaterial({
  style: uiMaterial.MaterialStyle.ULTRA_THIN,
  interactive: true,
  lightEffect: {}
})
```
不要自己拿半透明色 + blur 拼，容易在深色/浅色/图片背景上脏。材质要加在：底部 Tab、标题栏、Slider/Toggle 等控件容器；不是给每个文字加。

### 主题
- 用 Token（颜色/圆角/间距/字号）集中管理；
- 默认蓝白，夜间蓝黑；不要保留紫色残留；
- 旧主题值要做迁移映射，避免升级后变透明/黑块；
- 切换主题要重建 shell，避免局部组件不刷新。

### 动画
- 页面切换 250–350ms，缓动统一；
- Tabs 内容切换、阅读器进入/退出、覆盖层出现都要有过渡；
- 动画期间不要触发重排/重新 OCR。

通过门槛：三端截图各一张，顶部不裁切、底部无空白、横竖屏切换不崩。

## Phase 3：数据与导入

- 文件导入用系统文件选择器，不要申请受限 ACL 权限；
- 大文件复制到沙箱目录，记录 URI 失效问题；
- 漫画支持 zip/cbz/图片目录；小说支持 txt/epub/zip-html；
- 解析放 Worker，避免主线程卡死；
- 阅读进度、书架、设置用 RDB/Preferences 持久化；
- 卸载/换签名会清数据，交付前提醒用户导出。

## Phase 4：OCR（系统 + 本地）

### 系统 OCR
- Core Vision Kit 首次调用可能冷启动 30s+；
- App 启动后预热一次，不要等用户点 OCR 才加载；
- 识别后做版面分析：行/段/气泡，不要逐字排版；
- 文字方向按检测框宽高逐块判断：横宽→横排，竖长→竖排；不要全页强制竖排；
- 覆盖层白块要按图片像素边界裁剪，不能超出画布。

### 本地 OCR（PP-OCRv6 + ONNX Runtime）
- 依赖：`@ohos/onnxruntime`；`@ohos/aki` 必须显式 override 到兼容版本（本项目 1.2.26），否则编译/运行会炸；
- det/rec 两个模型都要下，缺一不可；
- 输入预处理：resize/归一化/CHW；输出做 DB 后处理；
- 模型放沙箱 models 目录，下载用 `.part` 临时文件，完成后原子改名；
- 下载源要国内可达：本项目 det 走 jsDelivr，rec 走 gh-proxy；raw.githubusercontent 在真机可能超时；
- 下载完成必须刷新 UI 档位，否则用户以为没生效；
- 首次推理慢是正常的，记录冷/热数据。

详细实现见 [references/ocr-and-models.md](references/ocr-and-models.md)。

## Phase 5：翻译与性能

### 抽象
统一 `Translator` 接口，UI 不关心引擎：
- 在线：必应/OpenAI 兼容（DeepSeek、Kimi、硅基流动、混元、MiniMax、智谱等）；
- 本地：llama.cpp + GGUF（Hy-MT2 Q4 等）；
- 失败降级：在线失败提示 + 可切本地；本地失败提示下载模型。

### 性能
- 单页文本行 4 路并发（网络引擎）；本地 llama 串行（1 路），否则抢 CPU/显存；
- 预翻译默认关闭，避免首屏抢网络；
- 整本翻译要可暂停/继续，分页/分章入队；
- 目标：单页 OCR+翻译 < 10s；本项目实测系统 OCR 约 3s、本地 OCR 约 6s；
- 覆盖层排版做缓存，避免重复计算。

### 模型下载
- HuggingFace 在国内可能不可达；GGUF 改 ModelScope 镜像（本项目实测 21.9MB/s）；
- 下载要显示进度/速度/暂停/继续/删除；
- 存储统计要同时算 models 与 cache 分片，且 `mkdirSync` 前先 `accessSync`，否则 EEXIST 会让统计变 0。

详细见 [references/translation-and-performance.md](references/translation-and-performance.md)。

## Phase 6：华为账号与云同步

### Account Kit
- AGC 创建应用，包名必须与 `bundleName` 完全一致；
- 开启「华为账号」开放能力；
- APP ID 与 Client ID 相同：**不需要** `client_id` metadata；不同才需要加到 entry 的 module.json5；
- 签名必须使用该 AGC 应用的调试/发布证书 + Profile；
- 证书 SHA-256 指纹要加到 AGC 应用，等约 10 分钟，并 bump versionCode；
- 错误 `1001502003 / Invalid clientId or profile` 本质是 AGC/签名/Profile 不匹配，不是代码错。

### 云同步
- 代码用 `@kit.CloudFoundationKit` 的 `cloudStorage.bucket()`；
- 必须先在 AGC 开通云存储实例（项目 → 云开发 Serverless → 云存储）；
- 未开通时上传返回 `404 Product does not exist`；
- AGC 可能提示「云开发服务停止新开发者接入」——这是外部政策阻塞，不是客户端 bug；
- 备选：已有云开发项目、申请白名单，或改用 WebDAV/自建对象存储。

详细见 [references/account-sign-cloud.md](references/account-sign-cloud.md)。

## Phase 7：签名、构建、部署

### 一次性打通
```bash
devecocli auth login --no-prompt
cd <project>
devecocli signature generate --force
devecocli build --modules entry --build-mode debug
```

### 换签名后
设备旧包证书不同会报：
```text
9568332 install sign info inconsistent
```
处理：
```bash
devecocli device app uninstall --device <serial> --bundle <bundle>
devecocli run --module entry --device <serial>
```
或在 DevEco：Project Structure 确认新签名 → Build → Clean → Rebuild → 运行。

### 常见工具坑
- `hdc` 不在 PATH：用 `devecocli device ...` 代替；
- 开发者模式下 CLI 不能自动解锁屏幕：先手动解锁；
- DevEco 的构建缓存可能仍是旧签名：Clean/Rebuild；
- 不要混用 CLI 与 IDE 两套旧产物。

## Phase 8：真机验收

必做：
1. `devecocli device list` 确认真机；
2. 构建、安装、启动；
3. 截图（书架、阅读、OCR 覆盖、翻译、我的、登录）；
4. 抓崩溃日志；
5. 记录冷/热启动、单页 OCR、翻译耗时、下载速度；
6. 更新 README/TESTING/CHANGELOG/AGC 文档。

```bash
devecocli run --module entry --device <serial> --uninstall
devecocli ui screenshot --device <serial> --path /tmp/app.png
devecocli log --device <serial> --bundle-name <bundle> --crash --tail 50
```

## 高频坑速查

| 现象 | 根因 | 处理 |
|---|---|---|
| 1001502003 Invalid clientId/profile | AGC 应用/证书/Profile 不匹配 | 确认包名、签名、指纹、Profile 同属一个应用 |
| 9568332 sign inconsistent | 设备旧包与当前 HAP 证书不同 | 卸载旧包；Clean/Rebuild |
| 9568276 install already exist | 同 versionCode 覆盖安装 | 卸载或 bump versionCode |
| 10106102 device screen locked | 开发者模式不能自动解锁 | 手动解锁后再跑 |
| 404 Product does not exist | 云存储实例未开通 | AGC 云开发→云存储开通；否则换后端 |
| OCR 首次 30s+ | Core Vision 冷启动 | 启动预热 |
| 模型目录 0 B | mkdir EEXIST / 只算一个目录 | access 检查 + 统计 models+cache |
| 下载卡住/超时 | raw.githubusercontent 被墙 | 换 jsDelivr/gh-proxy/ModelScope |
| 底部白条/顶部裁切 | 全屏安全区处理错误 | 动态状态栏 padding + Tab bottom 0 |
| 横排译文变竖排 | 全页强制方向 | 按检测框宽高逐块自动 |
| 真机安装旧包 | DevEco 缓存旧 HAP | Clean/Rebuild，统一签名 |
| 模拟器登录失败 | 模拟器无华为账号面板 | 用真机验证 |

完整清单见 [references/pitfalls.md](references/pitfalls.md)。

## 命令速查

```bash
# 设备
devecocli device list
devecocli device unlock --device <serial>
devecocli device wake --device <serial>

# 账号/签名
devecocli auth login --no-prompt
devecocli auth status
devecocli signature generate --force

# 构建/部署
devecocli build --modules entry --build-mode debug
devecocli run --module entry --device <serial> --uninstall
devecocli run --module entry --device <serial> --skip-build

# 截图/日志
devecocli ui screenshot --device <serial> --path /tmp/app.png
devecocli log --device <serial> --bundle-name <bundle> --crash --tail 50
```

## 交付定义（DoD）

- [ ] 换一台机器可按文档重新构建；
- [ ] 换设备可重新签名并安装；
- [ ] 手机/平板/2in1 截图通过；
- [ ] OCR/翻译有成功与失败路径；
- [ ] 华为账号真机已登录；
- [ ] 云同步要么通过，要么写明外部阻塞；
- [ ] README/TESTING/CHANGELOG/AGC 文档已更新；
- [ ] 仓库无 keystore、密码、Client Secret、个人账号信息；
- [ ] 推送提交，工作区干净。

## 参考文件

- [references/architecture.md](references/architecture.md)
- [references/ui-multidevice.md](references/ui-multidevice.md)
- [references/ocr-and-models.md](references/ocr-and-models.md)
- [references/translation-and-performance.md](references/translation-and-performance.md)
- [references/account-sign-cloud.md](references/account-sign-cloud.md)
- [references/testing-and-automation.md](references/testing-and-automation.md)
- [references/pitfalls.md](references/pitfalls.md)
- [references/case-study-starflow.md](references/case-study-starflow.md)
- [scripts/doctor.sh](scripts/doctor.sh)

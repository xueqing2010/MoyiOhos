# DevEco 官方内置 Skills 索引

DevEco 通过 `devecocli skills` 提供 49 个官方 HarmonyOS Skills。本项目已安装其中最相关的 30 个到 `~/.dsh/skills/`，可直接用 `skill` 工具按名称加载。

## 加载顺序（写代码前）

1. **写第一个 .ets 前**：`hmos-arkui-develop-skill`（ArkTS/ArkUI 致命约束、API 查表）；
2. **写任何 @kit.* import 前**：`hmos-one-sdk-skill`（25 个 Kit 的签名/错误码/权限）；
3. **构建报错**：`hmos-arkts-syntax-checker`；
4. **多设备/全屏/安全区/旋转**：先 `hmos-multidevice-scenario-entry`，再按需加载 screen-window-size / avoid-areas / natural-orientation；
5. **华为账号**：按按钮形态选 login-button / login-api / quicklogin；
6. **AGC/证书/上架/构建**：`hmos-connect-api-cli-skill`；
7. **测试**：`hmos-local-test` / `hmos-instrument-test`；
8. **崩溃/卡死/内存**：jscrash / appfreeze / memleak / apifault；
9. **动效/悬浮窗**：longtake-transition / arkuikit-window-floatwindow；
10. **架构/迁移**：arkui-mvvm-pattern / statemgt-migration。

## 已安装清单（30）

| Skill | 何时用 |
|---|---|
| hmos-arkui-develop-skill | 写/改 .ets，ArkTS 语法、组件、状态、布局、动画 |
| hmos-arkts-syntax-checker | 编译失败、循环修复、定位 HAP/App 产物 |
| hmos-arkts-knowledge-retriever | 查 ArkTS 语言/API 文档 |
| hmos-arkts-deprecated-interface-checker | 清废弃 API、升级 API |
| hmos-arkui-mvvm-pattern | 分层、ViewModel、重构 |
| hmos-arkui-statemgt-migration | V1→V2 状态迁移 |
| hmos-multidevice-scenario-entry | 多设备适配总入口/路由 |
| hmos-multidevice-screen-window-size | 断点、GridRow/GridCol、分栏、窗口尺寸 |
| hmos-multidevice-avoid-areas | 状态栏/导航栏/刘海/键盘避让、沉浸全屏 |
| hmos-multidevice-natural-orientation | 旋转、方向策略、折叠屏方向 |
| hmos-multidevice-interaction-methods | 触摸/鼠标/键盘/手写笔/悬停 |
| hmos-multidevice-fold-state | 折叠态、悬停态、折痕 |
| hmos-multidevice-hardware-access | 相机/SysCap/硬件降级 |
| hmos-window-smart-orientation | 智感旋转、18 种 Orientation |
| hmos-account-kit-login-api-client | 自定义华为登录按钮 + Authorization Code |
| hmos-account-kit-login-button-client | 标准华为登录按钮 + 协议页 |
| hmos-account-kit-quicklogin-client | 一键登录/匿名手机号 |
| hmos-connect-api-cli-skill | AGC 登录、创建应用、上传、证书/Profile、ACL |
| hmos-one-sdk-skill | @kit.* API 签名/错误码/权限（25 Kit） |
| hmos-local-test | ArkTS/JS 单元测试、覆盖率 |
| hmos-instrument-test | Instrument Test、ASan |
| hmos-apifault-analysis | 错误码/日志根因诊断 |
| hmos-jscrash-analysis | JS Crash / faultlogger / SourceMap |
| hmos-appfreeze-analysis | Freeze/卡死/ANR 日志 |
| hmos-memleak-analysis | ArkTS/JS/C++ 静态内存泄漏 |
| hmos-arkui-longtake-transition | 一镜到底、Navigation 转场 |
| hmos-arkui-kit-window-floatwindow | PiP/闪控窗/悬浮球 |
| hmos-design-visual-mobile | HarmonyOS 移动端视觉还原 |
| hmos-runtime-fix-skill | 运行时崩溃/白屏/启动失败 |
| app-metadata-audit-skill | AGC 上架元数据合规审查 |

其余 19 个（Scan Kit、Map Kit、Push Kit、LiveView、支付、ASCF、Ads、app continuity 等）可按需安装：

```bash
devecocli skills list
devecocli skills add --path ~/.dsh/skills --skill <name> --force
```

## 与本 skill 的分工

- **官方 skill**：具体 API 签名、错误码、官方规范、DFX 诊断流程；
- **本 skill**：StarFlow 实战顺序、模块拆分、OCR/翻译/本地模型、AGC 踩坑、真机验收与提效命令。

写代码时优先让官方 skill 提供“准确签名”，本 skill 提供“工程落地顺序和坑”。

## 重要提醒

- `hmos-arkui-develop-skill` 的 quick-apis/quick-rules 是**按需 Grep**，不要整读大文件；
- `hmos-one-sdk-skill` 必须在写 @kit.* import 前加载，避免命名空间/导出成员错误；
- 官方 skill 也有版本差异，遇到冲突以**当前 SDK/编译器报错**为准；
- 不要把官方 skill 的整棵 references 复制进项目，安装到用户级目录即可。

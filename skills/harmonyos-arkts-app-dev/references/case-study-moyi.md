# 案例复盘：墨译 Moyi（HarmonyOS）

## 1. 项目背景

- 上游：Android「StarFlow（星译）」，LGPL-3.0。
- 目标：HarmonyOS NEXT 上以 ArkTS 独立实现，功能对齐，适配 Phone/Tablet/2in1。
- 设备：PCE-W30 真机（API 26，2880×1920），Mate 90 Pro / MatePad Pro 13 模拟器。
- 工具：DevEco Studio 6、devecocli、API 26 SDK。

## 2. 架构选择

7 个模块：entry + commons + coremodel + corenovel + coreocr + corerender + coretranslate。

为什么拆：
- OCR/翻译/渲染/解析可独立测试；
- 换 OCR 实现（系统→ONNX）不污染页面；
- 上游功能多，单模块会失控。

代价：
- HAR 改动需要 clean；
- 跨模块类型要导出；
- 早期部分逻辑仍在 entry，后续再迁。

## 3. 关键决策时间线

1. 先系统 OCR 上线：Core Vision 快速可用，但首调 36s。
2. 启动预热：EntryAbility 延迟预热，单页降到约 3s。
3. 本地 OCR Plan B：ONNX Runtime + PP-OCRv6，det/rec 自动下载，离线约 6s/页。
4. 翻译抽象：必应 + OpenAI 兼容 + 本地 llama。
5. 性能：网络 4 路并发，本地 1 路；预翻译默认关闭；目标 <10s。
6. UI 重做：紫→蓝白，底部沉浸 Tab，平板左 rail，全屏铺满。
7. 多端修复：动态状态栏 padding、Tab bottom 0、自动横竖排。
8. 账号/签名：AGC 应用、CLI 登录、自动签名、真机登录。
9. 云同步：CloudFoundationKit 代码完成，但 AGC 云存储未开通，404 阻塞。

## 4. 实测数据

| 项目 | 数据 |
|---|---|
| 系统 OCR 首调 | ~36s |
| 系统 OCR 预热后单页 | ~3s |
| 本地 OCR | det 1791ms、rec 2580ms、总 ~6s |
| 单页翻译 | 约 3.2s（4 路） |
| GGUF 下载 | ModelScope 21.9MB/s |
| 模型占用 | 284.9MB（含 cache） |
| HAP | 约 114–120MB |
| Tab 动画 | 320ms |
| 构建 | clean 约数分钟；增量 1–3s |

## 5. 踩过的主要坑

### 5.1 OCR 冷启动
现象：首次点 OCR 等 30s+。
修复：启动后台预热；用户点之前已完成初始化。

### 5.2 raw.githubusercontent 在真机不可达
现象：rec 模型下载卡住/超时。
修复：det 改 jsDelivr，rec 改 gh-proxy；GGUF 改 ModelScope。

### 5.3 模型目录 0B
现象：下载完成仍显示 0。
修复：mkdirSync 前 accessSync；统计 models + cache 两个目录。

### 5.4 全屏顶部裁切/底部白条
现象：标题被状态栏遮，底部空一条。
修复：动态读 AvoidArea top；Tab barBottomMargin 0。

### 5.5 横排漫画译文被竖排
现象：字距巨大。
修复：按每个检测框 w/h 自动选择横/竖，不再全页强制。

### 5.6 华为账号 1001502003
现象：Invalid clientId or profile。
根因：AGC 应用/证书/Profile/指纹不匹配。
修复：创建 AGC 应用、开 Account Kit、CLI 生成签名、真机登录通过。

### 5.7 自动签名卡住
现象：DevEco 自动签名转圈。
根因：受限 ACL FILE_ACCESS_PERSIST 阻塞。
修复：移除权限（文件导入走系统 picker），CLI 生成签名。

### 5.8 9568332 安装签名不一致
现象：换签名后 DevEco 部署失败。
修复：卸载旧包；Clean/Rebuild；统一 CLI/IDE 签名。

### 5.9 云同步 404
现象：备份返回 404 Product does not exist。
根因：AGC 云存储实例未开通；且 AGC 提示云开发停止新开发者接入。
结论：客户端代码不是根因；需要白名单/已有项目/换后端。

## 6. 做对了什么

- 先用 CLI 把构建-签名-安装-启动闭环跑通，再回到 GUI；
- 每个性能问题都记录数字，不靠感觉；
- 所有外部依赖都有镜像/降级；
- UI 先做三端断点，再补动画；
- 文档与截图随代码提交，换机能复现。

## 7. 可以做得更好

- 更早引入 UI 截图回归；
- 更早把 OCR/翻译服务从 entry 拆出；
- 滚动/分页压力测试不足；
- 2in1 真机回归不足；
- 云同步应提前确认 AGC 政策，而不是写完才发现不能开通。

## 8. 一句话总结

先闭环、再优化；签名先行、真机为准；外部依赖必须有镜像和降级；每个坑都留下错误码、根因和可复现命令。

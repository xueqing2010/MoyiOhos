# OCR 与本地模型

## 1. 两条 OCR 路线

| 路线 | 适用 | 优点 | 缺点 |
|---|---|---|---|
| Core Vision Kit（系统 OCR） | 快速上线、真机 | 无需模型、准确率高 | 首次冷启动 30s+，可定制性弱 |
| PP-OCRv6 + ONNX Runtime | 离线、可控 | 无系统依赖、可调参 | 需下载模型、首推理慢、内存高 |

推荐：系统 OCR 做默认，本地 OCR 做离线/隐私档位；启动预热系统 OCR。

## 2. Core Vision 接入

- 使用 `@kit.CoreVisionKit` 的 text recognition；
- 输入 PixelMap，输出文字块 + 四角坐标；
- 首次调用初始化耗时很长，App 启动后后台预热一次；
- 识别结果不要直接当“行”：要做版面/气泡合并；
- 失败/无文字要返回空结果，不要抛到 UI。

预热思路：

```ts
// EntryAbility.onWindowStageCreate 之后，延迟 1s 触发，不阻塞首帧
setTimeout(() => {
  OcrService.prewarm().catch(() => {});
}, 1000);
```

## 3. 本地 PP-OCRv6

### 依赖
- `@ohos/onnxruntime`；
- `@ohos/aki`：版本必须与 ORT 兼容，本项目在根 `oh-package.json5` 显式 override `1.2.26`；
- native .so 同时支持 arm64-v8a / x86_64。

### 模型
- det：文本检测，输出概率图，做 DB 后处理得到四边形；
- rec：文字识别，输入裁剪图，CTCLoss 解码；
- 两个模型缺一不可；设置页点任意一个模型下载，应自动串行下载 det+rec，再切到 local 档位。

### 预处理
- det：等比 resize 到 32 的倍数，归一化 mean/std，CHW；
- rec：高度 48，宽度按比例，最多 320/640，归一化；
- 输入 tensor 名称/维度从模型 metadata 读，不要写死。

### 后处理
- det：阈值 → 连通域/轮廓 → 最小外接矩形 → 透视变换裁剪；
- rec：argmax → 去 blank → 去重复 → 字表映射；
- 结果按阅读顺序排序（先上后下，先左后右）；
- 过滤太小的框和低置信度，避免噪点覆盖。

### 性能
- 首次 session 创建 + 推理 5–10s 正常；
- 预热后单页 det 约 1.8s、rec 约 2.6s（中端平板实测）；
- 多页并发不要超过 2，内存会爆；
- 推理放 Worker/TaskPool，UI 线程只接收结果。

## 4. 模型下载

### 源
- 国内真机优先 jsDelivr / gh-proxy / ModelScope；
- `raw.githubusercontent.com` 在部分网络会超时；
- 不要把模型打进 HAP（体积大、许可复杂），首次使用下载。

已知可用（以项目代码为准）：
- det：`https://cdn.jsdelivr.net/gh/xujunjiex/Moyi@master/app/src/main/assets/ppocrv6/det_v6_small.onnx`
- rec：`https://gh-proxy.com/https://raw.githubusercontent.com/xujunjiex/Moyi/master/app/src/main/assets/ppocrv6/rec_v6_small.onnx`

### 下载器
- 下载到 `cacheDir/downloads/*.part`；
- 完成后校验大小/可选哈希，再 rename 到 `filesDir/models/`；
- 支持暂停/继续/删除；
- 并发下载不要太多，避免弱网互相抢；
- UI 显示已下载/总大小、速度、剩余时间；
- 下载完成刷新设置页档位，不需要用户重启。

### 存储统计
坑：`fs.mkdirSync(dir, true)` 在目录存在时会抛 EEXIST，导致捕获后显示 0 B。
正确：

```ts
if (!fs.accessSync(dir)) {
  fs.mkdirSync(dir, true);
}
```

统计要同时算 `modelsDir()` 与 `cacheModelsDir()`，否则下载完成后仍显示 0。

## 5. 覆盖层渲染

- 译文白块按原图坐标映射到屏幕，不要用固定字号；
- 裁剪到图片边界与页面边界，防止越界；
- 文字方向：按每个检测框的宽高判断：
  - `w >= h` → 横排；
  - `h > w` → 竖排；
  - 不要全页强制竖排/横排；
- 字号自适应：先按框宽算，超长再缩；
- 行距/字距按语言调整，日文转中文不要保留日文字距；
- 阅读态/对照态切换不要重新 OCR。

## 6. 常见错误

| 现象 | 原因 | 处理 |
|---|---|---|
| 首次 OCR 30s+ | Core Vision 冷启动 | 启动预热 |
| 本地 OCR 输出乱码 | rec 字表不对/输入归一化错 | 对齐字典与预处理 |
| 检测框为 0 | det 阈值/输入尺寸错 | 打印输出 shape，调阈值 |
| 覆盖层越界 | 坐标未裁剪 | 限制在图片 rect 内 |
| 竖排漫画字距大 | 全页强制竖排 | 按框宽高自动 |
| 模型下载失败 | raw.githubusercontent 超时 | 换 jsDelivr/gh-proxy |
| 模型目录 0B | mkdir EEXIST / 只统计一个目录 | access 检查 + 双目录统计 |
| 设置页下载后仍显示未下载 | 未刷新档位/未重新读配置 | 下载完成回调刷新 |

## 7. 隐私与许可

- 图片/文本默认不上传；本地 OCR/本地翻译要明确标注；
- 模型许可归发布方，不随仓库分发；
- 不要打印用户图片内容、书籍正文、API Key。

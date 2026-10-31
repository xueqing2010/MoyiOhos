# OCR 模型来源与许可（墨译）

> 更新：2026-10-31
> 结论：应用内 OCR 已切换为 **PaddlePaddle 官方 PP-OCRv6 small ONNX**，不再从上游 StarFlow / MoeTranslate 仓库下载模型。

## 1. 上游模型来源

原先 OcrModelService 从：

~~~text
https://cdn.jsdelivr.net/gh/xujunjiex/StarFlow@master/app/src/main/assets/ppocrv6/det_v6_small.onnx
https://gh-proxy.com/https://raw.githubusercontent.com/xujunjiex/StarFlow/master/app/src/main/assets/ppocrv6/rec_v6_small.onnx
~~~

下载。

- xujunjiex/StarFlow 是 **murangogo/MoeTranslate（萌译）** 的 fork；
- MoeTranslate 为 Android 开源项目，LGPL-3.0；
- 该仓库把 PP-OCRv6 模型放在 app/src/main/assets/ppocrv6；
- 上游仓库未单独给出模型文件许可证；为避免把“上游仓库的模型文件”当作可再分发资产，本项目不再引用该地址。

## 2. 官方来源

PP-OCRv6 是 **PaddlePaddle / 百度飞桨** 的官方 OCR 模型族，官方 ONNX 模型卡：

| 模型 | 官方地址 | 许可证 |
|---|---|---|
| det small | https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx | Apache-2.0 |
| rec small | https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx | Apache-2.0 |

模型卡首行即：

~~~yaml
license: apache-2.0
library_name: PaddleOCR
~~~

应用内使用国内镜像：

~~~text
https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx
https://hf-mirror.com/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx
~~~

## 3. 已做的验证

在 Mate 90 Pro 模拟器完成：

- 从官方镜像下载 det（9.4MB）与 rec（20.2MB）；
- 本地原生 ONNX Runtime det+rec 运行成功；
- 合成漫画页识别 **6 行，0 失败**；
- 单页 OCR 约 **429ms**（原生 det+rec，6 行）。

## 4. 字典

entry/src/main/resources/rawfile/ppocrv6_dict.txt 与 PaddleOCR 官方：

~~~text
https://github.com/PaddlePaddle/PaddleOCR/blob/main/ppocr/utils/dict/ppocrv6_dict.txt
~~~

**SHA-256 完全一致**：

~~~text
b5f2bfe2bdd9448429e3e82b51c789775d9b42f2403d082b00662eb77e401c5d
~~~

因此字典也属于 PaddleOCR 官方文件（Apache-2.0），不是上游 StarFlow 私有资产。

## 5. 是否迁入本仓库

当前**不把 30MB 模型二进制提交进仓库**，原因：

- 官方源可稳定下载，避免仓库膨胀；
- 使用官方 HF 地址，许可链更清晰；
- 应用仍保留“用户按需下载”策略，不随安装包分发。

如果后续需要完全离线或官方镜像不可用，可在取得 Apache-2.0 合规声明后，将 inference.onnx 重命名放入：

~~~text
models/ppocrv6/ppocrv6_det_official.onnx
models/ppocrv6/ppocrv6_rec_official.onnx
~~~

并同步修改 OcrModelService 的两个 URL；当前不这样做。

## 6. 结论

- 上游：xujunjiex/StarFlow / murangogo/MoeTranslate，个人开源项目；
- 官方：PaddlePaddle / 百度飞桨，Apache-2.0；
- 本项目：使用官方地址，不再依赖上游模型文件；
- 字典：与 PaddleOCR 官方字典哈希一致；
- 软著材料：模型权重不计入申请人原创范围，模型加载/推理代码属于软件作品。

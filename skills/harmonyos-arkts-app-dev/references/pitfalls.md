# 全量坑位清单

> 按“现象 → 根因 → 修复”记录。带 * 的是本项目实际踩过并有提交记录的。

## A. 构建 / 签名

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| A1* | `9568276 install already exist` | 同 versionCode 覆盖安装 | 卸载，或 bump versionCode |
| A2* | `9568332 install sign info inconsistent` | 设备旧包与当前 HAP 证书不同 | 卸载旧包；Clean/Rebuild；统一签名 |
| A3* | DevEco 自动签名一直转圈 | 受限 ACL 权限 `FILE_ACCESS_PERSIST` 阻塞 | 移除权限或改用 `devecocli signature generate` |
| A4* | `devecocli signature generate` 提示未登录 | CLI 未登录 | `devecocli auth login --no-prompt` |
| A5* | 自动签名生成后 build-profile 仍指向旧证书 | IDE 缓存/根配置被覆盖 | 核对 `signingConfigs.material` 路径；clean |
| A6* | 真机安装成功但启动报 10106102 | 屏幕锁定，开发者模式不能自动解锁 | 手动解锁；`device unlock` 仅辅助 |
| A7* | 安装旧包后登录失效 | 旧签名 Profile 不匹配 AGC | 用新 Profile 重装，卸载旧包 |
| A8 | clean 后仍用旧 .so | 原生库缓存 | 删除 `entry/build`、`.hvigor`，重新构建 |
| A9 | `hdc: command not found` | SDK 路径未进 PATH | 用 `devecocli device ...` 或配置 SDK 环境 |
| A10 | 模拟器安装失败 | ABI 不含 x86_64 | 同时打包 arm64-v8a/x86_64 |

## B. ArkTS / 运行时

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| B1 | 编译报 `any`/动态属性 | ArkTS 限制 | 用明确类型/Record/类 |
| B2 | 页面返回后定时器还在跑 | 未清理 | `aboutToDisappear` 清理 |
| B3 | 列表滚动错位 | key 不稳定 | 用唯一 id 作 key |
| B4* | 启动白屏/首帧慢 | 启动做重活（OCR/模型） | 放后台，延迟预热 |
| B5 | 状态不刷新 | 嵌套对象未触发观察 | 拆字段/重建 key |
| B6* | 主题切换局部不更新 | shell 缓存 | 切换后重建 shell |
| B7 | 大图 OOM | 整本 decode | 只解码当前/前后页 |
| B8 | 并发请求旧结果覆盖新页 | 无任务取消 | 用 pageId/seq 丢弃旧结果 |

## C. UI / 多端

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| C1* | 顶部标题被状态栏裁切 | 全屏后没加动态 padding | 读取 AvoidArea top，动态 padding |
| C2* | 底部白条 | Tab 同时加安全区和 margin | `barBottomMargin: 0`，只留一处 |
| C3* | 平板仍显示手机底部 Tab | 只按设备类型判断 | 按窗口宽度断点 |
| C4* | 2in1 拖拽后布局错 | 只测一次宽度 | 监听 windowSizeChange |
| C5* | 沉浸材质发灰/脏 | 自己用半透明+blur 模拟 | 用 `uiMaterial.ImmersiveMaterial` |
| C6* | 夜间模式文字看不清 | 只换背景没换文字 token | 主题 token 全量切换 |
| C7 | 字体放大按钮截断 | 固定高度 | 自适应高度/最大行数 |
| C8 | 动画掉帧 | 动画中重排/OCR | 动画期间冻结重活 |

## D. OCR / 模型

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| D1* | 首次 OCR 36s | Core Vision 冷启动 | 启动预热 |
| D2* | 本地 OCR 6s/页 | 模型首推理/串行 | 预热 session，控制并发 |
| D3* | 译文白块越界 | 未按图片 rect 裁剪 | 限制在画布内 |
| D4* | 横排漫画译文变竖排 | 全页强制竖排 | 按检测框 w/h 逐块判断 |
| D5* | 模型目录显示 0B | mkdir EEXIST + 只统计一个目录 | access 检查 + models/cache 双统计 |
| D6* | 设置页下载后仍显示未下载 | 未刷新档位 | 下载完成回调刷新 tier |
| D7* | 下载超时/卡住 | raw.githubusercontent 被墙 | jsDelivr/gh-proxy/ModelScope |
| D8 | 本地 OCR 乱码 | 字典/归一化/CHW 错 | 对齐模型预处理与字表 |
| D9 | det 输出空 | 阈值/输入尺寸错 | 打印 shape，调阈值 |
| D10 | 内存暴涨 | 每页新建 session | 复用 + 释放 |
| D11 | 模型下载一半损坏 | 无 .part/校验 | 临时文件 + 大小/哈希校验 |

## E. 翻译 / 性能

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| E1* | 单页翻译慢 | 本地 llama 多路并发 | 本地 1 路，网络 4 路 |
| E2* | 首屏卡 | 预翻译默认开 | 默认关闭 |
| E3* | GGUF 下载慢 | HuggingFace 不可达 | ModelScope 镜像 |
| E4 | 429 | 并发过高 | 降并发 + 退避 |
| E5 | 译文为空 | 响应结构差异 | 兼容 choices/message/content |
| E6 | 长文超 context | 未分段 | 按段切分 + 摘要 |
| E7 | 旧结果覆盖新页 | 无取消 | 任务 id/页码校验 |
| E8 | 整本翻译无法暂停 | 未做队列状态 | 分页队列 + pause/resume |

## F. 华为账号 / 云

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| F1* | 1001502003 Invalid clientId/profile | AGC/证书/Profile 不匹配 | 四者统一；重签 |
| F2* | 真机登录页拉起但无回调 | 签名/指纹/回调不匹配 | 检查 AGC 配置与指纹 |
| F3* | 云备份 404 Product does not exist | 云存储实例未开通 | AGC 云开发→云存储开通 |
| F4* | AGC 提示云开发停止新开发者接入 | 外部政策 | 申请白名单/已有项目/换后端 |
| F5 | 模拟器登录失败 | 无华为账号面板 | 用真机 |
| F6 | 换证书后登录失效 | 旧安装包/旧 Profile | 卸载重装 + bump versionCode |
| F7 | Client ID 配置不生效 | 加到错误模块/项目级 | 只加 entry module metadata |

## G. 测试 / 自动化

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| G1* | DevEco 控制台是旧错误 | 日志未清/未重新跑 | 看时间戳；重新运行 |
| G2* | CUA element_token stale | 快照过期 | 每次操作前重新 get_window_state |
| G3* | 背景点击无效 | 模态窗口/焦点 | foreground 或 AppleScript |
| G4* | 坐标点偏 | 截图缩放 | 按比例换算 |
| G5 | 设备自动锁屏 | 超时短 | 设置 sleeptime 30min |
| G6 | 截图全黑 | 屏幕熄灭/锁屏 | wake + unlock + 截图 |
| G7 | 日志无崩溃 | 应用已退出 | 先复现，再抓 crash |

## H. 文档 / 安全

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| H1* | README 说签名已清空但实际已配置 | 文档滞后 | 及时更新 |
| H2* | 文档包含 Client Secret/账号 | 截图未脱敏 | 删除/打码 |
| H3 | 模型/字体许可缺失 | 未记录 | NOTICE/THIRD_PARTY |
| H4 | 上游 LGPL 归属丢失 | 直接搬代码 | 保留 LICENSE/归属说明 |
| H5 | 截图太大 | 未压缩 | jpg 85 + 限制长边 |

## 最后检查

- 任何“配置类”错误，先判断是**代码**还是**账号/签名/AGC/网络**；
- 任何“装不上”，先看错误码，不要重装十次；
- 任何“慢”，先量冷/热、并发、模型加载；
- 任何“UI 错位”，先查安全区/断点/材质层，而不是调 padding 猜。

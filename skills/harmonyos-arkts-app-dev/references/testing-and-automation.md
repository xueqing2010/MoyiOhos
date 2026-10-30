# 构建、真机测试与自动化

## 1. 工具选择

优先 `devecocli`，不要到处找 `hdc`：

| 任务 | 命令 |
|---|---|
| 列设备 | `devecocli device list` |
| 唤醒/解锁 | `devecocli device wake/unlock --device <serial>` |
| 截屏 | `devecocli ui screenshot --device <serial> --path /tmp/x.png` |
| 点击/滑动 | `devecocli ui click/swipe ...` |
| 日志 | `devecocli log --device <serial> --bundle-name <bundle> --crash --tail 50` |
| 安装启动 | `devecocli run --module entry --device <serial>` |
| 仅部署 | `devecocli run ... --skip-build` |
| 卸载重装 | `devecocli run ... --uninstall` |

## 2. 构建

```bash
cd <project>
devecocli build --modules entry --build-mode debug
```

产物：
`entry/build/default/outputs/default/entry-default-signed.hap`

失败时：
1. 看最后 80 行；
2. 是否签名/ACL/依赖；
3. 清理 `entry/build` 与 `.hvigor` 缓存；
4. 重新 `ohpm install`。

## 3. 真机准备

- 开发者模式 + USB 调试；
- 屏幕解锁（开发者模式下 CLI 不能自动解锁）；
- 设置屏幕超时足够长：
  `devecocli device screen sleeptime --device <serial> 1800000`
- 确认设备在 `devecocli device list` 中；
- 首次安装可能需在设备上确认。

## 4. 安装失败排查

| 错误 | 处理 |
|---|---|
| 9568276 install already exist | 卸载或 bump versionCode |
| 9568332 sign inconsistent | 卸载旧包；统一签名 |
| 10106102 screen locked | 手动解锁 |
| 安装超时 | 重新插拔/重启 hdc/设备 |

换签名后必须卸载一次，否则永远 9568332。

## 5. 截图验收

```bash
devecocli ui screenshot --device <serial> --path /tmp/app.png
```

检查：
- 顶部无裁切；
- 底部无白条；
- 文字不被 Tab 遮挡；
- 深浅色都正常；
- 平板双列不错位；
- OCR 覆盖层不越界。

不要只信“启动成功”，要打开关键页面逐页截图。

## 6. 日志

```bash
devecocli log --device <serial> --bundle-name com.example.app --crash --tail 80
devecocli log --device <serial> --level E --tail 100
```

关键 tag：
- OCR/Translate/Cloud/Account；
- 不要打印正文/图片/Key。

## 7. CUA/桌面自动化坑

- Safari/DevEco 的 AX 树可能几千节点，会被截断；
- element_token 会因新快照失效，每次操作前重新快照；
- 背景点击可能不生效，模态框用 foreground/AppleScript；
- 像素坐标要按截图缩放换算；
- 菜单项优先用 AppleScript `click menu item`，比盲点稳；
- 对话框可能不在 AX 树（webview），用坐标或键盘；
- 不要用 CUA 做大批量文件编辑，直接 CLI/写文件。

## 8. 测试矩阵

至少：

| 设备 | 场景 |
|---|---|
| 手机模拟器 | 首次启动、导入、阅读、翻译、设置 |
| 平板模拟器 | 双列布局、左 rail、全屏 |
| 真机平板 | 系统 OCR、本地 OCR、账号、分享、云同步 |
| 2in1（可用时） | 窗口拖拽、窄/宽断点 |

## 9. 性能记录模板

```
设备/版本：
冷启动首帧：
系统 OCR 首调/预热后：
本地 OCR det/rec/总：
单页翻译：
整本 N 页耗时：
模型下载速度：
内存峰值：
```

## 10. 发布前

- [ ] clean build 成功
- [ ] 真机安装启动
- [ ] 登录/云同步验证
- [ ] 崩溃日志为空
- [ ] 截图更新
- [ ] README/TESTING/CHANGELOG 更新
- [ ] 仓库无密钥/签名材料
- [ ] git push

## 11. 自动化脚本

参见 [../scripts/doctor.sh](../scripts/doctor.sh)：检查工具、设备、签名、权限、构建产物。

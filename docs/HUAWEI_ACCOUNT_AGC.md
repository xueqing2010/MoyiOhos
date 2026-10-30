# 华为账号登录 / AGC 配置指南

本文针对本仓库当前真机报错：

```
Invalid input parameter value. Invalid clientId or profile.
```

该报错来自华为账号服务（Account Kit），对应错误码 **1001502003**。它通常不是代码逻辑问题，而是 **AGC 应用未配置 Client ID / 未使用对应签名 Profile**。

## 0. 需要准备的材料

| 材料 | 获取位置 |
|---|---|
| AGC 项目 | AppGallery Connect → 我的项目 |
| AGC 应用（包名必须为 `com.moe.starflow`） | 项目 → 添加应用 |
| APP ID / Client ID | AGC → 项目 → 常规 → 应用 |
| 调试/发布证书（.p12） | AGC → 证书、APP ID 和 Profile → 证书管理 |
| 调试/发布 Profile（.p7b） | AGC → 证书、APP ID 和 Profile → Profile 管理 |
| 签名证书 SHA-256 指纹 | DevEco Studio 自动签名或 keytool 导出 |

> 当前仓库不包含签名材料；`build-profile.json5` 的 signingConfigs 已清空。真实登录必须先把签名配置补回来。

## 1. 在 AGC 创建项目与应用

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)。
2. 新建项目，再在项目下 **添加应用**：
   - 平台选择 **HarmonyOS**；
   - 包名填写 **`com.moe.starflow`**（必须与 `AppScope/app.json5` 完全一致）；
   - 应用分类按实际上架分类选择。
3. 在 **常规 → 应用** 中记录：
   - **APP ID**
   - **Client ID**
4. 在 **开放能力** 中开通：
   - **Account Kit（华为账号）**
   - **Cloud Foundation Kit（云存储）**（需要云同步时）

## 2. 配置 Client ID

打开：

`entry/src/main/module.json5`

在 `module.metadata` 中追加：

```json5
"metadata": [
  {
    "name": "ohos.arkui.UIMaterial.state",
    "value": "enable"
  },
  {
    "name": "client_id",
    "value": "你的应用 Client ID"
  }
]
```

注意：

- 必须配置在 **type 为 entry 的模块** 的 module.json5 中；
- 必须使用 **应用 Client ID**，不要错用 **项目 Client ID**；
- 如果 AGC 中 **Client ID 与 APP ID 相同**，按官方说明可以不加该 metadata；
- 不要把 Client ID 写进代码常量或资源字符串，使用 metadata 配置。

## 3. 配置签名与指纹

### 方式 A：DevEco 自动签名（推荐调试）

1. 登录 DevEco Studio 的华为账号；
2. `File → Project Structure → Signing Configs`；
3. 勾选 **Automatically generate signature**；
4. 连接真机，让 DevEco 生成调试证书与调试 Profile；
5. 在 AGC 的 **证书、APP ID 和 Profile → 证书管理** 中，把生成的证书 **SHA-256 指纹** 添加到应用；
6. 等待约 10 分钟，然后修改 `AppScope/app.json5` 的 **versionCode** 触发指纹生效；
7. 重新构建、卸载旧包、安装新包。

### 方式 B：手动签名

1. 在 AGC 申请调试/发布证书（.p12）与 Profile（.p7b）；
2. 在 DevEco **Signing Configs** 中导入；
3. 将证书 SHA-256 指纹加入 AGC 应用；
4. 重新构建并安装。

> 调试阶段必须用**调试证书 + 调试 Profile**；发布阶段必须换成**发布证书 + 发布 Profile**。切换调试/发布签名后需升级 versionCode，否则会命中指纹缓存。

## 4. 真机验证

1. 真机登录华为账号，连接网络；
2. 安装带正确签名与 client_id 的 HAP；
3. 打开 App → 我的 → 华为账号登录；
4. 正常应拉起华为账号授权页，授权后返回 openID/unionID；
5. 若仍失败，抓取 hilog：

```bash
hdc -t <serial> shell hilog -x | grep -iE 'Account|clientId|profile|100150'
```

### 常见错误

| 错误 | 原因 | 处理 |
|---|---|---|
| 1001502003 / Invalid clientId or profile | client_id 未配置、配置错误，或 Profile 无效 | 检查 entry/module.json5 的 client_id；重新申请 Profile 并签名 |
| 9568332 / install sign info inconsistent | 设备上已装包的签名证书与当前 HAP 不一致（换过调试证书/Profile 后最常见） | 卸载旧包再装，或在 DevEco 中 Clean + Rebuild 后用同一签名重新部署 |
| 1001500001 / 指纹证书校验失败 | AGC 未配置证书指纹，或换证书后未更新 | 在 AGC 添加 SHA-256 指纹，等 10 分钟并升级 versionCode |
| 模拟器登录失败 | 模拟器缺少华为账号面板/能力 | 使用真机验证 |
| 授权页拉起后无回调 | 签名与 AGC 应用不一致 | 确认包名、证书指纹、Profile 三者对应同一个 AGC 应用 |

### 换签名后 DevEco 部署报 9568332 install sign info inconsistent

这是签名不一致，不是代码错误。设备上已安装包的证书与 DevEco 当前构建出的 HAP 证书不是同一套。处理顺序：

1. 确认 DevEco File → Project Structure → Signing Configs 使用的是当前 build-profile.json5 中同一套 .p12/.cer/.p7b；
2. 在 DevEco 执行 Build → Clean Project，再 Build → Rebuild Project；
3. 卸载设备上的旧包（会清本地数据，云同步文件不在包内）：
   devecocli device app uninstall --device 2BD0223929003920 --bundle com.moe.starflow
4. 再在 DevEco 点运行，或直接：
   devecocli run --module entry --device 2BD0223929003920 --uninstall

不要混用两套签名：用 devecocli signature generate 换过证书后，旧安装包必须卸载一次；之后 DevEco 与 CLI 使用同一份 build-profile.json5 即可正常增量安装。

## 5. 云同步额外配置

华为云同步使用 **Cloud Foundation Kit**：

1. 在 AGC **开放能力 → Cloud Foundation Kit** 开通；
2. 创建云存储/云数据库资源；
3. 将同一个应用与签名配置关联；
4. 确认设备已登录华为账号；
5. 在 App「我的」页执行备份/恢复验证。

## 6. 本仓库当前状态

- AGC 应用已创建：**星译 StarFlow**，包名 **`com.moe.starflow`**；
- **APP ID / Client ID 相同**：`6917620459514246462`（按华为官方说明，此时**不需要**在 `module.json5` 追加 `client_id` metadata）；
- 已在 AGC 打开 **华为账号** 开放能力；
- 已通过 CLI 完成登录并自动生成调试签名材料：

  ```bash
  devecocli auth login --no-prompt
  cd /Users/kong/Desktop/StarFlowOhos
  devecocli signature generate --force
  devecocli build --modules entry --build-mode debug
  ```

  生成后在根目录 `build-profile.json5` 的 `app.signingConfigs[0].material` 中看到 `.p12 / .cer / .p7b` 路径，签名材料位于 `~/.ohos/config/`。
- 已移除 `ohos.permission.FILE_ACCESS_PERSIST`：该权限属于**受限 ACL 权限**，会阻止自动签名；当前阅读/导入流程使用系统文件选择器，不需要该权限。若后续确实需要持久化文件访问，应在 AGC **ACL 权限** 中申请，而不是直接写回 `module.json5`。
- 构建与安装已验证：真机 `2BD0223929003920` 可安装；模拟器 `127.0.0.1:5555` 启动 **Smoke: PASS**。
- 真机启动仍需**先解锁屏幕**；开发者模式下 CLI 不能自动解锁。解锁后执行：

  ```bash
  devecocli run --module entry --device 2BD0223929003920 --skip-build
  ```

- **华为账号登录已通过真机验证**：PCE-W30 上显示「已登录华为账号」，可执行云备份 / 云恢复与退出账号。
- **云同步暂阻塞**：点击云备份返回 `404 Product does not exist`，原因是尚未在 AGC 开通云存储实例。
  - 官方路径：AGC → 项目 → **云开发（Serverless） → 云存储 → 立即开通**，创建存储实例；
  - 但当前 AGC 首页提示「关于云开发服务停止新开发者接入的公告」，新账号可能无法再开通；需申请白名单或使用已有云开发项目。
  - 未开通前，Cloud Storage 的 bucket 不存在，任何上传都会 404；这不是客户端代码错误。
- 若仍报 `Invalid clientId or profile`，在 AGC 检查 Profile 是否为同一应用、证书 SHA-256 是否已加入应用，并把 `AppScope/app.json5` 的 `versionCode` +1 后重装。

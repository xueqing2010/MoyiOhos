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
| 1001500001 / 指纹证书校验失败 | AGC 未配置证书指纹，或换证书后未更新 | 在 AGC 添加 SHA-256 指纹，等 10 分钟并升级 versionCode |
| 模拟器登录失败 | 模拟器缺少华为账号面板/能力 | 使用真机验证 |
| 授权页拉起后无回调 | 签名与 AGC 应用不一致 | 确认包名、证书指纹、Profile 三者对应同一个 AGC 应用 |

## 5. 云同步额外配置

华为云同步使用 **Cloud Foundation Kit**：

1. 在 AGC **开放能力 → Cloud Foundation Kit** 开通；
2. 创建云存储/云数据库资源；
3. 将同一个应用与签名配置关联；
4. 确认设备已登录华为账号；
5. 在 App「我的」页执行备份/恢复验证。

## 6. 本仓库当前状态

- 仓库内没有 `client_id` metadata；
- 没有 AGC 应用绑定；
- 当前安装包使用本地/调试签名；
- 因此真实华为账号登录会返回 `Invalid clientId or profile`，这属于配置缺失，不是 Account Kit 调用代码错误。

补齐上述 AGC 配置并把 Client ID / 签名材料提供后，即可在真机完成登录与云同步闭环。

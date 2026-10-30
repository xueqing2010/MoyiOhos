# 华为账号、签名与云同步

## 1. AGC 应用

1. 登录 AppGallery Connect；
2. 创建项目 → 添加应用；
3. 平台 HarmonyOS，包名必须与 `AppScope/app.json5` 的 `bundleName` 完全一致；
4. 记录 **APP ID** 与 **Client ID**；
5. 在「开放能力」中开启 **华为账号**；
6. 云同步还需开通 **云存储**（见第 5 节）。

### Client ID metadata 规则

- APP ID == Client ID：**不需要** `client_id` metadata；
- APP ID != Client ID：在 **entry** 模块 `module.json5` 的 `metadata` 加：

```json5
{
  "name": "client_id",
  "value": "<AGC 应用 Client ID>"
}
```

不要加错到项目级/其他 HAR。

## 2. 调试证书与 Profile

### 方式 A：CLI 自动（推荐）

```bash
devecocli auth login --no-prompt
cd <project>
devecocli signature generate --force
```

会生成：
- `~/.ohos/config/default_<Project>_<hash>.p12`
- `.cer`
- `.p7b`
- `.csr`

并写入根目录 `build-profile.json5` 的 `app.signingConfigs`。

### 方式 B：DevEco 自动签名

`File → Project Structure → Signing Configs → Automatically generate signature`。

坑：
- 若项目声明了受限 ACL 权限（如 `ohos.permission.FILE_ACCESS_PERSIST`），自动签名会被 ACL 弹窗/报错阻塞；
- 先移除不必要的受限权限，或改走 CLI；
- 自动签名卡住不要反复点，直接 CLI。

## 3. 证书指纹与 Profile

- AGC → 证书、APP ID 和 Profile → 证书：上传/查看证书；
- 应用详情 → SHA256 证书/公钥指纹 → 添加证书指纹；
- AGC → Profile：创建调试 Profile，选择应用、证书、设备；
- 下载 `.p7b` 并让 `build-profile.json5` 指向它；
- 改指纹后等待约 10 分钟，并 bump `versionCode`；
- 设备必须注册到调试 Profile（真机 UDID）。

### 换签名后

设备旧包证书不同，会报：

```text
9568332 install sign info inconsistent
```

处理：

```bash
devecocli device app uninstall --device <serial> --bundle <bundle>
devecocli run --module entry --device <serial>
```

或在 DevEco：Clean → Rebuild → 运行。

## 4. Account Kit 登录

代码大致：

```ts
import { authentication } from '@kit.AccountKit';

const req = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
req.forceLogin = false;
req.state = '...';
const controller = new authentication.LoginWithHuaweiIDController();
const resp = await controller.executeRequest(req);
```

坑：
- 必须在真机验证，模拟器通常无账号面板；
- 签名/Profile/AGC 应用不匹配 → `1001502003 Invalid clientId or profile`；
- 指纹未生效 → `1001500001`；
- 回调地址/scope 配置错误 → 授权页拉起后无回调；
- 用户取消登录要当正常分支处理，不要弹错误。

## 5. 云同步（Cloud Foundation Kit）

代码：

```ts
import { cloudStorage } from '@kit.CloudFoundationKit';

const bucket = cloudStorage.bucket();
await bucket.uploadFile(context, {
  localPath,
  cloudPath: 'backup/latest.json'
});
```

前置条件：
1. 已登录华为账号；
2. AGC 已开通 **云存储** 实例；
3. 应用签名与 AGC 应用匹配。

开通路径：
AGC → 项目 → **云开发（Serverless） → 云存储 → 立即开通**。
存储实例名只能小写字母/数字/中划线，3–57 字符。

### 404 Product does not exist

不是代码错误，是 bucket 不存在/未开通。

如果 AGC 提示「云开发服务停止新开发者接入」：
- 新账号可能无法创建新实例；
- 尝试申请白名单/使用已有云开发项目；
- 或改用 WebDAV / 自建对象存储作为降级。

## 6. 安全

- 不提交 `.p12/.cer/.p7b/.csr`；
- 不提交 Client Secret、API Key、keystore 密码；
- 不在日志打印 token/openID 全量；
- 截图前遮蔽账号/密钥；
- 云同步文件路径固定，避免用户间覆盖。

## 7. 账号/云同步验收

- [ ] 真机已登录，显示账号 ID；
- [ ] 备份成功，云端有文件；
- [ ] 卸载重装后可恢复；
- [ ] 失败提示可操作（不是原始 404）；
- [ ] 未登录时按钮引导登录；
- [ ] 云存储未开通时有明确说明。

## 8. 常见错误表

| 错误 | 含义 | 处理 |
|---|---|---|
| 1001502003 | clientId/profile 无效 | 检查 AGC 应用、Client ID、Profile、签名 |
| 1001500001 | 证书指纹不匹配 | AGC 加指纹，等待，bump versionCode |
| 9568332 | 安装签名不一致 | 卸载旧包 |
| 9568276 | 已存在同版本 | 卸载或 bump versionCode |
| 404 Product does not exist | 云存储未开通 | AGC 开通云存储 |
| 10106102 | 设备锁屏 | 手动解锁 |

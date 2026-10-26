# ADR-0005：应用内更新的信任链改为 Ed25519 更新签名 + 固定代码签名证书

日期：2026-10-27　状态：已接受（对应审计 #17）

## 背景

在此之前，应用内更新的信任只落在 GitHub 一处：

- 期望的 SHA-256 来自 GitHub API 的 asset digest，或同一个 release 里的 `.sha256`；
- 安装前的 `codesign` 要求只有 `identifier "com.jryang1997.MenuBarMijia"`，任何人都能用同一个 Bundle ID 做 ad-hoc 签名；
- 解包后无条件执行 `xattr -dr com.apple.quarantine`，主动绕过 Gatekeeper。

威胁模型很直接：GitHub 账号、Token 或 CI 任意一环被拿下（参见 #25：`contents: write` 且 main 无保护），攻击者就能发一个新 release、附上匹配的 `.sha256` 与同 ID 的 ad-hoc 签名包，让所有开启了自动更新的用户装上恶意版本且不经过 Gatekeeper。项目已有真实用户与下载量，这是全项目影响面最大的链路。

## 决定

1. **Ed25519 分离签名，作为主防线。** 发布时用私钥对最终 DMG 字节签名，生成 `<DMG>.ed25519.sig` 并作为 release 附件上传。应用把 32 字节公钥编进 `UpdateChecker.updateSigningPublicKeyBase64`，在下载完成、SHA-256 校验通过之后、解包之前验证签名。签名缺失、不是合法 base64、或与包内容不匹配，一律中止安装并报明确错误（`updateSignatureMissing` / `updateSignatureInvalid`）。选择 CryptoKit `Curve25519.Signing` 是因为它是系统自带、无第三方依赖，和 Sparkle 的 Ed25519 思路一致；Linux 侧由 ADR-0003 的 swift-crypto 垫片提供同名 API。

   私钥的保存方式决定这条防线到底防谁：**推荐完全不配置 `MENUBARMIJIA_UPDATE_SIGNING_KEY` secret，在可信机器上离线签名后手动上传**，这样 GitHub/CI 被攻破也拿不到私钥。发布工作流也允许把私钥放进 GitHub secret 自动签名，但这等于把“GitHub 被攻破”重新纳入密钥泄露面；便利性与独立性需要自己取舍。

2. **钉住代码签名证书。** 项目没有付费 Apple 开发者账号，发布包用固定的自签名代码签名证书（RSA 3072，10 年，Code Signing EKU）。`scripts/build_app.sh` 在设置了 `MACOS_SIGNING_IDENTITY` 时用该身份签名，并把证书 SHA-1（`MACOS_CERT_SHA1`）写进 App 的 `Info.plist` 键 `MijiaCodeSignCertSHA1`。更新时读取运行中 App 的该键，把 `codesign` 要求构造成：

   ```
   identifier "com.jryang1997.MenuBarMijia" and certificate leaf = H"<sha1>"
   ```

   同 Bundle ID 的 ad-hoc 包没有这张证书，无法通过。**这里刻意不使用 `anchor apple generic`**：自签名证书不链到 Apple，加上 anchor 会让所有正式签名更新永远匹配不上；精确钉住叶子证书哈希本身就是信任锚。没有该键的本地构建退回 identifier-only，由 Ed25519 继续兜底。

   把证书 p12 放进 GitHub secret 的残余风险是：CI 被攻破时攻击者可以签出“看起来同源”的 App 包；但只要 Ed25519 私钥没有同时放进 GitHub secret（推荐离线保存），就仍然产不出能通过更新校验的 `.ed25519.sig`。因此 p12 泄露不足以投放恶意更新，私钥的保管方式才是最终门槛。

3. **隔离属性按构建类型处理。** 新增纯函数 `AppUpdater.shouldStripQuarantine(currentAppIsAdHoc:)`：只有非 Apple 锚定的构建（ad-hoc 或自签名、本地开发）才去掉 `com.apple.quarantine`，保证本地自更新可用；Apple 锚定的正式构建保留隔离属性，让 Gatekeeper 正常检查替换后的 App。`currentAppIsAdHoc()` 用 `SecCodeCopySelf` → `SecCodeCopyStaticCode` → `SecCodeCopyDesignatedRequirement` → `SecRequirementCopyString` 判断 designated requirement 是否含 `anchor apple generic`；读取失败时保守地当作 ad-hoc（维持本地更新，不让功能因环境差异失效）。代价是自签名发布包仍会去隔离——这类包本来也无法通过 Gatekeeper 公证检查，保留隔离只会让自更新直接失败。

4. **发布流程缺签名就不发布。** 新增 tag 触发的 `.github/workflows/release.yml`：`MACOS_SIGNING_P12` / `MACOS_SIGNING_P12_PASSWORD` 存在时导入临时钥匙串、签名并写入证书 SHA-1，不存在时降级为 ad-hoc 并在 job summary 警告；`MENUBARMIJIA_UPDATE_SIGNING_KEY` 不存在时 job **失败**并打印离线签名命令（`scripts/sign_update.swift`），宁可不发布也不发未签名更新。私钥格式支持 32 字节 raw seed 的 base64 或 PKCS#8 PEM。

## 后果

- 不配置更新签名私钥 secret（推荐）时，GitHub 账号、release 或 CI 被攻破都无法产出能通过校验的更新包；攻击者最多造成“更新失败”，而不是“装上恶意版本”。配置了该 secret 时，GitHub/CI 被攻破即等价于私钥泄露，这条防线退化到与 secret 同级的保护。
- 发布流程多了一步离线签名（或配置私钥 secret），换取了更新链路的独立性。轮换密钥需要同时改 `UpdateChecker.updateSigningPublicKeyBase64` 并发布新版本；轮换代码签名证书同理，旧版本会因钉住旧证书而拒绝新包，需要先用旧证书发一个过渡版本。
- 残余风险：升级到本实现之前发布的旧版本仍按旧信任链检查更新，因此“第一次升级到带签名校验的版本”这一步无法由新机制保护；之后的所有更新才受 Ed25519 约束。
- 残余风险：攻击者可以重放一份**旧版本但签名有效**的 DMG，并把 release 标成更高版本号；版本号本身没有签名覆盖。当前缓解依赖 release 可见性与用户察觉，后续可把最低版本/渠道写进签名载荷再收紧。
- CI secret 里的 p12 能签出同证书的 App 包，但不能伪造更新签名（除非同时泄露了 Ed25519 私钥）；私钥泄露才是灾难性事件。
- 自签名构建仍会去隔离；这是“没有 Apple 公证”这一前提下的可用性取舍，而不是对 Gatekeeper 的普遍绕过。

## 相关

- #17（本 ADR 的来源）、#25（CI 权限与 release 覆盖风险）
- ADR-0003（MijiaCore 在 Linux 上编译，CryptoKit 由 swift-crypto 垫片提供）
- `Sources/MijiaCore/UpdateChecker.swift`、`Sources/MijiaCore/UpdateSignature.swift`、`scripts/sign_update.swift`、`scripts/build_app.sh`、`.github/workflows/release.yml`

# 更新记录

## 未发布

### 安全与隐私
- **应用内更新有了独立的信任链（[#17](https://github.com/jryang1997/MenuBarMijia/issues/17)）**：发布 DMG 时用离线 Ed25519 私钥生成 `<DMG>.ed25519.sig`，公钥编进 App；下载后先校验 SHA-256，再验证签名，缺失或不匹配一律中止安装。代码签名要求从只认 Bundle ID 改为钉住固定证书的 SHA-1（构建时写入 `Info.plist` 的 `MijiaCodeSignCertSHA1`），同 Bundle ID 的 ad-hoc 包不再通过。只有非 Apple 锚定的本地构建才会去掉 `com.apple.quarantine`，正式构建保留隔离属性交给 Gatekeeper。发布工作流缺少签名私钥时直接失败，不再发布未签名更新；离线签名见 `scripts/sign_update.swift`。
- **AI 服务商改为精确域名识别（[#19](https://github.com/jryang1997/MenuBarMijia/issues/19)）**：`openrouter.ai.evil.com`、`notopenrouter.ai` 这类仿冒地址不再被当成 OpenRouter，也拿不到你保存的 Key。自定义地址的 Key 只发给保存时的那台服务器；换地址要重新填。非 https 的公网地址一律不发送（本机和局域网除外）。macOS 与 Windows 共用 `Tests/Fixtures/provider_golden.json` 校验。
- **不再自动读取 CodexBar / 环境变量里的 Key（[#20](https://github.com/jryang1997/MenuBarMijia/issues/20)）**：改为设置里的「从 CodexBar / 环境变量导入 Key」按钮，点了才读取并复制到本机钥匙串；设置里显示来源，可一键撤销。第一次要把指令发给某个云端 AI 服务前，会先问你一次（说明发送什么、发给谁），之后可在隐私设置里撤销授权。本机/局域网模型不用确认。升级后如果之前靠 CodexBar 自动接入，需要点一次导入。
- **AI 没把握时不再自己动手（[#21](https://github.com/jryang1997/MenuBarMijia/issues/21)）**：Jev 等 AI 给出的动作，只有把握 ≥ 80% 才直接执行；低于 80%、或没给出把握度的，变成建议胶囊，点一下才执行。打开电暖器、开关插座、启动扫地机即使 AI 很有把握也要点一下（关电暖器不用）。聊天类模型（DeepSeek 等）同样适用，回执不再声称已经开了还没开的设备。macOS 与 Windows 同步。
- **Home Assistant 断线后不再自己换地址（[#18](https://github.com/jryang1997/MenuBarMijia/issues/18)）**：以前连不上时会扫描局域网，把访问令牌直接发给扫到的第一台“Home Assistant”（可能是别人伪装的）。现在只在面板顶部提示「发现了 xxx，要切换过去吗？」，点「切换」才换；点「不切换」本次不再问。和你上次选的那台实例标识（uuid）不一致的直接忽略。连续断两次才扫描，最多 10 分钟一次。设置和新手引导里的「扫描」只填地址，点保存才连接。
- **凭证只存钥匙串，不再明文回退（[#16](https://github.com/jryang1997/MenuBarMijia/issues/16)）**：上一版为了绕开升级后的钥匙串弹窗，把米家会话、HA 令牌、AI API Key 和 LG 电视配对密钥都明文镜像到了 `UserDefaults`（`defaults read com.jryang1997.MenuBarMijia` 就能读到）。现在钥匙串是唯一存储：读取不再先看明文，读到钥匙串后也不再回写；保存空值即删除。升级后首次启动会自动把旧明文键（`ha_fallback_token`、`mi_session_fallback_v1`、`keychain_fallback_*`、`lg_webos_client_key`）迁入钥匙串并删除原键，钥匙串写入失败时保留明文等下次重试。由于 App 是 ad-hoc 自签名构建，升级后系统可能询问一次钥匙串访问；拒绝授权则需重新登录一次。Windows 版保持凭据管理器存储，不受影响。
- **米家会话不再保存账号级 `passToken`（[#27](https://github.com/jryang1997/MenuBarMijia/issues/27)）**：`passToken` 全仓库没有一处使用，会话过期一直是提示重新扫码，所以登录成功后不再持久化它；迁移旧会话时会解码后重新编码，把已存的 `passToken` 一并去掉，不需要重新登录。决策见 `docs/adr/0004-no-pass-token-storage.md`。

### 防误操作
- **「全关」更安全（[#23](https://github.com/jryang1997/MenuBarMijia/issues/23)）**：只关当前看到的设备（当前房间、未隐藏）；插座和扫地机默认不参与（插座常接路由器、冰箱、鱼缸，扫地机不该被打断回充），可在设备右键菜单里单独加入或排除，Windows 在设置里勾选。所有皮肤都改为按住 0.6 秒才执行（经典皮肤以前单击就关），按钮显示范围和台数，例如「全关·书房 (2)」。撤销横幅从 5 秒延长到 10 秒。VoiceOver 可用「关闭这 N 台设备」操作。

### 可靠性
- **米家云不再全天每 6 秒拉一次数据（[#26](https://github.com/jryang1997/MenuBarMijia/issues/26)）**：面板打开时 6 秒刷新；面板关着改成 1 分钟一次（低电量模式 3 分钟）；电脑睡眠、显示器睡眠、锁屏、切换用户时完全不请求，醒来或解锁后马上刷新一次。选了某个家庭时只拉这个家庭的设备。米家云提示请求太频繁（HTTP 429）时至少等 1 分钟再试、最长 15 分钟，并在面板上提示。想核对请求量，可在「控制台」App 搜 `Mi cloud polling`，每次切换都会记下之前拉了几次。Windows：面板打开 12 秒、收在托盘里 1 分钟。
- **合盖睡眠后，错过的定时不再一开盖就执行（[#22](https://github.com/jryang1997/MenuBarMijia/issues/22)）**：定时到点时如果已经晚了 1 分钟以上（通常是电脑在睡眠），不会自动执行，而是和“启动时发现过期”一样进入「已错过」提示并发通知，由你决定立即执行或忽略。晚几秒的照常执行。Windows 同步。

## 1.0.6

本次提供 macOS (`MenuBarMijia-1.0.6.dmg`) 与 Windows 安装包。

### 新增与改进
- **macOS 应用内一键下载、校验、安装与重启更新 ([#4](https://github.com/jryang1997/MenuBarMijia/issues/4), [#5](https://github.com/jryang1997/MenuBarMijia/pull/5))**：在「软件更新」区域展示新版本号与可折叠的更新说明；点击「下载并安装」后直接在应用内流式下载 GitHub Releases 安装包（优先 `.dmg`，次选 `.zip`），分块校验 SHA-256 摘要，后台静默挂载解包，剥离 `com.apple.quarantine` 并通过 `codesign --verify --deep --strict` 校验 Bundle ID 与代码签名。校验通过后由用户点击「立即重启完成更新」完成原位替换与自动重启，无需手动挂载 DMG 拖入 `/Applications`。
- **自动检查更新开关与底栏轻量角标提醒 ([#4](https://github.com/jryang1997/MenuBarMijia/issues/4))**：新增「自动检查更新」偏好开关（默认开启，按 24 小时节流），在面板底栏以胶囊角标静默提示新版本或就绪状态，不弹出打断当前工作的系统模态窗口；下载失败或无写入权限时保持当前版本正常运行，并提供「重试」与「手动下载 DMG」兜底按钮。
- **跨版本更新无感保留登录态、钥匙串凭据与自定义配置 ([#4](https://github.com/jryang1997/MenuBarMijia/issues/4))**：为米家云登录会话 (`MiSessionStore`) 与各 AI 服务商 API Key (`KeychainHelper`) 补齐 `UserDefaults` 回退同步及 `kSecUseAuthenticationUISkip` 非阻塞查询，在应用启动及替换重启前自动同步凭据，消除 Ad-hoc 签名跨版本更新后的 macOS 钥匙串授权弹窗。

## 1.0.5

本次提供 macOS (`MenuBarMijia-1.0.5.dmg`) 与 Windows 安装包。

### 修复
- **修复自定义 `localhost:3425` / `127.0.0.1:3425` 兼容接口保存后被重置为 OpenRouter 的问题 ([#3](https://github.com/jryang1997/MenuBarMijia/issues/3))**：移除 `AssistantConfig.load(from:)` 中无条件拦截 `localhost:3425` 与 `127.0.0.1:3425` 的旧版遗留覆盖逻辑，完整保留用户显式保存的自定义 Base URL、模型与对应服务商槽位的 API Key。
- **统一「测试连接」与语音/文字指令执行的配置解析路径 ([#3](https://github.com/jryang1997/MenuBarMijia/issues/3))**：`HomeStore.verifyAssistantConfig(_:)` 与设置面板保存操作现统一读取持久化后的 `store.assistantConfig`（`AssistantConfig.load(from: userDefaults)`），确保「测试连接」与实际 AI 指令执行使用完全相同的生效端点、模型及凭据，消除测试假阳性；同时为非 `.standard` 的测试 `UserDefaults` 增加独立密钥存储隔离，并补充 `127.0.0.1:3425` 与 `localhost:3425` 保存/读取往返及端到端执行回归测试。

## 1.0.4

本次提供 macOS (`MenuBarMijia-1.0.4.dmg`) 与 Windows 安装包。

### 修复与新增
- **修复米家扫码登录后菜单栏图标消失 / 进程闪退问题 ([#2](https://github.com/jryang1997/MenuBarMijia/issues/2))**：定位并修复 `MiCloudProvider.loadMissingSpecs()` 在 Release (`-O`) 编译优化下，因 `withTaskGroup` 子任务直接返回内联异步挂起点的三元组 `return (model, try await source.spec(...), nil)`，触发 Swift 6.4 协程分片优化消除元组首字段（`model`）写入、进而导致未初始化内存解引用 `EXC_BAD_ACCESS (SIGBUS)` 闪退或全部设备规格被跳过（`0 supported`）的问题。现改为先完成 `await` 再构造具名 `SpecLoadOutcome` 结构体，并补充 20+ 模型并发加载回归测试与 `scripts/check.sh` 静态门禁。
- **多 AI 服务商一键切换与自有 API Key 支持（macOS & Windows 双端对齐）**：不再局限于复用 CodexBar 中的 OpenRouter 密钥，现内置 **TypeSafe Jev 官方 (`https://api.typesafe.ai/v1`)**、**OpenRouter (`~typesafe/jev-latest`)**、**DeepSeek (`deepseek-chat`)**、**通义千问 Qwen**、**智谱 GLM**、**Moonshot Kimi**、**硅基流动 SiliconFlow**、**OpenAI**、**Groq**、**Ollama 本地模型** 及自定义 OpenAI 兼容端点预设。用户可在设置页或新手引导直接填入自己的 API Key，切换服务商时自动填入推荐 Base URL 与模型名；Jev 模型自动调用 `/v1/systemone` 结构化多选决策接口，DeepSeek 等通用模型自动调用 `/v1/chat/completions` JSON 规划接口。

## 1.0.3

本次提供 macOS (`MenuBarMijia-1.0.3.dmg`) 与 Windows 安装包。

### 新增与改进
- **系统门槛下放至 macOS 14+ (Sonoma / Sequoia / Tahoe)**：将 `Package.swift` 与应用打包最低系统版本从 `macOS 26.0` 下调至 `macOS 14.0`。macOS 26 保持原生 SwiftUI `.glassEffect` Liquid Glass 液态玻璃渲染，macOS 14 与 15 自动回退至 `.ultraThinMaterial` 毛玻璃；核心库 `MijiaCore` 可直接作为独立 SwiftPM 库引用。
- **定时器磁盘持久化与过期安全确认**：延时指令（如「10 分钟后关加热器」）持久化保存在本地 `UserDefaults` (`assistant_scheduled_commands_v1`)。应用重启后，未到期定时按剩余秒数继续倒计时；退出期间已过期的定时转入待确认队列（绝不在后台静默触发过期硬件操作），通过指令栏顶部横幅与 macOS 原生通知提供「立即执行」或「忽略」。
- **双端黄金语料 (`intent_golden.json`) 与 Windows 英文指令完整对齐**：新增跨平台共享测试语料 `Tests/Fixtures/intent_golden.json`，由 Swift Testing 与 Windows TypeScript 测试共同校验；Windows 端补齐词边界消费式英文解析（支持色温、空调模式、相对调温、自动风速、英文延时与撤销）。
- **隐私与米家云直连说明完善**：在 README 与登录设置页补充米家非官方客户端 API 的账号风控提示与官方 `xiaomi_home` 替代方案，并披露本地 `UserDefaults` 明文存储键名。

## 1.0.2

本次提供 macOS (`MenuBarMijia-1.0.2.dmg`) 与 Windows 安装包。

### 新增
- **应用内中英双语国际化 (`zh-Hans` / `en`)**：支持「跟随系统 / 简体中文 / English」实时切换（偏好设置与新手引导均可一键切换），全面覆盖主控制面板、设备磁贴、快捷场景、设置页、安全通知与系统权限弹窗。
- **英文语音识别与本机 0ms 英文指令解析**：英文界面下自动切换 `en-US` 语音识别，支持英文自然语言设备控制（如 `"turn on study light"`, `"study light moonlight mode"`, `"set living room ac to 24 degrees"`, `"dimmer"`）、英文延时指令（`"in 10 minutes turn off study light"`, `"cancel timer"`）与英文撤销（`"undo"`, `"revert"`）。
- **米家云端多地区服务器选择**：扫码登录支持切换中国大陆 (`cn`)、新加坡/国际 (`sg`)、欧洲 (`de`)、美区 (`us`)、俄罗斯 (`ru`) 节点。

## 1.0.1

本次提供 macOS (`MenuBarMijia-1.0.1.dmg`) 与 Windows 安装包。

### 修复
- 应用名称、安装包（`MenuBarMijia.app` / `MenuBarMijia-1.0.1.dmg`）与仓库名称统一为 `MenuBarMijia`。
- LG webOS 电视局域网直连默认关闭，移除内置的局域网 IP 与 MAC 地址默认值，改为由用户在设置中填写或局域网扫描。
- 未配置 AI 服务 API Key 时，默认地址保持为 OpenRouter (`https://openrouter.ai/api/v1`)，不再回退连接本机 `localhost:3425` 端口，并在触发复杂指令时直接提示配置 API Key（简单指令仍可 0ms 本地离线执行）。
- Home Assistant 支持独立实体的设备合成，补齐没有物理设备注册记录的灯、风扇、空调、插座等已支持类型。
- 按 Home Assistant 的标准设备类别识别温湿度计和普通开关，保留辅助开关设备的环境读数，避免实体名子串误伤有效插座。
- 初次连接等待区域、设备、实体注册表和状态全部就绪后发布列表，避免隐藏设备暂时出现；注册表权限或格式错误会显示连接错误。
- Windows 云端控制失败时显示错误并保留原状态；撤销按成功指令逆序恢复实际修改的属性和原始开关状态，失败后可重试。
- Windows 保留手动选择的数据源，避免已有小米登录信息覆盖该选择；同步设备时不再重叠请求。
- Windows 灯具详情显示设备支持的日光、月光等模式，点击后通过米家云切换，并支持撤销恢复原模式。

### 工程
- 固定 Windows 原生依赖版本；CI 在核心测试通过后生成安装包和 SHA-256 校验文件，发布时上传到对应版本。
- 增加 Windows 页面控制、模式切换及撤销回归测试，以及 HA 设备识别、初始返回顺序和注册表错误的 Swift Testing 用例。

## 1.0.0

### 新增
- 说「再暗一点」「调高两度」「温度低一点」可以微调；没说设备时只调正开着的。
- 风扇：「高档」「风速调低」「摇头」「停止摇头」。
- 定时：「10 分钟后关灯」「半小时后关空调」，指令栏里能看到倒计时并取消；也可以说「取消定时」。
- 语音撤销：说「撤销」能恢复 10 分钟内最近一次语音操作。
- 设置页「检查更新」，读取 GitHub Releases。
- 隐私：可以关掉习惯学习、逐条删除已记住的习惯、让语音只在本机识别；设置页写明哪些内容会发给 AI。

### 改进
- App 名称统一为 MenuBarMijia（登录信息和设置会保留）。
- AI 出错时说人话：超时、断网、密钥不对、请求太多、服务器出错分别提示。
- 默认家庭名改为「我的家」。

### 工程
- 版本号放在 `VERSION`；`scripts/release.sh` 一条命令完成签名、DMG、公证。
- GitHub Actions：macOS 上编译和测试，Linux 上跑核心测试。
- 核心库可以在 Linux 上编译测试（`scripts/linux-check/run.sh`）。
- `HomeStore.swift` 拆出 `HomeStore+Assistant.swift`。

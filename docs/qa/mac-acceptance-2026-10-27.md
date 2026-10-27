# PR #65 Mac 验收记录

已推送代码 `0368475e50c29f3292262a243745f67e59e3dd84` 的四项必需 CI 全绿，GitHub 为 CLEAN、未落后 main。PR 仍为草稿，尚未合并或发布。真实设备、独立账号升级与正式发行签名验收未完成。

随后华氏实测发现顶部环境条漏换算。本地已用一行改动修复，并通过本地化测试、实际开发签名打包和实机观察。该行尚未提交，等待用户决定是否增加一轮 Sol 复审，不能把前述绿灯归到这行代码上。

## 基准与证据归属

固定代码基准为 `ad6c72046ca4a7ca88d48ce57cc08da0b7351a55`。领取的 PR head `098de7d` 与基准功能代码相同，只增加交接文档。本轮继续 `fix/audit-issues`，保留已有作者。

本机为 arm64、macOS 27.0.1、Xcode 27.1、Swift 6.4。原始日志留在私有目录 `~/Library/Logs/MenuBarMijia-qa/20261027-pr65/`。仅公开窗口截图与脱敏结论，不上传桌面截图、原始界面树、账号或钥匙串数据。

| 固定提交或阶段 | 实际结果 |
| --- | --- |
| 原 CI [40452691649](https://github.com/jryang1997/MenuBarMijia/actions/runs/40452691649) | Linux 四项核心断言失败，macOS 缺元数据打包失败。 |
| 本机 `check-before.log` | 核心 265 项有五项失败，App 25 项有 18 个问题。 |
| `e7118c0` 的 `check-reviewed.log` | 核心 266/266；App 29 项只有两项图像测试失败，共 14 张图。其余 27 项通过，包括面板 16 项和新增 Intent 4 项。整体命令非零。 |
| `8cd0fd6` | 修正 CI Swift 6.3.3 的动画闭包结果推断，20 项面板与 Intent 关联测试通过。CI 编译随后通过，元数据查找仍失败。 |
| `58a62b0` | 惰性语言资源搜索和 Xcode 中间路径修复。18 项本地化与 20 项面板、Intent 测试通过。CI 实际打包成功，295 项测试只剩 14 张图像差异。 |
| `d276164` / [40458193827](https://github.com/jryang1997/MenuBarMijia/actions/runs/40458193827) | 固定快照摄氏单位后，传感器图精确通过，剩 13 张差异经逐图审查。 |
| `0368475` | 接纳 13 张已审查 CI 图片。必需 linux-core、macos、windows-core、windows-installer 全部通过，Homebrew self-test 通过。 |
| 本机后续完整检查 | `check-lazy.log` 核心 266/266；本机 macOS 27 与 macOS 26 CI 图像环境仍不同。精度保持 1，不把本机图录为 CI 基线。 |
| 顶部华氏未提交修复 | `header-temperature-tests.log` 本地化 18/18；`build-header-signed.log` 实际打包成功；[实机截图](evidence/pr65/header-fahrenheit-fixed.png) 顶部显示 78.4°，与卡片和菜单栏 78.4°F 一致。该行未获额外 Sol 审查。 |

Windows 本机 `npm test` 93/93，TypeScript 与 Vite 生产构建通过。Homebrew 本机离线自检 29 项通过，包含 Ruby 检查。受控本地 TLS 实际验证换证拒绝与重新配对，不将其当作真实电视验收。

## 实际打包与签名

`build-final.log` 对应 ad-hoc 包，包含四个动作、四个 App Shortcuts 与模块语言资源。系统 Shortcuts 能发现动作，但 `linkd` 因没有 Team ID 拒绝通信。

随后使用本机已有 Apple Development 身份实际运行打包脚本，没有新增证书、修改认证权限或触碰离线更新私钥。开发签名严格校验通过，Team ID 存在。`build-lazy-signed.log` 与 `build-header-signed.log` 保留完整结果。开发签名不等于 Developer ID 发行、Gatekeeper、公证或升级验收。

新签名身份触发的桌面 TCC 提示暴露了语言资源搜索提前枚举所有父目录的问题。调用栈与 TCC 日志定位后，改为模块资源命中即停止搜索。没有通过扩大文件权限解决该代码问题。

## 修复与独立审查

- 明确清空 NSPanel 自带初始空视图，让首次打开实际安装 SwiftUI 内容。隐藏重开保留同一内容树。
- 缺失语言资源时保留保存的 tag，显示回退到可用语言。加入模块资源路径并采用惰性备用目录搜索。
- 中文定时允许数字与单位间空白，Swift、Windows 与共享黄金语料保持一致。
- 修正目录 URL 的目录标志比较与误引用空调的传感器断言。
- 快捷指令和 URL 共用有时限的首份快照等待，空家庭也能完成加载。外部入口等待设备、场景请求结果再反馈，失败保留回滚。
- Xcode 生成新常量数据后显式提取元数据，兼容新旧中间目录名，缺少元数据仍硬失败。CI 保留具体构建日志。
- 快照固定 1x、固定摄氏，并恢复测试前的设置。逐图接纳有来源和哈希的 13 张 CI 产物，未改精度或开启录制模式，见[逐图验收记录](evidence/pr65/snapshot-baseline-review.md)。

sol-loop 共五轮，模型 `gpt-6.1-sol`，xhigh。S1 冷启动空数据与 S2 提前报成功均修复。第二至第五轮 APPROVE。后续轮次只检查变更代码和未决项，用量未暴露。此批准覆盖已推送的行为修复，不包含顶部华氏一行新修复，也不代表全部 170 文件原始审计改动或所有实机门槛已独立验证。

本轮采用 Prove It Works 原则，要求实际包与系统返回值；采用 Laziness Protocol 原则，只补已复现失败，没有新增动作、认证方案或设备模型。

## 实机验收矩阵

以 `-home_backend demo` 显式启动。只有下面列出的步骤实际测到，不将单测代替系统操作。

| 阶段 | 结果与剩余缺口 |
| --- | --- |
| 启动与演示 #47 | [真实面板](evidence/pr65/panel-demo.png) 有演示标记、13 台虚拟设备。点击客厅灯，开启数 4 变 3。未抓包证明零请求，未断网验收。 |
| 独立设置 #42 | 设置与面板可同时存在，切换到 Shortcuts 后设置仍在。家居连接、通用和关于页实际可达，未完成全部分区与复制文本流程。 |
| 菜单栏与声音 #54/#56 | 实测 tooltip 开启数、温度与演示状态随控制和单位更新。声音默认关闭。右键、拖动、多显示器与播放未测。 |
| 自定义热键 #43 | 默认 ⌥M 实际呼出。录制、重启持久化、冲突与释放未测。 |
| 无障碍 #41 | 界面树有设备名称与详细控制入口。VoiceOver、降低透明度和对比度实测未完成。 |
| 语言与单位 #51/#52 | [English](evidence/pr65/settings-english.png)、[繁体](evidence/pr65/settings-traditional.png) 与华氏设置实际切换。顶部漏转换的一行补修已有[实机证据](evidence/pr65/header-fahrenheit-fixed.png)，待额外复审。仍有部分繁体界面字段回退，完整九皮肤和深浅色实机矩阵未完成。语言与温度测试后均恢复跟随系统。 |
| 搜索 #60 | 演示名字是“书房台灯”，`sftd` [匹配一台](evidence/pr65/search-sftd.png)，Return 后[实际开启](evidence/pr65/search-return.png)。`sfd` 对当前演示名字无匹配。首次 Esc 清空并退出搜索。↑↓、→ 与第二次 Esc 未形成完整验收证据。 |
| 撤销 #34/#53 | 核心回归通过；未完整实测悬停、十分钟入口和重开。 |
| 通知与语音 #50/#55 | 新账号首请求、拒绝入口与离线中文识别未测。 |
| 真实连接 #18/#26/#37 | 未登录真实 HA、米家或海外账号；地址变化、锁屏轮询未测。 |
| 误操作与定时 #21/#22/#23 | 核心安全和定时回归通过；真实 AI、合盖跨时与实际设备范围未测。 |
| 长开、电量、用电 #35/#62 | 无长期真实读数、冷却跨重启和清除后重启实测。 |
| 快捷指令 #57 | 系统[发现四动作](evidence/pr65/shortcuts-discovery.png)，并实际返回[客厅温湿度](evidence/pr65/shortcut-result-climate.png)、[设备切换](evidence/pr65/shortcut-result-toggle.png)、[场景](evidence/pr65/shortcut-result-scene.png)、[一句话控制](evidence/pr65/shortcut-result-ask.png)。均为演示实体。Spotlight 和四动作真实冷启动矩阵未测。 |
| URL #57 | 手写 toggle URL 实际出现[确认框](evidence/pr65/url-confirm.png)，默认 Cancel，点击取消后书房灯仍开启。scene、ask URL 与冷启动尚未实测，没有把 Intent 测试当作 URL 验收。 |
| Mac 自动化 #59 | 默认规则为空已观察；真实锁屏、合盖、外接屏触发未测。 |
| 升级与凭据 #16/#17/#32 | 缺独立测试账号与发行签名升级产物。没有写假账号 token、删除真实凭据或授权测试程序长期读取钥匙串。 |
| TLS #30 | 受控真实 TLS 换证拒绝通过；真实电视显式重新信任和配对未测。 |

本轮创建的“新建快捷指令 3”已删除，库内数量恢复为原来的 15。原有快捷指令保留。临时 `Package.resolved` 已移到私有 QA 目录，运行数据和历史资料保留。

独立证据审计曾指出轮数、签名阶段和提交归属不一致，已在本文修正。该审计模型实际标识未暴露。剩余最关键边界是顶部一行修复待复审，以及上述未测系统、账号、设备与发行条件。完整标准继续以 [Mac 交接文档](mac-handover.md) 为准，不提前关闭 issue。

<p align="center"><img src="assets/brand/app-icon.png" alt="Codex Jet：Codex usage 额度监测与 Tibo reset 提醒" width="112"></p>

# Codex Usage 与 Tibo Reset 监测工具 — Codex Jet

**在 macOS 菜单栏查看 Codex 剩余额度、消耗速度、每小时分模型 token 用量与 Tibo 临时重置信号。** Codex Jet 把个人账户的 usage 监测与 codex-reset.com 的全局重置雷达放在一起，帮助判断额度能否撑到下次截止，以及届时预计还剩多少。

[English](README.md) · [下载 macOS 通用版](https://github.com/StarrHuang/codex-jet/releases/latest) · [安装与更新](docs/deployment.md) · [验证方法](docs/verification.md)

需要 macOS 14+，并已安装、登录 Codex CLI。支持 Apple Silicon 和 Intel，界面支持简体中文、英语、日语、韩语，也可跟随系统语言。

## Codex usage：额度监测、消耗曲线与 token 统计

- **当前额度**：读取账户实际返回的额度窗口与剩余百分比，区分有效、过期和缺失读数。
- **菜单栏插件**：紧凑显示时钟 Logo、当前余量与最近截止倒计时；超过 48 小时改用天数。
- **额度消耗曲线**：下拉面板默认显示完整曲线，保留时间范围、采样空档和最近额度变化。
- **每小时分模型 token**：基于本机 Codex 会话用量记录，查看输入、其中缓存、输出、其中推理与总量；子项不重复相加。
- **本地账户历史**：按账户保存额度观测，从实际开始记录时建立历史，不补造过去数据。

## Codex burn rate：现有额度能撑到重置吗？

主窗口与插件共用同一套“当前余量 → 最近截止 → 能否撑到 → 预计剩余与速度建议”。近期实测速率与本周期平均估算分别标注，不混为同一个结论。

最近截止取正常周重置、有效且有时间的官方临时公告窗口、同账户有效储备卡到期中最近的未来目标。**卡到期需要手动兑换，不会自动补额**；单纯的站点观察不作为个人账户的重置倒计时。

状态 Logo 用红黄绿和灰色表达：有余量缓冲、接近目标速度、可能提前用尽或已经耗尽、暂时无法判断。若计划在目标前用尽，面板显示相应的速度调整参考；线性预测取决于后续工作量与服务规则，不能保证兑现。

额度时钟的弧长表示实际读到的余量，指针转速表示近期消耗快慢，不是实际钟点。公告外环只作提醒，账户实际读数才会改变余量。

## Codex Tibo reset：临时重置提醒与全局雷达

想追踪 **Codex Tibo reset**？应用通过 [codex-reset.com](https://codex-reset.com/zh/) 展示临时重置公告、来源链接、可用时间、置信度及更新时间。这里的“Tibo reset”指雷达追踪的额外重置信号与公告，不是一种单独的账户权益。

有有效未来目标时可显示倒计时、时间换算依据和重置提醒；没有明确时间、来源过期、历史或待核验信号会保留相应状态。储备卡到期与手动用卡情景单独列出。

**全局重置信号不能证明你的账户已经到账。** 个人额度以本机已登录账户的真实读数为准。

## 安装与更新

从 [GitHub Releases](https://github.com/StarrHuang/codex-jet/releases/latest) 下载通用安装包，或克隆后安装：

```sh
git clone https://github.com/StarrHuang/codex-jet.git
cd codex-jet
./scripts/install.sh
```

默认安装到 `~/Applications/Codex Jet.app`。更新前先退出应用，再执行相同脚本；安装器会验证校验和、签名与 CPU 架构。每台 Mac 使用自己的 Codex 登录与本地历史，不自动同步账户或历史。安装包使用 ad-hoc 签名，尚未使用 Apple Developer ID 公证。更多选项见[部署说明](docs/deployment.md)。

## 常见问题与数据边界

**Token 数能换算成订阅额度吗？** 不能。token 来自本机记录活动，可能跨账户或供应商；额度百分比来自当前账户。应用不按 token 比例分摊各模型的订阅额度。空白小时表示没有记录，不保证真实用量为零。

**会自动兑换卡或消耗额度吗？** 不会。储备卡需要手动兑换，应用不发起模型生成请求或自动消耗额度。

**数据存在哪里？** 账户额度历史保存在 `~/Library/Application Support/CodexReset/history.json`，用账户哈希分区，不存账户邮箱；哈希不等于匿名化保证。应用不上传额度历史或对话内容。公共雷达请求不包含个人额度或账户数据。

## 致谢与独立性

Codex Jet 是独立社区项目，与 OpenAI、Tibo、codex-reset.com 无隶属或官方背书关系。

- 感谢 [codex-reset.com](https://codex-reset.com/zh/) 提供公共全局重置雷达、信号与时间线。
- 参考 Tokei 的紧凑额度卡片呈现；不包含 Tokei 源码或美术素材。
- 参考 [CodexBar](https://github.com/steipete/CodexBar) 的周期用量节奏比较和产品思路，当前实现独立编写。

手机配对功能目前是源码预览，使用服务器收件箱验证；详见 [iPhone 提醒接入说明](docs/iphone-reminders.md)，后台推送尚未接通。

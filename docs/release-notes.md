# Codex Jet 0.20.1 — Codex Usage & Tibo Reset Monitor

- 时钟指针改用 Core Animation 合成层，保留实测速度映射；不可见、停用及减少动态效果时停止旋转。
- 历史 JSON 保存移至后台，复用保存结果，避免刷新后再次完整读取。保留全部历史、账户隔离和原子写入。
- token 缓存随七天统计窗口清理过期记录，保留模型上下文、未来记录与错误提示。曲线、提醒、采样周期和四种语言保持兼容。
- 新增可复现的性能采样与合成基准。详细结果和测量口径见 `docs/performance-2026-11-02.md`。

English

- Rotate the quota-clock hand with Core Animation while preserving the measured-pace mapping; stop rotation when hidden, inactive, or Reduce Motion is enabled.
- Move history JSON I/O off the main actor and reuse the persisted result, eliminating a second full-file read per refresh. Preserve complete history, account isolation, and atomic writes.
- Prune expired usage records from the rolling seven-day token cache while retaining model context, future records, and warnings. Keep charts, reminders, polling intervals, and all four languages.
- Add repeatable process sampling and synthetic benchmarks. See `docs/performance-2026-11-02.md` for results and measurement definitions.

# Codex Jet 0.20.0 — Codex Usage & Tibo Reset Monitor

Night-mode presentation has improved across the app, including chart grids, secondary text, legends, and reset countdown contrast. The mint clock and quota status colors retain their established meanings.

During a temporary reset announcement, the popover presents a compact overview with the current quota, nearest reset deadline, and pace guidance. Supporting details remain expandable, while the quota-consumption curve stays visible by default. The display changes do not alter quota or history calculations.

This release continues direct macOS distribution; it is not an App Store build.

# Codex Jet 0.19.0 — Codex Usage & Tibo Reset Monitor

Japanese and Korean interface catalogs join Simplified Chinese and English. The catalogs use machine-assisted translation with reviewed key terminology; individual wording may still need refinement.

The static mint clock mark now shares one vector source across the app and generated macOS icon. The menu bar keeps its quota state colors in light appearance with a darker palette. Reset reminders use a persistent, across-desktops window with a prominent target countdown and direct acknowledge and snooze controls.

The menu bar popover keeps the full quota-consumption curve visible by default. Quota measurement, target selection, pace calculations, and account data boundaries are unchanged.

# Codex Jet 0.18.0 — Codex Usage & Tibo Reset Monitor

A native macOS Codex usage monitor with hourly model token statistics, quota burn-rate forecasts, and Tibo reset alerts from codex-reset.com.

The main window and compact quota views now share an overview of the current balance, nearest eligible reset target, and measured pace. It uses the existing deadline and pace results; quota forecasting and target selection are unchanged.

Announcements use concise summaries, with supporting details available on expansion. The repeated balance displays and 3D quota instrument are removed from the overview. Immediately after the quota overview and announcement summary, the popover keeps the full quota-consumption curve visible by default, including its time range, legend, and change markers; lower sections remain available by scrolling.

The menu bar now uses a native quota logo instead of the emoji status lamp. It retains the existing runway status colors. The AppIcon is unchanged.

# Codex Jet 0.17.0

The quota display now uses a clock face: the colored arc shows the latest observed balance, and the hand's speed represents recent measured quota use. The clock does not show actual time; only a new account reading changes the displayed balance. A brief outer rim marks a reset announcement without changing the quota arc. The compact status-bar indicator keeps its existing behavior.

Codex Jet also gets a new app icon. Simplified Chinese and English, quota status colors, reset targets, and local reminders remain available.

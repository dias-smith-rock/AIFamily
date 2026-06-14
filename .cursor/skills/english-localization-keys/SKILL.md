---
name: english-localization-keys
description: >-
  WeFamily iOS localization using English snake_case String Catalog keys split by
  domain table. Use when adding UI strings, L10n, Localizable.xcstrings, i18n,
  多语言, 本地化, or localization/keys.json.
---

# 英文 Key 多语言规范（WeFamily iOS）

> **运行时架构（冻结）**：`.cursor/rules/app-localization.mdc` — `LocalizedStringResource`、`appLocaleEnvironment`、`.id(selectedLanguage.id)` 等**不得改动**。

## 核心规则

**Catalog Key 使用英文 snake_case**（如 `settings_location_reporting_nav_title`），**禁止**新增中文或英文句子作 Key。

| 资源 | 路径 |
|------|------|
| 映射表 | `localization/keys.json` |
| 分域 Catalog | `reminder/Localization/{Common,Settings,Auth,...}.xcstrings` |
| Swift 访问层 | `reminder/Localization/L10n.swift` + `L10n+*.swift` |
| 迁移脚本 | `scripts/migrate_i18n_to_english_keys.py` |
| 补充词条 | `scripts/add_missing_i18n_entries.py` |
| Lint | `scripts/lint_i18n_keys.py` |

## Key 命名

```
{domain}_{feature}_{element}[_{qualifier}]
```

domain：`common` `settings` `auth` `schedule` `family` `location` `vip` `todo` `feedback` `assistant`

## SwiftUI 写法

```swift
// View — 依赖根节点 .appLocaleEnvironment + .id(selectedLanguage.id)
Text(L10n.Settings.locationReportingNavTitle.localized)

// Alert / Button — 优先 L10n.Entry 或 .localized（LocalizedStringResource）
.alert(L10n.Common.notice, ...) { Button(L10n.Common.ok) {} }

// 带插值 — 需 @Environment(\.locale)
Text(L10n.Todo.overdueCount.formatted(locale: locale, count))

// TextField（iOS 18）— 用 AppLocalized.string
TextField(AppLocalized.string(L10n.Common.nicknameSuchAsMum, locale: locale), text: $name)

// ViewModel
AppLocalized.localized(L10n.Auth.sessionAbnormalRetry)
L10n.Family.groupName.string(locale: locale)
```

自定义组件参数使用 `L10n.Entry` 或 `LocalizedStringResource`，禁止裸 `String` 中文。

## 新增词条流程

1. 在 `localization/keys.json` 增加一行（或运行 `add_missing_i18n_entries.py` 模板）。
2. 写入对应 `{Table}.xcstrings` 的 **9 语言** localizations。
3. 在 `L10n+{Table}.swift` 增加 `static let … = Entry(key: "…", table: .…)`.
4. 运行 `python3 scripts/lint_i18n_keys.py`。

## 禁止

- View 层 `Text("中文")` 或裸 snake_case 字符串
- 修改 Supabase / API `rawValue`、调试日志为非 UI 标识

## 自检

```bash
python3 scripts/lint_i18n_keys.py
```

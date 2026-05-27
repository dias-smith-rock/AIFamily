---
name: chinese-localization-keys
description: >-
  Enforces WeFamily iOS localization using Chinese literals as String Catalog keys
  (Localizable.xcstrings). Use when adding or changing UI strings, LocalizedStringKey,
  enums localizedName, AppLocalized, multi-language, i18n, 多语言, 本地化, or
  Localizable.xcstrings.
---

# 中文 Key 多语言规范（WeFamily iOS）

## 核心规则

**用中文原意作为多语言的 Key。** 禁止新增英文语义 Key（如 `btn_save`、`task_status_pending`、`tab_home`）。

| 资源 | 路径 |
|------|------|
| String Catalog | `reminder/Localizable.xcstrings` |
| 批量迁移脚本 | `scripts/migrate_i18n_chinese_keys.py` |
| 补充词条脚本 | `scripts/add_i18n_keys.py` |

项目**没有**独立的 `Localizable.strings`；所有翻译写在 `Localizable.xcstrings`，**左侧 Key 必须与 Swift 代码中的中文字符串 100% 一致**（含标点、空格）。

## SwiftUI 写法

```swift
// ✅
Text("保存")
Section("基础信息")
TextField("邮箱", text: $email)
navigationTitle("编辑资料")

// ❌
Text("btn_save")
Text(LocalizedStringKey("task_status_pending"))
```

自定义组件的参数类型必须是 `LocalizedStringKey`，不能是 `String`（否则环境 `\.locale` 无法翻译）：

```swift
// ✅
struct FormRow: View {
    let title: LocalizedStringKey
}

// ❌
struct FormRow: View {
    let title: String
}
```

## 枚举与计算属性

`localizedName` / `titleKey` 等返回 **中文 Key**，不要用 `rawValue` 或英文字面量：

```swift
var localizedName: LocalizedStringKey {
    switch self {
    case .pending: "待接受"
    case .completed: "已完成"
    }
}
```

`rawValue` 仅用于 **API / 数据库 / UserDefaults**（如 `in_progress`、`male`），不得直接用于 UI。

## 带变量的字符串

代码与 Catalog Key 的占位符必须对应：

| Swift | Catalog Key（示例） |
|-------|---------------------|
| `Text("提前 \(minutes) 分钟")` | `提前 %lld 分钟` |
| `Text("来自 \(name)")` | `来自 %@` |
| `"\(hours)小时\(remainder)分钟"` | `%lld小时%lld分钟` |

时长、提醒等复用：`TaskDurationText.swift`、`TaskReminderLabel.swift`、`TaskDurationFormatting.swift`。

非 View 上下文（ViewModel、错误文案）使用：

```swift
String(localized: "网络连接失败，请稍后重试。")
// 或需指定 locale 时：
String(localized: String.LocalizationValue("保存"), locale: appSettings.appLocale)
```

View 层优先 `Text("…")` + 根节点 `.environment(\.locale, appSettings.appLocale)`（见 `reminderApp.swift`），避免 `AppLocalized.string` 把文案提前解析成 `String`。

## 新增词条流程

1. 在 Swift 中写**最终中文文案**作为 Key。
2. 在 `Localizable.xcstrings` 添加同名 Key，填写 `en`、`zh-Hant` 等翻译。
3. 若误用英文 Key，运行 `python3 scripts/migrate_i18n_chinese_keys.py` 或手动将 Catalog 中英 Key 合并为中文 Key 后删除英文 Key。

## 禁止改动的字符串

- Supabase / JSON 字段名、`CodingKeys`、`rawValue`（持久化）
- SF Symbol 名、`Image("AppLogo")` 等资源名
- 语言选择器中的语言自称（如 `English`、`Español`）
- 调试日志、通知内部 `skipReason` 等非 UI 标识

## 自检清单

- [ ] 无新增 `snake_case` / 英文句子类 UI Key
- [ ] 枚举 UI 文案走 `localizedName`，非 `rawValue`
- [ ] 表单封装组件文本参数为 `LocalizedStringKey`
- [ ] `Localizable.xcstrings` 中 Key 与 Swift 字面量完全一致
- [ ] 插值字符串 Catalog 使用 `%lld` / `%@` 与代码一致

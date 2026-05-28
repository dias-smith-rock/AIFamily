---
name: native-dialogs
description: >-
  Enforces WeFamily iOS dialog patterns: use SwiftUI .alert or .confirmationDialog
  only—never .popover or custom bubble overlays for confirmations or action menus.
  Use when adding or changing alerts, confirmation dialogs, popover, 弹窗, 气泡,
  删除确认, destructive actions, action sheets, or refactoring dialog UI.
---

# 原生弹窗规范（WeFamily iOS）

遵循 [Apple HIG — Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) 与 [Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)。与 [chinese-localization-keys](chinese-localization-keys/SKILL.md) 配合：弹窗内所有 Title、Message、Button 文案必须使用**中文原文作为 Key**。

## 禁止项

| 禁止 | 原因 |
|------|------|
| `.popover` 做确认 / 多选操作 | iPad 上呈气泡，与「高危确认应居中」不一致；组织切换等已改为 `confirmationDialog` |
| 自定义 ZStack 半透明卡片模拟 Alert | 非系统行为，无障碍与样式不统一 |
| `String(localized: "中文")` / `AppLocalized.string(...)` 作为 Alert 标题或按钮（View 层） | 应写 `Text("中文")`、`Button("中文")`，由 `\.locale` + Catalog 翻译 |
| 把 `LocalizedStringKey` 降级为普通 `String` 再塞进 Alert | 破坏多语言 |

**允许保留（不属于本规范替换范围）：**

- `.sheet` / `.fullScreenCover`：创建/编辑表单、解散群组等多步流程
- `.menu`：纯展示型下拉（若需大量列表 + 勾选，优先 `confirmationDialog` 或 `sheet` 列表，勿恢复自定义 popover 面板）
- 加载遮罩（如转移群主时的 `ProgressView` 叠层）——不是确认弹窗

## 类型选择（必判）

### 场景 A → `.alert`（居中警告）

用于**单一高危或强提示**，通常只有 1 个破坏性/主操作 + 取消：

- 删除任务、退出群组、注销账号、解散确认
- 不可逆操作的二次确认（`role: .destructive`）
- 纯通知型（如「权限变更通知」+「立即查看」+「关闭」）

```swift
.alert("删除任务", isPresented: $isShowingDeleteAlert) {
    Button("仅删除此任务", role: .destructive) {
        Task { await performDelete(scope: .singleOnly) }
    }
    Button("取消", role: .cancel) { }
} message: {
    Text("此操作无法撤销。")
}
```

- 破坏性按钮**必须** `role: .destructive`（系统红色）
- 取消**必须** `role: .cancel`
- 重复任务等多档删除：仍在 **同一 `.alert`** 内放多个 `destructive` 按钮（见 `TaskDetailView`）

### 场景 B → `.confirmationDialog`（底部操作表）

用于**多个并列操作**（≥2 个有意义选项 + 取消）：

- 组织切换（列表 +「创建新组织」）
- 循环任务「仅修改此任务 / 修改此任务及以后」
- 扫码方式（相机 / 相册）
- 转移群主确认（`确认转移` + `取消`）

```swift
.confirmationDialog("切换组织", isPresented: $isShowingSwitcher, titleVisibility: .visible) {
    ForEach(organizations) { organization in
        Button(organization.name) { onSelect(organization) }
    }
    Button("创建新组织") { isShowingCreateOrganization = true }
    Button("取消", role: .cancel) { }
}
```

- `titleVisibility: .visible` 当标题需要明确语境时加上
- 需要说明时使用 `message: { Text("请选择删除范围。") }`
- iPhone 为底部 sheet；iPad 可能仍为 popover 形态——属系统适配，**不要**为此再写自定义 `.popover` 面板

## 多语言（与 Catalog 绑定）

| 规则 | 说明 |
|------|------|
| 资源文件 | `reminder/Localizable.xcstrings`（无独立 `Localizable.strings`） |
| Key | 与 Swift 中字面量 **100% 一致**（标点、全角符号） |
| View 层 | `.alert("删除任务", ...)`、`Button("取消", role: .cancel)` |
| 带参数 message | Catalog 用 `%@` / `%lld`；运行时可用 `String(format: String(localized: "您已成为「%@」的创建者…"), name)`，Key 仍为中文 |
| 动态错误正文 | `Text(errorMessageFromServer)` 可用 `String`；**固定 UI 文案**仍用中文 Key |

新增文案流程：先写 Swift 中文 Key → 再在 `Localizable.xcstrings` 补 `en`、`zh-Hant` 等。

## 项目内参考实现

| 场景 | 文件 |
|------|------|
| 删除任务 Alert | `reminder/Views/Schedule/TaskDetailView.swift` |
| 循环任务修改范围 | `reminder/Views/Schedule/CreateTaskView.swift` |
| 组织切换操作表 | `reminder/Views/Schedule/OrganizationSwitcherMenu.swift` |
| 创建者权限通知 Alert | `reminder/ContentView.swift` |
| 退出 / 注销 / 提示 | `reminder/Views/Family/FamilyView.swift`、`MineView.swift` |
| 扫码方式 | `HouseholdSelectionView.swift`、`OrgRoutingView.swift` |
| 转移群主 | `reminder/Views/Family/TransferOwnershipView.swift` |

## 重构检查清单

- [ ] 全仓库无 `.popover` 用于确认或操作菜单（`rg '\.popover' reminder`）
- [ ] 无自定义「仿 Alert」全屏遮罩组件（除非改为 `.alert`）
- [ ] 高危操作使用 `.alert` + `role: .destructive`
- [ ] 多选项使用 `.confirmationDialog` + `role: .cancel`
- [ ] 未将表单类流程误改为 Alert（仍用 sheet）
- [ ] 弹窗文案为中文 Key，且已同步 `Localizable.xcstrings`

## 常见错误

```swift
// ❌ iPad 气泡式确认
.confirmationDialog(...) { }  // 用于「仅删除 + 取消」——应改为 .alert

// ❌ 自定义气泡
.popover(isPresented: $show) { VStack { ... } }

// ❌ View 层英文/间接本地化
.alert(AppLocalized.string("删除任务", locale: locale), ...)
Button(String(localized: "取消"), role: .cancel) { }

// ✅
.alert("删除任务", isPresented: $show) {
    Button("取消", role: .cancel) { }
}
```

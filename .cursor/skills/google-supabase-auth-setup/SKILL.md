---
name: google-supabase-auth-setup
description: Configure and troubleshoot Google OAuth with Supabase for iOS apps. Use when users mention Google login, Supabase Auth provider setup, OAuth redirect URLs, or errors like "missing OAuth secret" and callback failures.
---

# Google + Supabase Auth Setup

## 适用场景

当用户提到以下关键词时使用本 Skill：
- Google 登录
- Supabase Auth / Providers
- OAuth 重定向失败
- iOS Deep Link 回调失败
- `missing OAuth secret` / `validation_failed`

## 快速结论

Google 登录在 Supabase 中必须配置：
- `Client ID`（Google Web OAuth 客户端）
- `Client Secret`（同一客户端）

仅配置 `Client ID` 会报：
- `Unsupported provider: missing OAuth secret`

## 标准配置流程

1. 在 Google Cloud 创建/使用 `OAuth 2.0 Client ID`，类型必须是 `Web application`。
2. 在该 Google OAuth 客户端里设置：
   - `Authorized redirect URIs` 包含：
     - `https://<PROJECT-REF>.supabase.co/auth/v1/callback`
3. 在 Supabase 控制台 `Authentication -> Providers -> Google`：
   - 填入 Google `Client ID`
   - 填入 Google `Client Secret`
   - 启用 Provider 并保存
4. 在 Supabase `Authentication -> URL Configuration`：
   - `Additional Redirect URLs` 包含 iOS 回调，例如：
     - `aifamily://auth-callback`
5. 在 iOS 工程：
   - `Info.plist` 配置 URL Scheme（如 `aifamily`）
   - 登录代码使用同一回调地址：
     - `redirectTo: URL(string: "aifamily://auth-callback")`
   - App 处理回调 URL 并恢复 session

## iOS 侧建议实现（Supabase Swift）

```swift
try await SupabaseManager.shared.client.auth.signInWithOAuth(
    provider: .google,
    redirectTo: URL(string: "aifamily://auth-callback")
)
```

```swift
.onOpenURL { url in
    Task {
        _ = try? await SupabaseManager.shared.client.auth.session(from: url)
        await appRouter.refreshStateFromBackend()
    }
}
```

## 排障清单（按优先级）

1. **报错 `missing OAuth secret`**
   - 原因：Supabase Google Provider 未配置 `Client Secret`
   - 处理：补齐并保存 Secret
2. **点击登录无跳转**
   - 原因：按钮未调用 `signInWithOAuth`
   - 处理：检查点击事件和 async 调用链
3. **浏览器授权后无法回到 App**
   - 原因：iOS URL Scheme 未配置，或 `redirectTo` 与 Scheme 不一致
   - 处理：统一 `Info.plist` 与代码回调地址
4. **回到 App 但仍是未登录**
   - 原因：未在 `onOpenURL` 中执行 `session(from:)`
   - 处理：补 session 恢复和状态刷新
5. **Google 控制台报 redirect_uri_mismatch**
   - 原因：Google OAuth 客户端缺少 Supabase callback
   - 处理：添加 `https://<PROJECT-REF>.supabase.co/auth/v1/callback`

## 游客转正（linkIdentity）

匿名用户绑定 Apple/Google 使用 `linkIdentity()` / `linkIdentityWithIdToken()`，**必须**在 Supabase 开启 Manual Linking：

1. **线上项目**：Dashboard → **Authentication** → **Sign In / Providers** → **User Signups** → 打开 **Allow manual linking**
2. **本地 / 自托管**：`supabase/config.toml` 中 `enable_manual_linking = true`（或 `GOTRUE_SECURITY_MANUAL_LINKING_ENABLED=true`）
3. 同时确保 **Allow anonymous sign-ins** 已开启

未开启时报错：`Manual linking is disabled`（客户端会映射为友好文案）。

### Google / Apple 已被其他用户占用

游客 `linkIdentity` 时若 OAuth 已绑定另一 `auth.users`，GoTrue 返回 `Identity is already linked to another user`。

**Family Sync 产品策略（不提供切换登录、不合并数据）：**

- 客户端识别该错误，弹出专用说明（`auth_identity_already_linked_*`）
- 引导用户：**换一个 Google/Apple 绑定**，或**继续游客**（当前群组保留在本游客 UUID）
- **禁止**自动 fallback 为 `signInWithOAuth` 登录已有账号（会丢弃当前游客 session/群组上下文）

参考：[Identity Linking](https://supabase.com/docs/guides/auth/auth-identity-linking) · [Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous)

## 输出要求（给用户的回复模板）

- 先判断是「代码问题」还是「控制台配置问题」
- 给出最小可执行修复步骤（3-5 条）
- 如有报错文案，逐条对照解释
- 最后附 1 条验证路径：
  - `点击登录 -> 授权 -> 回到 App -> session 有效 -> 路由切换成功`

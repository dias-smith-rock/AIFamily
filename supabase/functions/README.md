# Supabase Edge Functions (Invite Links)

本目录包含两条函数：

- `generate-invite-link`：签发短时邀请链接（JWT + nonce）
- `consume-invite-link`：校验并一次性消费邀请链接（防重放）

## 与 iOS 客户端参数对齐

`generate-invite-link` 请求体：

```json
{
  "token": "invite-xxx",
  "channel": "wechat",
  "expiresInSeconds": 900
}
```

这与当前 iOS `SupabaseInviteLinkService` 保持一致：`token / channel / expiresInSeconds`。

## 必需环境变量

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INVITE_JWT_SECRET`（至少 32 字符）
- `INVITE_BASE_URL`（可选，默认 `https://aifamily.app/invite`）

## 部署命令

```bash
supabase functions deploy generate-invite-link
supabase functions deploy consume-invite-link
```

## 建议的调用方式

1. App 调 `generate-invite-link` 获取 `url`
2. 执行端打开该 `url`，取到 `sig`
3. 执行端调 `consume-invite-link` 提交 `sig`
4. 服务端校验签名、过期时间、nonce，并将 nonce 标记为已使用

## consume-invite-link 调用示例

- iOS 示例：`reminder/Services/InviteLinkConsumeClient.swift`
- H5 示例：`supabase/functions/examples/consume-invite-link.h5.js`

### 错误码映射建议

- `200`：消费成功，返回 `valid/inviteToken/channel/nonce`
- `409`：已消费（应提示“链接已被使用，请重新生成”）
- `410`：已过期（应提示“链接已过期，请重新生成”）
- `400/404`：无效或篡改
- `401`：客户端鉴权失败

## 安全说明

- JWT 负责防篡改（HMAC-SHA256）
- `exp` 限制有效期
- `invite_link_nonces.used_at` 实现一次性消费

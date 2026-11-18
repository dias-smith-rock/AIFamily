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

### Task recognition context and text fallback

`POST parse-create-task-from-text` accepts `{text, reference_instant, selected_calendar_day, time_zone, locale}`. `text` is 1–6000 Unicode characters, `reference_instant` is an ISO8601 instant with explicit offset, `time_zone` is an IANA timezone, `locale` is a language identifier, and optional `selected_calendar_day` is `YYYY-MM-DD`. Relative dates use the reference instant in the supplied timezone; the calendar selection only locates image content. Unknown clock times remain null. The response is `{success:true,task:{...}}`, with the same fields consumed by `AIParsedTaskPayload`. Recognition never writes tasks.

Images accept the same optional context alongside existing `image_url`, `target_date`, and `recognition_region`. Supplying any modern context field requires the complete reference/timezone/locale context. Legacy image requests use server current time with the historical Asia/Hong_Kong timezone default; `target_date` remains a cell-selection hint. OCR text is no longer included in logs or responses.

Both endpoints require a real, non-anonymous user access token in `Authorization: Bearer ...`; tokens are verified using Supabase Auth `/auth/v1/user`, rather than trusting a Bearer prefix. Keep gateway JWT verification enabled for deployment. Runtime secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `DEEPSEEK_API_KEY`; optional `DEEPSEEK_API_BASE_URL` and `DEEPSEEK_TASK_MODEL` retain their existing defaults. Images additionally require `OCR_API_KEY` (and optional `OCR_MODEL`). Auth, image download and provider requests time out after 8, 15 and 30 seconds respectively. Provider failure details and task content are not returned as errors. Each warm function instance allows ten requests per authenticated user per minute; this is basic abuse protection, not a distributed quota—configure gateway quotas separately before a broad launch.

Local verification (no live provider calls):

```sh
deno test --allow-env supabase/functions/tests/task-parsing_test.ts
deno check supabase/functions/parse-create-task-from-text/index.ts supabase/functions/parse-create-task-from-images/index.ts
```

When a target **test project** is authorized, deploy using `supabase functions deploy parse-create-task-from-text --project-ref <test-project-ref>` and likewise for `parse-create-task-from-images`; never pass `--no-verify-jwt`. No deployment is performed by this implementation.

Image downloads accept signed/public Storage object URLs from the configured `SUPABASE_URL` origin, including existing fallback attachment buckets; redirects are rejected. HTTPS is required except when the configured project is a localhost development instance. This matches the app's upload/sign workflow and prevents arbitrary server-side URL fetches. Downloaded images are limited to 12 MiB and JPEG/PNG/WebP/HEIC/HEIF content types.

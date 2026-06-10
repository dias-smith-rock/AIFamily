# WeSync 订阅（StoreKit 2 + 服务端校验）部署检查清单

适用版本：服务端校验 + RLS 收紧（`verify-apple-subscription` Edge Function + `activate_premium_from_apple` RPC）。

---

## 一、部署前准备

| 项 | 要求 | 如何确认 |
|---|---|---|
| Bundle ID | `com.aifamilygroup.reminder` | Xcode → Target → General |
| Product ID | `wesync.vip.monthly` / `wesync.vip.yearly` | App Store Connect → 订阅 |
| App Apple ID | 数字 ID（如 `6775353963`） | App Store Connect → App 信息 → Apple ID |
| Supabase 表 | `subscription_orders`、`user_entitlements`、`households` 已存在 | Table Editor |
| `households.creator_id` | **auth user id**（非 membership id） | 抽样查一行 creator 与 `auth.users` 对齐 |

---

## 二、部署步骤（按顺序）

### Step 1 — 执行 SQL 迁移

**文件：**

- `reminder/Services/Supabase/migrations/20260610_subscription_server_rls.sql`
- 或 `supabase/migrations/20260610120000_subscription_server_rls.sql`

**方式 A：Supabase Dashboard**

1. SQL Editor → New query
2. 粘贴整份迁移 SQL → Run
3. 应无报错

**方式 B：Supabase CLI**

```bash
cd /path/to/AIFamily
supabase db push
# 或仅执行该 migration（视你项目链接方式而定）
```

**迁移做了什么：**

- `subscription_orders` / `user_entitlements`：开启 RLS，authenticated 仅 **SELECT 本人**
- `households`：触发器禁止非 `service_role` 修改 `is_premium`
- 创建 RPC `activate_premium_from_apple`（仅 `service_role` 可执行）
- `external_transaction_id` 唯一索引（幂等）

---

### Step 2 — 验证数据库对象

在 SQL Editor 执行：

```sql
-- 1. RPC 是否存在
select proname, prosecdef
from pg_proc
where proname = 'activate_premium_from_apple';

-- 2. RLS 是否开启
select relname, relrowsecurity
from pg_class
where relname in ('subscription_orders', 'user_entitlements');

-- 3. 触发器是否存在
select tgname
from pg_trigger
where tgname = 'trg_guard_household_is_premium';

-- 4. 唯一索引
select indexname
from pg_indexes
where indexname = 'subscription_orders_external_transaction_id_uidx';
```

期望：RPC 存在且 `prosecdef = true`；两表 `relrowsecurity = true`；触发器与索引均存在。

---

### Step 3 — 部署 Edge Function

```bash
cd /path/to/AIFamily
supabase link --project-ref <你的 project ref>   # 若尚未 link
supabase functions deploy verify-apple-subscription
```

**`supabase/config.toml` 应包含：**

```toml
[functions.verify-apple-subscription]
enabled = true
verify_jwt = true
```

Edge Function 会自动获得 `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_ROLE_KEY`（Supabase 注入）。

**可选 Secrets（生产建议）：**

```bash
supabase secrets set APP_APPLE_ID=6775353963
```

> Production 环境验签时 Apple 库需要 `appAppleId`；Sandbox 本地测试通常可不设，代码内有默认值。

---

### Step 4 — 确认 Edge Function 可访问

Dashboard → **Edge Functions** → `verify-apple-subscription` → 状态为 Active。

本地冒烟（需有效用户 JWT，见下方「手动 curl 测试」）。

---

### Step 5 — iOS / App Store Connect

| 项 | 操作 |
|---|---|
| In-App Purchase Capability | Xcode → Target → Signing & Capabilities → + In-App Purchase |
| 本地测试 | Scheme → Run → Options → StoreKit Configuration → `WeSyncSubscriptions.storekit` |
| 沙盒 / TestFlight | Connect 中订阅商品状态为「准备提交」或可测试；使用 Sandbox 账号 |

---

### Step 6 — 端到端验收（推荐顺序）

1. **模拟器 + `.storekit`**：购买月付 → 应弹出订阅成功
2. **Supabase 数据**：见「三、验收 SQL」
3. **App 内**：`hasPremiumAccess == true`，VIP 页显示已激活
4. **恢复购买**：删 App 重装 → Restore → 权益恢复
5. **RLS 防伪造**：见「四、安全验收」

---

## 三、验收 SQL

购买成功后，用**你的 user id** 替换 `<USER_UUID>`：

```sql
-- 个人权益
select user_id, is_pro, pro_expires_at
from user_entitlements
where user_id = '<USER_UUID>';

-- 最近订单
select id, plan_purchased, external_transaction_id, environment, expires_at, paid_at
from subscription_orders
where payer_id = '<USER_UUID>'
order by paid_at desc
limit 5;

-- 作为创建者的群组是否 Premium
select id, name, creator_id, is_premium
from households
where creator_id = '<USER_UUID>';
```

期望：

- `user_entitlements.is_pro = true`，`pro_expires_at` 在未来
- `subscription_orders` 有 `apple_iap` / `completed` 记录，`external_transaction_id` 非空
- 你创建的群组 `is_premium = true`

---

## 四、安全验收（RLS 是否生效）

在 SQL Editor 用 **authenticated** 角色模拟（或客户端直接尝试，迁移后应失败）：

```sql
-- 应失败：客户端不能直接给自己写 VIP
insert into user_entitlements (user_id, is_pro, pro_expires_at)
values (auth.uid(), true, now() + interval '1 year');

-- 应失败：客户端不能直接改群组 Premium
update households set is_premium = true where creator_id = auth.uid();
```

期望：报 RLS 或触发器错误（`is_premium may only be updated by the server`）。

---

## 五、排查步骤（按症状）

### 症状 A：App 提示「购买失败，请稍后重试」

| 步骤 | 检查 |
|------|------|
| 1 | Xcode 控制台 / Supabase **Edge Functions → Logs** 是否有 `verify-apple-subscription` 调用 |
| 2 | 用户是否已登录（非访客） |
| 3 | Edge Function 是否已 deploy |
| 4 | 迁移是否已执行（RPC 不存在会 500） |

---

### 症状 B：Edge Function 401 Unauthorized

| 原因 | 处理 |
|------|------|
| 未带 JWT | 确认 App 已登录；`functions.invoke` 会自动带 session |
| JWT 过期 | 重新登录 |
| `verify_jwt = false` 且 handler 校验失败 | 保持 `verify_jwt = true` |

---

### 症状 C2：Edge Function 500 — `plan_purchased` is of type subscription_plan but expression is of type text

**原因：** RPC 将 `text` 直接写入 `subscription_orders.plan_purchased`（枚举列）。

**处理：** 在 Supabase SQL Editor 执行 `20260611_fix_activate_premium_plan_cast.sql`（或 `supabase db push`）。

---

### 症状 C3：Edge Function 500 — `invalid input value for enum order_status: "completed"`

**原因：** 库表 `order_status` 枚举值为 `success`，不是 `completed`。

**处理：** 执行 `20260612_fix_activate_premium_order_status.sql`（或 `supabase db push`）。

---

### 症状 C：Edge Function 500 — `function activate_premium_from_apple does not exist`

**原因：** SQL 迁移未执行。

**处理：** 执行 `20260610_subscription_server_rls.sql`。

---

### 症状 D：Edge Function 500 — `forbidden` / `42501`

**原因：** RPC 未授予 `service_role`，或 JWT role 不是 service_role。

**处理：**

```sql
grant execute on function public.activate_premium_from_apple(
  uuid, text, integer, text, text, text, timestamptz, timestamptz
) to service_role;
```

确认 Edge Function 使用 `SUPABASE_SERVICE_ROLE_KEY` 创建 admin client。

---

### 症状 E：Edge Function 500 — Apple 验签失败

| 可能原因 | 处理 |
|----------|------|
| `environment` 不匹配 | Sandbox 购买须传 `environment: "sandbox"`；Xcode `.storekit` 本地测试为 `xcode`（x5c 仅 1 张证书） |
| `Invalid x5c certificate chain` | 多为 Xcode StoreKit 测试；须 deploy 含 Xcode 单证书验签的版本，且 App 传 `environment: "xcode"` |
| Production 缺 `APP_APPLE_ID` | `supabase secrets set APP_APPLE_ID=<数字 ID>` |
| Bundle ID 不一致 | Connect / Xcode 须为 `com.aifamilygroup.reminder` |
| 无法拉取 Apple 根证书 | Edge Function 需出网访问 `apple.com` |
| `Buffer is not defined` / `crypto.X509Certificate` | 官方 `@apple/app-store-server-library` 不兼容 Deno；当前函数使用 `jose` + `@peculiar/x509` 验签，须重新 deploy |
| `function activate_premium_from_apple does not exist` | 未执行 SQL 迁移 |

常见错误文案：`Verification failed`、`JWS signature`、`X509Certificate` 相关。Xcode DEBUG 控制台会显示服务端 `error` 字段（不再只有 generic 500）。

---

### 症状 F：400 Unsupported productId

**原因：** JWS 内 `productId` 不是 `wesync.vip.monthly` / `wesync.vip.yearly`。

**处理：** 对齐 App Store Connect Product ID 与 `StoreKitProductCatalog.swift`。

---

### 症状 G：购买成功但 App 仍非 Pro

| 步骤 | 检查 |
|------|------|
| 1 | `user_entitlements` 是否有行且 `is_pro = true` |
| 2 | 当前群 `households.is_premium`（若依赖群继承） |
| 3 | `pro_expires_at` 是否已过期 |
| 4 | 杀 App 重开或切换群组触发 `refreshPremiumStateAfterClaim` |

---

### 症状 H：群组未变 Premium

| 原因 | 处理 |
|------|------|
| 用户不是群组 `creator_id` | 仅**创建者**的群会被更新；成员群需创建者付费 |
| `creator_id` 存的是 membership id | 与线上一致性核对；当前实现按 **user id** 过滤 |
| 触发器误拦 service_role | 检查 `request.jwt.claim.role` 是否为 `service_role` |

---

### 症状 I：重复购买报唯一约束错误

**原因：** `external_transaction_id` 重复插入（幂等逻辑应跳过 INSERT）。

**处理：** 查 Edge Function 日志；确认 RPC 内「已存在则跳过 insert」分支正常。同一 transaction 重复调用应仍返回 success。

---

### 症状 J：模拟器商品价格为占位符 `$4.99`

**原因：** 未绑定 `.storekit` 或商品 ID 不匹配。

**处理：** Scheme → Run → Options → StoreKit Configuration → `WeSyncSubscriptions.storekit`。

---

## 六、日志查看位置

| 位置 | 内容 |
|------|------|
| Supabase Dashboard → Edge Functions → `verify-apple-subscription` → Logs | `activate_premium_from_apple` 错误、Apple 验签异常 |
| Xcode 控制台 `[StoreKit]` | `syncEntitlementsOnLaunch` / `transaction update` 错误 |
| Firebase Analytics | 事件 `vip_purchased` |

---

## 七、手动 curl 测试（高级）

> 需要真实用户 `access_token` 与一次购买后的 `signedTransactionInfo`（JWS 字符串）。通常用 App 日志临时打印或断点获取，仅用于联调。

```bash
curl -s -X POST \
  "$SUPABASE_URL/functions/v1/verify-apple-subscription" \
  -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "signedTransactionInfo": "<JWS_FROM_STOREKIT>",
    "environment": "sandbox"
  }'
```

成功响应示例：

```json
{
  "success": true,
  "plan": "pro_monthly",
  "productId": "wesync.vip.monthly",
  "transactionId": "...",
  "expiresAt": "2026-07-10T..."
}
```

---

## 八、发布检查清单（Checklist）

复制到 PR / 发布单逐项勾选：

```
[ ] SQL 迁移已在生产 Supabase 执行
[ ] activate_premium_from_apple RPC 存在且仅 service_role 可执行
[ ] subscription_orders / user_entitlements RLS 已开启
[ ] households is_premium 触发器已创建
[ ] verify-apple-subscription 已 deploy 且 verify_jwt = true
[ ] APP_APPLE_ID 已配置（Production）
[ ] Connect 订阅商品 ID 与代码一致
[ ] Xcode IAP Capability 已开启
[ ] 模拟器 .storekit 购买通过
[ ] Sandbox / TestFlight 购买通过
[ ] user_entitlements + subscription_orders 有正确数据
[ ] 创建者群组 is_premium = true
[ ] 客户端无法直接 insert user_entitlements（安全验收）
[ ] 恢复购买可用
```

---

## 九、相关代码路径

| 组件 | 路径 |
|------|------|
| SQL 迁移 | `reminder/Services/Supabase/migrations/20260610_subscription_server_rls.sql` |
| Edge Function | `supabase/functions/verify-apple-subscription/index.ts` |
| iOS 调用 | `reminder/Services/SubscriptionSupabaseSupport.swift` |
| StoreKit | `reminder/Services/StoreKitSubscriptionService.swift` |
| Product ID | `reminder/Utilities/StoreKitProductCatalog.swift` |
| 本地 StoreKit 配置 | `reminder/Configuration/WeSyncSubscriptions.storekit` |

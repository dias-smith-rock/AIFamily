# WeSync 订阅（RevenueCat + Supabase）部署检查清单

适用版本：RevenueCat SDK 购买/恢复 + Webhook 主路径 + 客户端 `sync-revenuecat-entitlement` 兜底。

---

## 一、RevenueCat Dashboard

| 项 | 值 |
|----|-----|
| Bundle ID | `com.aifamilygroup.reminder` |
| Entitlement | `premium` |
| Store 商品 | `wesync.vip.monthly` / `wesync.vip.yearly` |
| Offering | Current offering 含月付/年付 Package |
| Webhook URL | `https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook` |
| Webhook Authorization | 与 Supabase secret `REVENUECAT_WEBHOOK_AUTHORIZATION` 一致（如 `Bearer <secret>`） |
| Public API Key | 写入 iOS `Info.plist` → `RevenueCatAPIKey` |
| Secret API Key | `supabase secrets set REVENUECAT_SECRET_API_KEY=sk_...` |

`app_user_id` 规则：登录后 iOS 调用 `Purchases.logIn(supabaseUserId)`，Webhook 与 sync 均使用 **auth user UUID**。

---

## 二、Supabase 部署

### Step 1 — SQL

执行以下 migration（按顺序）：

1. [`20260617_revenuecat_entitlement_sync.sql`](reminder/Services/Supabase/migrations/20260617_revenuecat_entitlement_sync.sql)
2. [`20260618_user_entitlements_select_rls.sql`](reminder/Services/Supabase/migrations/20260618_user_entitlements_select_rls.sql)（客户端读取 `user_entitlements` 需此 RLS）

验证：

```sql
select proname from pg_proc
where proname = 'sync_user_entitlement_from_revenuecat';
```

### Step 2 — Secrets

```bash
supabase secrets set REVENUECAT_SECRET_API_KEY=sk_...
supabase secrets set REVENUECAT_WEBHOOK_AUTHORIZATION='Bearer your_shared_secret'
```

### Step 3 — Edge Functions

```bash
supabase functions deploy revenuecat-webhook
supabase functions deploy sync-revenuecat-entitlement
```

`supabase/config.toml` 应包含：

- `revenuecat-webhook` → `verify_jwt = false`
- `sync-revenuecat-entitlement` → `verify_jwt = true`

---

## 三、iOS

1. Xcode 已添加 SPM `RevenueCat/purchases-ios`
2. `Info.plist` 中 `RevenueCatAPIKey` 替换为 Dashboard Public Key
3. Scheme → StoreKit Configuration 可选（RevenueCat 亦支持沙盒 Apple ID）

---

## 四、数据流

| 路径 | 触发 | 写入 |
|------|------|------|
| Webhook 主路径 | RevenueCat 服务器 | `sync_user_entitlement_from_revenuecat` |
| 客户端兜底 | 登录 / 回前台 / 购买后（已登录） | `sync-revenuecat-entitlement` → 同上 RPC |
| 本机权限 | RevenueCat `CustomerInfo` | `AppRouter.hasPremiumAccess` 即时放行 |

组织继承仍读 `user_entitlements`（`household_creator_has_active_pro` RPC）。

---

## 五、验收（沙盒）

部署后可用 [`scripts/qa-revenuecat-sandbox.sh`](../scripts/qa-revenuecat-sandbox.sh) 模拟 Webhook / 客户端 sync（需 `SUPABASE_PROJECT_REF` 与 secrets）。

- [ ] 未登录可购买，立即解锁 Pro（5.1.1）
- [ ] 登录后 `user_entitlements.is_pro = true`
- [ ] RevenueCat Dashboard 发送测试 Webhook → Supabase Logs
- [ ] 沙盒过期后 Webhook `EXPIRATION` 或回前台 sync → `is_pro = false`
- [ ] 创建者 Pro 同步后，成员组织内继承 VIP
- [ ] Restore Purchases 可用

验收 SQL：

```sql
select user_id, is_pro, pro_expires_at, updated_at
from user_entitlements where user_id = '<UUID>';
```

---

## 六、相关代码

| 组件 | 路径 |
|------|------|
| iOS 订阅服务 | `reminder/Services/RevenueCatSubscriptionService.swift` |
| 云端 sync 调用 | `reminder/Services/SubscriptionSupabaseSupport.swift` |
| Webhook | `supabase/functions/revenuecat-webhook/index.ts` |
| 客户端 sync | `supabase/functions/sync-revenuecat-entitlement/index.ts` |
| SQL RPC | `reminder/Services/Supabase/migrations/20260617_revenuecat_entitlement_sync.sql` |
| 商品 ID | `reminder/Utilities/StoreKitProductCatalog.swift` |

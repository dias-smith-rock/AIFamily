# Family Sync 订阅（RevenueCat + Supabase）部署检查清单

适用版本：RevenueCat SDK 购买/恢复 + Webhook 主路径 + 客户端 `sync-revenuecat-entitlement` 兜底。

---

## 一、RevenueCat Dashboard

| 项 | 值 |
|----|-----|
| Bundle ID | `com.aifamilygroup.reminder` |
| Entitlement | `premium` |
| Store 商品 | `wesync.vip.monthly` / `wesync.vip.yearly` |
| Offering | 标识符 **`current`**（全小写），在 Dashboard 勾选为 Current offering，含月付/年付 Package |
| Webhook URL | `https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook` |
| Webhook Authorization | 与 Supabase secret `REVENUECAT_WEBHOOK_AUTHORIZATION` 一致（如 `Bearer <secret>`） |
| Public API Key (`appl_...`) | **仅** iOS `Info.plist` → `RevenueCatAPIKey` |
| Secret API Key (`sk_...`) | **仅** Supabase secret `REVENUECAT_SECRET_API_KEY`（勿写入 App；服务端 REST 勿带 `X-Platform`） |

`app_user_id` 规则：登录后 iOS 调用 `Purchases.logIn(supabaseUserId)`，Webhook 与 sync 均使用 **auth user UUID**。

---

## 二、Supabase 部署

### Step 1 — SQL

执行以下 migration（按顺序）：

1. [`20260627120003_revenuecat_entitlement_sync.sql`](supabase/migrations/20260627120003_revenuecat_entitlement_sync.sql)（或 `supabase db push` 全量迁移）
2. `user_entitlements` SELECT RLS 已含于 [`20260627020719_remote_schema.sql`](supabase/migrations/20260627020719_remote_schema.sql) 基线

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

## 六、故障排查：本机 VIP 有、云端无记录

### 现象

App 显示用户已 VIP（`hasPremiumAccess=true`），但 `user_entitlements` 表无行或 `is_pro=false`。

### 是否正常

| 时机 | 判断 |
|------|------|
| 购买后几秒内 | 可接受（Webhook / sync 有延迟） |
| 已登录用户长期无记录 | **不正常**，影响换设备、组织继承 |

### 原因速查

1. **本机放行不依赖数据库**：`AppRouter.hasPremiumAccess` = 云端 **或** 组织继承 **或** RevenueCat SDK 本机权益。
2. **云端写入仅两条路**：Webhook（`revenuecat-webhook`）或客户端 sync（`sync-revenuecat-entitlement` → RPC）。
3. **RPC 仅在 `is_pro=true` 时 INSERT**；`is_pro=false` 只 UPDATE，从未写入则表无行。
4. **常见配置缺口**：RevenueCat `premium` entitlement 未绑商品、Offering 标识符非 `current` 或未勾选 Current、Edge Function / secrets / migration 未部署。
5. **RLS**：缺 SELECT 策略时 App 读不到云端行（见 `20260618_user_entitlements_select_rls.sql`），但不阻止 service_role 写入。

### 验证步骤

```bash
# 检查清单 + 可选 webhook/sync 探测
SUPABASE_PROJECT_REF=xxx TEST_USER_ID=<uuid> USER_JWT=<jwt> \
  ./scripts/verify-revenuecat-supabase.sh
```

1. RevenueCat Dashboard → Customers → 搜用户 Supabase UUID → 是否有交易、`premium` 是否 Active。
2. Supabase → Edge Functions Logs → `sync-revenuecat-entitlement` / `revenuecat-webhook`。
3. Xcode 日志：`[RevenueCat] syncEntitlementToCloud error` 或 `cloud sync mismatch`。
4. App VIP 页：若本机 Pro 但云端未对齐，会显示 **云端同步失败** 横幅（可点「重试云端同步」）。
5. 日志 `RevenueCat API 403 ... code 7243 Secret API keys should not be used in your app`：
   - Supabase secret 必须用 **`sk_...` Secret API Key**（不是 `appl_...`）
   - **`appl_...` 只能放 Info.plist**；**`sk_...` 只能放 Supabase secrets**
   - 修复后重新 `supabase functions deploy sync-revenuecat-entitlement`
6. 日志 `originalAppUserId=$RCAnonymousID:... entitlements=[]`：购买在匿名 ID 上，未合并到 Supabase UUID。App 会在 sync 前自动 `logIn` + `syncPurchases`；服务端 sync 也会回查 alias。仍失败时请退出重登或 VIP 页「重试云端同步」。
7. 日志 `cloud sync mismatch ... synced.isPro=false`：表示 RevenueCat REST 未返回有效 `premium`/订阅。常见原因：
   - Edge Function 未部署最新 `revenuecat.ts`（需 `supabase functions deploy sync-revenuecat-entitlement`）
   - Dashboard 中商品未绑定 Entitlement `premium`
   - `app_user_id` 不一致（App 使用小写 Supabase UUID，与 RC Customers 对齐）
   - 购买后 RC 服务端缓存未更新（App 会自动 `syncPurchases` 并重试 3 次）

### 修复优先级

1. 跑齐 migration + deploy functions + secrets。
2. RevenueCat：`premium` + Offering `current`（Current）+ Webhook。
3. 已登录用户购买后点 VIP 页「重试云端同步」，或重新登录触发 sync。

---

## 七、相关代码

| 组件 | 路径 |
|------|------|
| iOS 订阅服务 | `reminder/Services/RevenueCatSubscriptionService.swift` |
| 云端 sync 调用 | `reminder/Services/SubscriptionSupabaseSupport.swift` |
| Webhook | `supabase/functions/revenuecat-webhook/index.ts` |
| 客户端 sync | `supabase/functions/sync-revenuecat-entitlement/index.ts` |
| SQL RPC | `supabase/migrations/20260627120003_revenuecat_entitlement_sync.sql` |
| 商品 ID | `reminder/Utilities/StoreKitProductCatalog.swift` |

---
name: supabase-schema
description: >-
  WeFamily / WeSync Supabase 表结构与 iOS 模型映射（tasks 空间字段、RPC、身份 ID 维度）。
  Use when editing FamilyTask, TaskDataService, RLS-related filters, create_task_with_spatial,
  complete_task_with_spatial, geofence, completion_location, migrations, or database ERD alignment.
---

# Supabase  schema ↔ iOS 客户端

## 变更纪律（必读）

**已对齐线上的列映射冻结，只增不改。** 不得因 ERD/文档把既有 `CodingKeys`、Payload 键名、ID 维度批量改掉；仅新增库列时扩展 Model/Payload，写入键名以 **Table Editor / PostgREST 报错** 为准。读取可多加一条兼容 decode，写入不得猜列名。详见 `.cursor/rules/supabase-column-mapping.mdc`。

以 **Supabase 线上表结构** 为准更新本表；Studio ERD 仅作参考。`reminder/Services/Supabase/SupabaseSetup.sql` 为早期 MVP 草稿，**勿**以其 `tasks` 列名为准。

## 数据库迁移（canonical）

**唯一执行目录：** `supabase/migrations/`（Supabase CLI / Branching 只读此路径）。

| 顺序 | 文件 | 说明 |
|------|------|------|
| 1 | `20260627020719_remote_schema.sql` | `supabase db pull` 基线（含 location RPC、RevenueCat RPC 等） |
| 2 | `20260627023215_device_bindings_target_type_check.sql` | device_bindings check 约束 |
| 3 | `20260627120000_task_spatial_rpc.sql` | 空间任务 RPC（幂等） |
| 4 | `20260627120001_location_states_ghost_default.sql` | 位置隐身默认 false |
| 5 | `20260627120002_live_huddle_realtime_rls.sql` | Live Huddle Realtime RLS |
| 6 | `20260627120003_revenuecat_entitlement_sync.sql` | RevenueCat → user_entitlements |
| 7 | `20260627120004_wallet_ledger_schema.sql` | 公账 / 积分 MVP |

废弃历史 SQL（勿加入 migrations 链）：`supabase/schema-history/`。

新增 schema：**先**写 `supabase/migrations/YYYYMMDDHHMMSS_*.sql`，**再** `supabase db push` 或合并分支；禁止只在 SQL Editor 手改 master 而不同步到此目录。

## `tasks` 表（核心）

| 数据库列 | Swift (`FamilyTask`) | 说明 |
|----------|----------------------|------|
| `id` | `id` | UUID |
| `household_id` | `householdId` | 群组 |
| `creator_id` | `creatorId` | **运行时写入 `household_memberships.id`（小写 UUID 字符串）**，与 RLS `membership_ids_for_current_user_in_household` 一致；ERD 若连到 `auth.users` 为示意，勿在前端改成 `auth.uid()` |
| `parent_task_id` | `parentTaskId` | 重复子任务 |
| `group_id` | `groupId` | 旧版批量重复 |
| `involved_member_ids` | `involvedMemberIds` | **`household_memberships.id` 数组**，不是 user id |
| `target_profile_id` / `target_profile_ids` | `targetProfileId` / `targetProfileIds` | `family_profiles.id` |
| `title`, `description`, … | 同名驼峰 | 经 `SupabaseCodec` snake_case |
| `location_data` | `locationData` | JSONB |
| `geofence` | `geofence` | JSONB → `TaskGeofence`（`lat`/`lng`/`address_name`/`trigger_type` 见 `TaskSpatial.swift`） |
| `completion_location` | `completionLocation` | JSONB → `TaskCompletionLocation` |
| `recurrence_end_date` | `recurrenceEndDate` | 线上实际列名；解码可兼容 `recurrence_end_at`（ERD 草案，未上线前勿写入） |
| `issue` | `issue` | `text`，任务「遇到问题」说明；≠ `TaskStatus.issue` 枚举 |
| `alarm_set_by` | `alarmSetBy` | JSONB `[String: AlarmConfig]`（按成员称呼键） |
| `task_type` | `taskType` | `scheduled` / `flexible` / `birthday_reminder` / **`expense`** / **`income`** |
| `estimated_cost` | `estimatedCost` | 任务预估费用（日程创建 UI）；≠ 公账实付 |
| `list_id` | `listId` | 购物清单等外键（账本预留） |
| `actual_amount` | `actualAmount` | 公账实付/实收（NUMERIC → `Double`） |
| `payer_id` | `payerId` | **membership id** — 垫付人 |
| `split_member_ids` | `splitMemberIds` | **membership id[]** — 均摊 |
| `expense_category` | `expenseCategory` | 分类快照文本，如 `🍔 餐饮美食` |
| `reward_points` | `rewardPoints` | 任务可获积分（审批流预留） |
| `point_approved_by` | `pointApprovedBy` | **membership id** — 审批家长 |
| `end_datetime` | `endDatetime` | |
| `duration_minutes` | `durationMinutes` | |
| `source` | `source` | `TaskSource` |

### 空间 RPC

| RPC | 参数 | 客户端 |
|-----|------|--------|
| `create_task_with_spatial` | `p_title`, `p_description`, `p_creator_id`, `p_tenant_id`, `p_geofence` | `CreateTaskWithSpatialParams`；`p_tenant_id` = `householdId`；`p_creator_id` = **membership id**；库中**只能保留一个重载**（`p_title` 用 `text`，勿再建 `varchar` 版，否则 PostgREST 报 candidate 歧义） |
| `complete_task_with_spatial` | `p_task_id`, `p_user_id`, `p_completion_location` | `CompleteTaskWithSpatialParams`；`p_user_id` = **membership id**；定位失败时 `p_completion_location` 传 `nil` |

实现位置：`TaskSpatialRPC.swift`、`SupabaseTaskDataService`、`TaskCompletionLocationProvider`。

### `location_states` 与位置 RPC

| 数据库列 | Swift | 说明 |
|----------|-------|------|
| `id` | `LocationStateRecord.databaseId` | 可选；无 `id` 列时用 `profileId` 作 `Identifiable.id` |
| `household_id` | `householdId` | **必填**；与 `entity_id` 联合唯一，禁止跨群组混读 |
| `entity_id` | `profileId` | **`family_profiles.id`**，不是 user id / membership id |
| `locations` | `locations: [LocationPayload]` | JSONB 数组，**newest-first**；最多 **20** 条（触发器 `location_states_cap_locations_trg`）；元素键 `lat`/`lng`/`address_name`/`recorded_at`/`battery_level`/`is_charging` |
| `is_ghost_mode` | `isGhostMode` | 默认 `false`；仅「保持隐藏」写 `true` |
| `updated_at` | `updatedAt` | |

| RPC | 参数 | 客户端 |
|-----|------|--------|
| `push_entity_location` | `p_entity_id`, `p_household_id`, `p_new_location`, `p_min_distance_meters`, `p_min_interval_seconds` | `PushEntityLocationParams`（`LocationStateRPC.swift`）；`p_entity_id` = **`family_profiles.id`**；prepend 新点到 `locations`；服务端须**同时**满足位移与间隔；RPC 下限与设置页最小可选项一致：**100m**、**5 分钟**（`20260611_location_states_setting_floors.sql`）；`0`/null 参数回退默认 **500m** / **15 分钟** |

- **读取**：`SupabaseLocationStateDataService.fetch*` 按 `household_id` 过滤；解码可兼容已废弃的 `current_location` / `history_location_*`（仅读）。
- **写入**：`reportCurrentLocationIfNeeded` → `LocationPersistWriteGate`（距离 + 时间双门禁，阈值见 `LocationPersistPreferences` 用户设置）→ RPC；RPC 未部署时 PostgREST upsert 写 `locations`。
- **展示态**：`UserLocationState.locations`（`locations[0]` = 当前）；轨迹 `breadcrumbCoordinates` = 数组 reversed。
- **Live Huddle Realtime**：频道 `circle:{household_id}:live_huddle`（小写 UUID）；见 `LiveLocationManager`、`supabase/migrations/20260627120002_live_huddle_realtime_rls.sql`。

迁移：location 相关变更已并入 `20260627020719_remote_schema.sql` 基线（`locations` JSONB 数组 + cap 触发器 + `push_entity_location`）；增量见 `20260627120001_location_states_ghost_default.sql`。

### 写入路径

- **单条创建（无重复）**：`CreateTaskView` → RPC → `tasks` `update` 补全列。
- **`TaskDataService.createTask`**：RPC + `updateTask` 合并完整 `FamilyTask`。
- **重复母/子任务**：仍 `insert` `TaskInsertPayload`（`recurrence_end_date` 键名）。
- **完成**：`status == .completed` 且有 `actingMembershipId` → `complete_task_with_spatial`。

## 身份 ID 口诀（必读）

- **橘子堆** = `involved_member_ids`（membership id）
- **苹果** = `auth.users.id`（user id）
- 禁止用 user id 填 `involved_member_ids` 或在前端用 `auth.uid()` 过滤该数组
- 「是否派给我」→ `AppRouter.selectedMembershipId` + `FamilyTask.involvesMembership(id:)`
- 「是否我创建」→ `task.creatorId == selectedMembershipId`（不是 auth user id）

## 相关表（简述）

| 表 | iOS 模型 / 服务 |
|----|-----------------|
| `households` | `Household` |
| `household_memberships` | `HouseholdMembership` |
| `family_profiles` | `FamilyProfile` |
| `feedbacks` | `Feedback` |
| `task_attachments` | `TaskAttachment` |
| `location_states` | `LocationStateRecord`；`household_id` + `entity_id` 群组隔离；JSONB `current_location` / `history_location_*` → `LocationPayload`（`lat`/`lng`/`address_name`） |
| `subscription_orders` | `SubscriptionOrder`；历史 Apple IAP 订单（可选）；新购走路径见 RevenueCat |
| `user_entitlements` | `UserEntitlement`；`is_pro`、`pro_expires_at`；**写入**仅 `service_role`（`sync_user_entitlement_from_revenuecat`）；**读取** authenticated `user_id = auth.uid()`（`20260618_user_entitlements_select_rls.sql`） |
| `households.is_premium` | 购买激活时由 RPC 写入的缓存位；**客户端 VIP 判断不依赖此列**，改用 RPC `household_creator_has_active_pro` |
| `resolve_household_creator_user_id` | RPC 内部辅助：优先 `household_memberships.role=creator` → `user_id`；回退 `households.creator_id` 作 auth user id 或 membership id |
| `household_creator_has_active_pro` | RPC（authenticated 成员可调用）：`resolve_household_creator_user_id` → `user_entitlements` 判断创建者 Pro 是否有效 |
| IAP / RevenueCat | Entitlement `premium`；服务端 `resolveEntitlementState` 与 iOS 一致（`premium` 或 `subscriptions` 中 `wesync.vip.*` 未过期）；Webhook + `sync-revenuecat-entitlement` 写入 |
| VIP 权限（客户端） | `AppRouter.hasPremiumAccess`：`PremiumAccess`（本人 `user_entitlements.isActive` **或** `household_creator_has_active_pro`）**或** `RevenueCatSubscriptionService.hasActiveProEntitlement` |
| `invite_link_nonces` | `InviteLinkNonce` |
| `expense_categories` | `ExpenseCategory`；`household_id` + `name` 唯一；`icon` + `name` 展示为 `displayLabel` |
| `points_ledger` | `PointsLedgerEntry`；`target_profile_id` = **`family_profiles.id`**；`amount` 正=赚取负=兑换 |
| `household_rewards` | Phase 2 愿望商城；`required_points` |

迁移：`supabase/migrations/20260627120004_wallet_ledger_schema.sql`（tasks 增量列 + 三表 + 公账 RLS 增补）。

## 账本写入路径（MVP）

- **公账/收入**：`LedgerDataService.createLedgerTask` → 直接 `insert` `tasks`（`task_type` = `expense` / `income`），不经 `create_task_with_spatial`。
- **积分流水**：`LedgerDataService.insertPointsLedgerEntry` → `points_ledger`。
- **分类 seed**：`ensureDefaultCategories` 首次为空时写入 8 条预设模板（`ExpenseCategory.defaultSeedTemplates`）。
- **沙盒**：客户端 `LedgerAccessControl` — `creator`/`admin` 见公账分段；`member` 锁定积分视图。DB RLS：`expense`/`income` 行仅 `can_manage_household` 可读。

## 编解码

- 表行：`SupabaseCodec`（`convertToSnakeCase` / `convertFromSnakeCase`）。
- JSONB 子对象（`TaskGeofence`、`TaskCompletionLocation`）：**显式 `CodingKeys`**（`lat`、`address_name` 等），勿依赖全局 snake 策略。
- 手写 PostgREST payload（`TaskInsertPayload`）：列名用 **数据库字面量**（以 Studio 表结构为准，如 `recurrence_end_date`）。

## 修改检查清单

1. 新列是否加入 `FamilyTask` + `CodingKeys`（或 payload 显式键）？
2. `involved_member_ids` / `creator_id` 是否仍为 **membership id**？
3. 空间 JSONB 是否带 `TaskSpatial` 的 `CodingKeys`？
4. Mock / `RecurrenceEngine` / `familyTaskFromInsertPayload` 是否补全新属性？
5. 本地化若涉及新 UI 文案 → `chinese-localization-keys` skill。

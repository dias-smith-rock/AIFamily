---
name: supabase-schema
description: >-
  WeFamily / Family Sync Supabase 表结构与 iOS 模型映射（tasks 空间字段、RPC、身份 ID 维度、
  ledger_transactions、expense_categories、category_tags、transaction_tag_mappings）。
  Use when editing FamilyTask, TaskDataService, RLS-related filters, create_task_with_spatial,
  complete_task_with_spatial, geofence, completion_location, ledger_transactions,
  expense_categories, category_tags, migrations, or database ERD alignment.
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
| 7 | `20260627120004_wallet_ledger_schema.sql` | **历史**公账/积分 MVP（tasks 扩展列 + 精简 `expense_categories`）；公账部分已被目标四表架构取代 |
| 8 | `20260627130000_fix_membership_role_helpers.sql` | `can_manage_household` / `current_user_role` 对齐 `household_memberships.role` |
| 9 | `20260627135000_ledger_four_tables_schema.sql` | **正式四表 DDL**：升级 `expense_categories` + 创建 `category_tags` / `ledger_transactions` / `transaction_tag_mappings` |
| 10 | `20260627140000_ledger_four_tables_rls.sql` | 公账四表 POLICY + `seed_household_presets` SECURITY DEFINER |
| 11 | `20260627150000_ledger_member_income_rls.sql` | member 可读/写 `type=income`；支出仍仅 manager |
| 12 | `20260627160000_ledger_seed_backfill.sql` | `seed_household_presets_for` + 既有家庭回填 |
| 13 | `20260627170000_ensure_ledger_presets_rpc.sql` | RPC `ensure_household_ledger_presets`（成员/游客可幂等补种） |
| 14 | `20260627180000_ledger_payer_ids.sql` | `ledger_transactions.payer_ids uuid[]` + 从 `payer_id` 回填 |
| 15 | `20260627190000_ledger_visible_member_ids.sql` | `visible_member_ids` + SELECT RLS 可见度 |
| 16 | `20260728120000_tasks_timezone.sql` | `tasks.timezone`（IANA；全天/重复日历日语义） |
| 17 | `20261006120000_tracked_device_pairing.sql` | `household_memberships.is_tracked_device` + 儿童设备配对 nonce / RPC / RLS |
| 18 | `20261006133000_tracked_device_pin.sql` | `household_memberships.tracked_device_pin`（列权限收回）+ 管理员 get/set、追踪端 sync/report、claim 保留 PIN |
| 19 | `20261006151000_tracked_device_claim_keep_pin.sql` | 核销配对码不再提交/覆盖 PIN；空 PIN 不报 invalid pin |
| 20 | `20261006160000_tracked_device_claim_nickname.sql` | claim 写入 `nickname`（NOT NULL）并优先更新已有影子 membership |
| 21 | `20261006170000_tracked_device_membership_nickname_default.sql` | `nickname` 列默认 `Member`；再次替换 claim RPC（线上仍跑旧 INSERT 导致 23502） |
| 22 | `20261006180000_tracked_device_pairing_realtime.sql` | `tracked_device_pairing_nonces` 加入 Realtime，管理员端感知核销 |
| 23 | `20261006190000_tracked_device_model_bound_at.sql` | membership `tracked_device_model` / `tracked_device_bound_at`；claim 写入；追踪端 report 型号 |
| 24 | `20261006200000_location_states_uncapped.sql` | `location_states.locations` 取消 20 条上限 |
| 25 | `20261008120000_location_trail_segments.sql` | `location_trail_segments` 稀疏轨迹段 + `push_location_trail_segment`（48h / 每实体 20 段） |

**公账目标 schema**（`expense_categories` 完整列、`category_tags`、`ledger_transactions`、`transaction_tag_mappings`、`seed_household_presets`）见 `20260627135000_ledger_four_tables_schema.sql` 起。

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
| `task_type` | `taskType` | 日程/待办：`scheduled` / `flexible` / `birthday_reminder`。**`expense` / `income`：历史兼容，新公账勿再写入** → 见 `ledger_transactions` |
| `timezone` | `timezone` | IANA（如 `Asia/Shanghai`）；全天/重复按此解释日历日；`nil` 回退显示时区/系统时区 |
| `estimated_cost` | `estimatedCost` | 任务预估费用（日程创建 UI）；≠ 公账实付 |
| `list_id` | `listId` | 购物清单等外键（预留） |
| `actual_amount` | `actualAmount` | **已废弃 · 公账勿写入** → `ledger_transactions.amount` |
| `payer_id` | `payerId` | **已废弃 · 公账勿写入** → `ledger_transactions.payer_ids`（**profile id[]**） |
| `split_member_ids` | `splitMemberIds` | **已废弃 · 公账勿写入**（旧均摊 membership id[]）；目标人见 `ledger_transactions.target_member_ids` |
| `expense_category` | `expenseCategory` | **已废弃 · 公账勿写入** → `ledger_transactions.category_name_snapshot` + `category_icon_snapshot` |
| `reward_points` | `rewardPoints` | 任务可获积分（行为积分审批流预留） |
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
| `locations` | `locations: [LocationPayload]` | JSONB 数组，**newest-first**，**不封顶**（触发器 `location_states_cap_locations_trg` 仅校验数组类型）；元素键 `lat`/`lng`/`address_name`/`recorded_at`/`battery_level`/`is_charging` |
| `is_ghost_mode` | `isGhostMode` | 默认 `false`；仅「保持隐藏」写 `true` |
| `updated_at` | `updatedAt` | |

| RPC | 参数 | 客户端 |
|-----|------|--------|
| `push_entity_location` | `p_entity_id`, `p_household_id`, `p_new_location`, `p_min_distance_meters`, `p_min_interval_seconds` | `PushEntityLocationParams`（`LocationStateRPC.swift`）；`p_entity_id` = **`family_profiles.id`**；prepend 新点到 `locations`；服务端须**同时**满足位移与间隔；RPC 下限与设置页最小可选项一致：**100m**、**5 分钟**（`20260611_location_states_setting_floors.sql`）；`0`/null 参数回退默认 **500m** / **15 分钟** |

- **读取**：`SupabaseLocationStateDataService.fetch*` 按 `household_id` 过滤；解码可兼容已废弃的 `current_location` / `history_location_*`（仅读）。
- **写入**：`reportCurrentLocationIfNeeded` → `LocationPersistWriteGate`（距离 + 时间双门禁，阈值见 `LocationPersistPreferences` 用户设置）→ RPC；RPC 未部署时 PostgREST upsert 写 `locations`。
- **展示态**：`UserLocationState.locations`（`locations[0]` = 当前）；轨迹 `breadcrumbCoordinates` = 数组 reversed。
- **Live Huddle Realtime**：频道 `circle:{household_id}:live_huddle`（小写 UUID）；见 `LiveLocationManager`、`supabase/migrations/20260627120002_live_huddle_realtime_rls.sql`。

迁移：location 相关变更已并入 `20260627020719_remote_schema.sql` 基线（`locations` JSONB 数组 + `push_entity_location`）；`20261006200000_location_states_uncapped.sql` 取消 20 条上限；增量见 `20260627120001_location_states_ghost_default.sql`。

### `location_trail_segments`（稀疏行程轨迹）

| 数据库列 | Swift (`LocationTrailSegment`) | 说明 |
|----------|-------------------------------|------|
| `id` | `id` | UUID |
| `household_id` | `householdId` | 群组 |
| `entity_id` | `entityId` | **`family_profiles.id`**（与 `location_states.entity_id` 一致） |
| `started_at` / `ended_at` | `startedAt` / `endedAt` | 段起止 |
| `waypoints` | `waypoints: [TrailWaypoint]` | JSONB 数组，**最旧→最新**；键 `lat`/`lng`/`recorded_at`（无电量等大字段） |
| `point_count` | `pointCount` | 锚点数量 |
| `created_at` | `createdAt` | 可选 |

| RPC | 参数 | 说明 |
|-----|------|------|
| `push_location_trail_segment` | `p_household_id`, `p_entity_id`, `p_started_at`, `p_ended_at`, `p_waypoints` | 校验 membership.profile_id = entity；插入后删 **48h** 外段 + 每实体最多 **20** 段 |

- **本机**：`OnDeviceTrailBuffer` 密采 → `TrailSimplifier`（Douglas-Peucker）→ `LocationTrailCaptureCoordinator` 上报。
- **展示**：`RoadSnapRouteBuilder`（MKDirections）贴路；Ghost 时不缓冲不上报。
- **与 `location_states` 关系**：并存；后者仍只做实时位置/粗历史。

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

### 账本 ID 维度（与 tasks 不同）

| 字段 | 维度 |
|------|------|
| `tasks.creator_id` / `payer_id`（废弃公账列） | **membership id** |
| `ledger_transactions.creator_id` | **`family_profiles.id`**（操作人档案） |
| `ledger_transactions.payer_ids` | **`family_profiles.id[]`**（垫付人，多选） |
| `ledger_transactions.payer_id` | **只读兼容** — 旧单垫付人；新写入勿再填 |
| `ledger_transactions.target_member_ids` | **`family_profiles.id[]`**（为了谁，多选） |
| `ledger_transactions.visible_member_ids` | **`family_profiles.id[]`**（可见度；`{}` = 不额外限制） |
| `points_ledger.target_profile_id` | **`family_profiles.id`** |

## 家庭公账（Ledger）— 目标权威架构

公账流水**不再**写入 `tasks`。目标表结构如下（产品确认脚本；正式 migration 待补进 `supabase/migrations/`）。

### `expense_categories`

每个家庭独立的收支分类；支持预设 i18n key 与软删除。

| 数据库列 | 说明 |
|----------|------|
| `id` | UUID PK |
| `household_id` | → `households.id` ON DELETE CASCADE |
| `type` | `expense` \| `income` |
| `name` | 默认/保底英文名（如 `Dining`） |
| `preset_key` | 预设英文 Key（如 `cat_dining`），供前端 i18n；可空 |
| `icon` | Emoji / SF Symbol 字符串，默认 `🏷️` |
| `color_hex` | 主题色，默认 `#007AFF` |
| `is_preset` | 是否系统预设 |
| `sort_order` | 排序权重 |
| `is_deleted` | 软删除（历史报表仍靠交易快照） |
| `created_at` / `updated_at` | TIMESTAMPTZ |

唯一约束：`(household_id, type, name)`。索引：`(household_id, type)`。

**已废弃**：MVP 精简版仅 `name`/`icon`、唯一键 `(household_id, name)`，以及客户端 `ensureDefaultCategories` 本地种子路径。新家庭依赖 `seed_household_presets` 触发器。

### `category_tags`

强绑定到某一 `expense_categories.id`（每分类标签集独立）。

| 数据库列 | 说明 |
|----------|------|
| `id` | UUID PK |
| `category_id` | → `expense_categories.id` ON DELETE CASCADE |
| `household_id` | → `households.id` ON DELETE CASCADE |
| `name` | 保底英文名（如 `Breakfast`） |
| `preset_key` | 如 `tag_breakfast`；可空 |
| `is_preset` / `is_deleted` | 预设 / 软删除 |
| `created_at` | TIMESTAMPTZ |

唯一约束：`(category_id, name)`。索引：`category_id`。

### `ledger_transactions`

单笔收支主流水。

| 数据库列 | 说明 |
|----------|------|
| `id` | UUID PK |
| `household_id` | → `households.id` |
| `creator_id` | **`family_profiles.id`** — 创建操作人 |
| `type` | `expense` \| `income` |
| `amount` | `NUMERIC(12,2)`，`CHECK (amount > 0)` |
| `currency` | `VARCHAR(3)`，默认 `HKD` |
| `transaction_time` | 实际发生时间，默认 `now()` |
| `category_id` | → `expense_categories.id` ON DELETE SET NULL |
| `category_name_snapshot` | 分类名快照（必填） |
| `category_icon_snapshot` | 分类图标快照 |
| `payer_ids` | **`family_profiles.id[]`**，默认 `{}`（多选垫付人；权威字段） |
| `payer_id` | **只读兼容** — 旧单垫付人；migration 已回填进 `payer_ids`；客户端不再写入 |
| `target_member_ids` | **`family_profiles.id[]`**，默认 `{}` |
| `visible_member_ids` | **`family_profiles.id[]`**，默认 `{}`；非空时仅列表内 profile（及 `creator_id`）可读；空 = 不额外限制 |
| `note` | 备注 |
| `attachment_urls` | 凭证 URL 数组，默认 `{}` |
| `source` | `manual` \| `ai_vision` \| `ai_voice`，默认 `manual` |
| `created_at` / `updated_at` | TIMESTAMPTZ |

索引：`(household_id, transaction_time DESC)`、`category_id`。

### `transaction_tag_mappings`

交易 ↔ 标签多对多；保存标签名快照。

| 数据库列 | 说明 |
|----------|------|
| `transaction_id` | → `ledger_transactions.id` ON DELETE CASCADE |
| `tag_id` | → `category_tags.id` ON DELETE SET NULL |
| `tag_name_snapshot` | 标签文字快照（必填） |
| `created_at` | TIMESTAMPTZ |

主键：`(transaction_id, tag_name_snapshot)`。索引：`transaction_id`。

### 种子触发器 `seed_household_presets`

- `AFTER INSERT ON households` → `seed_household_presets()` → `seed_household_presets_for(household_id)`。
- 自动注入英文预设：**支出** Dining / Transportation / Shopping / Sports & Fitness / Travel / Home Repairs（各带标签）；**收入** Salary & Income / Refunds（各带标签）。
- **仅新建家庭自动种子**；既有家庭需执行 `20260627160000_ledger_seed_backfill.sql`（幂等：已有未删除分类则跳过）。
- **客户端向前兼容**：进入 Wallet 拉取分类为空时调用 RPC `ensure_household_ledger_presets(p_household_id)`（任意活跃成员含 member）；服务端 `SECURITY DEFINER` 幂等补齐（按 `preset_key`）。见 `20260627170000_ensure_ledger_presets_rpc.sql`。
- 客户端**不要**再依赖 `ExpenseCategory.defaultSeedTemplates` / `ensureDefaultCategories` 作为权威种子（该路径已废弃）。

### 新四表 RLS

四表均已开启行级安全（`ENABLE ROW LEVEL SECURITY`）：

```sql
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE category_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_tag_mappings ENABLE ROW LEVEL SECURITY;
```

| 表 | RLS | POLICY |
|----|-----|--------|
| `expense_categories` | 已启用 | manager 全权限；member **SELECT** 仅 `type=income` |
| `category_tags` | 已启用 | manager 全权限；member **SELECT** 仅挂在 income 分类下 |
| `ledger_transactions` | 已启用 | manager 全权限；member **SELECT/INSERT** 仅 `type=income`；UPDATE/DELETE 仍仅 manager |
| `transaction_tag_mappings` | 已启用 | 与关联流水可见范围对齐（income 对 member 可写） |

脚本：`20260627140000_ledger_four_tables_rls.sql` + `20260627150000_ledger_member_income_rls.sql`。前置：`20260627130000_fix_membership_role_helpers.sql`。

## 相关表（简述）

| 表 | iOS 模型 / 服务 |
|----|-----------------|
| `households` | `Household`；新建后触发 `seed_household_presets` |
| `household_memberships` | `HouseholdMembership` |
| `family_profiles` | `FamilyProfile` |
| `feedbacks` | `Feedback` |
| `task_attachments` | `TaskAttachment` |
| `location_states` | `LocationStateRecord`；`household_id` + `entity_id` 群组隔离；JSONB `locations` → `LocationPayload` |
| `location_trail_segments` | `LocationTrailSegment`；稀疏 `waypoints` → `TrailWaypoint`；RPC `push_location_trail_segment` |
| `household_memberships.is_tracked_device` | `HouseholdMembership.isTrackedDevice` / `JoinedHousehold.isTrackedDevice`；儿童定位设备标记（角色仍为 `member`） |
| `household_memberships.tracked_device_pin` | 4–6 位门锁 PIN；**禁止** PostgREST 直读/直写；RPC `get_tracked_device_pin` / `set_tracked_device_pin`（`can_manage_household`）、`sync_own_tracked_device_pin` / `report_own_tracked_device_pin`（追踪端） |
| `tracked_device_pairing_nonces` | 一次性配对码；RPC `create_tracked_device_pairing_nonce` / `claim_tracked_device_pairing_nonce(p_nonce, p_user_id)`（不覆盖管理员 PIN） |
| `subscription_orders` | `SubscriptionOrder`；历史 Apple IAP 订单（可选）；新购走路径见 RevenueCat |
| `user_entitlements` | `UserEntitlement`；`is_pro`、`pro_expires_at`；**写入**仅 `service_role`（`sync_user_entitlement_from_revenuecat`）；**读取** authenticated `user_id = auth.uid()` |
| `households.is_premium` | 购买激活时由 RPC 写入的缓存位；**客户端 VIP 判断不依赖此列**，改用 RPC `household_creator_has_active_pro` |
| `resolve_household_creator_user_id` | RPC 内部辅助：优先 `household_memberships.role=creator` → `user_id`；回退 `households.creator_id` 作 auth user id 或 membership id |
| `household_creator_has_active_pro` | RPC（authenticated 成员可调用）：`resolve_household_creator_user_id` → `user_entitlements` 判断创建者 Pro 是否有效 |
| IAP / RevenueCat | Entitlement `premium`；服务端 `resolveEntitlementState` 与 iOS 一致（`premium` 或 `subscriptions` 中 `wesync.vip.*` 未过期）；Webhook + `sync-revenuecat-entitlement` 写入 |
| VIP 权限（客户端） | `AppRouter.hasPremiumAccess`：`PremiumAccess`（本人 `user_entitlements.isActive` **或** `household_creator_has_active_pro`）**或** `RevenueCatSubscriptionService.hasActiveProEntitlement` |
| `invite_link_nonces` | `InviteLinkNonce` |
| `expense_categories` | 目标：`type` + `preset_key` + 软删除等（见上节）；iOS 模型待对齐 |
| `category_tags` | 分类专属标签；iOS 模型待对齐 |
| `ledger_transactions` | 公账主流水；iOS 模型待对齐 |
| `transaction_tag_mappings` | 交易-标签映射 + 快照 |
| `points_ledger` | `PointsLedgerEntry`；`target_profile_id` = **`family_profiles.id`**；`amount` 正=赚取负=兑换 |
| `household_rewards` | Phase 2 愿望商城；`required_points` |

迁移备注：`20260627120004_wallet_ledger_schema.sql` 中的精简 `expense_categories` 与「公账写 tasks」为历史 MVP；`20260627130000_fix_membership_role_helpers.sql` 仍有效。

### 角色 helper（RLS）

| 函数 | 说明 |
|------|------|
| `get_user_role_in_household` | 返回当前用户在群组的 `role::text`（`creator` / `admin` / `member`），仅 `status=active` |
| `can_manage_household` | `role in ('creator','admin')` |
| `is_active_household_member` | `get_user_role_in_household(...) is not null`（含 member） |
| `seed_household_presets_for` | 幂等写入默认分类/标签（`SECURITY DEFINER`；触发器 / service_role） |
| `ensure_household_ledger_presets` | 成员可调用的补种 RPC → `seed_household_presets_for` |
| `current_user_role` | 委托 `get_user_role_in_household`（**禁止**引用 `user_role` 列） |

## 账本写入路径

### 公账（目标 · 客户端已对齐）

- **写入**：`LedgerDataService.createTransaction` → `ledger_transactions` + `transaction_tag_mappings`（`payer_ids` / `target_member_ids` / `visible_member_ids` / `creator_id` 均为 **profile id**；勿再写 `payer_id`）。
- **读取**：`LedgerTransaction` 优先 `payer_ids`；若为空则回退 `[payer_id]`。可见度由 RLS `visible_member_ids` 过滤（`current_user_profile_id_in_household`）。
- **新建默认可见度**：客户端默认勾选 active `creator`/`admin` 的 profile id；**Me 必选**。
- **客户端统计**：Wallet / 分类列表 / 报表均基于 `visibleTransactions`（`isVisible(to: viewerProfileId)`），与 RLS 语义一致。
- **分类/标签读取**：`expense_categories` / `category_tags`，过滤 `is_deleted = false`。
- **新建家庭**：依赖 `seed_household_presets`；客户端不再本地种子。
- **行为积分**：本期不做 UI；`points_ledger` 表保留。

### 废弃路径（勿再用于公账）

- **勿** `insert` `tasks`（`task_type` = `expense` / `income`）。
- **勿** 客户端 `ensureDefaultCategories` 种子。

## 编解码

- 表行：`SupabaseCodec`（`convertToSnakeCase` / `convertFromSnakeCase`）。
- JSONB 子对象（`TaskGeofence`、`TaskCompletionLocation`）：**显式 `CodingKeys`**（`lat`、`address_name` 等），勿依赖全局 snake 策略。
- 手写 PostgREST payload（`TaskInsertPayload`）：列名用 **数据库字面量**（以 Studio 表结构为准，如 `recurrence_end_date`）。

## 修改检查清单

1. 新列是否加入对应 Model + `CodingKeys`（或 payload 显式键）？
2. `involved_member_ids` / `tasks.creator_id` 是否仍为 **membership id**？
3. 空间 JSONB 是否带 `TaskSpatial` 的 `CodingKeys`？
4. Mock / `RecurrenceEngine` / `familyTaskFromInsertPayload` 是否补全新属性？
5. 本地化若涉及新 UI 文案 → `english-localization-keys` skill（`preset_key` 映射）。
6. **公账是否写入 `ledger_transactions`（而非 `tasks`）？**
7. **分类/标签软删后，交易是否仍写入 `category_*_snapshot` / `tag_name_snapshot`？**
8. 账本人物字段是否使用 **`family_profiles.id`**（勿误写成 membership id）？

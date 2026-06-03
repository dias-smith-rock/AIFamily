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
| `task_type` | `taskType` | `scheduled` / `flexible` |
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
| `id` | `LocationStateRecord.id` | UUID |
| `household_id` | `householdId` | **必填**；与 `entity_id` 联合唯一，禁止跨群组混读 |
| `entity_id` | `membershipId`（Swift 属性名） | **`household_memberships.id`**，不是 user id；PostgREST 键为 `entity_id` |
| `current_location` / `history_location_1` / `history_location_2` | `LocationPayload?` | 显式 `CodingKeys`：`lat`、`lng`、`address_name` |
| `is_ghost_mode` | `isGhostMode` | 默认 `false`；仅「保持隐藏」写 `true` |
| `updated_at` | `updatedAt` | |

| RPC | 参数 | 客户端 |
|-----|------|--------|
| `push_entity_location` | `p_entity_id`, `p_household_id`, `p_new_location` | `PushEntityLocationParams`（`LocationStateRPC.swift`）；`p_entity_id` = **membership id**；`p_new_location` = `LocationPayload` JSONB |

- **读取**：`SupabaseLocationStateDataService.fetch*` 按 `household_id` 过滤。
- **写入**：`reportCurrentLocationIfNeeded` → RPC；RPC 未部署时回退 PostgREST insert/update。
- **展示态**：`UserLocationState` 含 `householdId`（合并自 `LocationMemberAssembler`）。
- **Live Huddle Realtime**：频道 `circle:{household_id}:live_huddle`（小写 UUID）；见 `LiveLocationManager`、`20260602_live_huddle_realtime_rls.sql`。

迁移：`20260602_location_states_household_rpc.sql`、`20260602_location_states_ghost_default.sql`。

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
| `subscription_orders` / `user_entitlement` | `SubscriptionSupabaseSupport` |
| `invite_link_nonces` | `InviteLinkNonce` |

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

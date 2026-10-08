# Cross-platform architecture (iOS + Android)

**Clients:** iOS (`reminder/` SwiftUI) and Android (`android/` Kotlin Compose) share **backend contracts only** — not UI or ViewModels.

**Canonical schema docs:** [`.cursor/skills/supabase-schema/SKILL.md`](../.cursor/skills/supabase-schema/SKILL.md)  
**Migrations (DDL truth):** [`supabase/migrations/`](../supabase/migrations/)  
**Copy keys truth:** [`localization/keys.json`](../localization/keys.json)

## Identity dimensions (frozen)

| Field / concept | ID type | Notes |
|---|---|---|
| `tasks.creator_id` | `household_memberships.id` | Never `auth.users.id` |
| `tasks.involved_member_ids` | `household_memberships.id[]` | Filter “assigned to me” with selected membership |
| `location_states.entity_id` | `family_profiles.id` | Map / push location |
| `ledger_transactions.payer_ids` | `family_profiles.id[]` | Wallet |
| Session user | `auth.users.id` | Auth only |

## Core RPCs (Android must match online names)

| RPC | Key params |
|---|---|
| `create_task_with_spatial` | `p_title`, `p_description`, `p_creator_id` (membership), `p_tenant_id` (household), `p_geofence` |
| `complete_task_with_spatial` | `p_task_id`, `p_user_id` (membership), `p_completion_location` (nullable) |
| `push_entity_location` | `p_entity_id` (profile), `p_household_id`, `p_new_location`, distance/interval floors |
| `push_location_trail_segment` | Deferred on Android v1 |

Column mapping rule: **add-only**; never rename online write keys for elegance. See `.cursor/rules/supabase-column-mapping.mdc`.

## Android v1 scope (parity with cuts)

**In scope:** Auth + org routing, Schedule day list, Todos, Wallet read, Location member list + ghost toggle, Settings + Play Billing hook, FCM hook.

**Deferred:** Live Huddle, tracked-device pairing, week grid 7×24, trail snap-to-road, deep background location.

## App routing states

Align with iOS `AppRouter` semantics:

1. Bootstrapping  
2. Unauthenticated  
3. OrgRouting (no active membership)  
4. PendingApproval  
5. Active (main tabs)

## Change process

1. Add migration under `supabase/migrations/`.  
2. Update supabase-schema skill.  
3. Update iOS + Android clients.  
4. New UI strings → `localization/keys.json` → iOS xcstrings + `scripts/export_android_strings.py`.

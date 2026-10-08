# RPC / table catalog (client-facing)

See also `shared/architecture.md` and the supabase-schema skill.

## Tables commonly read by Android v1

- `tasks` — schedule (`task_type != flexible`) and todos (`task_type = flexible`)
- `household_memberships` — member list
- `location_states` — latest points (`locations` JSONB, newest-first)
- `ledger_transactions` — wallet feed
- `expense_categories` / `category_tags` — wallet metadata (later)

## Write path notes

- Prefer spatial RPCs for create/complete task (same as iOS).
- Ghost mode: prefer **local preference** first (iOS pattern); do not rely on server `is_ghost_mode` alone for “hide me”.

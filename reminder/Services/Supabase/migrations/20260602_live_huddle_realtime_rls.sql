-- Live Huddle Realtime 授权：与 iOS 频道 `circle:{household_id}:live_huddle`（private）配对使用。
-- 部署后请在 Supabase Dashboard → Settings → API 重载 schema；客户端已设 `config.isPrivate = true`。

-- 若项目尚未对 realtime.messages 启用 RLS，需先启用（Supabase 新项目可能已默认启用）。
alter table if exists realtime.messages enable row level security;

drop policy if exists "household_live_huddle_receive" on realtime.messages;
drop policy if exists "household_live_huddle_send" on realtime.messages;

create policy "household_live_huddle_receive"
on realtime.messages
for select
to authenticated
using (
    realtime.messages.extension in ('broadcast', 'presence')
    and realtime.topic() like 'circle:%:live_huddle'
    and exists (
        select 1
        from public.household_memberships hm
        where hm.user_id = auth.uid()
          and hm.status = 'active'
          and realtime.topic() = 'circle:' || lower(hm.household_id::text) || ':live_huddle'
    )
);

create policy "household_live_huddle_send"
on realtime.messages
for insert
to authenticated
with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and realtime.topic() like 'circle:%:live_huddle'
    and exists (
        select 1
        from public.household_memberships hm
        where hm.user_id = auth.uid()
          and hm.status = 'active'
          and realtime.topic() = 'circle:' || lower(hm.household_id::text) || ':live_huddle'
    )
);

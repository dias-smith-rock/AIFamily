-- AIFamily production-oriented setup (household_id + user_role based)
-- ⚠️ 历史 MVP 草稿：tasks 列名与线上一致 ERD 不符。请以 Supabase Studio ERD 为准，
--    客户端映射见 `.cursor/skills/supabase-schema/SKILL.md`。
-- Execute in Supabase SQL editor.

create extension if not exists "pgcrypto";

-- 1) Household graph
create table if not exists public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.household_memberships (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    user_role text not null check (user_role in ('owner', 'manager', 'executor', 'viewer')),
    status text not null default 'active' check (status in ('active', 'invited', 'disabled')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (household_id, user_id)
);

-- 2) Core business tables
create table if not exists public.family_members (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    display_name text not null,
    role text not null,
    permission text not null,
    notification_channel text not null,
    phone_number text,
    avatar_emoji text,
    notifications_enabled boolean not null default true,
    invite_token text unique,
    binding_status text not null default 'pending' check (binding_status in ('pending', 'linked', 'disabled')),
    created_by uuid not null default auth.uid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.tasks (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    title text not null,
    note text,
    scheduled_at timestamptz not null,
    due_at timestamptz,
    location text,
    assignee_id uuid not null references public.family_members(id),
    child_name text,
    status text not null,
    priority text not null,
    source text not null,
    created_by uuid not null default auth.uid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.feedbacks (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    task_id uuid not null references public.tasks(id),
    sender_id uuid not null references public.family_members(id),
    type text not null,
    text text,
    audio_url text,
    audio_duration_seconds integer,
    is_read boolean not null default false,
    created_by uuid not null default auth.uid(),
    created_at timestamptz not null default now()
);

create index if not exists idx_household_memberships_user_id on public.household_memberships(user_id);
create index if not exists idx_family_members_household_id on public.family_members(household_id);
create index if not exists idx_tasks_household_id on public.tasks(household_id);
create index if not exists idx_feedbacks_household_id on public.feedbacks(household_id);

create table if not exists public.task_attachments (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references public.tasks(id) on delete cascade,
    file_url text not null,
    file_type text not null,
    file_size_bytes bigint,
    created_by uuid default auth.uid(),
    created_at timestamptz not null default now()
);

create index if not exists idx_task_attachments_task_id on public.task_attachments(task_id);

create table if not exists public.invite_link_nonces (
    nonce uuid primary key,
    invite_token text not null,
    channel text not null check (channel in ('wechat', 'app', 'whatsapp', 'sms')),
    expires_at timestamptz not null,
    used_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists idx_invite_link_nonces_expires_at on public.invite_link_nonces(expires_at);
create index if not exists idx_invite_link_nonces_used_at on public.invite_link_nonces(used_at);

-- 3) RLS helpers
create or replace function public.current_household_ids()
returns setof uuid
language sql
security definer
set search_path = public
as $$
    select hm.household_id
    from public.household_memberships hm
    where hm.user_id = auth.uid() and hm.status = 'active'
$$;

create or replace function public.current_user_role(target_household_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
    select hm.user_role
    from public.household_memberships hm
    where hm.household_id = target_household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
    limit 1
$$;

create or replace function public.can_manage_household(target_household_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
    select coalesce(
        public.current_user_role(target_household_id) in ('owner', 'manager'),
        false
    )
$$;

create or replace function public.membership_ids_for_current_user_in_household(p_household_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        array_agg(hm.id order by hm.created_at),
        '{}'::uuid[]
    )
    from public.household_memberships hm
    where hm.household_id = p_household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
$$;

revoke all on function public.membership_ids_for_current_user_in_household(uuid) from public;
grant execute on function public.membership_ids_for_current_user_in_household(uuid) to authenticated;

-- 4) RLS policies
alter table public.household_memberships enable row level security;
alter table public.family_members enable row level security;
alter table public.tasks enable row level security;
alter table public.feedbacks enable row level security;
alter table public.invite_link_nonces enable row level security;

drop policy if exists "memberships_select_same_user_or_household_manager" on public.household_memberships;
create policy "memberships_select_same_user_or_household_manager"
on public.household_memberships
for select
using (
    user_id = auth.uid()
    or public.can_manage_household(household_id)
);

drop policy if exists "family_members_select_same_household" on public.family_members;
create policy "family_members_select_same_household"
on public.family_members
for select
using (household_id in (select public.current_household_ids()));

drop policy if exists "family_members_insert_managers" on public.family_members;
create policy "family_members_insert_managers"
on public.family_members
for insert
with check (
    public.can_manage_household(household_id)
    and created_by = auth.uid()
);

drop policy if exists "family_members_update_managers" on public.family_members;
create policy "family_members_update_managers"
on public.family_members
for update
using (public.can_manage_household(household_id))
with check (public.can_manage_household(household_id));

-- involved_member_ids: household_memberships.id（非 auth.uid）。creator_id 同为 membership id。
drop policy if exists "tasks_select_same_household" on public.tasks;
drop policy if exists "tasks_select_household_and_involvement" on public.tasks;
create policy "tasks_select_household_and_involvement"
on public.tasks
for select
using (
    household_id in (select public.current_household_ids())
    and (
        public.can_manage_household(household_id)
        or tasks.creator_id = any (public.membership_ids_for_current_user_in_household(tasks.household_id))
        or tasks.involved_member_ids is null
        or cardinality(tasks.involved_member_ids) = 0
        or (
            tasks.involved_member_ids is not null
            and tasks.involved_member_ids
                && public.membership_ids_for_current_user_in_household(tasks.household_id)
        )
    )
);

drop policy if exists "tasks_insert_managers" on public.tasks;
create policy "tasks_insert_managers"
on public.tasks
for insert
with check (
    public.can_manage_household(household_id)
    and created_by = auth.uid()
);

drop policy if exists "tasks_update_managers_and_executor" on public.tasks;
create policy "tasks_update_managers_and_executor"
on public.tasks
for update
using (
    public.can_manage_household(household_id)
    or public.current_user_role(household_id) = 'executor'
)
with check (
    public.can_manage_household(household_id)
    or public.current_user_role(household_id) = 'executor'
);

drop policy if exists "feedbacks_select_same_household" on public.feedbacks;
create policy "feedbacks_select_same_household"
on public.feedbacks
for select
using (household_id in (select public.current_household_ids()));

drop policy if exists "feedbacks_insert_same_household_executor_or_manager" on public.feedbacks;
create policy "feedbacks_insert_same_household_executor_or_manager"
on public.feedbacks
for insert
with check (
    household_id in (select public.current_household_ids())
    and public.current_user_role(household_id) in ('owner', 'manager', 'executor')
    and created_by = auth.uid()
);

drop policy if exists "feedbacks_update_managers" on public.feedbacks;
create policy "feedbacks_update_managers"
on public.feedbacks
for update
using (public.can_manage_household(household_id))
with check (public.can_manage_household(household_id));

-- invite_link_nonces is managed only by Edge Functions (service role).
drop policy if exists "invite_link_nonces_no_client_access" on public.invite_link_nonces;
create policy "invite_link_nonces_no_client_access"
on public.invite_link_nonces
for all
to authenticated
using (false)
with check (false);

-- 5) Storage & Realtime
insert into storage.buckets (id, name, public)
values ('voice-feedbacks', 'voice-feedbacks', false)
on conflict (id) do nothing;

drop policy if exists "voice_feedbacks_read_same_household" on storage.objects;
create policy "voice_feedbacks_read_same_household"
on storage.objects
for select
to authenticated
using (
    bucket_id = 'voice-feedbacks'
    and split_part(name, '/', 1) in (
        select household_id::text from public.current_household_ids()
    )
);

drop policy if exists "voice_feedbacks_write_executor_or_manager" on storage.objects;
create policy "voice_feedbacks_write_executor_or_manager"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'voice-feedbacks'
    and split_part(name, '/', 1) in (
        select household_id::text from public.current_household_ids()
    )
);

alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.feedbacks;

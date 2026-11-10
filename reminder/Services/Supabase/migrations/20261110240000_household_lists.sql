-- 通用清单（购物 / 旅行 / 自定义）：容器 + 条目。
-- 在 Supabase SQL Editor 或 CLI 执行；RLS 按家庭活跃成员读写。

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.household_lists (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  creator_id uuid not null,
  title text not null,
  kind text not null default 'custom'
    check (kind in ('shopping', 'trip', 'custom')),
  trip_start_date date,
  trip_end_date date,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint household_lists_trip_dates_check check (
    trip_end_date is null
    or trip_start_date is null
    or trip_end_date >= trip_start_date
  )
);

comment on table public.household_lists is
  'Shared household lists (shopping / trip / custom). creator_id = household_memberships.id.';

comment on column public.household_lists.creator_id is
  'household_memberships.id of the creator (not auth.users.id).';

create index if not exists household_lists_household_sort_idx
  on public.household_lists (household_id, sort_order, created_at desc);

create table if not exists public.list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.household_lists (id) on delete cascade,
  household_id uuid not null references public.households (id) on delete cascade,
  title text not null,
  is_checked boolean not null default false,
  note text,
  sort_order integer not null default 0,
  creator_id uuid not null,
  completed_by uuid,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.list_items is
  'Checklist rows for household_lists. creator_id / completed_by = membership ids.';

create index if not exists list_items_list_sort_idx
  on public.list_items (list_id, sort_order, created_at);

create index if not exists list_items_household_idx
  on public.list_items (household_id);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------

create or replace function public.set_household_lists_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists household_lists_set_updated_at on public.household_lists;
create trigger household_lists_set_updated_at
  before update on public.household_lists
  for each row
  execute function public.set_household_lists_updated_at();

create or replace function public.set_list_items_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists list_items_set_updated_at on public.list_items;
create trigger list_items_set_updated_at
  before update on public.list_items
  for each row
  execute function public.set_list_items_updated_at();

-- ---------------------------------------------------------------------------
-- RLS：家庭活跃成员可读可写
-- ---------------------------------------------------------------------------

alter table public.household_lists enable row level security;
alter table public.list_items enable row level security;

revoke all on table public.household_lists from public, anon;
revoke all on table public.list_items from public, anon;

grant select, insert, update, delete on table public.household_lists to authenticated;
grant select, insert, update, delete on table public.list_items to authenticated;

drop policy if exists household_lists_select_members on public.household_lists;
create policy household_lists_select_members
  on public.household_lists
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = household_lists.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists household_lists_insert_members on public.household_lists;
create policy household_lists_insert_members
  on public.household_lists
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = household_lists.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
        and hm.id = household_lists.creator_id
    )
  );

drop policy if exists household_lists_update_members on public.household_lists;
create policy household_lists_update_members
  on public.household_lists
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = household_lists.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
  with check (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = household_lists.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists household_lists_delete_members on public.household_lists;
create policy household_lists_delete_members
  on public.household_lists
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = household_lists.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists list_items_select_members on public.list_items;
create policy list_items_select_members
  on public.list_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = list_items.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists list_items_insert_members on public.list_items;
create policy list_items_insert_members
  on public.list_items
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = list_items.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
        and hm.id = list_items.creator_id
    )
    and exists (
      select 1
      from public.household_lists hl
      where hl.id = list_items.list_id
        and hl.household_id = list_items.household_id
    )
  );

drop policy if exists list_items_update_members on public.list_items;
create policy list_items_update_members
  on public.list_items
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = list_items.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  )
  with check (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = list_items.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists list_items_delete_members on public.list_items;
create policy list_items_delete_members
  on public.list_items
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = list_items.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

notify pgrst, 'reload schema';

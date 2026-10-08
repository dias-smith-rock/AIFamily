-- 稀疏轨迹段：本机密采简化后上云；查看端 MapKit 贴路重建。
-- entity_id = family_profiles.id（与 location_states 一致）。

create table if not exists public.location_trail_segments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  entity_id uuid not null references public.family_profiles (id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  waypoints jsonb not null default '[]'::jsonb,
  point_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint location_trail_segments_time_check check (ended_at >= started_at),
  constraint location_trail_segments_waypoints_is_array check (jsonb_typeof(waypoints) = 'array')
);

comment on table public.location_trail_segments is
  'Sparse trail waypoints (simplified on device). Road geometry is reconstructed client-side via MapKit.';

create index if not exists location_trail_segments_household_entity_ended_idx
  on public.location_trail_segments (household_id, entity_id, ended_at desc);

create index if not exists location_trail_segments_ended_at_idx
  on public.location_trail_segments (ended_at);

alter table public.location_trail_segments enable row level security;

-- 同家庭 active 成员可读
drop policy if exists location_trail_segments_select_members on public.location_trail_segments;
create policy location_trail_segments_select_members
  on public.location_trail_segments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = location_trail_segments.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

-- 仅本人（membership.profile_id = entity_id）可插入
drop policy if exists location_trail_segments_insert_own on public.location_trail_segments;
create policy location_trail_segments_insert_own
  on public.location_trail_segments
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = location_trail_segments.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
        and hm.profile_id = location_trail_segments.entity_id
    )
  );

-- 删除：本人或可管理家庭者（清理用）
drop policy if exists location_trail_segments_delete_own_or_manager on public.location_trail_segments;
create policy location_trail_segments_delete_own_or_manager
  on public.location_trail_segments
  for delete
  to authenticated
  using (
    public.can_manage_household(household_id)
    or exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = location_trail_segments.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
        and hm.profile_id = location_trail_segments.entity_id
    )
  );

-- 上报 + 保留策略（48h / 每实体最多 20 段）
create or replace function public.push_location_trail_segment(
  p_household_id uuid,
  p_entity_id uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_waypoints jsonb
)
returns public.location_trail_segments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.location_trail_segments;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if p_household_id is null or p_entity_id is null then
    raise exception 'household and entity required';
  end if;

  if p_ended_at < p_started_at then
    raise exception 'ended_at before started_at';
  end if;

  if jsonb_typeof(p_waypoints) is distinct from 'array' then
    raise exception 'waypoints must be a json array';
  end if;

  v_count := jsonb_array_length(p_waypoints);
  if v_count < 2 then
    raise exception 'waypoints need at least 2 points';
  end if;
  if v_count > 80 then
    raise exception 'waypoints exceed max 80';
  end if;

  if not exists (
    select 1
    from public.household_memberships hm
    where hm.household_id = p_household_id
      and hm.user_id = v_uid
      and hm.status = 'active'
      and hm.profile_id = p_entity_id
  ) then
    raise exception 'not allowed to push trail for this entity';
  end if;

  insert into public.location_trail_segments (
    household_id,
    entity_id,
    started_at,
    ended_at,
    waypoints,
    point_count
  )
  values (
    p_household_id,
    p_entity_id,
    p_started_at,
    p_ended_at,
    p_waypoints,
    v_count
  )
  returning * into v_row;

  -- TTL：删除超过 48 小时的段
  delete from public.location_trail_segments
  where household_id = p_household_id
    and entity_id = p_entity_id
    and ended_at < (timezone('utc', now()) - interval '48 hours');

  -- 每实体最多保留最近 20 段
  delete from public.location_trail_segments
  where id in (
    select id
    from public.location_trail_segments
    where household_id = p_household_id
      and entity_id = p_entity_id
    order by ended_at desc
    offset 20
  );

  return v_row;
end;
$$;

revoke all on function public.push_location_trail_segment(uuid, uuid, timestamptz, timestamptz, jsonb) from public;
grant execute on function public.push_location_trail_segment(uuid, uuid, timestamptz, timestamptz, jsonb) to authenticated;

-- Realtime（可选：家庭成员看到新轨迹）
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.location_trail_segments;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;

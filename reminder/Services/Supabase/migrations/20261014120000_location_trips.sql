-- 校车行程。与 location_states / location_trail_segments 分开：
-- 行程行放最新位置和车速；锚点约 80 米一个，供 MapKit 贴路；几何只存贴路结果。
-- 客户端只读表，写入走下面的函数。在 Supabase SQL Editor 执行本文件。

-- ---------------------------------------------------------------------------
-- 距离（米）
-- ---------------------------------------------------------------------------

create or replace function public.location_distance_meters(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select 6371000.0 * 2.0 * asin(least(1.0, sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2.0), 2)
    + cos(radians(p_lat1)) * cos(radians(p_lat2))
      * power(sin(radians(p_lng2 - p_lng1) / 2.0), 2)
  )));
$$;

revoke all on function public.location_distance_meters(double precision, double precision, double precision, double precision) from public;

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------

create table if not exists public.location_trips (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  entity_id uuid not null references public.family_profiles (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'arrived', 'ended')),
  started_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz,
  end_reason text,
  started_by uuid not null,
  latest_latitude double precision,
  latest_longitude double precision,
  latest_recorded_at timestamptz,
  latest_speed_kmh double precision,
  last_moved_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint location_trips_end_check check (
    (status = 'active' and ended_at is null)
    or (status in ('arrived', 'ended') and ended_at is not null)
  ),
  constraint location_trips_speed_check check (
    latest_speed_kmh is null
    or (latest_speed_kmh >= 0 and latest_speed_kmh <= 300)
  ),
  constraint location_trips_latest_coord_check check (
    (latest_latitude is null and latest_longitude is null)
    or (
      latest_latitude between -90 and 90
      and latest_longitude between -180 and 180
    )
  )
);

comment on table public.location_trips is
  'One school-bus trip. Latest fix and speed live on this row; history points do not store speed.';

create unique index if not exists location_trips_one_active_per_entity
  on public.location_trips (household_id, entity_id)
  where status = 'active';

create index if not exists location_trips_household_entity_started_idx
  on public.location_trips (household_id, entity_id, started_at desc);

create index if not exists location_trips_ended_at_idx
  on public.location_trips (ended_at);

create table if not exists public.location_trip_anchors (
  trip_id uuid not null references public.location_trips (id) on delete cascade,
  seq integer not null check (seq >= 0),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  recorded_at timestamptz not null,
  primary key (trip_id, seq)
);

comment on table public.location_trip_anchors is
  'Sparse road-snap anchors, about 80 meters apart. seq 0 is the trip start.';

create table if not exists public.location_trip_geometry (
  trip_id uuid not null references public.location_trips (id) on delete cascade,
  pair_index integer not null check (pair_index >= 0),
  status text not null check (status in ('road', 'straight')),
  vertices jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (trip_id, pair_index),
  constraint location_trip_geometry_vertices_is_array check (jsonb_typeof(vertices) = 'array')
);

comment on table public.location_trip_geometry is
  'Snapped polyline for anchors seq=pair_index -> seq=pair_index+1. road can replace straight; road is kept.';

create index if not exists location_trip_geometry_trip_idx
  on public.location_trip_geometry (trip_id, pair_index);

-- ---------------------------------------------------------------------------
-- 权限：家庭成员可读。写入仅限 security definer 函数。
-- ---------------------------------------------------------------------------

alter table public.location_trips enable row level security;
alter table public.location_trip_anchors enable row level security;
alter table public.location_trip_geometry enable row level security;

revoke all on table public.location_trips from public, anon, authenticated;
revoke all on table public.location_trip_anchors from public, anon, authenticated;
revoke all on table public.location_trip_geometry from public, anon, authenticated;

grant select on table public.location_trips to authenticated;
grant select on table public.location_trip_anchors to authenticated;
grant select on table public.location_trip_geometry to authenticated;

drop policy if exists location_trips_select_members on public.location_trips;
create policy location_trips_select_members
  on public.location_trips
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.household_memberships hm
      where hm.household_id = location_trips.household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists location_trip_anchors_select_members on public.location_trip_anchors;
create policy location_trip_anchors_select_members
  on public.location_trip_anchors
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.location_trips t
      join public.household_memberships hm
        on hm.household_id = t.household_id
      where t.id = location_trip_anchors.trip_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

drop policy if exists location_trip_geometry_select_members on public.location_trip_geometry;
create policy location_trip_geometry_select_members
  on public.location_trip_geometry
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.location_trips t
      join public.household_memberships hm
        on hm.household_id = t.household_id
      where t.id = location_trip_geometry.trip_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- 内部：清理 7 天前已结束的行程；搁置超过 2 小时的 active 也结束。
-- ---------------------------------------------------------------------------

create or replace function public.purge_location_trips(
  p_household_id uuid,
  p_entity_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.location_trips
  set status = 'ended',
      ended_at = timezone('utc', now()),
      end_reason = 'idle'
  where household_id = p_household_id
    and entity_id = p_entity_id
    and status = 'active'
    and last_moved_at < timezone('utc', now()) - interval '2 hours';

  delete from public.location_trips
  where household_id = p_household_id
    and entity_id = p_entity_id
    and status <> 'active'
    and ended_at < timezone('utc', now()) - interval '7 days';
end;
$$;

revoke all on function public.purge_location_trips(uuid, uuid) from public;

create or replace function public.location_trip_caller_is_member(
  p_household_id uuid,
  p_entity_id uuid,
  p_as_subject boolean
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_memberships hm
    where hm.household_id = p_household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
      and (
        (p_as_subject and hm.profile_id = p_entity_id)
        or (not p_as_subject and hm.profile_id is distinct from p_entity_id)
      )
  );
$$;

revoke all on function public.location_trip_caller_is_member(uuid, uuid, boolean) from public;

-- ---------------------------------------------------------------------------
-- 家长开始。同一小孩只能有一条 active。
-- ---------------------------------------------------------------------------

create or replace function public.start_location_trip(
  p_household_id uuid,
  p_entity_id uuid
)
returns public.location_trips
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.location_trips;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_household_id is null or p_entity_id is null then
    raise exception 'household and entity required';
  end if;

  if not public.location_trip_caller_is_member(p_household_id, p_entity_id, false) then
    raise exception 'only a parent in this household can start a trip';
  end if;

  if not exists (
    select 1
    from public.household_memberships hm
    where hm.household_id = p_household_id
      and hm.profile_id = p_entity_id
      and hm.status = 'active'
  ) then
    raise exception 'entity is not an active member of this household';
  end if;

  perform public.purge_location_trips(p_household_id, p_entity_id);

  begin
    insert into public.location_trips (
      household_id,
      entity_id,
      status,
      started_by
    )
    values (
      p_household_id,
      p_entity_id,
      'active',
      v_uid
    )
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'active trip already exists';
  end;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- 家长或小孩机结束。p_status = arrived | ended。
-- ---------------------------------------------------------------------------

create or replace function public.end_location_trip(
  p_trip_id uuid,
  p_status text,
  p_reason text default null
)
returns public.location_trips
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.location_trips;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_status is null or p_status not in ('arrived', 'ended') then
    raise exception 'status must be arrived or ended';
  end if;

  select * into v_row
  from public.location_trips
  where id = p_trip_id
  for update;

  if v_row.id is null then
    raise exception 'trip not found';
  end if;

  if not (
    public.location_trip_caller_is_member(v_row.household_id, v_row.entity_id, false)
    or public.location_trip_caller_is_member(v_row.household_id, v_row.entity_id, true)
  ) then
    raise exception 'not allowed to end this trip';
  end if;

  if v_row.status <> 'active' then
    return v_row;
  end if;

  update public.location_trips
  set status = p_status,
      ended_at = timezone('utc', now()),
      end_reason = nullif(btrim(p_reason), '')
  where id = p_trip_id
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- 小孩机上报最新点。位移约 80 米才追加锚点。静止超过 2 小时则结束。
-- 返回 { trip, inserted_anchor_seq }。新锚点的 seq 非空时，客户端去贴这一对。
-- ---------------------------------------------------------------------------

create or replace function public.push_location_trip_fix(
  p_trip_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_recorded_at timestamptz,
  p_speed_kmh double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.location_trips;
  v_recorded_at timestamptz := coalesce(p_recorded_at, timezone('utc', now()));
  v_last_anchor public.location_trip_anchors;
  v_distance double precision;
  v_moved boolean := false;
  v_seq integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid coordinate';
  end if;
  if p_speed_kmh is not null and (p_speed_kmh < 0 or p_speed_kmh > 300) then
    raise exception 'invalid speed';
  end if;
  if v_recorded_at > timezone('utc', now()) + interval '5 minutes' then
    raise exception 'recorded_at is in the future';
  end if;

  select * into v_trip
  from public.location_trips
  where id = p_trip_id
  for update;

  if v_trip.id is null then
    raise exception 'trip not found';
  end if;

  if not public.location_trip_caller_is_member(v_trip.household_id, v_trip.entity_id, true) then
    raise exception 'only the tracked device can push a trip fix';
  end if;

  if v_trip.status <> 'active' then
    return jsonb_build_object('trip', to_jsonb(v_trip), 'inserted_anchor_seq', null);
  end if;

  if v_trip.latest_latitude is not null and v_trip.latest_longitude is not null then
    v_distance := public.location_distance_meters(
      v_trip.latest_latitude, v_trip.latest_longitude, p_latitude, p_longitude
    );
    v_moved := v_distance >= 30;
  else
    v_moved := true;
  end if;

  if v_trip.last_moved_at < timezone('utc', now()) - interval '2 hours' and not v_moved then
    update public.location_trips
    set status = 'ended',
        ended_at = timezone('utc', now()),
        end_reason = 'idle'
    where id = p_trip_id
    returning * into v_trip;
    return jsonb_build_object('trip', to_jsonb(v_trip), 'inserted_anchor_seq', null);
  end if;

  update public.location_trips
  set latest_latitude = p_latitude,
      latest_longitude = p_longitude,
      latest_recorded_at = v_recorded_at,
      latest_speed_kmh = p_speed_kmh,
      last_moved_at = case when v_moved then v_recorded_at else last_moved_at end
  where id = p_trip_id
  returning * into v_trip;

  select * into v_last_anchor
  from public.location_trip_anchors
  where trip_id = p_trip_id
  order by seq desc
  limit 1;

  if v_last_anchor.trip_id is null then
    v_seq := 0;
  elsif v_last_anchor.seq >= 1999 then
    v_seq := null;
  else
    v_distance := public.location_distance_meters(
      v_last_anchor.latitude, v_last_anchor.longitude, p_latitude, p_longitude
    );
    if v_distance >= 80 then
      v_seq := v_last_anchor.seq + 1;
    end if;
  end if;

  if v_seq is not null then
    insert into public.location_trip_anchors (trip_id, seq, latitude, longitude, recorded_at)
    values (p_trip_id, v_seq, p_latitude, p_longitude, v_recorded_at);
  end if;

  return jsonb_build_object('trip', to_jsonb(v_trip), 'inserted_anchor_seq', v_seq);
end;
$$;

-- ---------------------------------------------------------------------------
-- 贴路结果。pair_index 对应锚点 seq。road 至少 3 个顶点。
-- 已有 road 不覆盖；straight 可以被后到的 road 升级。
-- ---------------------------------------------------------------------------

create or replace function public.push_location_trip_geometry(
  p_trip_id uuid,
  p_pair_index integer,
  p_status text,
  p_vertices jsonb default '[]'::jsonb
)
returns public.location_trip_geometry
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.location_trips;
  v_row public.location_trip_geometry;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_pair_index is null or p_pair_index < 0 then
    raise exception 'pair_index must be >= 0';
  end if;
  if p_status is null or p_status not in ('road', 'straight') then
    raise exception 'status must be road or straight';
  end if;
  if jsonb_typeof(p_vertices) is distinct from 'array' then
    raise exception 'vertices must be a json array';
  end if;

  v_count := jsonb_array_length(p_vertices);
  if v_count > 500 then
    raise exception 'vertices exceed max 500';
  end if;
  if p_status = 'road' and v_count < 3 then
    raise exception 'road geometry needs at least 3 vertices';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_vertices) elem
    where jsonb_typeof(elem) is distinct from 'object'
       or jsonb_typeof(elem -> 'lat') is distinct from 'number'
       or jsonb_typeof(elem -> 'lng') is distinct from 'number'
  ) then
    raise exception 'vertices must be objects with numeric lat/lng';
  end if;

  select * into v_trip
  from public.location_trips
  where id = p_trip_id;

  if v_trip.id is null then
    raise exception 'trip not found';
  end if;

  if not exists (
    select 1
    from public.household_memberships hm
    where hm.household_id = v_trip.household_id
      and hm.user_id = auth.uid()
      and hm.status = 'active'
  ) then
    raise exception 'not allowed to write trip geometry';
  end if;

  if (
    select count(*)
    from public.location_trip_anchors a
    where a.trip_id = p_trip_id
      and a.seq in (p_pair_index, p_pair_index + 1)
  ) < 2 then
    raise exception 'anchor pair not found';
  end if;

  with upsert as (
    insert into public.location_trip_geometry as g (
      trip_id,
      pair_index,
      status,
      vertices
    )
    values (
      p_trip_id,
      p_pair_index,
      p_status,
      case when p_status = 'straight' then '[]'::jsonb else p_vertices end
    )
    on conflict (trip_id, pair_index) do update
      set status = excluded.status,
          vertices = excluded.vertices,
          updated_at = timezone('utc', now())
      where g.status = 'straight'
        and excluded.status = 'road'
    returning g.*
  )
  select * into v_row from upsert;

  if v_row.trip_id is null then
    select * into v_row
    from public.location_trip_geometry
    where trip_id = p_trip_id
      and pair_index = p_pair_index;
  end if;

  return v_row;
end;
$$;

revoke all on function public.start_location_trip(uuid, uuid) from public;
revoke all on function public.end_location_trip(uuid, text, text) from public;
revoke all on function public.push_location_trip_fix(uuid, double precision, double precision, timestamptz, double precision) from public;
revoke all on function public.push_location_trip_geometry(uuid, integer, text, jsonb) from public;

grant execute on function public.start_location_trip(uuid, uuid) to authenticated;
grant execute on function public.end_location_trip(uuid, text, text) to authenticated;
grant execute on function public.push_location_trip_fix(uuid, double precision, double precision, timestamptz, double precision) to authenticated;
grant execute on function public.push_location_trip_geometry(uuid, integer, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime：行程行（头像、车速、开始/结束）、锚点、贴路折线。
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.location_trips;
    exception
      when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.location_trip_anchors;
    exception
      when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.location_trip_geometry;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;

notify pgrst, 'reload schema';

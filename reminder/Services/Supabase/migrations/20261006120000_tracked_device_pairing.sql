-- 儿童定位设备：membership 标记 + 一次性配对码 + 基础 RLS 隔离。
-- 角色仍为 member；is_tracked_device 表示「追踪端」。

alter table public.household_memberships
  add column if not exists is_tracked_device boolean not null default false;

comment on column public.household_memberships.is_tracked_device is
  'True when this membership is a child/tracked location device (UI + RLS restricted).';

create table if not exists public.tracked_device_pairing_nonces (
  nonce text primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  target_profile_id uuid not null references public.family_profiles (id) on delete cascade,
  created_by_membership_id uuid not null references public.household_memberships (id) on delete cascade,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by_user_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists tracked_device_pairing_nonces_household_idx
  on public.tracked_device_pairing_nonces (household_id);

create index if not exists tracked_device_pairing_nonces_profile_idx
  on public.tracked_device_pairing_nonces (target_profile_id);

alter table public.tracked_device_pairing_nonces enable row level security;

-- 仅管理员可读自己群的配对码行（可选）；核销走 SECURITY DEFINER RPC。
drop policy if exists tracked_device_pairing_nonces_select_managers on public.tracked_device_pairing_nonces;
create policy tracked_device_pairing_nonces_select_managers
  on public.tracked_device_pairing_nonces
  for select
  to authenticated
  using (public.can_manage_household(household_id));

create or replace function public.current_user_is_tracked_device_in(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select hm.is_tracked_device
      from public.household_memberships hm
      where hm.household_id = target_household_id
        and hm.user_id = auth.uid()
        and hm.status = 'active'
      limit 1
    ),
    false
  );
$$;

revoke all on function public.current_user_is_tracked_device_in(uuid) from public;
grant execute on function public.current_user_is_tracked_device_in(uuid) to authenticated;

create or replace function public.create_tracked_device_pairing_nonce(
  p_household_id uuid,
  p_manager_membership_id uuid,
  p_target_profile_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_nonce text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_i int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if public.can_manage_household(p_household_id) is not true then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.household_memberships hm
    where hm.id = p_manager_membership_id
      and hm.household_id = p_household_id
      and hm.user_id = v_uid
      and hm.status = 'active'
  ) then
    raise exception 'invalid manager membership';
  end if;

  if not exists (
    select 1
    from public.family_profiles fp
    where fp.id = p_target_profile_id
  ) then
    raise exception 'invalid target profile';
  end if;

  -- 作废同 profile 未消费旧码
  update public.tracked_device_pairing_nonces
  set consumed_at = now()
  where target_profile_id = p_target_profile_id
    and household_id = p_household_id
    and consumed_at is null;

  loop
    v_nonce := '';
    for v_i in 1..6 loop
      v_nonce := v_nonce || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.tracked_device_pairing_nonces t where t.nonce = v_nonce
    );
  end loop;

  insert into public.tracked_device_pairing_nonces (
    nonce,
    household_id,
    target_profile_id,
    created_by_membership_id,
    expires_at
  ) values (
    v_nonce,
    p_household_id,
    p_target_profile_id,
    p_manager_membership_id,
    now() + interval '30 minutes'
  );

  return v_nonce;
end;
$$;

revoke all on function public.create_tracked_device_pairing_nonce(uuid, uuid, uuid) from public;
grant execute on function public.create_tracked_device_pairing_nonce(uuid, uuid, uuid) to authenticated;

create or replace function public.claim_tracked_device_pairing_nonce(
  p_nonce text,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.tracked_device_pairing_nonces%rowtype;
  v_membership_id uuid;
  v_existing_user uuid;
begin
  if v_uid is null or v_uid <> p_user_id then
    raise exception 'not authenticated';
  end if;

  select *
    into v_row
  from public.tracked_device_pairing_nonces
  where nonce = upper(trim(p_nonce))
  for update;

  if not found then
    raise exception 'invalid pairing code';
  end if;

  if v_row.consumed_at is not null then
    raise exception 'pairing code already used';
  end if;

  if v_row.expires_at < now() then
    raise exception 'pairing code expired';
  end if;

  -- 目标 profile 上已有绑定用户则拒绝（除非是当前用户重绑）
  select hm.id, hm.user_id
    into v_membership_id, v_existing_user
  from public.household_memberships hm
  where hm.household_id = v_row.household_id
    and hm.profile_id = v_row.target_profile_id
    and hm.status = 'active'
  order by hm.created_at asc
  limit 1;

  if v_membership_id is not null and v_existing_user is not null and v_existing_user <> p_user_id then
    raise exception 'profile already bound to another device';
  end if;

  -- 当前用户若已在该家庭且绑定别的 profile，拒绝（避免游客身份串档案）
  if exists (
    select 1
    from public.household_memberships hm
    where hm.household_id = v_row.household_id
      and hm.user_id = p_user_id
      and hm.status = 'active'
      and (hm.profile_id is distinct from v_row.target_profile_id)
  ) then
    raise exception 'user already active in household with different profile';
  end if;

  if v_membership_id is null then
    insert into public.household_memberships (
      household_id,
      user_id,
      profile_id,
      role,
      status,
      joined_at,
      is_tracked_device
    ) values (
      v_row.household_id,
      p_user_id,
      v_row.target_profile_id,
      'member',
      'active',
      now(),
      true
    )
    returning id into v_membership_id;
  else
    update public.household_memberships
    set user_id = p_user_id,
        is_tracked_device = true,
        status = 'active',
        joined_at = coalesce(joined_at, now()),
        updated_at = now()
    where id = v_membership_id;
  end if;

  update public.tracked_device_pairing_nonces
  set consumed_at = now(),
      consumed_by_user_id = p_user_id
  where nonce = v_row.nonce;

  return v_membership_id;
end;
$$;

revoke all on function public.claim_tracked_device_pairing_nonce(text, uuid) from public;
grant execute on function public.claim_tracked_device_pairing_nonce(text, uuid) to authenticated;

-- tasks：追踪端禁止 SELECT（其它策略仍生效时，用 restrictive 策略收紧）
drop policy if exists tasks_deny_tracked_device_select on public.tasks;
create policy tasks_deny_tracked_device_select
  on public.tasks
  as restrictive
  for select
  to authenticated
  using (public.current_user_is_tracked_device_in(household_id) is not true);

drop policy if exists tasks_deny_tracked_device_write on public.tasks;
create policy tasks_deny_tracked_device_write
  on public.tasks
  as restrictive
  for all
  to authenticated
  using (public.current_user_is_tracked_device_in(household_id) is not true)
  with check (public.current_user_is_tracked_device_in(household_id) is not true);

-- ledger（表存在时再收紧）
do $$
begin
  if to_regclass('public.ledger_transactions') is not null then
    execute $p$
      drop policy if exists ledger_tx_deny_tracked_device on public.ledger_transactions;
      create policy ledger_tx_deny_tracked_device
        on public.ledger_transactions
        as restrictive
        for all
        to authenticated
        using (public.current_user_is_tracked_device_in(household_id) is not true)
        with check (public.current_user_is_tracked_device_in(household_id) is not true);
    $p$;
  end if;
end $$;

notify pgrst, 'reload schema';

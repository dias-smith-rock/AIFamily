-- location_states 群组隔离 + push_entity_location RPC（历史版本，entity 曾误用 membership）
-- 当前 canonical 迁移：20260602_location_states_profile_entity.sql（entity_id = family_profiles.id）
-- 在 Supabase SQL Editor 执行后：Settings → API → Reload schema cache

alter table if exists public.location_states
    add column if not exists household_id uuid references public.households(id) on delete cascade;

comment on column public.location_states.household_id is
    '位置行所属群组；与 entity_id 联合唯一，禁止跨 household 读写。';

create unique index if not exists location_states_household_entity_uidx
    on public.location_states (household_id, entity_id);

do $$
declare
    fn regprocedure;
begin
    for fn in
        select p.oid::regprocedure
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'push_entity_location'
    loop
        execute format('drop function if exists %s', fn);
    end loop;
end;
$$;

create function public.push_entity_location(
    p_entity_id uuid,
    p_household_id uuid,
    p_new_location jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row public.location_states%rowtype;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;

    if not exists (
        select 1
        from public.household_memberships hm
        where hm.id = p_entity_id
          and hm.household_id = p_household_id
          and hm.user_id = auth.uid()
    ) then
        raise exception 'forbidden';
    end if;

    select *
    into v_row
    from public.location_states ls
    where ls.entity_id = p_entity_id
      and ls.household_id = p_household_id
    limit 1;

    if found and coalesce(v_row.is_ghost_mode, false) then
        return;
    end if;

    if found then
        update public.location_states
        set
            history_location_2 = history_location_1,
            history_location_1 = current_location,
            current_location = p_new_location,
            updated_at = now()
        where entity_id = p_entity_id
          and household_id = p_household_id;
    else
        insert into public.location_states (
            household_id,
            entity_id,
            current_location,
            history_location_1,
            history_location_2,
            is_ghost_mode,
            updated_at
        )
        values (
            p_household_id,
            p_entity_id,
            p_new_location,
            null,
            null,
            false,
            now()
        );
    end if;
end;
$$;

grant execute on function public.push_entity_location(uuid, uuid, jsonb) to authenticated;

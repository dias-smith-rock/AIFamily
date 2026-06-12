-- RevenueCat → user_entitlements sync RPC (service_role only).
-- Deploy in Supabase SQL Editor, then reload API schema cache.

create or replace function public.sync_creator_households_premium(
    p_user_id uuid,
    p_is_premium boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if to_regprocedure('public.resolve_household_creator_user_id(uuid)') is not null then
        update public.households h
        set is_premium = p_is_premium,
            updated_at = now()
        where public.resolve_household_creator_user_id(h.id) = p_user_id;
    else
        update public.households h
        set is_premium = p_is_premium,
            updated_at = now()
        where h.creator_id = p_user_id;
    end if;
end;
$$;

create or replace function public.sync_user_entitlement_from_revenuecat(
    p_user_id uuid,
    p_is_pro boolean,
    p_pro_expires_at timestamptz default null,
    p_plan_purchased text default null,
    p_source text default 'revenuecat'
)
returns table (
    user_id uuid,
    is_pro boolean,
    pro_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := p_user_id;
    v_is_pro boolean := coalesce(p_is_pro, false);
    v_expires timestamptz := p_pro_expires_at;
begin
    if v_user_id is null then
        raise exception 'p_user_id is required';
    end if;

    if v_is_pro then
        insert into public.user_entitlements (user_id, is_pro, pro_expires_at)
        values (v_user_id, true, v_expires)
        on conflict (user_id) do update
        set is_pro = true,
            pro_expires_at = case
                when excluded.pro_expires_at is null then public.user_entitlements.pro_expires_at
                when public.user_entitlements.pro_expires_at is null then excluded.pro_expires_at
                else greatest(public.user_entitlements.pro_expires_at, excluded.pro_expires_at)
            end,
            updated_at = now();

        perform public.sync_creator_households_premium(v_user_id, true);
    else
        update public.user_entitlements ue
        set is_pro = false,
            pro_expires_at = least(coalesce(ue.pro_expires_at, now()), now()),
            updated_at = now()
        where ue.user_id = v_user_id;

        perform public.sync_creator_households_premium(v_user_id, false);
    end if;

    return query
    select ue.user_id, ue.is_pro, ue.pro_expires_at
    from public.user_entitlements ue
    where ue.user_id = v_user_id;
end;
$$;

revoke all on function public.sync_user_entitlement_from_revenuecat(
    uuid, boolean, timestamptz, text, text
) from public;

grant execute on function public.sync_user_entitlement_from_revenuecat(
    uuid, boolean, timestamptz, text, text
) to service_role;

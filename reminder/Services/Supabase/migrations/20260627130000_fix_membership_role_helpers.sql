-- Fix legacy role helpers: household_memberships.role (creator/admin/member),
-- not the obsolete user_role column (owner/manager/executor/viewer).

create or replace function public.get_user_role_in_household(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select hm.role::text
    into v_role
  from public.household_memberships hm
  where hm.household_id = p_household_id
    and hm.user_id = auth.uid()
    and hm.status = 'active'
  limit 1;

  return v_role;
end;
$$;

create or replace function public.current_user_role(target_household_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
    select public.get_user_role_in_household(target_household_id)
$$;

create or replace function public.can_manage_household(target_household_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
    select coalesce(
        public.get_user_role_in_household(target_household_id) in ('creator', 'admin'),
        false
    )
$$;

revoke all on function public.get_user_role_in_household(uuid) from public;
revoke all on function public.current_user_role(uuid) from public;
revoke all on function public.can_manage_household(uuid) from public;

grant execute on function public.get_user_role_in_household(uuid) to authenticated;
grant execute on function public.current_user_role(uuid) to authenticated;
grant execute on function public.can_manage_household(uuid) to authenticated;

notify pgrst, 'reload schema';

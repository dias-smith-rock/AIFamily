-- Deploy in Supabase SQL Editor, then: Settings → API → Reload schema cache (or wait ~1 min).
-- Matches iOS `CreateTaskWithSpatialParams` / `CompleteTaskWithSpatialParams`.

-- 删除同名全部重载，避免 PostgREST「Could not choose the best candidate function」
--（常见于同时存在 p_title text 与 p_title varchar 两个版本）。
do $$
declare
    fn regprocedure;
begin
    for fn in
        select p.oid::regprocedure
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in (
              'create_task_with_spatial',
              'complete_task_with_spatial'
          )
    loop
        execute format('drop function if exists %s', fn);
    end loop;
end;
$$;

create function public.create_task_with_spatial(
    p_title text,
    p_description text,
    p_creator_id uuid,
    p_tenant_id uuid,
    p_geofence jsonb default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row public.tasks;
begin
    insert into public.tasks (
        household_id,
        creator_id,
        title,
        description,
        geofence,
        status,
        priority,
        is_all_day,
        duration_minutes,
        source,
        task_type
    )
    values (
        p_tenant_id,
        p_creator_id,
        p_title,
        p_description,
        p_geofence,
        'new',
        'normal',
        false,
        60,
        'manual',
        'scheduled'
    )
    returning * into v_row;

    return v_row;
end;
$$;

create function public.complete_task_with_spatial(
    p_task_id uuid,
    p_user_id uuid,
    p_completion_location jsonb default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row public.tasks;
begin
    update public.tasks
    set
        status = 'completed',
        completion_location = p_completion_location,
        updated_at = now()
    where id = p_task_id
    returning * into v_row;

    if v_row.id is null then
        raise exception 'task_not_found';
    end if;

    return v_row;
end;
$$;

grant execute on function public.create_task_with_spatial(text, text, uuid, uuid, jsonb) to authenticated;
grant execute on function public.complete_task_with_spatial(uuid, uuid, jsonb) to authenticated;

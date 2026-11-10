-- 任务最近编辑人：与 creator_id 同为 household_memberships.id
alter table public.tasks
  add column if not exists updated_by uuid references public.household_memberships(id);

-- 历史行回填为创建人
update public.tasks
set updated_by = creator_id
where updated_by is null
  and creator_id is not null;

create index if not exists idx_tasks_updated_by on public.tasks(updated_by);

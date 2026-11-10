-- Device tokens for APNs push (task assignment, etc.). One row per (user, token).
create table if not exists public.user_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  apns_token text not null,
  platform text not null default 'ios' check (platform in ('ios')),
  environment text not null default 'production'
    check (environment in ('development', 'production')),
  updated_at timestamptz not null default now(),
  unique (user_id, apns_token)
);

create index if not exists idx_user_device_tokens_user_id
  on public.user_device_tokens(user_id);

alter table public.user_device_tokens enable row level security;

drop policy if exists user_device_tokens_own on public.user_device_tokens;
create policy user_device_tokens_own on public.user_device_tokens
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.user_device_tokens to authenticated;
grant all on public.user_device_tokens to service_role;

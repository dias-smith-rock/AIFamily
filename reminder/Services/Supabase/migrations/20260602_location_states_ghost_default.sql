-- 位置隐身默认关闭：仅用户手动「保持隐藏」后 is_ghost_mode 才为 true。
-- 在 Supabase SQL Editor 执行；新行默认不隐身。

alter table if exists public.location_states
    alter column is_ghost_mode set default false;

comment on column public.location_states.is_ghost_mode is
    '用户手动开启「保持隐藏」时为 true；计时时效隐身仅本机偏好，默认 false。';

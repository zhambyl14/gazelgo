-- Tasu · registration audit
-- Тіркелу кезінде пароль/құпия сөз сақталмайды: тек progress және байланысқа
-- қажет non-sensitive мәндер жазылады. Бұл abandoned signup-тарды модераторға
-- қай қадамда тоқтағанын көруге мүмкіндік береді.

create table if not exists public.registration_drafts (
  id uuid primary key default gen_random_uuid(),
  draft_key text not null unique,
  role text not null default 'client' check (role in ('client','executor')),
  stage integer not null default 0 check (stage between 0 and 3),
  stage_label text not null default '',
  full_name text,
  phone text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_registration_drafts_last_seen
  on public.registration_drafts(last_seen_at desc);

alter table public.registration_drafts enable row level security;

create or replace function public.save_registration_draft(
  p_draft_key text,
  p_role text,
  p_stage integer,
  p_stage_label text,
  p_full_name text default null,
  p_phone text default null,
  p_data jsonb default '{}'::jsonb,
  p_completed boolean default false
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(length(trim(p_draft_key)), 0) < 8
     or p_role not in ('client','executor')
     or p_stage not between 0 and 3 then
    raise exception 'BAD_INPUT';
  end if;

  insert into public.registration_drafts
    (draft_key, role, stage, stage_label, full_name, phone, data, completed_at)
  values
    (trim(p_draft_key), p_role, p_stage, left(coalesce(p_stage_label,''), 120),
     nullif(left(trim(coalesce(p_full_name,'')), 120), ''),
     nullif(left(trim(coalesce(p_phone,'')), 32), ''),
     coalesce(p_data, '{}'::jsonb) - 'password' - 'password2',
     case when p_completed then now() else null end)
  on conflict (draft_key) do update set
    role = excluded.role,
    stage = excluded.stage,
    stage_label = excluded.stage_label,
    full_name = excluded.full_name,
    phone = excluded.phone,
    data = excluded.data,
    last_seen_at = now(),
    completed_at = case when p_completed then now() else registration_drafts.completed_at end;
end;
$$;

grant execute on function public.save_registration_draft(text,text,integer,text,text,text,jsonb,boolean)
  to anon, authenticated;

create or replace function public.mod_registration_drafts()
returns setof public.registration_drafts
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  return query
    select * from public.registration_drafts
    where completed_at is null or last_seen_at > now() - interval '30 days'
    order by completed_at nulls first, last_seen_at desc
    limit 500;
end;
$$;

grant execute on function public.mod_registration_drafts() to authenticated;

-- Жабық чат тарихын модератор көруі үшін суреттерді бірден өшірмейміз.
-- 30 күннен ескі архивтік файлдар ғана тазаланады; мәтіндік хабарламалар
-- support_threads/support_messages ішінде сақтала береді.
create or replace function public.mod_pending_support_images()
returns text[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_paths text[];
begin
  if auth.uid() is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  select coalesce(array_agg(m.image_path), '{}') into v_paths
  from public.support_messages m
  join public.support_threads t on t.id = m.thread_id
  where t.status = 'closed'
    and t.images_cleaned = false
    and t.closed_at < now() - interval '30 days'
    and m.image_path is not null;

  update public.support_threads t
  set images_cleaned = true
  where t.status = 'closed'
    and t.images_cleaned = false
    and t.closed_at < now() - interval '30 days';
  return v_paths;
end;
$$;

grant execute on function public.mod_pending_support_images() to authenticated;

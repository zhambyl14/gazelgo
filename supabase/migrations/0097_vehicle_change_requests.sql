-- ============================================================
-- Tasu · 0097_vehicle_change_requests.sql
-- ============================================================
-- Орындаушы көлігінің деректерін (түрі/санаты, түсі, жылы, маркасы,
-- моделі, нөмірі) ӨЗІ өзгерте алмайды — модераторға өтініш жібереді.
-- Модератор растаса, executor_profiles жаңарады және орындаушыға
-- хабар барады. Бір орындаушыда бір уақытта бір ғана күтіп тұрған өтініш.
-- Идемпотентті.
-- ============================================================

create table if not exists public.vehicle_change_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  vehicle_type text not null,
  vehicle_brand text not null default '',
  vehicle_model text not null default '',
  vehicle_year int,
  vehicle_color text not null default '',
  vehicle_plate text not null default '',
  note text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  moderator_comment text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid
);

create unique index if not exists vehicle_change_requests_one_pending
  on public.vehicle_change_requests (user_id) where status = 'pending';

alter table public.vehicle_change_requests enable row level security;

drop policy if exists vcr_select_own on public.vehicle_change_requests;
create policy vcr_select_own on public.vehicle_change_requests
  for select to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------
-- Орындаушы өтініш жібереді
-- ------------------------------------------------------------
create or replace function public.request_vehicle_change(
  p_type text,
  p_brand text,
  p_model text,
  p_year int,
  p_color text,
  p_plate text,
  p_note text default ''
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.executor_profiles where user_id = v_uid) then
    raise exception 'NOT_EXECUTOR';
  end if;
  if coalesce(trim(p_type), '') = '' then raise exception 'BAD_VEHICLE_TYPE'; end if;
  if p_year is not null and (p_year < 1980 or p_year > extract(year from now())::int + 1) then
    raise exception 'BAD_YEAR';
  end if;

  delete from public.vehicle_change_requests
   where user_id = v_uid and status = 'pending';

  insert into public.vehicle_change_requests
    (user_id, vehicle_type, vehicle_brand, vehicle_model, vehicle_year,
     vehicle_color, vehicle_plate, note)
  values
    (v_uid, trim(p_type), trim(coalesce(p_brand, '')), trim(coalesce(p_model, '')),
     p_year, trim(coalesce(p_color, '')), trim(coalesce(p_plate, '')),
     left(trim(coalesce(p_note, '')), 300))
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.request_vehicle_change(text, text, text, int, text, text, text) to authenticated;

-- ------------------------------------------------------------
-- Модератор: өтініштер тізімі (қазіргі көлігімен қатар)
-- ------------------------------------------------------------
create or replace function public.mod_vehicle_changes(p_status text default 'pending')
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.mod_can('executors') or public.mod_can('applications')) then
    raise exception 'FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'user_id', r.user_id,
      'full_name', p.full_name,
      'phone', p.phone,
      'status', r.status,
      'note', r.note,
      'created_at', r.created_at,
      'moderator_comment', r.moderator_comment,
      'new', jsonb_build_object(
        'vehicle_type', r.vehicle_type, 'vehicle_brand', r.vehicle_brand,
        'vehicle_model', r.vehicle_model, 'vehicle_year', r.vehicle_year,
        'vehicle_color', r.vehicle_color, 'vehicle_plate', r.vehicle_plate),
      'old', jsonb_build_object(
        'vehicle_type', e.vehicle_type, 'vehicle_brand', e.vehicle_brand,
        'vehicle_model', e.vehicle_model, 'vehicle_year', e.vehicle_year,
        'vehicle_color', e.vehicle_color, 'vehicle_plate', e.vehicle_plate)
    ) order by r.created_at desc)
    from public.vehicle_change_requests r
    join public.profiles p on p.id = r.user_id
    left join public.executor_profiles e on e.user_id = r.user_id
    where r.status = coalesce(p_status, 'pending')
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.mod_vehicle_changes(text) to authenticated;

-- ------------------------------------------------------------
-- Модератор: растау / қабылдамау
-- ------------------------------------------------------------
create or replace function public.mod_vehicle_change_resolve(
  p_id uuid,
  p_approve boolean,
  p_comment text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  if not (public.mod_can('executors') or public.mod_can('applications')) then
    raise exception 'FORBIDDEN';
  end if;
  select * into r from public.vehicle_change_requests
   where id = p_id and status = 'pending' for update;
  if not found then raise exception 'NOT_PENDING'; end if;

  if p_approve then
    update public.executor_profiles set
      vehicle_type = r.vehicle_type,
      vehicle_brand = r.vehicle_brand,
      vehicle_model = r.vehicle_model,
      vehicle_year = r.vehicle_year,
      vehicle_color = r.vehicle_color,
      vehicle_plate = r.vehicle_plate
    where user_id = r.user_id;
  end if;

  update public.vehicle_change_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    moderator_comment = nullif(trim(coalesce(p_comment, '')), ''),
    resolved_at = now(),
    resolved_by = auth.uid()
  where id = p_id;

  perform public.send_push(
    case when p_approve then 'Көлік деректері жаңартылды'
         else 'Көлік өзгерту өтініші қабылданбады' end,
    case when p_approve then 'Модератор өтінішіңізді растады.'
         else coalesce(nullif(trim(coalesce(p_comment, '')), ''),
                       'Модератор өтінішті қабылдамады.') end,
    jsonb_build_object('type', 'vehicle_change'),
    array[r.user_id],
    case when p_approve then 'Данные автомобиля обновлены'
         else 'Заявка на смену авто отклонена' end,
    case when p_approve then 'Модератор подтвердил вашу заявку.'
         else coalesce(nullif(trim(coalesce(p_comment, '')), ''),
                       'Модератор отклонил заявку.') end
  );
end;
$$;
grant execute on function public.mod_vehicle_change_resolve(uuid, boolean, text) to authenticated;

notify pgrst, 'reload schema';

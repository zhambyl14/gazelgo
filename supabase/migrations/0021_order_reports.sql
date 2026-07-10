-- GazelGo · 0021_order_reports.sql
-- «Күдікті жүк туралы хабарлау»: клиент те, орындаушы да заказ бойынша
-- модераторға дереу белгі бере алады (тыйым салынған жүкке күдіктенсе).
-- Хабарлама екі жерге жазылады: (1) құрылымдалған order_reports кестесі
-- (аудит/фильтр үшін), (2) бар support_send() арқылы модератордың қолдау
-- чатына — сол арқылы бөлек модератор UI жасамай-ақ, дереу көрінеді.

create table if not exists public.order_reports (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  reporter_id   uuid not null references public.profiles(id) on delete cascade,
  reporter_role text not null,
  reason        text not null default '',
  status        text not null default 'open',
  created_at    timestamptz not null default now()
);
create index if not exists idx_order_reports_order on public.order_reports (order_id);
create index if not exists idx_order_reports_status on public.order_reports (status, created_at desc);

alter table public.order_reports enable row level security;

drop policy if exists order_reports_select on public.order_reports;
create policy order_reports_select on public.order_reports
  for select to authenticated
  using (reporter_id = auth.uid() or public.is_moderator());
-- INSERT саясаты ӘДЕЙІ жоқ — жазба тек төмендегі SECURITY DEFINER RPC
-- арқылы ғана жасалады (валидация: тек заказдың нақты қатысушысы жібере алады).

create or replace function public.report_order(p_order uuid, p_reason text default '')
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role text;
  v_reason text;
  v_body text;
  v_report_id uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  if o.client_id = v_uid then
    v_role := 'client';
  elsif o.executor_id = v_uid then
    v_role := 'executor';
  else
    raise exception 'FORBIDDEN';
  end if;

  v_reason := coalesce(trim(p_reason), '');

  insert into public.order_reports (order_id, reporter_id, reporter_role, reason)
  values (p_order, v_uid, v_role, v_reason)
  returning id into v_report_id;

  v_body := '🚨 КҮДІКТІ ЖҮК ТУРАЛЫ ХАБАРЛАМА — заказ #' || left(p_order::text, 8)
    || E'\nХабарлаған: ' || (case when v_role = 'client' then 'Клиент' else 'Газелист' end)
    || E'\nЖүк сипаттамасы: ' || coalesce(nullif(o.cargo_desc, ''), '(жазылмаған)')
    || (case when v_reason <> '' then E'\nСебебі: ' || v_reason else '' end);

  perform public.support_send(v_body, null);

  return v_report_id;
end;
$$;
revoke all on function public.report_order(uuid, text) from public, anon;
grant execute on function public.report_order(uuid, text) to authenticated;

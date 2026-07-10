-- GazelGo · 0018_abuse_limits.sql
-- Теріс пайдалануға қарсы серверлік шектеулер («комитет аудиті» қорытындысы):
--
-- 1) СПАМ-ЗАКАЗ: клиент заказ беріп → өзі тоқтатып → қайта беріп газелисттерді
--    әуре қылуы мүмкін еді (клиенттік кодта тек TOO_MANY_ACTIVE=5 бар-тын).
--    Енді: соңғы 60 минутта ӨЗІ тоқтатқан заказы 3-ке жетсе — жаңа заказ
--    беруге уақытша тыйым (TOO_MANY_CANCELS). Триггер арқылы — сondықтан
--    create_order қай нұсқада болса да (0013/0014) автоматты күшінде.
--
-- 2) ТІРКЕЛУ ЛИМИТІ: signup edge function-ға арналған оқиға журналы
--    (auth_events). Бір IP-ден сағатына 5 тіркелуден артық — RATE_LIMITED.
--    Кесте тек service_role-ге ашық (RLS қосулы, саясат жоқ).

-- ---------- 1) клиенттің бас тарту спамына тосқауыл ----------
create or replace function public.check_client_order_abuse()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_cancels int;
begin
  select count(*) into v_cancels
    from public.orders o
   where o.client_id = new.client_id
     and o.status = 'cancelled'
     and o.cancelled_by = new.client_id
     and o.created_at > now() - interval '60 minutes';
  if v_cancels >= 3 then
    raise exception 'TOO_MANY_CANCELS';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_client_order_abuse on public.orders;
create trigger trg_client_order_abuse
  before insert on public.orders
  for each row execute function public.check_client_order_abuse();

-- ---------- 2) тіркелу оқиғаларының журналы (IP rate-limit) ----------
create table if not exists public.auth_events (
  id         bigint generated always as identity primary key,
  ip         text not null,
  kind       text not null default 'signup',
  created_at timestamptz not null default now()
);
create index if not exists idx_auth_events_ip
  on public.auth_events (ip, kind, created_at desc);

-- Тек service_role (edge function) жазады/оқиды — RLS қосулы, саясат жоқ.
alter table public.auth_events enable row level security;

-- Ескі жазбаларды тазалау (журнал өспес үшін, күніне бір рет)
do $$ begin
  perform cron.unschedule('gazelgo-auth-events-cleanup');
exception when others then null; end $$;
select cron.schedule(
  'gazelgo-auth-events-cleanup',
  '0 3 * * *',
  $$delete from public.auth_events where created_at < now() - interval '7 days'$$
);

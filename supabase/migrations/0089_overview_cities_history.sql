-- ============================================================
-- Tasu · 0089_overview_cities_history.sql
-- ============================================================
-- Модератор «Шолу» бөліміне:
--   1) mod_city_stats(p_days) — ҚАЛА-ҚАЛА бойынша: клиенттер, орындаушылар
--      (расталған / линияда), заказдар (берілген / аяқталған / тоқтаған /
--      қазір жүріп жатқан), неше адам заказ берді.
--   2) mod_status_changes(p_limit, p_order) — заказ статусын КІМ өзгерткені
--      (қолдау қызметкері мен модератор): әрекеттер журналынан (0082
--      audit_orders триггері жазады), аты-жөнімен. p_order берілсе — тек
--      сол заказдың тарихы.
--   3) mod_executor_history(p_user) — орындаушыны КІМ тіркеді/қабылдады/
--      бұғаттады/өзгертті: журнал + ағымдағы moderated_by.
--
-- Клиенттің қаласы профильде сақталмайды, сондықтан ол оның ЕҢ СОҢҒЫ
-- заказының алу қаласы (from_city) бойынша анықталады; заказы жоқ клиент
-- «—» тобына түседі.
--
-- Рұқсат: функциялар ішінде mod_can(...) тексереді (staff_request_guard-қа
-- тиіспейміз). Идемпотентті. SQL Editor-да ҚОЛМЕН қолданылады (0088-ден кейін).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Қала бойынша статистика
-- ------------------------------------------------------------
create or replace function public.mod_city_stats(p_days int default 7)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_since timestamptz;
  v_days  int := greatest(1, least(coalesce(p_days, 7), 365));
begin
  if auth.uid() is null or not public.is_moderator()
     or not public.mod_can('overview') then
    raise exception 'FORBIDDEN';
  end if;

  -- 1 күн = бүгін (түн ортасынан), қалғаны — соңғы N күн.
  v_since := case when v_days = 1 then date_trunc('day', now())
                  else now() - make_interval(days => v_days) end;

  return coalesce((
    with cl as (            -- клиенттер: қаласы = соңғы заказының алу қаласы
      select coalesce(nullif(trim(lo.from_city), ''), '—') as city, count(*) as n
        from public.profiles p
        left join lateral (
          select o.from_city from public.orders o
           where o.client_id = p.id order by o.created_at desc limit 1
        ) lo on true
       where p.has_client_role and p.role <> 'moderator' and p.deleted_at is null
       group by 1
    ),
    ex as (                 -- орындаушылар
      select coalesce(nullif(trim(ep.city), ''), '—') as city,
             count(*) as total,
             count(*) filter (where ep.status = 'approved') as approved,
             count(*) filter (
               where ep.status = 'approved' and coalesce(ep.on_line, true)
                 and exists (select 1 from public.tariff_sessions ts
                              where ts.executor_id = ep.user_id
                                and ts.expires_at > now())) as on_line
        from public.executor_profiles ep
        join public.profiles p on p.id = ep.user_id and p.deleted_at is null
       group by 1
    ),
    ord as (                -- заказдар (таңдалған кезеңде) + қазір жүргендер
      select coalesce(nullif(trim(o.from_city), ''), '—') as city,
             count(*) filter (where o.created_at >= v_since) as orders,
             count(distinct o.client_id) filter (where o.created_at >= v_since) as customers,
             count(*) filter (where o.created_at >= v_since and o.status = 'completed') as completed,
             count(*) filter (where o.created_at >= v_since and o.status in ('cancelled','expired')) as cancelled,
             count(*) filter (where o.status in ('searching','accepted','arrived','loading','in_transit')) as active
        from public.orders o
       group by 1
    ),
    cities as (
      select city from cl union select city from ex union select city from ord
    )
    select jsonb_agg(jsonb_build_object(
             'city',      c.city,
             'clients',   coalesce(cl.n, 0),
             'executors', coalesce(ex.total, 0),
             'approved',  coalesce(ex.approved, 0),
             'on_line',   coalesce(ex.on_line, 0),
             'orders',    coalesce(ord.orders, 0),
             'customers', coalesce(ord.customers, 0),
             'completed', coalesce(ord.completed, 0),
             'cancelled', coalesce(ord.cancelled, 0),
             'active',    coalesce(ord.active, 0)
           ) order by coalesce(ord.orders, 0) desc,
                      coalesce(cl.n, 0) + coalesce(ex.total, 0) desc,
                      c.city)
      from cities c
      left join cl  on cl.city  = c.city
      left join ex  on ex.city  = c.city
      left join ord on ord.city = c.city
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_city_stats(int) to authenticated;

-- ------------------------------------------------------------
-- 2) Заказ статусын кім өзгертті
-- ------------------------------------------------------------
create or replace function public.mod_status_changes(
  p_limit int default 30,
  p_order uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator()
     or not (public.mod_can('overview') or public.mod_can('orders')
             or public.mod_can('line')) then
    raise exception 'FORBIDDEN';
  end if;

  return coalesce((
    select jsonb_agg(x order by x.at desc)
      from (
        select l.id,
               l.target_id                         as order_id,
               l.details ->> 'from'                as from_status,
               l.details ->> 'to'                  as to_status,
               l.created_at                        as at,
               l.moderator_id,
               m.full_name                         as who,
               (m.staff_perms is not null)         as is_staff,
               o.from_city
          from public.mod_audit_log l
          left join public.profiles m on m.id = l.moderator_id
          left join public.orders o on o.id::text = l.target_id
         where l.action = 'order_status'
           and (p_order is null or l.target_id = p_order::text)
         order by l.created_at desc
         limit greatest(1, least(coalesce(p_limit, 30), 200))
      ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_status_changes(int, uuid) to authenticated;

-- ------------------------------------------------------------
-- 3) Орындаушыны кім тіркеді / қабылдады / өзгертті
-- ------------------------------------------------------------
create or replace function public.mod_executor_history(p_user uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator()
     or not (public.mod_can('executors') or public.mod_can('applications')) then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'registered_at', (select created_at from public.executor_profiles where user_id = p_user),
    'moderated_at',  (select moderated_at from public.executor_profiles where user_id = p_user),
    'moderated_by',  (select m.full_name
                        from public.executor_profiles ep
                        join public.profiles m on m.id = ep.moderated_by
                       where ep.user_id = p_user),
    'events', coalesce((
      select jsonb_agg(x order by x.at desc)
        from (
          select l.action,
                 l.details,
                 l.created_at as at,
                 m.full_name  as who,
                 (m.staff_perms is not null) as is_staff
            from public.mod_audit_log l
            left join public.profiles m on m.id = l.moderator_id
           where l.target_id = p_user::text
             and l.action in ('executor_status','executor_create','executor_update',
                              'executor_delete','executor_umay','docs_requested',
                              'balance_adjust','account_block','account_unblock')
           order by l.created_at desc
           limit 50
        ) x
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.mod_executor_history(uuid) to authenticated;

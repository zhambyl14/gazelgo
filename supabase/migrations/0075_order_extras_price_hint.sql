-- ============================================================
-- Tasu · 0075_order_extras_price_hint.sql
-- ============================================================
--   1) ҚОСЫМША ҚЫЗМЕТТЕР (міндетті емес): тиеуші саны, қабат, лифт.
--      Газель/жүк заказдарының көбінде «жүк тиеуші керек пе, нешінші
--      қабат, лифт бар ма» деген сұрақ бар — бұрын клиент оны түсініктемеге
--      еркін мәтінмен жазатын (не мүлдем жазбайтын), орындаушы баға
--      қойғанда білмейтін. Енді — нақты өрістер, лентада белгі болып шығады.
--   2) update_order_details — клиент заказды ІЗДЕУ кезінде өңдей алады:
--      сипаттама, түсініктеме, қосымша қызметтер (бұрын тек бағаны көтеруге
--      болатын — қате жазылса, заказды тоқтатып, қайта беру керек еді).
--      create_order-ге ТИІСПЕЙМІЗ: қосымша өрістер заказ құрылған соң осы
--      функциямен жазылады (ескі қосымша нұсқалары бұрынғыдай жұмыс істейді).
--   3) order_price_hint — ҰСЫНЫЛАТЫН БАҒА: соңғы 90 күндегі ұқсас (көлік
--      түрі, қашықтық, қала) аяқталған заказдардың нақты бағасы бойынша
--      «әдетте 5 500 – 7 000 ₸». Дерек аз болса (< 5) — ештеңе қайтармайды
--      (қате кеңес бергеннен үндемеген жақсы). `pricing_hint` баптауымен
--      қосылады/өшіріледі (0060-та бұрыннан бар, әдепкі — қосулы).
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0074-тен кейін).
-- ============================================================

-- ============================================================
-- 1) Қосымша қызметтер өрістері
-- ============================================================
alter table public.orders add column if not exists loaders smallint not null default 0;
alter table public.orders add column if not exists floor_from smallint;
alter table public.orders add column if not exists floor_to smallint;
alter table public.orders add column if not exists has_elevator boolean;

do $$ begin
  alter table public.orders add constraint orders_loaders_range
    check (loaders between 0 and 10);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.orders add constraint orders_floors_range
    check ((floor_from is null or floor_from between -5 and 60)
       and (floor_to is null or floor_to between -5 and 60));
exception when duplicate_object then null; end $$;

-- ============================================================
-- 2) Клиент заказды іздеу кезінде өңдейді
-- ============================================================
-- null параметр — «өзгертпе». Қосымша қызметтер БІР ТОП болып жазылады:
-- p_loaders берілсе, қабат пен лифт те берілген мәнге ауысады (null —
-- тазалау).
create or replace function public.update_order_details(
  p_order uuid,
  p_cargo text default null,
  p_comment text default null,
  p_loaders int default null,
  p_floor_from int default null,
  p_floor_to int default null,
  p_elevator boolean default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;

  if p_cargo is not null and trim(p_cargo) = '' then
    raise exception 'BAD_INPUT';
  end if;
  if p_loaders is not null and (p_loaders < 0 or p_loaders > 10) then
    raise exception 'BAD_INPUT';
  end if;
  if (p_floor_from is not null and (p_floor_from < -5 or p_floor_from > 60))
     or (p_floor_to is not null and (p_floor_to < -5 or p_floor_to > 60)) then
    raise exception 'BAD_INPUT';
  end if;

  update public.orders
     set cargo_desc = case when p_cargo is null then cargo_desc
                           else left(trim(p_cargo), 500) end,
         comment = case when p_comment is null then comment
                        else left(trim(p_comment), 500) end,
         loaders = coalesce(p_loaders, loaders),
         floor_from = case when p_loaders is null then floor_from
                           else p_floor_from end,
         floor_to = case when p_loaders is null then floor_to
                         else p_floor_to end,
         has_elevator = case when p_loaders is null then has_elevator
                             else p_elevator end
   where id = p_order;
end;
$$;

grant execute on function
  public.update_order_details(uuid, text, text, int, int, int, boolean)
  to authenticated;

-- ============================================================
-- 3) Ұсынылатын баға
-- ============================================================
create index if not exists idx_orders_completed_vehicle
  on public.orders (vehicle_type, completed_at desc)
  where status = 'completed';

create or replace function public.order_price_hint(
  p_vehicle text,
  p_distance_km numeric,
  p_city text default null,
  p_intercity boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean;
  v_lo numeric;
  v_hi numeric;
  v_city text := public.norm_city(p_city);
  v_n int := 0;
  v_p25 numeric;
  v_p50 numeric;
  v_p75 numeric;
begin
  if p_vehicle is null or p_distance_km is null or p_distance_km <= 0 then
    return null;
  end if;

  select coalesce((value->>'enabled')::boolean, true) into v_enabled
    from public.app_settings where key = 'pricing_hint';
  if not coalesce(v_enabled, true) then return null; end if;

  -- Ұқсас қашықтық терезесі: қысқа сапарларда ±3 км, ұзындарда −40% / +50%.
  v_lo := greatest(p_distance_km * 0.6, p_distance_km - 3);
  v_hi := p_distance_km * 1.5 + 3;

  -- 1-қадам: СОЛ ҚАЛАДАҒЫ заказдар (қала ішіндегі заказ үшін).
  if not coalesce(p_intercity, false) and v_city is not null then
    select count(*),
           percentile_cont(0.25) within group (order by s.price),
           percentile_cont(0.5)  within group (order by s.price),
           percentile_cont(0.75) within group (order by s.price)
      into v_n, v_p25, v_p50, v_p75
      from (
        select coalesce(o.final_price, o.client_price)::numeric as price
          from public.orders o
         where o.status = 'completed'
           and o.completed_at > now() - interval '90 days'
           and o.vehicle_type::text = p_vehicle
           and coalesce(o.final_price, o.client_price) > 0
           and o.distance_km between v_lo and v_hi
           and public.norm_city(o.from_city) = v_city
      ) s;
  end if;

  -- 2-қадам: дерек аз — барлық қала бойынша (межгород белгісі сәйкес).
  if coalesce(v_n, 0) < 5 then
    select count(*),
           percentile_cont(0.25) within group (order by s.price),
           percentile_cont(0.5)  within group (order by s.price),
           percentile_cont(0.75) within group (order by s.price)
      into v_n, v_p25, v_p50, v_p75
      from (
        select coalesce(o.final_price, o.client_price)::numeric as price
          from public.orders o
         where o.status = 'completed'
           and o.completed_at > now() - interval '90 days'
           and o.vehicle_type::text = p_vehicle
           and coalesce(o.final_price, o.client_price) > 0
           and o.distance_km between v_lo and v_hi
           and (coalesce(public.norm_city(o.from_city), '')
                  <> coalesce(public.norm_city(o.to_city), ''))
               = coalesce(p_intercity, false)
      ) s;
  end if;

  if coalesce(v_n, 0) < 5 then return null; end if;

  return jsonb_build_object(
    'low',     (round(v_p25 / 100) * 100)::bigint,
    'typical', (round(v_p50 / 100) * 100)::bigint,
    'high',    (round(v_p75 / 100) * 100)::bigint,
    'samples', v_n
  );
end;
$$;

grant execute on function public.order_price_hint(text, numeric, text, boolean)
  to anon, authenticated;

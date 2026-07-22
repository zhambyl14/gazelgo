-- ============================================================
-- 0041 — Заказдар лентасы БАРЛЫҚ орындаушыға көрінеді (қала сүзгісіз)
-- ============================================================
-- Талап: заказдарды КӨРУ үшін тариф сатып алудың да, қаланың сәйкес
-- келуінің де қажеті жоқ — сәйкес көлік түріндегі БАРЛЫҚ заказ лентада
-- көрінеді. Бірақ нақты ҚАБЫЛДАУ (ұсыныс беру/қабылдау/тариф сатып алу)
-- бұрынғыдай тек расталған әрі белсенді тарифі бар орындаушыға рұқсат —
-- ҮСТІНЕ ҚАЛА ЕРЕЖЕСІ қосылады: ЖЕРГІЛІКТІ (қала ішіндегі) заказды тек
-- сол қаладағы орындаушы алады, ал МЕЖГОРОД (қалааралық) заказды кез
-- келген қаладағы орындаушы ала алады (қала сәйкессіздігі кедергі емес).
--
-- Көріну логикасын (`exec_can_see`) әрекет логикасынан (`exec_can_take`)
-- бөлеміз: лента `exec_can_see`-ті, ұсыныс/қабылдау `exec_can_take`-ті
-- қолданады.
-- ============================================================

-- Тек КӨРІНУ шарты: көлік түрі сәйкестігі ғана. Мақұлдау статусы да,
-- тариф сыйымдылығы да, ҚАЛА да ТЕКСЕРІЛМЕЙДІ (тек орындаушы профилі
-- болуы жеткілікті) — лентада барлық сәйкес көлік түріндегі заказ көрінеді.
create or replace function public.exec_can_see(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found then return false; end if;      -- статус ТЕКСЕРІЛМЕЙДІ
  if o.client_id = p_exec then return false; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- ҚАЛА БОЙЫНША СҮЗГІ ЖОҚ — қала ережесі тек ҚАБЫЛДАУ сәтінде
  -- (exec_can_take) тексеріледі, лентада бәрі көрінеді.
  return true;
end;
$$;

-- Әрекет ету шарты = көріну + РАСТАЛҒАН + белсенді тариф (сыйымдылық) +
-- ҚАЛА ЕРЕЖЕСІ (жергілікті заказ тек сол қаладағы орындаушыға, межгород —
-- кез келгенге) + белсенді заказ болса тек сол маршруттың жалғасы.
-- Ұсыныс беру / қабылдау осыны қолданады (сервердегі бөгет — бұрынғыдай).
create or replace function public.exec_can_take(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text; o_to text;
  o_intercity boolean;
  has_active boolean;
  can_stack boolean;
begin
  if not public.exec_can_see(p_exec, p_order) then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found or ep.status <> 'approved' then return false; end if;
  if not public.exec_has_capacity(p_exec) then return false; end if;

  select * into o from public.orders where id = p_order;
  if not found then return false; end if;

  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);
  o_intercity := (o_from is not null and o_to is not null and o_from <> o_to);

  -- ҚАЛА ЕРЕЖЕСІ: ЖЕРГІЛІКТІ (межгород ЕМЕС) заказды тек сол қаладағы
  -- орындаушы ала алады. МЕЖГОРОД заказды — қаласы сәйкес келмесе де
  -- кез келген орындаушы ала алады.
  if not o_intercity then
    if exec_city is not null and o_from is not null and exec_city <> o_from then
      return false;
    end if;
  end if;

  has_active := exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit'));

  if not has_active then return true; end if;

  -- Бір мезгілде екінші заказ — тек ағымдағы межгород маршруттың
  -- жалғасы болса ғана (басқа бағыттағы/жергілікті заказды алмайды).
  can_stack := o_intercity and exists (
    select 1 from public.orders a
    where a.executor_id = p_exec
      and a.status in ('accepted','arrived','loading','in_transit')
      and public.norm_city(a.from_city) is not null
      and public.norm_city(a.to_city) is not null
      and public.norm_city(a.from_city) <> public.norm_city(a.to_city)
      and (public.norm_city(a.to_city) = o_to
        or public.norm_city(a.from_city) = o_from));
  return can_stack;
end;
$$;

-- Лента енді КӨРІНУ шартын қолданады — қала/тариф/мақұлдау ескерусіз
-- сәйкес көлік түріндегі БАРЛЫҚ заказ көрінеді (әрекет сервер жағында
-- exec_can_take ішінде бөгеледі).
create or replace function public.executor_feed()
returns setof public.orders
language sql stable security definer
set search_path = public, pg_temp
as $$
  select o.*
  from public.orders o
  where o.status = 'searching'
    and o.type = 'bidding'
    and public.exec_can_see(auth.uid(), o.id)
  order by o.created_at desc
  limit 100;
$$;

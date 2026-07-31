-- ============================================================
-- Tasu · 0053_feed_city_filter.sql
-- ============================================================
-- ЛЕНТАДАҒЫ ҚАЛА СҮЗГІСІ (бұған дейін тек ҚАБЫЛДАУ сәтінде тексерілетін).
--
-- 0041-де («exec_can_see-ті exec_can_take-тен бөлу») ӘДЕЙІ шешім
-- қабылданған еді: лентада БАРЛЫҚ сәйкес көлік түріндегі заказ көрінсін,
-- қала ережесі тек ҚАБЫЛДАУ сәтінде тексерілсін. Бұл орындаушыға өз
-- қаласында ЖОҚ, бірақ басқа қалада бар заказдарды да «көру мүмкіндігін»
-- беру үшін алынған шешім болатын.
--
-- Іс жүзінде бұл шатастырады: мыс. Астанадағы орындаушыға Тараз қаласының
-- ІШІНДЕГІ (Тараз→Тараз) заказ көрінеді, бірақ ол оны АЛА АЛМАЙДЫ (басқа
-- қала). Енді лентаның өзі осы сүзгіні қолданады:
--   · ЖЕРГІЛІКТІ (from_city == to_city) заказ — тек СОЛ қаладағы
--     орындаушыға көрінеді;
--   · МЕЖГОРОД (from_city != to_city) заказ — қаласына қарамастан БӘРІНЕ
--     көрінеді (бұрынғыдай).
-- Орындаушының қаласы бапталмаса (`executor_profiles.city is null`) —
-- сүзгі қолданылмайды, бәрі көрінеді (бұрынғы тәртіп сақталады).
--
-- МАҚҰЛДАУ СТАТУСЫ бұрынғыдай ТЕКСЕРІЛМЕЙДІ — pending орындаушы да лентаны
-- толық көреді (тек ала алмайды), бұл ӨЗГЕРМЕЙДІ.
--
-- ЕСКЕРТУ: 0052-ден КЕЙІН орындаңыз. Идемпотентті.
-- ============================================================

create or replace function public.exec_can_see(p_exec uuid, p_order uuid)
returns boolean
language plpgsql stable
set search_path = public, pg_temp
as $$
declare
  o record;
  ep record;
  exec_city text;
  o_from text;
  o_to   text;
begin
  select * into o from public.orders where id = p_order;
  if not found then return false; end if;
  if o.status <> 'searching' then return false; end if;

  select * into ep from public.executor_profiles where user_id = p_exec;
  if not found then return false; end if;      -- статус ТЕКСЕРІЛМЕЙДІ

  if o.client_id = p_exec then return false; end if;

  -- КӨЛІК ТҮРІ: заказ тек сол түрдегі орындаушыға көрінеді
  if o.vehicle_type is distinct from ep.vehicle_type then return false; end if;

  -- ҚАЛА СҮЗГІСІ (0053): жергілікті заказ тек сол қаладағы орындаушыға
  -- КӨРІНЕДІ де. Межгород — бәріне. Қала бапталмаса — сүзгі жоқ.
  exec_city := public.norm_city(ep.city);
  o_from := public.norm_city(o.from_city);
  o_to   := public.norm_city(o.to_city);

  if exec_city is not null and o_from is not null
     and (o_to is null or o_from = o_to)  -- жергілікті (межгород емес)
     and exec_city <> o_from then
    return false;
  end if;

  return true;
end;
$$;

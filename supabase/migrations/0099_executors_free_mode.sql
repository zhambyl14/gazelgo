-- ============================================================
-- Tasu · 0099_executors_free_mode.sql
-- ============================================================
-- «ОРЫНДАУШЫЛАР ТЕГІН» режимі. Модератор Баптаулардан қосса:
--   * тариф сатып алудың / баланс толтырудың қажеті жоқ — орындаушы
--     әрқашан тарифте деп есептеледі (exec_has_capacity = true), заказ
--     қабылдағанда ештеңе шегерілмейді (consume_order сессия таппайды);
--   * әрқашан ЛИНИЯДА: on_line күші қосылады, өшіру мүмкін емес;
--   * қосымшада орындаушының басты бетіндегі баланс таблеткасы мен
--     тариф карточкасы, мәзірдегі «Тариф»/«Баланс» жасырылады.
-- Модератор режимді өшіріп, тарифті (мыс. 24 сағатқа 200 ₸) қайта қойса —
-- бәрі бұрынғыдай шығады, бұрынғы тариф сессиялары сақталады.
--
-- executor_stats() қайта жазылмайды: бұрынғысы executor_stats_base()
-- болып қалады да, жаңа орауыш free_mode / has_tariff / on_line қосады.
-- Идемпотентті. Supabase SQL Editor-да не MCP арқылы қолданылады (0098-ден кейін).
-- ============================================================

insert into public.app_settings (key, value)
values ('executors_free', jsonb_build_object('enabled', false))
on conflict (key) do nothing;

create or replace function public.executors_free()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select (value->>'enabled')::boolean
      from public.app_settings where key = 'executors_free'
  ), false);
$$;

grant execute on function public.executors_free() to anon, authenticated;

-- Тегін режимде — әрқашан сыйымдылық бар (0029 нұсқасы + бір шарт).
create or replace function public.exec_has_capacity(p_exec uuid)
returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  select public.executors_free() or exists (
    select 1 from public.tariff_sessions
    where executor_id = p_exec
      and ((not is_trial and coalesce(orders_left,0) > 0 and expires_at > now())
        or (is_trial and expires_at > now()))
  );
$$;

-- Линия: тегін режимде өшіруге болмайды (0011 нұсқасы + бір шарт).
create or replace function public.set_on_line(p_value boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  update public.executor_profiles
     set on_line = (p_value or public.executors_free())
   where user_id = v_uid;
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

grant execute on function public.set_on_line(boolean) to authenticated;

-- executor_stats орауышы.
do $$ begin
  if to_regprocedure('public.executor_stats_base()') is null then
    alter function public.executor_stats() rename to executor_stats_base;
  end if;
end $$;

revoke execute on function public.executor_stats_base() from public, anon, authenticated;

create or replace function public.executor_stats()
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v jsonb := public.executor_stats_base();
  v_free boolean := public.executors_free();
begin
  v := v || jsonb_build_object('free_mode', v_free);
  if v_free and coalesce((v->>'no_profile')::boolean, false) = false then
    v := v || jsonb_build_object(
      'has_tariff', true, 'simple_active', true, 'on_line', true);
  end if;
  return v;
end;
$$;

grant execute on function public.executor_stats() to authenticated;

-- Модератор қосқышы. Қосқанда барлық орындаушы бірден линияға шығады.
create or replace function public.mod_set_executors_free(p_enabled boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.app_settings (key, value)
  values ('executors_free', jsonb_build_object('enabled', coalesce(p_enabled, false)))
  on conflict (key) do update set value = excluded.value;

  if coalesce(p_enabled, false) then
    update public.executor_profiles set on_line = true where on_line is distinct from true;
  end if;

  perform public.mod_audit('executors_free', 'setting', 'executors_free',
    jsonb_build_object('enabled', coalesce(p_enabled, false)));
end;
$$;

grant execute on function public.mod_set_executors_free(boolean) to authenticated;

notify pgrst, 'reload schema';

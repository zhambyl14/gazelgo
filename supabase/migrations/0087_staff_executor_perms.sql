-- ============================================================
-- Tasu · 0087_staff_executor_perms.sql
-- ============================================================
-- ҚЫЗМЕТКЕРГЕ ДӘЛІРЕК РҰҚСАТ: «Орындаушылар» бөлімі үш деңгейге бөлінді.
--
--   executors        — қарау: тізім, іздеу, карточка, құжат жаңартуды сұрау
--   executors_edit   — орындаушыны қолмен қосу, деректерін өзгерту
--                      (аты, телефон, қала, көлік), Ұмай белгісі
--   executors_block  — бұғаттау / бұғаттан шығару
--
-- Орындаушыны БІРЖОЛА ЖОЮ — рұқсат емес: тек толық модератор
-- (executor-admin функциясы, 'delete').
--
--   * staff_perm_keys() — екі жаңа кілт қосылды.
--   * mod_set_executor_status — бұғаттау/шығару енді 'executors_block'
--     рұқсатын талап етеді (растау/қабылдамау — бұрынғыдай
--     'applications' не 'executors').
--   * mod_set_executor_umay — 'executors_edit' талап етеді.
--   * Бұрын 'executors' рұқсаты бар қызметкерлерге 'executors_block'
--     беріледі (олар бұрын да бұғаттай алатын — әрекет сақталады).
--     'executors_edit' АВТОМАТТЫ БЕРІЛМЕЙДІ: бұл жаңа мүмкіндік.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0086-дан кейін).
-- ============================================================

create or replace function public.staff_perm_keys()
returns text[]
language sql immutable
as $$
  select array[
    'overview','line','live_map','orders','applications','executors',
    'executors_edit','executors_block',
    'clients','balance','topups','support','reports','order_chats',
    'broadcast','news','vehicles','settings','audit'
  ]::text[];
$$;

-- 0040 нұсқасы + бұғаттау/шығару рұқсатын тексеру.
create or replace function public.mod_set_executor_status(p_user uuid, p_status text, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_status public.executor_status;
  v_old public.executor_status;
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  v_status := p_status::public.executor_status;
  if v_status not in ('approved','rejected','blocked') then raise exception 'BAD_STATUS'; end if;

  select status into v_old from public.executor_profiles where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;

  if v_status = 'blocked' or v_old = 'blocked' then
    -- бұғаттау не бұғаттан шығару ('executors_block'); растау/қабылдамау — 'applications'
    if not public.mod_can('executors_block') then
      raise exception 'NO_PERMISSION' using errcode = '42501';
    end if;
  elsif not public.mod_can('applications') then
    raise exception 'NO_PERMISSION' using errcode = '42501';
  end if;

  update public.executor_profiles
     set status = v_status,
         moderation_comment = nullif(trim(coalesce(p_comment,'')),''),
         moderated_by = v_uid,
         moderated_at = now()
   where user_id = p_user;

  -- Растағанда триал БЕРІЛМЕЙДІ (алынып тасталды).

  if v_status = 'blocked' then
    update public.tariff_sessions set expires_at = now(), orders_left = 0
     where executor_id = p_user
       and ((is_trial and expires_at > now()) or (not is_trial and coalesce(orders_left,0) > 0));
  end if;
end;
$$;

create or replace function public.mod_set_executor_umay(p_user uuid, p_on boolean)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator()
     or not public.mod_can('executors_edit') then
    raise exception 'FORBIDDEN';
  end if;
  if exists (select 1 from public.profiles
              where id = auth.uid() and blocked_at is not null) then
    raise exception 'NO_PERMISSION' using errcode = '42501';
  end if;

  update public.executor_profiles
     set is_umay = coalesce(p_on, false)
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;

  perform public.mod_audit('executor_umay', 'executor', p_user::text,
    jsonb_build_object('on', coalesce(p_on, false)));
end;
$$;

-- Бұрынғы «executors» қызметкерлері бұғаттау мүмкіндігін сақтайды.
update public.profiles
   set staff_perms = (
     select array_agg(distinct k order by k)
       from unnest(staff_perms || array['executors_block']) k
   )
 where role = 'moderator'
   and staff_perms is not null
   and 'executors' = any(staff_perms)
   and not ('executors_block' = any(staff_perms));

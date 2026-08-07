-- ============================================================
-- Tasu · 0062_referral_anti_farming.sql
-- ============================================================
-- 0061-де executor бонусы КОД ЕНГІЗІЛГЕН сәтте бірден берілетін. Пайдаланушы
-- (2026-08-07) дұрыс байқады: бұл жалған/бос аккаунттармен «өзіне-өзі»
-- бонус фармить жасауға жол ашады (тіркеліп қана, ешбір заказ орындамай).
--
-- ТҮЗЕТУ: сыйақы ЕНДІ шақырылған адамның БІРІНШІ АЯҚТАЛҒАН ЗАКАЗЫНДА ғана
-- беріледі (нақты жұмыс жасалғанда):
--   · Шақырылған ОРЫНДАУШЫ болса — 1-ші аяқталған заказында шақырушының
--     БАЛАНСЫНА нақты сома түседі (executor_bonus_amount, бұрынғыдай).
--   · Шақырылған КЛИЕНТ болса — 1-ші аяқталған заказында шақырушының
--     referral_count САНАҒЫ өседі (мөлшері енді `client_points_per_referral`
--     арқылы модератор баптайды, әдепкі 1).
-- `redeem_referral_code` ЕНДІ ТЕК referred_by байланысын жасайды —
-- ешбір сыйақы бермейді. Нақты сыйақы `order_advance`-тегі жаңа
-- `award_referral_rewards_if_due` шақыруынан келеді.
--
-- ЕСКЕРТУ: идемпотентті, 0060/0061 қолданылған/қолданылмаған екі жағдайда
-- да қауіпсіз. SQL Editor-да 0060 → 0061 → 0062 РЕТІМЕН қолдану керек.
-- ============================================================

update public.app_settings
   set value = value || jsonb_build_object(
     'client_points_per_referral',
     coalesce((value->>'client_points_per_referral')::int, 1)
   )
 where key = 'referral';

insert into public.app_settings (key, value)
values ('referral', jsonb_build_object(
  'enabled', false, 'executor_bonus_amount', 200, 'client_points_per_referral', 1
))
on conflict (key) do nothing;

alter table public.executor_profiles
  add column if not exists referral_bonus_paid boolean not null default false;

alter table public.profiles
  add column if not exists referral_points_paid boolean not null default false;

-- ============================================================
-- redeem_referral_code — ЕНДІ ТЕК БАЙЛАНЫС жасайды, сыйақы БЕРМЕЙДІ.
-- ============================================================
create or replace function public.redeem_referral_code(p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_referrer uuid;
  v_enabled boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select coalesce((value->>'enabled')::boolean, false) into v_enabled
    from public.app_settings where key = 'referral';
  if not coalesce(v_enabled, false) then raise exception 'DISABLED'; end if;

  if v_code = '' then raise exception 'BAD_CODE'; end if;

  if exists (
    select 1 from public.profiles where id = v_uid and referred_by is not null
  ) then
    raise exception 'ALREADY_REFERRED';
  end if;

  select id into v_referrer from public.profiles where referral_code = v_code;
  if v_referrer is null then raise exception 'BAD_CODE'; end if;
  if v_referrer = v_uid then raise exception 'SELF_REFERRAL'; end if;

  -- ТЕК байланыс. Санақ/бонус — шақырылған адам БІРІНШІ заказын
  -- аяқтағанда ғана (award_referral_rewards_if_due, order_advance ішінде).
  update public.profiles set referred_by = v_referrer where id = v_uid;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.redeem_referral_code(text) to authenticated;

-- ============================================================
-- award_referral_rewards_if_due — заказ аяқталғанда шақыруды тексереді.
-- ============================================================
create or replace function public.award_referral_rewards_if_due(
  p_client_id uuid, p_executor_id uuid
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean;
  v_exec_amount bigint;
  v_client_points int;
  v_ref uuid;
  v_paid boolean;
  v_done int;
begin
  select coalesce((value->>'enabled')::boolean, false),
         coalesce((value->>'executor_bonus_amount')::bigint, 200),
         coalesce((value->>'client_points_per_referral')::int, 1)
    into v_enabled, v_exec_amount, v_client_points
    from public.app_settings where key = 'referral';
  if not coalesce(v_enabled, false) then return; end if;

  -- ---- КЛИЕНТ жағы: 1-ші аяқталған заказда шақырушының санағы өседі ----
  if p_client_id is not null then
    select referred_by, referral_points_paid into v_ref, v_paid
      from public.profiles where id = p_client_id;
    if v_ref is not null and not coalesce(v_paid, false) then
      select count(*) into v_done from public.orders
       where client_id = p_client_id and status = 'completed';
      if v_done = 1 then
        update public.profiles set referral_points_paid = true where id = p_client_id;
        update public.profiles set referral_count = referral_count + greatest(v_client_points, 0)
         where id = v_ref;
      end if;
    end if;
  end if;

  -- ---- ОРЫНДАУШЫ жағы: 1-ші аяқталған заказда шақырушының балансына бонус ----
  if p_executor_id is not null then
    select p.referred_by, ep.referral_bonus_paid into v_ref, v_paid
      from public.profiles p
      join public.executor_profiles ep on ep.user_id = p.id
     where p.id = p_executor_id;
    if v_ref is not null and not coalesce(v_paid, false) then
      select count(*) into v_done from public.orders
       where executor_id = p_executor_id and status = 'completed';
      if v_done = 1 then
        update public.executor_profiles set referral_bonus_paid = true
         where user_id = p_executor_id;

        if v_exec_amount > 0 then
          update public.executor_profiles set balance = balance + v_exec_amount
           where user_id = v_ref;

          insert into public.balance_txns (executor_id, amount, type, note)
          values (v_ref, v_exec_amount, 'adjustment',
                  'Жаттыққа шақыру бонусы (дос 1-ші заказды аяқтады)');

          perform public.send_push(
            'Шақыру бонусы! 🎁',
            'Шақырған досыңыз алғашқы заказын аяқтады. Балансыңызға ' ||
              v_exec_amount || ' ₸ қосылды.',
            jsonb_build_object('type', 'bonus'),
            array[v_ref],
            'Бонус за приглашение! 🎁',
            'Приглашённый вами друг завершил первый заказ. На баланс ' ||
              'добавлено ' || v_exec_amount || ' ₸.'
          );
        end if;
      end if;
    end if;
  end if;
end;
$$;

-- ============================================================
-- order_advance — 0059 денесі + award_referral_rewards_if_due шақыруы.
-- ============================================================
create or replace function public.order_advance(p_order uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_next public.order_status;
  v_expected public.order_status;
  v_is_client boolean;
  v_is_executor boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_next := p_status::public.order_status;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  v_is_client := (o.client_id = v_uid);
  v_is_executor := (o.executor_id is not null and o.executor_id = v_uid);
  if not v_is_client and not v_is_executor then raise exception 'FORBIDDEN'; end if;

  v_expected := case o.status
    when 'accepted'   then 'arrived'::public.order_status
    when 'arrived'    then 'loading'::public.order_status
    when 'loading'    then 'in_transit'::public.order_status
    when 'in_transit' then 'completed'::public.order_status
    else null
  end;
  if v_expected is null or v_next <> v_expected then raise exception 'BAD_TRANSITION'; end if;

  -- Рөлдік тексеру: тиеу растауы — клиенттікі, қалғаны — орындаушыныкі.
  if v_next = 'loading' then
    if not v_is_client then raise exception 'CLIENT_ONLY'; end if;
  else
    if not v_is_executor then raise exception 'EXECUTOR_ONLY'; end if;
  end if;

  if v_next = 'completed' then
    update public.orders set status = 'completed', completed_at = now() where id = p_order;
    insert into public.earnings (executor_id, order_id, amount)
    values (o.executor_id, p_order, coalesce(o.final_price, 0))
    on conflict (order_id) do nothing;
    update public.executor_profiles
       set total_earned = total_earned + coalesce(o.final_price, 0),
           busy_order_id = null
     where user_id = o.executor_id;
    -- поездка санағышы (екі жаққа)
    update public.profiles set trips = trips + 1
     where id in (o.client_id, o.executor_id);
    -- бонус бағдарламасы (0059) — лимитке жетсе балансқа сома қосылады
    perform public.award_bonus_if_due(o.executor_id);
    -- жаттыққа шақыру сыйақысы (0062) — тек 1-ші аяқталған заказда
    perform public.award_referral_rewards_if_due(o.client_id, o.executor_id);
  else
    update public.orders set status = v_next where id = p_order;
  end if;
end;
$$;

grant execute on function public.order_advance(uuid,text) to authenticated;

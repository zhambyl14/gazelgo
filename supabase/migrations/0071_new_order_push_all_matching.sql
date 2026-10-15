-- Tasu · 0071_new_order_push_all_matching.sql
-- «Жаңа заказ» push-ы орындаушыларға МҮЛДЕМ жетпейтін.
--
-- Себебі: `notify_executors_new_order` алушыларды `exec_can_take` арқылы
-- іріктейтін, ал ол `exec_has_capacity`-ді талап етеді — яғни тек СОЛ
-- СӘТТЕ ақылы тарифі (смена) белсенді орындаушы ғана push алатын. Жоба
-- уақытша тоқтап тұрғанда ешкімнің тарифі белсенді емес → бірде-бір
-- орындаушыға хабар кетпейді, ал тарифті сатып алуға себеп те болмайды
-- (заказ бар екенін білмейді). Лента 0041/0063-тен бері бәріне көрінеді,
-- push та соған сай болуы керек.
--
-- Шешім: заказ КӨРІНЕТІН (`exec_can_see`: көлік түрі мен қаласы сай)
-- барлық РАСТАЛҒАН орындаушыға хабарлаймыз:
--   * тарифі белсенді, заказды қазір ала алатындарға — бұрынғы мәтін;
--   * тарифі жоқтарға — «алу үшін линияға шығыңыз» деген мәтін.
-- Заказ иесі (клиент) бұрынғыдай ешқашан алмайды.

create or replace function public.notify_executors_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ready uuid[];
  v_idle  uuid[];
begin
  if new.status <> 'searching' then return new; end if;

  select
    array_agg(ep.user_id) filter (where public.exec_can_take(ep.user_id, new.id)),
    array_agg(ep.user_id) filter (where not public.exec_can_take(ep.user_id, new.id))
  into v_ready, v_idle
  from public.executor_profiles ep
  where ep.status = 'approved'
    and ep.order_push_enabled = true
    and ep.user_id <> new.client_id
    and public.exec_can_see(ep.user_id, new.id);

  if coalesce(array_length(v_ready, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты — тезірек қараңыз.',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_ready,
      'Новый заказ',
      'Появился подходящий заказ — посмотрите скорее.'
    );
  end if;

  if coalesce(array_length(v_idle, 1), 0) > 0 then
    perform public.send_push(
      'Жаңа заказ',
      'Сізге сай жаңа заказ шықты. Алу үшін линияға шығыңыз (тариф).',
      jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
      v_idle,
      'Новый заказ',
      'Появился подходящий заказ. Чтобы взять его, выйдите на линию (тариф).'
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

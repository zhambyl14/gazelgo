-- ============================================================
-- Tasu · 0049_topup_notifications.sql
-- ============================================================
-- БАГ: орындаушы баланс толтыру өтінімін (request_topup RPC, 0003) жіберсе,
-- модераторға ЕШБІР push/уведомление келмейтін. Модератор өзгеріс болғанын
-- тек overview экранындағы «topups_pending» санағышты қолмен ашқанда ғана
-- көретін — жаңа өтінім (мыс. «жаңа өтінім» executor_profiles инсертінде)
-- бар болатын notify_moderators_new_application (0019/0025/0045) тәрізді
-- триггер topup_requests кестесінде мүлдем жоқ болатын.
--
-- Бұл миграция сол триггерді дәл сол үлгі бойынша қосады: жаңа
-- topup_requests жазбасы түскенде барлық модераторға (send_push
-- target_user_ids=null → барлық moderator) push жіберіледі.
--
-- ЕСКЕРТУ: 0045-тен КЕЙІН орындаңыз (send_push екі тілді нұсқасы керек).
-- Идемпотентті.
-- ============================================================

create or replace function public.notify_moderators_new_topup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  select full_name into v_name from public.profiles where id = new.executor_id;

  perform public.send_push(
    'Жаңа баланс толтыру өтінімі',
    case when coalesce(v_name, '') <> ''
         then v_name || ' балансын толтыруды сұрады: ' || new.amount::text || ' ₸.'
         else 'Жаңа баланс толтыру өтінімі келді: ' || new.amount::text || ' ₸.' end,
    jsonb_build_object('type', 'new_topup', 'topup_id', new.id::text),
    null,
    'Новая заявка на пополнение баланса',
    case when coalesce(v_name, '') <> ''
         then v_name || ' запросил пополнение баланса: ' || new.amount::text || ' ₸.'
         else 'Поступила новая заявка на пополнение баланса: ' || new.amount::text || ' ₸.' end
  );
  return new;
exception when others then
  -- push сәтсіз болса да негізгі INSERT үзілмеуі керек
  return new;
end;
$$;

drop trigger if exists trg_notify_new_topup on public.topup_requests;
create trigger trg_notify_new_topup
  after insert on public.topup_requests
  for each row execute function public.notify_moderators_new_topup();

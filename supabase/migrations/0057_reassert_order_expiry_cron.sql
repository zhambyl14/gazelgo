-- ============================================================
-- Tasu · 0057_reassert_order_expiry_cron.sql
-- ============================================================
-- Диагностика: ешкім қабылдамаған заказдар лентада КҮНДЕП тұрып қалуы
-- мүмкін екені хабарланды. Код деңгейінде логика ДҰРЫС:
--   · expire_stale_orders() (0039) заказды 6 сағаттан соң 'expired'
--     етеді (15 мин, 45 мин, содан кейін сағат сайын еске салу push
--     жібере отырып);
--   · executor_feed() (0041) тек status='searching' заказды көрсетеді —
--     'expired' болған соң лентадан бірден жоғалады;
--   · cron `gazelgo-expire-orders` (0004) осы функцияны әр 5 минут сайын
--     шақыруы керек.
--
-- НАҚТЫ ТАБЫЛҒАН СЕБЕП: серверде 0039-дың «alter table ... add column
-- reminder_count» бөлігі қолданылмай қалған екен (баған жоқ), сол
-- себепті `reminder_count`-ты пайдаланатын функция денесі ҚАТЕМЕН
-- сынып тұрған — cron әр 5 минут сайын үнсіз сәтсіз аяқталады да,
-- ЕШБІР заказ ешқашан expire болмайды. Бұл миграция бағанды да,
-- функцияны да, cron-ды да ҚАЙТА (идемпотентті) бекітеді.
-- ============================================================

-- 1) Жетпей тұрған баған (0039-дың бөлігі — қауіпсіз, бар болса тимейді).
alter table public.orders
  add column if not exists reminder_count integer not null default 0;

-- 2) Функцияны ТАҒЫ ДА анықтаймыз — сервердегі нақты дене қандай
--    күйде тұрғанына қарамай, дәл осы (0039-ға сай) нұсқа қолданыста
--    болатынына кепілдік үшін.
create or replace function public.expire_stale_orders()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
begin
  -- ---------- кестесі жеткен, әлі осы реттегі еске салу жіберілмеген заказдар ----------
  for o in
    select id, client_id, reminder_count from public.orders
     where type = 'bidding' and status = 'searching'
       and created_at < now() - (
         case
           when reminder_count = 0 then interval '15 minutes'
           when reminder_count = 1 then interval '45 minutes'
           else interval '45 minutes' + (reminder_count - 1) * interval '1 hour'
         end
       )
  loop
    update public.orders set reminder_count = reminder_count + 1 where id = o.id;
    perform public.send_push(
      'Заказыңыз әлі қабылданбады',
      'Ешкім қабылдамай жатыр — бағаны көтеріп көріңіз.',
      jsonb_build_object('type', 'order_reminder', 'order_id', o.id::text),
      array[o.client_id]
    );
  end loop;

  -- ---------- 6+ сағат қабылданбаған заказдар — expire ----------
  for o in
    select id, client_id from public.orders
     where type = 'bidding' and status = 'searching'
       and created_at < now() - interval '6 hours'
  loop
    update public.orders set status = 'expired' where id = o.id;
    perform public.send_push(
      'Заказ табылмады',
      '6 сағат ішінде орындаушы табылмады. Бағаны көтеріп, қайта '
        'жариялап көріңіз.',
      jsonb_build_object('type', 'order_expired', 'order_id', o.id::text),
      array[o.client_id]
    );
  end loop;
end;
$$;

-- 3) Cron тапсырмасын идемпотентті қайта тіркейміз (бар болса — зиян
--    жоқ, жоқ болса — енді жұмыс істей бастайды).
do $$
begin
  perform cron.unschedule('gazelgo-expire-orders');
exception when others then null;
end $$;

select cron.schedule('gazelgo-expire-orders', '*/5 * * * *',
  $$select public.expire_stale_orders()$$);

-- 4) Қазір ілініп қалған (6+ сағат «іздеуде» тұрған) заказдарды бірден
--    тазалайды — cron келесі 5 минутты күтпей-ақ.
select public.expire_stale_orders();

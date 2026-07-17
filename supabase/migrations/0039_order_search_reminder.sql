-- Tasu · 0039_order_search_reminder.sql
-- Пайдаланушы сұрады: заказ 6 сағат (expire, 0038) күтпей-ақ, бірнеше
-- минут ешкім қабылдамаса, клиент телефонын жауып ұмытып кетуі мүмкін —
-- сол себепті ҚАЙТАЛАНАТЫН еске салу push керек («ешкім қабылдамай
-- жатыр, бағаны көтеріп көріңіз» — client_price-ты update_order_price
-- RPC-мен (0006) көтеруге болады, қосымшада бұл мүмкіндік бұрыннан бар).
--
-- Кесте: 1-еске салу 15 минутта, 2-еске салу 45 минутта (1-ден 30 мин
-- соң), содан кейінгілері әр 1 сағат сайын (105, 165, 225, ... минут) —
-- заказ 6 сағатта (0038) expire болғанша. reminder_count бағаны әр
-- жіберуден кейін +1 болады, келесі табалдырық содан есептеледі.
--
-- expire_stale_orders() cron-ы (gazelgo-expire-orders, әр 5 минут, 0004)
-- енді ЕКІ блокты да қамтиды: қайталанатын еске салу, содан кейін
-- 6 сағаттан соң expire.

alter table public.orders
  add column if not exists reminder_count integer not null default 0;

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

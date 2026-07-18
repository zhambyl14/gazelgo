-- Tasu · 0038_order_expiry_notify.sql
-- Пайдаланушы сұрады: клиенттің заказы 6 сағат ішінде ешкіммен
-- қабылданбай (bidding, status='searching') automat expire болғанда
-- (0036-дағы expire_stale_orders, cron: gazelgo-expire-orders, әр 5 мин),
-- клиентке ЕШБІР хабарлама келмейтін еді — тек қосымшаны өзі ашып
-- статусты «Мерзімі өтті» деп көргенде ғана білетін. Телефонын жауып,
-- ұмытып кетуі мүмкін. Енді әр expire болған заказға клиентке push
-- жіберіледі (notify_executors_new_order-мен бірдей send_push, 0025,
-- үлгісі бойынша).
--
-- ЕСКЕРТУ: бұл функция 0039-да ТАҒЫ ДА ауыстырылады (еске салу
-- кестесі қосылады) — осы файл тарихи қадам ретінде қалады, соңғы
-- нақты мінез-құлық 0039-да.

create or replace function public.expire_stale_orders()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
begin
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

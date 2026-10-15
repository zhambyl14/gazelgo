-- Tasu · 0073_order_wait_escalation.sql
-- Клиент орындаушыны ҰЗАҚ КҮТПЕУІ үшін «екінші толқын» push.
--
-- 0071-ден бері жаңа заказ туралы хабар заказды көре алатын (`exec_can_see`:
-- көлік түрі мен қаласы сай) барлық РАСТАЛҒАН орындаушыға кетеді — бірақ тек
-- `order_push_enabled = true` болғандарға. Ешкім уведомлениесін қоспаған
-- немесе ешкім жауап бермеген жағдайда клиент бос күтіп қалады.
--
-- Шешім: заказ 4 минут бойы БІР ДЕ белсенді ұсыныссыз тұрса — сол заказды
-- көре алатын БАРЛЫҚ расталған орындаушыға (линияда емес, уведомлениесін
-- өшіріп қойғандарға да) БІР РЕТ «клиент күтіп отыр, заказ өзекті» деген
-- хабар жіберіледі. Бұл ұсыныс бергендерге (бас тартылса да) жіберілмейді.
-- Әр заказға тек бір рет (`escalated_at`), сондықтан спам болмайды.
--
-- Алдын ала (жоспарланған) заказда күту уақыты `scheduled_at`-тан
-- есептеледі (ол кезге дейін орындаушыларға көрінбейді). 3 сағаттан ескі
-- заказдар үшін жіберілмейді (ол кезде клиентке 0039 еске салуы жүреді).

alter table public.orders
  add column if not exists escalated_at timestamptz;

create or replace function public.escalate_waiting_orders()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  o record;
  v_targets uuid[];
begin
  for o in
    select ord.id, ord.client_id
      from public.orders ord
     where ord.type = 'bidding'
       and ord.status = 'searching'
       and ord.escalated_at is null
       and greatest(ord.created_at, coalesce(ord.scheduled_at, ord.created_at))
           < now() - interval '4 minutes'
       and greatest(ord.created_at, coalesce(ord.scheduled_at, ord.created_at))
           > now() - interval '3 hours'
       and not exists (
         select 1 from public.offers f
          where f.order_id = ord.id and f.status = 'pending'
       )
     for update of ord skip locked
  loop
    -- Әр заказ өз блогында: біреуінде қате болса, қалғандары жалғасады.
    begin
      update public.orders set escalated_at = now() where id = o.id;

      select array_agg(ep.user_id)
        into v_targets
        from public.executor_profiles ep
       where ep.status = 'approved'
         and ep.user_id <> o.client_id
         and public.exec_can_see(ep.user_id, o.id)
         and not exists (
           select 1 from public.offers f
            where f.order_id = o.id and f.executor_id = ep.user_id
         );

      if coalesce(array_length(v_targets, 1), 0) > 0 then
        perform public.send_push(
          'Клиент орындаушы күтіп отыр',
          'Сізге сай заказды әлі ешкім алмады — қарап шығыңыз, ол өзекті.',
          jsonb_build_object('type', 'new_order', 'order_id', o.id::text),
          v_targets,
          'Клиент ждёт исполнителя',
          'Подходящий заказ ещё никто не взял — посмотрите, он актуален.'
        );
      end if;
    exception when others then
      raise warning 'escalate_waiting_orders: %', sqlerrm;
    end;
  end loop;
end;
$$;

revoke execute on function public.escalate_waiting_orders()
  from public, anon, authenticated;

-- Әр минут сайын (күту табалдырығы 4 минут — кешігу ≤ 1 мин).
do $$ begin perform cron.unschedule('tasu-escalate-waiting-orders');
exception when others then null; end $$;
select cron.schedule(
  'tasu-escalate-waiting-orders',
  '* * * * *',
  'select public.escalate_waiting_orders()'
);

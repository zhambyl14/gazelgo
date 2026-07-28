-- Tasu · 0045_push_i18n_and_order_events.sql
-- Хабарландырулардағы төрт нақты ақаудың сервер жағындағы түзетуі:
--
-- 1) ЕКІ ТІЛДЕ ЕКІ РЕТ келетін push. Себебі: сервер қазақша push жіберетін,
--    ал қосымша сол оқиға туралы ЕКІНШІ рет локал уведомление көрсететін
--    (аударылған). Шешім: тіл енді СЕРВЕРДЕ сақталады (`profiles.lang`) әрі
--    `send_push` екі тілдегі мәтінді де жібереді — edge function әр
--    пайдаланушыға ӨЗ ТІЛІНДЕ БІР РЕТ жібереді. Қосымша жағында қосарланған
--    локал уведомление өшірілді.
--
-- 2) Клиентке ҰСЫНЫС туралы push мүлдем келмейтін (тек қосымша ашық тұрғанда
--    экранда көрінетін) — жаңа `notify_client_new_offer` триггері.
--
-- 3) «Орындаушы келді», «Заказ аяқталды» т.б. тек қосымша АШЫҚ тұрғанда
--    келетін (client_shell.dart ішіндегі локал уведомление) — енді
--    `notify_order_status_change` триггері нағыз push жібереді, қосымша
--    толық жабық болса да жетеді.
--
-- 4) Орындаушыға өз ұсынысының нәтижесі (қабылданды/қабылданбады) туралы
--    push жоқ еді — `notify_executor_offer_result` қосылды.
--
-- Сонымен қатар: «жаңа заказ» push-ы енді заказ ИЕСІНЕ (клиентке) ешқашан
-- жіберілмейді — қорғаныс шарты (бір адам әрі клиент, әрі орындаушы болып
-- тіркелген жағдайда).

-- ============ 1. Пайдаланушы тілі ============
alter table public.profiles
  add column if not exists lang text not null default 'kk';

alter table public.profiles drop constraint if exists profiles_lang_chk;
alter table public.profiles
  add constraint profiles_lang_chk check (lang in ('kk','ru'));

create or replace function public.set_my_lang(p_lang text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.profiles
     set lang = case when lower(coalesce(p_lang,'')) = 'ru' then 'ru' else 'kk' end
   where id = auth.uid();
end;
$$;
revoke all on function public.set_my_lang(text) from public, anon;
grant execute on function public.set_my_lang(text) to authenticated;

-- ============ 2. Құрылғы шыққанда токенді өшіру ============
-- Бір телефонда аккаунт ауысса, ЕСКІ иесіне арналған push жаңа иесіне
-- көрінбеуі керек (клиентке «жаңа заказ» келуінің басты себебі осы еді).
create or replace function public.delete_push_token(p_token text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  delete from public.push_tokens
   where token = trim(coalesce(p_token,'')) and user_id = auth.uid();
end;
$$;
revoke all on function public.delete_push_token(text) from public, anon;
grant execute on function public.delete_push_token(text) to authenticated;

-- ============ 3. send_push — екі тілді ============
-- Ескі 4-аргументті нұсқа жойылып, орнына тілдік нұсқасы келеді. Ескі
-- шақырулар (0038, 0039, 0025) 4 аргументпен сол күйі жұмыс істей береді —
-- ru мәтіні берілмесе, қазақшасы екі тілге де кетеді.
drop function if exists public.send_push(text, text, jsonb, uuid[]);

create or replace function public.send_push(
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_target_user_ids uuid[] default null,
  p_title_ru text default null,
  p_body_ru text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_secrets where key = 'push_trigger_secret';
  if v_secret is null or v_secret = '' then
    return;
  end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'title', p_title,
      'body', p_body,
      'title_ru', coalesce(p_title_ru, p_title),
      'body_ru', coalesce(p_body_ru, p_body),
      'data', coalesce(p_data, '{}'::jsonb),
      'target_user_ids', to_jsonb(p_target_user_ids)
    )
  );
exception when others then
  null;
end;
$$;

-- ============ 4. Жаңа заказ → сай орындаушыларға (заказ иесінен басқа) ============
create or replace function public.notify_executors_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
begin
  if new.status <> 'searching' then return new; end if;

  select array_agg(ep.user_id) into v_ids
  from public.executor_profiles ep
  where ep.status = 'approved'
    and ep.order_push_enabled = true
    -- Заказ ИЕСІ ешқашан «жаңа заказ» push алмайды: бір адам әрі клиент,
    -- әрі орындаушы болып тіркелген болса, өз заказы туралы хабарландыру
    -- келіп, шатастыратын.
    and ep.user_id <> new.client_id
    and public.exec_can_take(ep.user_id, new.id);

  if v_ids is null or array_length(v_ids, 1) = 0 then return new; end if;

  perform public.send_push(
    'Жаңа заказ',
    'Сізге сай жаңа заказ шықты — тезірек қараңыз.',
    jsonb_build_object('type', 'new_order', 'order_id', new.id::text),
    v_ids,
    'Новый заказ',
    'Появился подходящий заказ — посмотрите скорее.'
  );
  return new;
exception when others then
  return new;
end;
$$;

-- ============ 5. Жаңа ұсыныс → клиентке ============
create or replace function public.notify_client_new_offer()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client uuid;
  v_name text;
  v_price text;
begin
  if new.status <> 'pending' then return new; end if;

  select client_id into v_client from public.orders where id = new.order_id;
  if v_client is null or v_client = new.executor_id then return new; end if;

  select full_name into v_name from public.profiles where id = new.executor_id;
  -- Қосымшадағыдай мыңдық бөлгішпен: 5855 → «5 855».
  v_price := replace(to_char(new.price, 'FM999,999,999,999'), ',', ' ');

  perform public.send_push(
    'Жаңа ұсыныс: ' || v_price || ' ₸',
    case when coalesce(v_name,'') <> ''
         then v_name || ' заказыңызға ұсыныс берді — қараңыз.'
         else 'Заказыңызға жаңа ұсыныс түсті — қараңыз.' end,
    jsonb_build_object('type', 'new_offer', 'order_id', new.order_id::text),
    array[v_client],
    'Новое предложение: ' || v_price || ' ₸',
    case when coalesce(v_name,'') <> ''
         then v_name || ' предложил цену по вашему заказу — посмотрите.'
         else 'По вашему заказу поступило новое предложение — посмотрите.' end
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_client_new_offer on public.offers;
create trigger trg_notify_client_new_offer
  after insert on public.offers
  for each row execute function public.notify_client_new_offer();

-- ============ 6. Заказ статусы өзгерді → клиентке ============
-- Бұрын бұл хабарламалар тек қосымша АШЫҚ тұрғанда (client_shell.dart
-- ішіндегі локал уведомление) көрінетін — телефон құлыпты болса жоғалатын.
create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_title_kk text; v_body_kk text;
  v_title_ru text; v_body_ru text;
  v_target uuid;
begin
  if new.status = old.status then return new; end if;

  -- Әдепкі алушы — клиент. «Тиеу басталды» бұдан бөлек: оны КЛИЕНТТІҢ ӨЗІ
  -- басады, сол себепті push орындаушыға кетеді (адам өз әрекеті туралы
  -- хабарландыру алмауы керек — пайдаланушы нақты шағымданған мінез).
  v_target := new.client_id;

  case new.status
    when 'accepted' then
      v_title_kk := 'Орындаушы табылды';
      v_body_kk  := 'Орындаушы заказды қабылдап, жолға шықты.';
      v_title_ru := 'Исполнитель найден';
      v_body_ru  := 'Исполнитель принял заказ и выехал.';
    when 'arrived' then
      v_title_kk := 'Орындаушы келді';
      v_body_kk  := 'Орындаушы жеткен жері — қарсы алыңыз.';
      v_title_ru := 'Исполнитель прибыл';
      v_body_ru  := 'Исполнитель на месте — встречайте.';
    when 'loading' then
      -- Клиент растады → орындаушыға хабарлаймыз (енді «Жолға шықтық»
      -- дей алады, 0027).
      v_target   := new.executor_id;
      v_title_kk := 'Клиент тиеуді растады';
      v_body_kk  := 'Енді «Жолға шықтық» деп белгілей аласыз.';
      v_title_ru := 'Клиент подтвердил погрузку';
      v_body_ru  := 'Теперь можно отметить «В пути».';
    when 'in_transit' then
      v_title_kk := 'Жүгіңіз жолда';
      v_body_kk  := 'Орындаушы жүкті жеткізуге шықты.';
      v_title_ru := 'Груз в пути';
      v_body_ru  := 'Исполнитель везёт груз к месту доставки.';
    when 'completed' then
      v_title_kk := 'Заказ аяқталды';
      v_body_kk  := 'Орындаушыны бағалауды ұмытпаңыз ⭐';
      v_title_ru := 'Заказ завершён';
      v_body_ru  := 'Не забудьте оценить исполнителя ⭐';
    when 'cancelled' then
      -- Тоқтатқан адамның ӨЗІНЕ хабарландыру келмейді — екінші жаққа ғана.
      if new.cancelled_by is not null and new.cancelled_by = new.client_id then
        v_target := new.executor_id;
      else
        v_target := new.client_id;
      end if;
      v_title_kk := 'Заказ тоқтатылды';
      v_body_kk  := coalesce(nullif(new.cancel_reason, ''), 'Заказ тоқтатылды.');
      v_title_ru := 'Заказ отменён';
      v_body_ru  := coalesce(nullif(new.cancel_reason, ''), 'Заказ отменён.');
    when 'searching' then
      -- accepted → searching: орындаушы бас тартты, заказ қайта іздеуде
      v_title_kk := 'Заказ қайта іздеуде';
      v_body_kk  := 'Орындаушы бас тартты — жаңа орындаушы ізделуде 🔄';
      v_title_ru := 'Заказ снова в поиске';
      v_body_ru  := 'Исполнитель отказался — ищем нового 🔄';
    else
      -- expired: жеке push-ы expire_stale_orders ішінде жіберіледі.
      return new;
  end case;

  if v_target is null then return new; end if;

  perform public.send_push(
    v_title_kk, v_body_kk,
    -- `audience` — хабарламаны басқанда ҚАЙ экранды ашуды білдіреді
    -- (клиенттің заказ беті ме, әлде орындаушының белсенді заказы ма).
    jsonb_build_object('type', 'order_status', 'order_id', new.id::text,
                       'status', new.status::text,
                       'audience', case when v_target = new.client_id
                                        then 'client' else 'executor' end),
    array[v_target],
    v_title_ru, v_body_ru
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_order_status_change on public.orders;
create trigger trg_notify_order_status_change
  after update of status on public.orders
  for each row execute function public.notify_order_status_change();

-- ============ 7. Ұсыныс нәтижесі → орындаушыға ============
create or replace function public.notify_executor_offer_result()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = old.status then return new; end if;

  if new.status = 'accepted' then
    perform public.send_push(
      'Ұсынысыңыз қабылданды 🎉',
      'Клиент сіздің бағаңызды таңдады — жолға шығыңыз.',
      jsonb_build_object('type', 'offer_accepted', 'order_id', new.order_id::text),
      array[new.executor_id],
      'Ваше предложение принято 🎉',
      'Клиент выбрал вашу цену — выезжайте.'
    );
  elsif new.status = 'rejected' then
    perform public.send_push(
      'Ұсынысыңыз қабылданбады',
      'Клиент басқа орындаушыны таңдады. Лентадан жаңа заказ қараңыз.',
      jsonb_build_object('type', 'offer_rejected', 'order_id', new.order_id::text),
      array[new.executor_id],
      'Предложение отклонено',
      'Клиент выбрал другого исполнителя. Посмотрите новые заказы в ленте.'
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_executor_offer_result on public.offers;
create trigger trg_notify_executor_offer_result
  after update of status on public.offers
  for each row execute function public.notify_executor_offer_result();

-- ============ 8. Бұрыннан бар push-тарды да екі тілге көшіру ============
-- Орыс тіліндегі пайдаланушыға қазақша push келетін (қосымша интерфейсі
-- орысша тұрса да) — сол сәйкессіздік те түзетілді.

-- 8.1 қолдау чаты (0035 нұсқасының үстіне)
create or replace function public.notify_support_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  th record;
  v_snippet text;
begin
  select * into th from public.support_threads where id = new.thread_id;
  if not found then return new; end if;

  v_snippet := left(coalesce(new.body, ''), 120);
  if v_snippet = '' and new.image_path is not null then
    v_snippet := '📷 Сурет жіберілді';
  end if;
  if v_snippet = '' then v_snippet := 'Жаңа хабарлама'; end if;

  if new.sender_role = 'moderator' then
    perform public.send_push(
      'Tasu қолдау қызметі', v_snippet,
      jsonb_build_object('type', 'support_reply', 'thread_id', th.id::text),
      array[th.user_id],
      'Служба поддержки Tasu', v_snippet
    );
  else
    perform public.send_push(
      'Жаңа хабарлама — қолдау чаты', v_snippet,
      jsonb_build_object('type', 'support_message', 'thread_id', th.id::text),
      null,
      'Новое сообщение — чат поддержки', v_snippet
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

-- 8.2 модераторға жаңа/қайта өтінім (0025 нұсқасының үстіне)
create or replace function public.notify_moderators_new_application()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  select full_name into v_name from public.profiles where id = new.user_id;
  perform public.send_push(
    case when tg_op = 'UPDATE' then 'Қайта жіберілген өтінім'
         else 'Жаңа газелист өтінімі' end,
    case when coalesce(v_name, '') <> ''
         then v_name || ' тіркелу өтінімін жіберді — модерация күтуде.'
         else 'Жаңа өтінім модерация күтуде.' end,
    jsonb_build_object('type', 'new_application'),
    null,
    case when tg_op = 'UPDATE' then 'Повторная заявка'
         else 'Новая заявка исполнителя' end,
    case when coalesce(v_name, '') <> ''
         then v_name || ' отправил заявку на регистрацию — ожидает модерации.'
         else 'Новая заявка ожидает модерации.' end
  );
  return new;
exception when others then
  return new;
end;
$$;

-- 8.3 еске салу / мерзімі өту (0039 нұсқасының үстіне — логикасы сол күйі)
create or replace function public.expire_stale_orders()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
begin
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
      array[o.client_id],
      'Ваш заказ ещё не принят',
      'Пока никто не откликнулся — попробуйте поднять цену.'
    );
  end loop;

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
      array[o.client_id],
      'Исполнитель не найден',
      'За 6 часов исполнитель не нашёлся. Поднимите цену и опубликуйте '
        'заказ заново.'
    );
  end loop;
end;
$$;

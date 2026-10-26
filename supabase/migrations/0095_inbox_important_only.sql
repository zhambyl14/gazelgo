-- ============================================================
-- Tasu · 0095_inbox_important_only.sql
-- ============================================================
-- «ХАБАРЛАМАЛАР» ОРТАЛЫҒЫ тек МАҢЫЗДЫ хабарларды сақтасын.
--
-- Бұрын онда заказдың әр қадамы жиналып кететін («жаңа заказ», «ұсыныс
-- келді», «заказ қабылданды», «жүргізуші табылмады»…) — маңыздысы
-- көміліп қалатын. Енді ол заказ ағынының хабарлары орталыққа ЖАЗЫЛМАЙДЫ
-- (push бұрынғыдай жіберіледі, заказ экранының өзінде де көрінеді):
--   new_order, new_offer, offer_accepted, offer_rejected, order_status,
--   order_expired, order_reminder.
-- Орталықта қалатындар: модератор хабарламасы (broadcast), қолдау жауабы,
-- бонус, баланс (толтыру), жаңа БАҒА (review_received), жаңалықтар мен
-- жаңарту хабарлары (жаңа тип қосылса — әдепкіде көрінеді), модератордың
-- жұмыс хабарлары (жаңа өтінім, толтыру, қолдау).
--
--   * send_push v3 — 0080 нұсқасы + жоғарыдағы тізімді орталыққа жазбау.
--   * Ескі «заказ ағыны» жазбалары өшіріледі.
--   * notification_mark_read(id) — бір хабарламаны оқылды деп белгілеу
--     (хабарламаны ашқанда оның қызыл белгісі кетеді).
--   * Клиент пен орындаушыға жаңа баға келгенде хабарлама (review_received).
--
-- Идемпотентті. Қосымша жаңа нұсқасы шықпай тұрып қолданыңыз.
-- ============================================================

-- ------------------------------------------------------------
-- 1) send_push v3
-- ------------------------------------------------------------
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
  -- 1) Хабарламалар орталығы: тек маңызды түрлер.
  if p_target_user_ids is not null
     and coalesce(p_data->>'type', '') not in (
       'order_chat',
       'new_order', 'new_offer', 'offer_accepted', 'offer_rejected',
       'order_status', 'order_expired', 'order_reminder'
     ) then
    begin
      insert into public.notifications (user_id, title, body, title_ru, body_ru, data)
      select distinct u, p_title, coalesce(p_body, ''), p_title_ru, p_body_ru,
             coalesce(p_data, '{}'::jsonb)
        from unnest(p_target_user_ids) as u
       where u is not null
         and exists (select 1 from public.profiles p where p.id = u);
    exception when others then
      null;
    end;
  end if;

  -- 2) Push (0045-тегідей).
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

-- ------------------------------------------------------------
-- 2) Ескі заказ ағыны жазбаларын тазалау
-- ------------------------------------------------------------
delete from public.notifications
 where coalesce(data->>'type', '') in (
   'new_order', 'new_offer', 'offer_accepted', 'offer_rejected',
   'order_status', 'order_expired', 'order_reminder'
 );

-- ------------------------------------------------------------
-- 3) Бір хабарламаны оқылды деп белгілеу
-- ------------------------------------------------------------
create or replace function public.notification_mark_read(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.notifications
     set read_at = now()
   where id = p_id and user_id = auth.uid() and read_at is null;
end;
$$;

grant execute on function public.notification_mark_read(uuid) to authenticated;

-- ------------------------------------------------------------
-- 4) Жаңа баға келгенде хабарлама
-- ------------------------------------------------------------
create or replace function public.notify_review_received()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.target_id is null then return new; end if;
  perform public.send_push(
    'Сізге жаңа баға қойылды: ' || new.rating || '/5 ⭐',
    coalesce(nullif(trim(new.comment), ''), 'Пікір қалдырылмады'),
    jsonb_build_object('type', 'review_received', 'rating', new.rating),
    array[new.target_id],
    'Вам поставили новую оценку: ' || new.rating || '/5 ⭐',
    coalesce(nullif(trim(new.comment), ''), 'Без комментария')
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_review_received on public.reviews;
create trigger trg_notify_review_received
  after insert on public.reviews
  for each row execute function public.notify_review_received();

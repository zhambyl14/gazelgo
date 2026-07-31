-- ============================================================
-- Tasu · 0052_topup_bot_i18n_and_manual_audit.sql
-- ============================================================
-- ЕКІ ТҮЗЕТУ:
--
-- 1) БОТТЫҢ СЕБЕБІ ЕНДІ ЕКІ ТІЛДЕ ЖАЗЫЛАДЫ. Бұған дейін бот қабылдамаған
--    кезде орындаушыға жіберілетін себеп мәтіні ӘРҚАШАН қазақша болатын —
--    орысша тіл таңдаған орындаушы да сол қазақша мәтінді көретін
--    (`send_push`-тың `body_ru` параметрі `body`-мен бірдей мәнмен
--    толтырылатын). Енді `topup_requests.note_ru` бағаны қосылды,
--    edge функция (`topup-verify`) екі тілдегі мәтінді де есептеп жібереді.
--
-- 2) МОДЕРАТОР ҚОСЫМШАДАН ҚОЛМЕН ҚАБЫЛДАМАСА — TELEGRAM-ГЕ ДЕ ЖАЗЫЛАДЫ.
--    Бұған дейін тек боттың өз шешімі және Telegram түймесінен келген
--    шешім Telegram-ге хабарланатын; модератор Tasu·Модератор
--    қосымшасынан («Толтырулар» бетінен) қолмен қабылдамаса, бұл ЕШҚАНДАЙ
--    із қалдырмайтын. Енді жаңа триггер осындай жағдайда `topup-bot`
--    функциясына хабар жіберіп, Telegram чатына аудит жазбасын салады.
--
-- ЕСКЕРТУ: 0051-ден КЕЙІН орындаңыз. Идемпотентті.
-- ============================================================


-- ============================================================
-- 1) note_ru бағаны
-- ============================================================
alter table public.topup_requests
  add column if not exists note_ru text;


-- ============================================================
-- 2) apply_topup_review — орысша нұсқасын да қабылдайды
-- ============================================================
create or replace function public.apply_topup_review(
  p_topup    uuid,
  p_approve  boolean,
  p_note     text default '',
  p_reviewer uuid default null,
  p_note_ru  text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  t       record;
  v_bal   bigint;
begin
  select * into t from public.topup_requests where id = p_topup for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if t.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_approve then
    update public.topup_requests
       set status = 'approved',
           note = nullif(trim(coalesce(p_note,'')),''),
           note_ru = nullif(trim(coalesce(p_note_ru,'')),''),
           reviewed_by = p_reviewer, reviewed_at = now()
     where id = p_topup;

    update public.executor_profiles set balance = balance + t.amount
     where user_id = t.executor_id
    returning balance into v_bal;

    insert into public.balance_txns (executor_id, amount, type, note, ref_id)
    values (t.executor_id, t.amount, 'topup', 'Kaspi толтыру', p_topup);
  else
    update public.topup_requests
       set status = 'rejected',
           note = nullif(trim(coalesce(p_note,'')),''),
           note_ru = nullif(trim(coalesce(p_note_ru,'')),''),
           reviewed_by = p_reviewer, reviewed_at = now()
     where id = p_topup;
  end if;

  return jsonb_build_object(
    'ok', true,
    'amount', t.amount,
    'executor_id', t.executor_id,
    'balance', v_bal
  );
end;
$$;

revoke all on function public.apply_topup_review(uuid, boolean, text, uuid, text)
  from public, anon, authenticated;

-- Ескі 4-параметрлі қолтаңба (0051) ендігі уақытта пайдаланылмайды —
-- Postgres функцияны РЕТ (параметр саны) бойынша ажыратады, сондықтан
-- ескісі де қалады, бірақ ешкім оны шақырмайды. Тазалық үшін жоямыз.
drop function if exists public.apply_topup_review(uuid, boolean, text, uuid);


-- ============================================================
-- 3) mod_review_topup — қолтаңбасы ӨЗГЕРМЕЙДІ (модератор бір тілде жазады)
-- ============================================================
create or replace function public.mod_review_topup(p_topup uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  perform public.apply_topup_review(p_topup, p_approve, p_note, auth.uid());
end;
$$;

grant execute on function public.mod_review_topup(uuid, boolean, text) to authenticated;


-- ============================================================
-- 4) bot_submit_topup_check — payload-тан note_ru да алады
-- ============================================================
create or replace function public.bot_submit_topup_check(
  p_secret  text,
  p_topup   uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  t          record;
  v_cfg      jsonb;
  v_verdict  text;
  v_codes    text[];
  v_claims   text[];
  v_max      bigint;
  v_key      text;
  v_res      jsonb := null;
  v_dupe     boolean := false;
begin
  if not public.bot_secret_ok(p_secret) then raise exception 'FORBIDDEN'; end if;

  select * into t from public.topup_requests where id = p_topup for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  select value into v_cfg from public.app_settings where key = 'topup_bot';
  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  v_max := coalesce((v_cfg->>'auto_approve_max')::bigint, 0);

  v_verdict := coalesce(p_payload->>'verdict', 'error');

  v_codes := case when jsonb_typeof(p_payload->'reason_codes') = 'array'
    then coalesce(array(select jsonb_array_elements_text(p_payload->'reason_codes')), '{}')
    else '{}'::text[] end;
  v_claims := case when jsonb_typeof(p_payload->'claim_keys') = 'array'
    then coalesce(array(select jsonb_array_elements_text(p_payload->'claim_keys')), '{}')
    else '{}'::text[] end;

  if v_verdict = 'approved' then
    if t.status <> 'pending' then
      v_verdict := 'flagged'; v_codes := array_append(v_codes, 'ALREADY_REVIEWED');
    elsif coalesce((v_cfg->>'enabled')::boolean, false) is not true then
      v_verdict := 'flagged'; v_codes := array_append(v_codes, 'BOT_DISABLED');
    elsif v_max <= 0 or t.amount > v_max then
      v_verdict := 'flagged'; v_codes := array_append(v_codes, 'ABOVE_CEILING');
    elsif array_length(v_claims, 1) is null then
      v_verdict := 'flagged'; v_codes := array_append(v_codes, 'DUP_DETECTION_UNAVAILABLE');
    end if;
  end if;

  if v_verdict = 'approved' then
    foreach v_key in array v_claims loop
      begin
        insert into public.topup_receipt_claims (claim_key, topup_id, executor_id)
        values (v_key, p_topup, t.executor_id);
      exception when unique_violation then
        v_dupe := true;
      end;
    end loop;

    if v_dupe then
      if coalesce((v_cfg->>'auto_reject_duplicates')::boolean, false) then
        v_verdict := 'rejected';
      else
        v_verdict := 'flagged';
      end if;
      v_codes := array_append(v_codes, 'DUPLICATE_RECEIPT');
      delete from public.topup_receipt_claims where topup_id = p_topup;
    end if;
  end if;

  if v_verdict = 'approved' then
    v_res := public.apply_topup_review(
      p_topup, true,
      coalesce(nullif(p_payload->>'note', ''), 'Бот автоматты растады'),
      null,
      coalesce(nullif(p_payload->>'note_ru', ''), 'Бот автоматически подтвердил'));
  elsif v_verdict = 'rejected' then
    v_res := public.apply_topup_review(
      p_topup, false,
      case when 'DUPLICATE_RECEIPT' = any(v_codes)
           then 'Бұл чек бұрын пайдаланылған'
           else coalesce(nullif(p_payload->>'note', ''), 'Чек тексеруден өтпеді') end,
      null,
      case when 'DUPLICATE_RECEIPT' = any(v_codes)
           then 'Этот чек уже был использован ранее'
           else coalesce(nullif(p_payload->>'note_ru', ''), 'Чек не прошёл проверку') end);
  end if;

  insert into public.topup_receipt_checks (
    topup_id, executor_id, image_sha256, image_bytes, image_mime,
    ocr_raw, ocr_fields, llm_fields, engines_agreed, extracted,
    verdict, reason_codes, summary_kk, duration_ms, engine_versions)
  values (
    p_topup, t.executor_id,
    p_payload->>'image_sha256',
    (p_payload->>'image_bytes')::int,
    p_payload->>'image_mime',
    left(coalesce(p_payload->>'ocr_raw', ''), 8000),
    p_payload->'ocr_fields',
    p_payload->'llm_fields',
    (p_payload->>'engines_agreed')::boolean,
    p_payload->'extracted',
    v_verdict, v_codes,
    p_payload->>'summary_kk',
    (p_payload->>'duration_ms')::int,
    p_payload->'engine_versions');

  update public.topup_requests
     set bot_verdict = v_verdict,
         bot_summary = p_payload->>'summary_kk',
         bot_checked_at = now()
   where id = p_topup;

  return jsonb_build_object(
    'ok', true,
    'verdict', v_verdict,
    'reason_codes', to_jsonb(v_codes),
    'review', v_res
  );
end;
$$;

revoke all on function public.bot_submit_topup_check(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.bot_submit_topup_check(text, uuid, jsonb) to service_role;


-- ============================================================
-- 5) bot_review_topup — Telegram түймесінен де note_ru жіберуге мүмкіндік
-- ============================================================
create or replace function public.bot_review_topup(
  p_secret  text,
  p_topup   uuid,
  p_approve boolean,
  p_note    text default '',
  p_actor   text default 'telegram',
  p_note_ru text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_res jsonb;
begin
  if not public.bot_secret_ok(p_secret) then raise exception 'FORBIDDEN'; end if;

  v_res := public.apply_topup_review(p_topup, p_approve, p_note, null, p_note_ru);

  if p_approve then
    insert into public.topup_receipt_claims (claim_key, topup_id, executor_id)
    select 'sha:' || c.image_sha256, p_topup, c.executor_id
      from public.topup_receipt_checks c
     where c.topup_id = p_topup and c.image_sha256 is not null
     order by c.created_at desc limit 1
    on conflict (claim_key) do nothing;
  end if;

  update public.topup_requests
     set bot_verdict = case when p_approve then 'manual_approved' else 'manual_rejected' end,
         bot_summary = nullif(trim(coalesce(p_note, '')), '')
   where id = p_topup;

  return jsonb_build_object('ok', true, 'actor', p_actor, 'review', v_res);
end;
$$;

revoke all on function public.bot_review_topup(text, uuid, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.bot_review_topup(text, uuid, boolean, text, text, text) to service_role;

drop function if exists public.bot_review_topup(text, uuid, boolean, text, text);


-- ============================================================
-- 6) Орындаушыға push — тіліне қарай дұрыс мәтін таңдайды
-- ============================================================
create or replace function public.notify_executor_topup_reviewed()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = old.status then return new; end if;

  if new.status = 'approved' then
    perform public.send_push(
      'Баланс толтырылды',
      'Балансыңызға ' || new.amount::text || ' ₸ қосылды.',
      jsonb_build_object('type', 'topup_approved', 'topup_id', new.id::text),
      array[new.executor_id],
      'Баланс пополнен',
      'На ваш баланс зачислено ' || new.amount::text || ' ₸.'
    );
  elsif new.status = 'rejected' then
    perform public.send_push(
      'Толтыру қабылданбады',
      coalesce(nullif(new.note, ''), 'Чек тексеруден өтпеді.'),
      jsonb_build_object('type', 'topup_rejected', 'topup_id', new.id::text),
      array[new.executor_id],
      'Пополнение отклонено',
      -- 0052: орысша нұсқасы БАР болса, соны қолданамыз — жоқ болса
      -- (мыс. модератор қосымшадан бір ғана тілде жазса) қазақшасына
      -- түседі, бұрынғыдай.
      coalesce(nullif(new.note_ru, ''), nullif(new.note, ''), 'Чек не прошёл проверку.')
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_topup_reviewed on public.topup_requests;
create trigger trg_notify_topup_reviewed
  after update of status on public.topup_requests
  for each row execute function public.notify_executor_topup_reviewed();


-- ============================================================
-- 7) Модератор ҚОСЫМШАДАН қолмен шешім қабылдаса — Telegram-ге аудит
-- ============================================================
-- Бот пен Telegram түймесі арқылы қабылданған шешімдер Telegram чатында
-- бәрібір көрінеді (олардың ІЗІ сол жерде қалады). Бірақ модератор
-- Tasu·Модератор қосымшасынан («Толтырулар» бетінен) қолмен растаса/
-- қабылдамаса, бұған дейін бұл ЕШҚАНДАЙ Telegram жазбасын қалдырмайтын.
--
-- `reviewed_by is not null` — дәл осы модератордың ӨЗ қолымен (қосымшадан)
-- шешім қабылдағанын білдіреді: бот пен Telegram түймесі әрдайым
-- `apply_topup_review`-ды `p_reviewer = null` етіп шақырады
-- (`bot_submit_topup_check`, `bot_review_topup`), тек `mod_review_topup`
-- (қосымшадағы RPC) ғана `auth.uid()` жібереді.
create or replace function public.notify_telegram_manual_review()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
begin
  if new.reviewed_by is null then return new; end if;
  if old.status <> 'pending' then return new; end if;
  if new.status not in ('approved', 'rejected') then return new; end if;

  select value into v_secret from public.app_secrets where key = 'topup_bot_secret';
  if v_secret is null or v_secret = '' then return new; end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/topup-bot',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-topup-secret', v_secret
    ),
    body := jsonb_build_object('action', 'manual_review', 'topup_id', new.id::text),
    timeout_milliseconds := 15000
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notify_telegram_manual_review on public.topup_requests;
create trigger trg_notify_telegram_manual_review
  after update of status on public.topup_requests
  for each row execute function public.notify_telegram_manual_review();

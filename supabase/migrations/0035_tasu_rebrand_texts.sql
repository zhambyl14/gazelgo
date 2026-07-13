-- Tasu · 0035_tasu_rebrand_texts.sql
-- Атау GazelGo → Tasu ауыстырылғанда қалып қойған, пайдаланушыға көрінетін
-- екі мәтін: (1) қолдау чатының push тақырыбы, (2) Kaspi атауының
-- app_settings-тегі ЖАРИЯ мәні (0004_seed.sql-дегі seed default-ты
-- түзету ескі, әлдеқашан қолданылған миграцияны retroactively өзгертпейді
-- — сол себепті мұнда нақты UPDATE керек).

-- ---------- 1) support push тақырыбы ----------
create or replace function public.notify_support_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t record;
  v_snippet text;
begin
  select * into t from public.support_threads where id = new.thread_id;
  if not found then return new; end if;

  v_snippet := left(coalesce(new.body, ''), 120);
  if v_snippet = '' and new.image_path is not null then
    v_snippet := '📷 Сурет жіберілді';
  end if;
  if v_snippet = '' then v_snippet := 'Жаңа хабарлама'; end if;

  if new.sender_role = 'moderator' then
    -- модератор жауап берді — нақты сол пайдаланушыға ғана
    perform public.send_push(
      'Tasu қолдау қызметі',
      v_snippet,
      jsonb_build_object('type', 'support_reply', 'thread_id', t.id::text),
      array[t.user_id]
    );
  else
    -- пайдаланушы жазды — барлық модераторға (target_user_ids жоқ = broadcast)
    perform public.send_push(
      'Жаңа хабарлама — қолдау чаты',
      v_snippet,
      jsonb_build_object('type', 'support_message', 'thread_id', t.id::text)
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

-- ---------- 2) Kaspi атауы: тек әлі әдепкі "GazelGo" болып тұрса түзету
--    (модератор Баптаулар табынан өзгертіп қойған болса — тимейді) ----------
update public.app_settings
   set value = jsonb_set(value, '{kaspi_name}', '"Tasu"')
 where key = 'payment'
   and value->>'kaspi_name' = 'GazelGo';

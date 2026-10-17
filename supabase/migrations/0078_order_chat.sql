-- ============================================================
-- Tasu · 0078_order_chat.sql
-- ============================================================
-- ЗАКАЗ ЧАТЫ: клиент ↔ орындаушы (+ модератор бақылайды).
--
--   * Чат тек заказ ҚАБЫЛДАНҒАН соң ашылады (accepted … in_transit) және
--     аяқталғаннан кейін 24 сағатқа дейін (жоғалған зат т.б. үшін).
--   * Хабар жіберілгенде екінші тарапқа push кетеді.
--   * МОДЕРАТОР барлық чатты оқи алады (иесінің 2026-10-16 талабы:
--     «оқи алуға, тексеріп отыруға доступ болсын») және қажет болса өзі
--     жаза алады («Модератор» белгісімен). Сілтеме не балағат сөз бар хабар
--     `flagged` белгісін алады — модератор оларды бірінші көреді.
--   * Пайдаланушылар чаттың модератор тарапынан қаралуы мүмкін екенін
--     біледі (қосымшада чаттың басында ескерту тұрады).
--   * `order_chat` баптауы (әдепкі — қосулы) арқылы өшіруге болады.
--
-- Идемпотентті. Supabase SQL Editor-да ҚОЛМЕН қолданылады (0077-тен кейін).
-- ============================================================

create table if not exists public.order_messages (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null check (sender_role in ('client','executor','moderator')),
  body        text not null check (length(trim(body)) between 1 and 1000),
  flagged     boolean not null default false,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists idx_order_messages_order
  on public.order_messages (order_id, created_at);
create index if not exists idx_order_messages_recent
  on public.order_messages (created_at desc);

-- Заказдың тарабы ма (клиент не тағайындалған орындаушы). SECURITY DEFINER —
-- RLS саясатының ішінде orders кестесінің өз RLS-іне тірелмеу үшін.
create or replace function public.is_order_party(p_order uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.orders o
     where o.id = p_order
       and (o.client_id = auth.uid() or o.executor_id = auth.uid())
  );
$$;

grant execute on function public.is_order_party(uuid) to authenticated;

alter table public.order_messages enable row level security;

drop policy if exists order_messages_read on public.order_messages;
create policy order_messages_read on public.order_messages
  for select to authenticated
  using (public.is_moderator() or public.is_order_party(order_id));
-- INSERT/UPDATE саясаты ЖОҚ — тек төмендегі RPC арқылы.

insert into public.app_settings (key, value)
values ('order_chat', jsonb_build_object('enabled', true))
on conflict (key) do nothing;

-- ============================================================
-- Хабар жіберу
-- ============================================================
create or replace function public.order_chat_send(p_order uuid, p_body text)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role text;
  v_body text := trim(coalesce(p_body, ''));
  v_flag boolean;
  v_id uuid;
  v_enabled boolean;
  v_targets uuid[];
  v_preview text;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if v_body = '' then raise exception 'EMPTY'; end if;
  if length(v_body) > 1000 then v_body := left(v_body, 1000); end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  if o.client_id = v_uid then
    v_role := 'client';
  elsif o.executor_id = v_uid then
    v_role := 'executor';
  elsif public.is_moderator() then
    v_role := 'moderator';
  else
    raise exception 'FORBIDDEN';
  end if;

  if v_role <> 'moderator' then
    select coalesce((value->>'enabled')::boolean, true) into v_enabled
      from public.app_settings where key = 'order_chat';
    if not coalesce(v_enabled, true) then raise exception 'DISABLED'; end if;

    if not (o.status in ('accepted','arrived','loading','in_transit')
            or (o.status = 'completed'
                and o.completed_at > now() - interval '24 hours')) then
      raise exception 'CHAT_CLOSED';
    end if;
  end if;

  -- Модератордың назарына: сілтеме не балағат сөз.
  v_flag := v_body ~* '(https?://|www\.|t\.me/|wa\.me/)'
         or v_body ~* '(бляд|сука|хуй|пизд|ебан|мразь|qotaq|қотақ|сігіл)';

  insert into public.order_messages (order_id, sender_id, sender_role, body, flagged)
  values (p_order, v_uid, v_role, v_body, v_flag)
  returning id into v_id;

  -- Екінші тарапқа push.
  v_targets := array_remove(array[
    case when v_role <> 'client' then o.client_id end,
    case when v_role <> 'executor' then o.executor_id end
  ], null);
  v_preview := case when length(v_body) > 90 then left(v_body, 90) || '…'
                    else v_body end;

  if coalesce(array_length(v_targets, 1), 0) > 0 then
    perform public.send_push(
      case v_role when 'moderator' then 'Модератордан хабар'
                  when 'client' then 'Клиенттен хабар'
                  else 'Орындаушыдан хабар' end,
      v_preview,
      jsonb_build_object('type', 'order_chat', 'order_id', p_order::text),
      v_targets,
      case v_role when 'moderator' then 'Сообщение модератора'
                  when 'client' then 'Сообщение от клиента'
                  else 'Сообщение от исполнителя' end,
      v_preview
    );
  end if;

  return v_id;
end;
$$;

grant execute on function public.order_chat_send(uuid, text) to authenticated;

-- ============================================================
-- Оқылды деп белгілеу (тек тараптар — модератор оқығаны есепке алынбайды)
-- ============================================================
create or replace function public.order_chat_mark_read(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.is_order_party(p_order) then return; end if;
  update public.order_messages
     set read_at = now()
   where order_id = p_order
     and sender_id <> v_uid
     and read_at is null;
end;
$$;

grant execute on function public.order_chat_mark_read(uuid) to authenticated;

-- ============================================================
-- Модератор: соңғы чаттар тізімі (белгіленгендері бірінші сүзгімен)
-- ============================================================
create or replace function public.mod_order_chats(
  p_limit int default 60,
  p_flagged_only boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  return coalesce((
    select jsonb_agg(x order by x.last_at desc)
      from (
        select m.order_id,
               max(m.created_at) as last_at,
               count(*) as total,
               count(*) filter (where m.flagged) as flagged,
               (array_agg(m.body order by m.created_at desc))[1] as last_body,
               o.status::text as status,
               o.from_address, o.to_address,
               pc.full_name as client_name,
               pe.full_name as executor_name
          from public.order_messages m
          join public.orders o on o.id = m.order_id
          left join public.profiles pc on pc.id = o.client_id
          left join public.profiles pe on pe.id = o.executor_id
         group by m.order_id, o.status, o.from_address, o.to_address,
                  pc.full_name, pe.full_name
        having (not coalesce(p_flagged_only, false))
            or count(*) filter (where m.flagged) > 0
         order by max(m.created_at) desc
         limit greatest(1, least(coalesce(p_limit, 60), 200))
      ) x
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.mod_order_chats(int, boolean) to authenticated;

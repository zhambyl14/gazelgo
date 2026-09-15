-- Tasu · 0068_support_bot_human_takeover.sql
-- Модератор чатқа араласқаннан кейін осы тредте авто-ботты өшіру.

alter table public.support_threads
  add column if not exists human_takeover boolean not null default false;

-- Бұрын модератор жауап берген ашық тредтерді де бірден адам режиміне ауыстырамыз.
update public.support_threads t
   set human_takeover = true
 where not t.human_takeover
   and exists (
     select 1
       from public.support_messages m
      where m.thread_id = t.id
        and m.sender_role = 'moderator'
   );

-- Пайдаланушы қайта жазса да, модератор алған тред адам режимінде қалады.
create or replace function public.support_send(
  p_body text, p_image_path text default null, p_order_id uuid default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_thread uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if coalesce(trim(p_body), '') = '' and p_image_path is null then
    raise exception 'EMPTY';
  end if;

  select id into v_thread
    from public.support_threads
   where user_id = v_uid and status = 'open'
   order by created_at desc
   limit 1;

  if v_thread is null then
    insert into public.support_threads
      (user_id, order_id, last_sender_role, last_user_msg_at, last_msg_at)
    values (v_uid, p_order_id, 'user', now(), now())
    returning id into v_thread;
  else
    update public.support_threads
       set last_sender_role = 'user',
           last_user_msg_at = now(),
           last_msg_at = now(),
           order_id = coalesce(p_order_id, order_id)
     where id = v_thread;
  end if;

  insert into public.support_messages
    (thread_id, sender_id, sender_role, body, image_path)
  values (v_thread, v_uid, 'user', coalesce(trim(p_body), ''), p_image_path);
  return v_thread;
end;
$$;

grant execute on function public.support_send(text, text, uuid) to authenticated;

-- Модератор бірінші рет жауап берген сәттен бастап ботты осы тредке өшіреміз.
create or replace function public.support_reply(
  p_thread uuid, p_body text, p_image_path text default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_body), '') = '' and p_image_path is null then
    raise exception 'EMPTY';
  end if;

  update public.support_threads
     set status = 'open',
         last_sender_role = 'moderator',
         last_msg_at = now(),
         human_takeover = true
   where id = p_thread;

  insert into public.support_messages
    (thread_id, sender_id, sender_role, body, image_path)
  values (p_thread, v_uid, 'moderator', coalesce(trim(p_body), ''), p_image_path);
end;
$$;

grant execute on function public.support_reply(uuid, text, text) to authenticated;

-- Триггер user хабарламасын көрсе де, модератор алған тредке HTTP шақыру жібермейді.
create or replace function public.dispatch_support_bot()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_secret text;
  v_cfg jsonb;
  v_human_takeover boolean;
begin
  if new.sender_role <> 'user' then return new; end if;

  select coalesce(human_takeover, false)
    into v_human_takeover
    from public.support_threads
   where id = new.thread_id;
  if v_human_takeover then return new; end if;

  select value into v_cfg
    from public.app_settings
   where key = 'support_bot';
  if coalesce((v_cfg->>'enabled')::boolean, false) is not true then
    return new;
  end if;

  select value into v_secret
    from public.app_secrets
   where key = 'support_bot_secret';
  if v_secret is null or v_secret = '' then return new; end if;

  perform net.http_post(
    url := 'https://xibxaqcrdpgyzohfplda.supabase.co/functions/v1/support-bot',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-support-secret', v_secret
    ),
    body := jsonb_build_object(
      'thread_id', new.thread_id::text,
      'message_id', new.id::text
    ),
    timeout_milliseconds := 30000
  );
  return new;
exception when others then
  return new;
end;
$$;

-- Боттың хабарламасы модератор жауап бергеннен кейін жарысып келсе де, сақталмасын.
create or replace function public.bot_support_reply(
  p_secret text, p_thread uuid, p_body text, p_sender uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(p_secret, '') = '' or not exists (
    select 1 from public.app_secrets
     where key = 'support_bot_secret' and value = p_secret
  ) then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_body), '') = '' then raise exception 'EMPTY'; end if;

  update public.support_threads
     set status = 'open', last_sender_role = 'bot', last_msg_at = now()
   where id = p_thread
     and not coalesce(human_takeover, false);

  if not found then return; end if;

  insert into public.support_messages (thread_id, sender_id, sender_role, body)
  values (p_thread, p_sender, 'bot', trim(p_body));
end;
$$;

revoke all on function public.bot_support_reply(text, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.bot_support_reply(text, uuid, text, uuid)
  to service_role;

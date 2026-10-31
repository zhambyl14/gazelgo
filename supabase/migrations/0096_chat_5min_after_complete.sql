-- Аяқталған заказдағы чат 24 сағаттың орнына 5 минуттан кейін жабылады.
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
                and o.completed_at > now() - interval '5 minutes')) then
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

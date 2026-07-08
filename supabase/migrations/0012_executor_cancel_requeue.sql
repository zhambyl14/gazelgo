-- ============ Орындаушы қабылданған заказдан бас тартса — «cancelled»
-- емес, қайта «іздеуде» күйіне қайтарылады (клиент қайта заказ бермейді).
-- Сонымен қатар заказда қала аты сақталады (адрес дисплейінде "Қала, көше"
-- үшін және лентада «қала ішінде / межгород» белгісі үшін).

alter table public.orders
  add column if not exists from_city text,
  add column if not exists to_city text;

-- ============ create_order: қала өрістерін қабылдайды ============
create or replace function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null,
  p_photos text[] default '{}',
  p_from_city text default null,
  p_to_city text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_type public.order_type;
  v_size public.vehicle_size;
  v_system bigint;
  v_id uuid;
  v_active int;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and role = 'client') then
    raise exception 'NOT_CLIENT';
  end if;

  v_type := p_type::public.order_type;
  v_size := p_size::public.vehicle_size;

  if coalesce(trim(p_from_address),'') = '' or coalesce(trim(p_to_address),'') = ''
     or coalesce(trim(p_cargo),'') = '' then
    raise exception 'BAD_INPUT';
  end if;

  select count(*) into v_active from public.orders
  where client_id = v_uid
    and status in ('searching','accepted','arrived','loading','in_transit');
  if v_active >= 5 then raise exception 'TOO_MANY_ACTIVE'; end if;

  if v_type = 'bidding' then
    if p_client_price is null or p_client_price < 100 then raise exception 'BAD_PRICE'; end if;
    v_system := null;
  else
    v_system := public.instant_quote(p_size, p_distance_km);
  end if;

  insert into public.orders
    (client_id, type, from_address, from_lat, from_lng, from_city,
     to_address, to_lat, to_lng, to_city, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, v_type, trim(p_from_address), p_from_lat, p_from_lng, nullif(trim(coalesce(p_from_city,'')),''),
     trim(p_to_address), p_to_lat, p_to_lng, nullif(trim(coalesce(p_to_city,'')),''), coalesce(p_distance_km,0),
     trim(p_cargo), coalesce(trim(p_comment),''), v_size,
     case when v_type = 'bidding' then p_client_price end,
     v_system, coalesce(p_photos, '{}'))
  returning id into v_id;

  if v_type = 'instant' then
    perform public.assign_next_vip(v_id);
  end if;

  return jsonb_build_object('id', v_id, 'system_price', v_system);
end;
$$;

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[],text,text)
  to authenticated;

-- ============ cancel_order: орындаушы «accepted» кезеңінде бас тартса —
-- заказ «cancelled» емес, қайта «searching» күйіне ауысады ============
create or replace function public.cancel_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_is_client boolean;
  v_is_executor boolean;
begin
  if v_uid is null then raise exception 'AUTH'; end if;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  v_is_client := (o.client_id = v_uid);
  v_is_executor := (o.executor_id is not null and o.executor_id = v_uid);
  if not v_is_client and not v_is_executor then raise exception 'FORBIDDEN'; end if;
  if o.status in ('completed','cancelled','expired') then raise exception 'NOT_AVAILABLE'; end if;

  -- процесс кезеңі — бас тартуға болмайды
  if o.status in ('loading','in_transit') then raise exception 'CANNOT_CANCEL_IN_PROGRESS'; end if;

  -- searching: тек клиент
  if o.status = 'searching' and not v_is_client then raise exception 'FORBIDDEN'; end if;

  -- arrived: орындаушы бас тарта алмайды
  if o.status = 'arrived' and v_is_executor then raise exception 'CANNOT_CANCEL_IN_PROGRESS'; end if;

  -- қабылданғаннан кейін себеп міндетті
  if o.status <> 'searching' and coalesce(trim(p_reason),'') = '' then
    raise exception 'REASON_REQUIRED';
  end if;

  -- орындаушы қабылдағаннан кейін бас тартса: заказ жойылмайды, клиентке
  -- қайта заказ беруге тура келмеу үшін «іздеуде» күйіне қайта ашылады.
  if v_is_executor and o.status = 'accepted' then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;

    update public.orders
       set status = 'searching', executor_id = null, accepted_at = null,
           final_price = null
     where id = p_order;

    update public.offers set status = 'rejected'
     where order_id = p_order and status in ('pending','accepted');
    update public.vip_dispatches set status = 'expired'
     where order_id = p_order and status = 'pending';

    if o.type = 'instant' then
      perform public.assign_next_vip(p_order);
    end if;
    return;
  end if;

  update public.orders
     set status = 'cancelled', cancelled_by = v_uid,
         cancel_reason = coalesce(trim(p_reason),'')
   where id = p_order;

  update public.vip_dispatches set status = 'expired'
   where order_id = p_order and status = 'pending';
  update public.offers set status = 'rejected'
   where order_id = p_order and status = 'pending';

  if o.executor_id is not null then
    update public.executor_profiles set busy_order_id = null
     where user_id = o.executor_id and busy_order_id = p_order;
  end if;
end;
$$;

grant execute on function public.cancel_order(uuid,text) to authenticated;

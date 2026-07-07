-- GazelGo · 0008_docs_review_geo.sql
-- Құжат жаңарту модерациясы (нақты өрістер + қабылдау/қайтару),
-- VIP жауап уақыты 20с, заказ тек Қазақстан ішінде.

-- ============ executor_profiles: құжат ревью өрістері ============
alter table public.executor_profiles
  add column if not exists docs_update_fields text[] not null default '{}';
alter table public.executor_profiles
  add column if not exists docs_review_pending boolean not null default false;

-- guard: жаңа бағандарды тек сервер өзгертеді
create or replace function public.guard_executor_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    new.updated_at := now();
    return new;
  end if;
  if new.balance is distinct from old.balance
     or new.total_earned is distinct from old.total_earned
     or new.busy_order_id is distinct from old.busy_order_id
     or new.moderated_by is distinct from old.moderated_by
     or new.moderated_at is distinct from old.moderated_at
     or new.moderation_comment is distinct from old.moderation_comment
     or new.docs_update_requested is distinct from old.docs_update_requested
     or new.docs_update_comment is distinct from old.docs_update_comment
     or new.docs_update_fields is distinct from old.docs_update_fields
     or new.docs_review_pending is distinct from old.docs_review_pending then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  if new.status is distinct from old.status
     and not (old.status = 'rejected' and new.status = 'pending') then
    raise exception 'FORBIDDEN_STATUS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ============ mod_request_docs: нақты өрістермен ============
drop function if exists public.mod_request_docs(uuid, text);
create or replace function public.mod_request_docs(
  p_user uuid, p_fields text[], p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  if p_fields is null or array_length(p_fields,1) is null then
    raise exception 'NO_FIELDS';
  end if;
  update public.executor_profiles
     set docs_update_requested = true,
         docs_update_fields = p_fields,
         docs_update_comment = nullif(trim(coalesce(p_comment,'')),''),
         docs_review_pending = false
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;

-- ============ submit_docs_update: орындаушы жаңа құжат жібереді (ревьюге) ============
create or replace function public.submit_docs_update(
  p_id_doc text default null,
  p_license text default null,
  p_tech text default null,
  p_photos text[] default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update public.executor_profiles
     set id_doc_path = coalesce(p_id_doc, id_doc_path),
         license_path = coalesce(p_license, license_path),
         tech_passport_path = coalesce(p_tech, tech_passport_path),
         vehicle_photos = coalesce(p_photos, vehicle_photos),
         docs_review_pending = true
   where user_id = auth.uid();
  if not found then raise exception 'NOT_EXECUTOR'; end if;
end;
$$;

-- ============ модератор: құжат өзгерісін қабылдау / қайтару ============
create or replace function public.mod_approve_docs(p_user uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.executor_profiles
     set docs_update_requested = false, docs_review_pending = false,
         docs_update_fields = '{}', docs_update_comment = null
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;

create or replace function public.mod_reject_docs(p_user uuid, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.executor_profiles
     set docs_review_pending = false, docs_update_requested = true,
         docs_update_comment = nullif(trim(coalesce(p_comment,'')),'')
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;

grant execute on function public.mod_request_docs(uuid,text[],text) to authenticated;
grant execute on function public.submit_docs_update(text,text,text,text[]) to authenticated;
grant execute on function public.mod_approve_docs(uuid) to authenticated;
grant execute on function public.mod_reject_docs(uuid,text) to authenticated;

-- ============ VIP жауап уақыты 20 секунд ============
create or replace function public.assign_next_vip(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
  v_exec uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if not found or o.type <> 'instant' or o.status <> 'searching' then return; end if;

  update public.vip_dispatches
     set status = 'expired'
   where order_id = p_order and status = 'pending' and expires_at <= now();

  if exists (select 1 from public.vip_dispatches
             where order_id = p_order and status = 'pending' and expires_at > now()) then
    return;
  end if;

  select ep.user_id into v_exec
  from public.executor_profiles ep
  join public.profiles p on p.id = ep.user_id
  where ep.status = 'approved'
    and ep.vehicle_size = o.size
    and ep.busy_order_id is null
    and exists (select 1 from public.tariff_sessions ts
                where ts.executor_id = ep.user_id
                  and ts.kind = 'vip' and ts.expires_at > now())
    and not exists (select 1 from public.vip_dispatches d
                    where d.order_id = p_order and d.executor_id = ep.user_id)
  order by p.rating desc, random()
  limit 1;

  if v_exec is not null then
    insert into public.vip_dispatches (order_id, executor_id, expires_at)
    values (p_order, v_exec, now() + interval '20 seconds');
  end if;
end;
$$;

-- ============ create_order: тек Қазақстан ішінде ============
create or replace function public.create_order(
  p_type text,
  p_from_address text, p_from_lat float8, p_from_lng float8,
  p_to_address text,   p_to_lat float8,   p_to_lng float8,
  p_distance_km numeric,
  p_cargo text, p_comment text,
  p_size text,
  p_client_price bigint default null,
  p_photos text[] default '{}'
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

  -- Қазақстан шекарасы (шамамен)
  if p_from_lat < 40 or p_from_lat > 56 or p_from_lng < 46 or p_from_lng > 88
     or p_to_lat < 40 or p_to_lat > 56 or p_to_lng < 46 or p_to_lng > 88 then
    raise exception 'OUT_OF_KZ';
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
    (client_id, type, from_address, from_lat, from_lng,
     to_address, to_lat, to_lng, distance_km, cargo_desc, comment, size,
     client_price, system_price, photos)
  values
    (v_uid, v_type, trim(p_from_address), p_from_lat, p_from_lng,
     trim(p_to_address), p_to_lat, p_to_lng, coalesce(p_distance_km,0),
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

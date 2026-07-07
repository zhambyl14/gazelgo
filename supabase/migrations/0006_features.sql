-- GazelGo · 0006_features.sql
-- Жаңа мүмкіндіктер: аватар, екіжақты рейтинг, поездка саны, заказ фотолары,
-- құжат жаңарту сұранымы, қолдау чаты, ұсынысты қабылдамау/баға көтеру,
-- бас тарту ережелері, storage бакеттері, cron.

-- ============ profiles: поездка саны ============
alter table public.profiles
  add column if not exists trips integer not null default 0;

-- ============ reviews: екіжақты (клиент↔орындаушы) ============
alter table public.reviews
  add column if not exists author_role public.user_role;
alter table public.reviews
  add column if not exists author_id uuid references public.profiles(id) on delete cascade;
alter table public.reviews
  add column if not exists target_id uuid references public.profiles(id) on delete cascade;

-- бұрынғы жазбалар: клиент → орындаушыны бағалаған
update public.reviews
   set author_role = 'client', author_id = client_id, target_id = executor_id
 where author_id is null;

-- order_id бойынша бір ғана пікір шектеуін алып тастап, (order_id, author_role) қоямыз
alter table public.reviews drop constraint if exists reviews_order_id_key;
create unique index if not exists reviews_order_author
  on public.reviews(order_id, author_role);
create index if not exists idx_reviews_target
  on public.reviews(target_id, created_at desc);

-- рейтингті қайта есептеу (target бойынша)
create or replace function public.recompute_rating(p_user uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles p
     set rating = coalesce(sub.avg_r, 0), rating_count = coalesce(sub.cnt, 0)
    from (select round(avg(rating)::numeric, 2) as avg_r, count(*) as cnt
            from public.reviews where target_id = p_user) sub
   where p.id = p_user;
end;
$$;

-- ============ orders: тіркелген фотолар ============
alter table public.orders
  add column if not exists photos text[] not null default '{}';

-- ============ executor_profiles: құжат жаңарту сұранымы ============
alter table public.executor_profiles
  add column if not exists docs_update_requested boolean not null default false;
alter table public.executor_profiles
  add column if not exists docs_update_comment text;

-- ============ guard триггерлерін жаңарту ============
-- trips-ті тек сервер өзгертеді (клиент қолдан көтермес үшін)
create or replace function public.guard_profiles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('postgres','service_role','supabase_admin') then
    return new;
  end if;
  if new.role is distinct from old.role
     or new.rating is distinct from old.rating
     or new.rating_count is distinct from old.rating_count
     or new.trips is distinct from old.trips then
    raise exception 'FORBIDDEN_COLUMN';
  end if;
  return new;
end;
$$;

-- docs_update_requested/comment-ті тек сервер өзгертеді (модератор сұранымы)
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
     or new.docs_update_comment is distinct from old.docs_update_comment then
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

-- ============ create_order: p_photos параметрі ============
drop function if exists public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint);

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

grant execute on function public.create_order(
  text,text,float8,float8,text,float8,float8,numeric,text,text,text,bigint,text[])
  to authenticated;

-- ============ submit_review: екіжаққа да ============
create or replace function public.submit_review(p_order uuid, p_rating int, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_role public.user_role;
  v_target uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.status <> 'completed' then raise exception 'NOT_COMPLETED'; end if;
  if o.executor_id is null then raise exception 'NOT_FOUND'; end if;

  if v_uid = o.client_id then
    v_role := 'client'; v_target := o.executor_id;
  elsif v_uid = o.executor_id then
    v_role := 'executor'; v_target := o.client_id;
  else
    raise exception 'FORBIDDEN';
  end if;

  if exists (select 1 from public.reviews where order_id = p_order and author_role = v_role) then
    raise exception 'ALREADY_REVIEWED';
  end if;

  insert into public.reviews
    (order_id, client_id, executor_id, author_role, author_id, target_id, rating, comment)
  values
    (p_order, o.client_id, o.executor_id, v_role, v_uid, v_target,
     p_rating, coalesce(trim(p_comment),''));

  perform public.recompute_rating(v_target);
end;
$$;

-- ============ ұсынысты қабылдамау (клиент) ============
create or replace function public.reject_offer(p_offer uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  select order_id into v_order from public.offers where id = p_offer;
  if v_order is null then raise exception 'NOT_FOUND'; end if;
  if not exists (select 1 from public.orders where id = v_order and client_id = v_uid) then
    raise exception 'FORBIDDEN';
  end if;
  update public.offers set status = 'rejected'
   where id = p_offer and status = 'pending';
end;
$$;

-- ============ bidding бағасын көтеру (клиент) ============
create or replace function public.update_order_price(p_order uuid, p_price bigint)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if p_price is null or p_price < 100 then raise exception 'BAD_PRICE'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found or o.client_id <> v_uid then raise exception 'FORBIDDEN'; end if;
  if o.type <> 'bidding' or o.status <> 'searching' then raise exception 'NOT_AVAILABLE'; end if;
  update public.orders set client_price = p_price where id = p_order;
end;
$$;

-- ============ order_advance: поездка санағышы ============
create or replace function public.order_advance(p_order uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  o record;
  v_next public.order_status;
  v_expected public.order_status;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  v_next := p_status::public.order_status;

  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if o.executor_id is null or o.executor_id <> v_uid then raise exception 'FORBIDDEN'; end if;

  v_expected := case o.status
    when 'accepted'   then 'arrived'::public.order_status
    when 'arrived'    then 'loading'::public.order_status
    when 'loading'    then 'in_transit'::public.order_status
    when 'in_transit' then 'completed'::public.order_status
    else null
  end;
  if v_expected is null or v_next <> v_expected then raise exception 'BAD_TRANSITION'; end if;

  if v_next = 'completed' then
    update public.orders set status = 'completed', completed_at = now() where id = p_order;
    insert into public.earnings (executor_id, order_id, amount)
    values (v_uid, p_order, coalesce(o.final_price, 0))
    on conflict (order_id) do nothing;
    update public.executor_profiles
       set total_earned = total_earned + coalesce(o.final_price, 0),
           busy_order_id = null
     where user_id = v_uid;
    -- поездка санағышы (екі жаққа)
    update public.profiles set trips = trips + 1
     where id in (o.client_id, o.executor_id);
  else
    update public.orders set status = v_next where id = p_order;
  end if;
end;
$$;

-- ============ cancel_order: кезеңге қарай ережелер ============
-- searching: клиент қана, себепсіз болады.
-- accepted:  клиент те, орындаушы да — БІРАҚ себеп міндетті.
-- arrived:   тек клиент, себеп міндетті (орындаушы бас тарта алмайды).
-- loading/in_transit: ешкім бас тарта алмайды (процесс жүріп жатыр).
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

-- ============ модератор: құжат жаңартуды сұрау ============
create or replace function public.mod_request_docs(p_user uuid, p_comment text default '')
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  update public.executor_profiles
     set docs_update_requested = true,
         docs_update_comment = nullif(trim(coalesce(p_comment,'')),'')
   where user_id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end;
$$;

-- Орындаушы құжаттарды жаңартқанда флагты өшіру (definer)
create or replace function public.clear_docs_request()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.executor_profiles
     set docs_update_requested = false, docs_update_comment = null
   where user_id = auth.uid();
end;
$$;

-- ============ ҚОЛДАУ ЧАТЫ ============
create table if not exists public.support_threads (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  status           text not null default 'open',       -- open | closed
  last_sender_role text,                               -- user | moderator
  last_user_msg_at timestamptz,
  last_msg_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  closed_at        timestamptz,
  closed_by        uuid
);
create index if not exists idx_threads_user on public.support_threads(user_id, status);
create index if not exists idx_threads_open on public.support_threads(status, last_msg_at);

create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  thread_id   uuid not null references public.support_threads(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null,                            -- user | moderator
  body        text not null default '',
  image_path  text,                                     -- 'support' бакеті
  created_at  timestamptz not null default now()
);
create index if not exists idx_msgs_thread on public.support_messages(thread_id, created_at);

alter table public.support_threads  enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists threads_select on public.support_threads;
create policy threads_select on public.support_threads
  for select to authenticated
  using (user_id = auth.uid() or public.is_moderator());

drop policy if exists msgs_select on public.support_messages;
create policy msgs_select on public.support_messages
  for select to authenticated
  using (
    public.is_moderator()
    or exists (select 1 from public.support_threads t
               where t.id = support_messages.thread_id and t.user_id = auth.uid())
  );

-- Пайдаланушы хабарлама жібереді (ашық тред болмаса — жаңасын ашады)
create or replace function public.support_send(p_body text, p_image_path text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_thread uuid;
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if coalesce(trim(p_body),'') = '' and p_image_path is null then raise exception 'EMPTY'; end if;

  select id into v_thread from public.support_threads
   where user_id = v_uid and status = 'open'
   order by created_at desc limit 1;

  if v_thread is null then
    insert into public.support_threads (user_id, last_sender_role, last_user_msg_at, last_msg_at)
    values (v_uid, 'user', now(), now())
    returning id into v_thread;
  else
    update public.support_threads
       set last_sender_role = 'user', last_user_msg_at = now(), last_msg_at = now()
     where id = v_thread;
  end if;

  insert into public.support_messages (thread_id, sender_id, sender_role, body, image_path)
  values (v_thread, v_uid, 'user', coalesce(trim(p_body),''), p_image_path);
  return v_thread;
end;
$$;

-- Модератор жауап береді
create or replace function public.support_reply(p_thread uuid, p_body text, p_image_path text default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_moderator() then raise exception 'FORBIDDEN'; end if;
  if coalesce(trim(p_body),'') = '' and p_image_path is null then raise exception 'EMPTY'; end if;
  update public.support_threads
     set status = 'open', last_sender_role = 'moderator', last_msg_at = now()
   where id = p_thread;
  insert into public.support_messages (thread_id, sender_id, sender_role, body, image_path)
  values (p_thread, v_uid, 'moderator', coalesce(trim(p_body),''), p_image_path);
end;
$$;

-- Чатты аяқтау (екі тарап та)
create or replace function public.support_close(p_thread uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH'; end if;
  if not public.is_moderator()
     and not exists (select 1 from public.support_threads
                     where id = p_thread and user_id = v_uid) then
    raise exception 'FORBIDDEN';
  end if;
  update public.support_threads
     set status = 'closed', closed_at = now(), closed_by = v_uid
   where id = p_thread and status = 'open';
end;
$$;

-- Автоаяқтау: модератор соңғы жазып, пайдаланушы 24 сағат үнсіз болса
create or replace function public.auto_close_support()
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.support_threads
     set status = 'closed', closed_at = now()
   where status = 'open'
     and last_sender_role = 'moderator'
     and last_msg_at < now() - interval '24 hours';
  -- мүлдем тасталған тредтер (7 күн)
  update public.support_threads
     set status = 'closed', closed_at = now()
   where status = 'open' and last_msg_at < now() - interval '7 days';
end;
$$;

-- ============ STORAGE бакеттері ============
insert into storage.buckets (id, name, public)
values ('orders', 'orders', true), ('support', 'support', true)
on conflict (id) do nothing;

-- orders: өз папкаңа жаз, көпшілік оқиды (аяқталған соң қосымша өшіреді)
drop policy if exists "orders_insert_own" on storage.objects;
create policy "orders_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'orders' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "orders_select_all" on storage.objects;
create policy "orders_select_all" on storage.objects
  for select using (bucket_id = 'orders');
drop policy if exists "orders_delete_own_or_mod" on storage.objects;
create policy "orders_delete_own_or_mod" on storage.objects
  for delete to authenticated
  using (bucket_id = 'orders'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_moderator()));

-- support: өз папкаңа жаз, көпшілік оқиды
drop policy if exists "support_insert_own" on storage.objects;
create policy "support_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'support' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "support_select_all" on storage.objects;
create policy "support_select_all" on storage.objects
  for select using (bucket_id = 'support');

-- ============ realtime ============
do $$ begin alter publication supabase_realtime add table public.support_messages;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.support_threads;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.reviews;
exception when duplicate_object then null; end $$;

-- ============ grants ============
grant execute on function public.reject_offer(uuid) to authenticated;
grant execute on function public.update_order_price(uuid,bigint) to authenticated;
grant execute on function public.mod_request_docs(uuid,text) to authenticated;
grant execute on function public.clear_docs_request() to authenticated;
grant execute on function public.support_send(text,text) to authenticated;
grant execute on function public.support_reply(uuid,text,text) to authenticated;
grant execute on function public.support_close(uuid) to authenticated;
revoke execute on function public.recompute_rating(uuid) from public, anon, authenticated;
revoke execute on function public.auto_close_support() from public, anon, authenticated;

-- ============ cron ============
do $$ begin perform cron.unschedule('gazelgo-auto-close-support');
exception when others then null; end $$;
select cron.schedule('gazelgo-auto-close-support', '*/30 * * * *',
  $$select public.auto_close_support()$$);

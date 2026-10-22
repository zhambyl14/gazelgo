-- ============================================================
-- Tasu · 0088_order_chat_search.sql
-- ============================================================
-- Модератор «Заказ чаттары» тізімінде ІЗДЕУ: заказ нөмірі (#xxxxxxxx —
-- заказ ID-ының алғашқы 8 таңбасы, толық ID де болады), клиент не
-- орындаушының аты, телефоны бойынша. Іздеу СЕРВЕРДЕ жүреді, сондықтан
-- «соңғы 80 чат» шегінен тыс ескі заказ да табылады.
--
-- mod_order_chats(int, boolean) орнына mod_order_chats(int, boolean, text)
-- (бұрынғы екі аргументті шақыру p_query = null-мен бұрынғыдай жұмыс істейді).
--
-- Идемпотентті. Supabase SQL Editor-да қолданылады (0087-ден кейін).
-- ============================================================

drop function if exists public.mod_order_chats(int, boolean);

create or replace function public.mod_order_chats(
  p_limit int default 60,
  p_flagged_only boolean default false,
  p_query text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_q text := lower(regexp_replace(coalesce(p_query, ''), '[#\s]', '', 'g'));
  v_digits text := regexp_replace(coalesce(p_query, ''), '[^0-9]', '', 'g');
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
         where v_q = ''
            or o.id::text ilike '%' || v_q || '%'
            or pc.full_name ilike '%' || btrim(p_query) || '%'
            or pe.full_name ilike '%' || btrim(p_query) || '%'
            or (length(v_digits) >= 7 and (
                 regexp_replace(coalesce(pc.phone, ''), '[^0-9]', '', 'g') like '%' || v_digits || '%'
                 or regexp_replace(coalesce(pe.phone, ''), '[^0-9]', '', 'g') like '%' || v_digits || '%'))
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

grant execute on function public.mod_order_chats(int, boolean, text) to authenticated;

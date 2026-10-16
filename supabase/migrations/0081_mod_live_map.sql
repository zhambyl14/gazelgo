-- ============================================================
-- Tasu · 0081_mod_live_map.sql
-- ============================================================
-- МОДЕРАТОРДЫҢ ТІРІ КАРТАСЫ: сұраныс пен ұсыныс бір картада.
--
--   * орындаушылар — соңғы 30 минутта орнын жібергендер (0073: белсенді
--     заказда 15с сайын, бос әрі линияда болса минутына бір рет): көлік
--     түрі, бос / заказда / үзілісте, аты-жөні мен телефоны;
--   * заказдар — іздеудегі және орындалып жатқан (соңғы 3 күн) заказдардың
--     алу нүктелері.
--
-- Модератор «Алматыда заказ көп, бос көлік аз» дегенді бір қарағанда
-- көреді, қажет болса орындаушыға қоңырау шалады не жаппай хабарлама
-- жібереді.
--
-- executor_locations-қа тікелей SELECT саясаты ӘДЕЙІ жоқ (0060) — модератор
-- да тек осы SECURITY DEFINER функциясы арқылы оқиды.
--
-- 0073-тен КЕЙІН қолданылады (heading бағаны керек). Идемпотентті.
-- ============================================================

create or replace function public.mod_live_map()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_moderator() then
    raise exception 'FORBIDDEN';
  end if;

  return jsonb_build_object(
    'executors', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', l.executor_id,
               'lat', l.lat,
               'lng', l.lng,
               'heading', l.heading,
               'updated_at', l.updated_at,
               'order_id', l.order_id,
               'vehicle_type', ep.vehicle_type::text,
               'name', p.full_name,
               'phone', p.phone,
               'busy', ep.busy_order_id is not null or l.order_id is not null,
               'on_line', coalesce(ep.on_line, true)
             ))
        from public.executor_locations l
        join public.executor_profiles ep on ep.user_id = l.executor_id
        join public.profiles p on p.id = l.executor_id
       where l.updated_at > now() - interval '30 minutes'
         and ep.status = 'approved'
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', o.id,
               'lat', o.from_lat,
               'lng', o.from_lng,
               'status', o.status::text,
               'vehicle_type', o.vehicle_type::text,
               'price', coalesce(o.final_price, o.client_price),
               'created_at', o.created_at,
               'from_city', o.from_city
             ))
        from public.orders o
       where o.status in ('searching', 'accepted', 'arrived', 'loading', 'in_transit')
         and o.created_at > now() - interval '3 days'
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.mod_live_map() to authenticated;

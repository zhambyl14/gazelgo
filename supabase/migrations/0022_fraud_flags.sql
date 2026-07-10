-- GazelGo · 0022_fraud_flags.sql
-- Жеңіл эвристикалық «тексеру қажет» флагы — модератор заказды ашқанда
-- көреді. ML/сурет-анализ ЕМЕС (жүктің ішін тексеру мүмкін емес, мұны ML
-- шешеді деу — жалған қауіпсіздік сезімі). Тек объективті статистика:
-- бір client+executor жұбының қайталануы (collusion үшін міндетті шарт —
-- бір реттік кездейсоқтық емес) және жаңа аккаунт + жоғары құнды заказ.
-- Табалдырықтар нақты қолдану деректері жиналған соң нақтыланады.

create or replace function public.order_fraud_flags(p_order uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  o record;
  v_pair_count int := 0;
  v_client_age_hours numeric;
  v_client_order_count int;
  v_price bigint;
begin
  if not public.is_moderator() then raise exception 'FORBIDDEN'; end if;

  select * into o from public.orders where id = p_order;
  if not found then raise exception 'NOT_FOUND'; end if;

  if o.executor_id is not null then
    select count(*) into v_pair_count
      from public.orders x
     where x.client_id = o.client_id
       and x.executor_id = o.executor_id
       and x.status = 'completed'
       and x.completed_at > now() - interval '30 days';
  end if;

  select extract(epoch from (now() - p.created_at)) / 3600.0
    into v_client_age_hours
    from public.profiles p where p.id = o.client_id;

  select count(*) into v_client_order_count
    from public.orders where client_id = o.client_id;

  v_price := coalesce(o.final_price, o.client_price, 0);

  return jsonb_build_object(
    'repeated_pair_count', v_pair_count,
    'client_account_age_hours', round(coalesce(v_client_age_hours, 0)::numeric, 1),
    'client_total_orders', coalesce(v_client_order_count, 0),
    'is_new_account_high_value',
      (coalesce(v_client_age_hours, 999) < 24 and v_price > 20000)
  );
end;
$$;
revoke all on function public.order_fraud_flags(uuid) from public, anon;
grant execute on function public.order_fraud_flags(uuid) to authenticated;

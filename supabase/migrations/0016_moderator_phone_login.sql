-- GazelGo · 0016_moderator_phone_login.sql
-- Кіру телефон+құпиясөзге көшкен соң (0015), бұрын email-мен (moderator@
-- gazelgo.kz) құрылған модератор аккаунты LoginScreen-нен кіре алмай қалды —
-- өріс тек телефон нөмірін қабылдайды. Бар аккаунтты сол баяғы құпиясөзбен
-- телефон-негізді синтетикалық email-ге көшіреміз (0004_seed.sql-дағы жаңа
-- ағынмен бірдей): +7 700 000 00 01 нөмірі.

do $$
declare
  v_id uuid;
  v_old_email text := 'moderator@gazelgo.kz';
  v_new_email text := '77000000001@phone.gazelgo.kz';
begin
  select id into v_id from auth.users where email = v_old_email;
  if v_id is not null and not exists (
    select 1 from auth.users where email = v_new_email
  ) then
    update auth.users
       set email = v_new_email,
           raw_user_meta_data = raw_user_meta_data || '{"phone":"77000000001"}'::jsonb,
           updated_at = now()
     where id = v_id;

    update auth.identities
       set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_new_email)),
           updated_at = now()
     where user_id = v_id and provider = 'email';

    update public.profiles
       set phone = '77000000001'
     where id = v_id and (phone is null or phone = '');
  end if;
end $$;

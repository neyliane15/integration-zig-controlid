-- =====================================================================================================
-- Ambiente local (ferramentas/local) — SÓ para a máquina do desenvolvedor, nunca no Supabase.
-- Schema local_auth: funções que o portão (portao.mjs) chama via PostgREST com a service_role para
-- imitar o GoTrue (login com senha bcrypt de auth.users, cadastro, troca de senha). Idempotente.
-- =====================================================================================================

alter role authenticator with login password 'authenticator';

create schema if not exists local_auth;
revoke all on schema local_auth from public, anon, authenticated;
grant usage on schema local_auth to service_role;

create or replace function local_auth.usuario_json(p_id uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'id', u.id, 'aud', 'authenticated', 'role', 'authenticated', 'email', u.email, 'phone', '',
    'email_confirmed_at', u.email_confirmed_at, 'confirmed_at', u.confirmed_at, 'last_sign_in_at', u.last_sign_in_at,
    'app_metadata', coalesce(u.raw_app_meta_data, '{"provider":"email","providers":["email"]}'::jsonb),
    'user_metadata', coalesce(u.raw_user_meta_data, '{}'::jsonb),
    'identities', '[]'::jsonb, 'created_at', u.created_at, 'updated_at', u.updated_at, 'is_anonymous', false)
    from auth.users u where u.id = p_id
$$;

create or replace function local_auth.entrar(p_email text, p_senha text) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users
   where lower(email) = lower(btrim(p_email))
     and encrypted_password is not null
     and encrypted_password = extensions.crypt(p_senha, encrypted_password)
     and (banned_until is null or banned_until < now())
     and deleted_at is null;
  if v_id is null then
    return null;
  end if;
  update auth.users set last_sign_in_at = now() where id = v_id;
  return local_auth.usuario_json(v_id);
end $$;

create or replace function local_auth.usuario(p_id uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select local_auth.usuario_json(p_id)
$$;

create or replace function local_auth.cadastrar(p_email text, p_senha text, p_meta jsonb default '{}') returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido' using errcode = '22023';
  end if;
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'A senha deve ter pelo menos 6 caracteres' using errcode = '22023';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'User already registered' using errcode = '23505';
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at, last_sign_in_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          extensions.crypt(p_senha, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', coalesce(p_meta, '{}'::jsonb), now(), now(), now(), '', '', '', '');
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
  return local_auth.usuario_json(v_id);
end $$;

create or replace function local_auth.atualizar(p_id uuid, p_senha text default null, p_meta jsonb default null) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_senha is not null then
    if length(p_senha) < 6 then
      raise exception 'A senha deve ter pelo menos 6 caracteres' using errcode = '22023';
    end if;
    update auth.users set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')), updated_at = now()
     where id = p_id;
  end if;
  if p_meta is not null then
    update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || p_meta, updated_at = now()
     where id = p_id;
  end if;
  return local_auth.usuario_json(p_id);
end $$;

revoke all on all functions in schema local_auth from public, anon, authenticated;
grant execute on all functions in schema local_auth to service_role;

-- O PostgREST relê o schema quando recebe este aviso.
notify pgrst, 'reload schema';

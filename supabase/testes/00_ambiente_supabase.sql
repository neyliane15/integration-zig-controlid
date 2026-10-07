-- =====================================================================================================
-- Ambiente que imita o Supabase num Postgres 16 puro (testes de banco e ambiente local).
-- NÃO vai para o Supabase de verdade (lá isso tudo já existe). Idempotente.
--   * papéis anon, authenticated, service_role (bypassrls), authenticator
--   * schema extensions (pgcrypto, uuid-ossp)
--   * schema auth: users, identities, uid(), role(), jwt(), email()
--   * schema storage mínimo: buckets, objects, foldername()  (para as políticas das fotos)
--   * privilégios padrão do Supabase em public
--   * schema teste: ok(), erro(), como(), como_servico(), contar()
-- =====================================================================================================

-- ------------------------------------------------------------------------------------------- papéis
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit password 'authenticator';
  end if;
end $$;
grant anon, authenticated, service_role to authenticator;

-- ------------------------------------------------------------------------------------- extensões
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
do $$ begin execute format('alter database %I set search_path = "$user", public, extensions', current_database()); end $$;
set search_path = "$user", public, extensions;

-- ------------------------------------------------------------------------------------------ auth
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  instance_id                 uuid,
  id                          uuid primary key,
  aud                         varchar(255),
  role                        varchar(255),
  email                       varchar(255),
  encrypted_password          varchar(255),
  email_confirmed_at          timestamptz,
  invited_at                  timestamptz,
  confirmation_token          varchar(255),
  confirmation_sent_at        timestamptz,
  recovery_token              varchar(255),
  recovery_sent_at            timestamptz,
  email_change_token_new      varchar(255),
  email_change                varchar(255),
  email_change_sent_at        timestamptz,
  last_sign_in_at             timestamptz,
  raw_app_meta_data           jsonb,
  raw_user_meta_data          jsonb,
  is_super_admin              boolean,
  created_at                  timestamptz,
  updated_at                  timestamptz,
  phone                       text unique default null,
  phone_confirmed_at          timestamptz,
  phone_change                text default '',
  phone_change_token          varchar(255) default '',
  phone_change_sent_at        timestamptz,
  confirmed_at                timestamptz generated always as (least(email_confirmed_at, phone_confirmed_at)) stored,
  email_change_token_current  varchar(255) default '',
  email_change_confirm_status smallint default 0,
  banned_until                timestamptz,
  reauthentication_token      varchar(255) default '',
  reauthentication_sent_at    timestamptz,
  is_sso_user                 boolean not null default false,
  deleted_at                  timestamptz,
  is_anonymous                boolean not null default false
);
create index if not exists users_email_idx on auth.users (email);

create table if not exists auth.identities (
  provider_id      text not null,
  user_id          uuid not null references auth.users (id) on delete cascade,
  identity_data    jsonb not null,
  provider         text not null,
  last_sign_in_at  timestamptz,
  created_at       timestamptz,
  updated_at       timestamptz,
  email            text generated always as (lower(identity_data ->> 'email')) stored,
  id               uuid primary key default gen_random_uuid(),
  constraint identities_provider_id_provider_unique unique (provider_id, provider)
);
create index if not exists identities_user_id_idx on auth.identities (user_id);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.email() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant execute on all functions in schema auth to anon, authenticated, service_role;
grant all on all tables in schema auth to service_role;

-- --------------------------------------------------------------------------- storage (mínimo)
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id                  text primary key,
  name                text not null unique,
  owner               uuid,
  public              boolean default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

create table if not exists storage.objects (
  id                uuid primary key default gen_random_uuid(),
  bucket_id         text references storage.buckets (id),
  name              text,
  owner             uuid,
  metadata          jsonb,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now(),
  last_accessed_at  timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;

create or replace function storage.foldername(name text) returns text[]
language plpgsql immutable as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1 : array_length(_parts, 1) - 1];
end $$;

grant all on all tables in schema storage to anon, authenticated, service_role;
grant execute on all functions in schema storage to anon, authenticated, service_role;

-- ---------------------------------------------------------- privilégios padrão do Supabase em public
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- ======================================================================================= teste
create schema if not exists teste;
grant usage on schema teste to public;

-- Afirmação: notice 'ok: ...' ou exceção 'FALHOU: ...'.
create or replace function teste.ok(p_descricao text, p_condicao boolean) returns void
language plpgsql as $$
begin
  if p_condicao is true then
    raise notice 'ok: %', p_descricao;
  else
    raise exception 'FALHOU: % (condição = %)', p_descricao, coalesce(p_condicao::text, 'null');
  end if;
end $$;

-- Executa p_sql e exige que falhe com mensagem contendo p_trecho (e, se informado, o SQLSTATE p_codigo).
create or replace function teste.erro(p_descricao text, p_sql text, p_trecho text default null, p_codigo text default null)
returns void language plpgsql as $$
declare
  v_msg text;
  v_cod text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text, v_cod = returned_sqlstate;
    if (p_trecho is null or position(p_trecho in v_msg) > 0) and (p_codigo is null or v_cod = p_codigo) then
      raise notice 'ok: % (erro: %)', p_descricao, v_msg;
      return;
    end if;
    raise exception 'FALHOU: % — erro inesperado [%] %', p_descricao, v_cod, v_msg;
  end;
  raise exception 'FALHOU: % — era esperado um erro e o comando passou', p_descricao;
end $$;

-- Executa p_sql e exige que NÃO falhe.
create or replace function teste.passa(p_descricao text, p_sql text) returns void
language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    raise exception 'FALHOU: % — %', p_descricao, v_msg;
  end;
  raise notice 'ok: %', p_descricao;
end $$;

-- Quantidade de linhas devolvidas por p_sql (como o papel atual).
create or replace function teste.contar(p_sql text) returns bigint
language plpgsql as $$
declare
  v bigint;
begin
  execute format('select count(*) from (%s) _q', p_sql) into v;
  return v;
end $$;

-- Id do usuário pelo e-mail (enxerga auth.users mesmo vestindo outro papel).
create or replace function teste.uid(p_email text) returns uuid
language sql stable security definer set search_path = pg_catalog, pg_temp as $$
  select id from auth.users where lower(email) = lower(p_email)
$$;

-- Executa um comando (insert/update/delete) e devolve quantas linhas ele afetou.
create or replace function teste.afetadas(p_sql text) returns bigint
language plpgsql as $$
declare
  v bigint;
begin
  execute p_sql;
  get diagnostics v = row_count;
  return v;
end $$;

-- "Veste" um usuário pelo e-mail (null = anon), como o PostgREST faz: set local role + claims.
create or replace function teste.como(p_email text) returns uuid
language plpgsql as $$
declare
  v_id uuid;
begin
  reset role;
  if p_email is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    set local role anon;
    return null;
  end if;
  select id into v_id from auth.users where lower(email) = lower(p_email);
  if v_id is null then
    raise exception 'teste.como: usuário % não existe', p_email;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_id, 'role', 'authenticated', 'email', lower(p_email), 'aud', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  set local role authenticated;
  return v_id;
end $$;

-- Veste o service_role (N8N).
create or replace function teste.como_servico() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  set local role service_role;
end $$;

-- Volta a ser o dono do banco (SQL Editor), sem JWT.
create or replace function teste.como_dono() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

grant execute on all functions in schema teste to public;

-- ---------------------------------------------------------------------------------------------
-- Cenário padrão dos testes do backend-1 (resolvido em tempo de execução; chamar como dono).
-- Empresas E1 'c1…e1' e E2 'c1…e2'; usuários b1.<papel><n>@teste.local (senha 'segredo1');
-- funcionários F1a, F1b (E1) e F2a (E2); jornada J1 (E1) e J2 (E2); integrações I1 (acesso, E1), I1r (REP, E1), I2 (acesso, E2).
-- ---------------------------------------------------------------------------------------------
create or replace function teste.cenario_b1() returns void
language plpgsql as $$
declare
  u record;
begin
  perform teste.como_dono();
  insert into public.empresas (id, nome) values
    ('c1000000-0000-4000-8000-0000000000e1', 'Empresa Um'),
    ('c1000000-0000-4000-8000-0000000000e2', 'Empresa Dois');
  insert into public.funcionarios (id, empresa_id, nome, cpf, pontos_comissao, data_admissao) values
    ('c1000000-0000-4000-8000-0000000001a1', 'c1000000-0000-4000-8000-0000000000e1', 'Fulano Um', '52998224725', 10, '2026-01-01'),
    ('c1000000-0000-4000-8000-0000000001b1', 'c1000000-0000-4000-8000-0000000000e1', 'Beltrano Um', null, 5, '2026-01-01'),
    ('c1000000-0000-4000-8000-0000000001a2', 'c1000000-0000-4000-8000-0000000000e2', 'Fulano Dois', '11144477735', 7, '2026-01-01');
  insert into public.jornadas (id, empresa_id, nome) values
    ('c1000000-0000-4000-8000-000000000201', 'c1000000-0000-4000-8000-0000000000e1', 'Noite'),
    ('c1000000-0000-4000-8000-000000000202', 'c1000000-0000-4000-8000-0000000000e2', 'Noite');
  insert into public.integracoes (id, empresa_id, tipo, nome) values
    ('c1000000-0000-4000-8000-000000000101', 'c1000000-0000-4000-8000-0000000000e1', 'controlid_acesso', 'Porta 1'),
    ('c1000000-0000-4000-8000-000000000103', 'c1000000-0000-4000-8000-0000000000e1', 'controlid_rep', 'REP 1'),
    ('c1000000-0000-4000-8000-000000000102', 'c1000000-0000-4000-8000-0000000000e2', 'controlid_acesso', 'Porta 2');
  insert into public.integracoes_segredos (integracao_id, empresa_id, segredos) values
    ('c1000000-0000-4000-8000-000000000101', 'c1000000-0000-4000-8000-0000000000e1', '{"url":"http://10.0.0.1","login":"admin","senha":"s3cr3t-1"}'),
    ('c1000000-0000-4000-8000-000000000102', 'c1000000-0000-4000-8000-0000000000e2', '{"url":"http://10.0.0.2","login":"admin","senha":"s3cr3t-2"}');
  for u in
    select * from (values
      ('b1.master@teste.local',   'master',        null::uuid),
      ('b1.admin1@teste.local',   'administrador', 'c1000000-0000-4000-8000-0000000000e1'::uuid),
      ('b1.gerente1@teste.local', 'gerente',       'c1000000-0000-4000-8000-0000000000e1'::uuid),
      ('b1.leitura1@teste.local', 'leitura',       'c1000000-0000-4000-8000-0000000000e1'::uuid),
      ('b1.inativo1@teste.local', 'gerente',       'c1000000-0000-4000-8000-0000000000e1'::uuid),
      ('b1.admin2@teste.local',   'administrador', 'c1000000-0000-4000-8000-0000000000e2'::uuid),
      ('b1.gerente2@teste.local', 'gerente',       'c1000000-0000-4000-8000-0000000000e2'::uuid),
      ('b1.leitura2@teste.local', 'leitura',       'c1000000-0000-4000-8000-0000000000e2'::uuid)
    ) t(email, papel, empresa)
  loop
    perform public.admin_criar_usuario(u.email, 'segredo1', split_part(u.email, '@', 1), u.papel, u.empresa, null);
  end loop;
  update public.perfis set ativo = false where email = 'b1.inativo1@teste.local';
  update public.perfis set funcionario_id = 'c1000000-0000-4000-8000-0000000001a1' where email = 'b1.leitura1@teste.local';
  -- cadastro aberto (GoTrue): perfil sem empresa
  insert into auth.users (id, email, raw_user_meta_data, created_at)
  values ('c1000000-0000-4000-8000-00000000f0f0', 'b1.semempresa@teste.local', '{"nome":"Sem Empresa"}', now());
end $$;
grant execute on function teste.cenario_b1() to public;

-- =====================================================================================================
-- 20261006000100_base.sql  (backend-1)
-- Extensões, agora(), tocar_atualizado_em(), empresas, perfis, configuracao, auxiliares das políticas (§3.1),
-- dia_de_trabalho*, resolver_empresa, gatilho em auth.users, RPCs de usuários/empresa, RLS.
-- Idempotente. Privilégios: etiquetas no comment (concedidos por 20261006000900_permissoes.sql).
-- =====================================================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------------------------------- relógio
create or replace function public.agora() returns timestamptz
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(nullif(current_setting('app.agora', true), '')::timestamptz, now())
$$;
comment on function public.agora() is
  '[api] Relógio da lógica de negócio: app.agora (testes) ou now().';

create or replace function public.tocar_atualizado_em() returns trigger
language plpgsql
set search_path = public, extensions, pg_temp
as $$
begin
  new.atualizado_em := now();
  return new;
end $$;
comment on function public.tocar_atualizado_em() is '[interno] Gatilho: mantém atualizado_em.';

-- ---------------------------------------------------------------------------- contexto da chamada
-- Sem JWT nenhum (SQL Editor / dono do banco).
create or replace function public.sem_jwt() returns boolean
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}') in ('{}', 'null')
     and nullif(current_setting('request.jwt.claim.sub', true), '') is null
     and coalesce(nullif(current_setting('role', true), ''), 'none') not in ('anon', 'authenticated', 'service_role')
$$;
comment on function public.sem_jwt() is '[interno] Verdadeiro quando a chamada vem do SQL Editor (sem JWT).';

-- "Sistema": service_role (N8N) ou SQL Editor. Nunca anon/authenticated.
create or replace function public.eh_sistema() returns boolean
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select auth.uid() is null
     and coalesce(nullif(current_setting('role', true), ''), 'none') not in ('anon', 'authenticated')
     and coalesce(auth.role(), '') not in ('anon', 'authenticated')
$$;
comment on function public.eh_sistema() is '[interno] Verdadeiro para service_role ou SQL Editor.';

-- ======================================================================================= empresas
create table if not exists public.empresas (
  id                              uuid primary key default gen_random_uuid(),
  nome                            text not null check (btrim(nome) <> ''),
  cnpj                            text check (cnpj is null or cnpj ~ '^[0-9]{14}$'),
  telefone                        text,
  cidade                          text,
  uf                              text check (uf is null or uf ~ '^[A-Z]{2}$'),
  fuso                            text not null default 'America/Sao_Paulo',
  virada_dia                      time not null default '05:00',
  comissao_percentual_retencao    numeric(5,2) not null default 20
                                  check (comissao_percentual_retencao between 0 and 100),
  ponto_alarme_atraso             boolean not null default false,
  ponto_janela_duplicada_minutos  int not null default 2 check (ponto_janela_duplicada_minutos between 0 and 30),
  ativa                           boolean not null default true,
  criado_em                       timestamptz not null default now(),
  atualizado_em                   timestamptz not null default now()
);
comment on table public.empresas is '[api:crud] Empresas (estabelecimentos/redes).';

-- ========================================================================================= perfis
create table if not exists public.perfis (
  id          uuid primary key references auth.users (id) on delete cascade,
  nome        text not null,
  email       text not null,
  papel       text not null default 'administrador'
              check (papel in ('master', 'administrador', 'gerente', 'leitura')),
  empresa_id  uuid references public.empresas (id) on delete cascade,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  constraint perfis_master_sem_empresa check (papel <> 'master' or empresa_id is null)
);
create index if not exists perfis_empresa_idx on public.perfis (empresa_id);
comment on table public.perfis is '[api:leitura] Perfis dos usuários (1:1 com auth.users). Escrita só por RPC.';

-- =================================================================================== configuracao
create table if not exists public.configuracao (
  id               int primary key default 1 check (id = 1),
  master_email     text,
  cadastro_aberto  boolean not null default true
);
insert into public.configuracao (id) values (1) on conflict (id) do nothing;
comment on table public.configuracao is '[api:leitura] Configuração global da plataforma (só o master lê).';

-- ================================================================ auxiliares das políticas (§3.1)
create or replace function public.eh_master() returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select exists (select 1 from public.perfis p where p.id = auth.uid() and p.ativo and p.papel = 'master')
$$;
comment on function public.eh_master() is '[politica] Usuário atual é master ativo.';

create or replace function public.meu_papel() returns text
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.papel from public.perfis p where p.id = auth.uid()
$$;
comment on function public.meu_papel() is '[politica] Papel do usuário atual.';

create or replace function public.minha_empresa() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.empresa_id from public.perfis p where p.id = auth.uid()
$$;
comment on function public.minha_empresa() is '[politica] Empresa do usuário atual (null para master).';

create or replace function public.empresa_leitura() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.empresa_id
    from public.perfis p
    join public.empresas e on e.id = p.empresa_id
   where p.id = auth.uid() and p.ativo and e.ativa
     and p.papel in ('administrador', 'gerente', 'leitura')
$$;
comment on function public.empresa_leitura() is '[politica] Empresa que o usuário pode ler (L G A ativos).';

create or replace function public.empresa_operacao() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.empresa_id
    from public.perfis p
    join public.empresas e on e.id = p.empresa_id
   where p.id = auth.uid() and p.ativo and e.ativa
     and p.papel in ('administrador', 'gerente')
$$;
comment on function public.empresa_operacao() is '[politica] Empresa que o usuário pode operar (G A ativos).';

create or replace function public.empresa_administracao() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.empresa_id
    from public.perfis p
    join public.empresas e on e.id = p.empresa_id
   where p.id = auth.uid() and p.ativo and e.ativa
     and p.papel = 'administrador'
$$;
comment on function public.empresa_administracao() is '[politica] Empresa que o usuário administra (A ativo).';

create or replace function public.pode_ler(e uuid) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_leitura())
$$;
comment on function public.pode_ler(uuid) is '[politica] Master, sistema ou L G A da empresa.';

create or replace function public.pode_operar(e uuid) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_operacao())
$$;
comment on function public.pode_operar(uuid) is '[politica] Master, sistema ou G A da empresa.';

create or replace function public.pode_administrar(e uuid) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_administracao())
$$;
comment on function public.pode_administrar(uuid) is '[politica] Master, sistema ou A da empresa.';

-- ===================================================================== escopo de empresa (§2.5)
create or replace function public.resolver_empresa(p_empresa uuid, p_nivel text default 'ler') returns uuid
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid := coalesce(p_empresa, public.minha_empresa());
  v_ok boolean;
begin
  if v is null then
    raise exception 'Informe a empresa' using errcode = '22023';
  end if;
  v_ok := case p_nivel
            when 'ler' then public.pode_ler(v)
            when 'operar' then public.pode_operar(v)
            when 'administrar' then public.pode_administrar(v)
            else false
          end;
  if not v_ok then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if not exists (select 1 from public.empresas where id = v) then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;
  return v;
end $$;
comment on function public.resolver_empresa(uuid, text) is
  '[interno] Resolve p_empresa (ou a do usuário) e exige o nível ler/operar/administrar.';

-- ================================================================== dia de trabalho (§2.4)
create or replace function public.dia_de_trabalho(p_instante timestamptz, p_empresa uuid) returns date
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_fuso text;
  v_virada time;
begin
  select fuso, virada_dia into v_fuso, v_virada from public.empresas where id = p_empresa;
  if not found then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;
  return ((p_instante at time zone v_fuso) - v_virada)::date;
end $$;
comment on function public.dia_de_trabalho(timestamptz, uuid) is
  '[api] Dia de trabalho de um instante na empresa (fuso e virada_dia).';

create or replace function public.dia_de_trabalho_atual(p_empresa uuid default null) returns date
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select public.dia_de_trabalho(public.agora(), public.resolver_empresa(p_empresa, 'ler'))
$$;
comment on function public.dia_de_trabalho_atual(uuid) is '[api] Dia de trabalho atual da empresa.';

-- Instante de um horário de escala t no dia de trabalho D (§2.4).
create or replace function public.dia_de_trabalho_instante(p_data date, p_hora time, p_empresa uuid) returns timestamptz
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_fuso text;
  v_virada time;
begin
  select fuso, virada_dia into v_fuso, v_virada from public.empresas where id = p_empresa;
  if not found then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;
  return ((p_data + p_hora) + case when p_hora < v_virada then interval '1 day' else interval '0' end) at time zone v_fuso;
end $$;
comment on function public.dia_de_trabalho_instante(date, time, uuid) is
  '[api] Instante de um horário de escala no dia de trabalho (horário antes da virada = dia seguinte).';

-- ================================================================= gatilhos de empresas
create or replace function public.empresas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.nome := btrim(new.nome);
  new.cnpj := nullif(regexp_replace(coalesce(new.cnpj, ''), '[^0-9]', '', 'g'), '');
  new.uf := nullif(upper(btrim(coalesce(new.uf, ''))), '');
  new.telefone := nullif(btrim(coalesce(new.telefone, '')), '');
  new.cidade := nullif(btrim(coalesce(new.cidade, '')), '');
  if not exists (select 1 from pg_timezone_names where name = new.fuso) then
    raise exception 'Fuso horário inválido' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.criado_em := old.criado_em;
    -- Só o master (ou o sistema) muda "ativa"; para os demais o valor antigo é mantido.
    if new.ativa is distinct from old.ativa and not (public.eh_master() or public.eh_sistema()) then
      new.ativa := old.ativa;
    end if;
  end if;
  return new;
end $$;
comment on function public.empresas_antes_gravar() is '[interno] Gatilho: normaliza e protege empresas.';

drop trigger if exists empresas_antes_gravar on public.empresas;
create trigger empresas_antes_gravar before insert or update on public.empresas
  for each row execute function public.empresas_antes_gravar();
drop trigger if exists empresas_tocar on public.empresas;
create trigger empresas_tocar before update on public.empresas
  for each row execute function public.tocar_atualizado_em();

-- ======================================================================== RLS
alter table public.empresas enable row level security;
alter table public.perfis enable row level security;
alter table public.configuracao enable row level security;

drop policy if exists empresas_ler on public.empresas;
create policy empresas_ler on public.empresas for select to authenticated
  using ((select public.eh_master()) or id = (select public.empresa_leitura()));
drop policy if exists empresas_inserir on public.empresas;
create policy empresas_inserir on public.empresas for insert to authenticated
  with check ((select public.eh_master()));
drop policy if exists empresas_alterar on public.empresas;
create policy empresas_alterar on public.empresas for update to authenticated
  using ((select public.eh_master()) or id = (select public.empresa_administracao()))
  with check ((select public.eh_master()) or id = (select public.empresa_administracao()));
drop policy if exists empresas_excluir on public.empresas;
create policy empresas_excluir on public.empresas for delete to authenticated
  using ((select public.eh_master()));

drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (id = (select auth.uid()) or (select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

drop policy if exists configuracao_ler on public.configuracao;
create policy configuracao_ler on public.configuracao for select to authenticated
  using ((select public.eh_master()));

-- ================================================================ gatilho em auth.users (§10.1)
create or replace function public.auth_usuario_criado() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_email text := lower(coalesce(new.email, ''));
  v_nome text;
  v_papel text := 'administrador';
  v_empresa uuid := null;
  v_master_email text;
begin
  v_nome := coalesce(nullif(btrim(v_meta ->> 'nome'), ''), nullif(btrim(v_meta ->> 'full_name'), ''),
                     nullif(btrim(v_meta ->> 'name'), ''), nullif(split_part(v_email, '@', 1), ''), 'Usuário');

  if coalesce(current_setting('app.criando_usuario', true), '') = '1' then
    -- Insert feito por admin_criar_usuario/master_criar_empresa: papel e empresa vêm dos metadados.
    v_papel := coalesce(nullif(v_meta ->> 'papel', ''), 'administrador');
    v_empresa := nullif(v_meta ->> 'empresa_id', '')::uuid;
    if v_papel = 'master' then
      v_empresa := null;
    end if;
  else
    select lower(btrim(master_email)) into v_master_email from public.configuracao where id = 1;
    if v_master_email is not null and v_master_email = v_email
       and not exists (select 1 from public.perfis where papel = 'master') then
      v_papel := 'master';
    end if;
  end if;

  insert into public.perfis (id, nome, email, papel, empresa_id)
  values (new.id, v_nome, v_email, v_papel, v_empresa)
  on conflict (id) do nothing;
  return new;
end $$;
comment on function public.auth_usuario_criado() is '[interno] Gatilho em auth.users: cria o perfil.';

create or replace function public.auth_usuario_alterado() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if new.email is distinct from old.email then
    update public.perfis set email = lower(coalesce(new.email, '')) where id = new.id;
  end if;
  return new;
end $$;
comment on function public.auth_usuario_alterado() is '[interno] Gatilho em auth.users: espelha o e-mail no perfil.';

drop trigger if exists mdg_usuario_criado on auth.users;
create trigger mdg_usuario_criado after insert on auth.users
  for each row execute function public.auth_usuario_criado();
drop trigger if exists mdg_usuario_alterado on auth.users;
create trigger mdg_usuario_alterado after update of email on auth.users
  for each row execute function public.auth_usuario_alterado();

-- ======================================================================= RPCs de usuários (§10.1)
create or replace function public.validar_email(p_email text) returns text
language plpgsql immutable
set search_path = public, extensions, pg_temp
as $$
declare
  v text := lower(btrim(coalesce(p_email, '')));
begin
  if v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido' using errcode = '22023';
  end if;
  return v;
end $$;
comment on function public.validar_email(text) is '[interno] Normaliza e valida e-mail.';

create or replace function public.admin_criar_usuario(
  p_email text, p_senha text, p_nome text, p_papel text, p_empresa_id uuid, p_funcionario_id uuid default null
) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_email text := public.validar_email(p_email);
  v_nome text := btrim(coalesce(p_nome, ''));
  v_id uuid := gen_random_uuid();
  v_empresa uuid := p_empresa_id;
  v_func_empresa uuid;
begin
  if v_nome = '' then
    raise exception 'Informe o nome' using errcode = '22023';
  end if;
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'A senha deve ter pelo menos 6 caracteres' using errcode = '22023';
  end if;
  if p_papel is null or p_papel not in ('master', 'administrador', 'gerente', 'leitura') then
    raise exception 'Papel inválido' using errcode = '22023';
  end if;

  if p_papel = 'master' then
    if not public.sem_jwt() then
      raise exception 'Sem permissão' using errcode = '42501';
    end if;
    v_empresa := null;
  else
    if v_empresa is null then
      raise exception 'Informe a empresa' using errcode = '22023';
    end if;
    if not public.pode_administrar(v_empresa) then
      raise exception 'Sem permissão' using errcode = '42501';
    end if;
    if not exists (select 1 from public.empresas where id = v_empresa) then
      raise exception 'Empresa não encontrada' using errcode = 'P0002';
    end if;
  end if;

  if p_funcionario_id is not null then
    execute 'select empresa_id from public.funcionarios where id = $1' into v_func_empresa using p_funcionario_id;
    if v_func_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
    if v_func_empresa is distinct from v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'E-mail já cadastrado' using errcode = '23505';
  end if;

  perform set_config('app.criando_usuario', '1', true);
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, reauthentication_token, phone_change, phone_change_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_senha, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nome', v_nome, 'papel', p_papel, 'empresa_id', v_empresa),
    now(), now(), '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_id::text, v_id,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
          'email', now(), now(), now());
  perform set_config('app.criando_usuario', '', true);

  -- Garante papel/empresa/nome mesmo se o perfil já existia por algum motivo.
  update public.perfis set nome = v_nome, papel = p_papel, empresa_id = v_empresa, email = v_email, ativo = true
   where id = v_id;
  if p_funcionario_id is not null then
    execute 'update public.perfis set funcionario_id = $1 where id = $2' using p_funcionario_id, v_id;
  end if;
  return v_id;
end $$;
comment on function public.admin_criar_usuario(text, text, text, text, uuid, uuid) is
  '[api] Cria usuário (auth.users + identities + perfil). A na própria empresa; M em qualquer; master só pelo SQL Editor.';

-- Checagem comum: o chamador pode gerenciar o usuário alvo? Devolve o perfil do alvo.
create or replace function public.usuario_gerenciavel(p_usuario uuid) returns public.perfis
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.perfis;
begin
  select * into v from public.perfis where id = p_usuario;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;
  if public.eh_master() or public.sem_jwt() then
    return v;
  end if;
  if v.papel = 'master' or v.empresa_id is null or not public.pode_administrar(v.empresa_id) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return v;
end $$;
comment on function public.usuario_gerenciavel(uuid) is '[interno] Exige permissão sobre o usuário alvo.';

create or replace function public.admin_atualizar_usuario(
  p_usuario uuid, p_nome text, p_papel text, p_ativo boolean, p_funcionario_id uuid default null
) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.perfis := public.usuario_gerenciavel(p_usuario);
  v_nome text := btrim(coalesce(p_nome, ''));
  v_func_empresa uuid;
begin
  if v_nome = '' then
    raise exception 'Informe o nome' using errcode = '22023';
  end if;
  if p_papel is null or p_papel not in ('master', 'administrador', 'gerente', 'leitura')
     or (p_papel = 'master' and v.papel <> 'master')        -- não promove a master
     or (p_papel <> 'master' and v.papel = 'master' and v.empresa_id is null and not public.sem_jwt()) then
    raise exception 'Papel inválido' using errcode = '22023';
  end if;
  if p_usuario = auth.uid() and (p_papel is distinct from v.papel or coalesce(p_ativo, v.ativo) is distinct from v.ativo) then
    raise exception 'Você não pode alterar o próprio papel ou situação' using errcode = '42501';
  end if;
  if p_funcionario_id is not null then
    execute 'select empresa_id from public.funcionarios where id = $1' into v_func_empresa using p_funcionario_id;
    if v_func_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
    if v_func_empresa is distinct from v.empresa_id then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  end if;

  update public.perfis
     set nome = v_nome, papel = p_papel, ativo = coalesce(p_ativo, ativo)
   where id = p_usuario;
  execute 'update public.perfis set funcionario_id = $1 where id = $2' using p_funcionario_id, p_usuario;
end $$;
comment on function public.admin_atualizar_usuario(uuid, text, text, boolean, uuid) is
  '[api] Atualiza nome/papel/situação/funcionário de um usuário (A da empresa, M).';

create or replace function public.admin_redefinir_senha(p_usuario uuid, p_senha text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform public.usuario_gerenciavel(p_usuario);
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'A senha deve ter pelo menos 6 caracteres' using errcode = '22023';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')), updated_at = now()
   where id = p_usuario;
end $$;
comment on function public.admin_redefinir_senha(uuid, text) is '[api] Redefine a senha de um usuário (A da empresa, M).';

create or replace function public.admin_excluir_usuario(p_usuario uuid) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.perfis;
begin
  if p_usuario = auth.uid() then
    raise exception 'Você não pode excluir a si mesmo' using errcode = '42501';
  end if;
  v := public.usuario_gerenciavel(p_usuario);
  if v.papel = 'master' and not public.sem_jwt() then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  delete from auth.users where id = p_usuario;
end $$;
comment on function public.admin_excluir_usuario(uuid) is '[api] Exclui um usuário (A da empresa, M; nunca master nem a si).';

create or replace function public.atualizar_meu_perfil(p_nome text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
begin
  if auth.uid() is null or not exists (select 1 from public.perfis where id = auth.uid()) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if v_nome = '' then
    raise exception 'Informe o nome' using errcode = '22023';
  end if;
  update public.perfis set nome = v_nome where id = auth.uid();
end $$;
comment on function public.atualizar_meu_perfil(text) is '[api] Altera o nome do próprio perfil.';

create or replace function public.criar_minha_empresa(p_nome text, p_cnpj text default null) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.perfis;
  v_id uuid;
begin
  select * into v from public.perfis where id = auth.uid();
  if not found or not v.ativo or v.papel = 'master' then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if v.empresa_id is not null then
    raise exception 'Você já pertence a uma empresa' using errcode = '22023';
  end if;
  if not coalesce((select cadastro_aberto from public.configuracao where id = 1), true) then
    raise exception 'Cadastro de novas empresas desativado' using errcode = '42501';
  end if;
  if btrim(coalesce(p_nome, '')) = '' then
    raise exception 'Informe o nome' using errcode = '22023';
  end if;
  insert into public.empresas (nome, cnpj) values (p_nome, p_cnpj) returning id into v_id;
  update public.perfis set empresa_id = v_id, papel = 'administrador' where id = v.id;
  return v_id;
end $$;
comment on function public.criar_minha_empresa(text, text) is
  '[api] Cadastro aberto: cria a empresa e torna o usuário administrador dela.';

create or replace function public.master_criar_empresa(
  p_nome text, p_cnpj text, p_admin_email text, p_admin_senha text, p_admin_nome text
) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  if not (public.eh_master() or public.sem_jwt()) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if btrim(coalesce(p_nome, '')) = '' then
    raise exception 'Informe o nome' using errcode = '22023';
  end if;
  insert into public.empresas (nome, cnpj) values (p_nome, p_cnpj) returning id into v_id;
  perform public.admin_criar_usuario(p_admin_email, p_admin_senha, p_admin_nome, 'administrador', v_id, null);
  return v_id;
end $$;
comment on function public.master_criar_empresa(text, text, text, text, text) is
  '[api] Master: cria empresa + primeiro administrador numa transação.';

create or replace function public.tornar_master(p_email text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;
  update public.perfis set papel = 'master', empresa_id = null, ativo = true where id = v_id;
  update public.configuracao set master_email = lower(btrim(p_email)) where id = 1 and master_email is null;
end $$;
comment on function public.tornar_master(text) is '[interno] Torna um usuário existente master (só pelo SQL Editor).';

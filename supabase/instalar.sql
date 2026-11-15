-- =====================================================================================================
-- Meu Dia de Gerente — instalação/atualização completa do banco (Supabase).
-- ARQUIVO GERADO por ferramentas/gerar-instalar.sh a partir de supabase/migrations/. NÃO EDITE À MÃO.
--
-- Como usar: Supabase → SQL Editor → cole este arquivo inteiro → Run.
-- É idempotente: rodar de novo atualiza funções/políticas sem perder dados.
-- Depois: supabase/README.md (criar o master, ligar o Google, carga de demonstração opcional).
-- =====================================================================================================

begin;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000100_base.sql
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
  select coalesce(e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_leitura()), false)
$$;
comment on function public.pode_ler(uuid) is '[politica] Master, sistema ou L G A da empresa.';

create or replace function public.pode_operar(e uuid) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_operacao()), false)
$$;
comment on function public.pode_operar(uuid) is '[politica] Master, sistema ou G A da empresa.';

create or replace function public.pode_administrar(e uuid) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(e is not null and (public.eh_master() or public.eh_sistema() or e = public.empresa_administracao()), false)
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
  if v_ok is not true then
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
  '[interno] Dia de trabalho de um instante na empresa (fuso e virada_dia). Revisão 2: não exposta à API (revelava fuso/virada de outra empresa pelo id); o front usa dia_de_trabalho_atual.';

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
  '[interno] Instante de um horário de escala no dia de trabalho (horário antes da virada = dia seguinte). Revisão 2: não exposta à API.';

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

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000100_base.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000110_cadastros.sql
-- =====================================================================================================
-- 20261006000110_cadastros.sql  (backend-1)
-- funcionarios, funcionario_pontos, jornadas, jornada_dias, funcionario_jornadas, perfis.funcionario_id,
-- meu_funcionario(), pontos_vigentes(), gatilhos e RLS. Idempotente.
-- =====================================================================================================

-- =================================================================================== funcionarios
create table if not exists public.funcionarios (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas (id) on delete cascade,
  nome                 text not null check (btrim(nome) <> ''),
  apelido              text,
  matricula            text,
  cpf                  text check (cpf is null or cpf ~ '^[0-9]{11}$'),
  pis                  text check (pis is null or pis ~ '^[0-9]{11}$'),
  cargo                text,
  telefone             text,
  email                text,
  zig_employee_name    text,
  pontos_comissao      numeric(8,2) not null default 0 check (pontos_comissao >= 0),
  participa_comissao   boolean not null default true,
  data_admissao        date,
  data_desligamento    date,
  ativo                boolean not null default true,
  observacoes          text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  constraint funcionarios_datas check (data_desligamento is null or data_admissao is null
                                       or data_desligamento >= data_admissao)
);
create index if not exists funcionarios_empresa_idx on public.funcionarios (empresa_id);
create unique index if not exists funcionarios_matricula_uk on public.funcionarios (empresa_id, matricula)
  where matricula is not null;
create unique index if not exists funcionarios_cpf_uk on public.funcionarios (empresa_id, cpf) where cpf is not null;
create unique index if not exists funcionarios_pis_uk on public.funcionarios (empresa_id, pis) where pis is not null;
create unique index if not exists funcionarios_zig_uk on public.funcionarios (empresa_id, lower(btrim(zig_employee_name)))
  where zig_employee_name is not null;
comment on table public.funcionarios is '[api:crud] Funcionários da empresa.';

-- ============================================================================ funcionario_pontos
create table if not exists public.funcionario_pontos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  pontos          numeric(8,2) not null check (pontos >= 0),
  vigente_desde   date not null,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, vigente_desde)
);
create index if not exists funcionario_pontos_empresa_idx on public.funcionario_pontos (empresa_id);
create index if not exists funcionario_pontos_criado_por_idx on public.funcionario_pontos (criado_por);
comment on table public.funcionario_pontos is '[api:leitura] Histórico de pontos de comissão (escrito só pelo gatilho).';

-- ====================================================================================== jornadas
create table if not exists public.jornadas (
  id                         uuid primary key default gen_random_uuid(),
  empresa_id                 uuid not null references public.empresas (id) on delete cascade,
  nome                       text not null check (btrim(nome) <> ''),
  tolerancia_batida_minutos  int not null default 5 check (tolerancia_batida_minutos between 0 and 60),
  tolerancia_diaria_minutos  int not null default 10 check (tolerancia_diaria_minutos between 0 and 120),
  ativa                      boolean not null default true,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  unique (empresa_id, nome)
);
comment on table public.jornadas is '[api:crud] Jornadas/escalas semanais.';

create table if not exists public.jornada_dias (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas (id) on delete cascade,
  jornada_id          uuid not null references public.jornadas (id) on delete cascade,
  dia_semana          smallint not null check (dia_semana between 0 and 6),
  entrada             time not null,
  saida_intervalo     time,
  volta_intervalo     time,
  saida               time not null,
  batidas_esperadas   smallint generated always as (case when saida_intervalo is null then 2 else 4 end) stored,
  minutos_previstos   int generated always as (
      (((extract(epoch from (saida - entrada)) / 60)::int + 1440) % 1440)
    - coalesce((((extract(epoch from (volta_intervalo - saida_intervalo)) / 60)::int + 1440) % 1440), 0)
  ) stored,
  unique (jornada_id, dia_semana),
  constraint jornada_dias_intervalo check ((saida_intervalo is null) = (volta_intervalo is null))
);
create index if not exists jornada_dias_empresa_idx on public.jornada_dias (empresa_id);
comment on table public.jornada_dias is '[api:crud] Horários de cada dia da semana da jornada (sem linha = folga).';

create table if not exists public.funcionario_jornadas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  jornada_id      uuid not null references public.jornadas (id) on delete restrict,
  vigente_desde   date not null,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, vigente_desde)
);
create index if not exists funcionario_jornadas_empresa_idx on public.funcionario_jornadas (empresa_id);
create index if not exists funcionario_jornadas_jornada_idx on public.funcionario_jornadas (jornada_id);
comment on table public.funcionario_jornadas is '[api:crud] Jornada vigente de cada funcionário a partir de uma data.';

-- ===================================================================== perfis.funcionario_id
alter table public.perfis add column if not exists
  funcionario_id uuid references public.funcionarios (id) on delete set null;
create index if not exists perfis_funcionario_idx on public.perfis (funcionario_id);

create or replace function public.meu_funcionario() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.funcionario_id from public.perfis p where p.id = auth.uid()
$$;
comment on function public.meu_funcionario() is '[politica] Funcionário ligado ao perfil do usuário atual.';

-- Perfil do usuário atual (ou null) — para colunas criado_por/feito_por.
create or replace function public.meu_perfil_id() returns uuid
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p.id from public.perfis p where p.id = auth.uid()
$$;
comment on function public.meu_perfil_id() is '[politica] Id do perfil do usuário atual, se existir.';

-- ========================================================================= gatilhos funcionarios
create or replace function public.funcionarios_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.empresa_id := old.empresa_id;          -- imutável
    new.criado_em := old.criado_em;
  end if;
  new.nome := btrim(new.nome);
  new.cpf := nullif(regexp_replace(coalesce(new.cpf, ''), '[^0-9]', '', 'g'), '');
  new.pis := nullif(regexp_replace(coalesce(new.pis, ''), '[^0-9]', '', 'g'), '');
  new.zig_employee_name := nullif(btrim(coalesce(new.zig_employee_name, '')), '');
  new.matricula := nullif(btrim(coalesce(new.matricula, '')), '');
  new.apelido := nullif(btrim(coalesce(new.apelido, '')), '');
  if tg_op = 'INSERT' and new.matricula is null then
    perform pg_advisory_xact_lock(hashtextextended('mdg:matricula:' || new.empresa_id::text, 0));
    select (coalesce(max(matricula::numeric), 0) + 1)::text into new.matricula
      from public.funcionarios
     where empresa_id = new.empresa_id and matricula ~ '^[0-9]{1,18}$';
  end if;
  return new;
end $$;
comment on function public.funcionarios_antes_gravar() is
  '[interno] Gatilho: normaliza cpf/pis/nomes, gera matrícula, empresa imutável.';

drop trigger if exists funcionarios_antes_gravar on public.funcionarios;
create trigger funcionarios_antes_gravar before insert or update on public.funcionarios
  for each row execute function public.funcionarios_antes_gravar();
drop trigger if exists funcionarios_tocar on public.funcionarios;
create trigger funcionarios_tocar before update on public.funcionarios
  for each row execute function public.tocar_atualizado_em();

create or replace function public.funcionarios_registrar_pontos() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_desde date;
begin
  if tg_op = 'INSERT' then
    v_desde := coalesce(new.data_admissao, public.dia_de_trabalho(public.agora(), new.empresa_id));
  elsif new.pontos_comissao is distinct from old.pontos_comissao then
    v_desde := public.dia_de_trabalho(public.agora(), new.empresa_id);
  else
    return null;
  end if;
  insert into public.funcionario_pontos (empresa_id, funcionario_id, pontos, vigente_desde, criado_por)
  values (new.empresa_id, new.id, new.pontos_comissao, v_desde, public.meu_perfil_id())
  on conflict (funcionario_id, vigente_desde)
  do update set pontos = excluded.pontos, criado_por = excluded.criado_por, criado_em = now();
  return null;
end $$;
comment on function public.funcionarios_registrar_pontos() is '[interno] Gatilho: histórico de pontos de comissão.';

drop trigger if exists funcionarios_registrar_pontos on public.funcionarios;
create trigger funcionarios_registrar_pontos after insert or update of pontos_comissao on public.funcionarios
  for each row execute function public.funcionarios_registrar_pontos();

-- ======================================================================= gatilhos de jornadas
create or replace function public.jornadas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.jornadas_antes_gravar() is '[interno] Gatilho: jornada com empresa imutável.';

drop trigger if exists jornadas_antes_gravar on public.jornadas;
create trigger jornadas_antes_gravar before insert or update on public.jornadas
  for each row execute function public.jornadas_antes_gravar();
drop trigger if exists jornadas_tocar on public.jornadas;
create trigger jornadas_tocar before update on public.jornadas
  for each row execute function public.tocar_atualizado_em();

-- minutos de t contados a partir de "a" no relógio circular de 24 h
create or replace function public.minutos_desde(p_de time, p_ate time) returns int
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select (((extract(epoch from (p_ate - p_de)) / 60)::int + 1440) % 1440)
$$;
comment on function public.minutos_desde(time, time) is '[api] Minutos de p_de até p_ate no relógio circular de 24 h.';

create or replace function public.jornada_dias_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  m_si int; m_vi int; m_s int;
begin
  select empresa_id into new.empresa_id from public.jornadas where id = new.jornada_id;
  if new.empresa_id is null then
    raise exception 'Jornada não encontrada' using errcode = 'P0002';
  end if;
  m_s := public.minutos_desde(new.entrada, new.saida);
  if new.saida_intervalo is not null and new.volta_intervalo is not null then
    m_si := public.minutos_desde(new.entrada, new.saida_intervalo);
    m_vi := public.minutos_desde(new.entrada, new.volta_intervalo);
    if not (m_si > 0 and m_vi > m_si and m_s > m_vi) then
      raise exception 'Horários da jornada fora de ordem' using errcode = '22023';
    end if;
  elsif m_s = 0 then
    raise exception 'Horários da jornada fora de ordem' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.jornada_dias_antes_gravar() is
  '[interno] Gatilho: empresa da jornada e ordem circular dos horários.';

drop trigger if exists jornada_dias_antes_gravar on public.jornada_dias;
create trigger jornada_dias_antes_gravar before insert or update on public.jornada_dias
  for each row execute function public.jornada_dias_antes_gravar();

create or replace function public.funcionario_jornadas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_emp_jornada uuid;
begin
  select empresa_id into new.empresa_id from public.funcionarios where id = new.funcionario_id;
  if new.empresa_id is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  select empresa_id into v_emp_jornada from public.jornadas where id = new.jornada_id;
  if v_emp_jornada is distinct from new.empresa_id then
    raise exception 'Jornada de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.funcionario_jornadas_antes_gravar() is
  '[interno] Gatilho: empresa do funcionário; jornada da mesma empresa.';

drop trigger if exists funcionario_jornadas_antes_gravar on public.funcionario_jornadas;
create trigger funcionario_jornadas_antes_gravar before insert or update on public.funcionario_jornadas
  for each row execute function public.funcionario_jornadas_antes_gravar();

-- ================================================================================ pontos_vigentes
create or replace function public.pontos_vigentes(p_funcionario uuid, p_data date) returns numeric
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
  v_atual numeric;
  v numeric;
begin
  select empresa_id, pontos_comissao into v_empresa, v_atual from public.funcionarios where id = p_funcionario;
  if v_empresa is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  if not public.pode_operar(v_empresa) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  select pontos into v from public.funcionario_pontos
   where funcionario_id = p_funcionario and vigente_desde <= p_data
   order by vigente_desde desc limit 1;
  if v is null then
    select pontos into v from public.funcionario_pontos
     where funcionario_id = p_funcionario
     order by vigente_desde asc limit 1;
  end if;
  return coalesce(v, v_atual);
end $$;
comment on function public.pontos_vigentes(uuid, date) is '[api] Pontos de comissão vigentes do funcionário na data (G A M).';

-- =========================================================================================== RLS
alter table public.funcionarios enable row level security;
alter table public.funcionario_pontos enable row level security;
alter table public.jornadas enable row level security;
alter table public.jornada_dias enable row level security;
alter table public.funcionario_jornadas enable row level security;

drop policy if exists funcionarios_ler on public.funcionarios;
create policy funcionarios_ler on public.funcionarios for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists funcionarios_inserir on public.funcionarios;
create policy funcionarios_inserir on public.funcionarios for insert to authenticated
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists funcionarios_alterar on public.funcionarios;
create policy funcionarios_alterar on public.funcionarios for update to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists funcionarios_excluir on public.funcionarios;
create policy funcionarios_excluir on public.funcionarios for delete to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));

drop policy if exists funcionario_pontos_ler on public.funcionario_pontos;
create policy funcionario_pontos_ler on public.funcionario_pontos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

do $$
declare
  t text;
begin
  foreach t in array array['jornadas', 'jornada_dias', 'funcionario_jornadas'] loop
    execute format('drop policy if exists %1$s_ler on public.%1$s', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()))', t);
    execute format('drop policy if exists %1$s_inserir on public.%1$s', t);
    execute format('create policy %1$s_inserir on public.%1$s for insert to authenticated
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_alterar on public.%1$s', t);
    execute format('create policy %1$s_alterar on public.%1$s for update to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
  end loop;
end $$;

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000110_cadastros.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000120_integracoes_sync.sql
-- =====================================================================================================
-- 20261006000120_integracoes_sync.sql  (backend-1)
-- integracoes, integracoes_segredos, controlid_usuarios, sync_solicitacoes, sync_execucoes,
-- RPCs de integração / sincronização / usuários Control iD, RLS. Idempotente.
-- =====================================================================================================

-- ==================================================================================== integracoes
create table if not exists public.integracoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas (id) on delete cascade,
  tipo                 text not null check (tipo in ('zig', 'controlid_acesso', 'controlid_rep', 'tagme')),
  nome                 text not null check (btrim(nome) <> ''),
  ativa                boolean not null default true,
  parametros           jsonb not null default '{}'::jsonb,
  intervalo_minutos    int not null default 60 check (intervalo_minutos >= 15),
  cursor               jsonb not null default '{}'::jsonb,
  ultimo_sucesso_em    timestamptz,
  ultima_execucao_em   timestamptz,
  ultimo_status        text check (ultimo_status in ('sucesso', 'parcial', 'erro')),
  ultimo_erro          text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
create index if not exists integracoes_empresa_idx on public.integracoes (empresa_id);
create unique index if not exists integracoes_zig_uk on public.integracoes (empresa_id) where tipo = 'zig';
comment on table public.integracoes is '[api:crud] Integrações (Zig, Control iD acesso/REP, Tagme). Segredos ficam em integracoes_segredos.';
-- (adendo extras/ocorrências/reservas) bancos já instalados: check do tipo com 'tagme'.
alter table public.integracoes drop constraint if exists integracoes_tipo_check;
alter table public.integracoes add constraint integracoes_tipo_check
  check (tipo in ('zig', 'controlid_acesso', 'controlid_rep', 'tagme'));

create table if not exists public.integracoes_segredos (
  integracao_id  uuid primary key references public.integracoes (id) on delete cascade,
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  segredos       jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now()
);
create index if not exists integracoes_segredos_empresa_idx on public.integracoes_segredos (empresa_id);
comment on table public.integracoes_segredos is '[api:nenhum] Segredos das integrações (token, url, login, senha). Só service_role.';

-- ============================================================================= controlid_usuarios
create table if not exists public.controlid_usuarios (
  id                       uuid primary key default gen_random_uuid(),
  empresa_id               uuid not null references public.empresas (id) on delete cascade,
  integracao_id            uuid not null references public.integracoes (id) on delete cascade,
  user_id_externo          text not null,
  registration             text,
  nome                     text,
  cpf                      text,
  pis                      text,
  funcionario_id           uuid references public.funcionarios (id) on delete set null,
  vinculo                  text check (vinculo in ('automatico', 'manual')),
  removido_no_equipamento  boolean not null default false,
  visto_em                 timestamptz not null default now(),
  criado_em                timestamptz not null default now(),
  unique (integracao_id, user_id_externo)
);
create index if not exists controlid_usuarios_empresa_idx on public.controlid_usuarios (empresa_id);
create index if not exists controlid_usuarios_funcionario_idx on public.controlid_usuarios (funcionario_id);
create unique index if not exists controlid_usuarios_func_uk on public.controlid_usuarios (integracao_id, funcionario_id)
  where funcionario_id is not null;
comment on table public.controlid_usuarios is '[api:leitura] Espelho dos usuários de cada equipamento Control iD.';

-- ============================================================================== sync_solicitacoes
create table if not exists public.sync_solicitacoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  integracao_id   uuid references public.integracoes (id) on delete cascade,
  escopo          text not null check (escopo in ('tudo', 'funcionarios', 'batidas', 'vendas', 'reservas',
                                                  'exportar_funcionarios', 'apurar_ponto', 'exportar_fechamento')),
  data_inicio     date,
  data_fim        date,
  parametros      jsonb not null default '{}'::jsonb,
  status          text not null default 'pendente'
                  check (status in ('pendente', 'em_andamento', 'concluida', 'erro', 'cancelada')),
  solicitado_por  uuid references public.perfis (id) on delete set null,
  solicitado_em   timestamptz not null default now(),
  pego_em         timestamptz,
  concluido_em    timestamptz,
  execucao_id     uuid,
  mensagem        text,
  constraint sync_solicitacoes_periodo check (data_fim is null or data_inicio is null or data_fim >= data_inicio)
);
create index if not exists sync_solicitacoes_empresa_idx on public.sync_solicitacoes (empresa_id, solicitado_em desc);
create index if not exists sync_solicitacoes_integracao_idx on public.sync_solicitacoes (integracao_id);
create index if not exists sync_solicitacoes_fila_idx on public.sync_solicitacoes (solicitado_em) where status = 'pendente';
create index if not exists sync_solicitacoes_solicitado_por_idx on public.sync_solicitacoes (solicitado_por);
comment on table public.sync_solicitacoes is '[api:leitura] Fila do "Sincronizar agora" (escrita por sync_solicitar).';
alter table public.sync_solicitacoes drop constraint if exists sync_solicitacoes_escopo_check;
alter table public.sync_solicitacoes add constraint sync_solicitacoes_escopo_check
  check (escopo in ('tudo', 'funcionarios', 'batidas', 'vendas', 'reservas',
                    'exportar_funcionarios', 'apurar_ponto', 'exportar_fechamento'));

-- ================================================================================= sync_execucoes
create table if not exists public.sync_execucoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid references public.empresas (id) on delete cascade,
  integracao_id        uuid references public.integracoes (id) on delete set null,
  solicitacao_id       uuid references public.sync_solicitacoes (id) on delete set null,
  tipo                 text not null check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                         'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                         'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento', 'tagme_importar')),
  gatilho              text not null check (gatilho in ('agendado', 'manual', 'webhook')),
  workflow             text not null,
  n8n_execution_id     text,
  status               text not null default 'executando' check (status in ('executando', 'sucesso', 'parcial', 'erro')),
  iniciado_em          timestamptz not null default now(),
  finalizado_em        timestamptz,
  periodo_inicio       date,
  periodo_fim          date,
  registros_lidos      int not null default 0,
  registros_gravados   int not null default 0,
  registros_ignorados  int not null default 0,
  tentativas           int not null default 1,
  erro                 text,
  detalhes             jsonb not null default '{}'::jsonb
);
create index if not exists sync_execucoes_empresa_idx on public.sync_execucoes (empresa_id, iniciado_em desc);
create index if not exists sync_execucoes_integracao_idx on public.sync_execucoes (integracao_id, iniciado_em desc);
create index if not exists sync_execucoes_solicitacao_idx on public.sync_execucoes (solicitacao_id);
comment on table public.sync_execucoes is '[api:leitura] Execuções dos workflows N8N (escritas pelo serviço).';
alter table public.sync_execucoes drop constraint if exists sync_execucoes_tipo_check;
alter table public.sync_execucoes add constraint sync_execucoes_tipo_check
  check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                  'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                  'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento', 'tagme_importar'));

-- ====================================================================================== gatilhos
-- Parâmetros padrão por tipo (§11.1); as chaves informadas prevalecem.
create or replace function public.integracao_parametros_padrao(p_tipo text) returns jsonb
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case p_tipo
    when 'zig' then '{"rede": "", "dias_retroativos": 2}'::jsonb
    when 'controlid_acesso' then
      '{"modelo": "iDFace", "dias_retroativos": 2, "eventos_validos": [7], "relogio_em_hora_local": true}'::jsonb
    when 'controlid_rep' then '{"modelo": "iDClass", "dias_retroativos": 2, "identificador": "cpf"}'::jsonb
    when 'tagme' then '{"url_base": "", "restaurante_id": "", "dias_retroativos": 1, "dias_a_frente": 7}'::jsonb
    else '{}'::jsonb
  end
$$;
comment on function public.integracao_parametros_padrao(text) is '[api] Parâmetros padrão de cada tipo de integração.';

-- Padrões do envio ao equipamento (adendo envio Control iD, A.1).
create or replace function public.integracao_envio_padrao(p_tipo text, p_modelo text) returns jsonb
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case when p_tipo in ('controlid_acesso', 'controlid_rep') then
    jsonb_build_object(
      'ativo', false,
      'foto', p_tipo = 'controlid_acesso' and coalesce(p_modelo, '') ilike '%idface%',
      'cartao', true,
      'senha', true,
      'horarios', p_tipo = 'controlid_acesso',
      'ao_desligar', 'remover')
  else null end
$$;
comment on function public.integracao_envio_padrao(text, text) is '[api] Padrões de parametros.envio por tipo/modelo.';

create or replace function public.integracoes_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.nome := btrim(new.nome);
  if jsonb_typeof(new.parametros) is distinct from 'object' then
    new.parametros := '{}'::jsonb;
  end if;
  new.parametros := public.integracao_parametros_padrao(new.tipo) || new.parametros;
  if new.tipo in ('controlid_acesso', 'controlid_rep') then
    new.parametros := jsonb_set(new.parametros, '{envio}',
      public.integracao_envio_padrao(new.tipo, new.parametros ->> 'modelo')
      || case when jsonb_typeof(new.parametros -> 'envio') = 'object' then new.parametros -> 'envio' else '{}'::jsonb end);
  end if;
  if tg_op = 'INSERT' then
    if not public.eh_sistema() then
      new.cursor := '{}'::jsonb;
      new.ultimo_sucesso_em := null;
      new.ultima_execucao_em := null;
      new.ultimo_status := null;
      new.ultimo_erro := null;
    end if;
  else
    new.id := old.id;
    new.tipo := old.tipo;
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
    if not public.eh_sistema() then
      new.cursor := old.cursor;
      new.ultimo_sucesso_em := old.ultimo_sucesso_em;
      new.ultima_execucao_em := old.ultima_execucao_em;
      new.ultimo_status := old.ultimo_status;
      new.ultimo_erro := old.ultimo_erro;
    end if;
  end if;
  return new;
end $$;
comment on function public.integracoes_antes_gravar() is
  '[interno] Gatilho: tipo/empresa imutáveis; cursor e ultimo_* só pelo serviço; parâmetros padrão.';

drop trigger if exists integracoes_antes_gravar on public.integracoes;
create trigger integracoes_antes_gravar before insert or update on public.integracoes
  for each row execute function public.integracoes_antes_gravar();
drop trigger if exists integracoes_tocar on public.integracoes;
create trigger integracoes_tocar before update on public.integracoes
  for each row execute function public.tocar_atualizado_em();

-- empresa_id dos filhos de integracoes vem do pai.
create or replace function public.empresa_da_integracao() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid;
begin
  if new.integracao_id is not null then
    select empresa_id into v from public.integracoes where id = new.integracao_id;
    if v is null then
      raise exception 'Integração não encontrada' using errcode = 'P0002';
    end if;
    new.empresa_id := v;
  end if;
  return new;
end $$;
comment on function public.empresa_da_integracao() is '[interno] Gatilho: empresa_id = empresa da integração.';

drop trigger if exists integracoes_segredos_empresa on public.integracoes_segredos;
create trigger integracoes_segredos_empresa before insert or update on public.integracoes_segredos
  for each row execute function public.empresa_da_integracao();
drop trigger if exists integracoes_segredos_tocar on public.integracoes_segredos;
create trigger integracoes_segredos_tocar before update on public.integracoes_segredos
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists controlid_usuarios_empresa on public.controlid_usuarios;
create trigger controlid_usuarios_empresa before insert or update on public.controlid_usuarios
  for each row execute function public.empresa_da_integracao();
drop trigger if exists sync_solicitacoes_empresa on public.sync_solicitacoes;
create trigger sync_solicitacoes_empresa before insert on public.sync_solicitacoes
  for each row execute function public.empresa_da_integracao();
drop trigger if exists sync_execucoes_empresa on public.sync_execucoes;
create trigger sync_execucoes_empresa before insert on public.sync_execucoes
  for each row execute function public.empresa_da_integracao();

-- =========================================================================================== RLS
alter table public.integracoes enable row level security;
alter table public.integracoes_segredos enable row level security;   -- sem políticas: ninguém além do serviço
alter table public.controlid_usuarios enable row level security;
alter table public.sync_solicitacoes enable row level security;
alter table public.sync_execucoes enable row level security;

drop policy if exists integracoes_ler on public.integracoes;
create policy integracoes_ler on public.integracoes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists integracoes_inserir on public.integracoes;
create policy integracoes_inserir on public.integracoes for insert to authenticated
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));
drop policy if exists integracoes_alterar on public.integracoes;
create policy integracoes_alterar on public.integracoes for update to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()))
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));
drop policy if exists integracoes_excluir on public.integracoes;
create policy integracoes_excluir on public.integracoes for delete to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));

drop policy if exists controlid_usuarios_ler on public.controlid_usuarios;
create policy controlid_usuarios_ler on public.controlid_usuarios for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop policy if exists sync_solicitacoes_ler on public.sync_solicitacoes;
create policy sync_solicitacoes_ler on public.sync_solicitacoes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop policy if exists sync_execucoes_ler on public.sync_execucoes;
create policy sync_execucoes_ler on public.sync_execucoes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

-- ============================================================================ auxiliares internas
-- Integração existente, ativa (opcional) e de um dos tipos (opcional). Erros do §11.2.
create or replace function public.integracao_validar(p_integracao uuid, p_tipos text[] default null, p_exigir_ativa boolean default true)
returns public.integracoes
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.integracoes;
begin
  select * into v from public.integracoes where id = p_integracao;
  if not found then
    raise exception 'Integração não encontrada' using errcode = 'P0002';
  end if;
  if p_exigir_ativa and not v.ativa then
    raise exception 'Integração inativa' using errcode = '22023';
  end if;
  if p_tipos is not null and not (v.tipo = any (p_tipos)) then
    raise exception 'Tipo de integração incompatível' using errcode = '22023';
  end if;
  return v;
end $$;
comment on function public.integracao_validar(uuid, text[], boolean) is
  '[interno] Valida existência, situação e tipo de uma integração.';

-- ================================================================ RPCs de cadastro / integração
create or replace function public.funcionario_vincular_controlid(p_controlid_usuario uuid, p_funcionario uuid) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.controlid_usuarios;
  v_emp_func uuid;
begin
  select * into v from public.controlid_usuarios where id = p_controlid_usuario;
  if not found then
    raise exception 'Usuário do equipamento não encontrado' using errcode = 'P0002';
  end if;
  if not public.pode_operar(v.empresa_id) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_funcionario is null then
    -- Desvínculo manual: fica 'manual' sem funcionário para a importação não religar sozinha.
    update public.controlid_usuarios set funcionario_id = null, vinculo = 'manual' where id = v.id;
    return;
  end if;
  select empresa_id into v_emp_func from public.funcionarios where id = p_funcionario;
  if v_emp_func is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  if v_emp_func <> v.empresa_id then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  if v.funcionario_id is not distinct from p_funcionario then
    update public.controlid_usuarios set vinculo = 'manual' where id = v.id;
    return;
  end if;
  update public.controlid_usuarios set funcionario_id = null, vinculo = null
   where integracao_id = v.integracao_id and funcionario_id = p_funcionario and id <> v.id;
  update public.controlid_usuarios set funcionario_id = p_funcionario, vinculo = 'manual' where id = v.id;
end $$;
comment on function public.funcionario_vincular_controlid(uuid, uuid) is
  '[api] Vincula (ou desvincula, p_funcionario null) um usuário do equipamento a um funcionário (G A M).';

create or replace function public.integracao_chaves_segredo(p_tipo text) returns text[]
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case p_tipo
    when 'zig' then array['token']
    when 'controlid_acesso' then array['url', 'login', 'senha']
    when 'controlid_rep' then array['url', 'login', 'senha']
    when 'tagme' then array['token', 'cliente_id', 'cliente_segredo']
    else array[]::text[]
  end
$$;
comment on function public.integracao_chaves_segredo(text) is '[api] Chaves de segredo permitidas por tipo de integração.';

create or replace function public.integracao_definir_segredos(p_integracao uuid, p_segredos jsonb) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.integracoes;
  v_atual jsonb;
  r record;
  v_permitidas text[];
begin
  select * into v from public.integracoes where id = p_integracao;
  if not found then
    raise exception 'Integração não encontrada' using errcode = 'P0002';
  end if;
  if not public.pode_administrar(v.empresa_id) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_segredos is null or jsonb_typeof(p_segredos) <> 'object' then
    raise exception 'Segredo inválido para este tipo de integração' using errcode = '22023';
  end if;
  v_permitidas := public.integracao_chaves_segredo(v.tipo);
  select segredos into v_atual from public.integracoes_segredos where integracao_id = v.id;
  v_atual := coalesce(v_atual, '{}'::jsonb);
  for r in select key, value from jsonb_each(p_segredos) loop
    if not (r.key = any (v_permitidas)) or jsonb_typeof(r.value) not in ('string', 'null') then
      raise exception 'Segredo inválido para este tipo de integração' using errcode = '22023';
    end if;
    if jsonb_typeof(r.value) = 'null' or btrim(r.value #>> '{}') = '' then
      v_atual := v_atual - r.key;
    else
      v_atual := v_atual || jsonb_build_object(r.key, r.value #>> '{}');
    end if;
  end loop;
  insert into public.integracoes_segredos (integracao_id, empresa_id, segredos)
  values (v.id, v.empresa_id, v_atual)
  on conflict (integracao_id) do update set segredos = excluded.segredos;
end $$;
comment on function public.integracao_definir_segredos(uuid, jsonb) is
  '[api] Grava (merge) os segredos de uma integração; null/'''' remove a chave (A M).';

create or replace function public.integracao_segredos_preenchidos(p_integracao uuid) returns text[]
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
  v text[];
begin
  select empresa_id into v_empresa from public.integracoes where id = p_integracao;
  if v_empresa is null then
    raise exception 'Integração não encontrada' using errcode = 'P0002';
  end if;
  if not public.pode_operar(v_empresa) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  select coalesce(array_agg(k order by k), array[]::text[]) into v
    from public.integracoes_segredos s, jsonb_object_keys(s.segredos) k
   where s.integracao_id = p_integracao;
  return coalesce(v, array[]::text[]);
end $$;
comment on function public.integracao_segredos_preenchidos(uuid) is
  '[api] Nomes das chaves de segredo preenchidas (nunca os valores) (G A M).';

-- ======================================================================== sincronizar agora
create or replace function public.sync_escopo_compativel(p_escopo text, p_tipo text) returns boolean
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case p_escopo
    when 'tudo' then p_tipo in ('zig', 'controlid_acesso', 'controlid_rep', 'tagme')
    when 'funcionarios' then p_tipo in ('controlid_acesso', 'controlid_rep')
    when 'batidas' then p_tipo in ('controlid_acesso', 'controlid_rep')
    when 'vendas' then p_tipo = 'zig'
    when 'reservas' then p_tipo = 'tagme'
    when 'exportar_funcionarios' then p_tipo in ('controlid_acesso', 'controlid_rep')
    else false
  end
$$;
comment on function public.sync_escopo_compativel(text, text) is '[api] Escopo de sincronização compatível com o tipo.';

create or replace function public.sync_solicitar(
  p_integracao uuid default null, p_escopo text default 'tudo', p_data_inicio date default null,
  p_data_fim date default null, p_parametros jsonb default '{}', p_empresa uuid default null
) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
  v_int public.integracoes;
  v_sem_integracao boolean := p_escopo in ('apurar_ponto', 'exportar_fechamento');
  v_parametros jsonb := coalesce(p_parametros, '{}'::jsonb);
  v_criadas int := 0;
  v_fech uuid;
  v_existe boolean;
  r record;
begin
  if p_escopo is null or p_escopo not in ('tudo', 'funcionarios', 'batidas', 'vendas', 'reservas', 'exportar_funcionarios',
                                         'apurar_ponto', 'exportar_fechamento') then
    raise exception 'Escopo inválido' using errcode = '22023';
  end if;
  if jsonb_typeof(v_parametros) <> 'object' then
    raise exception 'Parâmetros inválidos' using errcode = '22023';
  end if;

  if p_integracao is not null then
    select * into v_int from public.integracoes where id = p_integracao;
    if not found then
      raise exception 'Integração não encontrada' using errcode = 'P0002';
    end if;
    v_empresa := v_int.empresa_id;
    if not public.pode_operar(v_empresa) then
      raise exception 'Sem permissão' using errcode = '42501';
    end if;
    if v_sem_integracao or not public.sync_escopo_compativel(p_escopo, v_int.tipo) then
      raise exception 'Tipo de integração incompatível' using errcode = '22023';
    end if;
    if not v_int.ativa then
      raise exception 'Integração inativa' using errcode = '22023';
    end if;
  else
    v_empresa := public.resolver_empresa(p_empresa, 'operar');
  end if;

  if p_data_inicio is not null and p_data_fim is not null then
    if p_data_fim < p_data_inicio then
      raise exception 'Período inválido' using errcode = '22023';
    end if;
    if p_data_fim - p_data_inicio + 1 > 31 then
      raise exception 'Período máximo de 31 dias' using errcode = '22023';
    end if;
  end if;

  if p_escopo = 'exportar_fechamento' then
    begin
      v_fech := (v_parametros ->> 'fechamento_id')::uuid;
    exception when others then
      v_fech := null;
    end;
    if v_fech is null then
      raise exception 'Fechamento não encontrado' using errcode = 'P0002';
    end if;
    if to_regclass('public.comissao_fechamentos') is not null then
      execute 'select exists (select 1 from public.comissao_fechamentos where id = $1 and empresa_id = $2)'
        into v_existe using v_fech, v_empresa;
      if not v_existe then
        raise exception 'Fechamento não encontrado' using errcode = 'P0002';
      end if;
    end if;
  end if;

  -- Solicitações presas em andamento há mais de 30 min viram erro.
  update public.sync_solicitacoes
     set status = 'erro', mensagem = 'Expirada', concluido_em = public.agora()
   where empresa_id = v_empresa and status = 'em_andamento' and pego_em < public.agora() - interval '30 minutes';

  for r in
    select null::uuid as integracao_id where v_sem_integracao
    union all
    select i.id from public.integracoes i
     where not v_sem_integracao
       and i.empresa_id = v_empresa and i.ativa
       and public.sync_escopo_compativel(p_escopo, i.tipo)
       and (p_integracao is null or i.id = p_integracao)
  loop
    if exists (select 1 from public.sync_solicitacoes s
                where s.empresa_id = v_empresa and s.escopo = p_escopo
                  and s.integracao_id is not distinct from r.integracao_id
                  and s.status in ('pendente', 'em_andamento')
                  and (p_escopo <> 'exportar_fechamento' or s.parametros ->> 'fechamento_id' = v_fech::text)) then
      continue;
    end if;
    insert into public.sync_solicitacoes (empresa_id, integracao_id, escopo, data_inicio, data_fim, parametros,
                                          solicitado_por, solicitado_em)
    values (v_empresa, r.integracao_id, p_escopo, p_data_inicio, p_data_fim, v_parametros,
            public.meu_perfil_id(), public.agora());
    v_criadas := v_criadas + 1;
  end loop;
  return v_criadas;
end $$;
comment on function public.sync_solicitar(uuid, text, date, date, jsonb, uuid) is
  '[api] "Sincronizar agora": enfileira uma solicitação por integração ativa alvo (G A M).';

-- ================================================================== ingestão: usuários Control iD
create or replace function public.ingestao_controlid_usuarios(p_integracao uuid, p_usuarios jsonb) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.integracoes := public.integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  v_rep boolean;
  v_ident text;
  v_item jsonb;
  v_idx int := -1;
  v_id text; v_reg text; v_nome text; v_cpf text; v_pis text;
  v_vistos text[] := array[]::text[];
  v_lidos int := 0; v_ignorados int := 0; v_inseridos int := 0; v_atualizados int := 0;
  v_removidos int := 0; v_vinculados int := 0; v_sem_vinculo int := 0;
  v_erros jsonb := '[]'::jsonb;
  v_inserido boolean;
  r record;
  v_func uuid;
begin
  if p_usuarios is null or jsonb_typeof(p_usuarios) <> 'array' then
    raise exception 'Lista de usuários inválida' using errcode = '22023';
  end if;
  v_rep := v.tipo = 'controlid_rep';
  v_ident := coalesce(v.parametros ->> 'identificador', 'cpf');

  for v_item in select value from jsonb_array_elements(p_usuarios) loop
    v_idx := v_idx + 1;
    v_lidos := v_lidos + 1;
    if jsonb_typeof(v_item) <> 'object' then
      v_ignorados := v_ignorados + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', 'item inválido');
      end if;
      continue;
    end if;
    v_id := btrim(coalesce(v_item ->> 'id', ''));
    v_cpf := nullif(regexp_replace(coalesce(v_item ->> 'cpf', ''), '[^0-9]', '', 'g'), '');
    v_pis := nullif(regexp_replace(coalesce(v_item ->> 'pis', ''), '[^0-9]', '', 'g'), '');
    if v_rep then
      v_id := regexp_replace(v_id, '[^0-9]', '', 'g');
      if v_id = '' then
        v_id := coalesce(case when v_ident = 'pis' then v_pis else v_cpf end, '');
      end if;
      if v_id <> '' and v_ident = 'pis' then v_pis := coalesce(v_pis, v_id); end if;
      if v_id <> '' and v_ident <> 'pis' then v_cpf := coalesce(v_cpf, v_id); end if;
    end if;
    if v_id = '' then
      v_ignorados := v_ignorados + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', 'id ausente');
      end if;
      continue;
    end if;
    if v_id = any (v_vistos) then
      v_ignorados := v_ignorados + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', 'id repetido');
      end if;
      continue;
    end if;
    v_vistos := v_vistos || v_id;
    v_reg := nullif(btrim(coalesce(v_item ->> 'registration', '')), '');
    v_nome := nullif(btrim(coalesce(v_item ->> 'name', v_item ->> 'nome', '')), '');

    insert into public.controlid_usuarios as c (empresa_id, integracao_id, user_id_externo, registration, nome, cpf, pis,
                                               visto_em, removido_no_equipamento)
    values (v.empresa_id, v.id, v_id, v_reg, v_nome, v_cpf, v_pis, public.agora(), false)
    on conflict (integracao_id, user_id_externo) do update
      set registration = excluded.registration, nome = excluded.nome, cpf = excluded.cpf, pis = excluded.pis,
          visto_em = excluded.visto_em, removido_no_equipamento = false
    returning (xmax = 0) into v_inserido;
    if v_inserido then v_inseridos := v_inseridos + 1; else v_atualizados := v_atualizados + 1; end if;
  end loop;

  update public.controlid_usuarios
     set removido_no_equipamento = true
   where integracao_id = v.id and not removido_no_equipamento and not (user_id_externo = any (v_vistos));
  get diagnostics v_removidos = row_count;

  -- Vínculo automático: matrícula, depois CPF, depois PIS (resultado único, mesma empresa, funcionário livre).
  for r in
    select c.id, c.registration, c.cpf, c.pis
      from public.controlid_usuarios c
     where c.integracao_id = v.id and c.funcionario_id is null and c.vinculo is null
       and not c.removido_no_equipamento
     order by c.user_id_externo
  loop
    v_func := null;
    if r.registration is not null then
      select min(f.id::text)::uuid into v_func from public.funcionarios f
       where f.empresa_id = v.empresa_id and f.matricula = r.registration
         and not exists (select 1 from public.controlid_usuarios x where x.integracao_id = v.id and x.funcionario_id = f.id)
      having count(*) = 1;
    end if;
    if v_func is null and r.cpf is not null then
      select min(f.id::text)::uuid into v_func from public.funcionarios f
       where f.empresa_id = v.empresa_id and f.cpf = r.cpf
         and not exists (select 1 from public.controlid_usuarios x where x.integracao_id = v.id and x.funcionario_id = f.id)
      having count(*) = 1;
    end if;
    if v_func is null and r.pis is not null then
      select min(f.id::text)::uuid into v_func from public.funcionarios f
       where f.empresa_id = v.empresa_id and f.pis = r.pis
         and not exists (select 1 from public.controlid_usuarios x where x.integracao_id = v.id and x.funcionario_id = f.id)
      having count(*) = 1;
    end if;
    if v_func is not null then
      update public.controlid_usuarios set funcionario_id = v_func, vinculo = 'automatico' where id = r.id;
      v_vinculados := v_vinculados + 1;
    end if;
  end loop;

  select count(*) into v_sem_vinculo from public.controlid_usuarios
   where integracao_id = v.id and funcionario_id is null and not removido_no_equipamento;

  return jsonb_build_object(
    'lidos', v_lidos, 'gravados', v_inseridos + v_atualizados, 'ignorados', v_ignorados,
    'inseridos', v_inseridos, 'atualizados', v_atualizados, 'removidos', v_removidos,
    'vinculados_automaticamente', v_vinculados, 'sem_vinculo', v_sem_vinculo
  ) || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_controlid_usuarios(uuid, jsonb) is
  '[servico] Snapshot completo dos usuários de um equipamento Control iD + vínculo automático (§11.3).';

-- =========================================================================== ingestão: consultas
create or replace function public.ingestao_integracoes_ativas(p_tipo text default null, p_somente_vencidas boolean default false)
returns table(integracao_id uuid, empresa_id uuid, tipo text, nome text, intervalo_minutos int, ultima_execucao_em timestamptz)
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select i.id, i.empresa_id, i.tipo, i.nome, i.intervalo_minutos, i.ultima_execucao_em
    from public.integracoes i
    join public.empresas e on e.id = i.empresa_id
   where i.ativa and e.ativa
     and (p_tipo is null or i.tipo = p_tipo)
     and (not coalesce(p_somente_vencidas, false)
          or i.ultima_execucao_em is null
          or public.agora() - i.ultima_execucao_em >= make_interval(mins => i.intervalo_minutos))
   order by i.ultima_execucao_em nulls first, i.id
$$;
comment on function public.ingestao_integracoes_ativas(text, boolean) is
  '[servico] Integrações ativas de empresas ativas (opcionalmente só as vencidas).';

create or replace function public.ingestao_integracao_config(p_integracao uuid) returns jsonb
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.integracoes := public.integracao_validar(p_integracao, null, false);
  e public.empresas;
  v_segredos jsonb;
  v_lojas jsonb;
  v_res jsonb;
begin
  select * into e from public.empresas where id = v.empresa_id;
  select segredos into v_segredos from public.integracoes_segredos where integracao_id = v.id;
  v_res := jsonb_build_object(
    'integracao_id', v.id, 'empresa_id', v.empresa_id, 'tipo', v.tipo, 'nome', v.nome, 'ativa', v.ativa,
    'parametros', v.parametros, 'segredos', coalesce(v_segredos, '{}'::jsonb), 'cursor', v.cursor,
    'fuso', e.fuso, 'virada_dia', to_char(e.virada_dia, 'HH24:MI:SS'),
    'dia_trabalho_atual', public.dia_de_trabalho(public.agora(), v.empresa_id)
  );
  if v.tipo = 'zig' then
    v_lojas := '[]'::jsonb;
    if to_regclass('public.zig_lojas') is not null then
      execute $q$select coalesce(jsonb_agg(jsonb_build_object('loja_id_externo', loja_id_externo, 'nome', nome,
                                                              'sincronizar', sincronizar) order by nome), '[]'::jsonb)
                   from public.zig_lojas where empresa_id = $1$q$
        into v_lojas using v.empresa_id;
    end if;
    v_res := v_res || jsonb_build_object('lojas', v_lojas);
  end if;
  return v_res;
end $$;
comment on function public.ingestao_integracao_config(uuid) is
  '[servico] Configuração completa (com segredos) de uma integração para o N8N.';

create or replace function public.ingestao_funcionarios_para_exportar(p_integracao uuid)
returns table(funcionario_id uuid, nome text, registration text, cpf text, pis text)
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.integracoes := public.integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  v_hoje date := public.dia_de_trabalho(public.agora(), v.empresa_id);
begin
  return query
  select f.id, f.nome, f.matricula, f.cpf, f.pis
    from public.funcionarios f
   where f.empresa_id = v.empresa_id and f.ativo
     and (f.data_admissao is null or f.data_admissao <= v_hoje)
     and (f.data_desligamento is null or f.data_desligamento >= v_hoje)
     and not exists (select 1 from public.controlid_usuarios c
                      where c.integracao_id = v.id and c.funcionario_id = f.id and not c.removido_no_equipamento)
   order by f.nome, f.id;
end $$;
comment on function public.ingestao_funcionarios_para_exportar(uuid) is
  '[servico] Funcionários no vínculo ainda sem usuário ligado neste equipamento.';

-- ============================================================================ ingestão: fila
create or replace function public.ingestao_sync_pegar_solicitacoes(p_limite int default 5)
returns table(solicitacao_id uuid, empresa_id uuid, integracao_id uuid, integracao_tipo text, escopo text,
              data_inicio date, data_fim date, parametros jsonb)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
#variable_conflict use_column
begin
  update public.sync_solicitacoes
     set status = 'erro', mensagem = 'Expirada', concluido_em = public.agora()
   where status = 'em_andamento' and pego_em < public.agora() - interval '30 minutes';

  -- Pendências de integração inativa ou empresa inativa não serão atendidas.
  update public.sync_solicitacoes s
     set status = 'cancelada', concluido_em = public.agora(),
         mensagem = case when not e.ativa then 'Empresa inativa' else 'Integração inativa' end
    from public.empresas e
   where s.status = 'pendente' and e.id = s.empresa_id
     and (not e.ativa or exists (select 1 from public.integracoes i where i.id = s.integracao_id and not i.ativa));

  return query
  with alvo as (
    select s.id from public.sync_solicitacoes s
     where s.status = 'pendente'
     order by s.solicitado_em, s.id
     limit greatest(coalesce(p_limite, 5), 1)
     for update skip locked
  ), pegas as (
    update public.sync_solicitacoes s
       set status = 'em_andamento', pego_em = public.agora()
      from alvo
     where s.id = alvo.id
    returning s.id, s.empresa_id, s.integracao_id, s.escopo, s.data_inicio, s.data_fim, s.parametros, s.solicitado_em
  )
  select p.id, p.empresa_id, p.integracao_id, i.tipo, p.escopo, p.data_inicio, p.data_fim, p.parametros
    from pegas p
    left join public.integracoes i on i.id = p.integracao_id
   order by p.solicitado_em, p.id;
end $$;
comment on function public.ingestao_sync_pegar_solicitacoes(int) is
  '[servico] Pega as solicitações pendentes mais antigas (for update skip locked) e as passa a em_andamento.';

create or replace function public.ingestao_sync_concluir_solicitacao(
  p_solicitacao uuid, p_status text, p_mensagem text default null, p_execucao uuid default null
) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_status is null or p_status not in ('concluida', 'erro') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  update public.sync_solicitacoes
     set status = p_status, mensagem = p_mensagem, execucao_id = coalesce(p_execucao, execucao_id),
         concluido_em = public.agora()
   where id = p_solicitacao;
  if not found then
    raise exception 'Solicitação não encontrada' using errcode = 'P0002';
  end if;
end $$;
comment on function public.ingestao_sync_concluir_solicitacao(uuid, text, text, uuid) is
  '[servico] Conclui uma solicitação da fila (concluida | erro).';

create or replace function public.ingestao_sync_iniciar(
  p_tipo text, p_gatilho text, p_workflow text, p_empresa uuid default null, p_integracao uuid default null,
  p_solicitacao uuid default null, p_periodo_inicio date default null, p_periodo_fim date default null,
  p_n8n_execution_id text default null
) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid := p_empresa;
  v_id uuid;
begin
  if p_integracao is not null then
    select empresa_id into v_empresa from public.integracoes where id = p_integracao;
    if v_empresa is null then
      raise exception 'Integração não encontrada' using errcode = 'P0002';
    end if;
  elsif v_empresa is not null and not exists (select 1 from public.empresas where id = v_empresa) then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;

  update public.sync_execucoes
     set status = 'erro', erro = 'Expirada', finalizado_em = public.agora()
   where status = 'executando' and tipo = p_tipo
     and integracao_id is not distinct from p_integracao
     and empresa_id is not distinct from v_empresa
     and iniciado_em < public.agora() - interval '30 minutes';

  insert into public.sync_execucoes (empresa_id, integracao_id, solicitacao_id, tipo, gatilho, workflow, n8n_execution_id,
                                     status, iniciado_em, periodo_inicio, periodo_fim)
  values (v_empresa, p_integracao, p_solicitacao, p_tipo, p_gatilho, coalesce(nullif(btrim(p_workflow), ''), '?'),
          p_n8n_execution_id, 'executando', public.agora(), p_periodo_inicio, p_periodo_fim)
  returning id into v_id;

  if p_integracao is not null then
    update public.integracoes set ultima_execucao_em = public.agora() where id = p_integracao;
  end if;
  return v_id;
end $$;
comment on function public.ingestao_sync_iniciar(text, text, text, uuid, uuid, uuid, date, date, text) is
  '[servico] Abre uma sync_execucoes (executando) e marca ultima_execucao_em da integração.';

create or replace function public.ingestao_sync_finalizar(
  p_execucao uuid, p_status text, p_lidos int default 0, p_gravados int default 0, p_ignorados int default 0,
  p_erro text default null, p_detalhes jsonb default '{}', p_tentativas int default 1
) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_integracao uuid;
begin
  if p_status is null or p_status not in ('sucesso', 'parcial', 'erro') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  update public.sync_execucoes
     set status = p_status, finalizado_em = public.agora(),
         registros_lidos = coalesce(p_lidos, 0), registros_gravados = coalesce(p_gravados, 0),
         registros_ignorados = coalesce(p_ignorados, 0), erro = p_erro,
         detalhes = coalesce(p_detalhes, '{}'::jsonb), tentativas = coalesce(p_tentativas, 1)
   where id = p_execucao
  returning integracao_id into v_integracao;
  if not found then
    raise exception 'Execução não encontrada' using errcode = 'P0002';
  end if;
  if v_integracao is not null then
    update public.integracoes
       set ultimo_status = p_status, ultimo_erro = p_erro,
           ultimo_sucesso_em = case when p_status in ('sucesso', 'parcial') then public.agora() else ultimo_sucesso_em end
     where id = v_integracao;
  end if;
end $$;
comment on function public.ingestao_sync_finalizar(uuid, text, int, int, int, text, jsonb, int) is
  '[servico] Fecha uma sync_execucoes e atualiza o último status da integração.';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000120_integracoes_sync.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000130_tarefas.sql
-- =====================================================================================================
-- 20261006000130_tarefas.sql  (backend-1)
-- tarefas_rotinas, tarefas_rotina_itens, tarefas, tarefa_itens, RPCs de tarefas, RLS. Idempotente.
-- =====================================================================================================

create table if not exists public.tarefas_rotinas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  recorrencia                 text not null default 'diaria' check (recorrencia in ('diaria', 'semanal', 'mensal')),
  dias_semana                 smallint[] not null default '{}',
  dia_mes                     smallint check (dia_mes between 1 and 31),
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  ativa                       boolean not null default true,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  constraint tarefas_rotinas_semanal check (recorrencia <> 'semanal' or cardinality(dias_semana) > 0),
  constraint tarefas_rotinas_mensal check (recorrencia <> 'mensal' or dia_mes is not null),
  constraint tarefas_rotinas_dias check (dias_semana <@ array[0,1,2,3,4,5,6]::smallint[])
);
create index if not exists tarefas_rotinas_empresa_idx on public.tarefas_rotinas (empresa_id);
create index if not exists tarefas_rotinas_resp_func_idx on public.tarefas_rotinas (responsavel_funcionario_id);
create index if not exists tarefas_rotinas_resp_perfil_idx on public.tarefas_rotinas (responsavel_perfil_id);
create index if not exists tarefas_rotinas_criado_por_idx on public.tarefas_rotinas (criado_por);
comment on table public.tarefas_rotinas is '[api:crud] Rotinas recorrentes que geram tarefas.';

create table if not exists public.tarefas_rotina_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,
  rotina_id   uuid not null references public.tarefas_rotinas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> '')
);
create index if not exists tarefas_rotina_itens_empresa_idx on public.tarefas_rotina_itens (empresa_id);
create index if not exists tarefas_rotina_itens_rotina_idx on public.tarefas_rotina_itens (rotina_id, ordem);
comment on table public.tarefas_rotina_itens is '[api:crud] Checklist das rotinas.';

create table if not exists public.tarefas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  rotina_id                   uuid references public.tarefas_rotinas (id) on delete set null,
  data                        date not null,
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  status                      text not null default 'pendente'
                              check (status in ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  concluida_por               uuid references public.perfis (id) on delete set null,
  concluida_em                timestamptz,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  unique (rotina_id, data)
);
create index if not exists tarefas_empresa_data_idx on public.tarefas (empresa_id, data);
create index if not exists tarefas_resp_func_idx on public.tarefas (responsavel_funcionario_id);
create index if not exists tarefas_resp_perfil_idx on public.tarefas (responsavel_perfil_id);
create index if not exists tarefas_concluida_por_idx on public.tarefas (concluida_por);
create index if not exists tarefas_criado_por_idx on public.tarefas (criado_por);
comment on table public.tarefas is '[api:crud] Tarefas do dia de trabalho (avulsas ou geradas por rotina).';

create table if not exists public.tarefa_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,
  tarefa_id   uuid not null references public.tarefas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> ''),
  feito       boolean not null default false,
  feito_por   uuid references public.perfis (id) on delete set null,
  feito_em    timestamptz
);
create index if not exists tarefa_itens_empresa_idx on public.tarefa_itens (empresa_id);
create index if not exists tarefa_itens_tarefa_idx on public.tarefa_itens (tarefa_id, ordem);
create index if not exists tarefa_itens_feito_por_idx on public.tarefa_itens (feito_por);
comment on table public.tarefa_itens is '[api:crud] Checklist das tarefas.';

-- ====================================================================================== gatilhos
-- Responsáveis da mesma empresa.
create or replace function public.tarefa_validar_responsaveis(p_empresa uuid, p_funcionario uuid, p_perfil uuid) returns void
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_funcionario is not null
     and not exists (select 1 from public.funcionarios where id = p_funcionario and empresa_id = p_empresa) then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  if p_perfil is not null
     and not exists (select 1 from public.perfis where id = p_perfil and empresa_id = p_empresa) then
    raise exception 'Usuário de outra empresa' using errcode = '22023';
  end if;
end $$;
comment on function public.tarefa_validar_responsaveis(uuid, uuid, uuid) is '[interno] Responsáveis da mesma empresa.';

create or replace function public.tarefas_rotinas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
  else
    new.criado_por := public.meu_perfil_id();
  end if;
  new.titulo := btrim(new.titulo);
  select coalesce(array_agg(distinct d order by d), '{}') into new.dias_semana from unnest(new.dias_semana) d;
  perform public.tarefa_validar_responsaveis(new.empresa_id, new.responsavel_funcionario_id, new.responsavel_perfil_id);
  return new;
end $$;
comment on function public.tarefas_rotinas_antes_gravar() is '[interno] Gatilho de tarefas_rotinas.';

drop trigger if exists tarefas_rotinas_antes_gravar on public.tarefas_rotinas;
create trigger tarefas_rotinas_antes_gravar before insert or update on public.tarefas_rotinas
  for each row execute function public.tarefas_rotinas_antes_gravar();
drop trigger if exists tarefas_rotinas_tocar on public.tarefas_rotinas;
create trigger tarefas_rotinas_tocar before update on public.tarefas_rotinas
  for each row execute function public.tocar_atualizado_em();

create or replace function public.tarefas_rotina_itens_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.tarefas_rotinas where id = new.rotina_id;
  if new.empresa_id is null then
    raise exception 'Rotina não encontrada' using errcode = 'P0002';
  end if;
  new.texto := btrim(new.texto);
  return new;
end $$;
comment on function public.tarefas_rotina_itens_antes_gravar() is '[interno] Gatilho: empresa da rotina.';

drop trigger if exists tarefas_rotina_itens_antes_gravar on public.tarefas_rotina_itens;
create trigger tarefas_rotina_itens_antes_gravar before insert or update on public.tarefas_rotina_itens
  for each row execute function public.tarefas_rotina_itens_antes_gravar();

create or replace function public.tarefas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
  else
    new.criado_por := public.meu_perfil_id();
  end if;
  new.titulo := btrim(new.titulo);
  if new.rotina_id is not null
     and (tg_op = 'INSERT' or new.rotina_id is distinct from old.rotina_id)
     and not exists (select 1 from public.tarefas_rotinas where id = new.rotina_id and empresa_id = new.empresa_id) then
    raise exception 'Rotina não encontrada' using errcode = 'P0002';
  end if;
  perform public.tarefa_validar_responsaveis(new.empresa_id, new.responsavel_funcionario_id, new.responsavel_perfil_id);
  if new.status = 'concluida' and (tg_op = 'INSERT' or old.status is distinct from 'concluida') then
    new.concluida_por := public.meu_perfil_id();
    new.concluida_em := public.agora();
  elsif new.status <> 'concluida' then
    new.concluida_por := null;
    new.concluida_em := null;
  elsif tg_op = 'UPDATE' then
    new.concluida_por := old.concluida_por;
    new.concluida_em := old.concluida_em;
  end if;
  return new;
end $$;
comment on function public.tarefas_antes_gravar() is '[interno] Gatilho de tarefas: conclusão, responsáveis, empresa.';

drop trigger if exists tarefas_antes_gravar on public.tarefas;
create trigger tarefas_antes_gravar before insert or update on public.tarefas
  for each row execute function public.tarefas_antes_gravar();
drop trigger if exists tarefas_tocar on public.tarefas;
create trigger tarefas_tocar before update on public.tarefas
  for each row execute function public.tocar_atualizado_em();

create or replace function public.tarefa_itens_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.tarefas where id = new.tarefa_id;
  if new.empresa_id is null then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  new.texto := btrim(new.texto);
  if new.feito and (tg_op = 'INSERT' or not old.feito) then
    new.feito_por := public.meu_perfil_id();
    new.feito_em := public.agora();
  elsif not new.feito then
    new.feito_por := null;
    new.feito_em := null;
  elsif tg_op = 'UPDATE' then
    new.feito_por := old.feito_por;
    new.feito_em := old.feito_em;
  end if;
  return new;
end $$;
comment on function public.tarefa_itens_antes_gravar() is '[interno] Gatilho de tarefa_itens: empresa e feito_por/em.';

drop trigger if exists tarefa_itens_antes_gravar on public.tarefa_itens;
create trigger tarefa_itens_antes_gravar before insert or update on public.tarefa_itens
  for each row execute function public.tarefa_itens_antes_gravar();

-- =========================================================================================== RLS
do $$
declare
  t text;
begin
  foreach t in array array['tarefas_rotinas', 'tarefas_rotina_itens', 'tarefas', 'tarefa_itens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_ler on public.%1$s', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()))', t);
    execute format('drop policy if exists %1$s_inserir on public.%1$s', t);
    execute format('create policy %1$s_inserir on public.%1$s for insert to authenticated
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_alterar on public.%1$s', t);
    execute format('create policy %1$s_alterar on public.%1$s for update to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
  end loop;
end $$;

-- ========================================================================================= RPCs
-- Rotina cai no dia D?
create or replace function public.rotina_cai_no_dia(p_recorrencia text, p_dias_semana smallint[], p_dia_mes smallint, p_data date)
returns boolean
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case p_recorrencia
    when 'diaria' then true
    when 'semanal' then extract(dow from p_data)::smallint = any (p_dias_semana)
    when 'mensal' then extract(day from p_data)::int
                       = least(p_dia_mes::int,
                               extract(day from (date_trunc('month', p_data) + interval '1 month - 1 day'))::int)
    else false
  end
$$;
comment on function public.rotina_cai_no_dia(text, smallint[], smallint, date) is
  '[api] A rotina (recorrência, dias da semana, dia do mês) cai na data? Mês curto → último dia.';

create or replace function public.tarefas_gerar_empresa(p_empresa uuid, p_data date) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_criadas int := 0;
  r record;
  v_tarefa uuid;
begin
  for r in
    select * from public.tarefas_rotinas t
     where t.empresa_id = p_empresa and t.ativa
       and public.rotina_cai_no_dia(t.recorrencia, t.dias_semana, t.dia_mes, p_data)
     order by t.horario_limite nulls last, t.titulo
  loop
    insert into public.tarefas (empresa_id, rotina_id, data, titulo, descricao, horario_limite, prioridade,
                                responsavel_funcionario_id, responsavel_perfil_id)
    values (p_empresa, r.id, p_data, r.titulo, r.descricao, r.horario_limite, r.prioridade,
            r.responsavel_funcionario_id, r.responsavel_perfil_id)
    on conflict (rotina_id, data) do nothing
    returning id into v_tarefa;
    if v_tarefa is not null then
      insert into public.tarefa_itens (empresa_id, tarefa_id, ordem, texto)
      select p_empresa, v_tarefa, i.ordem, i.texto from public.tarefas_rotina_itens i
       where i.rotina_id = r.id order by i.ordem, i.id;
      v_criadas := v_criadas + 1;
    end if;
    v_tarefa := null;
  end loop;
  return v_criadas;
end $$;
comment on function public.tarefas_gerar_empresa(uuid, date) is '[interno] Materializa as rotinas da empresa numa data.';

create or replace function public.tarefas_gerar_do_dia(p_data date default null, p_empresa uuid default null) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid := public.resolver_empresa(p_empresa, 'ler');
  v_hoje date := public.dia_de_trabalho(public.agora(), v_empresa);
  v_data date := coalesce(p_data, v_hoje);
begin
  if abs(v_data - v_hoje) > 366 then
    raise exception 'Período inválido' using errcode = '22023';
  end if;
  return public.tarefas_gerar_empresa(v_empresa, v_data);
end $$;
comment on function public.tarefas_gerar_do_dia(date, uuid) is
  '[api] Gera as tarefas das rotinas para a data (padrão: dia de trabalho atual). Idempotente (L G A M).';

create or replace function public.ingestao_tarefas_gerar(p_data date default null) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_total int := 0;
  e record;
begin
  for e in select id from public.empresas where ativa order by id loop
    v_total := v_total + public.tarefas_gerar_empresa(e.id, coalesce(p_data, public.dia_de_trabalho(public.agora(), e.id)));
  end loop;
  return v_total;
end $$;
comment on function public.ingestao_tarefas_gerar(date) is '[servico] Gera as tarefas do dia para todas as empresas ativas.';

-- Pode mexer na tarefa? G A M da empresa, ou L responsável por ela.
create or replace function public.tarefa_pode_mexer(p_tarefa public.tarefas) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(public.pode_operar(p_tarefa.empresa_id)
      or (public.pode_ler(p_tarefa.empresa_id)
          and (p_tarefa.responsavel_perfil_id is not distinct from auth.uid() and auth.uid() is not null
               or (p_tarefa.responsavel_funcionario_id is not null
                   and p_tarefa.responsavel_funcionario_id is not distinct from public.meu_funcionario()))), false)
$$;
comment on function public.tarefa_pode_mexer(public.tarefas) is '[interno] G A M ou responsável (leitura).';

create or replace function public.tarefa_mudar_status(p_tarefa uuid, p_status text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.tarefas;
begin
  select * into v from public.tarefas where id = p_tarefa;
  if not found or not public.pode_ler(v.empresa_id) then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  if not public.tarefa_pode_mexer(v) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('pendente', 'em_andamento', 'concluida', 'cancelada') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  update public.tarefas set status = p_status where id = p_tarefa;
end $$;
comment on function public.tarefa_mudar_status(uuid, text) is '[api] Muda o status da tarefa (G A M; L se responsável).';

create or replace function public.tarefa_marcar_item(p_item uuid, p_feito boolean) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.tarefas;
begin
  select t.* into v from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id where i.id = p_item;
  if not found or not public.pode_ler(v.empresa_id) then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  if not public.tarefa_pode_mexer(v) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  update public.tarefa_itens set feito = coalesce(p_feito, false) where id = p_item;
end $$;
comment on function public.tarefa_marcar_item(uuid, boolean) is '[api] Marca/desmarca item do checklist (G A M; L se responsável).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000130_tarefas.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000140_envio_controlid.sql
-- =====================================================================================================
-- 20261006000140_envio_controlid.sql  (backend-1)
-- Envio de dados ao Control iD (sistema → equipamento): credenciais (senha/cartões), foto facial, horários de
-- acesso, fila/estado de envio por equipamento × funcionário. Especificação: docs/CONTRATO-ADENDO-envio-controlid.md.
-- Idempotente.
-- =====================================================================================================

-- ======================================================================================== tabelas
create table if not exists public.funcionario_credenciais (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  senha           text check (senha is null or senha ~ '^[0-9]{4,8}$'),
  versao          int not null default 1,
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_credenciais_empresa_idx on public.funcionario_credenciais (empresa_id);
comment on table public.funcionario_credenciais is
  '[api:nenhum] Senha de acesso (PIN) do funcionário nos equipamentos. Nunca legível pela API.';

create table if not exists public.funcionario_cartoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  numero          text not null check (numero ~ '^[0-9]{1,20}$'),
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index if not exists funcionario_cartoes_funcionario_idx on public.funcionario_cartoes (funcionario_id);
create index if not exists funcionario_cartoes_criado_por_idx on public.funcionario_cartoes (criado_por);
comment on table public.funcionario_cartoes is '[api:nenhum] Cartões/crachás de acesso. Nunca legíveis pela API.';

create table if not exists public.funcionario_fotos (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  bucket          text not null default 'funcionarios-fotos',
  caminho         text not null,
  atualizado_por  uuid references public.perfis (id) on delete set null,
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_fotos_empresa_idx on public.funcionario_fotos (empresa_id);
create index if not exists funcionario_fotos_atualizado_por_idx on public.funcionario_fotos (atualizado_por);
comment on table public.funcionario_fotos is '[api:leitura] Foto facial do funcionário (arquivo no Storage, bucket privado).';

create table if not exists public.controlid_horarios (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (empresa_id, nome)
);
comment on table public.controlid_horarios is '[api:crud] Horários de acesso (faixas semanais) dos equipamentos de acesso.';

create table if not exists public.controlid_horario_faixas (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas (id) on delete cascade,
  horario_id   uuid not null references public.controlid_horarios (id) on delete cascade,
  dia_semana   smallint not null check (dia_semana between 0 and 6),
  inicio       time not null,
  fim          time not null,
  constraint controlid_horario_faixas_ordem check (fim > inicio)
);
create index if not exists controlid_horario_faixas_empresa_idx on public.controlid_horario_faixas (empresa_id);
create index if not exists controlid_horario_faixas_horario_idx on public.controlid_horario_faixas (horario_id, dia_semana);
comment on table public.controlid_horario_faixas is '[api:crud] Faixas (dia da semana, início, fim) de um horário de acesso.';

create table if not exists public.funcionario_horarios (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  horario_id      uuid not null references public.controlid_horarios (id) on delete cascade,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, horario_id)
);
create index if not exists funcionario_horarios_empresa_idx on public.funcionario_horarios (empresa_id);
create index if not exists funcionario_horarios_horario_idx on public.funcionario_horarios (horario_id);
comment on table public.funcionario_horarios is '[api:crud] Horários de acesso de cada funcionário.';

create table if not exists public.controlid_envios (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  integracao_id      uuid not null references public.integracoes (id) on delete cascade,
  alvo               text not null check (alvo in ('funcionario', 'horarios')),
  funcionario_id     uuid references public.funcionarios (id) on delete set null,
  funcionario_nome   text,
  operacao           text not null check (operacao in ('salvar', 'remover', 'bloquear')),
  status             text not null default 'pendente'
                     check (status in ('pendente', 'enviando', 'enviado', 'erro', 'aguardando')),
  versao             int not null default 1,
  assinatura         text not null,
  assinatura_enviada text,
  id_remoto          text,
  mapa_remoto        jsonb not null default '{}'::jsonb,
  tentativas         int not null default 0,
  erro               text,
  pendente_desde     timestamptz,
  pego_em            timestamptz,
  enviado_em         timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index if not exists controlid_envios_empresa_idx on public.controlid_envios (empresa_id, status);
create index if not exists controlid_envios_funcionario_idx on public.controlid_envios (funcionario_id);
create unique index if not exists controlid_envios_func_uk on public.controlid_envios (integracao_id, funcionario_id)
  where alvo = 'funcionario' and funcionario_id is not null;
create unique index if not exists controlid_envios_horarios_uk on public.controlid_envios (integracao_id)
  where alvo = 'horarios';
create index if not exists controlid_envios_fila_idx on public.controlid_envios (integracao_id, status);
comment on table public.controlid_envios is '[api:leitura] Estado do envio de cadastros/horários a cada equipamento Control iD.';

-- ================================================================================ gatilhos simples
create or replace function public.empresa_do_funcionario() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid;
begin
  select empresa_id into v from public.funcionarios where id = new.funcionario_id;
  if v is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  new.empresa_id := v;
  return new;
end $$;
comment on function public.empresa_do_funcionario() is '[interno] Gatilho: empresa_id = empresa do funcionário.';

drop trigger if exists funcionario_credenciais_empresa on public.funcionario_credenciais;
create trigger funcionario_credenciais_empresa before insert or update on public.funcionario_credenciais
  for each row execute function public.empresa_do_funcionario();
drop trigger if exists funcionario_cartoes_empresa on public.funcionario_cartoes;
create trigger funcionario_cartoes_empresa before insert or update on public.funcionario_cartoes
  for each row execute function public.empresa_do_funcionario();
drop trigger if exists funcionario_fotos_empresa on public.funcionario_fotos;
create trigger funcionario_fotos_empresa before insert or update on public.funcionario_fotos
  for each row execute function public.empresa_do_funcionario();

create or replace function public.funcionario_horarios_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid;
begin
  select empresa_id into new.empresa_id from public.funcionarios where id = new.funcionario_id;
  if new.empresa_id is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  select empresa_id into v from public.controlid_horarios where id = new.horario_id;
  if v is distinct from new.empresa_id then
    raise exception 'Horário de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.funcionario_horarios_antes_gravar() is '[interno] Gatilho: horário e funcionário da mesma empresa.';
drop trigger if exists funcionario_horarios_antes_gravar on public.funcionario_horarios;
create trigger funcionario_horarios_antes_gravar before insert or update on public.funcionario_horarios
  for each row execute function public.funcionario_horarios_antes_gravar();

create or replace function public.controlid_horarios_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.controlid_horarios_antes_gravar() is '[interno] Gatilho: horário com empresa imutável.';
drop trigger if exists controlid_horarios_antes_gravar on public.controlid_horarios;
create trigger controlid_horarios_antes_gravar before insert or update on public.controlid_horarios
  for each row execute function public.controlid_horarios_antes_gravar();
drop trigger if exists controlid_horarios_tocar on public.controlid_horarios;
create trigger controlid_horarios_tocar before update on public.controlid_horarios
  for each row execute function public.tocar_atualizado_em();

create or replace function public.controlid_horario_faixas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.controlid_horarios where id = new.horario_id;
  if new.empresa_id is null then
    raise exception 'Horário não encontrado' using errcode = 'P0002';
  end if;
  return new;
end $$;
comment on function public.controlid_horario_faixas_antes_gravar() is '[interno] Gatilho: empresa do horário.';
drop trigger if exists controlid_horario_faixas_antes_gravar on public.controlid_horario_faixas;
create trigger controlid_horario_faixas_antes_gravar before insert or update on public.controlid_horario_faixas
  for each row execute function public.controlid_horario_faixas_antes_gravar();

drop trigger if exists controlid_envios_tocar on public.controlid_envios;
create trigger controlid_envios_tocar before update on public.controlid_envios
  for each row execute function public.tocar_atualizado_em();

-- =========================================================================================== RLS
alter table public.funcionario_credenciais enable row level security;   -- sem políticas
alter table public.funcionario_cartoes enable row level security;       -- sem políticas
alter table public.funcionario_fotos enable row level security;
alter table public.controlid_horarios enable row level security;
alter table public.controlid_horario_faixas enable row level security;
alter table public.funcionario_horarios enable row level security;
alter table public.controlid_envios enable row level security;

drop policy if exists funcionario_fotos_ler on public.funcionario_fotos;
create policy funcionario_fotos_ler on public.funcionario_fotos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

drop policy if exists controlid_envios_ler on public.controlid_envios;
create policy controlid_envios_ler on public.controlid_envios for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

do $$
declare
  t text;
begin
  foreach t in array array['controlid_horarios', 'controlid_horario_faixas', 'funcionario_horarios'] loop
    execute format('drop policy if exists %1$s_ler on public.%1$s', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()))', t);
    execute format('drop policy if exists %1$s_inserir on public.%1$s', t);
    execute format('create policy %1$s_inserir on public.%1$s for insert to authenticated
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_alterar on public.%1$s', t);
    execute format('create policy %1$s_alterar on public.%1$s for update to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
  end loop;
end $$;

-- ============================================================================ Storage (fotos)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('funcionarios-fotos', 'funcionarios-fotos', false, 2097152, array['image/jpeg', 'image/png'])
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists mdg_fotos_ler on storage.objects';
    execute $p$create policy mdg_fotos_ler on storage.objects for select to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_leitura())::text))$p$;
    execute 'drop policy if exists mdg_fotos_inserir on storage.objects';
    execute $p$create policy mdg_fotos_inserir on storage.objects for insert to authenticated
      with check (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_fotos_alterar on storage.objects';
    execute $p$create policy mdg_fotos_alterar on storage.objects for update to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))
      with check (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_fotos_excluir on storage.objects';
    execute $p$create policy mdg_fotos_excluir on storage.objects for delete to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
  end if;
end $$;

-- ============================================================================ estado desejado
-- Configuração de envio efetiva de uma integração (com as regras fixas do REP).
create or replace function public.controlid_envio_config(p_integracao public.integracoes) returns jsonb
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select case when p_integracao.tipo = 'controlid_rep'
              then e || '{"horarios": false, "foto": false, "ao_desligar": "remover"}'::jsonb
              else e end
    from (select public.integracao_envio_padrao(p_integracao.tipo, p_integracao.parametros ->> 'modelo')
                 || coalesce(p_integracao.parametros -> 'envio', '{}'::jsonb) as e) x
$$;
comment on function public.controlid_envio_config(public.integracoes) is '[interno] parametros.envio efetivo da integração.';

create or replace function public.controlid_envio_ligado(p_integracao public.integracoes) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p_integracao.tipo in ('controlid_acesso', 'controlid_rep')
     and p_integracao.ativa
     and coalesce((public.controlid_envio_config(p_integracao) ->> 'ativo')::boolean, false)
     and exists (select 1 from public.empresas e where e.id = p_integracao.empresa_id and e.ativa)
$$;
comment on function public.controlid_envio_ligado(public.integracoes) is '[interno] Envio ligado para a integração?';

-- Grava/atualiza a linha de envio a partir do estado desejado (assinatura e motivo de espera).
create or replace function public.controlid_envio_gravar(
  p_integracao public.integracoes, p_alvo text, p_funcionario uuid, p_nome text, p_operacao text,
  p_assinatura text, p_motivo text, p_id_remoto text
) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.controlid_envios;
  v_status text;
begin
  if p_alvo = 'horarios' then
    select * into v from public.controlid_envios
     where integracao_id = p_integracao.id and alvo = 'horarios' for update;
  else
    select * into v from public.controlid_envios
     where integracao_id = p_integracao.id and alvo = 'funcionario' and funcionario_id = p_funcionario for update;
  end if;

  if v.id is null then
    insert into public.controlid_envios (empresa_id, integracao_id, alvo, funcionario_id, funcionario_nome, operacao, status,
                                         versao, assinatura, id_remoto, erro, pendente_desde)
    values (p_integracao.empresa_id, p_integracao.id, p_alvo, p_funcionario, p_nome, p_operacao,
            case when p_motivo is not null then 'aguardando' else 'pendente' end,
            1, p_assinatura, p_id_remoto, p_motivo, public.agora());
    return;
  end if;

  if p_assinatura is distinct from v.assinatura
     or (p_id_remoto is not null and p_id_remoto is distinct from v.id_remoto) then
    -- Mudou o desejado (ou o usuário do equipamento ligado ao funcionário): nova versão.
    v_status := case when p_motivo is not null then 'aguardando'
                     when p_assinatura = v.assinatura_enviada and p_id_remoto is not distinct from v.id_remoto
                          and v.status = 'enviado' then 'enviado'
                     when v.status = 'enviando' then 'enviando'
                     else 'pendente' end;
    update public.controlid_envios
       set versao = versao + 1, assinatura = p_assinatura, operacao = p_operacao,
           funcionario_nome = coalesce(p_nome, funcionario_nome),
           id_remoto = coalesce(p_id_remoto, id_remoto),
           status = v_status, erro = case when v_status = 'aguardando' then p_motivo else null end,
           tentativas = 0, pendente_desde = public.agora()
     where id = v.id;
  elsif p_motivo is not null and v.status in ('pendente', 'erro') then
    update public.controlid_envios set status = 'aguardando', erro = p_motivo where id = v.id;
  elsif p_motivo is null and v.status = 'aguardando' then
    update public.controlid_envios set status = 'pendente', erro = null, tentativas = 0, pendente_desde = public.agora()
     where id = v.id;
  elsif p_nome is not null and p_nome is distinct from v.funcionario_nome then
    update public.controlid_envios set funcionario_nome = p_nome where id = v.id;
  end if;
end $$;
comment on function public.controlid_envio_gravar(public.integracoes, text, uuid, text, text, text, text, text) is
  '[interno] Upsert do estado de envio com controle de versão.';

-- Horários ativos da empresa no formato do payload.
create or replace function public.controlid_horarios_json(p_empresa uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'horario_id', h.id, 'nome', h.nome,
           'faixas', (select coalesce(jsonb_agg(jsonb_build_object(
                        'dia_semana', f.dia_semana,
                        'inicio', to_char(f.inicio, 'HH24:MI:SS'), 'fim', to_char(f.fim, 'HH24:MI:SS'),
                        'inicio_segundos', extract(epoch from f.inicio)::int,
                        'fim_segundos', extract(epoch from f.fim)::int)
                      order by f.dia_semana, f.inicio, f.fim), '[]'::jsonb)
                        from public.controlid_horario_faixas f where f.horario_id = h.id))
         order by h.nome, h.id), '[]'::jsonb)
    from public.controlid_horarios h
   where h.empresa_id = p_empresa and h.ativo
$$;
comment on function public.controlid_horarios_json(uuid) is '[interno] Horários ativos da empresa (payload de envio).';

-- Regras de acesso (horários ativos do funcionário + ids remotos do equipamento).
create or replace function public.controlid_regras_funcionario(p_integracao uuid, p_funcionario uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'horario_id', h.id,
           'access_rule_id', (select (e.mapa_remoto -> h.id::text ->> 'access_rule_id')::bigint
                                from public.controlid_envios e
                               where e.integracao_id = p_integracao and e.alvo = 'horarios'))
         order by h.nome, h.id), '[]'::jsonb)
    from public.funcionario_horarios fh
    join public.controlid_horarios h on h.id = fh.horario_id and h.ativo
   where fh.funcionario_id = p_funcionario
$$;
comment on function public.controlid_regras_funcionario(uuid, uuid) is '[interno] Regras de acesso do funcionário no equipamento.';

-- Recalcula o estado desejado (adendo A.3). Filtros opcionais por funcionário e integração.
create or replace function public.controlid_envio_atualizar(
  p_empresa uuid, p_funcionario uuid default null, p_integracao uuid default null
) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  i public.integracoes;
  f public.funcionarios;
  v_cfg jsonb;
  v_acesso boolean;
  v_hoje date;
  v_horarios jsonb;
  v_envio_h public.controlid_envios;
  v_link text;
  v_existente public.controlid_envios;
  v_id_remoto text;
  v_no_vinculo boolean;
  v_operacao text;
  v_motivo text;
  v_estado jsonb;
  v_cred public.funcionario_credenciais;
  v_tem_horario boolean;
  v_n int := 0;
begin
  if p_empresa is null then
    return 0;
  end if;
  v_hoje := public.dia_de_trabalho(public.agora(), p_empresa);

  for i in
    select * from public.integracoes
     where empresa_id = p_empresa and tipo in ('controlid_acesso', 'controlid_rep')
       and (p_integracao is null or id = p_integracao)
     order by id
  loop
    continue when not public.controlid_envio_ligado(i);
    v_cfg := public.controlid_envio_config(i);
    v_acesso := i.tipo = 'controlid_acesso';

    -- --------------------------------------------------------------------- horários
    if p_funcionario is null and v_acesso and (v_cfg ->> 'horarios')::boolean then
      v_horarios := public.controlid_horarios_json(p_empresa);
      select * into v_envio_h from public.controlid_envios where integracao_id = i.id and alvo = 'horarios';
      if jsonb_array_length(v_horarios) > 0 or coalesce(v_envio_h.mapa_remoto, '{}'::jsonb) <> '{}'::jsonb then
        perform public.controlid_envio_gravar(i, 'horarios', null, null, 'salvar',
                                              md5(jsonb_build_object('horarios', v_horarios)::text), null, null);
      elsif v_envio_h.id is not null and v_envio_h.status <> 'enviando' then
        delete from public.controlid_envios where id = v_envio_h.id;
      end if;
    end if;
    select * into v_envio_h from public.controlid_envios where integracao_id = i.id and alvo = 'horarios';

    -- ------------------------------------------------------------------ funcionários
    for f in
      select * from public.funcionarios
       where empresa_id = p_empresa and (p_funcionario is null or id = p_funcionario)
       order by id
    loop
      v_link := null;
      select c.user_id_externo into v_link from public.controlid_usuarios c
       where c.integracao_id = i.id and c.funcionario_id = f.id and not c.removido_no_equipamento;
      select * into v_existente from public.controlid_envios
       where integracao_id = i.id and alvo = 'funcionario' and funcionario_id = f.id;
      v_id_remoto := coalesce(v_link, v_existente.id_remoto);
      v_no_vinculo := f.ativo and (f.data_admissao is null or f.data_admissao <= v_hoje)
                      and (f.data_desligamento is null or f.data_desligamento >= v_hoje);
      v_motivo := null;

      if v_no_vinculo then
        v_operacao := 'salvar';
      elsif v_id_remoto is not null then
        v_operacao := case when v_acesso and v_cfg ->> 'ao_desligar' = 'bloquear' then 'bloquear' else 'remover' end;
      else
        -- fora do vínculo e nada no equipamento: nada a fazer
        if v_existente.id is not null and v_existente.operacao = 'salvar' and v_existente.status <> 'enviando' then
          delete from public.controlid_envios where id = v_existente.id;
        end if;
        continue;
      end if;

      if v_operacao = 'salvar' then
        select * into v_cred from public.funcionario_credenciais where funcionario_id = f.id;
        v_tem_horario := exists (select 1 from public.funcionario_horarios fh
                                   join public.controlid_horarios h on h.id = fh.horario_id and h.ativo
                                  where fh.funcionario_id = f.id);
        v_estado := jsonb_build_object(
          'operacao', 'salvar',
          'usuario', jsonb_build_object('nome', f.nome, 'matricula', f.matricula, 'cpf', f.cpf, 'pis', f.pis),
          'senha', case when (v_cfg ->> 'senha')::boolean
                        then to_jsonb(case when v_cred.senha is not null then v_cred.versao else 0 end) end,
          'cartoes', case when (v_cfg ->> 'cartao')::boolean
                          then (select coalesce(jsonb_agg(c.id order by c.criado_em, c.id), '[]'::jsonb)
                                  from public.funcionario_cartoes c where c.funcionario_id = f.id) end,
          'foto', case when v_acesso and (v_cfg ->> 'foto')::boolean
                       then (select jsonb_build_object('caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
                               from public.funcionario_fotos ft where ft.funcionario_id = f.id) end,
          'regras', case when v_acesso and (v_cfg ->> 'horarios')::boolean
                         then public.controlid_regras_funcionario(i.id, f.id) end);
        if not v_acesso then
          if coalesce(i.parametros ->> 'identificador', 'cpf') = 'pis' and f.pis is null then
            v_motivo := 'PIS obrigatório no REP';
          elsif coalesce(i.parametros ->> 'identificador', 'cpf') <> 'pis' and f.cpf is null then
            v_motivo := 'CPF obrigatório no REP';
          end if;
        elsif (v_cfg ->> 'horarios')::boolean and v_tem_horario
              and coalesce(v_envio_h.status, '') <> 'enviado' then
          v_motivo := 'Aguardando envio dos horários';
        end if;
      else
        v_estado := jsonb_build_object('operacao', v_operacao, 'id_remoto', v_id_remoto);
      end if;

      perform public.controlid_envio_gravar(i, 'funcionario', f.id, f.nome, v_operacao, md5(v_estado::text),
                                            v_motivo, v_link);
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_n;
end $$;
comment on function public.controlid_envio_atualizar(uuid, uuid, uuid) is
  '[interno] Recalcula o estado desejado de envio ao Control iD (empresa, funcionário e/ou integração).';

-- ================================================================== gatilhos que disparam o recálculo
create or replace function public.controlid_envio_gatilho_funcionario() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.controlid_envio_atualizar(old.empresa_id, old.funcionario_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.controlid_envio_atualizar(new.empresa_id, new.funcionario_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_funcionario() is
  '[interno] Gatilho: dado do funcionário mudou → recalcula o envio dele.';

do $$
declare
  t text;
begin
  foreach t in array array['funcionario_credenciais', 'funcionario_cartoes', 'funcionario_fotos', 'funcionario_horarios'] loop
    execute format('drop trigger if exists controlid_envio on public.%I', t);
    execute format('create trigger controlid_envio after insert or update or delete on public.%I
                    for each row execute function public.controlid_envio_gatilho_funcionario()', t);
  end loop;
end $$;

create or replace function public.controlid_envio_gatilho_cadastro() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'INSERT' or (old.nome, old.matricula, old.cpf, old.pis, old.ativo, old.data_admissao, old.data_desligamento)
                         is distinct from
                         (new.nome, new.matricula, new.cpf, new.pis, new.ativo, new.data_admissao, new.data_desligamento) then
    perform public.controlid_envio_atualizar(new.empresa_id, new.id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_cadastro() is '[interno] Gatilho: cadastro do funcionário mudou.';
drop trigger if exists controlid_envio on public.funcionarios;
create trigger controlid_envio after insert or update on public.funcionarios
  for each row execute function public.controlid_envio_gatilho_cadastro();

-- Exclusão do funcionário: o que está no equipamento vira "remover" sem funcionário.
create or replace function public.controlid_envio_gatilho_exclusao() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  update public.controlid_envios e
     set operacao = 'remover', status = 'pendente', versao = e.versao + 1, tentativas = 0, erro = null,
         assinatura = md5('remover:' || e.id::text || ':' || clock_timestamp()::text),
         funcionario_nome = old.nome, pendente_desde = public.agora(),
         id_remoto = coalesce((select c.user_id_externo from public.controlid_usuarios c
                                where c.integracao_id = e.integracao_id and c.funcionario_id = old.id
                                  and not c.removido_no_equipamento limit 1), e.id_remoto)
   where e.alvo = 'funcionario' and e.funcionario_id = old.id
     and (e.id_remoto is not null
          or exists (select 1 from public.controlid_usuarios c
                      where c.integracao_id = e.integracao_id and c.funcionario_id = old.id and not c.removido_no_equipamento));
  delete from public.controlid_envios e
   where e.alvo = 'funcionario' and e.funcionario_id = old.id and e.operacao = 'salvar';
  -- equipamento com usuário ligado mas sem linha de envio (importado): também remover, se o envio está ligado
  insert into public.controlid_envios (empresa_id, integracao_id, alvo, funcionario_id, funcionario_nome, operacao, status,
                                       assinatura, id_remoto, pendente_desde)
  select i.empresa_id, i.id, 'funcionario', old.id, old.nome, 'remover', 'pendente',
         md5('remover:' || c.id::text), c.user_id_externo, public.agora()
    from public.controlid_usuarios c
    join public.integracoes i on i.id = c.integracao_id
   where c.funcionario_id = old.id and not c.removido_no_equipamento
     and public.controlid_envio_ligado(i)
     and not exists (select 1 from public.controlid_envios e where e.integracao_id = i.id and e.funcionario_id = old.id);
  return old;
end $$;
comment on function public.controlid_envio_gatilho_exclusao() is '[interno] Gatilho: funcionário excluído → remover no equipamento.';
drop trigger if exists controlid_envio_exclusao on public.funcionarios;
create trigger controlid_envio_exclusao before delete on public.funcionarios
  for each row execute function public.controlid_envio_gatilho_exclusao();

create or replace function public.controlid_envio_gatilho_empresa() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.controlid_envio_atualizar(old.empresa_id);
  else
    perform public.controlid_envio_atualizar(new.empresa_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_empresa() is '[interno] Gatilho: horários mudaram → recalcula a empresa.';
drop trigger if exists controlid_envio on public.controlid_horarios;
create trigger controlid_envio after insert or update or delete on public.controlid_horarios
  for each row execute function public.controlid_envio_gatilho_empresa();
drop trigger if exists controlid_envio on public.controlid_horario_faixas;
create trigger controlid_envio after insert or update or delete on public.controlid_horario_faixas
  for each row execute function public.controlid_envio_gatilho_empresa();

create or replace function public.controlid_envio_gatilho_integracao() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'INSERT' or old.parametros is distinct from new.parametros or old.ativa is distinct from new.ativa then
    perform public.controlid_envio_atualizar(new.empresa_id, null, new.id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_integracao() is '[interno] Gatilho: parâmetros/situação da integração mudaram.';
drop trigger if exists controlid_envio on public.integracoes;
create trigger controlid_envio after insert or update on public.integracoes
  for each row execute function public.controlid_envio_gatilho_integracao();

create or replace function public.controlid_envio_gatilho_usuarios() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' and old.funcionario_id is not null and old.funcionario_id is distinct from new.funcionario_id then
    perform public.controlid_envio_atualizar(old.empresa_id, old.funcionario_id, old.integracao_id);
  end if;
  if new.funcionario_id is not null and (tg_op = 'INSERT' or old.funcionario_id is distinct from new.funcionario_id
                                         or old.removido_no_equipamento is distinct from new.removido_no_equipamento) then
    perform public.controlid_envio_atualizar(new.empresa_id, new.funcionario_id, new.integracao_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_usuarios() is '[interno] Gatilho: vínculo com o equipamento mudou.';
drop trigger if exists controlid_envio on public.controlid_usuarios;
create trigger controlid_envio after insert or update on public.controlid_usuarios
  for each row execute function public.controlid_envio_gatilho_usuarios();

-- ==================================================================================== RPCs do front
create or replace function public.funcionario_para_operar(p_funcionario uuid) returns public.funcionarios
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios;
begin
  select * into f from public.funcionarios where id = p_funcionario;
  if not found then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  if public.pode_operar(f.empresa_id) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return f;
end $$;
comment on function public.funcionario_para_operar(uuid) is '[interno] Funcionário existente e operável (G A M).';

create or replace function public.funcionario_definir_senha(p_funcionario uuid, p_senha text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := nullif(btrim(coalesce(p_senha, '')), '');
begin
  if v is not null and v !~ '^[0-9]{4,8}$' then
    raise exception 'Senha de acesso inválida' using errcode = '22023';
  end if;
  insert into public.funcionario_credenciais (funcionario_id, empresa_id, senha, versao, atualizado_em)
  values (f.id, f.empresa_id, v, 1, now())
  on conflict (funcionario_id) do update
    set senha = excluded.senha,
        versao = funcionario_credenciais.versao + 1,
        atualizado_em = now()
  where funcionario_credenciais.senha is distinct from excluded.senha;
end $$;
comment on function public.funcionario_definir_senha(uuid, text) is
  '[api] Define (4 a 8 dígitos) ou remove (null/vazio) a senha de acesso do funcionário (G A M).';

create or replace function public.funcionario_adicionar_cartao(p_funcionario uuid, p_numero text) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := regexp_replace(coalesce(p_numero, ''), '[^0-9]', '', 'g');
  v_id uuid;
begin
  v := nullif(ltrim(v, '0'), '');
  v := coalesce(v, case when regexp_replace(coalesce(p_numero, ''), '[^0-9]', '', 'g') <> '' then '0' end);
  if v is null or length(v) > 20 then
    raise exception 'Número de cartão inválido' using errcode = '22023';
  end if;
  if exists (select 1 from public.funcionario_cartoes where empresa_id = f.empresa_id and numero = v) then
    raise exception 'Cartão já cadastrado' using errcode = '23505';
  end if;
  insert into public.funcionario_cartoes (empresa_id, funcionario_id, numero, criado_por)
  values (f.empresa_id, f.id, v, public.meu_perfil_id())
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'Cartão já cadastrado' using errcode = '23505';
end $$;
comment on function public.funcionario_adicionar_cartao(uuid, text) is '[api] Adiciona cartão/crachá ao funcionário (G A M).';

create or replace function public.funcionario_remover_cartao(p_cartao uuid) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
begin
  select empresa_id into v_empresa from public.funcionario_cartoes where id = p_cartao;
  if v_empresa is null then
    raise exception 'Cartão não encontrado' using errcode = 'P0002';
  end if;
  if public.pode_operar(v_empresa) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  delete from public.funcionario_cartoes where id = p_cartao;
end $$;
comment on function public.funcionario_remover_cartao(uuid) is '[api] Remove um cartão (G A M).';

create or replace function public.funcionario_definir_foto(p_funcionario uuid, p_caminho text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := nullif(btrim(coalesce(p_caminho, '')), '');
  v_existe boolean := true;
begin
  if v is null then
    delete from public.funcionario_fotos where funcionario_id = f.id;
    return;
  end if;
  if position(f.empresa_id::text || '/' || f.id::text || '/' in v) <> 1
     or v !~* ('^' || f.empresa_id::text || '/' || f.id::text || '/[^/]+\.(jpg|jpeg|png)$') then
    raise exception 'Foto inválida' using errcode = '22023';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)'
      into v_existe using 'funcionarios-fotos', v;
  end if;
  if not v_existe then
    raise exception 'Foto não encontrada' using errcode = 'P0002';
  end if;
  insert into public.funcionario_fotos (funcionario_id, empresa_id, bucket, caminho, atualizado_por, atualizado_em)
  values (f.id, f.empresa_id, 'funcionarios-fotos', v, public.meu_perfil_id(), public.agora())
  on conflict (funcionario_id) do update
    set caminho = excluded.caminho, atualizado_por = excluded.atualizado_por, atualizado_em = excluded.atualizado_em;
end $$;
comment on function public.funcionario_definir_foto(uuid, text) is
  '[api] Registra (ou remove, null) a foto facial já enviada ao Storage (G A M).';

create or replace function public.funcionario_credenciais(p_funcionario uuid) returns jsonb
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
begin
  return jsonb_build_object(
    'senha_definida', exists (select 1 from public.funcionario_credenciais c where c.funcionario_id = f.id and c.senha is not null),
    'cartoes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'final', right(c.numero, 4), 'criado_em', c.criado_em)
                                          order by c.criado_em, c.id), '[]'::jsonb)
                  from public.funcionario_cartoes c where c.funcionario_id = f.id),
    'foto', (select jsonb_build_object('caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
               from public.funcionario_fotos ft where ft.funcionario_id = f.id));
end $$;
comment on function public.funcionario_credenciais(uuid) is
  '[api] Resumo das credenciais (sem a senha nem o número completo dos cartões) (G A M).';

create or replace function public.controlid_envio_reenviar(
  p_integracao uuid default null, p_funcionario uuid default null, p_empresa uuid default null
) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
  v_n int;
begin
  if p_integracao is not null then
    select empresa_id into v_empresa from public.integracoes where id = p_integracao;
    if v_empresa is null then
      raise exception 'Integração não encontrada' using errcode = 'P0002';
    end if;
  elsif p_funcionario is not null then
    select empresa_id into v_empresa from public.funcionarios where id = p_funcionario;
    if v_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
  else
    v_empresa := public.resolver_empresa(p_empresa, 'operar');
  end if;
  if public.pode_operar(v_empresa) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  perform public.controlid_envio_atualizar(v_empresa, p_funcionario, p_integracao);
  update public.controlid_envios
     set status = 'pendente', tentativas = 0, erro = null, pendente_desde = public.agora()
   where empresa_id = v_empresa
     and (p_integracao is null or integracao_id = p_integracao)
     and (p_funcionario is null or funcionario_id = p_funcionario)
     and (status = 'erro' or (p_funcionario is not null and status = 'enviado'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;
comment on function public.controlid_envio_reenviar(uuid, uuid, uuid) is
  '[api] Volta a pendente os envios com erro (e os já enviados, se informar o funcionário) (G A M).';

-- ================================================================================ RPCs do N8N
create or replace function public.controlid_envio_payload(p_envio public.controlid_envios, p_integracao public.integracoes)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_cfg jsonb := public.controlid_envio_config(p_integracao);
  v_acesso boolean := p_integracao.tipo = 'controlid_acesso';
  f public.funcionarios;
begin
  if p_envio.alvo = 'horarios' then
    return jsonb_build_object('envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'horarios', 'operacao', 'salvar',
                              'mapa_anterior', p_envio.mapa_remoto,
                              'horarios', public.controlid_horarios_json(p_envio.empresa_id));
  end if;
  select * into f from public.funcionarios where id = p_envio.funcionario_id;
  if p_envio.operacao <> 'salvar' or f.id is null then
    return jsonb_build_object(
      'envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'funcionario', 'operacao', p_envio.operacao,
      'funcionario_id', f.id, 'id_remoto', p_envio.id_remoto,
      'usuario', jsonb_build_object('nome', coalesce(f.nome, p_envio.funcionario_nome), 'matricula', f.matricula,
                                    'cpf', f.cpf, 'pis', f.pis),
      'senha', null, 'cartoes', '[]'::jsonb, 'foto', null, 'regras_acesso', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'funcionario', 'operacao', 'salvar',
    'funcionario_id', f.id, 'id_remoto', p_envio.id_remoto,
    'usuario', jsonb_build_object('nome', f.nome, 'matricula', f.matricula, 'cpf', f.cpf, 'pis', f.pis),
    'senha', case when (v_cfg ->> 'senha')::boolean
                  then (select to_jsonb(c.senha) from public.funcionario_credenciais c where c.funcionario_id = f.id) end,
    'cartoes', case when (v_cfg ->> 'cartao')::boolean
                    then (select coalesce(jsonb_agg(c.numero order by c.criado_em, c.id), '[]'::jsonb)
                            from public.funcionario_cartoes c where c.funcionario_id = f.id) end,
    'foto', case when v_acesso and (v_cfg ->> 'foto')::boolean
                 then (select jsonb_build_object('bucket', ft.bucket, 'caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
                         from public.funcionario_fotos ft where ft.funcionario_id = f.id) end,
    'regras_acesso', case when v_acesso and (v_cfg ->> 'horarios')::boolean
                          then public.controlid_regras_funcionario(p_integracao.id, f.id) end);
end $$;
comment on function public.controlid_envio_payload(public.controlid_envios, public.integracoes) is
  '[interno] Payload completo (com segredos) de um item de envio.';

create or replace function public.ingestao_controlid_envios_pendentes(p_integracao uuid, p_limite int default 50) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  i public.integracoes := public.integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  v_cfg jsonb := public.controlid_envio_config(i);
  v_itens jsonb := '[]'::jsonb;
  e public.controlid_envios;
begin
  if public.controlid_envio_ligado(i) then
    perform public.controlid_envio_atualizar(i.empresa_id, null, i.id);
    update public.controlid_envios
       set status = 'pendente'
     where integracao_id = i.id and status = 'enviando' and pego_em < public.agora() - interval '30 minutes';
    for e in
      with alvo as (
        select id from public.controlid_envios
         where integracao_id = i.id
           and (status = 'pendente' or (status = 'erro' and tentativas < 5))
         order by (alvo = 'horarios') desc, (operacao <> 'salvar') desc, pendente_desde, id
         limit greatest(coalesce(p_limite, 50), 1)
         for update skip locked
      )
      update public.controlid_envios c
         set status = 'enviando', pego_em = public.agora(), tentativas = c.tentativas + 1
        from alvo where c.id = alvo.id
      returning c.*
    loop
      v_itens := v_itens || public.controlid_envio_payload(e, i);
    end loop;
    select coalesce(jsonb_agg(x order by (x ->> 'alvo' = 'horarios') desc, (x ->> 'operacao' <> 'salvar') desc), '[]'::jsonb)
      into v_itens from jsonb_array_elements(v_itens) x;
  end if;
  return jsonb_build_object(
    'integracao_id', i.id, 'tipo', i.tipo, 'modelo', i.parametros ->> 'modelo', 'envio', v_cfg,
    'identificador', case when i.tipo = 'controlid_rep' then coalesce(i.parametros ->> 'identificador', 'cpf') end,
    'itens', v_itens);
end $$;
comment on function public.ingestao_controlid_envios_pendentes(uuid, int) is
  '[servico] Recalcula e pega as pendências de envio do equipamento, com payload pronto (adendo A.5).';

create or replace function public.ingestao_controlid_envio_resultado(
  p_envio uuid, p_versao int, p_status text, p_id_remoto text default null, p_erro text default null,
  p_mapa_remoto jsonb default null
) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  e public.controlid_envios;
  f public.funcionarios;
  v_id_remoto text;
  v_status text;
begin
  if p_status is null or p_status not in ('enviado', 'erro') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  select * into e from public.controlid_envios where id = p_envio for update;
  if not found then
    raise exception 'Envio não encontrado' using errcode = 'P0002';
  end if;

  if p_status = 'erro' then
    update public.controlid_envios
       set status = 'erro', erro = coalesce(nullif(btrim(p_erro), ''), 'Erro sem mensagem')
     where id = e.id;
    return jsonb_build_object('status', 'erro', 'versao', e.versao);
  end if;

  v_id_remoto := case when e.operacao = 'remover' then null
                      else coalesce(nullif(btrim(p_id_remoto), ''), e.id_remoto) end;
  v_status := case when p_versao = e.versao then 'enviado' else 'pendente' end;

  if e.alvo = 'funcionario' and e.operacao = 'remover' and e.funcionario_id is null and v_status = 'enviado' then
    update public.controlid_usuarios set removido_no_equipamento = true
     where integracao_id = e.integracao_id and user_id_externo = e.id_remoto;
    delete from public.controlid_envios where id = e.id;
    return jsonb_build_object('status', 'enviado', 'versao', e.versao);
  end if;

  update public.controlid_envios
     set status = v_status, id_remoto = v_id_remoto, enviado_em = public.agora(), erro = null,
         assinatura_enviada = case when v_status = 'enviado' then assinatura else assinatura_enviada end,
         mapa_remoto = case when alvo = 'horarios' and p_mapa_remoto is not null
                                 and jsonb_typeof(p_mapa_remoto) = 'object' then p_mapa_remoto else mapa_remoto end
   where id = e.id;

  if e.alvo = 'funcionario' and e.funcionario_id is not null then
    select * into f from public.funcionarios where id = e.funcionario_id;
    if e.operacao = 'remover' and e.id_remoto is not null then
      update public.controlid_usuarios set removido_no_equipamento = true
       where integracao_id = e.integracao_id and user_id_externo = e.id_remoto;
    elsif e.operacao = 'salvar' and v_id_remoto is not null then
      -- O usuário criado/atualizado no equipamento fica ligado ao funcionário (sem desfazer vínculo manual).
      if not exists (select 1 from public.controlid_usuarios
                      where integracao_id = e.integracao_id and user_id_externo = v_id_remoto
                        and (funcionario_id is distinct from f.id) and (funcionario_id is not null or vinculo = 'manual')) then
        update public.controlid_usuarios set funcionario_id = null, vinculo = null
         where integracao_id = e.integracao_id and funcionario_id = f.id and user_id_externo <> v_id_remoto
           and coalesce(vinculo, '') <> 'manual';
        if not exists (select 1 from public.controlid_usuarios
                        where integracao_id = e.integracao_id and funcionario_id = f.id and user_id_externo <> v_id_remoto) then
          insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, registration, nome, cpf, pis,
                                                 funcionario_id, vinculo, removido_no_equipamento, visto_em)
          values (e.empresa_id, e.integracao_id, v_id_remoto, f.matricula, f.nome, f.cpf, f.pis, f.id, 'automatico', false,
                  public.agora())
          on conflict (integracao_id, user_id_externo) do update
            set funcionario_id = excluded.funcionario_id,
                vinculo = coalesce(controlid_usuarios.vinculo, 'automatico'),
                removido_no_equipamento = false, registration = excluded.registration, nome = excluded.nome,
                cpf = excluded.cpf, pis = excluded.pis;
        end if;
      end if;
    end if;
  end if;

  if e.alvo = 'horarios' then
    perform public.controlid_envio_atualizar(e.empresa_id, null, e.integracao_id);
    -- (revisão 2) Os funcionários que aguardavam os horários viram 'pendente' só agora, depois que o N8N já leu as
    -- pendências desta rodada: sem um novo pedido, ficavam esperando o agendador (até 1 h). Enfileira um envio.
    if v_status = 'enviado'
       and exists (select 1 from public.controlid_envios
                    where integracao_id = e.integracao_id and alvo = 'funcionario' and status = 'pendente')
       and not exists (select 1 from public.sync_solicitacoes
                        where integracao_id = e.integracao_id and status = 'pendente'
                          and escopo in ('exportar_funcionarios', 'tudo')) then
      insert into public.sync_solicitacoes (empresa_id, integracao_id, escopo, mensagem)
      values (e.empresa_id, e.integracao_id, 'exportar_funcionarios', 'Automático: envio dos funcionários após os horários');
    end if;
  end if;
  return jsonb_build_object('status', v_status, 'versao', e.versao);
end $$;
comment on function public.ingestao_controlid_envio_resultado(uuid, int, text, text, text, jsonb) is
  '[servico] Registra o resultado de um item de envio ao Control iD (adendo A.5).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000140_envio_controlid.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000200_ponto.sql
-- =====================================================================================================
-- 20261006000200_ponto.sql — backend-2
-- Ponto: batidas, apuração diária, alarmes, ajustes manuais auditados, abonos e banco de horas.
-- Contrato: §6 (DDL), §7 (regras), §10.4 (RPCs). Idempotente (executar.sh aplica duas vezes).
-- =====================================================================================================

-- ================================================================= ponto_batidas
create table if not exists public.ponto_batidas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,
  integracao_id   uuid references public.integracoes (id) on delete set null,
  origem          text not null check (origem in ('controlid_acesso', 'controlid_rep', 'manual')),
  id_externo      text,
  pessoa_externa  text,
  instante        timestamptz not null,
  data_trabalho   date not null,
  desconsiderada  boolean not null default false,
  motivo          text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_batidas_externa_uk unique (integracao_id, id_externo)
);
-- A regra "ponto_batidas_origem" do contrato é validada no gatilho BEFORE INSERT (para não quebrar o on delete set null).
create index if not exists ponto_batidas_func_dia_idx on public.ponto_batidas (funcionario_id, data_trabalho);
create index if not exists ponto_batidas_empresa_dia_idx on public.ponto_batidas (empresa_id, data_trabalho);
create index if not exists ponto_batidas_sem_func_idx on public.ponto_batidas (empresa_id, integracao_id, pessoa_externa)
  where funcionario_id is null;
create index if not exists ponto_batidas_integracao_idx on public.ponto_batidas (integracao_id, pessoa_externa);
create index if not exists ponto_batidas_criado_por_idx on public.ponto_batidas (criado_por);
comment on table public.ponto_batidas is '[api:leitura] Batidas de ponto (Control iD acesso/REP e manuais). Importadas são imutáveis.';

-- =================================================================== ponto_dias
create table if not exists public.ponto_dias (
  funcionario_id      uuid not null references public.funcionarios (id) on delete cascade,
  data                date not null,
  empresa_id          uuid not null references public.empresas (id) on delete cascade,
  jornada_id          uuid references public.jornadas (id) on delete set null,
  abono_tipo          text,
  batidas_esperadas   smallint not null default 0,
  batidas_validas     smallint not null default 0,
  batidas_duplicadas  smallint not null default 0,
  previsto_minutos    int not null default 0,
  trabalhado_minutos  int not null default 0,
  saldo_minutos       int not null default 0,
  atraso_minutos      int not null default 0,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text not null check (situacao in ('completo', 'incompleto', 'ausente', 'folga',
                                                        'sem_escala', 'abonado', 'suspenso', 'em_andamento',
                                                        'falta_justificada', 'falta_injustificada')),
  encerrado           boolean not null,
  alarmes_abertos     smallint not null default 0,
  apurado_em          timestamptz not null default now(),
  primary key (funcionario_id, data)
);
create index if not exists ponto_dias_empresa_idx on public.ponto_dias (empresa_id, data);
create index if not exists ponto_dias_jornada_idx on public.ponto_dias (jornada_id);
comment on table public.ponto_dias is '[api:leitura] Resultado persistido da apuração (funcionário × dia de trabalho).';

-- ================================================================ ponto_alarmes
create table if not exists public.ponto_alarmes (
  id                         uuid primary key default gen_random_uuid(),
  empresa_id                 uuid not null references public.empresas (id) on delete cascade,
  funcionario_id             uuid not null references public.funcionarios (id) on delete cascade,
  data                       date not null,
  tipo                       text not null check (tipo in ('batida_faltando', 'batidas_impares',
                                                           'sem_batida_dia_escalado', 'atraso')),
  batida_esperada            text not null default ''
                             check (batida_esperada in ('', 'entrada', 'saida_intervalo', 'volta_intervalo', 'saida')),
  horario_previsto           timestamptz,
  minutos                    int,
  detalhe                    text not null,
  status                     text not null default 'aberto' check (status in ('aberto', 'justificado', 'resolvido')),
  justificativa              text,
  justificado_por            uuid references public.perfis (id) on delete set null,
  justificado_em             timestamptz,
  resolvido_em               timestamptz,
  resolvido_automaticamente  boolean not null default false,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  unique (funcionario_id, data, tipo, batida_esperada)
);
create index if not exists ponto_alarmes_empresa_idx on public.ponto_alarmes (empresa_id, status, data desc);
create index if not exists ponto_alarmes_justificado_por_idx on public.ponto_alarmes (justificado_por);
comment on table public.ponto_alarmes is '[api:leitura] Alarmes de ponto (gerados pela apuração; justificar/reabrir por RPC).';

-- ================================================================= ponto_ajustes
create table if not exists public.ponto_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  batida_id        uuid references public.ponto_batidas (id) on delete set null,
  acao             text not null check (acao in ('incluir', 'desconsiderar', 'restaurar')),
  instante         timestamptz not null,
  motivo           text not null,
  feito_por        uuid references public.perfis (id) on delete set null,
  feito_por_nome   text not null,
  feito_em         timestamptz not null default now()
);
create index if not exists ponto_ajustes_empresa_idx on public.ponto_ajustes (empresa_id, feito_em desc);
create index if not exists ponto_ajustes_funcionario_idx on public.ponto_ajustes (funcionario_id);
create index if not exists ponto_ajustes_batida_idx on public.ponto_ajustes (batida_id);
create index if not exists ponto_ajustes_feito_por_idx on public.ponto_ajustes (feito_por);
comment on table public.ponto_ajustes is '[api:leitura] Auditoria de toda intervenção manual em batidas.';

-- ================================================================== ponto_abonos
create table if not exists public.ponto_abonos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,
  data            date not null,
  tipo            text not null check (tipo in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro',
                                                'suspensao')),
  motivo          text,
  ocorrencia_id   uuid,          -- abono gerado por suspensão (FK para funcionario_ocorrencias criada em …0250)
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_abonos_uk unique nulls not distinct (empresa_id, funcionario_id, data)
);
create index if not exists ponto_abonos_funcionario_idx on public.ponto_abonos (funcionario_id, data);
create index if not exists ponto_abonos_criado_por_idx on public.ponto_abonos (criado_por);
comment on table public.ponto_abonos is '[api:leitura] Abonos (folga, feriado, férias, atestado...). funcionario_id null = empresa toda.';
-- (adendo extras/ocorrências/reservas) suspensão: abono 'suspensao' gerado pela ocorrência; situação 'suspenso'.
alter table public.ponto_abonos add column if not exists ocorrencia_id uuid;
create index if not exists ponto_abonos_ocorrencia_idx on public.ponto_abonos (ocorrencia_id);
alter table public.ponto_abonos drop constraint if exists ponto_abonos_tipo_check;
alter table public.ponto_abonos add constraint ponto_abonos_tipo_check
  check (tipo in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro', 'suspensao'));
-- (adendo escala) abono 'ferias' gerado por ajuste de férias da escala (FK para escala_ajustes criada em …0280)
alter table public.ponto_abonos add column if not exists escala_ajuste_id uuid;
create index if not exists ponto_abonos_escala_ajuste_idx on public.ponto_abonos (escala_ajuste_id);
alter table public.ponto_dias drop constraint if exists ponto_dias_situacao_check;
alter table public.ponto_dias add constraint ponto_dias_situacao_check
  check (situacao in ('completo', 'incompleto', 'ausente', 'folga', 'sem_escala', 'abonado', 'suspenso', 'em_andamento',
                      'falta_justificada', 'falta_injustificada'));

-- ======================================================= banco_horas_lancamentos
create table if not exists public.banco_horas_lancamentos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  tipo             text not null check (tipo in ('saldo_inicial', 'ajuste', 'compensacao', 'pagamento')),
  minutos          int not null,
  motivo           text not null check (btrim(motivo) <> ''),
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now()
);
create unique index if not exists banco_horas_saldo_inicial_uk on public.banco_horas_lancamentos (funcionario_id, data)
  where tipo = 'saldo_inicial';
create index if not exists banco_horas_empresa_idx on public.banco_horas_lancamentos (empresa_id, data);
create index if not exists banco_horas_funcionario_idx on public.banco_horas_lancamentos (funcionario_id, data);
create index if not exists banco_horas_criado_por_idx on public.banco_horas_lancamentos (criado_por);
comment on table public.banco_horas_lancamentos is '[api:leitura] Lançamentos manuais do banco de horas (saldo inicial, ajustes, compensações, pagamentos).';

-- ========================================================================= RLS
alter table public.ponto_batidas enable row level security;
alter table public.ponto_dias enable row level security;
alter table public.ponto_alarmes enable row level security;
alter table public.ponto_ajustes enable row level security;
alter table public.ponto_abonos enable row level security;
alter table public.banco_horas_lancamentos enable row level security;

drop policy if exists ponto_batidas_ler on public.ponto_batidas;
create policy ponto_batidas_ler on public.ponto_batidas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_dias_ler on public.ponto_dias;
create policy ponto_dias_ler on public.ponto_dias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_alarmes_ler on public.ponto_alarmes;
create policy ponto_alarmes_ler on public.ponto_alarmes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_ajustes_ler on public.ponto_ajustes;
create policy ponto_ajustes_ler on public.ponto_ajustes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists ponto_abonos_ler on public.ponto_abonos;
create policy ponto_abonos_ler on public.ponto_abonos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists banco_horas_ler on public.banco_horas_lancamentos;
create policy banco_horas_ler on public.banco_horas_lancamentos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

-- ================================================================ auxiliares
create or replace function public.ponto_validar_periodo(p_inicio date, p_fim date, p_max_dias int)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido' using errcode = '22023';
  end if;
  if p_fim - p_inicio + 1 > p_max_dias then
    raise exception 'Período máximo de % dias', p_max_dias using errcode = '22023';
  end if;
end $$;
comment on function public.ponto_validar_periodo(date, date, int) is '[interno] Valida período (Período inválido / Período máximo de N dias).';

create or replace function public.ponto_nome_autor()
returns text language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select p.nome from public.perfis p where p.id = auth.uid()), 'Sistema')
$$;
comment on function public.ponto_nome_autor() is '[interno] Nome do perfil logado ou ''Sistema''.';

-- resolver_empresa (b1) + checagem nula-segura do nível (defesa em profundidade).
create or replace function public.ponto_resolver_empresa(p_empresa uuid, p_nivel text)
returns uuid language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v uuid;
begin
  v := public.resolver_empresa(p_empresa, p_nivel);
  if (case p_nivel when 'ler' then public.pode_ler(v) when 'operar' then public.pode_operar(v)
                   when 'administrar' then public.pode_administrar(v) end) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return v;
end $$;
comment on function public.ponto_resolver_empresa(uuid, text) is '[interno] resolver_empresa com checagem nula-segura do nível.';

-- Instante do horário de escala t no dia de trabalho D (§2.4).
create or replace function public.ponto_instante_escala(p_data date, p_hora time, p_fuso text, p_virada time)
returns timestamptz language sql stable set search_path = public, extensions, pg_temp as $$
  select ((p_data + p_hora) + (case when p_hora < p_virada then interval '1 day' else interval '0' end)) at time zone p_fuso
$$;
comment on function public.ponto_instante_escala(date, time, text, time) is '[interno] Instante de um horário de escala no dia de trabalho (§2.4).';

create or replace function public.ponto_fmt_minutos(p_minutos bigint)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when p_minutos < 0 then '-' else '' end
      || (abs(p_minutos) / 60)::text || 'h' || lpad((abs(p_minutos) % 60)::text, 2, '0')
$$;
comment on function public.ponto_fmt_minutos(bigint) is '[interno] Minutos como 7h30 / -3h26.';

-- Funcionário dentro do vínculo na data?
create or replace function public.ponto_no_vinculo(p_admissao date, p_desligamento date, p_data date)
returns boolean language sql immutable set search_path = public, extensions, pg_temp as $$
  select (p_admissao is null or p_data >= p_admissao) and (p_desligamento is null or p_data <= p_desligamento)
$$;
comment on function public.ponto_no_vinculo(date, date, date) is '[interno] Data dentro do vínculo (admissão/desligamento).';

-- ============================================== gatilhos das tabelas de ponto
create or replace function public.ponto_empresa_do_funcionario()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if new.funcionario_id is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
    if tg_table_name = 'ponto_abonos' and new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  end if;
  return new;
end $$;
comment on function public.ponto_empresa_do_funcionario() is '[interno] Gatilho: empresa_id preenchido a partir do funcionário.';

drop trigger if exists a_empresa on public.ponto_dias;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_dias
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_alarmes;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_alarmes
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_ajustes;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_ajustes
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_abonos;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_abonos
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.banco_horas_lancamentos;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.banco_horas_lancamentos
  for each row execute function public.ponto_empresa_do_funcionario();

drop trigger if exists tocar_atualizado_em on public.ponto_alarmes;
create trigger tocar_atualizado_em before update on public.ponto_alarmes
  for each row execute function public.tocar_atualizado_em();

create or replace function public.ponto_batidas_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if tg_op = 'INSERT' then
    if new.funcionario_id is not null then
      select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
      if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
      if new.empresa_id is null then new.empresa_id := v_empresa;
      elsif new.empresa_id <> v_empresa then raise exception 'Funcionário de outra empresa' using errcode = '22023';
      end if;
    end if;
    if new.integracao_id is not null then
      select i.empresa_id into v_empresa from public.integracoes i where i.id = new.integracao_id;
      if v_empresa is null then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
      if new.empresa_id is null then new.empresa_id := v_empresa;
      elsif new.empresa_id <> v_empresa then raise exception 'Integração de outra empresa' using errcode = '22023';
      end if;
    end if;
    -- regra ponto_batidas_origem (§6)
    if not ((new.origem = 'manual' and new.funcionario_id is not null and new.motivo is not null and new.id_externo is null)
         or (new.origem <> 'manual' and new.id_externo is not null and new.integracao_id is not null)) then
      raise exception 'Batida inválida para a origem %', new.origem using errcode = '23514';
    end if;
    new.data_trabalho := public.dia_de_trabalho(new.instante, new.empresa_id);
    return new;
  end if;

  -- UPDATE: batidas são imutáveis; só desconsiderada/motivo (RPC), funcionario_id (vínculo, §7.8)
  -- e integracao_id → null (exclusão da integração) podem mudar.
  if new.origem is distinct from old.origem or new.id_externo is distinct from old.id_externo
     or new.pessoa_externa is distinct from old.pessoa_externa or new.empresa_id is distinct from old.empresa_id
     or (new.instante is distinct from old.instante and old.origem <> 'manual')
     or (new.integracao_id is distinct from old.integracao_id and new.integracao_id is not null) then
    raise exception 'Batida importada não pode ser alterada' using errcode = '22023';
  end if;
  if new.funcionario_id is not null and new.funcionario_id is distinct from old.funcionario_id then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is distinct from new.empresa_id then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  end if;
  -- sempre derivada (também quando fuso/virada da empresa mudam)
  new.data_trabalho := public.dia_de_trabalho(new.instante, new.empresa_id);
  return new;
end $$;
comment on function public.ponto_batidas_antes() is '[interno] Gatilho de ponto_batidas: empresa, regra de origem, data_trabalho e imutabilidade.';

drop trigger if exists a_antes on public.ponto_batidas;
create trigger a_antes before insert or update on public.ponto_batidas
  for each row execute function public.ponto_batidas_antes();

-- ============================================================ cálculo de um dia
-- (adendo escala) Status da escala rotativa no dia: a função real é definida em …0280_escala.sql. Aqui só um esqueleto
-- (criado se ainda não existir) para que a apuração funcione antes da …0280 numa instalação/atualização em andamento.
do $$
begin
  if to_regprocedure('public.escala_status_ponto(uuid, date)') is null then
    execute $f$create function public.escala_status_ponto(p_funcionario uuid, p_data date, out status text, out chegada time)
      language sql stable security definer set search_path = public, extensions, pg_temp as
      'select null::text, null::time'$f$;
    execute $c$comment on function public.escala_status_ponto(uuid, date) is '[interno] Status da escala no dia (esqueleto; ver …0280).'$c$;
  end if;
  -- (adendo extras v3, §E.7.2) falta do funcionário no dia: a função real é definida em …0290_comissao_presenca.sql.
  if to_regprocedure('public.ponto_falta_do_dia(uuid, date)') is null then
    execute $f$create function public.ponto_falta_do_dia(p_funcionario uuid, p_data date) returns text
      language sql stable security definer set search_path = public, extensions, pg_temp as 'select null::text'$f$;
    execute $c$comment on function public.ponto_falta_do_dia(uuid, date) is '[interno] Falta do funcionário no dia (esqueleto; ver …0290).'$c$;
  end if;
end $$;

-- §7.2/§7.3. Não grava nada. Retorna 0 linhas se o funcionário não existe; fora_do_vinculo = true se D fora do vínculo.
create or replace function public.ponto_calcular_dia(p_funcionario uuid, p_data date)
returns table (
  funcionario_id      uuid,
  data                date,
  empresa_id          uuid,
  fora_do_vinculo     boolean,
  jornada_id          uuid,
  jornada_nome        text,
  abono_tipo          text,
  batidas_esperadas   smallint,
  batidas_validas     smallint,
  batidas_duplicadas  smallint,
  previsto_minutos    int,
  trabalhado_minutos  int,
  saldo_minutos       int,
  atraso_minutos      int,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text,
  encerrado           boolean,
  batidas             jsonb,
  esperadas           jsonb,
  alarmes             jsonb
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  f            record;
  e            record;
  j            record;
  jd           record;
  v_abono      text;
  v_slots      timestamptz[] := '{}';
  v_nomes      text[] := '{}';
  v_validas    timestamptz[] := '{}';
  v_ultima     timestamptz;
  v_dup        boolean;
  v_dups       int := 0;
  v_n          int;
  v_k          int;
  v_trab       int := 0;
  v_prev       int := 0;
  v_saldo      int := 0;
  v_atraso     int := 0;
  v_tol_dia    int := 0;
  v_tol_bat    int := 0;
  v_batidas    jsonb := '[]'::jsonb;
  v_esperadas  jsonb := '[]'::jsonb;
  v_alarmes    jsonb := '[]'::jsonb;
  v_encerrado  boolean;
  v_situacao   text;
  b            record;
  i            int;
  v_mask       int;
  v_idx        int[];
  v_custo      numeric;
  v_melhor     int[];
  v_melhor_c   numeric;
  v_esc        record;
  v_desloc     interval;
  v_falta      text;
  v_rotulos    constant jsonb := '{"entrada": "a entrada", "saida_intervalo": "a saída para o intervalo",
                                    "volta_intervalo": "a volta do intervalo", "saida": "a saída"}'::jsonb;
begin
  select * into f from public.funcionarios fu where fu.id = p_funcionario;
  if not found then return; end if;
  select * into e from public.empresas em where em.id = f.empresa_id;

  funcionario_id := f.id;
  data := p_data;
  empresa_id := f.empresa_id;

  if not public.ponto_no_vinculo(f.data_admissao, f.data_desligamento, p_data) then
    fora_do_vinculo := true;
    batidas_esperadas := 0; batidas_validas := 0; batidas_duplicadas := 0;
    previsto_minutos := 0; trabalhado_minutos := 0; saldo_minutos := 0; atraso_minutos := 0;
    encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);
    batidas := '[]'; esperadas := '[]'; alarmes := '[]';
    return next;
    return;
  end if;
  fora_do_vinculo := false;
  v_encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);

  -- 2. Escala e abono
  select jo.id, jo.nome, jo.tolerancia_batida_minutos, jo.tolerancia_diaria_minutos into j
    from public.funcionario_jornadas fj
    join public.jornadas jo on jo.id = fj.jornada_id
   where fj.funcionario_id = f.id and fj.vigente_desde <= p_data
   order by fj.vigente_desde desc
   limit 1;
  if j.id is not null then
    v_tol_dia := j.tolerancia_diaria_minutos;
    v_tol_bat := j.tolerancia_batida_minutos;
  end if;

  select a.tipo into v_abono
    from public.ponto_abonos a
   where a.empresa_id = f.empresa_id and a.data = p_data
     and (a.funcionario_id = f.id or a.funcionario_id is null)
   order by a.funcionario_id nulls last
   limit 1;

  -- (adendo escala §S.5) status da escala rotativa: folga/férias = não escalado; trabalha = escalado com a jornada,
  -- deslocada para a chegada da escala. null = funcionário fora da escala (só a jornada vale).
  select * into v_esc from public.escala_status_ponto(f.id, p_data);

  -- (adendo extras v3, §E.7.2) falta registrada: prevalece sobre abono da empresa e escala. Justificada = como abono
  -- (previsto 0); injustificada = dia previsto normal (saldo −previsto sem batida), sem alarmes.
  v_falta := public.ponto_falta_do_dia(f.id, p_data);
  if v_falta is not null then v_abono := null; end if;

  v_k := 0;
  if v_abono is null and v_falta is distinct from 'justificada' and j.id is not null
     and v_esc.status is distinct from 'folga' and v_esc.status is distinct from 'ferias' then
    select * into jd from public.jornada_dias x
     where x.jornada_id = j.id and x.dia_semana = extract(dow from p_data)::smallint;
    if not found and v_esc.status = 'trabalha' then
      -- jornada sem este dia da semana: usa o primeiro dia cadastrado (SEG→DOM) como modelo de horários
      select * into jd from public.jornada_dias x
       where x.jornada_id = j.id order by (x.dia_semana + 6) % 7 limit 1;
    end if;
    if found then
      v_prev := jd.minutos_previstos;
      v_k := jd.batidas_esperadas;
      if v_k = 4 then
        v_nomes := array['entrada', 'saida_intervalo', 'volta_intervalo', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.volta_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      else
        v_nomes := array['entrada', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      end if;
      if v_esc.chegada is not null then
        v_desloc := public.ponto_instante_escala(p_data, v_esc.chegada, e.fuso, e.virada_dia) - v_slots[1];
        for i in 1 .. v_k loop
          v_slots[i] := v_slots[i] + v_desloc;
        end loop;
      end if;
      for i in 1 .. v_k loop
        v_esperadas := v_esperadas || jsonb_build_object('batida', v_nomes[i], 'instante', v_slots[i]);
      end loop;
    end if;
  end if;

  -- 3. Batidas (duplicadas: a menos de N minutos da última válida)
  for b in
    select pb.id, pb.instante, pb.origem, pb.desconsiderada, pb.motivo
      from public.ponto_batidas pb
     where pb.funcionario_id = f.id and pb.data_trabalho = p_data
     order by pb.instante, pb.id
  loop
    v_dup := false;
    if not b.desconsiderada then
      if v_ultima is not null and b.instante - v_ultima < make_interval(mins => e.ponto_janela_duplicada_minutos) then
        v_dup := true;
        v_dups := v_dups + 1;
      else
        v_validas := v_validas || b.instante;
        v_ultima := b.instante;
      end if;
    end if;
    v_batidas := v_batidas || jsonb_build_object('id', b.id, 'instante', b.instante, 'origem', b.origem,
                                                 'desconsiderada', b.desconsiderada, 'duplicada', v_dup, 'motivo', b.motivo);
  end loop;
  v_n := coalesce(array_length(v_validas, 1), 0);

  -- 4. Trabalhado
  i := 1;
  while i + 1 <= v_n loop
    v_trab := v_trab + floor(extract(epoch from (v_validas[i + 1] - v_validas[i])) / 60)::int;
    i := i + 2;
  end loop;

  -- 5. Saldo
  if not v_encerrado then
    v_saldo := 0;
  elsif v_prev > 0 then
    if v_n = 0 then
      v_saldo := -v_prev;
    elsif abs(v_trab - v_prev) <= v_tol_dia then
      v_saldo := 0;
    else
      v_saldo := v_trab - v_prev;
    end if;
  else
    v_saldo := v_trab;
  end if;

  -- Quais slots foram batidos (0 < n < k): menor Σ|batida − slot|; empate → combinação lexicograficamente menor (§7.3).
  -- Calculado também no dia em andamento, para o atraso abaixo.
  v_melhor := null;
  if v_n > 0 and v_n < v_k then
    for v_mask in 0 .. (1 << v_k) - 1 loop
      v_idx := '{}';
      for i in 1 .. v_k loop
        if (v_mask >> (i - 1)) & 1 = 1 then v_idx := v_idx || i; end if;
      end loop;
      continue when coalesce(array_length(v_idx, 1), 0) <> v_n;
      v_custo := 0;
      for i in 1 .. v_n loop
        v_custo := v_custo + abs(extract(epoch from (v_validas[i] - v_slots[v_idx[i]])));
      end loop;
      if v_melhor is null or v_custo < v_melhor_c or (v_custo = v_melhor_c and v_idx < v_melhor) then
        v_melhor := v_idx;
        v_melhor_c := v_custo;
      end if;
    end loop;
  end if;

  -- 6. Atraso: só se a 1ª batida corresponde à entrada (se a entrada faltou, o alarme é "batida faltando", não atraso).
  if v_k > 0 and v_n > 0 and (v_melhor is null or 1 = any (v_melhor)) then
    v_atraso := greatest(0, floor(extract(epoch from (v_validas[1] - v_slots[1])) / 60)::int);
    if v_atraso <= v_tol_bat then v_atraso := 0; end if;
  end if;

  -- 7. Situação
  if v_falta is not null then v_situacao := 'falta_' || v_falta;
  elsif not v_encerrado then v_situacao := 'em_andamento';
  elsif v_abono = 'suspensao' then v_situacao := 'suspenso';
  elsif v_abono is not null then v_situacao := 'abonado';
  elsif v_k = 0 and v_n = 0 then
    v_situacao := case when v_esc.status in ('folga', 'ferias') or j.id is not null then 'folga' else 'sem_escala' end;
  elsif v_n = 0 then v_situacao := 'ausente';
  elsif v_n >= v_k and v_n % 2 = 0 then v_situacao := 'completo';
  else v_situacao := 'incompleto';
  end if;

  -- 8. Alarmes (§7.3) — dia abonado ou com falta registrada não gera alarme
  if v_abono is null and v_falta is null then
    if v_encerrado then
      if v_k > 0 and v_n = 0 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'sem_batida_dia_escalado', 'batida_esperada', '', 'horario_previsto', v_slots[1], 'minutos', null,
          'detalhe', format('Nenhuma batida em dia de escala (%s–%s)',
                            to_char(v_slots[1] at time zone e.fuso, 'HH24:MI'),
                            to_char(v_slots[v_k] at time zone e.fuso, 'HH24:MI')));
      elsif v_n > 0 and v_n < v_k then
        -- slots não batidos (v_melhor calculado acima): um alarme por batida faltante
        for i in 1 .. v_k loop
          if not (i = any (v_melhor)) then
            v_alarmes := v_alarmes || jsonb_build_object(
              'tipo', 'batida_faltando', 'batida_esperada', v_nomes[i], 'horario_previsto', v_slots[i], 'minutos', null,
              'detalhe', format('Faltou %s (%s)', v_rotulos ->> v_nomes[i], to_char(v_slots[i] at time zone e.fuso, 'HH24:MI')));
          end if;
        end loop;
      elsif v_n % 2 = 1 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'batidas_impares', 'batida_esperada', '', 'horario_previsto', null, 'minutos', null,
          'detalhe', format('%s %s (número ímpar)', v_n, case when v_n = 1 then 'batida' else 'batidas' end));
      end if;
    end if;
    if e.ponto_alarme_atraso and v_atraso > 0 then
      v_alarmes := v_alarmes || jsonb_build_object(
        'tipo', 'atraso', 'batida_esperada', 'entrada', 'horario_previsto', v_slots[1], 'minutos', v_atraso,
        'detalhe', format('Entrada %s (%s min de atraso)', to_char(v_validas[1] at time zone e.fuso, 'HH24:MI'), v_atraso));
    end if;
  end if;

  jornada_id := j.id;
  jornada_nome := j.nome;
  abono_tipo := v_abono;
  batidas_esperadas := v_k;
  batidas_validas := v_n;
  batidas_duplicadas := v_dups;
  previsto_minutos := v_prev;
  trabalhado_minutos := v_trab;
  saldo_minutos := v_saldo;
  atraso_minutos := v_atraso;
  primeira_batida := v_validas[1];
  ultima_batida := case when v_n > 0 then v_validas[v_n] end;
  situacao := v_situacao;
  encerrado := v_encerrado;
  batidas := v_batidas;
  esperadas := v_esperadas;
  alarmes := v_alarmes;
  return next;
end $$;
comment on function public.ponto_calcular_dia(uuid, date) is '[interno] Cálculo de um dia de ponto (§7.2/§7.3). Não grava.';

-- ============================================================ persistência
create or replace function public.ponto_contar_alarmes(p_funcionario uuid, p_data date)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  update public.ponto_dias d
     set alarmes_abertos = (select count(*) from public.ponto_alarmes a
                             where a.funcionario_id = p_funcionario and a.data = p_data and a.status = 'aberto')
   where d.funcionario_id = p_funcionario and d.data = p_data
$$;
comment on function public.ponto_contar_alarmes(uuid, date) is '[interno] Atualiza ponto_dias.alarmes_abertos.';

create or replace function public.ponto_apurar(p_funcionario uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa  uuid;
  v_atual    date;
  v_dia      date;
  c          record;
  a          jsonb;
  v_chaves   text[];
  v_total    int := 0;
begin
  if p_funcionario is null or p_inicio is null or p_fim is null then return 0; end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then return 0; end if;     -- funcionário excluído (cascata) → nada a fazer
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);

  for v_dia in select g::date from generate_series(p_inicio, least(p_fim, v_atual), interval '1 day') g loop
    select * into c from public.ponto_calcular_dia(p_funcionario, v_dia);

    if c.fora_do_vinculo then
      delete from public.ponto_dias where funcionario_id = p_funcionario and data = v_dia;
      update public.ponto_alarmes
         set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
       where funcionario_id = p_funcionario and data = v_dia and status = 'aberto';
      continue;
    end if;

    insert into public.ponto_dias as d (
      funcionario_id, data, empresa_id, jornada_id, abono_tipo, batidas_esperadas, batidas_validas, batidas_duplicadas,
      previsto_minutos, trabalhado_minutos, saldo_minutos, atraso_minutos, primeira_batida, ultima_batida,
      situacao, encerrado, apurado_em)
    values (
      p_funcionario, v_dia, v_empresa, c.jornada_id, c.abono_tipo, c.batidas_esperadas, c.batidas_validas, c.batidas_duplicadas,
      c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos, c.atraso_minutos, c.primeira_batida, c.ultima_batida,
      c.situacao, c.encerrado, public.agora())
    on conflict (funcionario_id, data) do update set
      jornada_id = excluded.jornada_id, abono_tipo = excluded.abono_tipo,
      batidas_esperadas = excluded.batidas_esperadas, batidas_validas = excluded.batidas_validas,
      batidas_duplicadas = excluded.batidas_duplicadas, previsto_minutos = excluded.previsto_minutos,
      trabalhado_minutos = excluded.trabalhado_minutos, saldo_minutos = excluded.saldo_minutos,
      atraso_minutos = excluded.atraso_minutos, primeira_batida = excluded.primeira_batida,
      ultima_batida = excluded.ultima_batida, situacao = excluded.situacao, encerrado = excluded.encerrado,
      apurado_em = excluded.apurado_em;

    v_chaves := '{}';
    for a in select * from jsonb_array_elements(c.alarmes) loop
      v_chaves := v_chaves || ((a ->> 'tipo') || '|' || (a ->> 'batida_esperada'));
      insert into public.ponto_alarmes as pa (
        empresa_id, funcionario_id, data, tipo, batida_esperada, horario_previsto, minutos, detalhe, status)
      values (
        v_empresa, p_funcionario, v_dia, a ->> 'tipo', a ->> 'batida_esperada',
        (a ->> 'horario_previsto')::timestamptz, (a ->> 'minutos')::int, a ->> 'detalhe', 'aberto')
      on conflict (funcionario_id, data, tipo, batida_esperada) do update set
        detalhe = excluded.detalhe,
        horario_previsto = excluded.horario_previsto,
        minutos = excluded.minutos,
        status = case when pa.status = 'resolvido' then 'aberto' else pa.status end,
        resolvido_em = case when pa.status = 'resolvido' then null else pa.resolvido_em end,
        resolvido_automaticamente = case when pa.status = 'resolvido' then false else pa.resolvido_automaticamente end
      where pa.status = 'resolvido'
         or (pa.detalhe, pa.horario_previsto, pa.minutos)
            is distinct from (excluded.detalhe, excluded.horario_previsto, excluded.minutos);
    end loop;

    update public.ponto_alarmes
       set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
     where funcionario_id = p_funcionario and data = v_dia and status = 'aberto'
       and not ((tipo || '|' || batida_esperada) = any (v_chaves));

    perform public.ponto_contar_alarmes(p_funcionario, v_dia);
    v_total := v_total + 1;
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar(uuid, date, date) is '[interno] Apura e persiste ponto_dias/ponto_alarmes (§7.4). Retorna dias apurados.';

-- Apura todos os funcionários de uma empresa (os que têm algum dia de vínculo no período).
create or replace function public.ponto_apurar_empresa(p_empresa uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_total int := 0; f record;
begin
  for f in
    select fu.id from public.funcionarios fu
     where fu.empresa_id = p_empresa
       and (fu.data_admissao is null or fu.data_admissao <= p_fim)
       and (fu.data_desligamento is null or fu.data_desligamento >= p_inicio)
     order by fu.id
  loop
    v_total := v_total + public.ponto_apurar(f.id, p_inicio, p_fim);
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar_empresa(uuid, date, date) is '[interno] Apura todos os funcionários da empresa no período.';

-- ======================================================= gatilhos em tabelas do backend-1 (§7.8)
create or replace function public.ponto_gatilho_controlid_usuario()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_antigo uuid := case when tg_op = 'UPDATE' then old.funcionario_id end;
  v_datas  date[];
  v_dia    date;
begin
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = new.funcionario_id
     where b.integracao_id = new.integracao_id
       and b.pessoa_externa = new.user_id_externo
       and b.origem = 'controlid_acesso'
       and (b.funcionario_id is null or b.funcionario_id = v_antigo)
       and b.funcionario_id is distinct from new.funcionario_id
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;

  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(v_antigo, v_dia, v_dia);
      perform public.ponto_apurar(new.funcionario_id, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_controlid_usuario() is '[interno] §7.8: vínculo Control iD → batidas de acesso e reapuração.';

drop trigger if exists ponto_vinculo_batidas on public.controlid_usuarios;
create trigger ponto_vinculo_batidas after update of funcionario_id on public.controlid_usuarios
  for each row when (old.funcionario_id is distinct from new.funcionario_id)
  execute function public.ponto_gatilho_controlid_usuario();
drop trigger if exists ponto_vinculo_batidas_ins on public.controlid_usuarios;
create trigger ponto_vinculo_batidas_ins after insert on public.controlid_usuarios
  for each row when (new.funcionario_id is not null)
  execute function public.ponto_gatilho_controlid_usuario();

create or replace function public.ponto_gatilho_funcionario_documentos()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_datas date[]; v_dia date;
begin
  if new.cpf is null and new.pis is null then return null; end if;
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = new.id
     where b.empresa_id = new.empresa_id
       and b.origem = 'controlid_rep'
       and b.funcionario_id is null
       and b.pessoa_externa is not null
       and b.pessoa_externa in (new.cpf, new.pis)
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;
  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(new.id, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_documentos() is '[interno] §7.8: CPF/PIS do funcionário → batidas REP sem vínculo.';

drop trigger if exists ponto_documentos on public.funcionarios;
create trigger ponto_documentos after insert or update of cpf, pis on public.funcionarios
  for each row execute function public.ponto_gatilho_funcionario_documentos();

create or replace function public.ponto_gatilho_funcionario_vinculo()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_atual date;
begin
  v_atual := public.dia_de_trabalho(public.agora(), new.empresa_id);
  perform public.ponto_apurar(new.id, v_atual - 93, v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_vinculo() is '[interno] §7.8: mudança de admissão/desligamento/ativo → reapura 93 dias.';

drop trigger if exists ponto_vinculo on public.funcionarios;
create trigger ponto_vinculo after update of data_admissao, data_desligamento, ativo on public.funcionarios
  for each row
  when (old.data_admissao is distinct from new.data_admissao
        or old.data_desligamento is distinct from new.data_desligamento
        or old.ativo is distinct from new.ativo)
  execute function public.ponto_gatilho_funcionario_vinculo();

create or replace function public.ponto_gatilho_funcionario_jornada()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_func   uuid;
  v_desde  date;
  v_empresa uuid;
  v_atual  date;
begin
  if tg_op = 'DELETE' then
    v_func := old.funcionario_id; v_desde := old.vigente_desde;
  elsif tg_op = 'UPDATE' then
    v_func := new.funcionario_id; v_desde := least(old.vigente_desde, new.vigente_desde);
    if old.funcionario_id is distinct from new.funcionario_id then
      select f.empresa_id into v_empresa from public.funcionarios f where f.id = old.funcionario_id;
      if v_empresa is not null then
        v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
        perform public.ponto_apurar(old.funcionario_id, greatest(old.vigente_desde, v_atual - 93), v_atual);
      end if;
    end if;
  else
    v_func := new.funcionario_id; v_desde := new.vigente_desde;
  end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = v_func;
  if v_empresa is null then return null; end if;
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
  perform public.ponto_apurar(v_func, greatest(v_desde, v_atual - 93), v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_jornada() is '[interno] §7.8: escala do funcionário mudou → reapura desde vigente_desde (máx. 93 dias).';

drop trigger if exists ponto_reapurar on public.funcionario_jornadas;
create trigger ponto_reapurar after insert or update or delete on public.funcionario_jornadas
  for each row execute function public.ponto_gatilho_funcionario_jornada();

create or replace function public.ponto_gatilho_jornada()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_jornada uuid;
  v_empresa uuid;
  v_atual   date;
  f         record;
begin
  if tg_table_name = 'jornadas' then
    v_jornada := coalesce(new.id, old.id);
  else
    v_jornada := coalesce(new.jornada_id, old.jornada_id);
  end if;
  select j.empresa_id into v_empresa from public.jornadas j where j.id = v_jornada;
  if v_empresa is null then return null; end if;
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
  for f in
    select distinct fj.funcionario_id from public.funcionario_jornadas fj
     where fj.jornada_id = v_jornada
  loop
    perform public.ponto_apurar(f.funcionario_id, v_atual - 31, v_atual);
  end loop;
  return null;
end $$;
comment on function public.ponto_gatilho_jornada() is '[interno] §7.8: jornada/jornada_dias mudou → reapura 31 dias dos funcionários dessa jornada.';

drop trigger if exists ponto_reapurar on public.jornada_dias;
create trigger ponto_reapurar after insert or update or delete on public.jornada_dias
  for each row execute function public.ponto_gatilho_jornada();
drop trigger if exists ponto_reapurar on public.jornadas;
create trigger ponto_reapurar after update of tolerancia_batida_minutos, tolerancia_diaria_minutos on public.jornadas
  for each row execute function public.ponto_gatilho_jornada();

-- Empresa: mudar fuso/virada/janela/alarme de atraso → reapura 31 dias.
create or replace function public.ponto_gatilho_empresa()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_atual date;
begin
  v_atual := public.dia_de_trabalho(public.agora(), new.id);
  perform public.ponto_apurar_empresa(new.id, v_atual - 31, v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_empresa() is '[interno] Parâmetros de ponto da empresa mudaram → reapura 31 dias.';

drop trigger if exists ponto_reapurar on public.empresas;
create trigger ponto_reapurar after update of fuso, virada_dia, ponto_janela_duplicada_minutos, ponto_alarme_atraso on public.empresas
  for each row
  when (old.fuso is distinct from new.fuso or old.virada_dia is distinct from new.virada_dia
        or old.ponto_janela_duplicada_minutos is distinct from new.ponto_janela_duplicada_minutos
        or old.ponto_alarme_atraso is distinct from new.ponto_alarme_atraso)
  execute function public.ponto_gatilho_empresa();

-- Fuso/virada mudou → data_trabalho das batidas precisa ser recalculada (antes da reapuração acima).
create or replace function public.ponto_gatilho_empresa_datas()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  -- o gatilho a_antes de ponto_batidas recalcula data_trabalho a partir da empresa já atualizada
  update public.ponto_batidas b
     set data_trabalho = b.data_trabalho
   where b.empresa_id = new.id
     and b.data_trabalho is distinct from ((b.instante at time zone new.fuso) - new.virada_dia)::date;
  return null;
end $$;
comment on function public.ponto_gatilho_empresa_datas() is '[interno] Recalcula data_trabalho das batidas quando fuso/virada mudam.';

drop trigger if exists a_ponto_datas on public.empresas;
create trigger a_ponto_datas after update of fuso, virada_dia on public.empresas
  for each row when (old.fuso is distinct from new.fuso or old.virada_dia is distinct from new.virada_dia)
  execute function public.ponto_gatilho_empresa_datas();

-- ============================================================ RPCs de leitura
create or replace function public.ponto_espelho(p_funcionario uuid, p_inicio date, p_fim date)
returns table (data date, dia_semana smallint, situacao text, encerrado boolean, abono_tipo text, jornada_nome text,
               previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int,
               batidas jsonb, alarmes jsonb, esperadas jsonb)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);

  return query
  select c.data, extract(dow from c.data)::smallint, c.situacao, c.encerrado, c.abono_tipo, c.jornada_nome,
         c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos, c.atraso_minutos, c.batidas,
         coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'tipo', a.tipo, 'batida_esperada', a.batida_esperada,
                                                       'status', a.status, 'detalhe', a.detalhe, 'justificativa', a.justificativa)
                                    order by a.horario_previsto nulls last, a.tipo, a.batida_esperada)
                     from public.ponto_alarmes a
                    where a.funcionario_id = p_funcionario and a.data = c.data
                      and a.status <> 'resolvido'), '[]'::jsonb),
         c.esperadas
    from generate_series(p_inicio, p_fim, interval '1 day') g
    cross join lateral public.ponto_calcular_dia(p_funcionario, g::date) c
   where not c.fora_do_vinculo
   order by c.data;
end $$;
comment on function public.ponto_espelho(uuid, date, date) is '[api] Espelho de ponto calculado ao vivo (máx. 62 dias). alarmes: abertos e justificados.';

-- Revisão 1: passou a devolver `esperadas` (antes o front recalculava a partir da jornada e errava em dia abonado).
-- Mudança de tipo de retorno exige drop (idempotente; os privilégios voltam na …0900_permissoes.sql).
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'ponto_dia_empresa'
                and pg_get_function_result(p.oid) not like '%esperadas jsonb%') then
    drop function public.ponto_dia_empresa(date, uuid);
  end if;
end $$;
create or replace function public.ponto_dia_empresa(p_data date default null, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, situacao text, encerrado boolean,
               previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int,
               batidas jsonb, alarmes_abertos int, esperadas jsonb)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_data date;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.dia_de_trabalho(public.agora(), v_empresa));
  return query
  select f.id, f.nome, f.cargo, c.situacao, c.encerrado, c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos,
         c.atraso_minutos, c.batidas,
         (select count(*)::int from public.ponto_alarmes a
           where a.funcionario_id = f.id and a.data = v_data and a.status = 'aberto'),
         c.esperadas
    from public.funcionarios f
    cross join lateral public.ponto_calcular_dia(f.id, v_data) c
   where f.empresa_id = v_empresa
     and not c.fora_do_vinculo
     and (f.ativo or jsonb_array_length(c.batidas) > 0)
   order by f.nome, f.id;
end $$;
comment on function public.ponto_dia_empresa(date, uuid) is '[api] Ponto do dia de todos os funcionários da empresa (ao vivo).';

-- ============================================================ RPCs de ação
create or replace function public.ponto_reapurar(p_inicio date, p_fim date, p_funcionario uuid default null,
                                                 p_empresa uuid default null)
returns integer language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
    if p_empresa is not null and p_empresa <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 93);
  if p_funcionario is not null then
    return public.ponto_apurar(p_funcionario, p_inicio, p_fim);
  end if;
  return public.ponto_apurar_empresa(v_empresa, p_inicio, p_fim);
end $$;
comment on function public.ponto_reapurar(date, date, uuid, uuid) is '[api] Recalcula o ponto (máx. 93 dias).';

create or replace function public.ponto_incluir_batida(p_funcionario uuid, p_instante timestamptz, p_motivo text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid; v_dia date;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if p_instante is null then raise exception 'Horário inválido' using errcode = '22023'; end if;
  if p_instante > public.agora() then raise exception 'Horário no futuro' using errcode = '22023'; end if;
  -- (revisão 2) batida de anos atrás (digitação errada, ex.: 1926) era aceita e gravada fora de qualquer apuração
  if p_instante < public.agora() - interval '366 days' then
    raise exception 'Horário muito antigo (máximo 1 ano)' using errcode = '22023';
  end if;

  insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo, criado_por)
  values (v_empresa, p_funcionario, 'manual', p_instante, btrim(p_motivo), auth.uid())
  returning id, data_trabalho into v_id, v_dia;

  insert into public.ponto_ajustes (empresa_id, funcionario_id, batida_id, acao, instante, motivo, feito_por, feito_por_nome, feito_em)
  values (v_empresa, p_funcionario, v_id, 'incluir', p_instante, btrim(p_motivo), auth.uid(), public.ponto_nome_autor(), public.agora());

  perform public.ponto_apurar(p_funcionario, v_dia, v_dia);
  return v_id;
end $$;
comment on function public.ponto_incluir_batida(uuid, timestamptz, text) is '[api] Inclui batida manual (auditada) e reapura o dia.';

create or replace function public.ponto_marcar_batida(p_batida uuid, p_motivo text, p_desconsiderar boolean)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare b record;
begin
  select * into b from public.ponto_batidas where id = p_batida;
  if not found then raise exception 'Batida não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(b.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if b.funcionario_id is null then
    raise exception 'Batida sem funcionário vinculado' using errcode = '22023';
  end if;

  update public.ponto_batidas
     set desconsiderada = p_desconsiderar,
         motivo = case when p_desconsiderar then btrim(p_motivo)
                       when origem = 'manual' then coalesce(
                         (select aj.motivo from public.ponto_ajustes aj
                           where aj.batida_id = p_batida and aj.acao = 'incluir' order by aj.feito_em limit 1), motivo)
                       else null end
   where id = p_batida;

  insert into public.ponto_ajustes (empresa_id, funcionario_id, batida_id, acao, instante, motivo, feito_por, feito_por_nome, feito_em)
  values (b.empresa_id, b.funcionario_id, b.id, case when p_desconsiderar then 'desconsiderar' else 'restaurar' end,
          b.instante, btrim(p_motivo), auth.uid(), public.ponto_nome_autor(), public.agora());

  perform public.ponto_apurar(b.funcionario_id, b.data_trabalho, b.data_trabalho);
end $$;
comment on function public.ponto_marcar_batida(uuid, text, boolean) is '[interno] Desconsidera/restaura batida com auditoria.';

create or replace function public.ponto_desconsiderar_batida(p_batida uuid, p_motivo text)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  select public.ponto_marcar_batida(p_batida, p_motivo, true)
$$;
comment on function public.ponto_desconsiderar_batida(uuid, text) is '[api] Desconsidera uma batida (auditado) e reapura.';

create or replace function public.ponto_restaurar_batida(p_batida uuid, p_motivo text)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  select public.ponto_marcar_batida(p_batida, p_motivo, false)
$$;
comment on function public.ponto_restaurar_batida(uuid, text) is '[api] Restaura uma batida desconsiderada (auditado) e reapura.';

create or replace function public.ponto_justificar_alarme(p_alarme uuid, p_justificativa text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_alarmes where id = p_alarme;
  if not found then raise exception 'Alarme não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_justificativa is null or btrim(p_justificativa) = '' then
    raise exception 'Informe a justificativa' using errcode = '22023';
  end if;
  update public.ponto_alarmes
     set status = 'justificado', justificativa = btrim(p_justificativa),
         justificado_por = auth.uid(), justificado_em = public.agora(),
         resolvido_em = null, resolvido_automaticamente = false
   where id = p_alarme;
  perform public.ponto_contar_alarmes(a.funcionario_id, a.data);
end $$;
comment on function public.ponto_justificar_alarme(uuid, text) is '[api] Justifica um alarme (não altera saldo).';

create or replace function public.ponto_reabrir_alarme(p_alarme uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_alarmes where id = p_alarme;
  if not found then raise exception 'Alarme não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  update public.ponto_alarmes
     set status = 'aberto', justificativa = null, justificado_por = null, justificado_em = null,
         resolvido_em = null, resolvido_automaticamente = false
   where id = p_alarme;
  -- se o alarme não é mais esperado, a apuração o resolve de novo automaticamente
  perform public.ponto_apurar(a.funcionario_id, a.data, a.data);
  perform public.ponto_contar_alarmes(a.funcionario_id, a.data);
end $$;
comment on function public.ponto_reabrir_alarme(uuid) is '[api] Reabre um alarme justificado.';

create or replace function public.ponto_abonar(p_inicio date, p_fim date, p_tipo text, p_motivo text default null,
                                               p_funcionario uuid default null, p_empresa uuid default null)
returns integer language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_dias int; v_falta date;
begin
  if p_funcionario is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
    if p_empresa is not null and p_empresa <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_tipo is null or p_tipo not in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro') then
    raise exception 'Tipo de abono inválido' using errcode = '22023';
  end if;
  if p_funcionario is not null and exists (
       select 1 from public.ponto_abonos a
        where a.funcionario_id = p_funcionario and a.data between p_inicio and p_fim and a.ocorrencia_id is not null) then
    raise exception 'Dia com suspensão: altere pela ocorrência' using errcode = '22023';
  end if;
  if p_funcionario is not null and exists (
       select 1 from public.ponto_abonos a
        where a.funcionario_id = p_funcionario and a.data between p_inicio and p_fim and a.escala_ajuste_id is not null) then
    raise exception 'Dia com férias na escala: altere pela escala' using errcode = '22023';
  end if;
  if p_funcionario is not null then
    select g::date into v_falta from generate_series(p_inicio, p_fim, interval '1 day') g
     where public.ponto_falta_do_dia(p_funcionario, g::date) is not null order by g limit 1;
    if v_falta is not null then
      raise exception 'Dia com falta em %: remova a falta antes', to_char(v_falta, 'DD/MM/YYYY') using errcode = '22023';
    end if;
  end if;

  insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por)
  select v_empresa, p_funcionario, g::date, p_tipo, nullif(btrim(p_motivo), ''), auth.uid()
    from generate_series(p_inicio, p_fim, interval '1 day') g
  on conflict on constraint ponto_abonos_uk do update
    set tipo = excluded.tipo, motivo = excluded.motivo, criado_por = excluded.criado_por, criado_em = now();
  v_dias := p_fim - p_inicio + 1;

  if p_funcionario is not null then
    perform public.ponto_apurar(p_funcionario, p_inicio, p_fim);
  else
    perform public.ponto_apurar_empresa(v_empresa, p_inicio, p_fim);
  end if;
  return v_dias;
end $$;
comment on function public.ponto_abonar(date, date, text, text, uuid, uuid) is '[api] Abona dias (upsert por dia) e reapura.';

create or replace function public.ponto_remover_abono(p_abono uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_abonos where id = p_abono;
  if not found then raise exception 'Abono não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if a.ocorrencia_id is not null then
    raise exception 'Dia com suspensão: altere pela ocorrência' using errcode = '22023';
  end if;
  if a.escala_ajuste_id is not null then
    raise exception 'Dia com férias na escala: altere pela escala' using errcode = '22023';
  end if;
  delete from public.ponto_abonos where id = p_abono;
  if a.funcionario_id is not null then
    perform public.ponto_apurar(a.funcionario_id, a.data, a.data);
  else
    perform public.ponto_apurar_empresa(a.empresa_id, a.data, a.data);
  end if;
end $$;
comment on function public.ponto_remover_abono(uuid) is '[api] Remove um abono e reapura.';

-- ============================================================ banco de horas (§7.5)
create or replace function public.banco_horas_calcular_saldo(p_funcionario uuid, p_ate date)
returns bigint language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_base bigint := 0; v_inicio date := '-infinity'; b record;
begin
  select l.data, l.minutos into b
    from public.banco_horas_lancamentos l
   where l.funcionario_id = p_funcionario and l.tipo = 'saldo_inicial' and l.data <= p_ate
   order by l.data desc
   limit 1;
  if found then v_base := b.minutos; v_inicio := b.data; end if;
  return v_base
    + coalesce((select sum(d.saldo_minutos) from public.ponto_dias d
                 where d.funcionario_id = p_funcionario and d.encerrado and d.data between v_inicio and p_ate), 0)
    + coalesce((select sum(l.minutos) from public.banco_horas_lancamentos l
                 where l.funcionario_id = p_funcionario and l.tipo <> 'saldo_inicial' and l.data between v_inicio and p_ate), 0);
end $$;
comment on function public.banco_horas_calcular_saldo(uuid, date) is '[interno] Saldo do banco de horas até a data (§7.5).';

create or replace function public.banco_horas_saldo(p_funcionario uuid, p_ate date default null)
returns bigint language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return public.banco_horas_calcular_saldo(p_funcionario,
           coalesce(p_ate, public.dia_de_trabalho(public.agora(), v_empresa) - 1));
end $$;
comment on function public.banco_horas_saldo(uuid, date) is '[api] Saldo do banco de horas (padrão: até ontem).';

create or replace function public.banco_horas_resumo(p_ate date default null, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, saldo_minutos bigint, saldo_mes_minutos bigint,
               ultimo_dia_apurado date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_ate date; v_mes date;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_ate := coalesce(p_ate, public.dia_de_trabalho(public.agora(), v_empresa) - 1);
  v_mes := date_trunc('month', v_ate)::date;
  return query
  select f.id, f.nome, f.cargo,
         public.banco_horas_calcular_saldo(f.id, v_ate),
         (select coalesce(sum(d.saldo_minutos), 0) from public.ponto_dias d
           where d.funcionario_id = f.id and d.encerrado and d.data between greatest(v_mes, r.inicio) and v_ate)
         + (select coalesce(sum(l.minutos), 0) from public.banco_horas_lancamentos l
             where l.funcionario_id = f.id and l.tipo <> 'saldo_inicial' and l.data between greatest(v_mes, r.inicio) and v_ate),
         (select max(d.data) from public.ponto_dias d where d.funcionario_id = f.id and d.encerrado)
    from public.funcionarios f
    cross join lateral (
      select coalesce((select max(l.data) from public.banco_horas_lancamentos l
                        where l.funcionario_id = f.id and l.tipo = 'saldo_inicial' and l.data <= v_ate),
                      '-infinity'::date) as inicio) r
   where f.empresa_id = v_empresa and f.ativo
   order by f.nome, f.id;
end $$;
comment on function public.banco_horas_resumo(date, uuid) is '[api] Saldo do banco de horas por funcionário ativo.';

create or replace function public.banco_horas_extrato(p_funcionario uuid, p_inicio date, p_fim date)
returns table (data date, tipo text, descricao text, minutos int, saldo_acumulado bigint, referencia_id uuid)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid;
  v_saldo   bigint;
  r         record;
  v_rotulos constant jsonb := '{"completo":"Completo","incompleto":"Incompleto","ausente":"Ausente","folga":"Folga",
     "sem_escala":"Sem escala","abonado":"Abonado","suspenso":"Suspenso","em_andamento":"Em andamento",
     "falta_justificada":"Falta justificada","falta_injustificada":"Falta injustificada"}'::jsonb;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);

  v_saldo := public.banco_horas_calcular_saldo(p_funcionario, p_inicio - 1);
  data := p_inicio - 1; tipo := 'saldo_anterior'; descricao := 'Saldo anterior';
  minutos := v_saldo::int; saldo_acumulado := v_saldo; referencia_id := null;
  return next;

  for r in
    select x.* from (
      select d.data, 1 as ordem, 'dia'::text as tipo,
             (v_rotulos ->> d.situacao)
               || case when d.abono_tipo is not null then ' (' || d.abono_tipo || ')' else '' end
               || ' — trabalhado ' || public.ponto_fmt_minutos(d.trabalhado_minutos)
               || case when d.previsto_minutos > 0 then ' de ' || public.ponto_fmt_minutos(d.previsto_minutos) else '' end
               as descricao,
             d.saldo_minutos as minutos, null::uuid as referencia_id, null::timestamptz as criado_em
        from public.ponto_dias d
       where d.funcionario_id = p_funcionario and d.encerrado and d.data between p_inicio and p_fim
         and (d.saldo_minutos <> 0 or d.situacao <> 'folga')
      union all
      select l.data, case when l.tipo = 'saldo_inicial' then 0 else 2 end, l.tipo, l.motivo, l.minutos, l.id, l.criado_em
        from public.banco_horas_lancamentos l
       where l.funcionario_id = p_funcionario and l.data between p_inicio and p_fim
    ) x
    order by x.data, x.ordem, x.criado_em, x.referencia_id
  loop
    if r.tipo = 'saldo_inicial' then v_saldo := r.minutos; else v_saldo := v_saldo + r.minutos; end if;
    data := r.data; tipo := r.tipo; descricao := r.descricao; minutos := r.minutos;
    saldo_acumulado := v_saldo; referencia_id := r.referencia_id;
    return next;
  end loop;
end $$;
comment on function public.banco_horas_extrato(uuid, date, date) is '[api] Extrato do banco de horas (máx. 366 dias).';

create or replace function public.banco_horas_lancar(p_funcionario uuid, p_data date, p_tipo text, p_minutos integer,
                                                     p_motivo text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('saldo_inicial', 'ajuste', 'compensacao', 'pagamento') then
    raise exception 'Tipo de lançamento inválido' using errcode = '22023';
  end if;
  if p_tipo = 'saldo_inicial' and not public.pode_administrar(v_empresa) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if p_minutos is null then raise exception 'Informe os minutos' using errcode = '22023'; end if;
  -- (revisão 2) limite de sanidade: ±100.000 min (≈ 1.666 h); 2.147.483.647 min era aceito e distorcia o saldo
  if abs(p_minutos::bigint) > 100000 then
    raise exception 'Minutos fora do limite (máximo 100.000)' using errcode = '22023';
  end if;
  if p_tipo = 'saldo_inicial'
     and exists (select 1 from public.banco_horas_lancamentos
                  where funcionario_id = p_funcionario and data = p_data and tipo = 'saldo_inicial') then
    raise exception 'Já existe saldo inicial nesta data' using errcode = '23505';
  end if;

  insert into public.banco_horas_lancamentos (empresa_id, funcionario_id, data, tipo, minutos, motivo, criado_por, criado_por_nome)
  values (v_empresa, p_funcionario, p_data, p_tipo, p_minutos, btrim(p_motivo), auth.uid(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.banco_horas_lancar(uuid, date, text, integer, text) is '[api] Lança ajuste/compensação/pagamento (saldo inicial só administrador).';

create or replace function public.banco_horas_excluir_lancamento(p_lancamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select l.empresa_id into v_empresa from public.banco_horas_lancamentos l where l.id = p_lancamento;
  if v_empresa is null then raise exception 'Lançamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_administrar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  delete from public.banco_horas_lancamentos where id = p_lancamento;
end $$;
comment on function public.banco_horas_excluir_lancamento(uuid) is '[api] Exclui lançamento do banco de horas (administrador).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000200_ponto.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000210_zig.sql
-- =====================================================================================================
-- 20261006000210_zig.sql — backend-2
-- Zig: lojas, itens vendidos (saída de produtos), faturamento, bandeiras, compradores e RPCs de vendas.
-- Contrato: §6 (DDL), §8 (regras), §10.5 (RPCs). Idempotente.
-- =====================================================================================================

-- ===================================================================== zig_lojas
create table if not exists public.zig_lojas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  integracao_id    uuid not null references public.integracoes (id) on delete cascade,
  loja_id_externo  text not null,
  nome             text not null,
  sincronizar      boolean not null default true,
  visto_em         timestamptz not null default now(),
  criado_em        timestamptz not null default now(),
  unique (empresa_id, loja_id_externo)
);
create index if not exists zig_lojas_integracao_idx on public.zig_lojas (integracao_id);
comment on table public.zig_lojas is '[api:crud] Lojas da Zig. authenticated (administrador) só altera `sincronizar`.';

-- ============================================================== zig_vendas_itens
create table if not exists public.zig_vendas_itens (
  id                 bigint generated always as identity primary key,
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo    text not null,
  data_operacao      date not null,
  transaction_id     text not null,
  transaction_date   timestamptz,
  event_id           text,
  event_date         date,
  invoice_id         text,
  product_id         text,
  product_sku        text,
  product_name       text,
  product_category   text,
  tipo               text not null check (tipo in ('Normal', 'Couvert', 'ZigCard', 'Entrance', 'Tip', 'Outro')),
  tipo_original      text,
  unit_value         bigint not null default 0,
  quantidade         numeric(14,3) not null default 0,
  fractional_amount  numeric(14,3),
  fraction_unit      text,
  discount_value     bigint not null default 0,
  valor_total        bigint not null,
  employee_name      text,
  additions          jsonb not null default '[]'::jsonb,
  importado_em       timestamptz not null default now()
);
create index if not exists zig_vendas_itens_dia_idx on public.zig_vendas_itens (empresa_id, data_operacao, loja_id_externo);
create index if not exists zig_vendas_itens_garcom_idx on public.zig_vendas_itens (empresa_id, lower(btrim(employee_name)));
comment on table public.zig_vendas_itens is '[api:leitura] Itens de /erp/saida-produtos (centavos). Tip = serviço.';

-- =============================================================== zig_faturamento
create table if not exists public.zig_faturamento (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  event_date       date,
  payment_id       int not null,
  payment_name     text not null,
  valor            bigint not null,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_faturamento_dia_idx on public.zig_faturamento (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_faturamento is '[api:leitura] Faturamento por forma de pagamento (/erp/faturamento), centavos.';

create table if not exists public.zig_faturamento_bandeiras (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  payment_id       int not null,
  payment_name     text,
  card_brand       text,
  valor            bigint not null,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_bandeiras_dia_idx on public.zig_faturamento_bandeiras (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_faturamento_bandeiras is '[api:leitura] Faturamento por bandeira (/erp/faturamento/detalhesMaquinaIntegrada).';

create table if not exists public.zig_compradores (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  transaction_id   text not null,
  products_value   bigint not null default 0,
  tip_value        bigint not null default 0,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_compradores_dia_idx on public.zig_compradores (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_compradores is '[api:leitura] /erp/compradores sem dados pessoais (LGPD): só valores por transação.';

-- ========================================================================= RLS
alter table public.zig_lojas enable row level security;
alter table public.zig_vendas_itens enable row level security;
alter table public.zig_faturamento enable row level security;
alter table public.zig_faturamento_bandeiras enable row level security;
alter table public.zig_compradores enable row level security;

drop policy if exists zig_lojas_ler on public.zig_lojas;
create policy zig_lojas_ler on public.zig_lojas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_lojas_alterar on public.zig_lojas;
create policy zig_lojas_alterar on public.zig_lojas for update to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()))
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));
drop policy if exists zig_vendas_itens_ler on public.zig_vendas_itens;
create policy zig_vendas_itens_ler on public.zig_vendas_itens for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_faturamento_ler on public.zig_faturamento;
create policy zig_faturamento_ler on public.zig_faturamento for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_bandeiras_ler on public.zig_faturamento_bandeiras;
create policy zig_bandeiras_ler on public.zig_faturamento_bandeiras for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_compradores_ler on public.zig_compradores;
create policy zig_compradores_ler on public.zig_compradores for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
create or replace function public.zig_lojas_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_tipo text;
begin
  if tg_op = 'INSERT' then
    select i.empresa_id, i.tipo into v_empresa, v_tipo from public.integracoes i where i.id = new.integracao_id;
    if v_empresa is null then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
    if v_tipo <> 'zig' then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
    new.empresa_id := v_empresa;
    return new;
  end if;
  -- UPDATE vindo do front (papel authenticated): só `sincronizar` muda.
  if coalesce(nullif(current_setting('role', true), ''), 'none') = 'authenticated' or auth.uid() is not null then
    new.id := old.id; new.empresa_id := old.empresa_id; new.integracao_id := old.integracao_id;
    new.loja_id_externo := old.loja_id_externo; new.nome := old.nome; new.visto_em := old.visto_em;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.zig_lojas_antes() is '[interno] Gatilho de zig_lojas: empresa da integração; authenticated só muda sincronizar.';

drop trigger if exists a_antes on public.zig_lojas;
create trigger a_antes before insert or update on public.zig_lojas
  for each row execute function public.zig_lojas_antes();

-- ================================================================ RPCs de vendas
create or replace function public.vendas_resumo(p_inicio date, p_fim date, p_loja text default null,
                                                p_empresa uuid default null)
returns table (faturamento bigint, vendas bigint, servico bigint, descontos bigint, transacoes bigint,
               servico_compradores bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select
    coalesce((select sum(z.valor) from public.zig_faturamento z
               where z.empresa_id = v_empresa and z.data_operacao between p_inicio and p_fim
                 and (p_loja is null or z.loja_id_externo = p_loja)), 0)::bigint,
    coalesce(sum(i.valor_total) filter (where i.tipo <> 'Tip'), 0)::bigint,
    coalesce(sum(i.valor_total) filter (where i.tipo = 'Tip'), 0)::bigint,
    coalesce(sum(i.discount_value), 0)::bigint,
    count(distinct i.transaction_id)::bigint,
    coalesce((select sum(c.tip_value) from public.zig_compradores c
               where c.empresa_id = v_empresa and c.data_operacao between p_inicio and p_fim
                 and (p_loja is null or c.loja_id_externo = p_loja)), 0)::bigint
    from public.zig_vendas_itens i
   where i.empresa_id = v_empresa and i.data_operacao between p_inicio and p_fim
     and (p_loja is null or i.loja_id_externo = p_loja);
end $$;
comment on function public.vendas_resumo(date, date, text, uuid) is '[api] Resumo de vendas do período (centavos).';

create or replace function public.vendas_faturamento_por_dia(p_inicio date, p_fim date, p_loja text default null,
                                                             p_empresa uuid default null)
returns table (data date, valor bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select g::date,
         coalesce((select sum(z.valor) from public.zig_faturamento z
                    where z.empresa_id = v_empresa and z.data_operacao = g::date
                      and (p_loja is null or z.loja_id_externo = p_loja)), 0)::bigint
    from generate_series(p_inicio, p_fim, interval '1 day') g
   order by 1;
end $$;
comment on function public.vendas_faturamento_por_dia(date, date, text, uuid) is '[api] Faturamento por dia (dias sem dado = 0).';

create or replace function public.vendas_faturamento_por_forma(p_inicio date, p_fim date, p_loja text default null,
                                                               p_empresa uuid default null)
returns table (payment_id int, payment_name text, valor bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select z.payment_id, mode() within group (order by z.payment_name), sum(z.valor)::bigint
    from public.zig_faturamento z
   where z.empresa_id = v_empresa and z.data_operacao between p_inicio and p_fim
     and (p_loja is null or z.loja_id_externo = p_loja)
   group by z.payment_id
   order by 3 desc, 1;
end $$;
comment on function public.vendas_faturamento_por_forma(date, date, text, uuid) is '[api] Faturamento por forma de pagamento.';

create or replace function public.vendas_por_garcom(p_inicio date, p_fim date, p_loja text default null,
                                                    p_empresa uuid default null)
returns table (employee_name text, funcionario_id uuid, funcionario_nome text, quantidade numeric, valor_vendas bigint,
               valor_servico bigint, transacoes bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  with g as (
    select nullif(lower(btrim(i.employee_name)), '') as chave,
           mode() within group (order by nullif(btrim(i.employee_name), '')) as nome,
           coalesce(sum(i.quantidade) filter (where i.tipo <> 'Tip'), 0) as qtd,
           coalesce(sum(i.valor_total) filter (where i.tipo <> 'Tip'), 0)::bigint as vendas,
           coalesce(sum(i.valor_total) filter (where i.tipo = 'Tip'), 0)::bigint as servico,
           count(distinct i.transaction_id)::bigint as trans
      from public.zig_vendas_itens i
     where i.empresa_id = v_empresa and i.data_operacao between p_inicio and p_fim
       and (p_loja is null or i.loja_id_externo = p_loja)
     group by 1
  )
  select g.nome, f.id, f.nome, g.qtd, g.vendas, g.servico, g.trans
    from g
    left join public.funcionarios f
      on g.chave is not null and f.empresa_id = v_empresa and lower(btrim(f.zig_employee_name)) = g.chave
   order by g.vendas desc, g.nome nulls last;
end $$;
comment on function public.vendas_por_garcom(date, date, text, uuid) is '[api] Vendas e serviço por garçom (employeeName da Zig).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000210_zig.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000220_comissoes.sql
-- =====================================================================================================
-- 20261006000220_comissoes.sql — backend-2
-- Comissão: serviço (Tips da Zig) − retenção = base; rateio por pontos com maior resto; rascunho → fechado (imutável).
-- Contrato: §6 (DDL), §9 (regras), §10.6 (RPCs); adendo extras v2 §E.3 (rateio diário, extras). Idempotente.
-- (v3) comissao_calcular, comissao_fechar e comissao_detalhe foram para …0290_comissao_presenca.sql.
-- =====================================================================================================

create table if not exists public.comissao_fechamentos (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null,
  data_inicio                 date not null,
  data_fim                    date not null,
  loja_id_externo             text,
  status                      text not null default 'rascunho' check (status in ('rascunho', 'fechado')),
  servico_zig_centavos        bigint not null default 0,
  servico_ajuste_centavos     bigint not null default 0,
  servico_bruto_centavos      bigint not null default 0,
  percentual_retencao         numeric(5,2) not null check (percentual_retencao between 0 and 100),
  retencao_centavos           bigint not null default 0,
  base_distribuivel_centavos  bigint not null default 0,
  proporcional_dias           boolean not null default false,
  dias_periodo                int not null default 0,
  soma_pontos_efetivos        numeric(18,6) not null default 0,
  valor_ponto_centavos        numeric(18,6),
  observacoes                 text,
  criado_por                  uuid references public.perfis (id) on delete set null,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  calculado_em                timestamptz,
  fechado_por                 uuid references public.perfis (id) on delete set null,
  fechado_em                  timestamptz,
  constraint comissao_periodo check (data_fim >= data_inicio and data_fim - data_inicio <= 92)
);
create index if not exists comissao_fechamentos_empresa_idx on public.comissao_fechamentos (empresa_id, data_inicio desc);
create index if not exists comissao_fechamentos_criado_por_idx on public.comissao_fechamentos (criado_por);
create index if not exists comissao_fechamentos_fechado_por_idx on public.comissao_fechamentos (fechado_por);
comment on table public.comissao_fechamentos is '[api:leitura] Fechamentos de comissão (rascunho → fechado, imutável).';

create table if not exists public.comissao_itens (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,
  fechamento_id     uuid not null references public.comissao_fechamentos (id) on delete cascade,
  funcionario_id    uuid references public.funcionarios (id) on delete set null,
  funcionario_nome  text not null,
  cargo             text,
  incluido          boolean not null default true,
  pontos            numeric(8,2) not null check (pontos >= 0),
  dias_trabalhados  int not null default 0,
  pontos_efetivos   numeric(18,6) not null default 0,
  valor_centavos    bigint not null default 0,
  criado_em         timestamptz not null default now(),
  unique (fechamento_id, funcionario_id)
);
create index if not exists comissao_itens_empresa_idx on public.comissao_itens (empresa_id);
create index if not exists comissao_itens_funcionario_idx on public.comissao_itens (funcionario_id);
comment on table public.comissao_itens is '[api:leitura] Itens (participantes) de um fechamento de comissão.';

-- ================================================================ adendo extras v2 (E.3): rateio diário
-- Fechamentos existentes ficam 'periodo' (coluna criada com esse default); novos nascem 'diario'.
alter table public.comissao_fechamentos add column if not exists modo_rateio text not null default 'periodo';
alter table public.comissao_fechamentos alter column modo_rateio set default 'diario';
alter table public.comissao_fechamentos drop constraint if exists comissao_fechamentos_modo_rateio_check;
alter table public.comissao_fechamentos add constraint comissao_fechamentos_modo_rateio_check
  check (modo_rateio in ('diario', 'periodo'));
alter table public.comissao_fechamentos add column if not exists dias_sem_presenca int not null default 0;
alter table public.comissao_fechamentos add column if not exists dias_sem_participantes int not null default 0;

-- Participante = funcionário OU extra (freela). Nome/cargo do participante: snapshot em funcionario_nome/cargo.
-- FK de extra_id → extras e o check de participante ficam em …0260_extras.sql (a tabela extras nasce lá).
alter table public.comissao_itens add column if not exists tipo text not null default 'funcionario';
alter table public.comissao_itens drop constraint if exists comissao_itens_tipo_check;
alter table public.comissao_itens add constraint comissao_itens_tipo_check check (tipo in ('funcionario', 'extra'));
alter table public.comissao_itens add column if not exists extra_id uuid;
alter table public.comissao_itens add column if not exists dias_presentes int not null default 0;
alter table public.comissao_itens add column if not exists pontos_manual boolean not null default false;
create unique index if not exists comissao_itens_extra_uk on public.comissao_itens (fechamento_id, extra_id);
create index if not exists comissao_itens_extra_idx on public.comissao_itens (extra_id);

-- v1 (removido): pontos extras de comissão. DROPs idempotentes para quem já rodou a v1.
drop table if exists public.comissao_pontos_extras cascade;
alter table public.comissao_itens drop column if exists pontos_extras;

-- Detalhe do rateio diário (só no modo 'diario'; recalcular o rascunho apaga e regrava).
create table if not exists public.comissao_rateio_dias (
  fechamento_id           uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id              uuid not null references public.empresas (id) on delete cascade,
  data                    date not null,
  servico_zig_centavos    bigint not null default 0,
  ajuste_centavos         bigint not null default 0,
  servico_bruto_centavos  bigint not null default 0,
  retencao_centavos       bigint not null default 0,
  base_centavos           bigint not null default 0,
  soma_pontos             numeric(18,2) not null default 0,
  participantes           int not null default 0,
  sem_presenca            boolean not null default false,
  sem_participantes       boolean not null default false,
  primary key (fechamento_id, data)
);
create index if not exists comissao_rateio_dias_empresa_idx on public.comissao_rateio_dias (empresa_id, data);
comment on table public.comissao_rateio_dias is '[api:leitura] Rateio diário da comissão: serviço, ajuste, retenção e base de cada dia.';

create table if not exists public.comissao_rateio_itens_dia (
  item_id         uuid not null references public.comissao_itens (id) on delete cascade,
  fechamento_id   uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  data            date not null,
  pontos          numeric(8,2) not null,
  valor_centavos  bigint not null default 0,
  fallback        boolean not null default false,
  primary key (item_id, data)
);
create index if not exists comissao_rateio_itens_dia_fechamento_idx on public.comissao_rateio_itens_dia (fechamento_id, data);
create index if not exists comissao_rateio_itens_dia_empresa_idx on public.comissao_rateio_itens_dia (empresa_id, data);
comment on table public.comissao_rateio_itens_dia is '[api:leitura] Rateio diário da comissão: pontos e valor de cada participante em cada dia.';

alter table public.comissao_fechamentos enable row level security;
alter table public.comissao_itens enable row level security;
drop policy if exists comissao_fechamentos_ler on public.comissao_fechamentos;
create policy comissao_fechamentos_ler on public.comissao_fechamentos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists comissao_itens_ler on public.comissao_itens;
create policy comissao_itens_ler on public.comissao_itens for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
alter table public.comissao_rateio_dias enable row level security;
alter table public.comissao_rateio_itens_dia enable row level security;
drop policy if exists comissao_rateio_dias_ler on public.comissao_rateio_dias;
create policy comissao_rateio_dias_ler on public.comissao_rateio_dias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists comissao_rateio_itens_dia_ler on public.comissao_rateio_itens_dia;
create policy comissao_rateio_itens_dia_ler on public.comissao_rateio_itens_dia for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
-- Em cascata (pg_trigger_depth() > 1) só passa: exclusão quando a empresa/fechamento já não existe,
-- ou UPDATE que apenas anula FKs (funcionário/perfil excluído → on delete set null).
create or replace function public.comissao_so_anula_fks(p_old jsonb, p_new jsonb, p_fks text[])
returns boolean language sql immutable set search_path = public, extensions, pg_temp as $$
  select not exists (
    select 1 from jsonb_each(p_new) n
     where n.key <> 'atualizado_em'
       and n.value is distinct from p_old -> n.key
       and not (n.key = any (p_fks) and n.value = 'null'::jsonb))
$$;
comment on function public.comissao_so_anula_fks(jsonb, jsonb, text[]) is '[interno] UPDATE só anula FKs?';

create or replace function public.comissao_fechamentos_protecao()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;
  if old.status = 'fechado' then
    if tg_op = 'DELETE' and pg_trigger_depth() > 1
       and not exists (select 1 from public.empresas e where e.id = old.empresa_id) then
      return old;
    end if;
    if tg_op = 'UPDATE' and pg_trigger_depth() > 1
       and public.comissao_so_anula_fks(to_jsonb(old), to_jsonb(new), array['criado_por', 'fechado_por']) then
      return new;
    end if;
    raise exception 'Fechamento já está fechado' using errcode = '22023';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.atualizado_em := now();
  return new;
end $$;
comment on function public.comissao_fechamentos_protecao() is '[interno] Fechamento fechado é imutável (nem o master altera).';

drop trigger if exists a_protecao on public.comissao_fechamentos;
create trigger a_protecao before insert or update or delete on public.comissao_fechamentos
  for each row execute function public.comissao_fechamentos_protecao();

create or replace function public.comissao_itens_protecao()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_status text; v_empresa uuid; v_fech uuid;
begin
  v_fech := case when tg_op = 'DELETE' then old.fechamento_id else new.fechamento_id end;
  select f.status, f.empresa_id into v_status, v_empresa from public.comissao_fechamentos f where f.id = v_fech;
  if tg_op = 'INSERT' then
    if v_empresa is null then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
    if v_status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
    new.empresa_id := v_empresa;
    return new;
  end if;
  if tg_op = 'UPDATE' and old.fechamento_id is distinct from new.fechamento_id then
    raise exception 'Item não pode mudar de fechamento' using errcode = '22023';
  end if;
  if v_status = 'fechado' then
    if tg_op = 'DELETE' and pg_trigger_depth() > 1
       and not exists (select 1 from public.empresas e where e.id = old.empresa_id) then
      return old;
    end if;
    if tg_op = 'UPDATE' and pg_trigger_depth() > 1
       and public.comissao_so_anula_fks(to_jsonb(old), to_jsonb(new), array['funcionario_id', 'extra_id']) then
      return new;
    end if;
    raise exception 'Fechamento já está fechado' using errcode = '22023';
  end if;
  -- fechamento inexistente (exclusão em cascata) ou rascunho: segue
  if tg_op = 'DELETE' then return old; end if;
  new.empresa_id := coalesce(v_empresa, old.empresa_id);
  return new;
end $$;
comment on function public.comissao_itens_protecao() is '[interno] Itens de fechamento fechado são imutáveis; empresa_id do fechamento.';

drop trigger if exists a_protecao on public.comissao_itens;
create trigger a_protecao before insert or update or delete on public.comissao_itens
  for each row execute function public.comissao_itens_protecao();

-- Detalhe do rateio: segue o status do fechamento (fechado = imutável); empresa_id do fechamento.
create or replace function public.comissao_rateio_protecao()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_status text; v_empresa uuid; v_fech uuid;
begin
  v_fech := case when tg_op = 'DELETE' then old.fechamento_id else new.fechamento_id end;
  select f.status, f.empresa_id into v_status, v_empresa from public.comissao_fechamentos f where f.id = v_fech;
  if tg_op = 'INSERT' then
    if v_empresa is null then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
    if v_status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
    new.empresa_id := v_empresa;
    return new;
  end if;
  if tg_op = 'UPDATE' and old.fechamento_id is distinct from new.fechamento_id then
    raise exception 'Item não pode mudar de fechamento' using errcode = '22023';
  end if;
  if v_status = 'fechado' then
    if tg_op = 'DELETE' and pg_trigger_depth() > 1
       and not exists (select 1 from public.empresas e where e.id = old.empresa_id) then
      return old;
    end if;
    raise exception 'Fechamento já está fechado' using errcode = '22023';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.empresa_id := coalesce(v_empresa, old.empresa_id);
  return new;
end $$;
comment on function public.comissao_rateio_protecao() is '[interno] Detalhe do rateio de fechamento fechado é imutável.';

drop trigger if exists a_protecao on public.comissao_rateio_dias;
create trigger a_protecao before insert or update or delete on public.comissao_rateio_dias
  for each row execute function public.comissao_rateio_protecao();
drop trigger if exists a_protecao on public.comissao_rateio_itens_dia;
create trigger a_protecao before insert or update or delete on public.comissao_rateio_itens_dia
  for each row execute function public.comissao_rateio_protecao();

-- ================================================================ cálculo (§9)
create or replace function public.comissao_pontos_vigentes(p_funcionario uuid, p_data date)
returns numeric language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(
    (select fp.pontos from public.funcionario_pontos fp
      where fp.funcionario_id = p_funcionario and fp.vigente_desde <= p_data order by fp.vigente_desde desc limit 1),
    (select fp.pontos from public.funcionario_pontos fp
      where fp.funcionario_id = p_funcionario order by fp.vigente_desde limit 1),
    (select f.pontos_comissao from public.funcionarios f where f.id = p_funcionario))
$$;
comment on function public.comissao_pontos_vigentes(uuid, date) is '[interno] Mesma regra de pontos_vigentes (§5), sem checagem de papel.';

-- comissao_calcular (§9 / adendo E.3 / presença v3 §E.7) está em …0290_comissao_presenca.sql (usa faltas e escala).

-- Carrega o fechamento e checa permissão de operação (G A M) e status rascunho.
create or replace function public.comissao_rascunho_para_editar(p_fechamento uuid)
returns public.comissao_fechamentos language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  return fc;
end $$;
comment on function public.comissao_rascunho_para_editar(uuid) is '[interno] Fechamento em rascunho editável pelo usuário?';

-- ================================================================ RPCs
-- assinaturas antigas (v1) ganharam p_modo_rateio: remove para não haver sobrecarga ambígua no PostgREST
drop function if exists public.comissao_criar_fechamento(date, date, text, text, boolean, uuid);
drop function if exists public.comissao_atualizar_fechamento(uuid, text, bigint, numeric, boolean, text);

create or replace function public.comissao_criar_fechamento(p_data_inicio date, p_data_fim date, p_titulo text default null,
                                                            p_loja text default null, p_proporcional_dias boolean default false,
                                                            p_empresa uuid default null, p_modo_rateio text default 'diario')
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid; v_pct numeric;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_data_inicio, p_data_fim, 93);
  p_modo_rateio := coalesce(p_modo_rateio, 'diario');
  if p_modo_rateio not in ('diario', 'periodo') then raise exception 'Modo de rateio inválido' using errcode = '22023'; end if;
  p_loja := nullif(btrim(p_loja), '');
  if p_loja is not null and not exists (select 1 from public.zig_lojas l
                                         where l.empresa_id = v_empresa and l.loja_id_externo = p_loja) then
    raise exception 'Loja não encontrada' using errcode = 'P0002';
  end if;
  select e.comissao_percentual_retencao into v_pct from public.empresas e where e.id = v_empresa;

  insert into public.comissao_fechamentos (empresa_id, titulo, data_inicio, data_fim, loja_id_externo, percentual_retencao,
                                           proporcional_dias, modo_rateio, criado_por)
  values (v_empresa,
          coalesce(nullif(btrim(p_titulo), ''),
                   'Comissão ' || to_char(p_data_inicio, 'DD/MM') || ' a ' || to_char(p_data_fim, 'DD/MM/YYYY')),
          p_data_inicio, p_data_fim, p_loja, coalesce(v_pct, 20), coalesce(p_proporcional_dias, false), p_modo_rateio, auth.uid())
  returning id into v_id;

  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, pontos)
  select v_empresa, v_id, f.id, f.nome, f.cargo, pv.pontos
    from public.funcionarios f
    cross join lateral (select public.comissao_pontos_vigentes(f.id, p_data_fim) as pontos) pv
   where f.empresa_id = v_empresa and f.ativo and f.participa_comissao
     and (f.data_admissao is null or f.data_admissao <= p_data_fim)
     and (f.data_desligamento is null or f.data_desligamento >= p_data_inicio)
     and pv.pontos > 0;

  perform public.comissao_calcular(v_id);
  return v_id;
end $$;
comment on function public.comissao_criar_fechamento(date, date, text, text, boolean, uuid, text) is
  '[api] Cria rascunho de comissão (modo diário ou período) com funcionários e extras do período e calcula.';

create or replace function public.comissao_atualizar_fechamento(p_fechamento uuid, p_titulo text, p_servico_ajuste_centavos bigint,
                                                                p_percentual_retencao numeric, p_proporcional_dias boolean,
                                                                p_observacoes text, p_modo_rateio text default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  if p_percentual_retencao is not null and (p_percentual_retencao < 0 or p_percentual_retencao > 100) then
    raise exception 'Percentual de retenção inválido' using errcode = '22023';
  end if;
  if p_modo_rateio is not null and p_modo_rateio not in ('diario', 'periodo') then
    raise exception 'Modo de rateio inválido' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set titulo = coalesce(nullif(btrim(p_titulo), ''), titulo),
         servico_ajuste_centavos = coalesce(p_servico_ajuste_centavos, servico_ajuste_centavos),
         percentual_retencao = coalesce(p_percentual_retencao, percentual_retencao),
         proporcional_dias = coalesce(p_proporcional_dias, proporcional_dias),
         modo_rateio = coalesce(p_modo_rateio, modo_rateio),
         observacoes = nullif(btrim(p_observacoes), '')
   where id = p_fechamento;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_atualizar_fechamento(uuid, text, bigint, numeric, boolean, text, text) is
  '[api] Edita parâmetros do rascunho (inclusive o modo de rateio) e recalcula.';

create or replace function public.comissao_definir_item(p_fechamento uuid, p_funcionario uuid, p_pontos numeric,
                                                        p_incluido boolean default true)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos; f record; v_pontos numeric;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  select * into f from public.funcionarios where id = p_funcionario;
  if not found then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if f.empresa_id <> fc.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  v_pontos := coalesce(p_pontos, public.comissao_pontos_vigentes(f.id, fc.data_fim));
  if v_pontos < 0 or v_pontos > 999999.99 then raise exception 'Pontos inválidos' using errcode = '22023'; end if;

  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, incluido, pontos, pontos_manual)
  values (fc.empresa_id, p_fechamento, f.id, f.nome, f.cargo, coalesce(p_incluido, true), v_pontos, p_pontos is not null)
  on conflict (fechamento_id, funcionario_id) do update
    set funcionario_nome = excluded.funcionario_nome, cargo = excluded.cargo,
        incluido = excluded.incluido, pontos = excluded.pontos, pontos_manual = excluded.pontos_manual;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_definir_item(uuid, uuid, numeric, boolean) is
  '[api] Inclui/atualiza funcionário participante (p_pontos null = automático) e recalcula.';

create or replace function public.comissao_definir_extra(p_fechamento uuid, p_extra uuid, p_incluido boolean)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos; x record;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  select * into x from public.extras where id = p_extra;
  if not found then raise exception 'Extra não encontrado' using errcode = 'P0002'; end if;
  if x.empresa_id <> fc.empresa_id then raise exception 'Extra de outra empresa' using errcode = '22023'; end if;
  if not exists (select 1 from public.diarias d where d.extra_id = x.id and d.data between fc.data_inicio and fc.data_fim) then
    if coalesce(p_incluido, true) then
      raise exception 'Extra sem dias lançados no período' using errcode = '22023';
    end if;
    perform public.comissao_calcular(p_fechamento);
    return;
  end if;
  insert into public.comissao_itens (empresa_id, fechamento_id, tipo, extra_id, funcionario_nome, cargo, incluido, pontos)
  values (fc.empresa_id, p_fechamento, 'extra', x.id, x.nome, x.funcao, coalesce(p_incluido, true), x.pontos_padrao)
  on conflict (fechamento_id, extra_id) do update set incluido = excluded.incluido;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_definir_extra(uuid, uuid, boolean) is '[api] Inclui/tira um extra (freela) do rascunho e recalcula.';

create or replace function public.comissao_remover_item(p_fechamento uuid, p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  delete from public.comissao_itens where fechamento_id = p_fechamento and funcionario_id = p_funcionario;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_remover_item(uuid, uuid) is '[api] Remove funcionário participante do rascunho e recalcula.';

create or replace function public.comissao_recalcular(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_recalcular(uuid) is '[api] Relê serviço, presença e extras e recalcula o rascunho.';

-- comissao_fechar: em …0290_comissao_presenca.sql (recusa extras sem pontuação, adendo §E.7.5).

create or replace function public.comissao_excluir_rascunho(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  delete from public.comissao_fechamentos where id = p_fechamento;
end $$;
comment on function public.comissao_excluir_rascunho(uuid) is '[api] Exclui um rascunho de comissão.';

-- ================================================================ detalhe (adendo E.3.4)
-- comissao_detalhe: em …0290_comissao_presenca.sql (entradas da prévia com a presença v3, §E.7.7).

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000220_comissoes.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000230_ingestao.sql
-- =====================================================================================================
-- 20261006000230_ingestao.sql — backend-2
-- RPCs de ingestão chamadas pelo N8N com service_role (todas [servico], idempotentes).
-- Contrato: §10.8, §11.2, §11.4–§11.6.
-- =====================================================================================================

-- ================================================================ auxiliares
create or replace function public.ingestao_integracao_validar(p_integracao uuid, p_tipos text[])
returns public.integracoes language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare i public.integracoes;
begin
  select * into i from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not i.ativa then raise exception 'Integração inativa' using errcode = '22023'; end if;
  if not (i.tipo = any (p_tipos)) then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  return i;
end $$;
comment on function public.ingestao_integracao_validar(uuid, text[]) is '[interno] Integração existe, ativa e do tipo certo (§11.2).';

-- Lê um instante: ISO com fuso (Z/offset) como veio; sem fuso, no fuso informado.
create or replace function public.ingestao_ler_instante(p_texto text, p_fuso text, p_exigir text default null)
returns timestamptz language plpgsql stable set search_path = public, extensions, pg_temp as $$
declare v_com_fuso boolean;
begin
  if p_texto is null or btrim(p_texto) = '' then return null; end if;
  p_texto := btrim(p_texto);
  v_com_fuso := p_texto ~* '(z|[+-][0-9]{2}(:?[0-9]{2})?)$' and p_texto ~ '[T ][0-9]{2}:[0-9]{2}';
  if p_exigir = 'com_fuso' and not v_com_fuso then raise exception 'instante sem fuso'; end if;
  if p_exigir = 'sem_fuso' and v_com_fuso then raise exception 'instante_local com fuso'; end if;
  if v_com_fuso then return p_texto::timestamptz; end if;
  return p_texto::timestamp at time zone p_fuso;
end $$;
comment on function public.ingestao_ler_instante(text, text, text) is '[interno] Converte texto ISO em timestamptz (sem fuso = fuso da empresa).';

create or replace function public.ingestao_centavos(p_valor jsonb)
returns bigint language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when p_valor is null or p_valor = 'null'::jsonb or btrim(p_valor #>> '{}') = '' then 0
              else round((p_valor #>> '{}')::numeric)::bigint end
$$;
comment on function public.ingestao_centavos(jsonb) is '[interno] Valor da Zig (centavos) → bigint; null → 0.';

create or replace function public.ingestao_texto(p_valor jsonb)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select nullif(btrim(p_valor #>> '{}'), '')
$$;
comment on function public.ingestao_texto(jsonb) is '[interno] jsonb escalar → texto aparado (vazio → null).';

create or replace function public.ingestao_loja_validar(p_empresa uuid, p_loja text)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_loja is null or not exists (select 1 from public.zig_lojas l where l.empresa_id = p_empresa and l.loja_id_externo = p_loja) then
    raise exception 'Loja não encontrada' using errcode = 'P0002';
  end if;
end $$;
comment on function public.ingestao_loja_validar(uuid, text) is '[interno] Loja existe em zig_lojas da empresa.';

create or replace function public.ingestao_lista(p_itens jsonb)
returns jsonb language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_itens is null or p_itens = 'null'::jsonb then return '[]'::jsonb; end if;
  if jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  return p_itens;
end $$;
comment on function public.ingestao_lista(jsonb) is '[interno] Garante array JSON.';

-- ======================================================== Control iD: batidas (§11.4)
create or replace function public.ingestao_controlid_batidas(p_integracao uuid, p_batidas jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig          public.integracoes;
  v_fuso      text;
  v_eventos   jsonb;
  v_rep       boolean;
  x           jsonb;
  v_idx       int := -1;
  v_lidos     int := 0;
  v_gravados  int := 0;
  v_ignorados int := 0;
  v_dups      int := 0;
  v_semfunc   int := 0;
  v_dias      int := 0;
  v_erros     jsonb := '[]'::jsonb;
  v_nerros    int := 0;
  v_idext     text;
  v_pessoa    text;
  v_instante  timestamptz;
  v_func      uuid;
  v_id        uuid;
  v_data      date;
  v_max_id    numeric;
  v_max_idtxt text;
  v_max_inst  timestamptz;
  v_cursor    jsonb;
  v_afetados  text[] := '{}';
  v_par       text;
  v_motivo    text;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  p_batidas := public.ingestao_lista(p_batidas);
  if jsonb_array_length(p_batidas) > 2000 then
    raise exception 'Lote maior que 2000 itens' using errcode = '22023';
  end if;
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;
  v_rep := ig.tipo = 'controlid_rep';
  v_eventos := coalesce(ig.parametros -> 'eventos_validos', '[7]'::jsonb);
  if jsonb_typeof(v_eventos) <> 'array' then v_eventos := '[7]'::jsonb; end if;

  for x in select value from jsonb_array_elements(p_batidas) loop
    v_idx := v_idx + 1;
    v_lidos := v_lidos + 1;
    v_motivo := null;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      v_idext := coalesce(public.ingestao_texto(x -> 'id_externo'), public.ingestao_texto(x -> 'nsr'));
      if v_idext is null then raise exception 'id_externo ausente'; end if;
      if v_rep and v_idext ~ '^[0-9]+$' then
        v_idext := coalesce(nullif(ltrim(v_idext, '0'), ''), '0');
      end if;
      if (x ? 'instante' and x -> 'instante' <> 'null'::jsonb) = (x ? 'instante_local' and x -> 'instante_local' <> 'null'::jsonb) then
        raise exception 'informe instante ou instante_local';
      end if;
      begin
        if x ? 'instante' and x -> 'instante' <> 'null'::jsonb then
          v_instante := public.ingestao_ler_instante(x ->> 'instante', v_fuso, 'com_fuso');
        else
          v_instante := public.ingestao_ler_instante(x ->> 'instante_local', v_fuso, 'sem_fuso');
        end if;
      exception when others then
        raise exception 'instante inválido';
      end;
      if v_instante is null then raise exception 'instante inválido'; end if;

      if v_rep then
        v_pessoa := regexp_replace(coalesce(public.ingestao_texto(x -> 'cpf'), public.ingestao_texto(x -> 'pis'), ''), '[^0-9]', '', 'g');
        if v_pessoa = '' then raise exception 'sem CPF/PIS'; end if;
      else
        v_pessoa := public.ingestao_texto(x -> 'user_id');
        if x ? 'evento' and x -> 'evento' <> 'null'::jsonb and not (v_eventos @> jsonb_build_array(x -> 'evento')
                                                                 or v_eventos @> jsonb_build_array((x ->> 'evento')::numeric)) then
          v_motivo := 'evento';
        elsif v_pessoa is null or v_pessoa = '0' then
          v_motivo := 'sem_usuario';
        end if;
      end if;
    exception when others then
      v_ignorados := v_ignorados + 1;
      v_nerros := v_nerros + 1;
      if v_nerros <= 20 then
        v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm);
      end if;
      continue;
    end;

    -- cursor considera todo item bem formado (inclusive ignorados por evento e já existentes)
    if v_idext ~ '^[0-9]+$' then
      if v_max_id is null or v_idext::numeric > v_max_id then v_max_id := v_idext::numeric; end if;
    elsif v_max_idtxt is null or v_idext > v_max_idtxt then
      v_max_idtxt := v_idext;
    end if;
    if v_max_inst is null or v_instante > v_max_inst then v_max_inst := v_instante; end if;

    if v_motivo is not null then
      v_ignorados := v_ignorados + 1;
      continue;
    end if;

    -- resolve funcionário (§7.1)
    v_func := null;
    if v_rep then
      select f.id into v_func from public.funcionarios f
       where f.empresa_id = ig.empresa_id
         and (case when x ? 'cpf' and public.ingestao_texto(x -> 'cpf') is not null then f.cpf else f.pis end) = v_pessoa
       limit 1;
    else
      select cu.funcionario_id into v_func from public.controlid_usuarios cu
       where cu.integracao_id = ig.id and cu.user_id_externo = v_pessoa;
    end if;

    insert into public.ponto_batidas (empresa_id, funcionario_id, integracao_id, origem, id_externo, pessoa_externa, instante)
    values (ig.empresa_id, v_func, ig.id, ig.tipo, v_idext, v_pessoa, v_instante)
    on conflict (integracao_id, id_externo) do nothing
    returning id, data_trabalho into v_id, v_data;

    if v_id is null then
      v_dups := v_dups + 1;
    else
      v_gravados := v_gravados + 1;
      if v_func is null then
        v_semfunc := v_semfunc + 1;
      else
        v_par := v_func::text || '|' || v_data::text;
        if not (v_par = any (v_afetados)) then v_afetados := v_afetados || v_par; end if;
      end if;
    end if;
    v_id := null;
  end loop;

  -- apura cada (funcionário, dia) afetado uma vez
  foreach v_par in array v_afetados loop
    v_dias := v_dias + public.ponto_apurar(split_part(v_par, '|', 1)::uuid, split_part(v_par, '|', 2)::date,
                                           split_part(v_par, '|', 2)::date);
  end loop;

  -- cursor (máximos)
  v_cursor := ig.cursor;
  if v_rep then
    if v_max_id is not null and (v_cursor ->> 'ultimo_nsr' is null or v_max_id > (v_cursor ->> 'ultimo_nsr')::numeric) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_nsr', v_max_id);
    end if;
  else
    if v_max_id is not null and (v_cursor ->> 'ultimo_id' is null or (v_cursor ->> 'ultimo_id') !~ '^[0-9]+$'
                                 or v_max_id > (v_cursor ->> 'ultimo_id')::numeric) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_id', v_max_id::text);
    elsif v_max_id is null and v_max_idtxt is not null
          and (v_cursor ->> 'ultimo_id' is null or v_max_idtxt > (v_cursor ->> 'ultimo_id')) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_id', v_max_idtxt);
    end if;
  end if;
  if v_max_inst is not null and (v_cursor ->> 'ultimo_instante' is null
                                 or v_max_inst > (v_cursor ->> 'ultimo_instante')::timestamptz) then
    v_cursor := v_cursor || jsonb_build_object('ultimo_instante', v_max_inst);
  end if;
  if v_cursor is distinct from ig.cursor then
    update public.integracoes set cursor = v_cursor where id = ig.id;
  end if;

  return jsonb_build_object('lidos', v_lidos, 'gravados', v_gravados, 'ignorados', v_ignorados, 'duplicados', v_dups,
                            'sem_funcionario', v_semfunc, 'dias_apurados', v_dias, 'cursor', v_cursor)
         || case when v_nerros > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_controlid_batidas(uuid, jsonb) is '[servico] Ingestão idempotente de batidas Control iD (§11.4).';

-- ======================================================== Zig (§11.5)
create or replace function public.ingestao_zig_lojas(p_integracao uuid, p_lojas jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v_idx int := -1; v_lidos int := 0; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_erros jsonb := '[]'::jsonb; v_id text; v_nome text; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  p_lojas := public.ingestao_lista(p_lojas);
  for x in select value from jsonb_array_elements(p_lojas) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    v_id := case when jsonb_typeof(x) = 'object' then public.ingestao_texto(x -> 'id') end;
    v_nome := case when jsonb_typeof(x) = 'object' then coalesce(public.ingestao_texto(x -> 'name'), public.ingestao_texto(x -> 'nome')) end;
    if v_id is null then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', 'id ausente'); end if;
      continue;
    end if;
    insert into public.zig_lojas as l (empresa_id, integracao_id, loja_id_externo, nome, visto_em)
    values (ig.empresa_id, ig.id, v_id, coalesce(v_nome, v_id), public.agora())
    on conflict (empresa_id, loja_id_externo) do update
      set nome = coalesce(v_nome, l.nome), integracao_id = excluded.integracao_id, visto_em = excluded.visto_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_ins + v_atu, 'ignorados', v_ign, 'inseridos', v_ins, 'atualizados', v_atu)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_lojas(uuid, jsonb) is '[servico] Upsert das lojas da Zig (preserva sincronizar).';

create or replace function public.ingestao_zig_tipo(p_tipo text)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select coalesce((select t from unnest(array['Normal', 'Couvert', 'ZigCard', 'Entrance', 'Tip']) t
                    where lower(t) = lower(btrim(p_tipo))), 'Outro')
$$;
comment on function public.ingestao_zig_tipo(text) is '[interno] type da Zig → tipo (desconhecido = Outro).';

create or replace function public.ingestao_zig_saida_produtos(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; v_fuso text; x jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0;
  v_rem int; v_erros jsonb := '[]'::jsonb; v_unit bigint; v_qtd numeric; v_desc bigint; v_tipo_orig text;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;

  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_vendas_itens:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_vendas_itens where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;

  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'transactionId') is null then raise exception 'transactionId ausente'; end if;
      v_unit := public.ingestao_centavos(x -> 'unitValue');
      v_qtd := coalesce((public.ingestao_texto(x -> 'count'))::numeric, 0);
      v_desc := public.ingestao_centavos(x -> 'discountValue');
      v_tipo_orig := public.ingestao_texto(x -> 'type');
      insert into public.zig_vendas_itens (
        empresa_id, loja_id_externo, data_operacao, transaction_id, transaction_date, event_id, event_date, invoice_id,
        product_id, product_sku, product_name, product_category, tipo, tipo_original, unit_value, quantidade,
        fractional_amount, fraction_unit, discount_value, valor_total, employee_name, additions)
      values (
        ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'transactionId'),
        public.ingestao_ler_instante(x ->> 'transactionDate', v_fuso),
        public.ingestao_texto(x -> 'eventId'),
        left(public.ingestao_texto(x -> 'eventDate'), 10)::date,
        public.ingestao_texto(x -> 'invoiceId'),
        public.ingestao_texto(x -> 'productId'), public.ingestao_texto(x -> 'productSku'),
        public.ingestao_texto(x -> 'productName'), public.ingestao_texto(x -> 'productCategory'),
        public.ingestao_zig_tipo(v_tipo_orig), v_tipo_orig, v_unit, v_qtd,
        (public.ingestao_texto(x -> 'fractionalAmount'))::numeric, public.ingestao_texto(x -> 'fractionUnit'),
        v_desc, round(v_unit * v_qtd)::bigint - v_desc,
        public.ingestao_texto(x -> 'employeeName'),
        case when jsonb_typeof(x -> 'additions') = 'array' then x -> 'additions' else '[]'::jsonb end);
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;

  if ig.cursor ->> 'ultimo_dia' is null or p_data > (ig.cursor ->> 'ultimo_dia')::date then
    update public.integracoes set cursor = cursor || jsonb_build_object('ultimo_dia', p_data) where id = ig.id;
  end if;

  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_saida_produtos(uuid, text, date, jsonb) is '[servico] Substitui os itens vendidos do dia/loja (/erp/saida-produtos).';

create or replace function public.ingestao_zig_faturamento(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0; v_rem int;
  v_erros jsonb := '[]'::jsonb;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_faturamento:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_faturamento where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'paymentId') is null then raise exception 'paymentId ausente'; end if;
      insert into public.zig_faturamento (empresa_id, loja_id_externo, data_operacao, event_id, event_date, payment_id,
                                          payment_name, valor)
      values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'eventId'),
              left(public.ingestao_texto(x -> 'eventDate'), 10)::date,
              (public.ingestao_texto(x -> 'paymentId'))::int,
              coalesce(public.ingestao_texto(x -> 'paymentName'), 'Forma ' || public.ingestao_texto(x -> 'paymentId')),
              public.ingestao_centavos(coalesce(x -> 'value', x -> 'valor', x -> 'totalValue')));
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_faturamento(uuid, text, date, jsonb) is '[servico] Substitui o faturamento do dia/loja (/erp/faturamento).';

create or replace function public.ingestao_zig_faturamento_bandeiras(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0; v_rem int;
  v_erros jsonb := '[]'::jsonb; v_valores jsonb;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_faturamento_bandeiras:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_faturamento_bandeiras
   where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'paymentId') is null then raise exception 'paymentId ausente'; end if;
      v_valores := case when jsonb_typeof(x -> 'values') = 'array' then x -> 'values' else '[]'::jsonb end;
      for v in select value from jsonb_array_elements(v_valores) loop
        insert into public.zig_faturamento_bandeiras (empresa_id, loja_id_externo, data_operacao, event_id, payment_id,
                                                      payment_name, card_brand, valor)
        values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'eventId'),
                (public.ingestao_texto(x -> 'paymentId'))::int, public.ingestao_texto(x -> 'paymentName'),
                coalesce(public.ingestao_texto(v -> 'cardBrand'), public.ingestao_texto(v -> 'brand')),
                public.ingestao_centavos(coalesce(v -> 'totalValue', v -> 'value', v -> 'valor')));
        v_grav := v_grav + 1;
      end loop;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_faturamento_bandeiras(uuid, text, date, jsonb) is '[servico] Substitui o faturamento por bandeira do dia/loja (cada values[] vira uma linha).';

create or replace function public.ingestao_zig_compradores(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0; v_rem int;
  v_erros jsonb := '[]'::jsonb;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_compradores:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_compradores where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'transactionId') is null then raise exception 'transactionId ausente'; end if;
      -- LGPD: userDocument, userDocumentType, userPhone, userName, userEmail são descartados.
      insert into public.zig_compradores (empresa_id, loja_id_externo, data_operacao, transaction_id, products_value, tip_value)
      values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'transactionId'),
              public.ingestao_centavos(x -> 'productsValue'), public.ingestao_centavos(x -> 'tipValue'));
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_compradores(uuid, text, date, jsonb) is '[servico] Substitui os compradores do dia/loja, sem dados pessoais.';

-- ======================================================== apuração e exportação (§11.6)
create or replace function public.ingestao_apurar_ponto(p_empresa uuid default null, p_inicio date default null,
                                                        p_fim date default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  e record; f record; v_atual date; v_ini date; v_fim date;
  v_emp int := 0; v_func int := 0; v_dias int := 0; v_n int;
begin
  if p_empresa is not null and not exists (select 1 from public.empresas where id = p_empresa) then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;
  for e in
    select em.id from public.empresas em
     where (p_empresa is null and em.ativa) or em.id = p_empresa
     order by em.id
  loop
    v_atual := public.dia_de_trabalho(public.agora(), e.id);
    v_ini := coalesce(p_inicio, v_atual - 2);
    v_fim := coalesce(p_fim, v_atual);
    perform public.ponto_validar_periodo(v_ini, v_fim, 93);
    v_emp := v_emp + 1;
    for f in
      select fu.id from public.funcionarios fu
       where fu.empresa_id = e.id
         and (fu.data_admissao is null or fu.data_admissao <= v_fim)
         and (fu.data_desligamento is null or fu.data_desligamento >= v_ini)
       order by fu.id
    loop
      v_n := public.ponto_apurar(f.id, v_ini, v_fim);
      if v_n > 0 then v_func := v_func + 1; end if;
      v_dias := v_dias + v_n;
    end loop;
  end loop;
  return jsonb_build_object('empresas', v_emp, 'funcionarios', v_func, 'dias', v_dias);
end $$;
comment on function public.ingestao_apurar_ponto(uuid, date, date) is '[servico] Rotina diária: apura todas as empresas ativas (padrão: dia atual − 2 até hoje).';

create or replace function public.ingestao_fechamento_exportar(p_fechamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_fech jsonb; v_itens jsonb;
begin
  select to_jsonb(fc) || jsonb_build_object('empresa_nome', e.nome) into v_fech
    from public.comissao_fechamentos fc join public.empresas e on e.id = fc.empresa_id
   where fc.id = p_fechamento;
  if v_fech is null then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(it) order by it.funcionario_nome, (it.tipo = 'extra'),
                            coalesce(it.funcionario_id, it.extra_id) nulls last, it.id), '[]'::jsonb) into v_itens
    from public.comissao_itens it where it.fechamento_id = p_fechamento;
  -- (adendo extras v2, E.3.4) detalhe diário do rateio (vazio no modo período)
  return jsonb_build_object('fechamento', v_fech, 'itens', v_itens,
    'dias', coalesce((select jsonb_agg(to_jsonb(rd) order by rd.data) from public.comissao_rateio_dias rd
                       where rd.fechamento_id = p_fechamento), '[]'::jsonb));
end $$;
comment on function public.ingestao_fechamento_exportar(uuid) is '[servico] Fechamento + itens (por nome) + dias do rateio para o CSV do N8N.';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000230_ingestao.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000240_painel.sql
-- =====================================================================================================
-- 20261006000240_painel.sql — backend-2
-- painel_do_dia: resumo do dia de trabalho (faturamento, serviço, ponto, tarefas, sincronização). Contrato §10.7.
-- + blocos reservas e ocorrencias (docs/CONTRATO-ADENDO-extras-ocorrencias-reservas.md, R.4).
-- =====================================================================================================

create or replace function public.painel_do_dia(p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa   uuid;
  v_hoje      date;
  v_ontem     date;
  v_mes       date;
  v_fat       jsonb;
  v_serv      jsonb;
  v_ponto     jsonb;
  v_tarefas   jsonb;
  v_sync      jsonb;
  v_fuso      text;
  v_virada    time;
  v_presentes int := 0;
  v_escalados int := 0;
  v_operar    boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  select e.fuso, e.virada_dia into v_fuso, v_virada from public.empresas e where e.id = v_empresa;
  v_hoje := public.dia_de_trabalho(public.agora(), v_empresa);
  v_ontem := v_hoje - 1;
  v_mes := date_trunc('month', v_hoje)::date;

  -- faturamento e serviço
  select jsonb_build_object(
           'hoje', coalesce(sum(z.valor) filter (where z.data_operacao = v_hoje), 0),
           'ontem', coalesce(sum(z.valor) filter (where z.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(z.valor) filter (where z.data_operacao >= v_mes), 0),
           'tem_zig', exists (select 1 from public.integracoes i where i.empresa_id = v_empresa and i.tipo = 'zig' and i.ativa))
    into v_fat
    from public.zig_faturamento z
   where z.empresa_id = v_empresa and z.data_operacao between least(v_mes, v_ontem) and v_hoje;

  select jsonb_build_object(
           'ontem', coalesce(sum(i.valor_total) filter (where i.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(i.valor_total) filter (where i.data_operacao >= v_mes), 0))
    into v_serv
    from public.zig_vendas_itens i
   where i.empresa_id = v_empresa and i.tipo = 'Tip' and i.data_operacao between least(v_mes, v_ontem) and v_hoje;

  -- ponto (ao vivo para hoje)
  select count(*) filter (where c.batidas_validas % 2 = 1),
         count(*) filter (where c.batidas_esperadas > 0)
    into v_presentes, v_escalados
    from public.funcionarios f
    cross join lateral public.ponto_calcular_dia(f.id, v_hoje) c
   where f.empresa_id = v_empresa and f.ativo and not c.fora_do_vinculo;

  select jsonb_build_object(
    'alarmes_abertos', (select count(*) from public.ponto_alarmes a where a.empresa_id = v_empresa and a.status = 'aberto'),
    'alarmes', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'funcionario_id', x.funcionario_id, 'funcionario_nome', x.nome,
                                           'data', x.data, 'tipo', x.tipo, 'batida_esperada', x.batida_esperada,
                                           'detalhe', x.detalhe) order by x.data desc, x.criado_em desc, x.id)
         from (select a.id, a.funcionario_id, f.nome, a.data, a.tipo, a.batida_esperada, a.detalhe, a.criado_em
                 from public.ponto_alarmes a
                 join public.funcionarios f on f.id = a.funcionario_id
                where a.empresa_id = v_empresa and a.status = 'aberto'
                order by a.data desc, a.criado_em desc, a.id
                limit 5) x), '[]'::jsonb),
    'presentes_agora', v_presentes,
    'escalados_hoje', v_escalados,
    'batidas_sem_funcionario', (select count(*) from public.ponto_batidas b
                                 where b.empresa_id = v_empresa and b.funcionario_id is null))
    into v_ponto;

  -- tarefas do dia (atrasadas: abertas de hoje ou de dias anteriores cujo prazo já passou)
  select jsonb_build_object(
           'total', count(*) filter (where t.data = v_hoje and t.status <> 'cancelada'),
           'concluidas', count(*) filter (where t.data = v_hoje and t.status = 'concluida'),
           'pendentes', count(*) filter (where t.data = v_hoje and t.status in ('pendente', 'em_andamento')),
           'atrasadas', count(*) filter (where t.status in ('pendente', 'em_andamento')
                                          and (t.data < v_hoje
                                               or (t.data = v_hoje and t.horario_limite is not null
                                                   and public.ponto_instante_escala(t.data, t.horario_limite, v_fuso, v_virada)
                                                       < public.agora()))))
    into v_tarefas
    from public.tarefas t
   where t.empresa_id = v_empresa and t.data between v_hoje - 31 and v_hoje;

  -- sincronização (só status, nunca segredos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'integracao_id', i.id, 'tipo', i.tipo, 'nome', i.nome, 'ativa', i.ativa,
           'ultimo_sucesso_em', i.ultimo_sucesso_em, 'ultimo_status', i.ultimo_status, 'ultimo_erro', i.ultimo_erro,
           'executando', exists (select 1 from public.sync_execucoes s where s.integracao_id = i.id and s.status = 'executando')
                      or exists (select 1 from public.sync_solicitacoes s
                                  where s.integracao_id = i.id and s.status in ('pendente', 'em_andamento')))
           order by i.tipo, i.nome, i.id), '[]'::jsonb)
    into v_sync
    from public.integracoes i
   where i.empresa_id = v_empresa;

  -- reservas e ocorrências (adendo extras/ocorrências/reservas R.4 / O.4): telefone e ocorrências só para G A M
  v_operar := public.pode_operar(v_empresa) is true;

  return jsonb_build_object(
    'empresa_id', v_empresa, 'dia_trabalho', v_hoje, 'ontem', v_ontem,
    'faturamento', v_fat, 'servico', v_serv, 'ponto', v_ponto, 'tarefas', v_tarefas, 'sincronizacao', v_sync,
    'reservas', public.reservas_painel(v_empresa, v_hoje, v_operar),
    'ocorrencias', case when v_operar then public.ocorrencias_resumo_empresa(v_empresa, 30) end);
end $$;
comment on function public.painel_do_dia(uuid) is '[api] Painel do dia de trabalho (§10.7).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000240_painel.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000250_ocorrencias.sql
-- =====================================================================================================
-- 20261006000250_ocorrencias.sql — backend (adendo extras/ocorrências/reservas, seção O)
-- Ocorrências disciplinares do funcionário (advertência / suspensão) com anexos no Storage (bucket privado
-- 'funcionarios-documentos'). Suspensão gera abonos 'suspensao' em ponto_abonos (situação 'suspenso', sem alarmes
-- nem saldo negativo). Dado sensível: só G A M. Idempotente.
-- =====================================================================================================

create table if not exists public.funcionario_ocorrencias (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,
  funcionario_id    uuid not null references public.funcionarios (id) on delete cascade,
  tipo              text not null check (tipo in ('advertencia', 'suspensao')),
  data              date not null,
  motivo            text not null check (btrim(motivo) <> ''),
  descricao         text,
  dias_suspensao    int check (dias_suspensao between 1 and 30),
  suspensao_inicio  date,
  suspensao_fim     date,
  criado_por        uuid references public.perfis (id) on delete set null,
  criado_por_nome   text not null,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint funcionario_ocorrencias_suspensao check (
    (tipo = 'advertencia' and dias_suspensao is null and suspensao_inicio is null and suspensao_fim is null)
    or (tipo = 'suspensao' and dias_suspensao is not null and suspensao_inicio is not null
        and suspensao_fim = suspensao_inicio + dias_suspensao - 1))
);
create index if not exists funcionario_ocorrencias_empresa_idx on public.funcionario_ocorrencias (empresa_id, data desc);
create index if not exists funcionario_ocorrencias_funcionario_idx on public.funcionario_ocorrencias (funcionario_id, data desc);
create index if not exists funcionario_ocorrencias_criado_por_idx on public.funcionario_ocorrencias (criado_por);
comment on table public.funcionario_ocorrencias is
  '[api:leitura] Ocorrências disciplinares (advertência/suspensão) do funcionário. Dado sensível: só G A M.';

create table if not exists public.funcionario_ocorrencia_anexos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  ocorrencia_id   uuid not null references public.funcionario_ocorrencias (id) on delete cascade,
  bucket          text not null default 'funcionarios-documentos',
  caminho         text not null unique,
  nome_arquivo    text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now()
);
create index if not exists funcionario_ocorrencia_anexos_empresa_idx on public.funcionario_ocorrencia_anexos (empresa_id);
create index if not exists funcionario_ocorrencia_anexos_ocorrencia_idx on public.funcionario_ocorrencia_anexos (ocorrencia_id);
create index if not exists funcionario_ocorrencia_anexos_criado_por_idx on public.funcionario_ocorrencia_anexos (criado_por);
comment on table public.funcionario_ocorrencia_anexos is
  '[api:leitura] Anexos (fotos/PDF no Storage, bucket privado funcionarios-documentos) das ocorrências. Só G A M.';

-- abono gerado pela suspensão (coluna criada em …0200)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ponto_abonos_ocorrencia_fk') then
    alter table public.ponto_abonos add constraint ponto_abonos_ocorrencia_fk
      foreign key (ocorrencia_id) references public.funcionario_ocorrencias (id) on delete cascade;
  end if;
end $$;

-- ================================================================ RLS
alter table public.funcionario_ocorrencias enable row level security;
alter table public.funcionario_ocorrencia_anexos enable row level security;
drop policy if exists funcionario_ocorrencias_ler on public.funcionario_ocorrencias;
create policy funcionario_ocorrencias_ler on public.funcionario_ocorrencias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists funcionario_ocorrencia_anexos_ler on public.funcionario_ocorrencia_anexos;
create policy funcionario_ocorrencia_anexos_ler on public.funcionario_ocorrencia_anexos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
drop trigger if exists a_empresa on public.funcionario_ocorrencias;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.funcionario_ocorrencias
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists tocar_atualizado_em on public.funcionario_ocorrencias;
create trigger tocar_atualizado_em before update on public.funcionario_ocorrencias
  for each row execute function public.tocar_atualizado_em();

create or replace function public.ocorrencia_anexo_empresa()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select o.empresa_id into v_empresa from public.funcionario_ocorrencias o where o.id = new.ocorrencia_id;
  if v_empresa is null then raise exception 'Ocorrência não encontrada' using errcode = 'P0002'; end if;
  new.empresa_id := v_empresa;
  return new;
end $$;
comment on function public.ocorrencia_anexo_empresa() is '[interno] Gatilho: empresa_id do anexo = da ocorrência.';
drop trigger if exists a_empresa on public.funcionario_ocorrencia_anexos;
create trigger a_empresa before insert or update of ocorrencia_id, empresa_id on public.funcionario_ocorrencia_anexos
  for each row execute function public.ocorrencia_anexo_empresa();

-- ================================================================ Storage (documentos)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('funcionarios-documentos', 'funcionarios-documentos', false, 5242880,
            array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists mdg_docs_ler on storage.objects';
    execute $p$create policy mdg_docs_ler on storage.objects for select to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_inserir on storage.objects';
    execute $p$create policy mdg_docs_inserir on storage.objects for insert to authenticated
      with check (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_alterar on storage.objects';
    execute $p$create policy mdg_docs_alterar on storage.objects for update to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))
      with check (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_excluir on storage.objects';
    execute $p$create policy mdg_docs_excluir on storage.objects for delete to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
  end if;
end $$;

-- ================================================================ auxiliares
create or replace function public.ocorrencia_para_operar(p_ocorrencia uuid)
returns public.funcionario_ocorrencias language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias;
begin
  select * into o from public.funcionario_ocorrencias where id = p_ocorrencia;
  if not found then raise exception 'Ocorrência não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(o.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return o;
end $$;
comment on function public.ocorrencia_para_operar(uuid) is '[interno] Ocorrência existente e operável (G A M).';

-- Valida os campos e devolve (tipo, dias, início, fim) normalizados.
create or replace function public.ocorrencia_validar(p_empresa uuid, p_tipo text, p_data date, p_motivo text,
                                                     p_dias int, p_inicio date,
                                                     out tipo text, out dias int, out inicio date, out fim date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_tipo is null or p_tipo not in ('advertencia', 'suspensao') then
    raise exception 'Tipo de ocorrência inválido' using errcode = '22023';
  end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if p_data > public.dia_de_trabalho(public.agora(), p_empresa) then
    raise exception 'Data no futuro' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'Informe o motivo' using errcode = '22023';
  end if;
  tipo := p_tipo;
  if p_tipo = 'advertencia' then
    return;
  end if;
  if p_dias is null or p_dias < 1 or p_dias > 30 then
    raise exception 'Dias de suspensão inválidos (1 a 30)' using errcode = '22023';
  end if;
  inicio := coalesce(p_inicio, p_data);
  if inicio < p_data or inicio > p_data + 60 then
    raise exception 'Início da suspensão inválido' using errcode = '22023';
  end if;
  dias := p_dias;
  fim := inicio + p_dias - 1;
end $$;
comment on function public.ocorrencia_validar(uuid, text, date, text, int, date) is '[interno] Validação de ocorrência (adendo O.3).';

-- Ressincroniza os abonos 'suspensao' de uma ocorrência e reapura os dias afetados (antigos e novos).
create or replace function public.ocorrencia_sincronizar_abonos(p_ocorrencia uuid, p_antigo_inicio date, p_antigo_fim date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v_existe boolean; v_conflito date; v_ini date; v_fim date;
begin
  select * into o from public.funcionario_ocorrencias where id = p_ocorrencia;
  v_existe := found;
  delete from public.ponto_abonos where ocorrencia_id = p_ocorrencia;
  if v_existe and o.tipo = 'suspensao' then
    select a.data into v_conflito
      from public.ponto_abonos a
     where a.funcionario_id = o.funcionario_id and a.data between o.suspensao_inicio and o.suspensao_fim
     order by a.data limit 1;
    if v_conflito is not null then
      raise exception 'Já existe abono para o funcionário em %', to_char(v_conflito, 'DD/MM/YYYY') using errcode = '22023';
    end if;
    -- (adendo extras v3, §E.7.2) dia com falta registrada não recebe suspensão
    select g::date into v_conflito from generate_series(o.suspensao_inicio, o.suspensao_fim, interval '1 day') g
     where public.ponto_falta_do_dia(o.funcionario_id, g::date) is not null order by g limit 1;
    if v_conflito is not null then
      raise exception 'Dia com falta em %: remova a falta antes', to_char(v_conflito, 'DD/MM/YYYY') using errcode = '22023';
    end if;
    insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por, ocorrencia_id)
    select o.empresa_id, o.funcionario_id, g::date, 'suspensao', left('Suspensão: ' || o.motivo, 500), public.meu_perfil_id(), o.id
      from generate_series(o.suspensao_inicio, o.suspensao_fim, interval '1 day') g;
  end if;
  v_ini := least(p_antigo_inicio, case when o.tipo = 'suspensao' then o.suspensao_inicio end);
  v_fim := greatest(p_antigo_fim, case when o.tipo = 'suspensao' then o.suspensao_fim end);
  if v_ini is not null and o.funcionario_id is not null then
    perform public.ponto_apurar(o.funcionario_id, v_ini, v_fim);
  end if;
end $$;
comment on function public.ocorrencia_sincronizar_abonos(uuid, date, date) is
  '[interno] Abonos ''suspensao'' da ocorrência (um por dia) + reapuração (adendo O.3).';

-- ================================================================ RPCs
create or replace function public.ocorrencia_criar(p_funcionario uuid, p_tipo text, p_data date, p_motivo text,
                                                   p_descricao text default null, p_dias_suspensao int default null,
                                                   p_suspensao_inicio date default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios; v record; v_id uuid;
begin
  f := public.funcionario_para_operar(p_funcionario);
  select * into v from public.ocorrencia_validar(f.empresa_id, p_tipo, p_data, p_motivo, p_dias_suspensao, p_suspensao_inicio);
  insert into public.funcionario_ocorrencias (empresa_id, funcionario_id, tipo, data, motivo, descricao, dias_suspensao,
                                              suspensao_inicio, suspensao_fim, criado_por, criado_por_nome)
  values (f.empresa_id, f.id, v.tipo, p_data, btrim(p_motivo), nullif(btrim(p_descricao), ''), v.dias, v.inicio, v.fim,
          public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  perform public.ocorrencia_sincronizar_abonos(v_id, null, null);
  return v_id;
end $$;
comment on function public.ocorrencia_criar(uuid, text, date, text, text, int, date) is
  '[api] Registra advertência/suspensão do funcionário (G A M). Suspensão gera abonos e reapura.';

create or replace function public.ocorrencia_atualizar(p_ocorrencia uuid, p_tipo text, p_data date, p_motivo text,
                                                       p_descricao text, p_dias_suspensao int default null,
                                                       p_suspensao_inicio date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v record;
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  select * into v from public.ocorrencia_validar(o.empresa_id, p_tipo, p_data, p_motivo, p_dias_suspensao, p_suspensao_inicio);
  update public.funcionario_ocorrencias
     set tipo = v.tipo, data = p_data, motivo = btrim(p_motivo), descricao = nullif(btrim(p_descricao), ''),
         dias_suspensao = v.dias, suspensao_inicio = v.inicio, suspensao_fim = v.fim
   where id = o.id;
  perform public.ocorrencia_sincronizar_abonos(o.id, o.suspensao_inicio, o.suspensao_fim);
end $$;
comment on function public.ocorrencia_atualizar(uuid, text, date, text, text, int, date) is
  '[api] Edita uma ocorrência (G A M); ressincroniza abonos de suspensão e reapura.';

create or replace function public.ocorrencia_excluir(p_ocorrencia uuid)
returns text[] language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v_caminhos text[];
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  select coalesce(array_agg(a.caminho order by a.criado_em, a.id), array[]::text[]) into v_caminhos
    from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id;
  delete from public.funcionario_ocorrencias where id = o.id;     -- anexos e abonos em cascata
  if o.tipo = 'suspensao' then
    perform public.ponto_apurar(o.funcionario_id, o.suspensao_inicio, o.suspensao_fim);
  end if;
  return v_caminhos;
end $$;
comment on function public.ocorrencia_excluir(uuid) is
  '[api] Exclui a ocorrência (G A M); devolve os caminhos dos anexos para remover do Storage.';

create or replace function public.ocorrencia_adicionar_anexo(p_ocorrencia uuid, p_caminho text, p_nome_arquivo text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v text := nullif(btrim(coalesce(p_caminho, '')), ''); v_existe boolean := true; v_id uuid;
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  if v is null or position(o.empresa_id::text || '/ocorrencias/' || o.id::text || '/' in v) <> 1
     or v !~* ('^' || o.empresa_id::text || '/ocorrencias/' || o.id::text || '/[^/]+\.(jpg|jpeg|png|webp|pdf)$') then
    raise exception 'Anexo inválido' using errcode = '22023';
  end if;
  if (select count(*) from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id) >= 10 then
    raise exception 'Limite de 10 anexos por ocorrência' using errcode = '22023';
  end if;
  if exists (select 1 from public.funcionario_ocorrencia_anexos a where a.caminho = v) then
    raise exception 'Anexo já registrado' using errcode = '23505';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)'
      into v_existe using 'funcionarios-documentos', v;
  end if;
  if not v_existe then
    raise exception 'Anexo não encontrado no armazenamento' using errcode = 'P0002';
  end if;
  insert into public.funcionario_ocorrencia_anexos (empresa_id, ocorrencia_id, caminho, nome_arquivo, criado_por)
  values (o.empresa_id, o.id, v, nullif(btrim(p_nome_arquivo), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.ocorrencia_adicionar_anexo(uuid, text, text) is
  '[api] Registra um anexo já enviado ao Storage (bucket funcionarios-documentos) (G A M).';

create or replace function public.ocorrencia_remover_anexo(p_anexo uuid)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a public.funcionario_ocorrencia_anexos;
begin
  select * into a from public.funcionario_ocorrencia_anexos where id = p_anexo;
  if not found then raise exception 'Anexo não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  delete from public.funcionario_ocorrencia_anexos where id = a.id;
  return a.caminho;
end $$;
comment on function public.ocorrencia_remover_anexo(uuid) is '[api] Remove o registro do anexo e devolve o caminho no Storage (G A M).';

create or replace function public.ocorrencias_listar(p_funcionario uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios;
begin
  f := public.funcionario_para_operar(p_funcionario);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', o.id, 'funcionario_id', o.funcionario_id, 'tipo', o.tipo, 'data', o.data, 'motivo', o.motivo,
             'descricao', o.descricao, 'dias_suspensao', o.dias_suspensao, 'suspensao_inicio', o.suspensao_inicio,
             'suspensao_fim', o.suspensao_fim, 'criado_por_nome', o.criado_por_nome, 'criado_em', o.criado_em,
             'atualizado_em', o.atualizado_em,
             'anexos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'caminho', a.caminho,
                                                                     'nome_arquivo', a.nome_arquivo, 'criado_em', a.criado_em)
                                                  order by a.criado_em, a.id)
                                   from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id), '[]'::jsonb))
           order by o.data desc, o.criado_em desc, o.id)
      from public.funcionario_ocorrencias o where o.funcionario_id = f.id), '[]'::jsonb);
end $$;
comment on function public.ocorrencias_listar(uuid) is '[api] Ocorrências do funcionário com anexos (G A M).';

create or replace function public.ocorrencias_contagem(p_funcionario uuid default null, p_empresa uuid default null)
returns table (funcionario_id uuid, advertencias int, suspensoes int, dias_suspensao int, ultima_data date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  return query
  select o.funcionario_id,
         (count(*) filter (where o.tipo = 'advertencia'))::int,
         (count(*) filter (where o.tipo = 'suspensao'))::int,
         coalesce(sum(o.dias_suspensao), 0)::int,
         max(o.data)
    from public.funcionario_ocorrencias o
   where o.empresa_id = v_empresa and (p_funcionario is null or o.funcionario_id = p_funcionario)
   group by o.funcionario_id
   order by o.funcionario_id;
end $$;
comment on function public.ocorrencias_contagem(uuid, uuid) is '[api] Contagem de ocorrências por funcionário (G A M).';

-- Resumo sem checagem (usado pelo painel, que já resolveu a empresa).
create or replace function public.ocorrencias_resumo_empresa(p_empresa uuid, p_dias int)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with h as (select public.dia_de_trabalho(public.agora(), p_empresa) as hoje),
       o as (select x.*, f.nome as funcionario_nome
               from public.funcionario_ocorrencias x
               join public.funcionarios f on f.id = x.funcionario_id, h
              where x.empresa_id = p_empresa and x.data between h.hoje - p_dias + 1 and h.hoje)
  select jsonb_build_object(
    'desde', h.hoje - p_dias + 1, 'ate', h.hoje,
    'advertencias', (select count(*) from o where o.tipo = 'advertencia'),
    'suspensoes', (select count(*) from o where o.tipo = 'suspensao'),
    'suspensos_hoje', (select count(distinct s.funcionario_id) from public.funcionario_ocorrencias s
                        where s.empresa_id = p_empresa and s.tipo = 'suspensao'
                          and h.hoje between s.suspensao_inicio and s.suspensao_fim),
    'recentes', coalesce((select jsonb_agg(jsonb_build_object(
                    'id', r.id, 'funcionario_id', r.funcionario_id, 'funcionario_nome', r.funcionario_nome, 'tipo', r.tipo,
                    'data', r.data, 'motivo', r.motivo, 'dias_suspensao', r.dias_suspensao,
                    'suspensao_inicio', r.suspensao_inicio, 'suspensao_fim', r.suspensao_fim)
                  order by r.data desc, r.criado_em desc, r.id)
                  from (select * from o order by o.data desc, o.criado_em desc, o.id limit 10) r), '[]'::jsonb))
  from h
$$;
comment on function public.ocorrencias_resumo_empresa(uuid, int) is '[interno] Resumo de ocorrências (adendo O.4), sem checagem.';

create or replace function public.ocorrencias_resumo(p_dias int default 30, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_dias is null or p_dias < 1 or p_dias > 366 then
    raise exception 'Período máximo de 366 dias' using errcode = '22023';
  end if;
  return public.ocorrencias_resumo_empresa(v_empresa, p_dias);
end $$;
comment on function public.ocorrencias_resumo(int, uuid) is '[api] Resumo das ocorrências dos últimos N dias (G A M).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000250_ocorrencias.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000260_extras.sql
-- =====================================================================================================
-- 20261006000260_extras.sql — backend (adendo extras/ocorrências/reservas, seção E — v2)
-- Extras = freelas/diaristas: cadastro (pontuação e diária padrão), dias trabalhados (diarias: extra com pontos
-- que entram no rateio diário da comissão, ou funcionário só como custo), valor padrão de diária do funcionário
-- e gastos totais por período. Valores e dados pessoais: só G A M. Idempotente; atualiza por cima da v1.
-- =====================================================================================================

-- ================================================================ v1 removida (pontos extras, diária avulsa)
drop function if exists public.comissao_extra_lancar(uuid, date, numeric, text);
drop function if exists public.comissao_extra_excluir(uuid);
drop function if exists public.comissao_extras_listar(date, date, uuid, uuid);
drop function if exists public.diaria_lancar(date, uuid, text, text, bigint, text, boolean, date, uuid);
drop function if exists public.diaria_atualizar(uuid, date, uuid, text, text, bigint, text, boolean, date);
drop function if exists public.diaria_preparar(uuid, date, uuid, text, text, bigint, boolean, date);
drop function if exists public.diarias_listar(date, date, uuid, boolean, uuid);

create or replace function public.comissao_periodo_fechado(p_empresa uuid, p_data date)
returns boolean language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from public.comissao_fechamentos f
                  where f.empresa_id = p_empresa and f.status = 'fechado' and p_data between f.data_inicio and f.data_fim)
$$;
comment on function public.comissao_periodo_fechado(uuid, date) is '[interno] A data cai num fechamento de comissão fechado?';

-- ================================================================ cadastro de extras (E.1)
create table if not exists public.extras (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  nome                   text not null check (btrim(nome) <> ''),
  funcao                 text,
  telefone               text,
  documento              text,
  pontos_padrao          numeric(8,2) not null default 0 check (pontos_padrao between 0 and 9999.99),
  valor_diaria_centavos  bigint check (valor_diaria_centavos between 0 and 100000000),
  ativo                  boolean not null default true,
  observacoes            text,
  criado_por             uuid references public.perfis (id) on delete set null,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);
create index if not exists extras_empresa_idx on public.extras (empresa_id, lower(nome));
create index if not exists extras_criado_por_idx on public.extras (criado_por);
comment on table public.extras is '[api:leitura] Extras (freelas/diaristas): pontuação e diária padrão, contato. Só G A M.';

-- (adendo extras v3, §E.7.5) pontuação pendente (extra importado sem pontos)
alter table public.extras add column if not exists pontos_pendente boolean not null default false;

alter table public.extras enable row level security;
drop policy if exists extras_ler on public.extras;
create policy extras_ler on public.extras for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop trigger if exists extras_tocar on public.extras;
create trigger extras_tocar before update on public.extras
  for each row execute function public.tocar_atualizado_em();

-- itens de comissão de extras (colunas em …0220)
alter table public.comissao_itens drop constraint if exists comissao_itens_extra_fk;
alter table public.comissao_itens add constraint comissao_itens_extra_fk
  foreign key (extra_id) references public.extras (id) on delete set null;
alter table public.comissao_itens drop constraint if exists comissao_itens_participante;
alter table public.comissao_itens add constraint comissao_itens_participante
  check ((tipo = 'funcionario' and extra_id is null) or (tipo = 'extra' and funcionario_id is null));

-- ================================================================ valor padrão da diária do funcionário
create table if not exists public.funcionario_valores_diaria (
  funcionario_id         uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  valor_diaria_centavos  bigint not null check (valor_diaria_centavos between 0 and 100000000),
  atualizado_por         uuid references public.perfis (id) on delete set null,
  atualizado_em          timestamptz not null default now()
);
create index if not exists funcionario_valores_diaria_empresa_idx on public.funcionario_valores_diaria (empresa_id);
create index if not exists funcionario_valores_diaria_atualizado_por_idx on public.funcionario_valores_diaria (atualizado_por);
comment on table public.funcionario_valores_diaria is
  '[api:leitura] Valor padrão da diária do funcionário (fora de funcionarios: a leitura não vê valores).';

-- ================================================================ dias trabalhados / diárias (E.2)
create table if not exists public.diarias (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  tipo             text not null default 'funcionario',
  extra_id         uuid references public.extras (id),
  funcionario_id   uuid references public.funcionarios (id) on delete set null,
  pessoa_nome      text not null check (btrim(pessoa_nome) <> ''),
  data             date not null,
  funcao           text,
  pontos           numeric(8,2),
  valor_centavos   bigint not null check (valor_centavos between 0 and 100000000),
  observacao       text,
  pago             boolean not null default false,
  pago_em          date,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint diarias_pagamento check (pago or pago_em is null)
);

-- Atualização por cima da v1 (diarias sem "tipo"): cada diária avulsa vira um extra cadastrado (pontos 0).
do $$
declare r record; v_nome text; v_extra uuid;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'diarias' and column_name = 'tipo') then
    return;
  end if;
  alter table public.diarias add column tipo text not null default 'funcionario';
  alter table public.diarias add column extra_id uuid references public.extras (id);
  alter table public.diarias add column pontos numeric(8,2);
  for r in
    select d.id, d.empresa_id, btrim(d.pessoa_nome) as nome, d.funcao, d.valor_centavos,
           row_number() over (partition by d.empresa_id, lower(btrim(d.pessoa_nome)), d.data order by d.criado_em, d.id) as rn
      from public.diarias d
     where d.funcionario_id is null
     order by d.empresa_id, d.data desc, d.criado_em desc, d.id
  loop
    v_nome := r.nome || case when r.rn > 1 then ' (' || r.rn || ')' else '' end;
    v_extra := null;
    select x.id into v_extra from public.extras x
     where x.empresa_id = r.empresa_id and lower(x.nome) = lower(v_nome) order by x.criado_em, x.id limit 1;
    if v_extra is null then
      insert into public.extras (empresa_id, nome, funcao, pontos_padrao, valor_diaria_centavos, observacoes)
      values (r.empresa_id, v_nome, r.funcao, 0, r.valor_centavos, 'Cadastrado automaticamente a partir de diária avulsa.')
      returning id into v_extra;
    end if;
    update public.diarias set tipo = 'extra', extra_id = v_extra, pontos = 0 where id = r.id;
  end loop;
end $$;

alter table public.diarias add column if not exists tipo text not null default 'funcionario';
alter table public.diarias add column if not exists extra_id uuid references public.extras (id);
alter table public.diarias add column if not exists pontos numeric(8,2);
alter table public.diarias drop constraint if exists diarias_tipo_check;
alter table public.diarias add constraint diarias_tipo_check check (tipo in ('extra', 'funcionario'));
alter table public.diarias drop constraint if exists diarias_pontos_check;
alter table public.diarias add constraint diarias_pontos_check check (pontos between 0 and 9999.99);
alter table public.diarias drop constraint if exists diarias_participante;
alter table public.diarias add constraint diarias_participante check (
  (tipo = 'extra' and extra_id is not null and funcionario_id is null and pontos is not null)
  or (tipo = 'funcionario' and extra_id is null and pontos is null));
-- (adendo extras v3, §E.7.5) dia de extra sem pontuação: vale 0 e não entra no rateio até a pontuação ser preenchida
alter table public.diarias add column if not exists pontos_pendente boolean not null default false;
alter table public.diarias drop constraint if exists diarias_pontos_pendente;
alter table public.diarias add constraint diarias_pontos_pendente check (not pontos_pendente or (tipo = 'extra' and pontos = 0));
create index if not exists diarias_empresa_idx on public.diarias (empresa_id, data);
create index if not exists diarias_funcionario_idx on public.diarias (funcionario_id, data);
create unique index if not exists diarias_extra_dia_uidx on public.diarias (extra_id, data) where extra_id is not null;
create index if not exists diarias_extra_idx on public.diarias (extra_id);
create index if not exists diarias_criado_por_idx on public.diarias (criado_por);
comment on table public.diarias is
  '[api:leitura] Dias trabalhados: de extra (pontos entram na comissão do dia) ou de funcionário (só custo). Só G A M.';

alter table public.funcionario_valores_diaria enable row level security;
alter table public.diarias enable row level security;
drop policy if exists funcionario_valores_diaria_ler on public.funcionario_valores_diaria;
create policy funcionario_valores_diaria_ler on public.funcionario_valores_diaria for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists diarias_ler on public.diarias;
create policy diarias_ler on public.diarias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop trigger if exists a_empresa on public.funcionario_valores_diaria;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.funcionario_valores_diaria
  for each row execute function public.ponto_empresa_do_funcionario();

-- diária: empresa_id do extra ou do funcionário (divergente = erro); funcionário excluído mantém a empresa.
create or replace function public.diarias_antes_gravar()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if new.extra_id is not null then
    select x.empresa_id into v_empresa from public.extras x where x.id = new.extra_id;
    if v_empresa is null then raise exception 'Extra não encontrado' using errcode = 'P0002'; end if;
    if new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Extra de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  elsif new.funcionario_id is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  end if;
  if tg_op = 'UPDATE' then
    if new.funcionario_id is null and new.extra_id is null and new.empresa_id is distinct from old.empresa_id then
      new.empresa_id := old.empresa_id;
    end if;
    new.atualizado_em := now();
  end if;
  return new;
end $$;
comment on function public.diarias_antes_gravar() is '[interno] Gatilho de diarias: empresa do extra/funcionário; atualizado_em.';
drop trigger if exists a_antes on public.diarias;
create trigger a_antes before insert or update on public.diarias
  for each row execute function public.diarias_antes_gravar();

-- ================================================================ RPCs do cadastro de extras
create or replace function public.extra_para_operar(p_extra uuid)
returns public.extras language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  select * into x from public.extras where id = p_extra;
  if not found then raise exception 'Extra não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(x.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return x;
end $$;
comment on function public.extra_para_operar(uuid) is '[interno] Extra existente e operável (G A M).';

create or replace function public.extra_validar(p_nome text, p_pontos numeric, p_valor bigint)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if nullif(btrim(coalesce(p_nome, '')), '') is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  if p_pontos is null or p_pontos < 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2) then
    raise exception 'Pontos inválidos' using errcode = '22023';
  end if;
  if p_valor is not null and (p_valor < 0 or p_valor > 100000000) then raise exception 'Valor inválido' using errcode = '22023'; end if;
end $$;
comment on function public.extra_validar(text, numeric, bigint) is '[interno] Validação do cadastro de extra (E.1).';

create or replace function public.extra_criar(p_nome text, p_funcao text default null, p_pontos_padrao numeric default 0,
                                              p_valor_diaria_centavos bigint default null, p_telefone text default null,
                                              p_documento text default null, p_observacoes text default null,
                                              p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.extra_validar(p_nome, coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos);
  insert into public.extras (empresa_id, nome, funcao, telefone, documento, pontos_padrao, valor_diaria_centavos, observacoes, criado_por)
  values (v_empresa, btrim(p_nome), nullif(btrim(p_funcao), ''), nullif(btrim(p_telefone), ''), nullif(btrim(p_documento), ''),
          coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos, nullif(btrim(p_observacoes), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.extra_criar(text, text, numeric, bigint, text, text, text, uuid) is '[api] Cadastra um extra (freela) (G A M).';

create or replace function public.extra_atualizar(p_extra uuid, p_nome text, p_funcao text, p_pontos_padrao numeric,
                                                  p_valor_diaria_centavos bigint, p_telefone text, p_documento text,
                                                  p_ativo boolean, p_observacoes text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  x := public.extra_para_operar(p_extra);
  perform public.extra_validar(p_nome, coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos);
  update public.extras
     set nome = btrim(p_nome), funcao = nullif(btrim(p_funcao), ''), telefone = nullif(btrim(p_telefone), ''),
         documento = nullif(btrim(p_documento), ''),
         pontos_padrao = case when x.pontos_pendente and p_pontos_padrao is null then x.pontos_padrao
                              else coalesce(p_pontos_padrao, 0) end,
         valor_diaria_centavos = p_valor_diaria_centavos, ativo = coalesce(p_ativo, true),
         observacoes = nullif(btrim(p_observacoes), '')
   where id = x.id;
  -- (v3, §E.7.5) extra pendente: pontos informados = preencher a pontuação (cadastro e dias pendentes)
  if x.pontos_pendente and p_pontos_padrao is not null then
    perform public.extra_definir_pontuacao(x.id, p_pontos_padrao);
  end if;
end $$;
comment on function public.extra_atualizar(uuid, text, text, numeric, bigint, text, text, boolean, text) is
  '[api] Substitui os dados do cadastro de um extra (G A M).';

create or replace function public.extra_excluir(p_extra uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  x := public.extra_para_operar(p_extra);
  if exists (select 1 from public.diarias d where d.extra_id = x.id) then
    raise exception 'Extra com dias lançados: desative em vez de excluir' using errcode = '22023';
  end if;
  delete from public.extras where id = x.id;
end $$;
comment on function public.extra_excluir(uuid) is '[api] Exclui um extra sem dias lançados (G A M).';

-- (v3) retorno ganhou pontos_pendente/dias_pendentes: mudança de tipo de retorno exige drop (privilégios voltam na …0900)
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'extras_listar'
                and pg_get_function_result(p.oid) not like '%dias_pendentes%') then
    drop function public.extras_listar(boolean, uuid);
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'diarias_listar'
                and pg_get_function_result(p.oid) not like '%pontos_pendente%') then
    drop function public.diarias_listar(date, date, text, uuid, uuid, boolean, uuid);
  end if;
end $$;

create or replace function public.extras_listar(p_incluir_inativos boolean default false, p_empresa uuid default null)
returns table (id uuid, nome text, funcao text, telefone text, documento text, pontos_padrao numeric, valor_diaria_centavos bigint,
               ativo boolean, observacoes text, pontos_pendente boolean, dias_lancados int, ultimo_dia date, dias_pendentes int,
               criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  return query
  select x.id, x.nome, x.funcao, x.telefone, x.documento, x.pontos_padrao, x.valor_diaria_centavos, x.ativo, x.observacoes,
         x.pontos_pendente, coalesce(l.qtd, 0)::int, l.ultimo, coalesce(l.pend, 0)::int, x.criado_em
    from public.extras x
    left join lateral (select count(*) as qtd, max(d.data) as ultimo, count(*) filter (where d.pontos_pendente) as pend
                         from public.diarias d where d.extra_id = x.id) l on true
   where x.empresa_id = v_empresa and (coalesce(p_incluir_inativos, false) or x.ativo)
   order by lower(x.nome), x.id;
end $$;
comment on function public.extras_listar(boolean, uuid) is '[api] Extras cadastrados da empresa (G A M).';

-- ================================================================ RPCs de valor padrão (funcionário)
create or replace function public.funcionario_definir_valor_diaria(p_funcionario uuid, p_valor_centavos bigint)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios;
begin
  f := public.funcionario_para_operar(p_funcionario);
  if p_valor_centavos is null then
    delete from public.funcionario_valores_diaria where funcionario_id = f.id;
    return;
  end if;
  if p_valor_centavos < 0 or p_valor_centavos > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
  insert into public.funcionario_valores_diaria (funcionario_id, empresa_id, valor_diaria_centavos, atualizado_por, atualizado_em)
  values (f.id, f.empresa_id, p_valor_centavos, public.meu_perfil_id(), now())
  on conflict (funcionario_id) do update
    set valor_diaria_centavos = excluded.valor_diaria_centavos, atualizado_por = excluded.atualizado_por,
        atualizado_em = excluded.atualizado_em;
end $$;
comment on function public.funcionario_definir_valor_diaria(uuid, bigint) is
  '[api] Define (ou remove, null) o valor padrão da diária do funcionário (G A M).';

create or replace function public.funcionario_valores_diaria_listar(p_empresa uuid default null)
returns table (funcionario_id uuid, valor_diaria_centavos bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  return query select v.funcionario_id, v.valor_diaria_centavos from public.funcionario_valores_diaria v
                where v.empresa_id = v_empresa order by v.funcionario_id;
end $$;
comment on function public.funcionario_valores_diaria_listar(uuid) is '[api] Valores padrão de diária da empresa (G A M).';

-- ================================================================ RPCs de dias trabalhados (E.2)
create or replace function public.diaria_validar_valores(p_empresa uuid, p_data date, p_pontos numeric, p_valor bigint,
                                                         p_extra boolean)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date;
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.dia_de_trabalho(public.agora(), p_empresa);
  if p_data < v_hoje - 366 or p_data > v_hoje + 62 then raise exception 'Data fora do limite' using errcode = '22023'; end if;
  if p_extra and (p_pontos is null or p_pontos < 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2)) then
    raise exception 'Pontos inválidos' using errcode = '22023';
  end if;
  if p_valor is null then raise exception 'Informe o valor da diária' using errcode = '22023'; end if;
  if p_valor < 0 or p_valor > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
end $$;
comment on function public.diaria_validar_valores(uuid, date, numeric, bigint, boolean) is '[interno] Validação de dia trabalhado (E.2).';

create or replace function public.diaria_checar_trava(p_empresa uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if public.comissao_periodo_fechado(p_empresa, p_data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
end $$;
comment on function public.diaria_checar_trava(uuid, date) is '[interno] Dia de extra em fechamento fechado é recusado (E.2).';

create or replace function public.diaria_checar_duplicada(p_extra uuid, p_data date, p_ignorar uuid default null)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from public.diarias d where d.extra_id = p_extra and d.data = p_data
                                              and (p_ignorar is null or d.id <> p_ignorar)) then
    raise exception 'Extra já tem dia lançado em %', to_char(p_data, 'DD/MM/YYYY') using errcode = '23505';
  end if;
end $$;
comment on function public.diaria_checar_duplicada(uuid, date, uuid) is '[interno] Um lançamento por extra por dia (E.2).';

create or replace function public.diaria_lancar(p_data date, p_extra uuid default null, p_funcionario uuid default null,
                                                p_pontos numeric default null, p_valor_centavos bigint default null,
                                                p_funcao text default null, p_observacao text default null,
                                                p_pago boolean default false, p_pago_em date default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras; f public.funcionarios; v_empresa uuid; v_pontos numeric; v_valor bigint; v_funcao text;
        v_nome text; v_pago boolean; v_id uuid; v_pend boolean := false;
begin
  if (p_extra is null) = (p_funcionario is null) then
    raise exception 'Informe o extra ou o funcionário' using errcode = '22023';
  end if;
  if p_extra is not null then
    x := public.extra_para_operar(p_extra);
    if not x.ativo then raise exception 'Extra inativo' using errcode = '22023'; end if;
    v_empresa := x.empresa_id; v_nome := x.nome;
    v_pontos := coalesce(p_pontos, x.pontos_padrao);
    v_pend := x.pontos_pendente and p_pontos is null;     -- (v3) extra sem pontuação: dia pendente (vale 0)
    if v_pend then v_pontos := 0; end if;
    v_valor := coalesce(p_valor_centavos, x.valor_diaria_centavos);
    v_funcao := coalesce(nullif(btrim(p_funcao), ''), x.funcao);
  else
    f := public.funcionario_para_operar(p_funcionario);
    if p_pontos is not null then raise exception 'Diária de funcionário não tem pontos' using errcode = '22023'; end if;
    v_empresa := f.empresa_id; v_nome := f.nome;
    v_valor := coalesce(p_valor_centavos,
                        (select v.valor_diaria_centavos from public.funcionario_valores_diaria v where v.funcionario_id = f.id));
    v_funcao := coalesce(nullif(btrim(p_funcao), ''), f.cargo);
  end if;
  perform public.diaria_validar_valores(v_empresa, p_data, v_pontos, v_valor, p_extra is not null);
  if p_extra is not null then
    perform public.diaria_checar_trava(v_empresa, p_data);
    perform public.diaria_checar_duplicada(x.id, p_data);
  end if;
  v_pago := coalesce(p_pago, false);
  insert into public.diarias (empresa_id, tipo, extra_id, funcionario_id, pessoa_nome, data, funcao, pontos, pontos_pendente,
                              valor_centavos, observacao, pago, pago_em, criado_por, criado_por_nome)
  values (v_empresa, case when p_extra is not null then 'extra' else 'funcionario' end, x.id, f.id, v_nome, p_data, v_funcao,
          v_pontos, v_pend, v_valor, nullif(btrim(p_observacao), ''), v_pago,
          case when v_pago then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), v_empresa)) end,
          public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.diaria_lancar(date, uuid, uuid, numeric, bigint, text, text, boolean, date) is
  '[api] Lança um dia trabalhado de extra (com pontos) ou diária de funcionário (G A M).';

create or replace function public.diaria_para_operar(p_diaria uuid)
returns public.diarias language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  select * into d from public.diarias where id = p_diaria;
  if not found then raise exception 'Diária não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(d.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return d;
end $$;
comment on function public.diaria_para_operar(uuid) is '[interno] Diária existente e operável (G A M).';

create or replace function public.diaria_atualizar(p_diaria uuid, p_data date, p_pontos numeric, p_valor_centavos bigint,
                                                   p_funcao text, p_observacao text, p_pago boolean, p_pago_em date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias; v_data date; v_pontos numeric; v_valor bigint; v_funcao_padrao text;
begin
  d := public.diaria_para_operar(p_diaria);
  if d.tipo = 'funcionario' and p_pontos is not null then
    raise exception 'Diária de funcionário não tem pontos' using errcode = '22023';
  end if;
  v_data := coalesce(p_data, d.data);
  v_pontos := case when d.tipo = 'extra' then coalesce(p_pontos, d.pontos) end;
  v_valor := coalesce(p_valor_centavos, d.valor_centavos);
  if v_data <> d.data then
    perform public.diaria_validar_valores(d.empresa_id, v_data, v_pontos, v_valor, d.tipo = 'extra');
  else
    -- data inalterada: não reaplica o limite de data (lançamento antigo continua editável, ex.: marcar pago)
    if d.tipo = 'extra' and (v_pontos < 0 or v_pontos > 9999.99 or v_pontos <> round(v_pontos, 2)) then
      raise exception 'Pontos inválidos' using errcode = '22023';
    end if;
    if v_valor < 0 or v_valor > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
  end if;
  if d.tipo = 'extra' and (v_data <> d.data or v_pontos <> d.pontos or (d.pontos_pendente and p_pontos is not null)) then
    perform public.diaria_checar_trava(d.empresa_id, d.data);
    perform public.diaria_checar_trava(d.empresa_id, v_data);
    if v_data <> d.data then perform public.diaria_checar_duplicada(d.extra_id, v_data, d.id); end if;
  end if;
  select coalesce((select x.funcao from public.extras x where x.id = d.extra_id),
                  (select f.cargo from public.funcionarios f where f.id = d.funcionario_id)) into v_funcao_padrao;
  update public.diarias
     set data = v_data, pontos = v_pontos, valor_centavos = v_valor,
         pontos_pendente = pontos_pendente and p_pontos is null,     -- (v3) pontos informados tiram a pendência
         funcao = coalesce(nullif(btrim(p_funcao), ''), v_funcao_padrao),
         observacao = nullif(btrim(p_observacao), ''),
         pago = coalesce(p_pago, pago),
         pago_em = case when p_pago is null then pago_em
                        when p_pago then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), d.empresa_id)) end
   where id = d.id;
end $$;
comment on function public.diaria_atualizar(uuid, date, numeric, bigint, text, text, boolean, date) is
  '[api] Edita um dia trabalhado/diária (null mantém data, pontos, valor e pagamento) (G A M).';

create or replace function public.diaria_marcar_paga(p_diaria uuid, p_pago boolean, p_pago_em date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  d := public.diaria_para_operar(p_diaria);
  update public.diarias
     set pago = coalesce(p_pago, false),
         pago_em = case when coalesce(p_pago, false)
                        then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), d.empresa_id)) end
   where id = d.id;
end $$;
comment on function public.diaria_marcar_paga(uuid, boolean, date) is '[api] Marca/desmarca a diária como paga (G A M).';

create or replace function public.diaria_excluir(p_diaria uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  d := public.diaria_para_operar(p_diaria);
  if d.tipo = 'extra' then perform public.diaria_checar_trava(d.empresa_id, d.data); end if;
  delete from public.diarias where id = d.id;
end $$;
comment on function public.diaria_excluir(uuid) is '[api] Exclui um dia trabalhado/diária (G A M).';

create or replace function public.diarias_listar(p_inicio date, p_fim date, p_tipo text default null, p_extra uuid default null,
                                                 p_funcionario uuid default null, p_pago boolean default null,
                                                 p_empresa uuid default null)
returns table (id uuid, data date, tipo text, extra_id uuid, funcionario_id uuid, pessoa_nome text, funcao text, pontos numeric,
               pontos_pendente boolean, valor_centavos bigint, observacao text, pago boolean, pago_em date, fechado boolean, criado_por_nome text,
               criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_extra is not null then
    v_empresa := (public.extra_para_operar(p_extra)).empresa_id;
  elsif p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  if p_tipo is not null and p_tipo not in ('extra', 'funcionario') then raise exception 'Tipo inválido' using errcode = '22023'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select d.id, d.data, d.tipo, d.extra_id, d.funcionario_id, coalesce(x.nome, f.nome, d.pessoa_nome), d.funcao, d.pontos,
         d.pontos_pendente, d.valor_centavos, d.observacao, d.pago, d.pago_em,
         d.tipo = 'extra' and public.comissao_periodo_fechado(d.empresa_id, d.data), d.criado_por_nome, d.criado_em
    from public.diarias d
    left join public.extras x on x.id = d.extra_id
    left join public.funcionarios f on f.id = d.funcionario_id
   where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
     and (p_tipo is null or d.tipo = p_tipo)
     and (p_extra is null or d.extra_id = p_extra)
     and (p_funcionario is null or d.funcionario_id = p_funcionario)
     and (p_pago is null or d.pago = p_pago)
   order by d.data desc, coalesce(x.nome, f.nome, d.pessoa_nome), d.criado_em, d.id;
end $$;
comment on function public.diarias_listar(date, date, text, uuid, uuid, boolean, uuid) is '[api] Dias trabalhados/diárias do período (G A M).';

-- ================================================================ gastos por período (E.5)
create or replace function public.gastos_periodo(p_inicio date, p_fim date, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return (
    with fech as (   -- fechamentos que contribuem: diário que cruza o período; período com data_fim dentro
      select fc.* from public.comissao_fechamentos fc
       where fc.empresa_id = v_empresa
         and ((fc.modo_rateio = 'diario' and fc.data_inicio <= p_fim and fc.data_fim >= p_inicio)
              or (fc.modo_rateio = 'periodo' and fc.data_fim between p_inicio and p_fim))
    ),
    com as (         -- valores de comissão: diário pelo detalhe (no dia), período inteiro em data_fim
      select fe.id as fechamento_id, fe.status, it.tipo, it.funcionario_id, it.extra_id, it.funcionario_nome, ri.data,
             ri.valor_centavos as valor
        from fech fe
        join public.comissao_rateio_itens_dia ri on ri.fechamento_id = fe.id
        join public.comissao_itens it on it.id = ri.item_id
       where fe.modo_rateio = 'diario' and ri.data between p_inicio and p_fim
      union all
      select fe.id, fe.status, it.tipo, it.funcionario_id, it.extra_id, it.funcionario_nome, fe.data_fim, it.valor_centavos
        from fech fe join public.comissao_itens it on it.fechamento_id = fe.id
       where fe.modo_rateio = 'periodo'
    ),
    lanc as (        -- uma linha por valor: (chave, tipo, ids, nome, data, coluna, valor, qtd)
      select case when d.extra_id is not null then 'x:' || d.extra_id
                  when d.funcionario_id is not null then 'f:' || d.funcionario_id
                  else 'n:' || lower(btrim(d.pessoa_nome)) end as chave,
             d.tipo, d.funcionario_id, d.extra_id, coalesce(x.nome, f.nome, d.pessoa_nome) as nome, d.data,
             case when d.pago then 'diarias_pagas' else 'diarias_a_pagar' end as coluna, d.valor_centavos as valor, 1 as qtd
        from public.diarias d
        left join public.extras x on x.id = d.extra_id
        left join public.funcionarios f on f.id = d.funcionario_id
       where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
      union all
      select case when c.extra_id is not null then 'x:' || c.extra_id
                  when c.funcionario_id is not null then 'f:' || c.funcionario_id
                  else 'n:' || lower(btrim(c.funcionario_nome)) end,
             c.tipo, c.funcionario_id, c.extra_id, coalesce(x.nome, f.nome, c.funcionario_nome), c.data,
             case when c.status = 'fechado' then 'comissoes_fechadas' else 'comissoes_previstas' end, c.valor, 0
        from com c
        left join public.extras x on x.id = c.extra_id
        left join public.funcionarios f on f.id = c.funcionario_id
    ),
    tot as (
      select coalesce(sum(valor) filter (where coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(valor) filter (where coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(valor) filter (where qtd = 1 and tipo = 'extra'), 0) as dx,
             coalesce(sum(valor) filter (where qtd = 1 and tipo = 'funcionario'), 0) as dfu,
             coalesce(sum(qtd), 0) as qtd,
             coalesce(sum(valor) filter (where coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(valor) filter (where coluna = 'comissoes_previstas'), 0) as cp
        from lanc
    ),
    pessoa as (
      select chave, (array_agg(tipo))[1] as tipo,
             (array_agg(funcionario_id) filter (where funcionario_id is not null))[1] as funcionario_id,
             (array_agg(extra_id) filter (where extra_id is not null))[1] as extra_id,
             (array_agg(nome order by nome))[1] as nome,
             sum(qtd) as qtd,
             coalesce(sum(valor) filter (where coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(valor) filter (where coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(valor) filter (where coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(valor) filter (where coluna = 'comissoes_previstas'), 0) as cp
        from lanc group by chave
    ),
    dia as (
      select g::date as data,
             coalesce(sum(l.valor) filter (where l.coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(l.valor) filter (where l.coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(l.valor) filter (where l.coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(l.valor) filter (where l.coluna = 'comissoes_previstas'), 0) as cp
        from generate_series(p_inicio::timestamp, p_fim::timestamp, interval '1 day') g
        left join lanc l on l.data = g::date
       group by g
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'inicio', p_inicio, 'fim', p_fim,
      'totais', (select jsonb_build_object('diarias_pagas', dp, 'diarias_a_pagar', dap, 'diarias', dp + dap, 'diarias_qtd', qtd,
                                           'diarias_extras', dx, 'diarias_funcionarios', dfu,
                                           'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                           'total', dp + dap + cf, 'total_com_previsto', dp + dap + cf + cp) from tot),
      'por_pessoa', coalesce((select jsonb_agg(jsonb_build_object(
                         'chave', chave, 'tipo', tipo, 'funcionario_id', funcionario_id, 'extra_id', extra_id, 'nome', nome,
                         'diarias_qtd', qtd, 'diarias_pagas', dp, 'diarias_a_pagar', dap, 'comissoes_fechadas', cf,
                         'comissoes_previstas', cp, 'total', dp + dap + cf) order by dp + dap + cf desc, nome collate "C", chave)
                       from pessoa where qtd > 0 or dp + dap + cf + cp > 0), '[]'::jsonb),
      'por_dia', (select jsonb_agg(jsonb_build_object('data', data, 'diarias_pagas', dp, 'diarias_a_pagar', dap,
                                                      'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                                      'total', dp + dap + cf) order by data) from dia),
      'fechamentos', coalesce((select jsonb_agg(jsonb_build_object(
                                 'id', fe.id, 'titulo', fe.titulo, 'status', fe.status, 'modo_rateio', fe.modo_rateio,
                                 'data_inicio', fe.data_inicio, 'data_fim', fe.data_fim,
                                 'base_distribuivel_centavos', fe.base_distribuivel_centavos,
                                 'valor_no_periodo_centavos', coalesce((select sum(c.valor) from com c where c.fechamento_id = fe.id), 0))
                               order by fe.data_fim, fe.titulo, fe.id) from fech fe), '[]'::jsonb))
  );
end $$;
comment on function public.gastos_periodo(date, date, uuid) is
  '[api] Gastos do período: diárias (extras e funcionários, pagas/a pagar) e comissões (fechadas/previstas), por pessoa e por dia (G A M).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000260_extras.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000270_reservas.sql
-- =====================================================================================================
-- 20261006000270_reservas.sql — backend (adendo extras/ocorrências/reservas, seção R)
-- Reservas do dia: cadastro manual, importação de CSV (front) e ingestão genérica da Tagme (N8N, tipo de integração
-- 'tagme' ajustado em …0120). Telefone/e-mail são dados pessoais: só G A M (leitura lê por reservas_listar, sem eles).
-- Idempotente.
-- =====================================================================================================

create table if not exists public.reservas (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  integracao_id  uuid references public.integracoes (id) on delete set null,
  origem         text not null check (origem in ('tagme', 'manual', 'importacao')),
  id_externo     text,
  data           date not null,
  horario        time,
  nome_cliente   text not null check (btrim(nome_cliente) <> ''),
  pessoas        int not null default 1 check (pessoas between 1 and 500),
  status         text not null default 'confirmada'
                 check (status in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu')),
  area           text,
  mesa           text,
  observacao     text,
  telefone       text,
  email          text,
  criado_por     uuid references public.perfis (id) on delete set null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  importado_em   timestamptz,
  constraint reservas_externa_uk unique (empresa_id, origem, id_externo),
  constraint reservas_tagme_id check (origem <> 'tagme' or id_externo is not null)
);
create index if not exists reservas_empresa_dia_idx on public.reservas (empresa_id, data, horario);
create index if not exists reservas_integracao_idx on public.reservas (integracao_id);
create index if not exists reservas_criado_por_idx on public.reservas (criado_por);
comment on table public.reservas is
  '[api:leitura] Reservas (Tagme, manuais, importadas). Select direto só G A M; leitura via reservas_listar (sem telefone/e-mail).';

alter table public.reservas enable row level security;
drop policy if exists reservas_ler on public.reservas;
create policy reservas_ler on public.reservas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop trigger if exists tocar_atualizado_em on public.reservas;
create trigger tocar_atualizado_em before update on public.reservas
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ auxiliares
create or replace function public.reserva_validar(p_data date, p_nome text, p_pessoas int, p_status text)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if nullif(btrim(coalesce(p_nome, '')), '') is null then raise exception 'Informe o nome do cliente' using errcode = '22023'; end if;
  if p_pessoas is null or p_pessoas < 1 or p_pessoas > 500 then
    raise exception 'Número de pessoas inválido' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'Status de reserva inválido' using errcode = '22023';
  end if;
end $$;
comment on function public.reserva_validar(date, text, int, text) is '[interno] Validação de reserva (adendo R.3).';

create or replace function public.reserva_para_operar(p_reserva uuid)
returns public.reservas language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  select * into r from public.reservas where id = p_reserva;
  if not found then raise exception 'Reserva não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(r.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return r;
end $$;
comment on function public.reserva_para_operar(uuid) is '[interno] Reserva existente e operável (G A M).';

-- Data 'AAAA-MM-DD' ou 'DD/MM/AAAA' → date (null se inválida).
create or replace function public.reserva_ler_data(p_texto text)
returns date language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t ~ '^\d{4}-\d{2}-\d{2}$' then return to_date(t, 'YYYY-MM-DD')::date
    + case when to_char(to_date(t, 'YYYY-MM-DD'), 'YYYY-MM-DD') = t then 0 else null end;
  elsif t ~ '^\d{2}/\d{2}/\d{4}$' then return to_date(t, 'DD/MM/YYYY')::date
    + case when to_char(to_date(t, 'DD/MM/YYYY'), 'DD/MM/YYYY') = t then 0 else null end;
  end if;
  return null;
exception when others then return null;
end $$;
comment on function public.reserva_ler_data(text) is '[interno] Lê data AAAA-MM-DD ou DD/MM/AAAA.';

-- Horário 'HH:MM' ou 'HH:MM:SS' → time. Vazio → null; inválido → exceção 'horário inválido'.
create or replace function public.reserva_ler_horario(p_texto text)
returns time language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t = '' then return null; end if;
  if t !~ '^([01]?\d|2[0-3]):[0-5]\d(:[0-5]\d)?$' then raise exception 'horário inválido'; end if;
  return t::time;
end $$;
comment on function public.reserva_ler_horario(text) is '[interno] Lê horário HH:MM[:SS].';

-- Converte um item jsonb (importação/ingestão) em campos de reserva; erro → exceção com o motivo (texto curto).
create or replace function public.reserva_ler_item(p_item jsonb, p_chave_hora text,
                                                   out data date, out horario time, out nome text, out pessoas int,
                                                   out status text, out telefone text, out email text, out area text,
                                                   out mesa text, out observacao text, out id_externo text)
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare v text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then raise exception 'item inválido'; end if;
  data := public.reserva_ler_data(p_item ->> 'data');
  if data is null then raise exception 'data inválida'; end if;
  horario := public.reserva_ler_horario(p_item ->> p_chave_hora);
  nome := nullif(btrim(coalesce(p_item ->> 'nome', p_item ->> 'nome_cliente', '')), '');
  if nome is null then raise exception 'informe o nome'; end if;
  v := btrim(coalesce(p_item ->> 'pessoas', ''));
  if v = '' then pessoas := 1;
  elsif v ~ '^\d{1,4}$' and v::int between 1 and 500 then pessoas := v::int;
  else raise exception 'pessoas inválido';
  end if;
  status := coalesce(nullif(btrim(p_item ->> 'status'), ''), 'confirmada');
  if status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'status inválido';
  end if;
  telefone := nullif(btrim(p_item ->> 'telefone'), '');
  email := nullif(btrim(p_item ->> 'email'), '');
  area := nullif(btrim(p_item ->> 'area'), '');
  mesa := nullif(btrim(p_item ->> 'mesa'), '');
  observacao := nullif(btrim(p_item ->> 'observacao'), '');
  id_externo := nullif(btrim(p_item ->> 'id_externo'), '');
end $$;
comment on function public.reserva_ler_item(jsonb, text) is '[interno] Item de importação/ingestão de reserva → campos.';

-- ================================================================ RPCs (front)
create or replace function public.reserva_criar(p_data date, p_horario time, p_nome_cliente text, p_pessoas int default 1,
                                                p_telefone text default null, p_area text default null, p_mesa text default null,
                                                p_observacao text default null, p_status text default 'confirmada',
                                                p_email text default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.reserva_validar(p_data, p_nome_cliente, coalesce(p_pessoas, 1), coalesce(p_status, 'confirmada'));
  insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                               telefone, email, criado_por)
  values (v_empresa, 'manual', p_data, p_horario, btrim(p_nome_cliente), coalesce(p_pessoas, 1), coalesce(p_status, 'confirmada'),
          nullif(btrim(p_area), ''), nullif(btrim(p_mesa), ''), nullif(btrim(p_observacao), ''),
          nullif(btrim(p_telefone), ''), nullif(btrim(p_email), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.reserva_criar(date, time, text, int, text, text, text, text, text, text, uuid) is
  '[api] Cria uma reserva manual (G A M).';

create or replace function public.reserva_atualizar(p_reserva uuid, p_data date, p_horario time, p_nome_cliente text,
                                                    p_pessoas int, p_telefone text, p_area text, p_mesa text,
                                                    p_observacao text, p_status text, p_email text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if r.origem = 'tagme' then
    raise exception 'Reserva da Tagme: só o status pode ser alterado' using errcode = '22023';
  end if;
  perform public.reserva_validar(p_data, p_nome_cliente, p_pessoas, p_status);
  update public.reservas
     set data = p_data, horario = p_horario, nome_cliente = btrim(p_nome_cliente), pessoas = p_pessoas, status = p_status,
         area = nullif(btrim(p_area), ''), mesa = nullif(btrim(p_mesa), ''), observacao = nullif(btrim(p_observacao), ''),
         telefone = nullif(btrim(p_telefone), ''), email = nullif(btrim(p_email), '')
   where id = r.id;
end $$;
comment on function public.reserva_atualizar(uuid, date, time, text, int, text, text, text, text, text, text) is
  '[api] Edita uma reserva manual/importada (G A M).';

create or replace function public.reserva_mudar_status(p_reserva uuid, p_status text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if p_status is null or p_status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'Status de reserva inválido' using errcode = '22023';
  end if;
  update public.reservas set status = p_status where id = r.id and status is distinct from p_status;
end $$;
comment on function public.reserva_mudar_status(uuid, text) is '[api] Muda o status de uma reserva (G A M).';

create or replace function public.reserva_cancelar(p_reserva uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform public.reserva_mudar_status(p_reserva, 'cancelada');
end $$;
comment on function public.reserva_cancelar(uuid) is '[api] Cancela uma reserva (G A M).';

create or replace function public.reserva_excluir(p_reserva uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if r.origem = 'tagme' then raise exception 'Reserva da Tagme não pode ser excluída' using errcode = '22023'; end if;
  delete from public.reservas where id = r.id;
end $$;
comment on function public.reserva_excluir(uuid) is '[api] Exclui uma reserva manual/importada (G A M).';

create or replace function public.reservas_listar(p_inicio date, p_fim date default null, p_status text[] default null,
                                                  p_empresa uuid default null)
returns table (id uuid, origem text, data date, horario time, nome_cliente text, pessoas int, status text, area text, mesa text,
               observacao text, telefone text, email text, criado_em timestamptz, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_operar boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, coalesce(p_fim, p_inicio), 93);
  v_operar := public.pode_operar(v_empresa) is true;
  return query
  select r.id, r.origem, r.data, r.horario, r.nome_cliente, r.pessoas, r.status, r.area, r.mesa, r.observacao,
         case when v_operar then r.telefone end, case when v_operar then r.email end, r.criado_em, r.atualizado_em
    from public.reservas r
   where r.empresa_id = v_empresa and r.data between p_inicio and coalesce(p_fim, p_inicio)
     and (p_status is null or r.status = any (p_status))
   order by r.data, r.horario nulls last, r.nome_cliente, r.id;
end $$;
comment on function public.reservas_listar(date, date, text[], uuid) is
  '[api] Reservas do período (L G A M; telefone/e-mail só para G A M).';

create or replace function public.reservas_importar(p_linhas jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_ids text[] := '{}'; v_novo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_linhas) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_linhas) with ordinality as e(valor, ord) loop
    begin
      select * into c from public.reserva_ler_item(it.valor, 'horario');
      if c.id_externo is not null then
        if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
        v_ids := v_ids || c.id_externo;
      end if;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    if c.id_externo is null then
      insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                                   telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa, c.observacao,
              c.telefone, c.email, public.meu_perfil_id(), public.agora());
      v_ins := v_ins + 1;
    else
      insert into public.reservas as r (empresa_id, origem, id_externo, data, horario, nome_cliente, pessoas, status, area, mesa,
                                        observacao, telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
              c.observacao, c.telefone, c.email, public.meu_perfil_id(), public.agora())
      on conflict (empresa_id, origem, id_externo) do update
        set data = excluded.data, horario = excluded.horario, nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas,
            status = excluded.status, area = excluded.area, mesa = excluded.mesa, observacao = excluded.observacao,
            telefone = excluded.telefone, email = excluded.email, importado_em = excluded.importado_em
      returning (xmax = 0) into v_novo;
      if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('lidos', jsonb_array_length(p_linhas), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'erros', v_erros);
end $$;
comment on function public.reservas_importar(jsonb, uuid) is '[api] Importa reservas de um CSV lido pelo front (G A M).';

-- ================================================================ ingestão (N8N)
create or replace function public.ingestao_reservas(p_integracao uuid, p_inicio date, p_fim date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_rem int := 0; v_ids text[] := '{}'; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['tagme']);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_itens) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:reservas:' || ig.empresa_id::text, 0));

  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_itens) with ordinality as e(valor, ord) loop
    begin
      if it.valor is null or jsonb_typeof(it.valor) <> 'object' then raise exception 'item inválido'; end if;
      if nullif(btrim(it.valor ->> 'id_externo'), '') is null then raise exception 'id_externo ausente'; end if;
      select * into c from public.reserva_ler_item(it.valor, 'hora');
      if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
      v_ids := v_ids || c.id_externo;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    insert into public.reservas as r (empresa_id, integracao_id, origem, id_externo, data, horario, nome_cliente, pessoas, status,
                                      area, mesa, observacao, telefone, email, importado_em)
    values (ig.empresa_id, ig.id, 'tagme', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
            c.observacao, c.telefone, c.email, public.agora())
    on conflict (empresa_id, origem, id_externo) do update
      set integracao_id = excluded.integracao_id, data = excluded.data, horario = excluded.horario,
          nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas, status = excluded.status, area = excluded.area,
          mesa = excluded.mesa, observacao = excluded.observacao, telefone = excluded.telefone, email = excluded.email,
          importado_em = excluded.importado_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;

  delete from public.reservas r
   where r.empresa_id = ig.empresa_id and r.origem = 'tagme' and r.data between p_inicio and p_fim
     and not (r.id_externo = any (v_ids));
  get diagnostics v_rem = row_count;

  update public.integracoes
     set cursor = jsonb_build_object('ultimo_inicio', p_inicio, 'ultimo_fim', p_fim)
   where id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_itens), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'removidos', v_rem, 'erros', v_erros);
end $$;
comment on function public.ingestao_reservas(uuid, date, date, jsonb) is
  '[servico] Reservas da Tagme (N8N): upsert por id_externo e remove as da janela que não vieram (adendo R.3).';

-- Bloco "reservas" do painel (sem checagem; o painel já resolveu a empresa).
create or replace function public.reservas_painel(p_empresa uuid, p_hoje date, p_telefone boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with e as (select fuso from public.empresas where id = p_empresa),
       r as (select * from public.reservas where empresa_id = p_empresa and data = p_hoje)
  select jsonb_build_object(
    'total', (select count(*) from r where status <> 'cancelada'),
    'pessoas', (select coalesce(sum(pessoas), 0) from r where status <> 'cancelada'),
    'canceladas', (select count(*) from r where status = 'cancelada'),
    'nao_compareceu', (select count(*) from r where status = 'nao_compareceu'),
    'sentadas', (select count(*) from r where status = 'sentada'),
    'tem_tagme', exists (select 1 from public.integracoes i where i.empresa_id = p_empresa and i.tipo = 'tagme' and i.ativa),
    'proximas', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'horario', x.horario, 'nome_cliente', x.nome_cliente, 'pessoas', x.pessoas,
                                           'status', x.status, 'area', x.area, 'mesa', x.mesa, 'observacao', x.observacao,
                                           'origem', x.origem, 'telefone', case when p_telefone then x.telefone end)
                        order by x.horario nulls last, x.nome_cliente, x.id)
         from (select r.* from r, e
                where r.status in ('confirmada', 'pendente')
                  and (r.horario is null or ((r.data + r.horario) at time zone e.fuso) >= public.agora() - interval '30 minutes')
                order by r.horario nulls last, r.nome_cliente, r.id
                limit 10) x), '[]'::jsonb))
$$;
comment on function public.reservas_painel(uuid, date, boolean) is '[interno] Bloco reservas do painel_do_dia (adendo R.4).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000270_reservas.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000280_escala.sql
-- =====================================================================================================
-- 20261006000280_escala.sql — backend (docs/CONTRATO-ADENDO-escala.md)
-- Escala rotativa 5x2 (modelo Macaw): setores, membros (funcionários cadastrados) com folgas da semana base, caminhos
-- de rodízio contínuo a partir de uma data-âncora (segunda-feira) + fase, ajustes por dia (folga/trabalha/férias/chegada),
-- troca de folgas, férias → abono 'ferias' (ponto_abonos.escala_ajuste_id) e reapuração do ponto (máx. 62 dias).
-- A integração com a apuração está em ponto_calcular_dia (…0200), que chama escala_status_ponto (definida aqui).
-- Idempotente.
-- =====================================================================================================

-- ================================================================ tabelas
create table if not exists public.escala_config (
  empresa_id     uuid primary key references public.empresas (id) on delete cascade,
  ancora         date not null check (extract(isodow from ancora) = 1),
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table public.escala_config is '[api:leitura] Escala rotativa: data-âncora (segunda, semana 0) e fase por empresa.';

create table if not exists public.escala_setores (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ordem          int  not null default 0,
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create unique index if not exists escala_setores_nome_uk on public.escala_setores (empresa_id, lower(btrim(nome)));
create index if not exists escala_setores_empresa_idx on public.escala_setores (empresa_id, ordem);
comment on table public.escala_setores is '[api:leitura] Setores da escala (Salão, Bar, Cozinha...).';

create table if not exists public.escala_membros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  setor_id        uuid not null references public.escala_setores (id) on delete cascade,
  funcionario_id  uuid not null unique references public.funcionarios (id) on delete cascade,
  folgas_base     smallint[] not null default '{}',
  chegada_padrao  time,
  caminho         smallint check (caminho between 1 and 20),
  posicao         smallint check (posicao between 1 and 99),
  ordem           int not null default 0,
  modelo_posicao  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint escala_membros_caminho check ((caminho is null) = (posicao is null)),
  constraint escala_membros_folgas check (folgas_base <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
                                          and coalesce(array_length(folgas_base, 1), 0) <= 6)
);
create index if not exists escala_membros_empresa_idx on public.escala_membros (empresa_id);
create index if not exists escala_membros_setor_idx on public.escala_membros (setor_id, ordem);
create unique index if not exists escala_membros_posicao_uk on public.escala_membros (setor_id, caminho, posicao)
  where caminho is not null;
create unique index if not exists escala_membros_modelo_uk on public.escala_membros (empresa_id, modelo_posicao)
  where modelo_posicao is not null;
comment on table public.escala_membros is
  '[api:leitura] Funcionários na escala: setor, folgas da semana base (0=SEG..6=DOM), chegada padrão, caminho/posição do rodízio.';

create table if not exists public.escala_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  membro_id        uuid not null references public.escala_membros (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  status           text check (status in ('trabalha', 'folga', 'ferias')),
  chegada          time,
  motivo           text,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (funcionario_id, data),
  constraint escala_ajustes_algo check (status is not null or chegada is not null)
);
create index if not exists escala_ajustes_empresa_idx on public.escala_ajustes (empresa_id, data);
create index if not exists escala_ajustes_membro_idx on public.escala_ajustes (membro_id);
create index if not exists escala_ajustes_criado_por_idx on public.escala_ajustes (criado_por);
comment on table public.escala_ajustes is
  '[api:leitura] Ajustes da escala por dia (status e/ou chegada). Só G A M leem a tabela; leitura vê pela escala_mes.';

-- abono de férias gerado pela escala (coluna criada em …0200)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ponto_abonos_escala_ajuste_fk') then
    alter table public.ponto_abonos add constraint ponto_abonos_escala_ajuste_fk
      foreign key (escala_ajuste_id) references public.escala_ajustes (id) on delete cascade;
  end if;
end $$;

-- ================================================================ RLS
alter table public.escala_config enable row level security;
alter table public.escala_setores enable row level security;
alter table public.escala_membros enable row level security;
alter table public.escala_ajustes enable row level security;
drop policy if exists escala_config_ler on public.escala_config;
create policy escala_config_ler on public.escala_config for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_setores_ler on public.escala_setores;
create policy escala_setores_ler on public.escala_setores for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_membros_ler on public.escala_membros;
create policy escala_membros_ler on public.escala_membros for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_ajustes_ler on public.escala_ajustes;
create policy escala_ajustes_ler on public.escala_ajustes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
create or replace function public.escala_setores_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.escala_setores_antes() is '[interno] Gatilho: setor com nome aparado e empresa imutável.';
drop trigger if exists a_antes on public.escala_setores;
create trigger a_antes before insert or update on public.escala_setores
  for each row execute function public.escala_setores_antes();

create or replace function public.escala_membros_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select s.empresa_id into v_empresa from public.escala_setores s where s.id = new.setor_id;
  if v_empresa is null then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  new.empresa_id := v_empresa;
  if not exists (select 1 from public.funcionarios f where f.id = new.funcionario_id and f.empresa_id = v_empresa) then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.escala_membros_antes() is '[interno] Gatilho: empresa do membro = do setor; funcionário da mesma empresa.';
drop trigger if exists a_antes on public.escala_membros;
create trigger a_antes before insert or update on public.escala_membros
  for each row execute function public.escala_membros_antes();

create or replace function public.escala_ajustes_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m record;
begin
  select x.empresa_id, x.funcionario_id into m from public.escala_membros x where x.id = new.membro_id;
  if m.empresa_id is null then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  new.empresa_id := m.empresa_id;
  new.funcionario_id := m.funcionario_id;
  return new;
end $$;
comment on function public.escala_ajustes_antes() is '[interno] Gatilho: empresa/funcionário do ajuste = do membro.';
drop trigger if exists a_antes on public.escala_ajustes;
create trigger a_antes before insert or update on public.escala_ajustes
  for each row execute function public.escala_ajustes_antes();

drop trigger if exists tocar_atualizado_em on public.escala_config;
create trigger tocar_atualizado_em before update on public.escala_config
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_setores;
create trigger tocar_atualizado_em before update on public.escala_setores
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_membros;
create trigger tocar_atualizado_em before update on public.escala_membros
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_ajustes;
create trigger tocar_atualizado_em before update on public.escala_ajustes
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ regra do rodízio (§S.2)
-- Membros com a posição k (0-based) e o tamanho n do caminho; p_setor restringe a um setor (usado pelo ponto).
create or replace function public.escala_membros_rodizio(p_empresa uuid, p_setor uuid default null)
returns table (id uuid, funcionario_id uuid, setor_id uuid, caminho smallint, posicao smallint, k int, n int,
               folgas_base smallint[], chegada_padrao time, fase_setor int, data_admissao date, data_desligamento date)
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
  select m.id, m.funcionario_id, m.setor_id, m.caminho, m.posicao,
         (row_number() over (partition by m.setor_id, m.caminho order by m.posicao, m.id) - 1)::int,
         (count(*) over (partition by m.setor_id, m.caminho))::int,
         m.folgas_base, m.chegada_padrao, s.fase, f.data_admissao, f.data_desligamento
    from public.escala_membros m
    join public.escala_setores s on s.id = m.setor_id
    join public.funcionarios f on f.id = m.funcionario_id
   where m.empresa_id = p_empresa and (p_setor is null or m.setor_id = p_setor)
$$;
comment on function public.escala_membros_rodizio(uuid, uuid) is '[interno] Membros com posição (k) e tamanho (n) do caminho.';

-- Número da semana (w) do dia em relação à âncora.
create or replace function public.escala_semana_num(p_data date, p_ancora date)
returns int language sql immutable set search_path = public, extensions, pg_temp as $$
  select ((p_data - (extract(isodow from p_data)::int - 1)) - p_ancora) / 7
$$;
comment on function public.escala_semana_num(date, date) is '[interno] Semana do dia contada a partir da âncora (semana 0).';

-- Escala calculada (regra + ajustes) para o período; p_funcionario restringe a um funcionário.
create or replace function public.escala_calcular(p_empresa uuid, p_inicio date, p_fim date, p_funcionario uuid default null)
returns table (funcionario_id uuid, membro_id uuid, setor_id uuid, data date, status text, status_auto text, origem text,
               chegada time, ajustado boolean, ajuste_status text, ajuste_chegada time, motivo text)
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
  with cfg as (select c.ancora, c.fase from public.escala_config c where c.empresa_id = p_empresa),
  mem as materialized (
    select r.* from public.escala_membros_rodizio(p_empresa,
             case when p_funcionario is not null
                  then (select x.setor_id from public.escala_membros x where x.funcionario_id = p_funcionario) end) r
     where p_funcionario is null
        or exists (select 1 from public.escala_membros x where x.funcionario_id = p_funcionario)
  ),
  base as (
    select b.*, g::date as d, cfg.ancora, cfg.fase as fase_emp
      from mem b cross join cfg cross join generate_series(p_inicio, p_fim, interval '1 day') g
     where p_funcionario is null or b.funcionario_id = p_funcionario
  ),
  calc as (
    select b.*,
           case when b.d < b.ancora or not public.ponto_no_vinculo(b.data_admissao, b.data_desligamento, b.d) then 'fora'
                when (extract(isodow from b.d)::int - 1)::smallint = any (alvo.folgas_base) then 'folga'
                else 'trabalha' end as st_auto
      from base b
      left join lateral (
        select a.folgas_base from mem a
         where (b.caminho is null and a.id = b.id)
            or (b.caminho is not null and a.setor_id = b.setor_id and a.caminho = b.caminho
                and a.k = (((b.k + public.escala_semana_num(b.d, b.ancora) + b.fase_emp + b.fase_setor) % b.n) + b.n) % b.n)
        limit 1
      ) alvo on true
  )
  select c.funcionario_id, c.id, c.setor_id, c.d,
         case when c.st_auto = 'fora' then 'fora' else coalesce(aj.status, c.st_auto) end,
         c.st_auto,
         case when c.st_auto <> 'fora' and aj.status is not null then 'ajuste' else 'auto' end,
         case when c.st_auto <> 'fora' and coalesce(aj.status, c.st_auto) = 'trabalha' then coalesce(aj.chegada, c.chegada_padrao) end,
         c.st_auto <> 'fora' and aj.id is not null,
         aj.status, aj.chegada, aj.motivo
    from calc c
    left join public.escala_ajustes aj on aj.funcionario_id = c.funcionario_id and aj.data = c.d
$$;
comment on function public.escala_calcular(uuid, date, date, uuid) is '[interno] Escala calculada (rodízio + ajustes) por funcionário × dia (§S.2).';

-- Usada por ponto_calcular_dia (…0200): status da escala no dia (null = fora da escala) e chegada.
create or replace function public.escala_status_ponto(p_funcionario uuid, p_data date, out status text, out chegada time)
language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; c record;
begin
  select m.empresa_id into v_empresa from public.escala_membros m where m.funcionario_id = p_funcionario;
  if v_empresa is null then return; end if;
  select * into c from public.escala_calcular(v_empresa, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then return; end if;
  status := c.status;
  chegada := c.chegada;
end $$;
comment on function public.escala_status_ponto(uuid, date) is '[interno] Status da escala no dia para a apuração (adendo escala §S.5).';

-- ================================================================ auxiliares
create or replace function public.escala_hoje(p_empresa uuid)
returns date language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select public.dia_de_trabalho(public.agora(), p_empresa)
$$;
comment on function public.escala_hoje(uuid) is '[interno] Dia de trabalho atual da empresa.';

-- Reapura os funcionários no período, limitado a [hoje − 61, hoje] (adendo §S.5).
create or replace function public.escala_reapurar(p_empresa uuid, p_funcionarios uuid[], p_inicio date default null,
                                                  p_fim date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date; v_ini date; v_fim date; v_f uuid;
begin
  if p_funcionarios is null then return; end if;
  v_hoje := public.escala_hoje(p_empresa);
  v_ini := greatest(coalesce(p_inicio, v_hoje - 61), v_hoje - 61);
  v_fim := least(coalesce(p_fim, v_hoje), v_hoje);
  if v_ini > v_fim then return; end if;
  for v_f in select distinct x from unnest(p_funcionarios) x where x is not null order by 1 loop
    perform public.ponto_apurar(v_f, v_ini, v_fim);
  end loop;
end $$;
comment on function public.escala_reapurar(uuid, uuid[], date, date) is '[interno] Reapura funcionários afetados pela escala (máx. 62 dias).';

create or replace function public.escala_funcionarios_dos_setores(p_setores uuid[])
returns uuid[] language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(array_agg(m.funcionario_id), '{}') from public.escala_membros m where m.setor_id = any (p_setores)
$$;
comment on function public.escala_funcionarios_dos_setores(uuid[]) is '[interno] Funcionários dos setores.';

-- Configuração da empresa (cria com âncora = segunda da semana atual, se não existir).
create or replace function public.escala_garantir_config(p_empresa uuid)
returns public.escala_config language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.escala_config; v_hoje date;
begin
  select * into c from public.escala_config where empresa_id = p_empresa;
  if found then return c; end if;
  v_hoje := public.escala_hoje(p_empresa);
  insert into public.escala_config (empresa_id, ancora, fase)
  values (p_empresa, v_hoje - (extract(isodow from v_hoje)::int - 1), 0)
  on conflict (empresa_id) do nothing;
  select * into c from public.escala_config where empresa_id = p_empresa;
  return c;
end $$;
comment on function public.escala_garantir_config(uuid) is '[interno] Garante a configuração da escala (âncora padrão = segunda atual).';

create or replace function public.escala_validar_fase(p_fase int)
returns int language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_fase is null then return 0; end if;
  if p_fase < -1000 or p_fase > 1000 then raise exception 'Fase inválida' using errcode = '22023'; end if;
  return p_fase;
end $$;
comment on function public.escala_validar_fase(int) is '[interno] Valida a fase (−1000..1000).';

create or replace function public.escala_validar_folgas(p_folgas smallint[])
returns smallint[] language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare v smallint[];
begin
  if p_folgas is null then return '{}'; end if;
  if exists (select 1 from unnest(p_folgas) x where x is null or x < 0 or x > 6) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v from unnest(p_folgas) x;
  if coalesce(array_length(v, 1), 0) > 6 or coalesce(array_length(v, 1), 0) <> coalesce(array_length(p_folgas, 1), 0) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  return v;
end $$;
comment on function public.escala_validar_folgas(smallint[]) is '[interno] Folgas da semana base: 0..6 sem repetição, até 6 dias; ordena.';

create or replace function public.escala_status_param(p_status text)
returns text language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_status is null or p_status in ('auto', 'automatico') then return null; end if;
  if p_status not in ('trabalha', 'folga', 'ferias') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  return p_status;
end $$;
comment on function public.escala_status_param(text) is '[interno] Status do ajuste: trabalha/folga/ferias; null ou auto = automático.';

create or replace function public.escala_setor_para_operar(p_setor uuid)
returns public.escala_setores language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(s.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return s;
end $$;
comment on function public.escala_setor_para_operar(uuid) is '[interno] Setor existente e operável (G A M).';

create or replace function public.escala_membro_para_operar(p_funcionario uuid)
returns public.escala_membros language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; m public.escala_membros;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  select * into m from public.escala_membros where funcionario_id = p_funcionario;
  if not found then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  return m;
end $$;
comment on function public.escala_membro_para_operar(uuid) is '[interno] Membro da escala operável (G A M).';

-- Grava (upsert por funcionário) um membro, sem reapurar. Retorna o id do membro.
create or replace function public.escala_gravar_membro(p_setor uuid, p_funcionario uuid, p_folgas smallint[], p_chegada time,
                                                       p_caminho smallint, p_posicao smallint, p_ordem int,
                                                       p_modelo_posicao text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_emp_f uuid; v_folgas smallint[]; v_pos smallint; v_ordem int; v_id uuid; v_atual public.escala_membros;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  select f.empresa_id into v_emp_f from public.funcionarios f where f.id = p_funcionario;
  if v_emp_f is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if v_emp_f <> s.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  v_folgas := public.escala_validar_folgas(p_folgas);
  if p_caminho is not null and (p_caminho < 1 or p_caminho > 20) then
    raise exception 'Caminho inválido' using errcode = '22023';
  end if;
  select * into v_atual from public.escala_membros where funcionario_id = p_funcionario;
  v_pos := null;
  if p_caminho is not null then
    v_pos := p_posicao;
    if v_pos is null then
      select coalesce(max(m.posicao), 0) + 1 into v_pos from public.escala_membros m
       where m.setor_id = p_setor and m.caminho = p_caminho and m.funcionario_id <> p_funcionario;
    end if;
    if v_pos < 1 or v_pos > 99 then raise exception 'Posição inválida' using errcode = '22023'; end if;
    if exists (select 1 from public.escala_membros m
                where m.setor_id = p_setor and m.caminho = p_caminho and m.posicao = v_pos and m.funcionario_id <> p_funcionario) then
      raise exception 'Posição já ocupada no caminho' using errcode = '23505';
    end if;
  end if;
  v_ordem := p_ordem;
  if v_ordem is null then
    if v_atual.id is not null and v_atual.setor_id = p_setor then
      v_ordem := v_atual.ordem;
    else
      select coalesce(max(m.ordem), 0) + 1 into v_ordem from public.escala_membros m where m.setor_id = p_setor;
    end if;
  end if;
  insert into public.escala_membros as m (empresa_id, setor_id, funcionario_id, folgas_base, chegada_padrao, caminho, posicao,
                                          ordem, modelo_posicao)
  values (s.empresa_id, p_setor, p_funcionario, v_folgas, p_chegada, p_caminho, v_pos, v_ordem, p_modelo_posicao)
  on conflict (funcionario_id) do update set
    setor_id = excluded.setor_id, folgas_base = excluded.folgas_base, chegada_padrao = excluded.chegada_padrao,
    caminho = excluded.caminho, posicao = excluded.posicao, ordem = excluded.ordem,
    modelo_posicao = coalesce(excluded.modelo_posicao, m.modelo_posicao)
  returning m.id into v_id;
  return v_id;
end $$;
comment on function public.escala_gravar_membro(uuid, uuid, smallint[], time, smallint, smallint, int, text) is
  '[interno] Grava membro da escala (validações §S.7 nº 4), sem reapurar.';

-- Abono 'ferias' do ajuste (§S.4).
create or replace function public.escala_sincronizar_abono(p_ajuste uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare aj public.escala_ajustes; v_motivo text;
begin
  select * into aj from public.escala_ajustes where id = p_ajuste;
  if not found then return; end if;
  if aj.status is distinct from 'ferias' then
    delete from public.ponto_abonos where escala_ajuste_id = aj.id;
    return;
  end if;
  v_motivo := left(case when aj.motivo is null then 'Férias (escala)' else 'Férias (escala): ' || aj.motivo end, 500);
  if exists (select 1 from public.ponto_abonos a where a.escala_ajuste_id = aj.id) then
    update public.ponto_abonos set motivo = v_motivo where escala_ajuste_id = aj.id and motivo is distinct from v_motivo;
    return;
  end if;
  if exists (select 1 from public.ponto_abonos a where a.funcionario_id = aj.funcionario_id and a.data = aj.data) then
    raise exception 'Já existe abono para o funcionário em %', to_char(aj.data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por, escala_ajuste_id)
  values (aj.empresa_id, aj.funcionario_id, aj.data, 'ferias', v_motivo, public.meu_perfil_id(), aj.id);
end $$;
comment on function public.escala_sincronizar_abono(uuid) is '[interno] Mantém o abono ''ferias'' de um ajuste de férias da escala.';

-- Grava o estado de um dia (status null = automático; chegada null = padrão; os dois null apagam o ajuste). Sem reapurar.
create or replace function public.escala_gravar_dia(p_membro uuid, p_data date, p_status text, p_chegada time, p_motivo text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_id uuid;
begin
  select * into m from public.escala_membros where id = p_membro;
  if p_status is null and p_chegada is null then
    delete from public.escala_ajustes where funcionario_id = m.funcionario_id and data = p_data;
    return;
  end if;
  insert into public.escala_ajustes as a (empresa_id, membro_id, funcionario_id, data, status, chegada, motivo,
                                          criado_por, criado_por_nome)
  values (m.empresa_id, m.id, m.funcionario_id, p_data, p_status, p_chegada, nullif(btrim(coalesce(p_motivo, '')), ''),
          public.meu_perfil_id(), public.ponto_nome_autor())
  on conflict (funcionario_id, data) do update set
    membro_id = excluded.membro_id, status = excluded.status, chegada = excluded.chegada, motivo = excluded.motivo,
    criado_por = excluded.criado_por, criado_por_nome = excluded.criado_por_nome
  returning a.id into v_id;
  perform public.escala_sincronizar_abono(v_id);
end $$;
comment on function public.escala_gravar_dia(uuid, date, text, time, text) is '[interno] Grava/apaga o ajuste de um dia e sincroniza o abono.';

create or replace function public.escala_validar_data(p_empresa uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date;
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.escala_hoje(p_empresa);
  if p_data < v_hoje - 62 or p_data > v_hoje + 366 then
    raise exception 'Data fora do limite' using errcode = '22023';
  end if;
end $$;
comment on function public.escala_validar_data(uuid, date) is '[interno] Data de ajuste em [hoje − 62, hoje + 366].';

create or replace function public.escala_hora(p_hora time)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select to_char(p_hora, 'HH24:MI')
$$;
comment on function public.escala_hora(time) is '[interno] Hora como HH:MM.';

-- Objeto-dia (§S.8) de um funcionário; p_motivo = incluir o motivo (G A M).
create or replace function public.escala_dia_json(p_empresa uuid, p_funcionario uuid, p_data date, p_motivo boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object('funcionario_id', c.funcionario_id, 'data', c.data, 'status', c.status, 'origem', c.origem,
                            'chegada', public.escala_hora(c.chegada), 'ajustado', c.ajustado,
                            'motivo', case when p_motivo then c.motivo end,
                            'falta', public.ponto_falta_do_dia(c.funcionario_id, c.data))
    from public.escala_calcular(p_empresa, p_data, p_data, p_funcionario) c
$$;
comment on function public.escala_dia_json(uuid, uuid, date, boolean) is '[interno] Objeto-dia da escala (adendo §S.8).';

-- ================================================================ RPCs de configuração
create or replace function public.escala_configurar(p_ancora date, p_fase int default 0, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_antiga date; v_fase int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if extract(isodow from p_ancora) <> 1 then
    raise exception 'A data-âncora deve ser uma segunda-feira' using errcode = '22023';
  end if;
  v_fase := public.escala_validar_fase(p_fase);
  select c.ancora into v_antiga from public.escala_config c where c.empresa_id = v_empresa;
  insert into public.escala_config as c (empresa_id, ancora, fase) values (v_empresa, p_ancora, v_fase)
  on conflict (empresa_id) do update set ancora = excluded.ancora, fase = excluded.fase;
  delete from public.escala_ajustes where empresa_id = v_empresa and data < p_ancora;
  perform public.escala_reapurar(v_empresa,
    (select array_agg(m.funcionario_id) from public.escala_membros m where m.empresa_id = v_empresa),
    least(coalesce(v_antiga, p_ancora), p_ancora));
  return jsonb_build_object('empresa_id', v_empresa, 'ancora', p_ancora, 'fase', v_fase);
end $$;
comment on function public.escala_configurar(date, int, uuid) is '[api] Define a data-âncora (segunda) e a fase da escala; reapura.';

create or replace function public.escala_salvar_setor(p_nome text, p_ordem int default null, p_fase int default 0,
                                                      p_setor uuid default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; s public.escala_setores; v_id uuid; v_nome text; v_fase int; v_cfg public.escala_config;
begin
  if p_setor is not null then
    s := public.escala_setor_para_operar(p_setor);
    v_empresa := s.empresa_id;
    if p_empresa is not null and p_empresa <> v_empresa then raise exception 'Sem permissão' using errcode = '42501'; end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  v_fase := public.escala_validar_fase(p_fase);
  if exists (select 1 from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(v_nome)
                and x.id is distinct from p_setor) then
    raise exception 'Setor já existe' using errcode = '23505';
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);
  if p_setor is null then
    insert into public.escala_setores (empresa_id, nome, ordem, fase)
    values (v_empresa, v_nome,
            coalesce(p_ordem, (select coalesce(max(x.ordem), 0) + 1 from public.escala_setores x where x.empresa_id = v_empresa)),
            v_fase)
    returning id into v_id;
  else
    update public.escala_setores set nome = v_nome, ordem = coalesce(p_ordem, ordem), fase = v_fase where id = p_setor;
    v_id := p_setor;
    if s.fase <> v_fase then
      perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(array[p_setor]), v_cfg.ancora);
    end if;
  end if;
  return v_id;
end $$;
comment on function public.escala_salvar_setor(text, int, int, uuid, uuid) is '[api] Cria ou altera um setor da escala.';

create or replace function public.escala_excluir_setor(p_setor uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_func uuid[];
begin
  s := public.escala_setor_para_operar(p_setor);
  v_func := public.escala_funcionarios_dos_setores(array[p_setor]);
  delete from public.escala_setores where id = p_setor;
  perform public.escala_reapurar(s.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
end $$;
comment on function public.escala_excluir_setor(uuid) is '[api] Exclui o setor (membros e ajustes) e reapura.';

create or replace function public.escala_salvar_membro(p_setor uuid, p_funcionario uuid, p_folgas_base smallint[] default '{}',
                                                       p_chegada_padrao time default null, p_caminho smallint default null,
                                                       p_posicao smallint default null, p_ordem int default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_antigo uuid; v_id uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  select m.setor_id into v_antigo from public.escala_membros m where m.funcionario_id = p_funcionario;
  v_id := public.escala_gravar_membro(p_setor, p_funcionario, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, p_ordem);
  perform public.escala_reapurar(s.empresa_id,
    public.escala_funcionarios_dos_setores(array[p_setor, v_antigo]) || p_funcionario,
    (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_id;
end $$;
comment on function public.escala_salvar_membro(uuid, uuid, smallint[], time, smallint, smallint, int) is
  '[api] Põe/atualiza um funcionário num setor da escala (upsert por funcionário) e reapura.';

create or replace function public.escala_definir_membros(p_setor uuid, p_membros jsonb)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_afetados uuid[]; v_lista uuid[]; x jsonb; i int := 0;
  v_func uuid; v_folgas smallint[]; v_cheg time; v_cam smallint; v_pos smallint;
begin
  s := public.escala_setor_para_operar(p_setor);
  if p_membros is null or jsonb_typeof(p_membros) <> 'array' then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg((e ->> 'funcionario_id')::uuid), '{}') into v_lista from jsonb_array_elements(p_membros) e;
  exception when others then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end;
  if exists (select 1 from unnest(v_lista) u where u is null) then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  if (select count(distinct u) from unnest(v_lista) u) <> coalesce(array_length(v_lista, 1), 0) then
    raise exception 'Funcionário repetido na lista' using errcode = '22023';
  end if;
  v_afetados := public.escala_funcionarios_dos_setores(array[p_setor])
             || public.escala_funcionarios_dos_setores(
                  (select coalesce(array_agg(distinct m.setor_id), '{}') from public.escala_membros m where m.funcionario_id = any (v_lista)))
             || v_lista;
  delete from public.escala_membros where setor_id = p_setor and not (funcionario_id = any (v_lista));
  update public.escala_membros set caminho = null, posicao = null where setor_id = p_setor;
  for x in select * from jsonb_array_elements(p_membros) loop
    i := i + 1;
    begin
      v_func := (x ->> 'funcionario_id')::uuid;
      v_folgas := case when jsonb_typeof(x -> 'folgas_base') = 'array'
                       then array(select jsonb_array_elements_text(x -> 'folgas_base')::smallint) else '{}'::smallint[] end;
      v_cheg := nullif(x ->> 'chegada_padrao', '')::time;
      v_cam := (x ->> 'caminho')::smallint;
      v_pos := (x ->> 'posicao')::smallint;
    exception when others then
      raise exception 'Lista de membros inválida' using errcode = '22023';
    end;
    perform public.escala_gravar_membro(p_setor, v_func, v_folgas, v_cheg, v_cam, v_pos, i);
  end loop;
  perform public.escala_reapurar(s.empresa_id, v_afetados, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return i;
end $$;
comment on function public.escala_definir_membros(uuid, jsonb) is '[api] Substitui a lista de membros do setor (ordem e caminhos) e reapura.';

create or replace function public.escala_remover_membro(p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_func uuid[];
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_func := public.escala_funcionarios_dos_setores(array[m.setor_id]);
  delete from public.escala_membros where id = m.id;
  perform public.escala_reapurar(m.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = m.empresa_id));
end $$;
comment on function public.escala_remover_membro(uuid) is '[api] Tira o funcionário da escala (apaga seus ajustes) e reapura.';

create or replace function public.escala_adicionar_funcionario(p_setor uuid, p_nome text, p_cargo text default null,
                                                               p_folgas_base smallint[] default '{}', p_chegada_padrao time default null,
                                                               p_caminho smallint default null, p_posicao smallint default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_nome text; v_func uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao)
  values (s.empresa_id, v_nome, nullif(btrim(coalesce(p_cargo, '')), ''), 0)
  returning id into v_func;
  perform public.escala_gravar_membro(p_setor, v_func, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, null);
  perform public.escala_reapurar(s.empresa_id, public.escala_funcionarios_dos_setores(array[p_setor]),
                                 (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_func;
end $$;
comment on function public.escala_adicionar_funcionario(uuid, text, text, smallint[], time, smallint, smallint) is
  '[api] Cadastra um funcionário e o põe num setor da escala; retorna o id do funcionário.';

-- Modelo do cliente (docs/referencias/escala-macaw-v3.html), §S.7.8.
create or replace function public.escala_aplicar_modelo_macaw(p_empresa uuid default null, p_ancora date default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_cfg public.escala_config; r record; v_setor uuid; v_func uuid; v_membro uuid;
  v_setores int := 0; v_membros int := 0; v_criados int := 0; v_pos smallint; v_chave text; v_setores_ids uuid[] := '{}';
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is not null then
    perform public.escala_configurar(p_ancora, coalesce((select c.fase from public.escala_config c where c.empresa_id = v_empresa), 0),
                                     v_empresa);
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);

  for r in
    select * from (values
      ('Salão', 1, 1, 'Garçom 1', 'Garçom', '{2,3}', 1, 1), ('Salão', 1, 2, 'Garçom 2', 'Garçom', '{2,3}', 1, 2),
      ('Salão', 1, 3, 'Garçom 3', 'Garçom', '{2,3}', 1, 3), ('Salão', 1, 4, 'Cumim 2', 'Cumim', '{2,6}', 1, 4),
      ('Salão', 1, 5, 'Garçom 4', 'Garçom', '{0,1}', 2, 1), ('Salão', 1, 6, 'Garçom 5', 'Garçom', '{0,1}', 2, 2),
      ('Salão', 1, 7, 'Garçom 6', 'Garçom', '{0,1}', 2, 3), ('Salão', 1, 8, 'Cumim 1', 'Cumim', '{1,6}', 2, 4),
      ('Maître', 2, 1, 'Maître 1', 'Maître', '{0,1}', 1, 2), ('Maître', 2, 2, 'Maître 2', 'Maître', '{1,3}', 1, 1),
      ('Maître', 2, 3, 'Maître 3', 'Maître', '{2,3}', 1, 4), ('Maître', 2, 4, 'Gerente', 'Gerente', '{2}', null, null),
      ('Maître', 2, 5, 'Recepção', 'Recepção', '{0,6}', 1, 3),
      ('Areia', 3, 1, 'Areia 1', 'Areia', '{0,6}', 1, 2), ('Areia', 3, 2, 'Areia 2', 'Areia', '{0,1}', 1, 1),
      ('Areia', 3, 3, 'Areia 3', 'Areia', '{2,3}', 1, 3), ('Areia', 3, 4, 'Areia 4', 'Areia', '{2,3}', 1, 4),
      ('Areia', 3, 5, 'Areia 5', 'Areia', '{1,4}', 1, 5),
      ('Bar', 4, 1, 'Bar 1', 'Bar', '{0,6}', 1, 1), ('Bar', 4, 2, 'Bar 2', 'Bar', '{0,1}', 1, 4),
      ('Bar', 4, 3, 'Bar 3', 'Bar', '{2,3}', 1, 3), ('Bar', 4, 4, 'Bar 4', 'Bar', '{2,3}', 1, 2),
      ('ASG', 5, 1, 'ASG 1', 'ASG', '{0,6}', 1, 1), ('ASG', 5, 2, 'ASG 2', 'ASG', '{1,2}', 1, 2),
      ('ASG', 5, 3, 'ASG 3', 'ASG', '{3,4}', 1, 3),
      ('Cozinha', 6, 1, 'Chef', 'Chef', '{3}', null, null), ('Cozinha', 6, 2, 'Cozinha 1', 'Cozinha', '{0,1}', 1, 3),
      ('Cozinha', 6, 3, 'Cozinha 2', 'Cozinha', '{0,1}', 1, 2), ('Cozinha', 6, 4, 'Cozinha 3', 'Cozinha', '{0,6}', 1, 1),
      ('Cozinha', 6, 5, 'Cozinha 4', 'Cozinha', '{1,2}', 2, 1), ('Cozinha', 6, 6, 'Cozinha 5', 'Cozinha', '{2,3}', 2, 2),
      ('Cozinha', 6, 7, 'Cozinha 6', 'Cozinha', '{3,6}', 2, 3), ('Cozinha', 6, 8, 'Cozinha 7', 'Cozinha', '{2,4}', 2, 4)
    ) as t(setor, ordem_setor, ordem, nome, cargo, folgas, caminho, posicao)
    order by ordem_setor, ordem
  loop
    select x.id into v_setor from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(r.setor);
    if v_setor is null then
      insert into public.escala_setores (empresa_id, nome, ordem) values (v_empresa, r.setor, r.ordem_setor) returning id into v_setor;
      v_setores := v_setores + 1;
    end if;
    if not (v_setor = any (v_setores_ids)) then v_setores_ids := v_setores_ids || v_setor; end if;
    v_chave := r.setor || '|' || r.nome;
    continue when exists (select 1 from public.escala_membros m where m.empresa_id = v_empresa and m.modelo_posicao = v_chave);
    -- funcionário de mesmo nome: já na escala → só marca a posição do modelo; fora da escala → entra nela
    select f.id, m.id into v_func, v_membro
      from public.funcionarios f left join public.escala_membros m on m.funcionario_id = f.id
     where f.empresa_id = v_empresa and lower(btrim(f.nome)) = lower(r.nome)
     order by (m.id is null) desc, f.criado_em, f.id
     limit 1;
    if v_membro is not null then
      update public.escala_membros set modelo_posicao = v_chave where id = v_membro and modelo_posicao is null;
      continue;
    end if;
    if v_func is null then
      insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao) values (v_empresa, r.nome, r.cargo, 0)
      returning id into v_func;
      v_criados := v_criados + 1;
    end if;
    v_pos := r.posicao;
    if r.caminho is not null and exists (select 1 from public.escala_membros m
                                          where m.setor_id = v_setor and m.caminho = r.caminho and m.posicao = v_pos) then
      v_pos := null;    -- posição ocupada → próxima livre do caminho
    end if;
    perform public.escala_gravar_membro(v_setor, v_func, r.folgas::smallint[], null, r.caminho::smallint, v_pos, r.ordem, v_chave);
    v_membros := v_membros + 1;
  end loop;

  perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(v_setores_ids), v_cfg.ancora);
  return jsonb_build_object('ancora', (select c.ancora from public.escala_config c where c.empresa_id = v_empresa),
                            'setores', v_setores, 'membros', v_membros, 'funcionarios_criados', v_criados);
end $$;
comment on function public.escala_aplicar_modelo_macaw(uuid, date) is
  '[api] Monta setores, caminhos e posições do modelo Macaw (cria funcionários provisórios); idempotente.';

-- (adendo extras v3, §S.11) dia com falta registrada não aceita ajuste/troca da escala
create or replace function public.escala_checar_falta(p_funcionario uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_funcionario is not null and p_data is not null and public.ponto_falta_do_dia(p_funcionario, p_data) is not null then
    raise exception 'Dia com falta em %: remova a falta antes', to_char(p_data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
end $$;
comment on function public.escala_checar_falta(uuid, date) is '[interno] Recusa ajuste/troca da escala em dia com falta.';

-- ================================================================ RPCs de ajuste
create or replace function public.escala_ajustar(p_funcionario uuid, p_data date, p_status text default null,
                                                 p_chegada time default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  -- (v3, §S.11) status de falta = atalho para falta_registrar (o ajuste do dia não muda)
  if p_status in ('falta_justificada', 'falta_injustificada') then
    perform public.falta_registrar(p_funcionario, p_data, substr(p_status, 7), p_motivo);
    return public.escala_dia_json(m.empresa_id, p_funcionario, p_data, true);
  end if;
  v_status := public.escala_status_param(p_status);
  perform public.escala_validar_data(m.empresa_id, p_data);
  select * into c from public.escala_calcular(m.empresa_id, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
  perform public.escala_checar_falta(p_funcionario, p_data);
  perform public.escala_gravar_dia(m.id, p_data, v_status, p_chegada, p_motivo);
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_data, p_data);
  return public.escala_dia_json(m.empresa_id, p_funcionario, p_data, true);
end $$;
comment on function public.escala_ajustar(uuid, date, text, time, text) is '[api] Define o estado de um dia da escala (status/chegada) e reapura.';

create or replace function public.escala_ajustar_periodo(p_funcionario uuid, p_inicio date, p_fim date, p_status text,
                                                         p_motivo text default null)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record; v_n int := 0;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_status := public.escala_status_param(p_status);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  perform public.escala_validar_data(m.empresa_id, p_inicio);
  perform public.escala_validar_data(m.empresa_id, p_fim);
  for c in select * from public.escala_calcular(m.empresa_id, p_inicio, p_fim, p_funcionario) x order by x.data loop
    continue when c.status = 'fora';
    perform public.escala_checar_falta(p_funcionario, c.data);
  end loop;
  for c in select * from public.escala_calcular(m.empresa_id, p_inicio, p_fim, p_funcionario) x order by x.data loop
    continue when c.status = 'fora';
    perform public.escala_gravar_dia(m.id, c.data, v_status, c.ajuste_chegada, p_motivo);
    v_n := v_n + 1;
  end loop;
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_inicio, p_fim);
  return v_n;
end $$;
comment on function public.escala_ajustar_periodo(uuid, date, date, text, text) is
  '[api] Mesmo status em vários dias (ex.: férias), mantendo a chegada ajustada; reapura.';

create or replace function public.escala_trocar(p_funcionario_a uuid, p_data_a date, p_funcionario_b uuid default null,
                                                p_data_b date default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ma public.escala_membros; mb public.escala_membros; v_motivo text; v_datas date[]; v_d date;
  ca record; cb record; v_out jsonb := '[]';
begin
  ma := public.escala_membro_para_operar(p_funcionario_a);
  if (p_funcionario_b is null and p_data_b is null) or p_funcionario_b = p_funcionario_a and p_data_b is null then
    raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023';
  end if;
  if p_funcionario_b is not null and p_funcionario_b <> p_funcionario_a then
    mb := public.escala_membro_para_operar(p_funcionario_b);
    if mb.empresa_id <> ma.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  end if;
  v_motivo := coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Troca de folga');
  perform public.escala_validar_data(ma.empresa_id, p_data_a);
  if p_data_b is not null then perform public.escala_validar_data(ma.empresa_id, p_data_b); end if;

  if mb.id is null then
    -- A troca o próprio status entre os dois dias
    if p_data_b = p_data_a then raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023'; end if;
    select * into ca from public.escala_calcular(ma.empresa_id, p_data_a, p_data_a, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, p_data_b, p_data_b, p_funcionario_a) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_checar_falta(p_funcionario_a, least(p_data_a, p_data_b));
    perform public.escala_checar_falta(p_funcionario_a, greatest(p_data_a, p_data_b));
    perform public.escala_gravar_dia(ma.id, p_data_a, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(ma.id, p_data_b, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], least(p_data_a, p_data_b), least(p_data_a, p_data_b));
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], greatest(p_data_a, p_data_b), greatest(p_data_a, p_data_b));
    select jsonb_agg(public.escala_dia_json(ma.empresa_id, p_funcionario_a, d, true) order by d) into v_out
      from unnest(array[p_data_a, p_data_b]) d;
    return v_out;
  end if;

  -- A e B trocam o status em cada dia
  v_datas := array[p_data_a];
  if p_data_b is not null and p_data_b <> p_data_a then v_datas := v_datas || p_data_b; end if;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_checar_falta(p_funcionario_a, v_d);
    perform public.escala_checar_falta(p_funcionario_b, v_d);
  end loop;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    perform public.escala_gravar_dia(ma.id, v_d, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(mb.id, v_d, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a, p_funcionario_b], v_d, v_d);
  end loop;
  select jsonb_agg(public.escala_dia_json(ma.empresa_id, f, d, true) order by o, d) into v_out
    from unnest(array[p_funcionario_a, p_funcionario_b]) with ordinality as u(f, o)
    cross join unnest(v_datas) d;
  return v_out;
end $$;
comment on function public.escala_trocar(uuid, date, uuid, date, text) is
  '[api] Troca de folga: A↔B num dia (ou em dois dias) ou A entre dois dias; reapura.';

-- ================================================================ RPCs de leitura
create or replace function public.escala_mes(p_ano_mes text, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_ini date; v_fim date; v_cfg public.escala_config; v_motivo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_ano_mes is null or p_ano_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Mês inválido (use AAAA-MM)' using errcode = '22023';
  end if;
  v_ini := (p_ano_mes || '-01')::date;
  v_fim := (v_ini + interval '1 month')::date - 1;
  v_motivo := public.pode_operar(v_empresa) is true;
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;

  return (
    with calc as materialized (select * from public.escala_calcular(v_empresa, v_ini, v_fim)),
    dias as (select g::date as d from generate_series(v_ini, v_fim, interval '1 day') g),
    -- (v3, §S.11) faltas do mês (FJ/FI); tabela da …0290 (função plpgsql: resolvida na execução)
    fal as (select fl.funcionario_id, fl.data, fl.tipo from public.funcionario_faltas fl
             where fl.empresa_id = v_empresa and fl.data between v_ini and v_fim),
    mem as (
      select m.*, f.nome, f.cargo from public.escala_membros m join public.funcionarios f on f.id = m.funcionario_id
       where m.empresa_id = v_empresa
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'ano_mes', p_ano_mes, 'inicio', v_ini, 'fim', v_fim,
      'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'pode_editar', v_motivo, 'hoje', public.escala_hoje(v_empresa),
      'dias', (select jsonb_agg(jsonb_build_object('data', d, 'dia_semana', extract(isodow from d)::int - 1,
                                                   'semana', case when v_cfg.ancora is not null then public.escala_semana_num(d, v_cfg.ancora) end)
                                order by d) from dias),
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs) order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'membro_id', m.id, 'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                            'chegada_padrao', public.escala_hora(m.chegada_padrao), 'folgas_base', to_jsonb(m.folgas_base),
                            'caminho', m.caminho, 'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                            'trabalha', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'trabalha'),
                            'folgas', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'folga'),
                            'ferias', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'ferias'),
                            'faltas', (select count(*) from fal where fal.funcionario_id = m.funcionario_id),
                            'dias', coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'data', dd.d, 'status', coalesce(c.status, 'fora'), 'origem', coalesce(c.origem, 'auto'),
                                       'chegada', public.escala_hora(c.chegada), 'ajustado', coalesce(c.ajustado, false),
                                       'motivo', case when v_motivo then c.motivo end, 'falta', fal.tipo) order by dd.d)
                                from dias dd left join calc c on c.funcionario_id = m.funcionario_id and c.data = dd.d
                                left join fal on fal.funcionario_id = m.funcionario_id and fal.data = dd.d), '[]'))
                          order by m.ordem, m.nome collate "C", m.id)
                     from mem m where m.setor_id = s.id), '[]'),
                 'na_escala', (select jsonb_agg((select count(*) from calc c where c.setor_id = s.id and c.data = dd.d and c.status = 'trabalha')
                                                order by dd.d) from dias dd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala', (select jsonb_agg((select count(*) from calc c where c.data = dd.d and c.status = 'trabalha') order by dd.d)
                      from dias dd))
  );
end $$;
comment on function public.escala_mes(text, uuid) is '[api] Escala do mês (AAAA-MM): setores, membros e dias (leitura vê, sem motivos).';

create or replace function public.escala_semana(p_data date default null, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_cfg public.escala_config; v_data date; v_seg date; v_w int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.escala_hoje(v_empresa));
  v_seg := v_data - (extract(isodow from v_data)::int - 1);
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;
  v_w := case when v_cfg.ancora is not null then public.escala_semana_num(v_seg, v_cfg.ancora) end;

  return (
    with r as materialized (select * from public.escala_membros_rodizio(v_empresa)),
    mem as (
      select r.*, f.nome, f.cargo, m.ordem,
             coalesce(case when v_w is null or r.caminho is null then r.folgas_base
                           else (select a.folgas_base from r a
                                  where a.setor_id = r.setor_id and a.caminho = r.caminho
                                    and a.k = (((r.k + v_w + coalesce(v_cfg.fase, 0) + r.fase_setor) % r.n) + r.n) % r.n) end,
                      r.folgas_base) as folgas_semana
        from r join public.funcionarios f on f.id = r.funcionario_id join public.escala_membros m on m.id = r.id
    ),
    wd as (select generate_series(0, 6) as d)
    select jsonb_build_object(
      'empresa_id', v_empresa, 'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'semana_inicio', v_seg, 'semana', v_w,
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'total', (select count(*) from mem m where m.setor_id = s.id),
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs, 'nomes', cm.nomes)
                                                        order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs,
                                                      jsonb_agg(m.nome order by m.posicao, m.id) as nomes
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((select jsonb_agg(jsonb_build_object(
                                               'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                                               'chegada_padrao', public.escala_hora(m.chegada_padrao), 'caminho', m.caminho,
                                               'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                                               'folgas_base', to_jsonb(m.folgas_base), 'folgas_semana', to_jsonb(m.folgas_semana))
                                             order by m.ordem, m.nome collate "C", m.id)
                                        from mem m where m.setor_id = s.id), '[]'),
                 'na_escala_base', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_base)))
                                                     order by wd.d) from wd),
                 'na_escala_semana', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_semana)))
                                                       order by wd.d) from wd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala_base', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_base))) order by wd.d) from wd),
      'na_escala_semana', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_semana))) order by wd.d) from wd))
  );
end $$;
comment on function public.escala_semana(date, uuid) is '[api] Semana base e semana de p_data pela regra do rodízio (sem ajustes).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000280_escala.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000290_comissao_presenca.sql
-- =====================================================================================================
-- 20261006000290_comissao_presenca.sql — backend (adendo extras/ocorrências/reservas v3, §E.7; adendo escala §S.11)
-- Presença do dia na comissão (ponto → escala → fallback individual; falta, suspensão, férias, atestado, abono individual
-- e fora do vínculo nunca), faltas (justificada/injustificada) com anexo, recálculo de rascunhos (faltas, desligamento),
-- extras com pontuação pendente e importação de extras em lote. Aqui ficam comissao_calcular, comissao_fechar e
-- comissao_detalhe (vieram da …0220). Fechamento FECHADO nunca muda. Idempotente.
-- =====================================================================================================

-- ================================================================ colunas novas
alter table public.comissao_fechamentos add column if not exists extras_sem_pontuacao int not null default 0;
alter table public.comissao_itens add column if not exists pontos_pendente boolean not null default false;

-- ================================================================ faltas (§E.7.2)
create table if not exists public.funcionario_faltas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  tipo             text not null check (tipo in ('justificada', 'injustificada')),
  motivo           text,
  anexo_caminho    text unique,
  anexo_nome       text,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (funcionario_id, data),
  constraint funcionario_faltas_motivo check (tipo = 'injustificada' or btrim(coalesce(motivo, '')) <> '')
);
create index if not exists funcionario_faltas_empresa_idx on public.funcionario_faltas (empresa_id, data);
create index if not exists funcionario_faltas_criado_por_idx on public.funcionario_faltas (criado_por);
comment on table public.funcionario_faltas is
  '[api:leitura] Faltas do funcionário (justificada/injustificada) por dia, com anexo opcional. Só G A M; escrita por RPC.';

alter table public.funcionario_faltas enable row level security;
drop policy if exists funcionario_faltas_ler on public.funcionario_faltas;
create policy funcionario_faltas_ler on public.funcionario_faltas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop trigger if exists a_empresa on public.funcionario_faltas;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.funcionario_faltas
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists tocar_atualizado_em on public.funcionario_faltas;
create trigger tocar_atualizado_em before update on public.funcionario_faltas
  for each row execute function public.tocar_atualizado_em();

-- Substitui o esqueleto da …0200 (usado por ponto_calcular_dia, ponto_abonar, ocorrências e escala).
create or replace function public.ponto_falta_do_dia(p_funcionario uuid, p_data date) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select fl.tipo from public.funcionario_faltas fl where fl.funcionario_id = p_funcionario and fl.data = p_data
$$;
comment on function public.ponto_falta_do_dia(uuid, date) is '[interno] Tipo da falta do funcionário no dia (null = sem falta).';

-- ================================================================ recálculo de rascunhos
create or replace function public.comissao_recalcular_rascunhos(p_empresa uuid, p_inicio date, p_fim date,
                                                                p_funcionario uuid default null)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r record; v_n int := 0;
begin
  for r in
    select f.id from public.comissao_fechamentos f
     where f.empresa_id = p_empresa and f.status = 'rascunho'
       and (p_inicio is null or f.data_fim >= p_inicio) and (p_fim is null or f.data_inicio <= p_fim)
       and (p_funcionario is null or exists (select 1 from public.comissao_itens it
                                              where it.fechamento_id = f.id and it.funcionario_id = p_funcionario))
     order by f.id
  loop
    perform public.comissao_calcular(r.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
comment on function public.comissao_recalcular_rascunhos(uuid, date, date, uuid) is
  '[interno] Recalcula os rascunhos de comissão da empresa que cruzam o período (fechados nunca).';

-- Desligamento/admissão mudou → rascunhos em que o funcionário tem item são recalculados (§E.7.3).
create or replace function public.comissao_gatilho_funcionario_vinculo()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform public.comissao_recalcular_rascunhos(new.empresa_id, null, null, new.id);
  return null;
end $$;
comment on function public.comissao_gatilho_funcionario_vinculo() is '[interno] Mudança de admissão/desligamento → recalcula rascunhos.';
drop trigger if exists zz_comissao_vinculo on public.funcionarios;
create trigger zz_comissao_vinculo after update of data_admissao, data_desligamento on public.funcionarios
  for each row
  when (old.data_admissao is distinct from new.data_admissao or old.data_desligamento is distinct from new.data_desligamento)
  execute function public.comissao_gatilho_funcionario_vinculo();

-- ================================================================ RPCs de faltas
create or replace function public.falta_json(p_falta uuid)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object('id', fl.id, 'funcionario_id', fl.funcionario_id, 'funcionario_nome', f.nome, 'data', fl.data,
                            'tipo', fl.tipo, 'motivo', fl.motivo, 'anexo_caminho', fl.anexo_caminho, 'anexo_nome', fl.anexo_nome,
                            'criado_por_nome', fl.criado_por_nome, 'criado_em', fl.criado_em, 'atualizado_em', fl.atualizado_em)
    from public.funcionario_faltas fl join public.funcionarios f on f.id = fl.funcionario_id
   where fl.id = p_falta
$$;
comment on function public.falta_json(uuid) is '[interno] Objeto-falta (§E.7.2).';

create or replace function public.falta_validar_anexo(p_empresa uuid, p_funcionario uuid, p_caminho text, p_ignorar uuid)
returns text language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v text := nullif(btrim(coalesce(p_caminho, '')), ''); v_prefixo text; v_existe boolean := true;
begin
  if v is null then return null; end if;
  v_prefixo := p_empresa::text || '/faltas/' || p_funcionario::text || '/';
  if position(v_prefixo in v) <> 1 or v !~* ('^' || v_prefixo || '[^/]+\.(jpg|jpeg|png|webp|pdf)$') then
    raise exception 'Anexo inválido' using errcode = '22023';
  end if;
  if exists (select 1 from public.funcionario_faltas fl where fl.anexo_caminho = v and fl.id is distinct from p_ignorar) then
    raise exception 'Anexo já registrado' using errcode = '23505';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)'
      into v_existe using 'funcionarios-documentos', v;
  end if;
  if not v_existe then raise exception 'Anexo não encontrado no armazenamento' using errcode = 'P0002'; end if;
  return v;
end $$;
comment on function public.falta_validar_anexo(uuid, uuid, text, uuid) is '[interno] Caminho de anexo de falta válido e existente no Storage.';

create or replace function public.falta_registrar(p_funcionario uuid, p_data date, p_tipo text, p_motivo text default null,
                                                  p_anexo_caminho text default null, p_anexo_nome text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  f public.funcionarios; v_hoje date; v_motivo text; v_atual public.funcionario_faltas; v_anexo text; v_id uuid;
  v_esc record;
begin
  f := public.funcionario_para_operar(p_funcionario);
  if p_tipo is null or p_tipo not in ('justificada', 'injustificada') then
    raise exception 'Tipo de falta inválido' using errcode = '22023';
  end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_motivo := nullif(btrim(coalesce(p_motivo, '')), '');
  if p_tipo = 'justificada' and v_motivo is null then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  v_hoje := public.dia_de_trabalho(public.agora(), f.empresa_id);
  if p_data > v_hoje then raise exception 'Data no futuro' using errcode = '22023'; end if;
  if p_data < v_hoje - 366 then raise exception 'Data fora do limite' using errcode = '22023'; end if;
  if not public.ponto_no_vinculo(f.data_admissao, f.data_desligamento, p_data) then
    raise exception 'Dia fora do vínculo do funcionário' using errcode = '22023';
  end if;
  if public.comissao_periodo_fechado(f.empresa_id, p_data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
  if exists (select 1 from public.ponto_batidas b
              where b.funcionario_id = f.id and b.data_trabalho = p_data and not b.desconsiderada) then
    raise exception 'Funcionário com batidas em %: desconsidere as batidas antes de registrar a falta',
      to_char(p_data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  if exists (select 1 from public.ponto_abonos a where a.funcionario_id = f.id and a.data = p_data) then
    raise exception 'Já existe abono para o funcionário em %', to_char(p_data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  select * into v_esc from public.escala_status_ponto(f.id, p_data);
  if v_esc.status = 'folga' then
    raise exception 'Funcionário de folga na escala em %', to_char(p_data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  select * into v_atual from public.funcionario_faltas where funcionario_id = f.id and data = p_data;
  v_anexo := public.falta_validar_anexo(f.empresa_id, f.id, p_anexo_caminho, v_atual.id);

  insert into public.funcionario_faltas as fl (empresa_id, funcionario_id, data, tipo, motivo, anexo_caminho, anexo_nome,
                                               criado_por, criado_por_nome)
  values (f.empresa_id, f.id, p_data, p_tipo, v_motivo, v_anexo, case when v_anexo is not null then nullif(btrim(p_anexo_nome), '') end,
          public.meu_perfil_id(), public.ponto_nome_autor())
  on conflict (funcionario_id, data) do update set
    tipo = excluded.tipo, motivo = excluded.motivo,
    anexo_caminho = coalesce(excluded.anexo_caminho, fl.anexo_caminho),
    anexo_nome = case when excluded.anexo_caminho is not null then excluded.anexo_nome else fl.anexo_nome end,
    criado_por = excluded.criado_por, criado_por_nome = excluded.criado_por_nome
  returning fl.id into v_id;

  perform public.ponto_apurar(f.id, p_data, p_data);
  perform public.comissao_recalcular_rascunhos(f.empresa_id, p_data, p_data);
  return public.falta_json(v_id)
         || jsonb_build_object('anexo_anterior',
                               case when v_anexo is not null and v_atual.anexo_caminho is distinct from v_anexo
                                    then v_atual.anexo_caminho end);
end $$;
comment on function public.falta_registrar(uuid, date, text, text, text, text) is
  '[api] Registra/altera a falta do funcionário no dia (G A M); reapura o ponto e recalcula rascunhos de comissão.';

create or replace function public.falta_para_operar(p_funcionario uuid, p_data date)
returns public.funcionario_faltas language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios; fl public.funcionario_faltas;
begin
  f := public.funcionario_para_operar(p_funcionario);
  select * into fl from public.funcionario_faltas where funcionario_id = f.id and data = p_data;
  if not found then raise exception 'Falta não encontrada' using errcode = 'P0002'; end if;
  return fl;
end $$;
comment on function public.falta_para_operar(uuid, date) is '[interno] Falta existente e operável (G A M).';

create or replace function public.falta_remover(p_funcionario uuid, p_data date)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fl public.funcionario_faltas;
begin
  fl := public.falta_para_operar(p_funcionario, p_data);
  if public.comissao_periodo_fechado(fl.empresa_id, fl.data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
  delete from public.funcionario_faltas where id = fl.id;
  perform public.ponto_apurar(fl.funcionario_id, fl.data, fl.data);
  perform public.comissao_recalcular_rascunhos(fl.empresa_id, fl.data, fl.data);
  return fl.anexo_caminho;
end $$;
comment on function public.falta_remover(uuid, date) is
  '[api] Remove a falta do dia (G A M); devolve o caminho do anexo para remover do Storage.';

create or replace function public.falta_definir_anexo(p_funcionario uuid, p_data date, p_caminho text, p_nome_arquivo text default null)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fl public.funcionario_faltas; v text;
begin
  fl := public.falta_para_operar(p_funcionario, p_data);
  v := public.falta_validar_anexo(fl.empresa_id, fl.funcionario_id, p_caminho, fl.id);
  update public.funcionario_faltas
     set anexo_caminho = v, anexo_nome = case when v is not null then nullif(btrim(p_nome_arquivo), '') end
   where id = fl.id;
  return case when fl.anexo_caminho is distinct from v then fl.anexo_caminho end;
end $$;
comment on function public.falta_definir_anexo(uuid, date, text, text) is
  '[api] Troca/remove o anexo da falta (G A M); devolve o caminho antigo.';

create or replace function public.faltas_listar(p_inicio date, p_fim date, p_funcionario uuid default null, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return coalesce((
    select jsonb_agg(public.falta_json(fl.id) order by fl.data desc, f.nome collate "C", fl.id)
      from public.funcionario_faltas fl join public.funcionarios f on f.id = fl.funcionario_id
     where fl.empresa_id = v_empresa and fl.data between p_inicio and p_fim
       and (p_funcionario is null or fl.funcionario_id = p_funcionario)), '[]'::jsonb);
end $$;
comment on function public.faltas_listar(date, date, uuid, uuid) is '[api] Faltas do período (G A M).';

-- ================================================================ presença do dia (§E.7.1)
create or replace function public.comissao_presenca(p_empresa uuid, p_inicio date, p_fim date, p_funcionario uuid default null)
returns table (funcionario_id uuid, data date, presente boolean, fallback boolean, bloqueado boolean, motivo text, origem text)
language sql stable security definer rows 200 set search_path = public, extensions, pg_temp set jit = off as $$
  with dias as (select g::date as d from generate_series(p_inicio, p_fim, interval '1 day') g),
  fu as (
    select f.id, f.data_admissao, f.data_desligamento,
           (exists (select 1 from public.controlid_usuarios cu where cu.funcionario_id = f.id)
            or exists (select 1 from public.ponto_dias pd where pd.funcionario_id = f.id
                          and pd.data between p_inicio and p_fim and pd.batidas_validas > 0)) as no_ponto
      from public.funcionarios f
     where f.empresa_id = p_empresa and (p_funcionario is null or f.id = p_funcionario)
  ),
  ponto_emp as (
    select distinct pd.data from public.ponto_dias pd
     where pd.empresa_id = p_empresa and pd.data between p_inicio and p_fim and pd.batidas_validas > 0
  ),
  esc as materialized (
    select e.funcionario_id, e.data, e.status from public.escala_calcular(p_empresa, p_inicio, p_fim, p_funcionario) e
  ),
  m as (
    select fu.id, dd.d,
           case
             when not public.ponto_no_vinculo(fu.data_admissao, fu.data_desligamento, dd.d) then 'fora_vinculo'
             when fl.tipo is not null then 'falta_' || fl.tipo
             when ab.tipo in ('suspensao', 'ferias', 'atestado') then ab.tipo
             when esc.status = 'ferias' then 'ferias'
             when coalesce(pd.batidas_validas, 0) > 0 then null
             when ab.tipo is not null then 'abono'
             when pe.data is not null and fu.no_ponto then 'sem_batida'
             when esc.status = 'trabalha' then null
             when esc.status = 'folga' then 'folga_escala'
             else 'sem_registro'
           end as motivo,
           case when coalesce(pd.batidas_validas, 0) > 0 then 'ponto' when esc.status = 'trabalha' then 'escala' end as origem_bruta
      from fu
      cross join dias dd
      left join public.ponto_dias pd on pd.funcionario_id = fu.id and pd.data = dd.d
      left join public.funcionario_faltas fl on fl.funcionario_id = fu.id and fl.data = dd.d
      left join lateral (select a.tipo from public.ponto_abonos a
                          where a.funcionario_id = fu.id and a.data = dd.d order by a.criado_em limit 1) ab on true
      left join esc on esc.funcionario_id = fu.id and esc.data = dd.d
      left join ponto_emp pe on pe.data = dd.d
  )
  select m.id, m.d, m.motivo is null, coalesce(m.motivo = 'sem_registro', false),
         coalesce(m.motivo in ('fora_vinculo', 'falta_justificada', 'falta_injustificada', 'suspensao', 'ferias', 'atestado', 'abono'),
                  false),
         m.motivo, case when m.motivo is null then m.origem_bruta end
    from m
$$;
comment on function public.comissao_presenca(uuid, date, date, uuid) is
  '[interno] Presença de cada funcionário em cada dia para a comissão (adendo extras v3, §E.7.1).';

-- ================================================================ cálculo (§9 / E.3 / E.7)
create or replace function public.comissao_calcular(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  fc        record;
  v_zig     bigint;
  v_bruto   bigint;
  v_ret     bigint;
  v_base    bigint;
  v_dias    int;
  v_soma    numeric;
  v_resto   bigint;
  v_aj_abs  bigint;
  v_sinal   int;
  v_sp      int := 0;
  v_spart   int := 0;
  v_pend    int := 0;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento for update;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  v_dias := fc.data_fim - fc.data_inicio + 1;

  -- presença do período (uma vez por cálculo)
  if to_regclass('pg_temp._mdg_presenca') is not null then drop table pg_temp._mdg_presenca; end if;
  create temp table _mdg_presenca on commit drop as
    select * from public.comissao_presenca(fc.empresa_id, fc.data_inicio, fc.data_fim);
  create index on _mdg_presenca (funcionario_id, data);

  -- (adendo E.3.2 passo 8) extras com dia lançado no período entram; extra sem lançamento no período sai
  insert into public.comissao_itens (empresa_id, fechamento_id, tipo, extra_id, funcionario_nome, cargo, pontos)
  select fc.empresa_id, p_fechamento, 'extra', x.id, x.nome, x.funcao, x.pontos_padrao
    from public.extras x
   where x.empresa_id = fc.empresa_id
     and exists (select 1 from public.diarias d
                  where d.extra_id = x.id and d.data between fc.data_inicio and fc.data_fim)
     and not exists (select 1 from public.comissao_itens it where it.fechamento_id = p_fechamento and it.extra_id = x.id);
  delete from public.comissao_itens it
   where it.fechamento_id = p_fechamento and it.tipo = 'extra'
     and not exists (select 1 from public.diarias d
                      where d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim);
  -- extras: snapshot atualizado, pontos = média dos lançamentos com pontuação (2 casas), dias lançados, pendência (v3)
  update public.comissao_itens it
     set funcionario_nome = x.nome, cargo = x.funcao,
         pontos = coalesce(l.media, x.pontos_padrao), dias_presentes = l.qtd, dias_trabalhados = l.qtd,
         pontos_pendente = l.pend > 0
    from public.extras x,
         lateral (select round(avg(d.pontos) filter (where not d.pontos_pendente), 2) as media, count(*)::int as qtd,
                         count(*) filter (where d.pontos_pendente)::int as pend
                    from public.diarias d
                   where d.extra_id = x.id and d.data between fc.data_inicio and fc.data_fim) l
   where it.fechamento_id = p_fechamento and it.extra_id = x.id;
  select count(*) into v_pend from public.comissao_itens it
   where it.fechamento_id = p_fechamento and it.tipo = 'extra' and it.incluido and it.pontos_pendente;

  -- funcionários: dias presentes (v3, §E.7.1/§E.7.4) — diário: presente; período: presente ou fallback (sem registro)
  update public.comissao_itens it set dias_presentes = 0, dias_trabalhados = 0
   where it.fechamento_id = p_fechamento and it.tipo = 'funcionario';
  update public.comissao_itens it
     set dias_presentes = c.qtd, dias_trabalhados = c.qtd
    from (select p.funcionario_id,
                 count(*) filter (where p.presente or (fc.modo_rateio = 'periodo' and p.fallback))::int as qtd
            from _mdg_presenca p group by p.funcionario_id) c
   where c.funcionario_id = it.funcionario_id and it.fechamento_id = p_fechamento and it.tipo = 'funcionario';

  -- 1. serviço do período
  select coalesce(sum(i.valor_total), 0) into v_zig
    from public.zig_vendas_itens i
   where i.empresa_id = fc.empresa_id and i.tipo = 'Tip'
     and i.data_operacao between fc.data_inicio and fc.data_fim
     and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo);

  delete from public.comissao_rateio_itens_dia where fechamento_id = p_fechamento;
  delete from public.comissao_rateio_dias where fechamento_id = p_fechamento;

  if fc.modo_rateio = 'periodo' then
    -- ============================================== modo período (§9; presença v3 §E.7.4)
    v_bruto := greatest(0, v_zig + fc.servico_ajuste_centavos);
    v_ret := round(v_bruto::numeric * fc.percentual_retencao / 100);
    v_base := v_bruto - v_ret;
    update public.comissao_itens it
       set pontos_efetivos = case
             when not it.incluido then 0
             when it.tipo = 'extra' then
               round(coalesce((select sum(d.pontos) from public.diarias d
                                where d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim
                                  and not d.pontos_pendente), 0) / v_dias, 6)
             when it.funcionario_id is not null
                  and not exists (select 1 from _mdg_presenca p where p.funcionario_id = it.funcionario_id and not p.bloqueado) then 0
             when fc.proporcional_dias then round(it.pontos * it.dias_trabalhados / v_dias, 6)
             else it.pontos end
     where it.fechamento_id = p_fechamento;

    select coalesce(sum(it.pontos_efetivos), 0) into v_soma from public.comissao_itens it where it.fechamento_id = p_fechamento;
    if v_soma = 0 then
      update public.comissao_itens set valor_centavos = 0 where fechamento_id = p_fechamento;
    else
      -- 9. maior resto — aritmética EXATA: piso = div(base × pe, soma) e resto = mod(base × pe, soma).
      -- Desempate por nome com collate "C" (igual à prévia do front em web/src/lib/comissao.ts).
      with c as (
        select it.id, div(v_base * it.pontos_efetivos, v_soma) as piso
          from public.comissao_itens it where it.fechamento_id = p_fechamento
      )
      update public.comissao_itens it set valor_centavos = c.piso::bigint
        from c where it.id = c.id;
      select v_base - coalesce(sum(valor_centavos), 0) into v_resto
        from public.comissao_itens where fechamento_id = p_fechamento;
      with ordem as (
        select it.id
          from public.comissao_itens it
         where it.fechamento_id = p_fechamento and it.pontos_efetivos > 0
         order by mod(v_base * it.pontos_efetivos, v_soma) desc,
                  it.pontos_efetivos desc, it.funcionario_nome collate "C" asc, (it.tipo = 'extra') asc,
                  coalesce(it.funcionario_id, it.extra_id) asc nulls last, it.id
         limit v_resto
      )
      update public.comissao_itens it set valor_centavos = it.valor_centavos + 1
        from ordem where it.id = ordem.id;
    end if;
  else
    -- ============================================== modo diário (adendo E.3.2 + presença v3 §E.7.1)
    -- funcionário automático: pontos exibidos = vigentes no fim
    update public.comissao_itens it
       set pontos = coalesce(public.comissao_pontos_vigentes(it.funcionario_id, fc.data_fim), 0)
     where it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.funcionario_id is not null
       and not it.pontos_manual;

    -- 1–2. serviço do dia e parte do ajuste (maior resto exato; peso = serviço do dia ≥ 0, ou 1 se o total for 0)
    v_aj_abs := abs(fc.servico_ajuste_centavos);
    v_sinal := case when fc.servico_ajuste_centavos < 0 then -1 else 1 end;
    with g as (
      select d::date as data from generate_series(fc.data_inicio::timestamp, fc.data_fim::timestamp, interval '1 day') d
    ), s as (
      select g.data,
             coalesce((select sum(i.valor_total) from public.zig_vendas_itens i
                        where i.empresa_id = fc.empresa_id and i.tipo = 'Tip' and i.data_operacao = g.data
                          and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo)), 0)::bigint as servico
        from g
    ), w as (
      select s.data, s.servico,
             case when (select sum(greatest(s2.servico, 0)) from s s2) > 0 then greatest(s.servico, 0) else 1 end::numeric as peso
        from s
    ), p as (
      select w.data, w.servico,
             div(v_aj_abs * w.peso, t.tot) as piso, mod(v_aj_abs * w.peso, t.tot) as resto
        from w, (select sum(peso) as tot from w) t
    ), r as (
      select p.*, row_number() over (order by p.resto desc, p.data) as rn,
             v_aj_abs - sum(p.piso) over () as sobra
        from p
    )
    insert into public.comissao_rateio_dias (fechamento_id, empresa_id, data, servico_zig_centavos, ajuste_centavos)
    select p_fechamento, fc.empresa_id, r.data, r.servico,
           (v_sinal * (r.piso + case when r.rn <= r.sobra then 1 else 0 end))::bigint
      from r;

    -- 3. bruto, retenção e base do dia
    update public.comissao_rateio_dias rd
       set servico_bruto_centavos = greatest(0, rd.servico_zig_centavos + rd.ajuste_centavos)
     where rd.fechamento_id = p_fechamento;
    update public.comissao_rateio_dias rd
       set retencao_centavos = round(rd.servico_bruto_centavos::numeric * fc.percentual_retencao / 100)::bigint
     where rd.fechamento_id = p_fechamento;
    update public.comissao_rateio_dias rd
       set base_centavos = rd.servico_bruto_centavos - rd.retencao_centavos
     where rd.fechamento_id = p_fechamento;

    -- 4. presentes do dia (ponto ou escala), fallback individual (sem registro, só com base > 0) e extras lançados
    insert into public.comissao_rateio_itens_dia (item_id, fechamento_id, empresa_id, data, pontos, fallback)
    select it.id, p_fechamento, fc.empresa_id, pr.data, x.pontos, pr.fallback
      from public.comissao_itens it
      join _mdg_presenca pr on pr.funcionario_id = it.funcionario_id
      join public.comissao_rateio_dias rd on rd.fechamento_id = p_fechamento and rd.data = pr.data
      cross join lateral (select case when it.pontos_manual then it.pontos
                                      else coalesce(public.comissao_pontos_vigentes(it.funcionario_id, pr.data), 0) end as pontos) x
     where it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.incluido and x.pontos > 0
       and (pr.presente or (pr.fallback and rd.base_centavos > 0))
    union all
    select it.id, p_fechamento, fc.empresa_id, d.data, d.pontos, false
      from public.comissao_itens it
      join public.diarias d on d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim
     where it.fechamento_id = p_fechamento and it.tipo = 'extra' and it.incluido and d.pontos > 0 and not d.pontos_pendente;

    -- 5. último recurso: dia com base > 0 e ninguém → funcionários incluídos não bloqueados (e snapshots)
    insert into public.comissao_rateio_itens_dia (item_id, fechamento_id, empresa_id, data, pontos, fallback)
    select it.id, p_fechamento, fc.empresa_id, rd.data, x.pontos, true
      from public.comissao_rateio_dias rd
      join public.comissao_itens it on it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.incluido
      cross join lateral (select case when it.pontos_manual or it.funcionario_id is null then it.pontos
                                      else coalesce(public.comissao_pontos_vigentes(it.funcionario_id, rd.data), 0) end as pontos) x
     where rd.fechamento_id = p_fechamento and rd.base_centavos > 0 and x.pontos > 0
       and not exists (select 1 from public.comissao_rateio_itens_dia ri
                        where ri.fechamento_id = p_fechamento and ri.data = rd.data)
       and (it.funcionario_id is null
            or not exists (select 1 from _mdg_presenca pr
                            where pr.funcionario_id = it.funcionario_id and pr.data = rd.data and pr.bloqueado));

    update public.comissao_rateio_dias rd
       set soma_pontos = a.soma, participantes = a.qtd, sem_presenca = a.fb
      from (select ri.data, sum(ri.pontos) as soma, count(*)::int as qtd, bool_or(ri.fallback) as fb
              from public.comissao_rateio_itens_dia ri where ri.fechamento_id = p_fechamento group by ri.data) a
     where rd.fechamento_id = p_fechamento and rd.data = a.data;
    update public.comissao_rateio_dias rd
       set sem_participantes = rd.base_centavos > 0 and rd.participantes = 0
     where rd.fechamento_id = p_fechamento;

    -- 6. rateio do dia: maior resto exato (div/mod), desempate como no modo período
    update public.comissao_rateio_itens_dia ri
       set valor_centavos = div(rd.base_centavos * ri.pontos, rd.soma_pontos)::bigint
      from public.comissao_rateio_dias rd
     where ri.fechamento_id = p_fechamento and rd.fechamento_id = p_fechamento and rd.data = ri.data and rd.soma_pontos > 0;
    with s as (
      select rd.data, rd.base_centavos as base, rd.soma_pontos as soma,
             rd.base_centavos - coalesce((select sum(ri.valor_centavos) from public.comissao_rateio_itens_dia ri
                                           where ri.fechamento_id = p_fechamento and ri.data = rd.data), 0) as sobra
        from public.comissao_rateio_dias rd
       where rd.fechamento_id = p_fechamento and rd.soma_pontos > 0
    ), o as (
      select ri.item_id, ri.data, s.sobra,
             row_number() over (partition by ri.data
                                order by mod(s.base * ri.pontos, s.soma) desc, ri.pontos desc,
                                         it.funcionario_nome collate "C" asc, (it.tipo = 'extra') asc,
                                         coalesce(it.funcionario_id, it.extra_id) asc nulls last, it.id) as rn
        from public.comissao_rateio_itens_dia ri
        join s on s.data = ri.data
        join public.comissao_itens it on it.id = ri.item_id
       where ri.fechamento_id = p_fechamento
    )
    update public.comissao_rateio_itens_dia ri set valor_centavos = ri.valor_centavos + 1
      from o where ri.item_id = o.item_id and ri.data = o.data and o.rn <= o.sobra;

    -- 7. itens e totais
    update public.comissao_itens it set valor_centavos = 0, pontos_efetivos = 0 where it.fechamento_id = p_fechamento;
    update public.comissao_itens it
       set valor_centavos = a.valor, pontos_efetivos = a.pontos
      from (select ri.item_id, sum(ri.valor_centavos) as valor, sum(ri.pontos) as pontos
              from public.comissao_rateio_itens_dia ri where ri.fechamento_id = p_fechamento group by ri.item_id) a
     where it.id = a.item_id;
    select coalesce(sum(rd.servico_bruto_centavos), 0), coalesce(sum(rd.retencao_centavos), 0),
           coalesce(sum(rd.base_centavos), 0), coalesce(sum(rd.soma_pontos), 0),
           count(*) filter (where rd.sem_presenca), count(*) filter (where rd.sem_participantes)
      into v_bruto, v_ret, v_base, v_soma, v_sp, v_spart
      from public.comissao_rateio_dias rd where rd.fechamento_id = p_fechamento;
  end if;

  update public.comissao_fechamentos
     set servico_zig_centavos = v_zig,
         servico_bruto_centavos = v_bruto,
         retencao_centavos = v_ret,
         base_distribuivel_centavos = v_base,
         dias_periodo = v_dias,
         soma_pontos_efetivos = v_soma,
         valor_ponto_centavos = case when v_soma = 0 then null else round(v_base / v_soma, 6) end,
         dias_sem_presenca = v_sp,
         dias_sem_participantes = v_spart,
         extras_sem_pontuacao = v_pend,
         calculado_em = public.agora()
   where id = p_fechamento;
  drop table pg_temp._mdg_presenca;
end $$;
comment on function public.comissao_calcular(uuid) is
  '[interno] Recalcula um fechamento em rascunho (§9 modo período; adendo E.3 modo diário; presença v3 §E.7).';

create or replace function public.comissao_fechar(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if public.pode_administrar(fc.empresa_id) is not true then
    raise exception 'Somente o administrador fecha a comissão' using errcode = '42501';
  end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  perform public.comissao_calcular(p_fechamento);
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if fc.soma_pontos_efetivos <= 0 then
    raise exception 'Fechamento sem participantes' using errcode = '22023';
  end if;
  if fc.dias_sem_participantes > 0 then
    raise exception 'Há dias com serviço sem participantes para ratear' using errcode = '22023';
  end if;
  if fc.extras_sem_pontuacao > 0 then
    raise exception 'Há extras sem pontuação: preencha antes de fechar' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set status = 'fechado', fechado_por = auth.uid(), fechado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_fechar(uuid) is '[api] Recalcula e fecha (administrador). Depois é imutável.';

-- ================================================================ detalhe (adendo E.3.4 + v3 §E.7.7)
create or replace function public.comissao_detalhe(p_fechamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return (
    with pres as materialized (select * from public.comissao_presenca(fc.empresa_id, fc.data_inicio, fc.data_fim))
    select jsonb_build_object(
    'fechamento', to_jsonb(fc),
    'servico_dias', (
      select jsonb_agg(jsonb_build_object('data', g::date, 'servico_zig_centavos',
               coalesce((select sum(i.valor_total) from public.zig_vendas_itens i
                          where i.empresa_id = fc.empresa_id and i.tipo = 'Tip' and i.data_operacao = g::date
                            and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo)), 0)::bigint)
               order by g)
        from generate_series(fc.data_inicio::timestamp, fc.data_fim::timestamp, interval '1 day') g),
    'dias', coalesce((
      select jsonb_agg(jsonb_build_object(
               'data', rd.data, 'servico_zig_centavos', rd.servico_zig_centavos, 'ajuste_centavos', rd.ajuste_centavos,
               'servico_bruto_centavos', rd.servico_bruto_centavos, 'retencao_centavos', rd.retencao_centavos,
               'base_centavos', rd.base_centavos, 'soma_pontos', rd.soma_pontos, 'participantes', rd.participantes,
               'sem_presenca', rd.sem_presenca, 'sem_participantes', rd.sem_participantes,
               'rateio', coalesce((
                 select jsonb_agg(jsonb_build_object('item_id', ri.item_id, 'pontos', ri.pontos,
                                                     'valor_centavos', ri.valor_centavos, 'fallback', ri.fallback)
                                  order by it.funcionario_nome collate "C", (it.tipo = 'extra'),
                                           coalesce(it.funcionario_id, it.extra_id) nulls last, it.id)
                   from public.comissao_rateio_itens_dia ri join public.comissao_itens it on it.id = ri.item_id
                  where ri.fechamento_id = rd.fechamento_id and ri.data = rd.data), '[]'::jsonb))
             order by rd.data)
        from public.comissao_rateio_dias rd where rd.fechamento_id = fc.id), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', it.id, 'tipo', it.tipo, 'funcionario_id', it.funcionario_id, 'extra_id', it.extra_id,
               'nome', it.funcionario_nome, 'cargo', it.cargo, 'incluido', it.incluido, 'pontos', it.pontos,
               'pontos_manual', it.pontos_manual, 'pontos_pendente', it.pontos_pendente, 'dias_presentes', it.dias_presentes,
               'pontos_efetivos', it.pontos_efetivos, 'valor_centavos', it.valor_centavos,
               'entrada', case
                 when it.tipo = 'extra' then coalesce((
                   select jsonb_agg(jsonb_build_object('data', d.data, 'presente', true, 'pontos', d.pontos,
                                                       'pendente', d.pontos_pendente) order by d.data)
                     from public.diarias d
                    where d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim), '[]'::jsonb)
                 when it.funcionario_id is null then '[]'::jsonb
                 else coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'data', p.data, 'presente', p.presente, 'fallback', p.fallback, 'bloqueado', p.bloqueado,
                            'motivo', p.motivo, 'origem', p.origem,
                            'pontos', coalesce(public.comissao_pontos_vigentes(it.funcionario_id, p.data), 0))
                          order by p.data)
                     from pres p where p.funcionario_id = it.funcionario_id), '[]'::jsonb)
               end)
             order by it.funcionario_nome collate "C", (it.tipo = 'extra'), coalesce(it.funcionario_id, it.extra_id) nulls last, it.id)
        from public.comissao_itens it where it.fechamento_id = fc.id), '[]'::jsonb)));
end $$;
comment on function public.comissao_detalhe(uuid) is '[api] Fechamento com rateio por dia e entradas da prévia (G A M).';

-- ================================================================ extras: pontuação pendente (§E.7.5)
create or replace function public.extra_definir_pontuacao(p_extra uuid, p_pontos numeric)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras; v_n int; v_ini date; v_fim date;
begin
  x := public.extra_para_operar(p_extra);
  if p_pontos is null or p_pontos < 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2) then
    raise exception 'Pontos inválidos' using errcode = '22023';
  end if;
  update public.extras set pontos_padrao = p_pontos, pontos_pendente = false where id = x.id;
  select min(d.data), max(d.data) into v_ini, v_fim from public.diarias d
   where d.extra_id = x.id and d.pontos_pendente and not public.comissao_periodo_fechado(d.empresa_id, d.data);
  update public.diarias d set pontos = p_pontos, pontos_pendente = false
   where d.extra_id = x.id and d.pontos_pendente and not public.comissao_periodo_fechado(d.empresa_id, d.data);
  get diagnostics v_n = row_count;
  if v_n > 0 then perform public.comissao_recalcular_rascunhos(x.empresa_id, v_ini, v_fim); end if;
  return v_n;
end $$;
comment on function public.extra_definir_pontuacao(uuid, numeric) is
  '[api] Preenche a pontuação de um extra e dos dias pendentes dele (G A M); recalcula rascunhos.';

-- ================================================================ importação de extras (§E.7.6)
create or replace function public.extras_normalizar_documento(p text)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select nullif(lower(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g')), '')
$$;
comment on function public.extras_normalizar_documento(text) is '[interno] Documento só com letras e dígitos, minúsculo.';

create or replace function public.extras_normalizar_nome(p text)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select nullif(lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')), '')
$$;
comment on function public.extras_normalizar_nome(text) is '[interno] Nome minúsculo, sem pontas e com espaços colapsados.';

-- Converte um campo jsonb (número ou texto) para numeric/bigint/date com a mensagem do contrato.
create or replace function public.extras_imp_num(p jsonb, p_msg text)
returns numeric language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) = 'number' then return (p #>> '{}')::numeric; end if;
  if jsonb_typeof(p) = 'string' and btrim(p #>> '{}') = '' then return null; end if;
  return replace(btrim(p #>> '{}'), ',', '.')::numeric;
exception when others then
  raise exception '%', p_msg using errcode = '22023';
end $$;
comment on function public.extras_imp_num(jsonb, text) is '[interno] Número de um campo da importação.';

create or replace function public.extras_imp_data(p jsonb)
returns date language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p is null or p = 'null'::jsonb or btrim(p #>> '{}') = '' then return null; end if;
  if (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida' using errcode = '22023'; end if;
  return (p #>> '{}')::date;
exception when others then
  raise exception 'Data inválida' using errcode = '22023';
end $$;
comment on function public.extras_imp_data(jsonb) is '[interno] Data (AAAA-MM-DD) de um campo da importação.';

create or replace function public.extras_importar(p_itens jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_linha jsonb; v_n int := 0; v_criados int := 0; v_atualizados int := 0; v_dias int := 0;
  v_erros jsonb := '[]'; v_pend uuid[] := '{}'; v_nome text; v_doc text; v_pontos numeric; v_valor numeric; v_extra uuid;
  v_qtd int; v_dia jsonb; v_data date; v_dpontos numeric; v_dvalor numeric; x public.extras; v_dias_linha int;
  v_criou boolean; v_diaria public.diarias; v_tem_pontos boolean; v_pend_dia boolean; v_msg text;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'Lista de extras inválida' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) > 1000 then
    raise exception 'Máximo de 1000 linhas por importação' using errcode = '22023';
  end if;

  for v_linha in select e from jsonb_array_elements(p_itens) e loop
    v_n := v_n + 1;
    begin
      if jsonb_typeof(v_linha) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
      v_nome := nullif(btrim(coalesce(v_linha ->> 'nome', '')), '');
      if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
      v_doc := nullif(btrim(coalesce(v_linha ->> 'documento', '')), '');
      v_tem_pontos := v_linha ? 'pontos' and v_linha -> 'pontos' <> 'null'::jsonb;
      v_pontos := public.extras_imp_num(v_linha -> 'pontos', 'Pontos inválidos');
      if v_pontos is not null and (v_pontos < 0 or v_pontos > 9999.99 or v_pontos <> round(v_pontos, 2)) then
        raise exception 'Pontos inválidos' using errcode = '22023';
      end if;
      v_tem_pontos := v_pontos is not null;
      v_valor := public.extras_imp_num(v_linha -> 'valor_diaria_centavos', 'Valor inválido');
      if v_valor is not null and (v_valor < 0 or v_valor > 100000000 or v_valor <> round(v_valor)) then
        raise exception 'Valor inválido' using errcode = '22023';
      end if;
      if v_linha ? 'dias_trabalhados' and v_linha -> 'dias_trabalhados' <> 'null'::jsonb
         and jsonb_typeof(v_linha -> 'dias_trabalhados') <> 'array' then
        raise exception 'Linha inválida' using errcode = '22023';
      end if;

      -- casamento: documento normalizado; senão nome normalizado (entre os sem documento, quando há documento)
      v_extra := null;
      if v_doc is not null then
        select x2.id into v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_documento(x2.documento) = public.extras_normalizar_documento(v_doc)
         order by x2.criado_em, x2.id limit 1;
      end if;
      if v_extra is null then
        select count(*), min(x2.id::text)::uuid into v_qtd, v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_nome(x2.nome) = public.extras_normalizar_nome(v_nome)
           and (v_doc is null or x2.documento is null);
        if v_qtd > 1 then
          raise exception 'Mais de um extra com este nome: informe o documento' using errcode = '22023';
        end if;
      end if;

      v_criou := v_extra is null;
      if v_criou then
        insert into public.extras (empresa_id, nome, funcao, telefone, documento, pontos_padrao, pontos_pendente,
                                   valor_diaria_centavos, criado_por)
        values (v_empresa, v_nome, nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''),
                nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), v_doc, coalesce(v_pontos, 0), not v_tem_pontos,
                v_valor::bigint, public.meu_perfil_id())
        returning id into v_extra;
      else
        update public.extras e
           set funcao = coalesce(nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''), e.funcao),
               telefone = coalesce(nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), e.telefone),
               documento = coalesce(v_doc, e.documento),
               valor_diaria_centavos = coalesce(v_valor::bigint, e.valor_diaria_centavos),
               ativo = true
         where e.id = v_extra;
        if v_tem_pontos then perform public.extra_definir_pontuacao(v_extra, v_pontos); end if;
      end if;
      select * into x from public.extras where id = v_extra;

      v_dias_linha := 0;
      for v_dia in select d from jsonb_array_elements(coalesce(nullif(v_linha -> 'dias_trabalhados', 'null'::jsonb), '[]')) d loop
        if jsonb_typeof(v_dia) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
        v_data := public.extras_imp_data(v_dia -> 'data');
        if v_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
        v_dpontos := public.extras_imp_num(v_dia -> 'pontos', 'Pontos inválidos');
        v_dvalor := public.extras_imp_num(v_dia -> 'valor_centavos', 'Valor inválido');
        if v_dvalor is not null and v_dvalor <> round(v_dvalor) then raise exception 'Valor inválido' using errcode = '22023'; end if;
        v_pend_dia := v_dpontos is null and x.pontos_pendente;
        v_dpontos := case when v_pend_dia then 0 else coalesce(v_dpontos, x.pontos_padrao) end;
        v_dvalor := coalesce(v_dvalor, x.valor_diaria_centavos);
        perform public.diaria_validar_valores(v_empresa, v_data, v_dpontos, v_dvalor::bigint, true);
        perform public.diaria_checar_trava(v_empresa, v_data);
        select * into v_diaria from public.diarias where extra_id = x.id and data = v_data;
        if v_diaria.id is null then
          insert into public.diarias (empresa_id, tipo, extra_id, pessoa_nome, data, funcao, pontos, pontos_pendente,
                                      valor_centavos, criado_por, criado_por_nome)
          values (v_empresa, 'extra', x.id, x.nome, v_data, x.funcao, v_dpontos, v_pend_dia, v_dvalor::bigint,
                  public.meu_perfil_id(), public.ponto_nome_autor());
        else
          update public.diarias set pontos = v_dpontos, pontos_pendente = v_pend_dia, valor_centavos = v_dvalor::bigint
           where id = v_diaria.id;
        end if;
        v_dias_linha := v_dias_linha + 1;
      end loop;

      v_dias := v_dias + v_dias_linha;
      if v_criou then v_criados := v_criados + 1; else v_atualizados := v_atualizados + 1; end if;
      select * into x from public.extras where id = v_extra;
      if x.pontos_pendente and not (x.id = any (v_pend)) then v_pend := v_pend || x.id; end if;
      if not x.pontos_pendente then v_pend := array_remove(v_pend, x.id); end if;
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v_erros := v_erros || jsonb_build_object('linha', v_n, 'mensagem', v_msg);
    end;
  end loop;

  return jsonb_build_object('lidos', v_n, 'criados', v_criados, 'atualizados', v_atualizados, 'dias_lancados', v_dias,
                            'pendentes_pontuacao', coalesce(array_length(v_pend, 1), 0), 'erros', v_erros);
end $$;
comment on function public.extras_importar(jsonb, uuid) is
  '[api] Importa extras em lote (upsert por documento ou nome) com dias trabalhados; sem pontos = pontuação pendente (G A M).';

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000290_comissao_presenca.sql

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 20261006000900_permissoes.sql
-- =====================================================================================================
-- 20261006000900_permissoes.sql  (backend-1) — SEMPRE A ÚLTIMA MIGRAÇÃO.
-- Varre o catálogo de public e concede privilégios pela etiqueta no início do comment (§2.2):
--   tabela  [api:crud] → authenticated: select, insert, update, delete
--           [api:leitura] → authenticated: select
--           [api:nenhum] / sem etiqueta → nada
--   função  [api] / [politica] → execute para authenticated (+ service_role)
--           [servico] / [interno] / sem etiqueta → só service_role (e o dono)
-- anon não recebe nada em public. service_role recebe tudo. Idempotente (revoga antes de conceder).
-- =====================================================================================================

-- Objetos novos criados pelo dono (postgres) em public não ficam abertos por padrão: só esta varredura concede.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

grant usage on schema public to anon, authenticated, service_role;

do $$
declare
  r record;
  v_etiqueta text;
begin
  -- -------------------------------------------------------------- tabelas, views e afins
  for r in
    select c.oid, c.relkind, format('%I.%I', n.nspname, c.relname) as nome,
           obj_description(c.oid, 'pg_class') as comentario
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p', 'v', 'm', 'f')
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on table %s from public, anon, authenticated', r.nome);
    execute format('grant all on table %s to service_role', r.nome);
    v_etiqueta := substring(coalesce(r.comentario, '') from '^\s*(\[[a-z_:]+\])');
    if v_etiqueta = '[api:crud]' then
      execute format('grant select, insert, update, delete on table %s to authenticated', r.nome);
    elsif v_etiqueta = '[api:leitura]' then
      execute format('grant select on table %s to authenticated', r.nome);
    end if;
  end loop;

  -- ------------------------------------------------------------------------ sequências
  for r in
    select format('%I.%I', n.nspname, c.relname) as nome,
           (select obj_description(t.oid, 'pg_class')
              from pg_depend d join pg_class t on t.oid = d.refobjid
             where d.objid = c.oid and d.deptype in ('a', 'i') and d.refclassid = 'pg_class'::regclass
             limit 1) as comentario_dono
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'S'
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on sequence %s from public, anon, authenticated', r.nome);
    execute format('grant all on sequence %s to service_role', r.nome);
    if substring(coalesce(r.comentario_dono, '') from '^\s*(\[[a-z_:]+\])') = '[api:crud]' then
      execute format('grant usage, select on sequence %s to authenticated', r.nome);
    end if;
  end loop;

  -- ------------------------------------------------------------- funções e procedimentos
  for r in
    select p.oid::regprocedure::text as assinatura, p.prokind,
           obj_description(p.oid, 'pg_proc') as comentario
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p', 'w')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on %s %s from public, anon, authenticated',
                   case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    execute format('grant execute on %s %s to service_role',
                   case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    v_etiqueta := substring(coalesce(r.comentario, '') from '^\s*(\[[a-z_:]+\])');
    if v_etiqueta in ('[api]', '[politica]') then
      execute format('grant execute on %s %s to authenticated',
                     case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    end if;
  end loop;
end $$;

-- <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< fim de 20261006000900_permissoes.sql

commit;

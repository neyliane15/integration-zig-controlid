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

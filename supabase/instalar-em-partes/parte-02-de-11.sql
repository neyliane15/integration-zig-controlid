-- Meu Dia de Gerente — instalação do banco, PARTE 02 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000110_cadastros.sql, 20261006000120_integracoes_sync.sql. Não edite à mão.

begin;
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
end $$;-- =====================================================================================================
-- 20261006000120_integracoes_sync.sql  (backend-1)
-- integracoes, integracoes_segredos, controlid_usuarios, sync_solicitacoes, sync_execucoes,
-- RPCs de integração / sincronização / usuários Control iD, RLS. Idempotente.
-- =====================================================================================================

-- ==================================================================================== integracoes
create table if not exists public.integracoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas (id) on delete cascade,
  tipo                 text not null check (tipo in ('zig', 'controlid_acesso', 'controlid_rep')),
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
comment on table public.integracoes is '[api:crud] Integrações (Zig, Control iD acesso/REP). Segredos ficam em integracoes_segredos.';

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
  escopo          text not null check (escopo in ('tudo', 'funcionarios', 'batidas', 'vendas',
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

-- ================================================================================= sync_execucoes
create table if not exists public.sync_execucoes (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid references public.empresas (id) on delete cascade,
  integracao_id        uuid references public.integracoes (id) on delete set null,
  solicitacao_id       uuid references public.sync_solicitacoes (id) on delete set null,
  tipo                 text not null check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                         'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                         'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento')),
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

commit;
select 'parte 02 de 11 instalada' as resultado;

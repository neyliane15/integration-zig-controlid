-- =====================================================================================================
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
    when 'tudo' then p_tipo in ('zig', 'controlid_acesso', 'controlid_rep')
    when 'funcionarios' then p_tipo in ('controlid_acesso', 'controlid_rep')
    when 'batidas' then p_tipo in ('controlid_acesso', 'controlid_rep')
    when 'vendas' then p_tipo = 'zig'
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
  if p_escopo is null or p_escopo not in ('tudo', 'funcionarios', 'batidas', 'vendas', 'exportar_funcionarios',
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

-- Meu Dia de Gerente — instalação do banco, PARTE 06 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000140_envio_controlid.sql, 20261006000200_ponto.sql. Não edite à mão.

begin;
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
  '[servico] Registra o resultado de um item de envio ao Control iD (adendo A.5).';-- =====================================================================================================
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
                                                        'sem_escala', 'abonado', 'em_andamento')),
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
  tipo            text not null check (tipo in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro')),
  motivo          text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_abonos_uk unique nulls not distinct (empresa_id, funcionario_id, data)
);
create index if not exists ponto_abonos_funcionario_idx on public.ponto_abonos (funcionario_id, data);
create index if not exists ponto_abonos_criado_por_idx on public.ponto_abonos (criado_por);
comment on table public.ponto_abonos is '[api:leitura] Abonos (folga, feriado, férias, atestado...). funcionario_id null = empresa toda.';

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

commit;
select 'parte 06 de 11 instalada' as resultado;

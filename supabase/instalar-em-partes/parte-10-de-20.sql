-- Meu Dia de Gerente — instalação do banco, PARTE 10 DE 20.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000220_comissoes.sql, 20261006000230_ingestao.sql. Não edite à mão.

begin;
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
comment on function public.comissao_excluir_rascunho(uuid) is '[api] Exclui um rascunho de comissão.';-- =====================================================================================================
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

commit;
select 'parte 10 de 20 instalada' as resultado;

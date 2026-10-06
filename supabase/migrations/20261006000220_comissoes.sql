-- =====================================================================================================
-- 20261006000220_comissoes.sql — backend-2
-- Comissão: serviço (Tips da Zig) − retenção = base; rateio por pontos com maior resto; rascunho → fechado (imutável).
-- Contrato: §6 (DDL), §9 (regras), §10.6 (RPCs). Idempotente.
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

alter table public.comissao_fechamentos enable row level security;
alter table public.comissao_itens enable row level security;
drop policy if exists comissao_fechamentos_ler on public.comissao_fechamentos;
create policy comissao_fechamentos_ler on public.comissao_fechamentos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists comissao_itens_ler on public.comissao_itens;
create policy comissao_itens_ler on public.comissao_itens for select to authenticated
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
       and public.comissao_so_anula_fks(to_jsonb(old), to_jsonb(new), array['funcionario_id']) then
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
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento for update;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;

  -- 1–3. serviço, retenção, base
  select coalesce(sum(i.valor_total), 0) into v_zig
    from public.zig_vendas_itens i
   where i.empresa_id = fc.empresa_id and i.tipo = 'Tip'
     and i.data_operacao between fc.data_inicio and fc.data_fim
     and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo);
  v_bruto := greatest(0, v_zig + fc.servico_ajuste_centavos);
  v_ret := round(v_bruto::numeric * fc.percentual_retencao / 100);
  v_base := v_bruto - v_ret;
  v_dias := fc.data_fim - fc.data_inicio + 1;

  -- 5–6. dias trabalhados e pontos efetivos
  update public.comissao_itens it
     set dias_trabalhados = case when it.funcionario_id is null then it.dias_trabalhados
                                 else (select count(*) from public.ponto_dias d
                                        where d.funcionario_id = it.funcionario_id
                                          and d.data between fc.data_inicio and fc.data_fim
                                          and d.batidas_validas > 0) end
   where it.fechamento_id = p_fechamento;
  update public.comissao_itens it
     set pontos_efetivos = case when not it.incluido then 0
                                when fc.proporcional_dias then round(it.pontos * it.dias_trabalhados / v_dias, 6)
                                else it.pontos end
   where it.fechamento_id = p_fechamento;

  select coalesce(sum(it.pontos_efetivos), 0) into v_soma from public.comissao_itens it where it.fechamento_id = p_fechamento;

  if v_soma = 0 then
    update public.comissao_itens set valor_centavos = 0 where fechamento_id = p_fechamento;
  else
    -- 9. maior resto
    with c as (
      select it.id, it.pontos_efetivos, it.funcionario_nome, it.funcionario_id,
             v_base * it.pontos_efetivos / v_soma as exato
        from public.comissao_itens it where it.fechamento_id = p_fechamento
    )
    update public.comissao_itens it set valor_centavos = floor(c.exato)::bigint
      from c where it.id = c.id;
    select v_base - coalesce(sum(valor_centavos), 0) into v_resto
      from public.comissao_itens where fechamento_id = p_fechamento;
    with ordem as (
      select it.id
        from public.comissao_itens it
       where it.fechamento_id = p_fechamento and it.pontos_efetivos > 0
       order by (v_base * it.pontos_efetivos / v_soma) - floor(v_base * it.pontos_efetivos / v_soma) desc,
                it.pontos_efetivos desc, it.funcionario_nome asc, it.funcionario_id asc nulls last, it.id
       limit v_resto
    )
    update public.comissao_itens it set valor_centavos = it.valor_centavos + 1
      from ordem where it.id = ordem.id;
  end if;

  update public.comissao_fechamentos
     set servico_zig_centavos = v_zig,
         servico_bruto_centavos = v_bruto,
         retencao_centavos = v_ret,
         base_distribuivel_centavos = v_base,
         dias_periodo = v_dias,
         soma_pontos_efetivos = v_soma,
         valor_ponto_centavos = case when v_soma = 0 then null else round(v_base / v_soma, 6) end,
         calculado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_calcular(uuid) is '[interno] Recalcula um fechamento em rascunho (§9).';

-- Carrega o fechamento e checa permissão de operação (G A M) e status rascunho.
create or replace function public.comissao_rascunho_para_editar(p_fechamento uuid)
returns public.comissao_fechamentos language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if not public.pode_operar(fc.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  return fc;
end $$;
comment on function public.comissao_rascunho_para_editar(uuid) is '[interno] Fechamento em rascunho editável pelo usuário?';

-- ================================================================ RPCs
create or replace function public.comissao_criar_fechamento(p_data_inicio date, p_data_fim date, p_titulo text default null,
                                                            p_loja text default null, p_proporcional_dias boolean default false,
                                                            p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid; v_pct numeric;
begin
  v_empresa := public.resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_data_inicio, p_data_fim, 93);
  p_loja := nullif(btrim(p_loja), '');
  if p_loja is not null and not exists (select 1 from public.zig_lojas l
                                         where l.empresa_id = v_empresa and l.loja_id_externo = p_loja) then
    raise exception 'Loja não encontrada' using errcode = 'P0002';
  end if;
  select e.comissao_percentual_retencao into v_pct from public.empresas e where e.id = v_empresa;

  insert into public.comissao_fechamentos (empresa_id, titulo, data_inicio, data_fim, loja_id_externo, percentual_retencao,
                                           proporcional_dias, criado_por)
  values (v_empresa,
          coalesce(nullif(btrim(p_titulo), ''),
                   'Comissão ' || to_char(p_data_inicio, 'DD/MM') || ' a ' || to_char(p_data_fim, 'DD/MM/YYYY')),
          p_data_inicio, p_data_fim, p_loja, coalesce(v_pct, 20), coalesce(p_proporcional_dias, false), auth.uid())
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
comment on function public.comissao_criar_fechamento(date, date, text, text, boolean, uuid) is '[api] Cria rascunho de comissão com os participantes e calcula.';

create or replace function public.comissao_atualizar_fechamento(p_fechamento uuid, p_titulo text, p_servico_ajuste_centavos bigint,
                                                                p_percentual_retencao numeric, p_proporcional_dias boolean,
                                                                p_observacoes text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  if p_percentual_retencao is not null and (p_percentual_retencao < 0 or p_percentual_retencao > 100) then
    raise exception 'Percentual de retenção inválido' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set titulo = coalesce(nullif(btrim(p_titulo), ''), titulo),
         servico_ajuste_centavos = coalesce(p_servico_ajuste_centavos, servico_ajuste_centavos),
         percentual_retencao = coalesce(p_percentual_retencao, percentual_retencao),
         proporcional_dias = coalesce(p_proporcional_dias, proporcional_dias),
         observacoes = nullif(btrim(p_observacoes), '')
   where id = p_fechamento;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_atualizar_fechamento(uuid, text, bigint, numeric, boolean, text) is '[api] Edita parâmetros do rascunho e recalcula.';

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

  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, incluido, pontos)
  values (fc.empresa_id, p_fechamento, f.id, f.nome, f.cargo, coalesce(p_incluido, true), v_pontos)
  on conflict (fechamento_id, funcionario_id) do update
    set funcionario_nome = excluded.funcionario_nome, cargo = excluded.cargo,
        incluido = excluded.incluido, pontos = excluded.pontos;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_definir_item(uuid, uuid, numeric, boolean) is '[api] Inclui/atualiza participante (snapshot de nome/cargo) e recalcula.';

create or replace function public.comissao_remover_item(p_fechamento uuid, p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  delete from public.comissao_itens where fechamento_id = p_fechamento and funcionario_id = p_funcionario;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_remover_item(uuid, uuid) is '[api] Remove participante do rascunho e recalcula.';

create or replace function public.comissao_recalcular(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_recalcular(uuid) is '[api] Relê serviço e presença e recalcula o rascunho.';

create or replace function public.comissao_fechar(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if not public.pode_operar(fc.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if not public.pode_administrar(fc.empresa_id) then
    raise exception 'Somente o administrador fecha a comissão' using errcode = '42501';
  end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  perform public.comissao_calcular(p_fechamento);
  if not exists (select 1 from public.comissao_fechamentos where id = p_fechamento and soma_pontos_efetivos > 0) then
    raise exception 'Fechamento sem participantes' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set status = 'fechado', fechado_por = auth.uid(), fechado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_fechar(uuid) is '[api] Recalcula e fecha (administrador). Depois é imutável.';

create or replace function public.comissao_excluir_rascunho(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  delete from public.comissao_fechamentos where id = p_fechamento;
end $$;
comment on function public.comissao_excluir_rascunho(uuid) is '[api] Exclui um rascunho de comissão.';

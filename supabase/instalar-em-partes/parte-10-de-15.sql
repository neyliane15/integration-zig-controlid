-- Meu Dia de Gerente — instalação do banco, PARTE 10 DE 15.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000220_comissoes.sql. Não edite à mão.

begin;
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
  v_aj_abs  bigint;
  v_sinal   int;
  v_sp      int := 0;
  v_spart   int := 0;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento for update;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  v_dias := fc.data_fim - fc.data_inicio + 1;

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
  -- extras: snapshot atualizado, pontos = média dos lançamentos (2 casas), dias lançados
  update public.comissao_itens it
     set funcionario_nome = x.nome, cargo = x.funcao,
         pontos = coalesce(l.media, x.pontos_padrao), dias_presentes = l.qtd, dias_trabalhados = l.qtd
    from public.extras x,
         lateral (select round(avg(d.pontos), 2) as media, count(*)::int as qtd from public.diarias d
                   where d.extra_id = x.id and d.data between fc.data_inicio and fc.data_fim) l
   where it.fechamento_id = p_fechamento and it.extra_id = x.id;
  -- funcionários: dias com batida válida
  update public.comissao_itens it set dias_presentes = 0, dias_trabalhados = 0
   where it.fechamento_id = p_fechamento and it.tipo = 'funcionario';
  update public.comissao_itens it
     set dias_presentes = c.qtd, dias_trabalhados = c.qtd
    from (select d.funcionario_id, count(*)::int as qtd from public.ponto_dias d
           where d.data between fc.data_inicio and fc.data_fim and d.batidas_validas > 0
           group by d.funcionario_id) c
   where c.funcionario_id = it.funcionario_id and it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.funcionario_id is not null;

  -- 1. serviço do período
  select coalesce(sum(i.valor_total), 0) into v_zig
    from public.zig_vendas_itens i
   where i.empresa_id = fc.empresa_id and i.tipo = 'Tip'
     and i.data_operacao between fc.data_inicio and fc.data_fim
     and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo);

  delete from public.comissao_rateio_itens_dia where fechamento_id = p_fechamento;
  delete from public.comissao_rateio_dias where fechamento_id = p_fechamento;

  if fc.modo_rateio = 'periodo' then
    -- ============================================== modo período (§9)
    v_bruto := greatest(0, v_zig + fc.servico_ajuste_centavos);
    v_ret := round(v_bruto::numeric * fc.percentual_retencao / 100);
    v_base := v_bruto - v_ret;
    update public.comissao_itens it
       set pontos_efetivos = case
             when not it.incluido then 0
             when it.tipo = 'extra' then
               round(coalesce((select sum(d.pontos) from public.diarias d
                                where d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim), 0) / v_dias, 6)
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
    -- ============================================== modo diário (adendo E.3.2)
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

    -- 4. presentes do dia: funcionários com batida válida (pontos vigentes na data ou manuais) e extras lançados
    insert into public.comissao_rateio_itens_dia (item_id, fechamento_id, empresa_id, data, pontos, fallback)
    select it.id, p_fechamento, fc.empresa_id, pd.data, x.pontos, false
      from public.comissao_itens it
      join public.ponto_dias pd on pd.funcionario_id = it.funcionario_id
                               and pd.data between fc.data_inicio and fc.data_fim and pd.batidas_validas > 0
      cross join lateral (select case when it.pontos_manual then it.pontos
                                      else coalesce(public.comissao_pontos_vigentes(it.funcionario_id, pd.data), 0) end as pontos) x
     where it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.incluido and x.pontos > 0
    union all
    select it.id, p_fechamento, fc.empresa_id, d.data, d.pontos, false
      from public.comissao_itens it
      join public.diarias d on d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim
     where it.fechamento_id = p_fechamento and it.tipo = 'extra' and it.incluido and d.pontos > 0;

    -- 5. fallback: dia com base > 0 e ninguém presente → todos os funcionários incluídos
    insert into public.comissao_rateio_itens_dia (item_id, fechamento_id, empresa_id, data, pontos, fallback)
    select it.id, p_fechamento, fc.empresa_id, rd.data, x.pontos, true
      from public.comissao_rateio_dias rd
      join public.comissao_itens it on it.fechamento_id = p_fechamento and it.tipo = 'funcionario' and it.incluido
      cross join lateral (select case when it.pontos_manual or it.funcionario_id is null then it.pontos
                                      else coalesce(public.comissao_pontos_vigentes(it.funcionario_id, rd.data), 0) end as pontos) x
     where rd.fechamento_id = p_fechamento and rd.base_centavos > 0 and x.pontos > 0
       and not exists (select 1 from public.comissao_rateio_itens_dia ri
                        where ri.fechamento_id = p_fechamento and ri.data = rd.data);

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
         calculado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_calcular(uuid) is '[interno] Recalcula um fechamento em rascunho (§9 modo período; adendo E.3 modo diário).';

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

commit;
select 'parte 10 de 15 instalada' as resultado;

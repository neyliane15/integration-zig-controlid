-- Meu Dia de Gerente — instalação do banco, PARTE 18 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000290_comissao_presenca.sql. Não edite à mão.

begin;
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

commit;
select 'parte 18 de 19 instalada' as resultado;

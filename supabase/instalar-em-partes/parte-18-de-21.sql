-- Meu Dia de Gerente — instalação do banco, PARTE 18 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000290_comissao_presenca.sql. Não edite à mão.

begin;
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

commit;
select 'parte 18 de 21 instalada' as resultado;

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

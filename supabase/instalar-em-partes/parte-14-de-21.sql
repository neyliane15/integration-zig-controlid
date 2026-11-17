-- Meu Dia de Gerente — instalação do banco, PARTE 14 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000260_extras.sql, 20261006000270_reservas.sql. Não edite à mão.

begin;
-- (v3) retorno ganhou pontos_pendente/dias_pendentes: mudança de tipo de retorno exige drop (privilégios voltam na …0900)
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'extras_listar'
                and pg_get_function_result(p.oid) not like '%dias_pendentes%') then
    drop function public.extras_listar(boolean, uuid);
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'diarias_listar'
                and pg_get_function_result(p.oid) not like '%pontos_pendente%') then
    drop function public.diarias_listar(date, date, text, uuid, uuid, boolean, uuid);
  end if;
end $$;

create or replace function public.extras_listar(p_incluir_inativos boolean default false, p_empresa uuid default null)
returns table (id uuid, nome text, funcao text, telefone text, documento text, pontos_padrao numeric, valor_diaria_centavos bigint,
               ativo boolean, observacoes text, pontos_pendente boolean, dias_lancados int, ultimo_dia date, dias_pendentes int,
               criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  return query
  select x.id, x.nome, x.funcao, x.telefone, x.documento, x.pontos_padrao, x.valor_diaria_centavos, x.ativo, x.observacoes,
         x.pontos_pendente, coalesce(l.qtd, 0)::int, l.ultimo, coalesce(l.pend, 0)::int, x.criado_em
    from public.extras x
    left join lateral (select count(*) as qtd, max(d.data) as ultimo, count(*) filter (where d.pontos_pendente) as pend
                         from public.diarias d where d.extra_id = x.id) l on true
   where x.empresa_id = v_empresa and (coalesce(p_incluir_inativos, false) or x.ativo)
   order by lower(x.nome), x.id;
end $$;
comment on function public.extras_listar(boolean, uuid) is '[api] Extras cadastrados da empresa (G A M).';

-- ================================================================ RPCs de valor padrão (funcionário)
create or replace function public.funcionario_definir_valor_diaria(p_funcionario uuid, p_valor_centavos bigint)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios;
begin
  f := public.funcionario_para_operar(p_funcionario);
  if p_valor_centavos is null then
    delete from public.funcionario_valores_diaria where funcionario_id = f.id;
    return;
  end if;
  if p_valor_centavos < 0 or p_valor_centavos > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
  insert into public.funcionario_valores_diaria (funcionario_id, empresa_id, valor_diaria_centavos, atualizado_por, atualizado_em)
  values (f.id, f.empresa_id, p_valor_centavos, public.meu_perfil_id(), now())
  on conflict (funcionario_id) do update
    set valor_diaria_centavos = excluded.valor_diaria_centavos, atualizado_por = excluded.atualizado_por,
        atualizado_em = excluded.atualizado_em;
end $$;
comment on function public.funcionario_definir_valor_diaria(uuid, bigint) is
  '[api] Define (ou remove, null) o valor padrão da diária do funcionário (G A M).';

create or replace function public.funcionario_valores_diaria_listar(p_empresa uuid default null)
returns table (funcionario_id uuid, valor_diaria_centavos bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  return query select v.funcionario_id, v.valor_diaria_centavos from public.funcionario_valores_diaria v
                where v.empresa_id = v_empresa order by v.funcionario_id;
end $$;
comment on function public.funcionario_valores_diaria_listar(uuid) is '[api] Valores padrão de diária da empresa (G A M).';

-- ================================================================ RPCs de dias trabalhados (E.2)
create or replace function public.diaria_validar_valores(p_empresa uuid, p_data date, p_pontos numeric, p_valor bigint,
                                                         p_extra boolean)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date;
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.dia_de_trabalho(public.agora(), p_empresa);
  if p_data < v_hoje - 366 or p_data > v_hoje + 62 then raise exception 'Data fora do limite' using errcode = '22023'; end if;
  if p_extra and (p_pontos is null or p_pontos < 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2)) then
    raise exception 'Pontos inválidos' using errcode = '22023';
  end if;
  if p_valor is null then raise exception 'Informe o valor da diária' using errcode = '22023'; end if;
  if p_valor < 0 or p_valor > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
end $$;
comment on function public.diaria_validar_valores(uuid, date, numeric, bigint, boolean) is '[interno] Validação de dia trabalhado (E.2).';

create or replace function public.diaria_checar_trava(p_empresa uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if public.comissao_periodo_fechado(p_empresa, p_data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
end $$;
comment on function public.diaria_checar_trava(uuid, date) is '[interno] Dia de extra em fechamento fechado é recusado (E.2).';

create or replace function public.diaria_checar_duplicada(p_extra uuid, p_data date, p_ignorar uuid default null)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if exists (select 1 from public.diarias d where d.extra_id = p_extra and d.data = p_data
                                              and (p_ignorar is null or d.id <> p_ignorar)) then
    raise exception 'Extra já tem dia lançado em %', to_char(p_data, 'DD/MM/YYYY') using errcode = '23505';
  end if;
end $$;
comment on function public.diaria_checar_duplicada(uuid, date, uuid) is '[interno] Um lançamento por extra por dia (E.2).';

create or replace function public.diaria_lancar(p_data date, p_extra uuid default null, p_funcionario uuid default null,
                                                p_pontos numeric default null, p_valor_centavos bigint default null,
                                                p_funcao text default null, p_observacao text default null,
                                                p_pago boolean default false, p_pago_em date default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras; f public.funcionarios; v_empresa uuid; v_pontos numeric; v_valor bigint; v_funcao text;
        v_nome text; v_pago boolean; v_id uuid; v_pend boolean := false;
begin
  if (p_extra is null) = (p_funcionario is null) then
    raise exception 'Informe o extra ou o funcionário' using errcode = '22023';
  end if;
  if p_extra is not null then
    x := public.extra_para_operar(p_extra);
    if not x.ativo then raise exception 'Extra inativo' using errcode = '22023'; end if;
    v_empresa := x.empresa_id; v_nome := x.nome;
    v_pontos := coalesce(p_pontos, x.pontos_padrao);
    v_pend := x.pontos_pendente and p_pontos is null;     -- (v3) extra sem pontuação: dia pendente (vale 0)
    if v_pend then v_pontos := 0; end if;
    v_valor := coalesce(p_valor_centavos, x.valor_diaria_centavos);
    v_funcao := coalesce(nullif(btrim(p_funcao), ''), x.funcao);
  else
    f := public.funcionario_para_operar(p_funcionario);
    if p_pontos is not null then raise exception 'Diária de funcionário não tem pontos' using errcode = '22023'; end if;
    v_empresa := f.empresa_id; v_nome := f.nome;
    v_valor := coalesce(p_valor_centavos,
                        (select v.valor_diaria_centavos from public.funcionario_valores_diaria v where v.funcionario_id = f.id));
    v_funcao := coalesce(nullif(btrim(p_funcao), ''), f.cargo);
  end if;
  perform public.diaria_validar_valores(v_empresa, p_data, v_pontos, v_valor, p_extra is not null);
  if p_extra is not null then
    perform public.diaria_checar_trava(v_empresa, p_data);
    perform public.diaria_checar_duplicada(x.id, p_data);
  end if;
  v_pago := coalesce(p_pago, false);
  insert into public.diarias (empresa_id, tipo, extra_id, funcionario_id, pessoa_nome, data, funcao, pontos, pontos_pendente,
                              valor_centavos, observacao, pago, pago_em, criado_por, criado_por_nome)
  values (v_empresa, case when p_extra is not null then 'extra' else 'funcionario' end, x.id, f.id, v_nome, p_data, v_funcao,
          v_pontos, v_pend, v_valor, nullif(btrim(p_observacao), ''), v_pago,
          case when v_pago then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), v_empresa)) end,
          public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.diaria_lancar(date, uuid, uuid, numeric, bigint, text, text, boolean, date) is
  '[api] Lança um dia trabalhado de extra (com pontos) ou diária de funcionário (G A M).';

create or replace function public.diaria_para_operar(p_diaria uuid)
returns public.diarias language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  select * into d from public.diarias where id = p_diaria;
  if not found then raise exception 'Diária não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(d.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return d;
end $$;
comment on function public.diaria_para_operar(uuid) is '[interno] Diária existente e operável (G A M).';

create or replace function public.diaria_atualizar(p_diaria uuid, p_data date, p_pontos numeric, p_valor_centavos bigint,
                                                   p_funcao text, p_observacao text, p_pago boolean, p_pago_em date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias; v_data date; v_pontos numeric; v_valor bigint; v_funcao_padrao text;
begin
  d := public.diaria_para_operar(p_diaria);
  if d.tipo = 'funcionario' and p_pontos is not null then
    raise exception 'Diária de funcionário não tem pontos' using errcode = '22023';
  end if;
  v_data := coalesce(p_data, d.data);
  v_pontos := case when d.tipo = 'extra' then coalesce(p_pontos, d.pontos) end;
  v_valor := coalesce(p_valor_centavos, d.valor_centavos);
  if v_data <> d.data then
    perform public.diaria_validar_valores(d.empresa_id, v_data, v_pontos, v_valor, d.tipo = 'extra');
  else
    -- data inalterada: não reaplica o limite de data (lançamento antigo continua editável, ex.: marcar pago)
    if d.tipo = 'extra' and (v_pontos < 0 or v_pontos > 9999.99 or v_pontos <> round(v_pontos, 2)) then
      raise exception 'Pontos inválidos' using errcode = '22023';
    end if;
    if v_valor < 0 or v_valor > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
  end if;
  if d.tipo = 'extra' and (v_data <> d.data or v_pontos <> d.pontos or (d.pontos_pendente and p_pontos is not null)) then
    perform public.diaria_checar_trava(d.empresa_id, d.data);
    perform public.diaria_checar_trava(d.empresa_id, v_data);
    if v_data <> d.data then perform public.diaria_checar_duplicada(d.extra_id, v_data, d.id); end if;
  end if;
  select coalesce((select x.funcao from public.extras x where x.id = d.extra_id),
                  (select f.cargo from public.funcionarios f where f.id = d.funcionario_id)) into v_funcao_padrao;
  update public.diarias
     set data = v_data, pontos = v_pontos, valor_centavos = v_valor,
         pontos_pendente = pontos_pendente and p_pontos is null,     -- (v3) pontos informados tiram a pendência
         funcao = coalesce(nullif(btrim(p_funcao), ''), v_funcao_padrao),
         observacao = nullif(btrim(p_observacao), ''),
         pago = coalesce(p_pago, pago),
         pago_em = case when p_pago is null then pago_em
                        when p_pago then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), d.empresa_id)) end
   where id = d.id;
end $$;
comment on function public.diaria_atualizar(uuid, date, numeric, bigint, text, text, boolean, date) is
  '[api] Edita um dia trabalhado/diária (null mantém data, pontos, valor e pagamento) (G A M).';

create or replace function public.diaria_marcar_paga(p_diaria uuid, p_pago boolean, p_pago_em date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  d := public.diaria_para_operar(p_diaria);
  update public.diarias
     set pago = coalesce(p_pago, false),
         pago_em = case when coalesce(p_pago, false)
                        then coalesce(p_pago_em, public.dia_de_trabalho(public.agora(), d.empresa_id)) end
   where id = d.id;
end $$;
comment on function public.diaria_marcar_paga(uuid, boolean, date) is '[api] Marca/desmarca a diária como paga (G A M).';

create or replace function public.diaria_excluir(p_diaria uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias;
begin
  d := public.diaria_para_operar(p_diaria);
  if d.tipo = 'extra' then perform public.diaria_checar_trava(d.empresa_id, d.data); end if;
  delete from public.diarias where id = d.id;
end $$;
comment on function public.diaria_excluir(uuid) is '[api] Exclui um dia trabalhado/diária (G A M).';

create or replace function public.diarias_listar(p_inicio date, p_fim date, p_tipo text default null, p_extra uuid default null,
                                                 p_funcionario uuid default null, p_pago boolean default null,
                                                 p_empresa uuid default null)
returns table (id uuid, data date, tipo text, extra_id uuid, funcionario_id uuid, pessoa_nome text, funcao text, pontos numeric,
               pontos_pendente boolean, valor_centavos bigint, observacao text, pago boolean, pago_em date, fechado boolean, criado_por_nome text,
               criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_extra is not null then
    v_empresa := (public.extra_para_operar(p_extra)).empresa_id;
  elsif p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  if p_tipo is not null and p_tipo not in ('extra', 'funcionario') then raise exception 'Tipo inválido' using errcode = '22023'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select d.id, d.data, d.tipo, d.extra_id, d.funcionario_id, coalesce(x.nome, f.nome, d.pessoa_nome), d.funcao, d.pontos,
         d.pontos_pendente, d.valor_centavos, d.observacao, d.pago, d.pago_em,
         d.tipo = 'extra' and public.comissao_periodo_fechado(d.empresa_id, d.data), d.criado_por_nome, d.criado_em
    from public.diarias d
    left join public.extras x on x.id = d.extra_id
    left join public.funcionarios f on f.id = d.funcionario_id
   where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
     and (p_tipo is null or d.tipo = p_tipo)
     and (p_extra is null or d.extra_id = p_extra)
     and (p_funcionario is null or d.funcionario_id = p_funcionario)
     and (p_pago is null or d.pago = p_pago)
   order by d.data desc, coalesce(x.nome, f.nome, d.pessoa_nome), d.criado_em, d.id;
end $$;
comment on function public.diarias_listar(date, date, text, uuid, uuid, boolean, uuid) is '[api] Dias trabalhados/diárias do período (G A M).';

-- ================================================================ gastos por período (E.5)
create or replace function public.gastos_periodo(p_inicio date, p_fim date, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return (
    with fech as (   -- fechamentos que contribuem: diário que cruza o período; período com data_fim dentro
      select fc.* from public.comissao_fechamentos fc
       where fc.empresa_id = v_empresa
         and ((fc.modo_rateio = 'diario' and fc.data_inicio <= p_fim and fc.data_fim >= p_inicio)
              or (fc.modo_rateio = 'periodo' and fc.data_fim between p_inicio and p_fim))
    ),
    com as (         -- valores de comissão: diário pelo detalhe (no dia), período inteiro em data_fim
      select fe.id as fechamento_id, fe.status, it.tipo, it.funcionario_id, it.extra_id, it.funcionario_nome, ri.data,
             ri.valor_centavos as valor
        from fech fe
        join public.comissao_rateio_itens_dia ri on ri.fechamento_id = fe.id
        join public.comissao_itens it on it.id = ri.item_id
       where fe.modo_rateio = 'diario' and ri.data between p_inicio and p_fim
      union all
      select fe.id, fe.status, it.tipo, it.funcionario_id, it.extra_id, it.funcionario_nome, fe.data_fim, it.valor_centavos
        from fech fe join public.comissao_itens it on it.fechamento_id = fe.id
       where fe.modo_rateio = 'periodo'
    ),
    lanc as (        -- uma linha por valor: (chave, tipo, ids, nome, data, coluna, valor, qtd)
      select case when d.extra_id is not null then 'x:' || d.extra_id
                  when d.funcionario_id is not null then 'f:' || d.funcionario_id
                  else 'n:' || lower(btrim(d.pessoa_nome)) end as chave,
             d.tipo, d.funcionario_id, d.extra_id, coalesce(x.nome, f.nome, d.pessoa_nome) as nome, d.data,
             case when d.pago then 'diarias_pagas' else 'diarias_a_pagar' end as coluna, d.valor_centavos as valor, 1 as qtd
        from public.diarias d
        left join public.extras x on x.id = d.extra_id
        left join public.funcionarios f on f.id = d.funcionario_id
       where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
      union all
      select case when c.extra_id is not null then 'x:' || c.extra_id
                  when c.funcionario_id is not null then 'f:' || c.funcionario_id
                  else 'n:' || lower(btrim(c.funcionario_nome)) end,
             c.tipo, c.funcionario_id, c.extra_id, coalesce(x.nome, f.nome, c.funcionario_nome), c.data,
             case when c.status = 'fechado' then 'comissoes_fechadas' else 'comissoes_previstas' end, c.valor, 0
        from com c
        left join public.extras x on x.id = c.extra_id
        left join public.funcionarios f on f.id = c.funcionario_id
    ),
    tot as (
      select coalesce(sum(valor) filter (where coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(valor) filter (where coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(valor) filter (where qtd = 1 and tipo = 'extra'), 0) as dx,
             coalesce(sum(valor) filter (where qtd = 1 and tipo = 'funcionario'), 0) as dfu,
             coalesce(sum(qtd), 0) as qtd,
             coalesce(sum(valor) filter (where coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(valor) filter (where coluna = 'comissoes_previstas'), 0) as cp
        from lanc
    ),
    pessoa as (
      select chave, (array_agg(tipo))[1] as tipo,
             (array_agg(funcionario_id) filter (where funcionario_id is not null))[1] as funcionario_id,
             (array_agg(extra_id) filter (where extra_id is not null))[1] as extra_id,
             (array_agg(nome order by nome))[1] as nome,
             sum(qtd) as qtd,
             coalesce(sum(valor) filter (where coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(valor) filter (where coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(valor) filter (where coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(valor) filter (where coluna = 'comissoes_previstas'), 0) as cp
        from lanc group by chave
    ),
    dia as (
      select g::date as data,
             coalesce(sum(l.valor) filter (where l.coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(l.valor) filter (where l.coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(l.valor) filter (where l.coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(l.valor) filter (where l.coluna = 'comissoes_previstas'), 0) as cp
        from generate_series(p_inicio::timestamp, p_fim::timestamp, interval '1 day') g
        left join lanc l on l.data = g::date
       group by g
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'inicio', p_inicio, 'fim', p_fim,
      'totais', (select jsonb_build_object('diarias_pagas', dp, 'diarias_a_pagar', dap, 'diarias', dp + dap, 'diarias_qtd', qtd,
                                           'diarias_extras', dx, 'diarias_funcionarios', dfu,
                                           'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                           'total', dp + dap + cf, 'total_com_previsto', dp + dap + cf + cp) from tot),
      'por_pessoa', coalesce((select jsonb_agg(jsonb_build_object(
                         'chave', chave, 'tipo', tipo, 'funcionario_id', funcionario_id, 'extra_id', extra_id, 'nome', nome,
                         'diarias_qtd', qtd, 'diarias_pagas', dp, 'diarias_a_pagar', dap, 'comissoes_fechadas', cf,
                         'comissoes_previstas', cp, 'total', dp + dap + cf) order by dp + dap + cf desc, nome collate "C", chave)
                       from pessoa where qtd > 0 or dp + dap + cf + cp > 0), '[]'::jsonb),
      'por_dia', (select jsonb_agg(jsonb_build_object('data', data, 'diarias_pagas', dp, 'diarias_a_pagar', dap,
                                                      'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                                      'total', dp + dap + cf) order by data) from dia),
      'fechamentos', coalesce((select jsonb_agg(jsonb_build_object(
                                 'id', fe.id, 'titulo', fe.titulo, 'status', fe.status, 'modo_rateio', fe.modo_rateio,
                                 'data_inicio', fe.data_inicio, 'data_fim', fe.data_fim,
                                 'base_distribuivel_centavos', fe.base_distribuivel_centavos,
                                 'valor_no_periodo_centavos', coalesce((select sum(c.valor) from com c where c.fechamento_id = fe.id), 0))
                               order by fe.data_fim, fe.titulo, fe.id) from fech fe), '[]'::jsonb))
  );
end $$;
comment on function public.gastos_periodo(date, date, uuid) is
  '[api] Gastos do período: diárias (extras e funcionários, pagas/a pagar) e comissões (fechadas/previstas), por pessoa e por dia (G A M).';-- =====================================================================================================
-- 20261006000270_reservas.sql — backend (adendo extras/ocorrências/reservas, seção R)
-- Reservas do dia: cadastro manual, importação de CSV (front) e ingestão genérica da Tagme (N8N, tipo de integração
-- 'tagme' ajustado em …0120). Telefone/e-mail são dados pessoais: só G A M (leitura lê por reservas_listar, sem eles).
-- Idempotente.
-- =====================================================================================================

create table if not exists public.reservas (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  integracao_id  uuid references public.integracoes (id) on delete set null,
  origem         text not null check (origem in ('tagme', 'manual', 'importacao')),
  id_externo     text,
  data           date not null,
  horario        time,
  nome_cliente   text not null check (btrim(nome_cliente) <> ''),
  pessoas        int not null default 1 check (pessoas between 1 and 500),
  status         text not null default 'confirmada'
                 check (status in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu')),
  area           text,
  mesa           text,
  observacao     text,
  telefone       text,
  email          text,
  criado_por     uuid references public.perfis (id) on delete set null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  importado_em   timestamptz,
  constraint reservas_externa_uk unique (empresa_id, origem, id_externo),
  constraint reservas_tagme_id check (origem <> 'tagme' or id_externo is not null)
);
create index if not exists reservas_empresa_dia_idx on public.reservas (empresa_id, data, horario);
create index if not exists reservas_integracao_idx on public.reservas (integracao_id);
create index if not exists reservas_criado_por_idx on public.reservas (criado_por);
comment on table public.reservas is
  '[api:leitura] Reservas (Tagme, manuais, importadas). Select direto só G A M; leitura via reservas_listar (sem telefone/e-mail).';

alter table public.reservas enable row level security;
drop policy if exists reservas_ler on public.reservas;
create policy reservas_ler on public.reservas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop trigger if exists tocar_atualizado_em on public.reservas;
create trigger tocar_atualizado_em before update on public.reservas
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ auxiliares
create or replace function public.reserva_validar(p_data date, p_nome text, p_pessoas int, p_status text)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if nullif(btrim(coalesce(p_nome, '')), '') is null then raise exception 'Informe o nome do cliente' using errcode = '22023'; end if;
  if p_pessoas is null or p_pessoas < 1 or p_pessoas > 500 then
    raise exception 'Número de pessoas inválido' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'Status de reserva inválido' using errcode = '22023';
  end if;
end $$;
comment on function public.reserva_validar(date, text, int, text) is '[interno] Validação de reserva (adendo R.3).';

create or replace function public.reserva_para_operar(p_reserva uuid)
returns public.reservas language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  select * into r from public.reservas where id = p_reserva;
  if not found then raise exception 'Reserva não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(r.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return r;
end $$;
comment on function public.reserva_para_operar(uuid) is '[interno] Reserva existente e operável (G A M).';

-- Data 'AAAA-MM-DD' ou 'DD/MM/AAAA' → date (null se inválida).
create or replace function public.reserva_ler_data(p_texto text)
returns date language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t ~ '^\d{4}-\d{2}-\d{2}$' then return to_date(t, 'YYYY-MM-DD')::date
    + case when to_char(to_date(t, 'YYYY-MM-DD'), 'YYYY-MM-DD') = t then 0 else null end;
  elsif t ~ '^\d{2}/\d{2}/\d{4}$' then return to_date(t, 'DD/MM/YYYY')::date
    + case when to_char(to_date(t, 'DD/MM/YYYY'), 'DD/MM/YYYY') = t then 0 else null end;
  end if;
  return null;
exception when others then return null;
end $$;
comment on function public.reserva_ler_data(text) is '[interno] Lê data AAAA-MM-DD ou DD/MM/AAAA.';

-- Horário 'HH:MM' ou 'HH:MM:SS' → time. Vazio → null; inválido → exceção 'horário inválido'.
create or replace function public.reserva_ler_horario(p_texto text)
returns time language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t = '' then return null; end if;
  if t !~ '^([01]?\d|2[0-3]):[0-5]\d(:[0-5]\d)?$' then raise exception 'horário inválido'; end if;
  return t::time;
end $$;
comment on function public.reserva_ler_horario(text) is '[interno] Lê horário HH:MM[:SS].';

commit;
select 'parte 14 de 21 instalada' as resultado;

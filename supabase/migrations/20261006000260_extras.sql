-- =====================================================================================================
-- 20261006000260_extras.sql — backend (adendo extras/ocorrências/reservas, seção E)
-- Aba Extras: pontos extras de comissão (tabela em …0220), valor padrão de diária, diárias (funcionário ou avulso)
-- e gastos totais por período. Valores: só G A M. Idempotente.
-- =====================================================================================================

-- ================================================================ pontos extras (tabela em …0220)
drop trigger if exists a_empresa on public.comissao_pontos_extras;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.comissao_pontos_extras
  for each row execute function public.ponto_empresa_do_funcionario();

create or replace function public.comissao_periodo_fechado(p_empresa uuid, p_data date)
returns boolean language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from public.comissao_fechamentos f
                  where f.empresa_id = p_empresa and f.status = 'fechado' and p_data between f.data_inicio and f.data_fim)
$$;
comment on function public.comissao_periodo_fechado(uuid, date) is '[interno] A data cai num fechamento de comissão fechado?';

create or replace function public.comissao_extra_lancar(p_funcionario uuid, p_data date, p_pontos numeric, p_motivo text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios; v_id uuid;
begin
  f := public.funcionario_para_operar(p_funcionario);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if p_pontos is null or p_pontos <= 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2) then
    raise exception 'Pontos extras inválidos' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if public.comissao_periodo_fechado(f.empresa_id, p_data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
  insert into public.comissao_pontos_extras (empresa_id, funcionario_id, data, pontos, motivo, criado_por, criado_por_nome)
  values (f.empresa_id, f.id, p_data, p_pontos, btrim(p_motivo), public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.comissao_extra_lancar(uuid, date, numeric, text) is
  '[api] Lança pontos extras de comissão para o funcionário numa data (G A M).';

create or replace function public.comissao_extra_excluir(p_extra uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.comissao_pontos_extras;
begin
  select * into x from public.comissao_pontos_extras where id = p_extra;
  if not found then raise exception 'Lançamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(x.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if public.comissao_periodo_fechado(x.empresa_id, x.data) then
    raise exception 'Período de comissão já fechado' using errcode = '22023';
  end if;
  delete from public.comissao_pontos_extras where id = x.id;
end $$;
comment on function public.comissao_extra_excluir(uuid) is '[api] Exclui um lançamento de pontos extras (G A M).';

create or replace function public.comissao_extras_listar(p_inicio date, p_fim date, p_funcionario uuid default null,
                                                         p_empresa uuid default null)
returns table (id uuid, funcionario_id uuid, funcionario_nome text, cargo text, data date, pontos numeric, motivo text,
               criado_por_nome text, criado_em timestamptz, fechado boolean)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select x.id, x.funcionario_id, f.nome, f.cargo, x.data, x.pontos, x.motivo, x.criado_por_nome, x.criado_em,
         public.comissao_periodo_fechado(x.empresa_id, x.data)
    from public.comissao_pontos_extras x
    join public.funcionarios f on f.id = x.funcionario_id
   where x.empresa_id = v_empresa and x.data between p_inicio and p_fim
     and (p_funcionario is null or x.funcionario_id = p_funcionario)
   order by x.data desc, x.criado_em desc, x.id;
end $$;
comment on function public.comissao_extras_listar(date, date, uuid, uuid) is '[api] Pontos extras lançados no período (G A M).';

-- ================================================================ valor padrão da diária
create table if not exists public.funcionario_valores_diaria (
  funcionario_id         uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  valor_diaria_centavos  bigint not null check (valor_diaria_centavos between 0 and 100000000),
  atualizado_por         uuid references public.perfis (id) on delete set null,
  atualizado_em          timestamptz not null default now()
);
create index if not exists funcionario_valores_diaria_empresa_idx on public.funcionario_valores_diaria (empresa_id);
create index if not exists funcionario_valores_diaria_atualizado_por_idx on public.funcionario_valores_diaria (atualizado_por);
comment on table public.funcionario_valores_diaria is
  '[api:leitura] Valor padrão da diária do funcionário (fora de funcionarios: a leitura não vê valores).';

-- ================================================================ diárias
create table if not exists public.diarias (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid references public.funcionarios (id) on delete set null,
  pessoa_nome      text not null check (btrim(pessoa_nome) <> ''),
  data             date not null,
  funcao           text,
  valor_centavos   bigint not null check (valor_centavos between 0 and 100000000),
  observacao       text,
  pago             boolean not null default false,
  pago_em          date,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint diarias_pagamento check (pago or pago_em is null)
);
create index if not exists diarias_empresa_idx on public.diarias (empresa_id, data);
create index if not exists diarias_funcionario_idx on public.diarias (funcionario_id, data);
create index if not exists diarias_criado_por_idx on public.diarias (criado_por);
comment on table public.diarias is '[api:leitura] Diárias pagas a funcionários ou avulsos (freelancers). Só G A M.';

alter table public.funcionario_valores_diaria enable row level security;
alter table public.diarias enable row level security;
drop policy if exists funcionario_valores_diaria_ler on public.funcionario_valores_diaria;
create policy funcionario_valores_diaria_ler on public.funcionario_valores_diaria for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists diarias_ler on public.diarias;
create policy diarias_ler on public.diarias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop trigger if exists a_empresa on public.funcionario_valores_diaria;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.funcionario_valores_diaria
  for each row execute function public.ponto_empresa_do_funcionario();

-- diária: com funcionário, empresa_id dele (funcionário de outra empresa = erro); sem funcionário, mantém a informada.
create or replace function public.diarias_antes_gravar()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if new.funcionario_id is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  end if;
  if tg_op = 'UPDATE' then
    if new.funcionario_id is null and old.funcionario_id is not null and new.empresa_id is distinct from old.empresa_id then
      new.empresa_id := old.empresa_id;
    end if;
    new.atualizado_em := now();
  end if;
  return new;
end $$;
comment on function public.diarias_antes_gravar() is '[interno] Gatilho de diarias: empresa do funcionário; atualizado_em.';
drop trigger if exists a_antes on public.diarias;
create trigger a_antes before insert or update on public.diarias
  for each row execute function public.diarias_antes_gravar();

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

-- Normaliza e valida os campos de uma diária (adendo E.2).
create or replace function public.diaria_preparar(p_empresa uuid, p_data date, p_funcionario uuid, p_pessoa_nome text,
                                                  p_funcao text, p_valor_centavos bigint, p_pago boolean, p_pago_em date,
                                                  out empresa_id uuid, out funcionario_id uuid, out pessoa_nome text,
                                                  out funcao text, out valor_centavos bigint, out pago boolean, out pago_em date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios; v_hoje date;
begin
  empresa_id := p_empresa;
  if p_funcionario is not null then
    f := public.funcionario_para_operar(p_funcionario);
    if p_empresa is not null and f.empresa_id <> p_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    empresa_id := f.empresa_id;
    funcionario_id := f.id;
    pessoa_nome := f.nome;
    funcao := coalesce(nullif(btrim(p_funcao), ''), f.cargo);
    valor_centavos := coalesce(p_valor_centavos,
                               (select v.valor_diaria_centavos from public.funcionario_valores_diaria v where v.funcionario_id = f.id));
  else
    pessoa_nome := nullif(btrim(coalesce(p_pessoa_nome, '')), '');
    if pessoa_nome is null then raise exception 'Informe o funcionário ou o nome' using errcode = '22023'; end if;
    funcao := nullif(btrim(p_funcao), '');
    valor_centavos := p_valor_centavos;
  end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.dia_de_trabalho(public.agora(), empresa_id);
  if p_data < v_hoje - 366 or p_data > v_hoje + 62 then raise exception 'Data fora do limite' using errcode = '22023'; end if;
  if valor_centavos is null then raise exception 'Informe o valor da diária' using errcode = '22023'; end if;
  if valor_centavos < 0 or valor_centavos > 100000000 then raise exception 'Valor inválido' using errcode = '22023'; end if;
  pago := coalesce(p_pago, false);
  pago_em := case when pago then coalesce(p_pago_em, v_hoje) end;
end $$;
comment on function public.diaria_preparar(uuid, date, uuid, text, text, bigint, boolean, date) is
  '[interno] Validação/normalização de diária (adendo E.2).';

create or replace function public.diaria_lancar(p_data date, p_funcionario uuid default null, p_pessoa_nome text default null,
                                                p_funcao text default null, p_valor_centavos bigint default null,
                                                p_observacao text default null, p_pago boolean default false,
                                                p_pago_em date default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v record; v_empresa uuid; v_id uuid;
begin
  if p_funcionario is null then
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  else
    v_empresa := p_empresa;
  end if;
  select * into v from public.diaria_preparar(v_empresa, p_data, p_funcionario, p_pessoa_nome, p_funcao, p_valor_centavos,
                                              p_pago, p_pago_em);
  insert into public.diarias (empresa_id, funcionario_id, pessoa_nome, data, funcao, valor_centavos, observacao, pago, pago_em,
                              criado_por, criado_por_nome)
  values (v.empresa_id, v.funcionario_id, v.pessoa_nome, p_data, v.funcao, v.valor_centavos, nullif(btrim(p_observacao), ''),
          v.pago, v.pago_em, public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.diaria_lancar(date, uuid, text, text, bigint, text, boolean, date, uuid) is
  '[api] Lança uma diária (funcionário ou avulso) (G A M).';

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

create or replace function public.diaria_atualizar(p_diaria uuid, p_data date, p_funcionario uuid, p_pessoa_nome text,
                                                   p_funcao text, p_valor_centavos bigint, p_observacao text,
                                                   p_pago boolean, p_pago_em date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d public.diarias; v record;
begin
  d := public.diaria_para_operar(p_diaria);
  select * into v from public.diaria_preparar(d.empresa_id, p_data, p_funcionario, p_pessoa_nome, p_funcao, p_valor_centavos,
                                              p_pago, p_pago_em);
  update public.diarias
     set funcionario_id = v.funcionario_id, pessoa_nome = v.pessoa_nome, data = p_data, funcao = v.funcao,
         valor_centavos = v.valor_centavos, observacao = nullif(btrim(p_observacao), ''), pago = v.pago, pago_em = v.pago_em
   where id = d.id;
end $$;
comment on function public.diaria_atualizar(uuid, date, uuid, text, text, bigint, text, boolean, date) is
  '[api] Substitui os dados de uma diária (G A M).';

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
  delete from public.diarias where id = d.id;
end $$;
comment on function public.diaria_excluir(uuid) is '[api] Exclui uma diária (G A M).';

create or replace function public.diarias_listar(p_inicio date, p_fim date, p_funcionario uuid default null,
                                                 p_pago boolean default null, p_empresa uuid default null)
returns table (id uuid, data date, funcionario_id uuid, pessoa_nome text, avulso boolean, funcao text, valor_centavos bigint,
               observacao text, pago boolean, pago_em date, criado_por_nome text, criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select d.id, d.data, d.funcionario_id, coalesce(f.nome, d.pessoa_nome), d.funcionario_id is null, d.funcao, d.valor_centavos,
         d.observacao, d.pago, d.pago_em, d.criado_por_nome, d.criado_em
    from public.diarias d
    left join public.funcionarios f on f.id = d.funcionario_id
   where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
     and (p_funcionario is null or d.funcionario_id = p_funcionario)
     and (p_pago is null or d.pago = p_pago)
   order by d.data desc, coalesce(f.nome, d.pessoa_nome), d.criado_em, d.id;
end $$;
comment on function public.diarias_listar(date, date, uuid, boolean, uuid) is '[api] Diárias do período (G A M).';

-- ================================================================ gastos por período (adendo E.3)
create or replace function public.gastos_periodo(p_inicio date, p_fim date, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return (
    with fech as (
      select fc.id, fc.titulo, fc.status, fc.data_inicio, fc.data_fim, fc.base_distribuivel_centavos
        from public.comissao_fechamentos fc
       where fc.empresa_id = v_empresa and fc.data_fim between p_inicio and p_fim
    ),
    lanc as (   -- uma linha por valor: (chave, funcionario_id, nome, avulso, data, coluna, valor)
      select case when d.funcionario_id is not null then 'f:' || d.funcionario_id
                  else 'a:' || lower(btrim(d.pessoa_nome)) end as chave,
             d.funcionario_id, coalesce(f.nome, d.pessoa_nome) as nome, d.funcionario_id is null as avulso, d.data,
             case when d.pago then 'diarias_pagas' else 'diarias_a_pagar' end as coluna, d.valor_centavos as valor, 1 as qtd
        from public.diarias d left join public.funcionarios f on f.id = d.funcionario_id
       where d.empresa_id = v_empresa and d.data between p_inicio and p_fim
      union all
      select case when it.funcionario_id is not null then 'f:' || it.funcionario_id
                  else 'a:' || lower(btrim(it.funcionario_nome)) end,
             it.funcionario_id, coalesce(f.nome, it.funcionario_nome), it.funcionario_id is null, fe.data_fim,
             case when fe.status = 'fechado' then 'comissoes_fechadas' else 'comissoes_previstas' end, it.valor_centavos, 0
        from fech fe join public.comissao_itens it on it.fechamento_id = fe.id
        left join public.funcionarios f on f.id = it.funcionario_id
    ),
    tot as (
      select coalesce(sum(valor) filter (where coluna = 'diarias_pagas'), 0) as dp,
             coalesce(sum(valor) filter (where coluna = 'diarias_a_pagar'), 0) as dap,
             coalesce(sum(qtd), 0) as qtd,
             coalesce(sum(valor) filter (where coluna = 'comissoes_fechadas'), 0) as cf,
             coalesce(sum(valor) filter (where coluna = 'comissoes_previstas'), 0) as cp
        from lanc
    ),
    pessoa as (
      select chave, (array_agg(funcionario_id) filter (where funcionario_id is not null))[1] as funcionario_id,
             (array_agg(nome order by (funcionario_id is null), nome))[1] as nome, bool_and(avulso) as avulso,
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
        from generate_series(p_inicio, p_fim, interval '1 day') g
        left join lanc l on l.data = g::date
       group by g
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'inicio', p_inicio, 'fim', p_fim,
      'totais', (select jsonb_build_object('diarias_pagas', dp, 'diarias_a_pagar', dap, 'diarias', dp + dap, 'diarias_qtd', qtd,
                                           'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                           'total', dp + dap + cf, 'total_com_previsto', dp + dap + cf + cp) from tot),
      'por_pessoa', coalesce((select jsonb_agg(jsonb_build_object(
                         'chave', chave, 'funcionario_id', funcionario_id, 'nome', nome, 'avulso', avulso, 'diarias_qtd', qtd,
                         'diarias_pagas', dp, 'diarias_a_pagar', dap, 'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                         'total', dp + dap + cf) order by dp + dap + cf desc, nome collate "C", chave)
                       from pessoa where qtd > 0 or dp + dap + cf + cp > 0), '[]'::jsonb),
      'por_dia', (select jsonb_agg(jsonb_build_object('data', data, 'diarias_pagas', dp, 'diarias_a_pagar', dap,
                                                      'comissoes_fechadas', cf, 'comissoes_previstas', cp,
                                                      'total', dp + dap + cf) order by data) from dia),
      'fechamentos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'titulo', titulo, 'status', status,
                                                                   'data_inicio', data_inicio, 'data_fim', data_fim,
                                                                   'base_distribuivel_centavos', base_distribuivel_centavos)
                                                order by data_fim, titulo, id) from fech), '[]'::jsonb))
  );
end $$;
comment on function public.gastos_periodo(date, date, uuid) is
  '[api] Gastos do período: diárias (pagas/a pagar) e comissões (fechadas/previstas), por pessoa e por dia (G A M).';

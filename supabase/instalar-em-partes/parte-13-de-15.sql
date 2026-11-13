-- Meu Dia de Gerente — instalação do banco, PARTE 13 DE 15.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000250_ocorrencias.sql, 20261006000260_extras.sql. Não edite à mão.

begin;
create or replace function public.ocorrencia_remover_anexo(p_anexo uuid)
returns text language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a public.funcionario_ocorrencia_anexos;
begin
  select * into a from public.funcionario_ocorrencia_anexos where id = p_anexo;
  if not found then raise exception 'Anexo não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  delete from public.funcionario_ocorrencia_anexos where id = a.id;
  return a.caminho;
end $$;
comment on function public.ocorrencia_remover_anexo(uuid) is '[api] Remove o registro do anexo e devolve o caminho no Storage (G A M).';

create or replace function public.ocorrencias_listar(p_funcionario uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios;
begin
  f := public.funcionario_para_operar(p_funcionario);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', o.id, 'funcionario_id', o.funcionario_id, 'tipo', o.tipo, 'data', o.data, 'motivo', o.motivo,
             'descricao', o.descricao, 'dias_suspensao', o.dias_suspensao, 'suspensao_inicio', o.suspensao_inicio,
             'suspensao_fim', o.suspensao_fim, 'criado_por_nome', o.criado_por_nome, 'criado_em', o.criado_em,
             'atualizado_em', o.atualizado_em,
             'anexos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'caminho', a.caminho,
                                                                     'nome_arquivo', a.nome_arquivo, 'criado_em', a.criado_em)
                                                  order by a.criado_em, a.id)
                                   from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id), '[]'::jsonb))
           order by o.data desc, o.criado_em desc, o.id)
      from public.funcionario_ocorrencias o where o.funcionario_id = f.id), '[]'::jsonb);
end $$;
comment on function public.ocorrencias_listar(uuid) is '[api] Ocorrências do funcionário com anexos (G A M).';

create or replace function public.ocorrencias_contagem(p_funcionario uuid default null, p_empresa uuid default null)
returns table (funcionario_id uuid, advertencias int, suspensoes int, dias_suspensao int, ultima_data date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    v_empresa := (public.funcionario_para_operar(p_funcionario)).empresa_id;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  return query
  select o.funcionario_id,
         (count(*) filter (where o.tipo = 'advertencia'))::int,
         (count(*) filter (where o.tipo = 'suspensao'))::int,
         coalesce(sum(o.dias_suspensao), 0)::int,
         max(o.data)
    from public.funcionario_ocorrencias o
   where o.empresa_id = v_empresa and (p_funcionario is null or o.funcionario_id = p_funcionario)
   group by o.funcionario_id
   order by o.funcionario_id;
end $$;
comment on function public.ocorrencias_contagem(uuid, uuid) is '[api] Contagem de ocorrências por funcionário (G A M).';

-- Resumo sem checagem (usado pelo painel, que já resolveu a empresa).
create or replace function public.ocorrencias_resumo_empresa(p_empresa uuid, p_dias int)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with h as (select public.dia_de_trabalho(public.agora(), p_empresa) as hoje),
       o as (select x.*, f.nome as funcionario_nome
               from public.funcionario_ocorrencias x
               join public.funcionarios f on f.id = x.funcionario_id, h
              where x.empresa_id = p_empresa and x.data between h.hoje - p_dias + 1 and h.hoje)
  select jsonb_build_object(
    'desde', h.hoje - p_dias + 1, 'ate', h.hoje,
    'advertencias', (select count(*) from o where o.tipo = 'advertencia'),
    'suspensoes', (select count(*) from o where o.tipo = 'suspensao'),
    'suspensos_hoje', (select count(distinct s.funcionario_id) from public.funcionario_ocorrencias s
                        where s.empresa_id = p_empresa and s.tipo = 'suspensao'
                          and h.hoje between s.suspensao_inicio and s.suspensao_fim),
    'recentes', coalesce((select jsonb_agg(jsonb_build_object(
                    'id', r.id, 'funcionario_id', r.funcionario_id, 'funcionario_nome', r.funcionario_nome, 'tipo', r.tipo,
                    'data', r.data, 'motivo', r.motivo, 'dias_suspensao', r.dias_suspensao,
                    'suspensao_inicio', r.suspensao_inicio, 'suspensao_fim', r.suspensao_fim)
                  order by r.data desc, r.criado_em desc, r.id)
                  from (select * from o order by o.data desc, o.criado_em desc, o.id limit 10) r), '[]'::jsonb))
  from h
$$;
comment on function public.ocorrencias_resumo_empresa(uuid, int) is '[interno] Resumo de ocorrências (adendo O.4), sem checagem.';

create or replace function public.ocorrencias_resumo(p_dias int default 30, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_dias is null or p_dias < 1 or p_dias > 366 then
    raise exception 'Período máximo de 366 dias' using errcode = '22023';
  end if;
  return public.ocorrencias_resumo_empresa(v_empresa, p_dias);
end $$;
comment on function public.ocorrencias_resumo(int, uuid) is '[api] Resumo das ocorrências dos últimos N dias (G A M).';-- =====================================================================================================
-- 20261006000260_extras.sql — backend (adendo extras/ocorrências/reservas, seção E — v2)
-- Extras = freelas/diaristas: cadastro (pontuação e diária padrão), dias trabalhados (diarias: extra com pontos
-- que entram no rateio diário da comissão, ou funcionário só como custo), valor padrão de diária do funcionário
-- e gastos totais por período. Valores e dados pessoais: só G A M. Idempotente; atualiza por cima da v1.
-- =====================================================================================================

-- ================================================================ v1 removida (pontos extras, diária avulsa)
drop function if exists public.comissao_extra_lancar(uuid, date, numeric, text);
drop function if exists public.comissao_extra_excluir(uuid);
drop function if exists public.comissao_extras_listar(date, date, uuid, uuid);
drop function if exists public.diaria_lancar(date, uuid, text, text, bigint, text, boolean, date, uuid);
drop function if exists public.diaria_atualizar(uuid, date, uuid, text, text, bigint, text, boolean, date);
drop function if exists public.diaria_preparar(uuid, date, uuid, text, text, bigint, boolean, date);
drop function if exists public.diarias_listar(date, date, uuid, boolean, uuid);

create or replace function public.comissao_periodo_fechado(p_empresa uuid, p_data date)
returns boolean language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from public.comissao_fechamentos f
                  where f.empresa_id = p_empresa and f.status = 'fechado' and p_data between f.data_inicio and f.data_fim)
$$;
comment on function public.comissao_periodo_fechado(uuid, date) is '[interno] A data cai num fechamento de comissão fechado?';

-- ================================================================ cadastro de extras (E.1)
create table if not exists public.extras (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  nome                   text not null check (btrim(nome) <> ''),
  funcao                 text,
  telefone               text,
  documento              text,
  pontos_padrao          numeric(8,2) not null default 0 check (pontos_padrao between 0 and 9999.99),
  valor_diaria_centavos  bigint check (valor_diaria_centavos between 0 and 100000000),
  ativo                  boolean not null default true,
  observacoes            text,
  criado_por             uuid references public.perfis (id) on delete set null,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);
create index if not exists extras_empresa_idx on public.extras (empresa_id, lower(nome));
create index if not exists extras_criado_por_idx on public.extras (criado_por);
comment on table public.extras is '[api:leitura] Extras (freelas/diaristas): pontuação e diária padrão, contato. Só G A M.';

alter table public.extras enable row level security;
drop policy if exists extras_ler on public.extras;
create policy extras_ler on public.extras for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop trigger if exists extras_tocar on public.extras;
create trigger extras_tocar before update on public.extras
  for each row execute function public.tocar_atualizado_em();

-- itens de comissão de extras (colunas em …0220)
alter table public.comissao_itens drop constraint if exists comissao_itens_extra_fk;
alter table public.comissao_itens add constraint comissao_itens_extra_fk
  foreign key (extra_id) references public.extras (id) on delete set null;
alter table public.comissao_itens drop constraint if exists comissao_itens_participante;
alter table public.comissao_itens add constraint comissao_itens_participante
  check ((tipo = 'funcionario' and extra_id is null) or (tipo = 'extra' and funcionario_id is null));

-- ================================================================ valor padrão da diária do funcionário
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

-- ================================================================ dias trabalhados / diárias (E.2)
create table if not exists public.diarias (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  tipo             text not null default 'funcionario',
  extra_id         uuid references public.extras (id),
  funcionario_id   uuid references public.funcionarios (id) on delete set null,
  pessoa_nome      text not null check (btrim(pessoa_nome) <> ''),
  data             date not null,
  funcao           text,
  pontos           numeric(8,2),
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

-- Atualização por cima da v1 (diarias sem "tipo"): cada diária avulsa vira um extra cadastrado (pontos 0).
do $$
declare r record; v_nome text; v_extra uuid;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'diarias' and column_name = 'tipo') then
    return;
  end if;
  alter table public.diarias add column tipo text not null default 'funcionario';
  alter table public.diarias add column extra_id uuid references public.extras (id);
  alter table public.diarias add column pontos numeric(8,2);
  for r in
    select d.id, d.empresa_id, btrim(d.pessoa_nome) as nome, d.funcao, d.valor_centavos,
           row_number() over (partition by d.empresa_id, lower(btrim(d.pessoa_nome)), d.data order by d.criado_em, d.id) as rn
      from public.diarias d
     where d.funcionario_id is null
     order by d.empresa_id, d.data desc, d.criado_em desc, d.id
  loop
    v_nome := r.nome || case when r.rn > 1 then ' (' || r.rn || ')' else '' end;
    v_extra := null;
    select x.id into v_extra from public.extras x
     where x.empresa_id = r.empresa_id and lower(x.nome) = lower(v_nome) order by x.criado_em, x.id limit 1;
    if v_extra is null then
      insert into public.extras (empresa_id, nome, funcao, pontos_padrao, valor_diaria_centavos, observacoes)
      values (r.empresa_id, v_nome, r.funcao, 0, r.valor_centavos, 'Cadastrado automaticamente a partir de diária avulsa.')
      returning id into v_extra;
    end if;
    update public.diarias set tipo = 'extra', extra_id = v_extra, pontos = 0 where id = r.id;
  end loop;
end $$;

alter table public.diarias add column if not exists tipo text not null default 'funcionario';
alter table public.diarias add column if not exists extra_id uuid references public.extras (id);
alter table public.diarias add column if not exists pontos numeric(8,2);
alter table public.diarias drop constraint if exists diarias_tipo_check;
alter table public.diarias add constraint diarias_tipo_check check (tipo in ('extra', 'funcionario'));
alter table public.diarias drop constraint if exists diarias_pontos_check;
alter table public.diarias add constraint diarias_pontos_check check (pontos between 0 and 9999.99);
alter table public.diarias drop constraint if exists diarias_participante;
alter table public.diarias add constraint diarias_participante check (
  (tipo = 'extra' and extra_id is not null and funcionario_id is null and pontos is not null)
  or (tipo = 'funcionario' and extra_id is null and pontos is null));
create index if not exists diarias_empresa_idx on public.diarias (empresa_id, data);
create index if not exists diarias_funcionario_idx on public.diarias (funcionario_id, data);
create unique index if not exists diarias_extra_dia_uidx on public.diarias (extra_id, data) where extra_id is not null;
create index if not exists diarias_extra_idx on public.diarias (extra_id);
create index if not exists diarias_criado_por_idx on public.diarias (criado_por);
comment on table public.diarias is
  '[api:leitura] Dias trabalhados: de extra (pontos entram na comissão do dia) ou de funcionário (só custo). Só G A M.';

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

-- diária: empresa_id do extra ou do funcionário (divergente = erro); funcionário excluído mantém a empresa.
create or replace function public.diarias_antes_gravar()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if new.extra_id is not null then
    select x.empresa_id into v_empresa from public.extras x where x.id = new.extra_id;
    if v_empresa is null then raise exception 'Extra não encontrado' using errcode = 'P0002'; end if;
    if new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Extra de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  elsif new.funcionario_id is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  end if;
  if tg_op = 'UPDATE' then
    if new.funcionario_id is null and new.extra_id is null and new.empresa_id is distinct from old.empresa_id then
      new.empresa_id := old.empresa_id;
    end if;
    new.atualizado_em := now();
  end if;
  return new;
end $$;
comment on function public.diarias_antes_gravar() is '[interno] Gatilho de diarias: empresa do extra/funcionário; atualizado_em.';
drop trigger if exists a_antes on public.diarias;
create trigger a_antes before insert or update on public.diarias
  for each row execute function public.diarias_antes_gravar();

-- ================================================================ RPCs do cadastro de extras
create or replace function public.extra_para_operar(p_extra uuid)
returns public.extras language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  select * into x from public.extras where id = p_extra;
  if not found then raise exception 'Extra não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(x.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return x;
end $$;
comment on function public.extra_para_operar(uuid) is '[interno] Extra existente e operável (G A M).';

create or replace function public.extra_validar(p_nome text, p_pontos numeric, p_valor bigint)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if nullif(btrim(coalesce(p_nome, '')), '') is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  if p_pontos is null or p_pontos < 0 or p_pontos > 9999.99 or p_pontos <> round(p_pontos, 2) then
    raise exception 'Pontos inválidos' using errcode = '22023';
  end if;
  if p_valor is not null and (p_valor < 0 or p_valor > 100000000) then raise exception 'Valor inválido' using errcode = '22023'; end if;
end $$;
comment on function public.extra_validar(text, numeric, bigint) is '[interno] Validação do cadastro de extra (E.1).';

create or replace function public.extra_criar(p_nome text, p_funcao text default null, p_pontos_padrao numeric default 0,
                                              p_valor_diaria_centavos bigint default null, p_telefone text default null,
                                              p_documento text default null, p_observacoes text default null,
                                              p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.extra_validar(p_nome, coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos);
  insert into public.extras (empresa_id, nome, funcao, telefone, documento, pontos_padrao, valor_diaria_centavos, observacoes, criado_por)
  values (v_empresa, btrim(p_nome), nullif(btrim(p_funcao), ''), nullif(btrim(p_telefone), ''), nullif(btrim(p_documento), ''),
          coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos, nullif(btrim(p_observacoes), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.extra_criar(text, text, numeric, bigint, text, text, text, uuid) is '[api] Cadastra um extra (freela) (G A M).';

create or replace function public.extra_atualizar(p_extra uuid, p_nome text, p_funcao text, p_pontos_padrao numeric,
                                                  p_valor_diaria_centavos bigint, p_telefone text, p_documento text,
                                                  p_ativo boolean, p_observacoes text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  x := public.extra_para_operar(p_extra);
  perform public.extra_validar(p_nome, coalesce(p_pontos_padrao, 0), p_valor_diaria_centavos);
  update public.extras
     set nome = btrim(p_nome), funcao = nullif(btrim(p_funcao), ''), telefone = nullif(btrim(p_telefone), ''),
         documento = nullif(btrim(p_documento), ''), pontos_padrao = coalesce(p_pontos_padrao, 0),
         valor_diaria_centavos = p_valor_diaria_centavos, ativo = coalesce(p_ativo, true),
         observacoes = nullif(btrim(p_observacoes), '')
   where id = x.id;
end $$;
comment on function public.extra_atualizar(uuid, text, text, numeric, bigint, text, text, boolean, text) is
  '[api] Substitui os dados do cadastro de um extra (G A M).';

create or replace function public.extra_excluir(p_extra uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x public.extras;
begin
  x := public.extra_para_operar(p_extra);
  if exists (select 1 from public.diarias d where d.extra_id = x.id) then
    raise exception 'Extra com dias lançados: desative em vez de excluir' using errcode = '22023';
  end if;
  delete from public.extras where id = x.id;
end $$;
comment on function public.extra_excluir(uuid) is '[api] Exclui um extra sem dias lançados (G A M).';

create or replace function public.extras_listar(p_incluir_inativos boolean default false, p_empresa uuid default null)
returns table (id uuid, nome text, funcao text, telefone text, documento text, pontos_padrao numeric, valor_diaria_centavos bigint,
               ativo boolean, observacoes text, dias_lancados int, ultimo_dia date, criado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  return query
  select x.id, x.nome, x.funcao, x.telefone, x.documento, x.pontos_padrao, x.valor_diaria_centavos, x.ativo, x.observacoes,
         coalesce(l.qtd, 0)::int, l.ultimo, x.criado_em
    from public.extras x
    left join lateral (select count(*) as qtd, max(d.data) as ultimo from public.diarias d where d.extra_id = x.id) l on true
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

commit;
select 'parte 13 de 15 instalada' as resultado;

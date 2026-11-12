-- Meu Dia de Gerente — instalação do banco, PARTE 12 DE 14.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000250_ocorrencias.sql, 20261006000260_extras.sql. Não edite à mão.

begin;
-- ================================================================ auxiliares
create or replace function public.ocorrencia_para_operar(p_ocorrencia uuid)
returns public.funcionario_ocorrencias language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias;
begin
  select * into o from public.funcionario_ocorrencias where id = p_ocorrencia;
  if not found then raise exception 'Ocorrência não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(o.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return o;
end $$;
comment on function public.ocorrencia_para_operar(uuid) is '[interno] Ocorrência existente e operável (G A M).';

-- Valida os campos e devolve (tipo, dias, início, fim) normalizados.
create or replace function public.ocorrencia_validar(p_empresa uuid, p_tipo text, p_data date, p_motivo text,
                                                     p_dias int, p_inicio date,
                                                     out tipo text, out dias int, out inicio date, out fim date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_tipo is null or p_tipo not in ('advertencia', 'suspensao') then
    raise exception 'Tipo de ocorrência inválido' using errcode = '22023';
  end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if p_data > public.dia_de_trabalho(public.agora(), p_empresa) then
    raise exception 'Data no futuro' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'Informe o motivo' using errcode = '22023';
  end if;
  tipo := p_tipo;
  if p_tipo = 'advertencia' then
    return;
  end if;
  if p_dias is null or p_dias < 1 or p_dias > 30 then
    raise exception 'Dias de suspensão inválidos (1 a 30)' using errcode = '22023';
  end if;
  inicio := coalesce(p_inicio, p_data);
  if inicio < p_data or inicio > p_data + 60 then
    raise exception 'Início da suspensão inválido' using errcode = '22023';
  end if;
  dias := p_dias;
  fim := inicio + p_dias - 1;
end $$;
comment on function public.ocorrencia_validar(uuid, text, date, text, int, date) is '[interno] Validação de ocorrência (adendo O.3).';

-- Ressincroniza os abonos 'suspensao' de uma ocorrência e reapura os dias afetados (antigos e novos).
create or replace function public.ocorrencia_sincronizar_abonos(p_ocorrencia uuid, p_antigo_inicio date, p_antigo_fim date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v_existe boolean; v_conflito date; v_ini date; v_fim date;
begin
  select * into o from public.funcionario_ocorrencias where id = p_ocorrencia;
  v_existe := found;
  delete from public.ponto_abonos where ocorrencia_id = p_ocorrencia;
  if v_existe and o.tipo = 'suspensao' then
    select a.data into v_conflito
      from public.ponto_abonos a
     where a.funcionario_id = o.funcionario_id and a.data between o.suspensao_inicio and o.suspensao_fim
     order by a.data limit 1;
    if v_conflito is not null then
      raise exception 'Já existe abono para o funcionário em %', to_char(v_conflito, 'DD/MM/YYYY') using errcode = '22023';
    end if;
    insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por, ocorrencia_id)
    select o.empresa_id, o.funcionario_id, g::date, 'suspensao', left('Suspensão: ' || o.motivo, 500), public.meu_perfil_id(), o.id
      from generate_series(o.suspensao_inicio, o.suspensao_fim, interval '1 day') g;
  end if;
  v_ini := least(p_antigo_inicio, case when o.tipo = 'suspensao' then o.suspensao_inicio end);
  v_fim := greatest(p_antigo_fim, case when o.tipo = 'suspensao' then o.suspensao_fim end);
  if v_ini is not null and o.funcionario_id is not null then
    perform public.ponto_apurar(o.funcionario_id, v_ini, v_fim);
  end if;
end $$;
comment on function public.ocorrencia_sincronizar_abonos(uuid, date, date) is
  '[interno] Abonos ''suspensao'' da ocorrência (um por dia) + reapuração (adendo O.3).';

-- ================================================================ RPCs
create or replace function public.ocorrencia_criar(p_funcionario uuid, p_tipo text, p_data date, p_motivo text,
                                                   p_descricao text default null, p_dias_suspensao int default null,
                                                   p_suspensao_inicio date default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare f public.funcionarios; v record; v_id uuid;
begin
  f := public.funcionario_para_operar(p_funcionario);
  select * into v from public.ocorrencia_validar(f.empresa_id, p_tipo, p_data, p_motivo, p_dias_suspensao, p_suspensao_inicio);
  insert into public.funcionario_ocorrencias (empresa_id, funcionario_id, tipo, data, motivo, descricao, dias_suspensao,
                                              suspensao_inicio, suspensao_fim, criado_por, criado_por_nome)
  values (f.empresa_id, f.id, v.tipo, p_data, btrim(p_motivo), nullif(btrim(p_descricao), ''), v.dias, v.inicio, v.fim,
          public.meu_perfil_id(), public.ponto_nome_autor())
  returning id into v_id;
  perform public.ocorrencia_sincronizar_abonos(v_id, null, null);
  return v_id;
end $$;
comment on function public.ocorrencia_criar(uuid, text, date, text, text, int, date) is
  '[api] Registra advertência/suspensão do funcionário (G A M). Suspensão gera abonos e reapura.';

create or replace function public.ocorrencia_atualizar(p_ocorrencia uuid, p_tipo text, p_data date, p_motivo text,
                                                       p_descricao text, p_dias_suspensao int default null,
                                                       p_suspensao_inicio date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v record;
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  select * into v from public.ocorrencia_validar(o.empresa_id, p_tipo, p_data, p_motivo, p_dias_suspensao, p_suspensao_inicio);
  update public.funcionario_ocorrencias
     set tipo = v.tipo, data = p_data, motivo = btrim(p_motivo), descricao = nullif(btrim(p_descricao), ''),
         dias_suspensao = v.dias, suspensao_inicio = v.inicio, suspensao_fim = v.fim
   where id = o.id;
  perform public.ocorrencia_sincronizar_abonos(o.id, o.suspensao_inicio, o.suspensao_fim);
end $$;
comment on function public.ocorrencia_atualizar(uuid, text, date, text, text, int, date) is
  '[api] Edita uma ocorrência (G A M); ressincroniza abonos de suspensão e reapura.';

create or replace function public.ocorrencia_excluir(p_ocorrencia uuid)
returns text[] language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v_caminhos text[];
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  select coalesce(array_agg(a.caminho order by a.criado_em, a.id), array[]::text[]) into v_caminhos
    from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id;
  delete from public.funcionario_ocorrencias where id = o.id;     -- anexos e abonos em cascata
  if o.tipo = 'suspensao' then
    perform public.ponto_apurar(o.funcionario_id, o.suspensao_inicio, o.suspensao_fim);
  end if;
  return v_caminhos;
end $$;
comment on function public.ocorrencia_excluir(uuid) is
  '[api] Exclui a ocorrência (G A M); devolve os caminhos dos anexos para remover do Storage.';

create or replace function public.ocorrencia_adicionar_anexo(p_ocorrencia uuid, p_caminho text, p_nome_arquivo text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare o public.funcionario_ocorrencias; v text := nullif(btrim(coalesce(p_caminho, '')), ''); v_existe boolean := true; v_id uuid;
begin
  o := public.ocorrencia_para_operar(p_ocorrencia);
  if v is null or position(o.empresa_id::text || '/ocorrencias/' || o.id::text || '/' in v) <> 1
     or v !~* ('^' || o.empresa_id::text || '/ocorrencias/' || o.id::text || '/[^/]+\.(jpg|jpeg|png|webp|pdf)$') then
    raise exception 'Anexo inválido' using errcode = '22023';
  end if;
  if (select count(*) from public.funcionario_ocorrencia_anexos a where a.ocorrencia_id = o.id) >= 10 then
    raise exception 'Limite de 10 anexos por ocorrência' using errcode = '22023';
  end if;
  if exists (select 1 from public.funcionario_ocorrencia_anexos a where a.caminho = v) then
    raise exception 'Anexo já registrado' using errcode = '23505';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)'
      into v_existe using 'funcionarios-documentos', v;
  end if;
  if not v_existe then
    raise exception 'Anexo não encontrado no armazenamento' using errcode = 'P0002';
  end if;
  insert into public.funcionario_ocorrencia_anexos (empresa_id, ocorrencia_id, caminho, nome_arquivo, criado_por)
  values (o.empresa_id, o.id, v, nullif(btrim(p_nome_arquivo), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.ocorrencia_adicionar_anexo(uuid, text, text) is
  '[api] Registra um anexo já enviado ao Storage (bucket funcionarios-documentos) (G A M).';

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

commit;
select 'parte 12 de 14 instalada' as resultado;

-- =====================================================================================================
-- 20261006000280_escala.sql — backend (docs/CONTRATO-ADENDO-escala.md)
-- Escala rotativa 5x2 (modelo Macaw): setores, membros (funcionários cadastrados) com folgas da semana base, caminhos
-- de rodízio contínuo a partir de uma data-âncora (segunda-feira) + fase, ajustes por dia (folga/trabalha/férias/chegada),
-- troca de folgas, férias → abono 'ferias' (ponto_abonos.escala_ajuste_id) e reapuração do ponto (máx. 62 dias).
-- A integração com a apuração está em ponto_calcular_dia (…0200), que chama escala_status_ponto (definida aqui).
-- Idempotente.
-- =====================================================================================================

-- ================================================================ tabelas
create table if not exists public.escala_config (
  empresa_id     uuid primary key references public.empresas (id) on delete cascade,
  ancora         date not null check (extract(isodow from ancora) = 1),
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table public.escala_config is '[api:leitura] Escala rotativa: data-âncora (segunda, semana 0) e fase por empresa.';

create table if not exists public.escala_setores (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ordem          int  not null default 0,
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create unique index if not exists escala_setores_nome_uk on public.escala_setores (empresa_id, lower(btrim(nome)));
create index if not exists escala_setores_empresa_idx on public.escala_setores (empresa_id, ordem);
comment on table public.escala_setores is '[api:leitura] Setores da escala (Salão, Bar, Cozinha...).';

create table if not exists public.escala_membros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  setor_id        uuid not null references public.escala_setores (id) on delete cascade,
  funcionario_id  uuid not null unique references public.funcionarios (id) on delete cascade,
  folgas_base     smallint[] not null default '{}',
  chegada_padrao  time,
  caminho         smallint check (caminho between 1 and 20),
  posicao         smallint check (posicao between 1 and 99),
  ordem           int not null default 0,
  modelo_posicao  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint escala_membros_caminho check ((caminho is null) = (posicao is null)),
  constraint escala_membros_folgas check (folgas_base <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
                                          and coalesce(array_length(folgas_base, 1), 0) <= 6)
);
create index if not exists escala_membros_empresa_idx on public.escala_membros (empresa_id);
create index if not exists escala_membros_setor_idx on public.escala_membros (setor_id, ordem);
create unique index if not exists escala_membros_posicao_uk on public.escala_membros (setor_id, caminho, posicao)
  where caminho is not null;
create unique index if not exists escala_membros_modelo_uk on public.escala_membros (empresa_id, modelo_posicao)
  where modelo_posicao is not null;
comment on table public.escala_membros is
  '[api:leitura] Funcionários na escala: setor, folgas da semana base (0=SEG..6=DOM), chegada padrão, caminho/posição do rodízio.';

create table if not exists public.escala_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  membro_id        uuid not null references public.escala_membros (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  status           text check (status in ('trabalha', 'folga', 'ferias')),
  chegada          time,
  motivo           text,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (funcionario_id, data),
  constraint escala_ajustes_algo check (status is not null or chegada is not null)
);
create index if not exists escala_ajustes_empresa_idx on public.escala_ajustes (empresa_id, data);
create index if not exists escala_ajustes_membro_idx on public.escala_ajustes (membro_id);
create index if not exists escala_ajustes_criado_por_idx on public.escala_ajustes (criado_por);
comment on table public.escala_ajustes is
  '[api:leitura] Ajustes da escala por dia (status e/ou chegada). Só G A M leem a tabela; leitura vê pela escala_mes.';

-- abono de férias gerado pela escala (coluna criada em …0200)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ponto_abonos_escala_ajuste_fk') then
    alter table public.ponto_abonos add constraint ponto_abonos_escala_ajuste_fk
      foreign key (escala_ajuste_id) references public.escala_ajustes (id) on delete cascade;
  end if;
end $$;

-- ================================================================ RLS
alter table public.escala_config enable row level security;
alter table public.escala_setores enable row level security;
alter table public.escala_membros enable row level security;
alter table public.escala_ajustes enable row level security;
drop policy if exists escala_config_ler on public.escala_config;
create policy escala_config_ler on public.escala_config for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_setores_ler on public.escala_setores;
create policy escala_setores_ler on public.escala_setores for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_membros_ler on public.escala_membros;
create policy escala_membros_ler on public.escala_membros for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_ajustes_ler on public.escala_ajustes;
create policy escala_ajustes_ler on public.escala_ajustes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
create or replace function public.escala_setores_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.escala_setores_antes() is '[interno] Gatilho: setor com nome aparado e empresa imutável.';
drop trigger if exists a_antes on public.escala_setores;
create trigger a_antes before insert or update on public.escala_setores
  for each row execute function public.escala_setores_antes();

create or replace function public.escala_membros_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select s.empresa_id into v_empresa from public.escala_setores s where s.id = new.setor_id;
  if v_empresa is null then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  new.empresa_id := v_empresa;
  if not exists (select 1 from public.funcionarios f where f.id = new.funcionario_id and f.empresa_id = v_empresa) then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.escala_membros_antes() is '[interno] Gatilho: empresa do membro = do setor; funcionário da mesma empresa.';
drop trigger if exists a_antes on public.escala_membros;
create trigger a_antes before insert or update on public.escala_membros
  for each row execute function public.escala_membros_antes();

create or replace function public.escala_ajustes_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m record;
begin
  select x.empresa_id, x.funcionario_id into m from public.escala_membros x where x.id = new.membro_id;
  if m.empresa_id is null then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  new.empresa_id := m.empresa_id;
  new.funcionario_id := m.funcionario_id;
  return new;
end $$;
comment on function public.escala_ajustes_antes() is '[interno] Gatilho: empresa/funcionário do ajuste = do membro.';
drop trigger if exists a_antes on public.escala_ajustes;
create trigger a_antes before insert or update on public.escala_ajustes
  for each row execute function public.escala_ajustes_antes();

drop trigger if exists tocar_atualizado_em on public.escala_config;
create trigger tocar_atualizado_em before update on public.escala_config
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_setores;
create trigger tocar_atualizado_em before update on public.escala_setores
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_membros;
create trigger tocar_atualizado_em before update on public.escala_membros
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_ajustes;
create trigger tocar_atualizado_em before update on public.escala_ajustes
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ regra do rodízio (§S.2)
-- Membros com a posição k (0-based) e o tamanho n do caminho; p_setor restringe a um setor (usado pelo ponto).
create or replace function public.escala_membros_rodizio(p_empresa uuid, p_setor uuid default null)
returns table (id uuid, funcionario_id uuid, setor_id uuid, caminho smallint, posicao smallint, k int, n int,
               folgas_base smallint[], chegada_padrao time, fase_setor int, data_admissao date, data_desligamento date)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select m.id, m.funcionario_id, m.setor_id, m.caminho, m.posicao,
         (row_number() over (partition by m.setor_id, m.caminho order by m.posicao, m.id) - 1)::int,
         (count(*) over (partition by m.setor_id, m.caminho))::int,
         m.folgas_base, m.chegada_padrao, s.fase, f.data_admissao, f.data_desligamento
    from public.escala_membros m
    join public.escala_setores s on s.id = m.setor_id
    join public.funcionarios f on f.id = m.funcionario_id
   where m.empresa_id = p_empresa and (p_setor is null or m.setor_id = p_setor)
$$;
comment on function public.escala_membros_rodizio(uuid, uuid) is '[interno] Membros com posição (k) e tamanho (n) do caminho.';

-- Número da semana (w) do dia em relação à âncora.
create or replace function public.escala_semana_num(p_data date, p_ancora date)
returns int language sql immutable set search_path = public, extensions, pg_temp as $$
  select ((p_data - (extract(isodow from p_data)::int - 1)) - p_ancora) / 7
$$;
comment on function public.escala_semana_num(date, date) is '[interno] Semana do dia contada a partir da âncora (semana 0).';

-- Escala calculada (regra + ajustes) para o período; p_funcionario restringe a um funcionário.
create or replace function public.escala_calcular(p_empresa uuid, p_inicio date, p_fim date, p_funcionario uuid default null)
returns table (funcionario_id uuid, membro_id uuid, setor_id uuid, data date, status text, status_auto text, origem text,
               chegada time, ajustado boolean, ajuste_status text, ajuste_chegada time, motivo text)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with cfg as (select c.ancora, c.fase from public.escala_config c where c.empresa_id = p_empresa),
  mem as materialized (
    select r.* from public.escala_membros_rodizio(p_empresa,
             case when p_funcionario is not null
                  then (select x.setor_id from public.escala_membros x where x.funcionario_id = p_funcionario) end) r
     where p_funcionario is null
        or exists (select 1 from public.escala_membros x where x.funcionario_id = p_funcionario)
  ),
  base as (
    select b.*, g::date as d, cfg.ancora, cfg.fase as fase_emp
      from mem b cross join cfg cross join generate_series(p_inicio, p_fim, interval '1 day') g
     where p_funcionario is null or b.funcionario_id = p_funcionario
  ),
  calc as (
    select b.*,
           case when b.d < b.ancora or not public.ponto_no_vinculo(b.data_admissao, b.data_desligamento, b.d) then 'fora'
                when (extract(isodow from b.d)::int - 1)::smallint = any (alvo.folgas_base) then 'folga'
                else 'trabalha' end as st_auto
      from base b
      left join lateral (
        select a.folgas_base from mem a
         where (b.caminho is null and a.id = b.id)
            or (b.caminho is not null and a.setor_id = b.setor_id and a.caminho = b.caminho
                and a.k = (((b.k + public.escala_semana_num(b.d, b.ancora) + b.fase_emp + b.fase_setor) % b.n) + b.n) % b.n)
        limit 1
      ) alvo on true
  )
  select c.funcionario_id, c.id, c.setor_id, c.d,
         case when c.st_auto = 'fora' then 'fora' else coalesce(aj.status, c.st_auto) end,
         c.st_auto,
         case when c.st_auto <> 'fora' and aj.status is not null then 'ajuste' else 'auto' end,
         case when c.st_auto <> 'fora' and coalesce(aj.status, c.st_auto) = 'trabalha' then coalesce(aj.chegada, c.chegada_padrao) end,
         c.st_auto <> 'fora' and aj.id is not null,
         aj.status, aj.chegada, aj.motivo
    from calc c
    left join public.escala_ajustes aj on aj.funcionario_id = c.funcionario_id and aj.data = c.d
$$;
comment on function public.escala_calcular(uuid, date, date, uuid) is '[interno] Escala calculada (rodízio + ajustes) por funcionário × dia (§S.2).';

-- Usada por ponto_calcular_dia (…0200): status da escala no dia (null = fora da escala) e chegada.
create or replace function public.escala_status_ponto(p_funcionario uuid, p_data date, out status text, out chegada time)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; c record;
begin
  select m.empresa_id into v_empresa from public.escala_membros m where m.funcionario_id = p_funcionario;
  if v_empresa is null then return; end if;
  select * into c from public.escala_calcular(v_empresa, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then return; end if;
  status := c.status;
  chegada := c.chegada;
end $$;
comment on function public.escala_status_ponto(uuid, date) is '[interno] Status da escala no dia para a apuração (adendo escala §S.5).';

-- ================================================================ auxiliares
create or replace function public.escala_hoje(p_empresa uuid)
returns date language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select public.dia_de_trabalho(public.agora(), p_empresa)
$$;
comment on function public.escala_hoje(uuid) is '[interno] Dia de trabalho atual da empresa.';

-- Reapura os funcionários no período, limitado a [hoje − 61, hoje] (adendo §S.5).
create or replace function public.escala_reapurar(p_empresa uuid, p_funcionarios uuid[], p_inicio date default null,
                                                  p_fim date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date; v_ini date; v_fim date; v_f uuid;
begin
  if p_funcionarios is null then return; end if;
  v_hoje := public.escala_hoje(p_empresa);
  v_ini := greatest(coalesce(p_inicio, v_hoje - 61), v_hoje - 61);
  v_fim := least(coalesce(p_fim, v_hoje), v_hoje);
  if v_ini > v_fim then return; end if;
  for v_f in select distinct x from unnest(p_funcionarios) x where x is not null order by 1 loop
    perform public.ponto_apurar(v_f, v_ini, v_fim);
  end loop;
end $$;
comment on function public.escala_reapurar(uuid, uuid[], date, date) is '[interno] Reapura funcionários afetados pela escala (máx. 62 dias).';

create or replace function public.escala_funcionarios_dos_setores(p_setores uuid[])
returns uuid[] language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(array_agg(m.funcionario_id), '{}') from public.escala_membros m where m.setor_id = any (p_setores)
$$;
comment on function public.escala_funcionarios_dos_setores(uuid[]) is '[interno] Funcionários dos setores.';

-- Configuração da empresa (cria com âncora = segunda da semana atual, se não existir).
create or replace function public.escala_garantir_config(p_empresa uuid)
returns public.escala_config language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.escala_config; v_hoje date;
begin
  select * into c from public.escala_config where empresa_id = p_empresa;
  if found then return c; end if;
  v_hoje := public.escala_hoje(p_empresa);
  insert into public.escala_config (empresa_id, ancora, fase)
  values (p_empresa, v_hoje - (extract(isodow from v_hoje)::int - 1), 0)
  on conflict (empresa_id) do nothing;
  select * into c from public.escala_config where empresa_id = p_empresa;
  return c;
end $$;
comment on function public.escala_garantir_config(uuid) is '[interno] Garante a configuração da escala (âncora padrão = segunda atual).';

create or replace function public.escala_validar_fase(p_fase int)
returns int language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_fase is null then return 0; end if;
  if p_fase < -1000 or p_fase > 1000 then raise exception 'Fase inválida' using errcode = '22023'; end if;
  return p_fase;
end $$;
comment on function public.escala_validar_fase(int) is '[interno] Valida a fase (−1000..1000).';

create or replace function public.escala_validar_folgas(p_folgas smallint[])
returns smallint[] language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare v smallint[];
begin
  if p_folgas is null then return '{}'; end if;
  if exists (select 1 from unnest(p_folgas) x where x is null or x < 0 or x > 6) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v from unnest(p_folgas) x;
  if coalesce(array_length(v, 1), 0) > 6 or coalesce(array_length(v, 1), 0) <> coalesce(array_length(p_folgas, 1), 0) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  return v;
end $$;
comment on function public.escala_validar_folgas(smallint[]) is '[interno] Folgas da semana base: 0..6 sem repetição, até 6 dias; ordena.';

create or replace function public.escala_status_param(p_status text)
returns text language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_status is null or p_status in ('auto', 'automatico') then return null; end if;
  if p_status not in ('trabalha', 'folga', 'ferias') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  return p_status;
end $$;
comment on function public.escala_status_param(text) is '[interno] Status do ajuste: trabalha/folga/ferias; null ou auto = automático.';

create or replace function public.escala_setor_para_operar(p_setor uuid)
returns public.escala_setores language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(s.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return s;
end $$;
comment on function public.escala_setor_para_operar(uuid) is '[interno] Setor existente e operável (G A M).';

create or replace function public.escala_membro_para_operar(p_funcionario uuid)
returns public.escala_membros language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; m public.escala_membros;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  select * into m from public.escala_membros where funcionario_id = p_funcionario;
  if not found then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  return m;
end $$;
comment on function public.escala_membro_para_operar(uuid) is '[interno] Membro da escala operável (G A M).';

-- Grava (upsert por funcionário) um membro, sem reapurar. Retorna o id do membro.
create or replace function public.escala_gravar_membro(p_setor uuid, p_funcionario uuid, p_folgas smallint[], p_chegada time,
                                                       p_caminho smallint, p_posicao smallint, p_ordem int,
                                                       p_modelo_posicao text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_emp_f uuid; v_folgas smallint[]; v_pos smallint; v_ordem int; v_id uuid; v_atual public.escala_membros;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  select f.empresa_id into v_emp_f from public.funcionarios f where f.id = p_funcionario;
  if v_emp_f is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if v_emp_f <> s.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  v_folgas := public.escala_validar_folgas(p_folgas);
  if p_caminho is not null and (p_caminho < 1 or p_caminho > 20) then
    raise exception 'Caminho inválido' using errcode = '22023';
  end if;
  select * into v_atual from public.escala_membros where funcionario_id = p_funcionario;
  v_pos := null;
  if p_caminho is not null then
    v_pos := p_posicao;
    if v_pos is null then
      select coalesce(max(m.posicao), 0) + 1 into v_pos from public.escala_membros m
       where m.setor_id = p_setor and m.caminho = p_caminho and m.funcionario_id <> p_funcionario;
    end if;
    if v_pos < 1 or v_pos > 99 then raise exception 'Posição inválida' using errcode = '22023'; end if;
    if exists (select 1 from public.escala_membros m
                where m.setor_id = p_setor and m.caminho = p_caminho and m.posicao = v_pos and m.funcionario_id <> p_funcionario) then
      raise exception 'Posição já ocupada no caminho' using errcode = '23505';
    end if;
  end if;
  v_ordem := p_ordem;
  if v_ordem is null then
    if v_atual.id is not null and v_atual.setor_id = p_setor then
      v_ordem := v_atual.ordem;
    else
      select coalesce(max(m.ordem), 0) + 1 into v_ordem from public.escala_membros m where m.setor_id = p_setor;
    end if;
  end if;
  insert into public.escala_membros as m (empresa_id, setor_id, funcionario_id, folgas_base, chegada_padrao, caminho, posicao,
                                          ordem, modelo_posicao)
  values (s.empresa_id, p_setor, p_funcionario, v_folgas, p_chegada, p_caminho, v_pos, v_ordem, p_modelo_posicao)
  on conflict (funcionario_id) do update set
    setor_id = excluded.setor_id, folgas_base = excluded.folgas_base, chegada_padrao = excluded.chegada_padrao,
    caminho = excluded.caminho, posicao = excluded.posicao, ordem = excluded.ordem,
    modelo_posicao = coalesce(excluded.modelo_posicao, m.modelo_posicao)
  returning m.id into v_id;
  return v_id;
end $$;
comment on function public.escala_gravar_membro(uuid, uuid, smallint[], time, smallint, smallint, int, text) is
  '[interno] Grava membro da escala (validações §S.7 nº 4), sem reapurar.';

-- Abono 'ferias' do ajuste (§S.4).
create or replace function public.escala_sincronizar_abono(p_ajuste uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare aj public.escala_ajustes; v_motivo text;
begin
  select * into aj from public.escala_ajustes where id = p_ajuste;
  if not found then return; end if;
  if aj.status is distinct from 'ferias' then
    delete from public.ponto_abonos where escala_ajuste_id = aj.id;
    return;
  end if;
  v_motivo := left(case when aj.motivo is null then 'Férias (escala)' else 'Férias (escala): ' || aj.motivo end, 500);
  if exists (select 1 from public.ponto_abonos a where a.escala_ajuste_id = aj.id) then
    update public.ponto_abonos set motivo = v_motivo where escala_ajuste_id = aj.id and motivo is distinct from v_motivo;
    return;
  end if;
  if exists (select 1 from public.ponto_abonos a where a.funcionario_id = aj.funcionario_id and a.data = aj.data) then
    raise exception 'Já existe abono para o funcionário em %', to_char(aj.data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por, escala_ajuste_id)
  values (aj.empresa_id, aj.funcionario_id, aj.data, 'ferias', v_motivo, public.meu_perfil_id(), aj.id);
end $$;
comment on function public.escala_sincronizar_abono(uuid) is '[interno] Mantém o abono ''ferias'' de um ajuste de férias da escala.';

-- Grava o estado de um dia (status null = automático; chegada null = padrão; os dois null apagam o ajuste). Sem reapurar.
create or replace function public.escala_gravar_dia(p_membro uuid, p_data date, p_status text, p_chegada time, p_motivo text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_id uuid;
begin
  select * into m from public.escala_membros where id = p_membro;
  if p_status is null and p_chegada is null then
    delete from public.escala_ajustes where funcionario_id = m.funcionario_id and data = p_data;
    return;
  end if;
  insert into public.escala_ajustes as a (empresa_id, membro_id, funcionario_id, data, status, chegada, motivo,
                                          criado_por, criado_por_nome)
  values (m.empresa_id, m.id, m.funcionario_id, p_data, p_status, p_chegada, nullif(btrim(coalesce(p_motivo, '')), ''),
          public.meu_perfil_id(), public.ponto_nome_autor())
  on conflict (funcionario_id, data) do update set
    membro_id = excluded.membro_id, status = excluded.status, chegada = excluded.chegada, motivo = excluded.motivo,
    criado_por = excluded.criado_por, criado_por_nome = excluded.criado_por_nome
  returning a.id into v_id;
  perform public.escala_sincronizar_abono(v_id);
end $$;
comment on function public.escala_gravar_dia(uuid, date, text, time, text) is '[interno] Grava/apaga o ajuste de um dia e sincroniza o abono.';

create or replace function public.escala_validar_data(p_empresa uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date;
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.escala_hoje(p_empresa);
  if p_data < v_hoje - 62 or p_data > v_hoje + 366 then
    raise exception 'Data fora do limite' using errcode = '22023';
  end if;
end $$;
comment on function public.escala_validar_data(uuid, date) is '[interno] Data de ajuste em [hoje − 62, hoje + 366].';

create or replace function public.escala_hora(p_hora time)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select to_char(p_hora, 'HH24:MI')
$$;
comment on function public.escala_hora(time) is '[interno] Hora como HH:MM.';

-- Objeto-dia (§S.8) de um funcionário; p_motivo = incluir o motivo (G A M).
create or replace function public.escala_dia_json(p_empresa uuid, p_funcionario uuid, p_data date, p_motivo boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object('funcionario_id', c.funcionario_id, 'data', c.data, 'status', c.status, 'origem', c.origem,
                            'chegada', public.escala_hora(c.chegada), 'ajustado', c.ajustado,
                            'motivo', case when p_motivo then c.motivo end)
    from public.escala_calcular(p_empresa, p_data, p_data, p_funcionario) c
$$;
comment on function public.escala_dia_json(uuid, uuid, date, boolean) is '[interno] Objeto-dia da escala (adendo §S.8).';

-- ================================================================ RPCs de configuração
create or replace function public.escala_configurar(p_ancora date, p_fase int default 0, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_antiga date; v_fase int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if extract(isodow from p_ancora) <> 1 then
    raise exception 'A data-âncora deve ser uma segunda-feira' using errcode = '22023';
  end if;
  v_fase := public.escala_validar_fase(p_fase);
  select c.ancora into v_antiga from public.escala_config c where c.empresa_id = v_empresa;
  insert into public.escala_config as c (empresa_id, ancora, fase) values (v_empresa, p_ancora, v_fase)
  on conflict (empresa_id) do update set ancora = excluded.ancora, fase = excluded.fase;
  delete from public.escala_ajustes where empresa_id = v_empresa and data < p_ancora;
  perform public.escala_reapurar(v_empresa,
    (select array_agg(m.funcionario_id) from public.escala_membros m where m.empresa_id = v_empresa),
    least(coalesce(v_antiga, p_ancora), p_ancora));
  return jsonb_build_object('empresa_id', v_empresa, 'ancora', p_ancora, 'fase', v_fase);
end $$;
comment on function public.escala_configurar(date, int, uuid) is '[api] Define a data-âncora (segunda) e a fase da escala; reapura.';

create or replace function public.escala_salvar_setor(p_nome text, p_ordem int default null, p_fase int default 0,
                                                      p_setor uuid default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; s public.escala_setores; v_id uuid; v_nome text; v_fase int; v_cfg public.escala_config;
begin
  if p_setor is not null then
    s := public.escala_setor_para_operar(p_setor);
    v_empresa := s.empresa_id;
    if p_empresa is not null and p_empresa <> v_empresa then raise exception 'Sem permissão' using errcode = '42501'; end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  v_fase := public.escala_validar_fase(p_fase);
  if exists (select 1 from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(v_nome)
                and x.id is distinct from p_setor) then
    raise exception 'Setor já existe' using errcode = '23505';
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);
  if p_setor is null then
    insert into public.escala_setores (empresa_id, nome, ordem, fase)
    values (v_empresa, v_nome,
            coalesce(p_ordem, (select coalesce(max(x.ordem), 0) + 1 from public.escala_setores x where x.empresa_id = v_empresa)),
            v_fase)
    returning id into v_id;
  else
    update public.escala_setores set nome = v_nome, ordem = coalesce(p_ordem, ordem), fase = v_fase where id = p_setor;
    v_id := p_setor;
    if s.fase <> v_fase then
      perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(array[p_setor]), v_cfg.ancora);
    end if;
  end if;
  return v_id;
end $$;
comment on function public.escala_salvar_setor(text, int, int, uuid, uuid) is '[api] Cria ou altera um setor da escala.';

create or replace function public.escala_excluir_setor(p_setor uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_func uuid[];
begin
  s := public.escala_setor_para_operar(p_setor);
  v_func := public.escala_funcionarios_dos_setores(array[p_setor]);
  delete from public.escala_setores where id = p_setor;
  perform public.escala_reapurar(s.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
end $$;
comment on function public.escala_excluir_setor(uuid) is '[api] Exclui o setor (membros e ajustes) e reapura.';

create or replace function public.escala_salvar_membro(p_setor uuid, p_funcionario uuid, p_folgas_base smallint[] default '{}',
                                                       p_chegada_padrao time default null, p_caminho smallint default null,
                                                       p_posicao smallint default null, p_ordem int default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_antigo uuid; v_id uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  select m.setor_id into v_antigo from public.escala_membros m where m.funcionario_id = p_funcionario;
  v_id := public.escala_gravar_membro(p_setor, p_funcionario, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, p_ordem);
  perform public.escala_reapurar(s.empresa_id,
    public.escala_funcionarios_dos_setores(array[p_setor, v_antigo]) || p_funcionario,
    (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_id;
end $$;
comment on function public.escala_salvar_membro(uuid, uuid, smallint[], time, smallint, smallint, int) is
  '[api] Põe/atualiza um funcionário num setor da escala (upsert por funcionário) e reapura.';

create or replace function public.escala_definir_membros(p_setor uuid, p_membros jsonb)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_afetados uuid[]; v_lista uuid[]; x jsonb; i int := 0;
  v_func uuid; v_folgas smallint[]; v_cheg time; v_cam smallint; v_pos smallint;
begin
  s := public.escala_setor_para_operar(p_setor);
  if p_membros is null or jsonb_typeof(p_membros) <> 'array' then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg((e ->> 'funcionario_id')::uuid), '{}') into v_lista from jsonb_array_elements(p_membros) e;
  exception when others then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end;
  if exists (select 1 from unnest(v_lista) u where u is null) then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  if (select count(distinct u) from unnest(v_lista) u) <> coalesce(array_length(v_lista, 1), 0) then
    raise exception 'Funcionário repetido na lista' using errcode = '22023';
  end if;
  v_afetados := public.escala_funcionarios_dos_setores(array[p_setor])
             || public.escala_funcionarios_dos_setores(
                  (select coalesce(array_agg(distinct m.setor_id), '{}') from public.escala_membros m where m.funcionario_id = any (v_lista)))
             || v_lista;
  delete from public.escala_membros where setor_id = p_setor and not (funcionario_id = any (v_lista));
  update public.escala_membros set caminho = null, posicao = null where setor_id = p_setor;
  for x in select * from jsonb_array_elements(p_membros) loop
    i := i + 1;
    begin
      v_func := (x ->> 'funcionario_id')::uuid;
      v_folgas := case when jsonb_typeof(x -> 'folgas_base') = 'array'
                       then array(select jsonb_array_elements_text(x -> 'folgas_base')::smallint) else '{}'::smallint[] end;
      v_cheg := nullif(x ->> 'chegada_padrao', '')::time;
      v_cam := (x ->> 'caminho')::smallint;
      v_pos := (x ->> 'posicao')::smallint;
    exception when others then
      raise exception 'Lista de membros inválida' using errcode = '22023';
    end;
    perform public.escala_gravar_membro(p_setor, v_func, v_folgas, v_cheg, v_cam, v_pos, i);
  end loop;
  perform public.escala_reapurar(s.empresa_id, v_afetados, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return i;
end $$;
comment on function public.escala_definir_membros(uuid, jsonb) is '[api] Substitui a lista de membros do setor (ordem e caminhos) e reapura.';

create or replace function public.escala_remover_membro(p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_func uuid[];
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_func := public.escala_funcionarios_dos_setores(array[m.setor_id]);
  delete from public.escala_membros where id = m.id;
  perform public.escala_reapurar(m.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = m.empresa_id));
end $$;
comment on function public.escala_remover_membro(uuid) is '[api] Tira o funcionário da escala (apaga seus ajustes) e reapura.';

create or replace function public.escala_adicionar_funcionario(p_setor uuid, p_nome text, p_cargo text default null,
                                                               p_folgas_base smallint[] default '{}', p_chegada_padrao time default null,
                                                               p_caminho smallint default null, p_posicao smallint default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_nome text; v_func uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao)
  values (s.empresa_id, v_nome, nullif(btrim(coalesce(p_cargo, '')), ''), 0)
  returning id into v_func;
  perform public.escala_gravar_membro(p_setor, v_func, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, null);
  perform public.escala_reapurar(s.empresa_id, public.escala_funcionarios_dos_setores(array[p_setor]),
                                 (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_func;
end $$;
comment on function public.escala_adicionar_funcionario(uuid, text, text, smallint[], time, smallint, smallint) is
  '[api] Cadastra um funcionário e o põe num setor da escala; retorna o id do funcionário.';

-- Modelo do cliente (docs/referencias/escala-macaw-v3.html), §S.7.8.
create or replace function public.escala_aplicar_modelo_macaw(p_empresa uuid default null, p_ancora date default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_cfg public.escala_config; r record; v_setor uuid; v_func uuid; v_membro uuid;
  v_setores int := 0; v_membros int := 0; v_criados int := 0; v_pos smallint; v_chave text; v_setores_ids uuid[] := '{}';
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is not null then
    perform public.escala_configurar(p_ancora, coalesce((select c.fase from public.escala_config c where c.empresa_id = v_empresa), 0),
                                     v_empresa);
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);

  for r in
    select * from (values
      ('Salão', 1, 1, 'Garçom 1', 'Garçom', '{2,3}', 1, 1), ('Salão', 1, 2, 'Garçom 2', 'Garçom', '{2,3}', 1, 2),
      ('Salão', 1, 3, 'Garçom 3', 'Garçom', '{2,3}', 1, 3), ('Salão', 1, 4, 'Cumim 2', 'Cumim', '{2,6}', 1, 4),
      ('Salão', 1, 5, 'Garçom 4', 'Garçom', '{0,1}', 2, 1), ('Salão', 1, 6, 'Garçom 5', 'Garçom', '{0,1}', 2, 2),
      ('Salão', 1, 7, 'Garçom 6', 'Garçom', '{0,1}', 2, 3), ('Salão', 1, 8, 'Cumim 1', 'Cumim', '{1,6}', 2, 4),
      ('Maître', 2, 1, 'Maître 1', 'Maître', '{0,1}', 1, 2), ('Maître', 2, 2, 'Maître 2', 'Maître', '{1,3}', 1, 1),
      ('Maître', 2, 3, 'Maître 3', 'Maître', '{2,3}', 1, 4), ('Maître', 2, 4, 'Gerente', 'Gerente', '{2}', null, null),
      ('Maître', 2, 5, 'Recepção', 'Recepção', '{0,6}', 1, 3),
      ('Areia', 3, 1, 'Areia 1', 'Areia', '{0,6}', 1, 2), ('Areia', 3, 2, 'Areia 2', 'Areia', '{0,1}', 1, 1),
      ('Areia', 3, 3, 'Areia 3', 'Areia', '{2,3}', 1, 3), ('Areia', 3, 4, 'Areia 4', 'Areia', '{2,3}', 1, 4),
      ('Areia', 3, 5, 'Areia 5', 'Areia', '{1,4}', 1, 5),
      ('Bar', 4, 1, 'Bar 1', 'Bar', '{0,6}', 1, 1), ('Bar', 4, 2, 'Bar 2', 'Bar', '{0,1}', 1, 4),
      ('Bar', 4, 3, 'Bar 3', 'Bar', '{2,3}', 1, 3), ('Bar', 4, 4, 'Bar 4', 'Bar', '{2,3}', 1, 2),
      ('ASG', 5, 1, 'ASG 1', 'ASG', '{0,6}', 1, 1), ('ASG', 5, 2, 'ASG 2', 'ASG', '{1,2}', 1, 2),
      ('ASG', 5, 3, 'ASG 3', 'ASG', '{3,4}', 1, 3),
      ('Cozinha', 6, 1, 'Chef', 'Chef', '{3}', null, null), ('Cozinha', 6, 2, 'Cozinha 1', 'Cozinha', '{0,1}', 1, 3),
      ('Cozinha', 6, 3, 'Cozinha 2', 'Cozinha', '{0,1}', 1, 2), ('Cozinha', 6, 4, 'Cozinha 3', 'Cozinha', '{0,6}', 1, 1),
      ('Cozinha', 6, 5, 'Cozinha 4', 'Cozinha', '{1,2}', 2, 1), ('Cozinha', 6, 6, 'Cozinha 5', 'Cozinha', '{2,3}', 2, 2),
      ('Cozinha', 6, 7, 'Cozinha 6', 'Cozinha', '{3,6}', 2, 3), ('Cozinha', 6, 8, 'Cozinha 7', 'Cozinha', '{2,4}', 2, 4)
    ) as t(setor, ordem_setor, ordem, nome, cargo, folgas, caminho, posicao)
    order by ordem_setor, ordem
  loop
    select x.id into v_setor from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(r.setor);
    if v_setor is null then
      insert into public.escala_setores (empresa_id, nome, ordem) values (v_empresa, r.setor, r.ordem_setor) returning id into v_setor;
      v_setores := v_setores + 1;
    end if;
    if not (v_setor = any (v_setores_ids)) then v_setores_ids := v_setores_ids || v_setor; end if;
    v_chave := r.setor || '|' || r.nome;
    continue when exists (select 1 from public.escala_membros m where m.empresa_id = v_empresa and m.modelo_posicao = v_chave);
    -- funcionário de mesmo nome: já na escala → só marca a posição do modelo; fora da escala → entra nela
    select f.id, m.id into v_func, v_membro
      from public.funcionarios f left join public.escala_membros m on m.funcionario_id = f.id
     where f.empresa_id = v_empresa and lower(btrim(f.nome)) = lower(r.nome)
     order by (m.id is null) desc, f.criado_em, f.id
     limit 1;
    if v_membro is not null then
      update public.escala_membros set modelo_posicao = v_chave where id = v_membro and modelo_posicao is null;
      continue;
    end if;
    if v_func is null then
      insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao) values (v_empresa, r.nome, r.cargo, 0)
      returning id into v_func;
      v_criados := v_criados + 1;
    end if;
    v_pos := r.posicao;
    if r.caminho is not null and exists (select 1 from public.escala_membros m
                                          where m.setor_id = v_setor and m.caminho = r.caminho and m.posicao = v_pos) then
      v_pos := null;    -- posição ocupada → próxima livre do caminho
    end if;
    perform public.escala_gravar_membro(v_setor, v_func, r.folgas::smallint[], null, r.caminho::smallint, v_pos, r.ordem, v_chave);
    v_membros := v_membros + 1;
  end loop;

  perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(v_setores_ids), v_cfg.ancora);
  return jsonb_build_object('ancora', (select c.ancora from public.escala_config c where c.empresa_id = v_empresa),
                            'setores', v_setores, 'membros', v_membros, 'funcionarios_criados', v_criados);
end $$;
comment on function public.escala_aplicar_modelo_macaw(uuid, date) is
  '[api] Monta setores, caminhos e posições do modelo Macaw (cria funcionários provisórios); idempotente.';

-- ================================================================ RPCs de ajuste
create or replace function public.escala_ajustar(p_funcionario uuid, p_data date, p_status text default null,
                                                 p_chegada time default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_status := public.escala_status_param(p_status);
  perform public.escala_validar_data(m.empresa_id, p_data);
  select * into c from public.escala_calcular(m.empresa_id, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
  perform public.escala_gravar_dia(m.id, p_data, v_status, p_chegada, p_motivo);
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_data, p_data);
  return public.escala_dia_json(m.empresa_id, p_funcionario, p_data, true);
end $$;
comment on function public.escala_ajustar(uuid, date, text, time, text) is '[api] Define o estado de um dia da escala (status/chegada) e reapura.';

create or replace function public.escala_ajustar_periodo(p_funcionario uuid, p_inicio date, p_fim date, p_status text,
                                                         p_motivo text default null)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record; v_n int := 0;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_status := public.escala_status_param(p_status);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  perform public.escala_validar_data(m.empresa_id, p_inicio);
  perform public.escala_validar_data(m.empresa_id, p_fim);
  for c in select * from public.escala_calcular(m.empresa_id, p_inicio, p_fim, p_funcionario) x order by x.data loop
    continue when c.status = 'fora';
    perform public.escala_gravar_dia(m.id, c.data, v_status, c.ajuste_chegada, p_motivo);
    v_n := v_n + 1;
  end loop;
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_inicio, p_fim);
  return v_n;
end $$;
comment on function public.escala_ajustar_periodo(uuid, date, date, text, text) is
  '[api] Mesmo status em vários dias (ex.: férias), mantendo a chegada ajustada; reapura.';

create or replace function public.escala_trocar(p_funcionario_a uuid, p_data_a date, p_funcionario_b uuid default null,
                                                p_data_b date default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ma public.escala_membros; mb public.escala_membros; v_motivo text; v_datas date[]; v_d date;
  ca record; cb record; v_out jsonb := '[]';
begin
  ma := public.escala_membro_para_operar(p_funcionario_a);
  if (p_funcionario_b is null and p_data_b is null) or p_funcionario_b = p_funcionario_a and p_data_b is null then
    raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023';
  end if;
  if p_funcionario_b is not null and p_funcionario_b <> p_funcionario_a then
    mb := public.escala_membro_para_operar(p_funcionario_b);
    if mb.empresa_id <> ma.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  end if;
  v_motivo := coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Troca de folga');
  perform public.escala_validar_data(ma.empresa_id, p_data_a);
  if p_data_b is not null then perform public.escala_validar_data(ma.empresa_id, p_data_b); end if;

  if mb.id is null then
    -- A troca o próprio status entre os dois dias
    if p_data_b = p_data_a then raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023'; end if;
    select * into ca from public.escala_calcular(ma.empresa_id, p_data_a, p_data_a, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, p_data_b, p_data_b, p_funcionario_a) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_gravar_dia(ma.id, p_data_a, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(ma.id, p_data_b, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], least(p_data_a, p_data_b), least(p_data_a, p_data_b));
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], greatest(p_data_a, p_data_b), greatest(p_data_a, p_data_b));
    select jsonb_agg(public.escala_dia_json(ma.empresa_id, p_funcionario_a, d, true) order by d) into v_out
      from unnest(array[p_data_a, p_data_b]) d;
    return v_out;
  end if;

  -- A e B trocam o status em cada dia
  v_datas := array[p_data_a];
  if p_data_b is not null and p_data_b <> p_data_a then v_datas := v_datas || p_data_b; end if;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
  end loop;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    perform public.escala_gravar_dia(ma.id, v_d, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(mb.id, v_d, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a, p_funcionario_b], v_d, v_d);
  end loop;
  select jsonb_agg(public.escala_dia_json(ma.empresa_id, f, d, true) order by o, d) into v_out
    from unnest(array[p_funcionario_a, p_funcionario_b]) with ordinality as u(f, o)
    cross join unnest(v_datas) d;
  return v_out;
end $$;
comment on function public.escala_trocar(uuid, date, uuid, date, text) is
  '[api] Troca de folga: A↔B num dia (ou em dois dias) ou A entre dois dias; reapura.';

-- ================================================================ RPCs de leitura
create or replace function public.escala_mes(p_ano_mes text, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_ini date; v_fim date; v_cfg public.escala_config; v_motivo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_ano_mes is null or p_ano_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Mês inválido (use AAAA-MM)' using errcode = '22023';
  end if;
  v_ini := (p_ano_mes || '-01')::date;
  v_fim := (v_ini + interval '1 month')::date - 1;
  v_motivo := public.pode_operar(v_empresa) is true;
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;

  return (
    with calc as materialized (select * from public.escala_calcular(v_empresa, v_ini, v_fim)),
    dias as (select g::date as d from generate_series(v_ini, v_fim, interval '1 day') g),
    mem as (
      select m.*, f.nome, f.cargo from public.escala_membros m join public.funcionarios f on f.id = m.funcionario_id
       where m.empresa_id = v_empresa
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'ano_mes', p_ano_mes, 'inicio', v_ini, 'fim', v_fim,
      'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'pode_editar', v_motivo, 'hoje', public.escala_hoje(v_empresa),
      'dias', (select jsonb_agg(jsonb_build_object('data', d, 'dia_semana', extract(isodow from d)::int - 1,
                                                   'semana', case when v_cfg.ancora is not null then public.escala_semana_num(d, v_cfg.ancora) end)
                                order by d) from dias),
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs) order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'membro_id', m.id, 'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                            'chegada_padrao', public.escala_hora(m.chegada_padrao), 'folgas_base', to_jsonb(m.folgas_base),
                            'caminho', m.caminho, 'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                            'trabalha', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'trabalha'),
                            'folgas', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'folga'),
                            'ferias', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'ferias'),
                            'dias', coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'data', dd.d, 'status', coalesce(c.status, 'fora'), 'origem', coalesce(c.origem, 'auto'),
                                       'chegada', public.escala_hora(c.chegada), 'ajustado', coalesce(c.ajustado, false),
                                       'motivo', case when v_motivo then c.motivo end) order by dd.d)
                                from dias dd left join calc c on c.funcionario_id = m.funcionario_id and c.data = dd.d), '[]'))
                          order by m.ordem, m.nome collate "C", m.id)
                     from mem m where m.setor_id = s.id), '[]'),
                 'na_escala', (select jsonb_agg((select count(*) from calc c where c.setor_id = s.id and c.data = dd.d and c.status = 'trabalha')
                                                order by dd.d) from dias dd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala', (select jsonb_agg((select count(*) from calc c where c.data = dd.d and c.status = 'trabalha') order by dd.d)
                      from dias dd))
  );
end $$;
comment on function public.escala_mes(text, uuid) is '[api] Escala do mês (AAAA-MM): setores, membros e dias (leitura vê, sem motivos).';

create or replace function public.escala_semana(p_data date default null, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_cfg public.escala_config; v_data date; v_seg date; v_w int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.escala_hoje(v_empresa));
  v_seg := v_data - (extract(isodow from v_data)::int - 1);
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;
  v_w := case when v_cfg.ancora is not null then public.escala_semana_num(v_seg, v_cfg.ancora) end;

  return (
    with r as materialized (select * from public.escala_membros_rodizio(v_empresa)),
    mem as (
      select r.*, f.nome, f.cargo, m.ordem,
             coalesce(case when v_w is null or r.caminho is null then r.folgas_base
                           else (select a.folgas_base from r a
                                  where a.setor_id = r.setor_id and a.caminho = r.caminho
                                    and a.k = (((r.k + v_w + coalesce(v_cfg.fase, 0) + r.fase_setor) % r.n) + r.n) % r.n) end,
                      r.folgas_base) as folgas_semana
        from r join public.funcionarios f on f.id = r.funcionario_id join public.escala_membros m on m.id = r.id
    ),
    wd as (select generate_series(0, 6) as d)
    select jsonb_build_object(
      'empresa_id', v_empresa, 'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'semana_inicio', v_seg, 'semana', v_w,
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'total', (select count(*) from mem m where m.setor_id = s.id),
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs, 'nomes', cm.nomes)
                                                        order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs,
                                                      jsonb_agg(m.nome order by m.posicao, m.id) as nomes
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((select jsonb_agg(jsonb_build_object(
                                               'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                                               'chegada_padrao', public.escala_hora(m.chegada_padrao), 'caminho', m.caminho,
                                               'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                                               'folgas_base', to_jsonb(m.folgas_base), 'folgas_semana', to_jsonb(m.folgas_semana))
                                             order by m.ordem, m.nome collate "C", m.id)
                                        from mem m where m.setor_id = s.id), '[]'),
                 'na_escala_base', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_base)))
                                                     order by wd.d) from wd),
                 'na_escala_semana', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_semana)))
                                                       order by wd.d) from wd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala_base', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_base))) order by wd.d) from wd),
      'na_escala_semana', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_semana))) order by wd.d) from wd))
  );
end $$;
comment on function public.escala_semana(date, uuid) is '[api] Semana base e semana de p_data pela regra do rodízio (sem ajustes).';

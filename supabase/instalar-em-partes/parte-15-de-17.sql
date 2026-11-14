-- Meu Dia de Gerente — instalação do banco, PARTE 15 DE 17.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000270_reservas.sql, 20261006000280_escala.sql. Não edite à mão.

begin;
comment on function public.reservas_listar(date, date, text[], uuid) is
  '[api] Reservas do período (L G A M; telefone/e-mail só para G A M).';

create or replace function public.reservas_importar(p_linhas jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_ids text[] := '{}'; v_novo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_linhas) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_linhas) with ordinality as e(valor, ord) loop
    begin
      select * into c from public.reserva_ler_item(it.valor, 'horario');
      if c.id_externo is not null then
        if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
        v_ids := v_ids || c.id_externo;
      end if;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    if c.id_externo is null then
      insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                                   telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa, c.observacao,
              c.telefone, c.email, public.meu_perfil_id(), public.agora());
      v_ins := v_ins + 1;
    else
      insert into public.reservas as r (empresa_id, origem, id_externo, data, horario, nome_cliente, pessoas, status, area, mesa,
                                        observacao, telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
              c.observacao, c.telefone, c.email, public.meu_perfil_id(), public.agora())
      on conflict (empresa_id, origem, id_externo) do update
        set data = excluded.data, horario = excluded.horario, nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas,
            status = excluded.status, area = excluded.area, mesa = excluded.mesa, observacao = excluded.observacao,
            telefone = excluded.telefone, email = excluded.email, importado_em = excluded.importado_em
      returning (xmax = 0) into v_novo;
      if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('lidos', jsonb_array_length(p_linhas), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'erros', v_erros);
end $$;
comment on function public.reservas_importar(jsonb, uuid) is '[api] Importa reservas de um CSV lido pelo front (G A M).';

-- ================================================================ ingestão (N8N)
create or replace function public.ingestao_reservas(p_integracao uuid, p_inicio date, p_fim date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_rem int := 0; v_ids text[] := '{}'; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['tagme']);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_itens) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:reservas:' || ig.empresa_id::text, 0));

  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_itens) with ordinality as e(valor, ord) loop
    begin
      if it.valor is null or jsonb_typeof(it.valor) <> 'object' then raise exception 'item inválido'; end if;
      if nullif(btrim(it.valor ->> 'id_externo'), '') is null then raise exception 'id_externo ausente'; end if;
      select * into c from public.reserva_ler_item(it.valor, 'hora');
      if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
      v_ids := v_ids || c.id_externo;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    insert into public.reservas as r (empresa_id, integracao_id, origem, id_externo, data, horario, nome_cliente, pessoas, status,
                                      area, mesa, observacao, telefone, email, importado_em)
    values (ig.empresa_id, ig.id, 'tagme', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
            c.observacao, c.telefone, c.email, public.agora())
    on conflict (empresa_id, origem, id_externo) do update
      set integracao_id = excluded.integracao_id, data = excluded.data, horario = excluded.horario,
          nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas, status = excluded.status, area = excluded.area,
          mesa = excluded.mesa, observacao = excluded.observacao, telefone = excluded.telefone, email = excluded.email,
          importado_em = excluded.importado_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;

  delete from public.reservas r
   where r.empresa_id = ig.empresa_id and r.origem = 'tagme' and r.data between p_inicio and p_fim
     and not (r.id_externo = any (v_ids));
  get diagnostics v_rem = row_count;

  update public.integracoes
     set cursor = jsonb_build_object('ultimo_inicio', p_inicio, 'ultimo_fim', p_fim)
   where id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_itens), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'removidos', v_rem, 'erros', v_erros);
end $$;
comment on function public.ingestao_reservas(uuid, date, date, jsonb) is
  '[servico] Reservas da Tagme (N8N): upsert por id_externo e remove as da janela que não vieram (adendo R.3).';

-- Bloco "reservas" do painel (sem checagem; o painel já resolveu a empresa).
create or replace function public.reservas_painel(p_empresa uuid, p_hoje date, p_telefone boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with e as (select fuso from public.empresas where id = p_empresa),
       r as (select * from public.reservas where empresa_id = p_empresa and data = p_hoje)
  select jsonb_build_object(
    'total', (select count(*) from r where status <> 'cancelada'),
    'pessoas', (select coalesce(sum(pessoas), 0) from r where status <> 'cancelada'),
    'canceladas', (select count(*) from r where status = 'cancelada'),
    'nao_compareceu', (select count(*) from r where status = 'nao_compareceu'),
    'sentadas', (select count(*) from r where status = 'sentada'),
    'tem_tagme', exists (select 1 from public.integracoes i where i.empresa_id = p_empresa and i.tipo = 'tagme' and i.ativa),
    'proximas', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'horario', x.horario, 'nome_cliente', x.nome_cliente, 'pessoas', x.pessoas,
                                           'status', x.status, 'area', x.area, 'mesa', x.mesa, 'observacao', x.observacao,
                                           'origem', x.origem, 'telefone', case when p_telefone then x.telefone end)
                        order by x.horario nulls last, x.nome_cliente, x.id)
         from (select r.* from r, e
                where r.status in ('confirmada', 'pendente')
                  and (r.horario is null or ((r.data + r.horario) at time zone e.fuso) >= public.agora() - interval '30 minutes')
                order by r.horario nulls last, r.nome_cliente, r.id
                limit 10) x), '[]'::jsonb))
$$;
comment on function public.reservas_painel(uuid, date, boolean) is '[interno] Bloco reservas do painel_do_dia (adendo R.4).';-- =====================================================================================================
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
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
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
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
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
language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
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

commit;
select 'parte 15 de 17 instalada' as resultado;

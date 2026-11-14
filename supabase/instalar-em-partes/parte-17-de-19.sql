-- Meu Dia de Gerente — instalação do banco, PARTE 17 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000290_comissao_presenca.sql. Não edite à mão.

begin;
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

commit;
select 'parte 17 de 19 instalada' as resultado;

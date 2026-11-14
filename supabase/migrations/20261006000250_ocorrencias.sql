-- =====================================================================================================
-- 20261006000250_ocorrencias.sql — backend (adendo extras/ocorrências/reservas, seção O)
-- Ocorrências disciplinares do funcionário (advertência / suspensão) com anexos no Storage (bucket privado
-- 'funcionarios-documentos'). Suspensão gera abonos 'suspensao' em ponto_abonos (situação 'suspenso', sem alarmes
-- nem saldo negativo). Dado sensível: só G A M. Idempotente.
-- =====================================================================================================

create table if not exists public.funcionario_ocorrencias (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,
  funcionario_id    uuid not null references public.funcionarios (id) on delete cascade,
  tipo              text not null check (tipo in ('advertencia', 'suspensao')),
  data              date not null,
  motivo            text not null check (btrim(motivo) <> ''),
  descricao         text,
  dias_suspensao    int check (dias_suspensao between 1 and 30),
  suspensao_inicio  date,
  suspensao_fim     date,
  criado_por        uuid references public.perfis (id) on delete set null,
  criado_por_nome   text not null,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint funcionario_ocorrencias_suspensao check (
    (tipo = 'advertencia' and dias_suspensao is null and suspensao_inicio is null and suspensao_fim is null)
    or (tipo = 'suspensao' and dias_suspensao is not null and suspensao_inicio is not null
        and suspensao_fim = suspensao_inicio + dias_suspensao - 1))
);
create index if not exists funcionario_ocorrencias_empresa_idx on public.funcionario_ocorrencias (empresa_id, data desc);
create index if not exists funcionario_ocorrencias_funcionario_idx on public.funcionario_ocorrencias (funcionario_id, data desc);
create index if not exists funcionario_ocorrencias_criado_por_idx on public.funcionario_ocorrencias (criado_por);
comment on table public.funcionario_ocorrencias is
  '[api:leitura] Ocorrências disciplinares (advertência/suspensão) do funcionário. Dado sensível: só G A M.';

create table if not exists public.funcionario_ocorrencia_anexos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  ocorrencia_id   uuid not null references public.funcionario_ocorrencias (id) on delete cascade,
  bucket          text not null default 'funcionarios-documentos',
  caminho         text not null unique,
  nome_arquivo    text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now()
);
create index if not exists funcionario_ocorrencia_anexos_empresa_idx on public.funcionario_ocorrencia_anexos (empresa_id);
create index if not exists funcionario_ocorrencia_anexos_ocorrencia_idx on public.funcionario_ocorrencia_anexos (ocorrencia_id);
create index if not exists funcionario_ocorrencia_anexos_criado_por_idx on public.funcionario_ocorrencia_anexos (criado_por);
comment on table public.funcionario_ocorrencia_anexos is
  '[api:leitura] Anexos (fotos/PDF no Storage, bucket privado funcionarios-documentos) das ocorrências. Só G A M.';

-- abono gerado pela suspensão (coluna criada em …0200)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ponto_abonos_ocorrencia_fk') then
    alter table public.ponto_abonos add constraint ponto_abonos_ocorrencia_fk
      foreign key (ocorrencia_id) references public.funcionario_ocorrencias (id) on delete cascade;
  end if;
end $$;

-- ================================================================ RLS
alter table public.funcionario_ocorrencias enable row level security;
alter table public.funcionario_ocorrencia_anexos enable row level security;
drop policy if exists funcionario_ocorrencias_ler on public.funcionario_ocorrencias;
create policy funcionario_ocorrencias_ler on public.funcionario_ocorrencias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists funcionario_ocorrencia_anexos_ler on public.funcionario_ocorrencia_anexos;
create policy funcionario_ocorrencia_anexos_ler on public.funcionario_ocorrencia_anexos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
drop trigger if exists a_empresa on public.funcionario_ocorrencias;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.funcionario_ocorrencias
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists tocar_atualizado_em on public.funcionario_ocorrencias;
create trigger tocar_atualizado_em before update on public.funcionario_ocorrencias
  for each row execute function public.tocar_atualizado_em();

create or replace function public.ocorrencia_anexo_empresa()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select o.empresa_id into v_empresa from public.funcionario_ocorrencias o where o.id = new.ocorrencia_id;
  if v_empresa is null then raise exception 'Ocorrência não encontrada' using errcode = 'P0002'; end if;
  new.empresa_id := v_empresa;
  return new;
end $$;
comment on function public.ocorrencia_anexo_empresa() is '[interno] Gatilho: empresa_id do anexo = da ocorrência.';
drop trigger if exists a_empresa on public.funcionario_ocorrencia_anexos;
create trigger a_empresa before insert or update of ocorrencia_id, empresa_id on public.funcionario_ocorrencia_anexos
  for each row execute function public.ocorrencia_anexo_empresa();

-- ================================================================ Storage (documentos)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('funcionarios-documentos', 'funcionarios-documentos', false, 5242880,
            array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists mdg_docs_ler on storage.objects';
    execute $p$create policy mdg_docs_ler on storage.objects for select to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_inserir on storage.objects';
    execute $p$create policy mdg_docs_inserir on storage.objects for insert to authenticated
      with check (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_alterar on storage.objects';
    execute $p$create policy mdg_docs_alterar on storage.objects for update to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))
      with check (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_docs_excluir on storage.objects';
    execute $p$create policy mdg_docs_excluir on storage.objects for delete to authenticated
      using (bucket_id = 'funcionarios-documentos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
  end if;
end $$;

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
    -- (adendo extras v3, §E.7.2) dia com falta registrada não recebe suspensão
    select g::date into v_conflito from generate_series(o.suspensao_inicio, o.suspensao_fim, interval '1 day') g
     where public.ponto_falta_do_dia(o.funcionario_id, g::date) is not null order by g limit 1;
    if v_conflito is not null then
      raise exception 'Dia com falta em %: remova a falta antes', to_char(v_conflito, 'DD/MM/YYYY') using errcode = '22023';
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
comment on function public.ocorrencias_resumo(int, uuid) is '[api] Resumo das ocorrências dos últimos N dias (G A M).';

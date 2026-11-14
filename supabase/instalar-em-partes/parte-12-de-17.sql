-- Meu Dia de Gerente — instalação do banco, PARTE 12 DE 17.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000230_ingestao.sql, 20261006000240_painel.sql, 20261006000250_ocorrencias.sql. Não edite à mão.

begin;
create or replace function public.ingestao_zig_compradores(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0; v_rem int;
  v_erros jsonb := '[]'::jsonb;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_compradores:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_compradores where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'transactionId') is null then raise exception 'transactionId ausente'; end if;
      -- LGPD: userDocument, userDocumentType, userPhone, userName, userEmail são descartados.
      insert into public.zig_compradores (empresa_id, loja_id_externo, data_operacao, transaction_id, products_value, tip_value)
      values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'transactionId'),
              public.ingestao_centavos(x -> 'productsValue'), public.ingestao_centavos(x -> 'tipValue'));
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_compradores(uuid, text, date, jsonb) is '[servico] Substitui os compradores do dia/loja, sem dados pessoais.';

-- ======================================================== apuração e exportação (§11.6)
create or replace function public.ingestao_apurar_ponto(p_empresa uuid default null, p_inicio date default null,
                                                        p_fim date default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  e record; f record; v_atual date; v_ini date; v_fim date;
  v_emp int := 0; v_func int := 0; v_dias int := 0; v_n int;
begin
  if p_empresa is not null and not exists (select 1 from public.empresas where id = p_empresa) then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;
  for e in
    select em.id from public.empresas em
     where (p_empresa is null and em.ativa) or em.id = p_empresa
     order by em.id
  loop
    v_atual := public.dia_de_trabalho(public.agora(), e.id);
    v_ini := coalesce(p_inicio, v_atual - 2);
    v_fim := coalesce(p_fim, v_atual);
    perform public.ponto_validar_periodo(v_ini, v_fim, 93);
    v_emp := v_emp + 1;
    for f in
      select fu.id from public.funcionarios fu
       where fu.empresa_id = e.id
         and (fu.data_admissao is null or fu.data_admissao <= v_fim)
         and (fu.data_desligamento is null or fu.data_desligamento >= v_ini)
       order by fu.id
    loop
      v_n := public.ponto_apurar(f.id, v_ini, v_fim);
      if v_n > 0 then v_func := v_func + 1; end if;
      v_dias := v_dias + v_n;
    end loop;
  end loop;
  return jsonb_build_object('empresas', v_emp, 'funcionarios', v_func, 'dias', v_dias);
end $$;
comment on function public.ingestao_apurar_ponto(uuid, date, date) is '[servico] Rotina diária: apura todas as empresas ativas (padrão: dia atual − 2 até hoje).';

create or replace function public.ingestao_fechamento_exportar(p_fechamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_fech jsonb; v_itens jsonb;
begin
  select to_jsonb(fc) || jsonb_build_object('empresa_nome', e.nome) into v_fech
    from public.comissao_fechamentos fc join public.empresas e on e.id = fc.empresa_id
   where fc.id = p_fechamento;
  if v_fech is null then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(it) order by it.funcionario_nome, (it.tipo = 'extra'),
                            coalesce(it.funcionario_id, it.extra_id) nulls last, it.id), '[]'::jsonb) into v_itens
    from public.comissao_itens it where it.fechamento_id = p_fechamento;
  -- (adendo extras v2, E.3.4) detalhe diário do rateio (vazio no modo período)
  return jsonb_build_object('fechamento', v_fech, 'itens', v_itens,
    'dias', coalesce((select jsonb_agg(to_jsonb(rd) order by rd.data) from public.comissao_rateio_dias rd
                       where rd.fechamento_id = p_fechamento), '[]'::jsonb));
end $$;
comment on function public.ingestao_fechamento_exportar(uuid) is '[servico] Fechamento + itens (por nome) + dias do rateio para o CSV do N8N.';-- =====================================================================================================
-- 20261006000240_painel.sql — backend-2
-- painel_do_dia: resumo do dia de trabalho (faturamento, serviço, ponto, tarefas, sincronização). Contrato §10.7.
-- + blocos reservas e ocorrencias (docs/CONTRATO-ADENDO-extras-ocorrencias-reservas.md, R.4).
-- =====================================================================================================

create or replace function public.painel_do_dia(p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa   uuid;
  v_hoje      date;
  v_ontem     date;
  v_mes       date;
  v_fat       jsonb;
  v_serv      jsonb;
  v_ponto     jsonb;
  v_tarefas   jsonb;
  v_sync      jsonb;
  v_fuso      text;
  v_virada    time;
  v_presentes int := 0;
  v_escalados int := 0;
  v_operar    boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  select e.fuso, e.virada_dia into v_fuso, v_virada from public.empresas e where e.id = v_empresa;
  v_hoje := public.dia_de_trabalho(public.agora(), v_empresa);
  v_ontem := v_hoje - 1;
  v_mes := date_trunc('month', v_hoje)::date;

  -- faturamento e serviço
  select jsonb_build_object(
           'hoje', coalesce(sum(z.valor) filter (where z.data_operacao = v_hoje), 0),
           'ontem', coalesce(sum(z.valor) filter (where z.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(z.valor) filter (where z.data_operacao >= v_mes), 0),
           'tem_zig', exists (select 1 from public.integracoes i where i.empresa_id = v_empresa and i.tipo = 'zig' and i.ativa))
    into v_fat
    from public.zig_faturamento z
   where z.empresa_id = v_empresa and z.data_operacao between least(v_mes, v_ontem) and v_hoje;

  select jsonb_build_object(
           'ontem', coalesce(sum(i.valor_total) filter (where i.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(i.valor_total) filter (where i.data_operacao >= v_mes), 0))
    into v_serv
    from public.zig_vendas_itens i
   where i.empresa_id = v_empresa and i.tipo = 'Tip' and i.data_operacao between least(v_mes, v_ontem) and v_hoje;

  -- ponto (ao vivo para hoje)
  select count(*) filter (where c.batidas_validas % 2 = 1),
         count(*) filter (where c.batidas_esperadas > 0)
    into v_presentes, v_escalados
    from public.funcionarios f
    cross join lateral public.ponto_calcular_dia(f.id, v_hoje) c
   where f.empresa_id = v_empresa and f.ativo and not c.fora_do_vinculo;

  select jsonb_build_object(
    'alarmes_abertos', (select count(*) from public.ponto_alarmes a where a.empresa_id = v_empresa and a.status = 'aberto'),
    'alarmes', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'funcionario_id', x.funcionario_id, 'funcionario_nome', x.nome,
                                           'data', x.data, 'tipo', x.tipo, 'batida_esperada', x.batida_esperada,
                                           'detalhe', x.detalhe) order by x.data desc, x.criado_em desc, x.id)
         from (select a.id, a.funcionario_id, f.nome, a.data, a.tipo, a.batida_esperada, a.detalhe, a.criado_em
                 from public.ponto_alarmes a
                 join public.funcionarios f on f.id = a.funcionario_id
                where a.empresa_id = v_empresa and a.status = 'aberto'
                order by a.data desc, a.criado_em desc, a.id
                limit 5) x), '[]'::jsonb),
    'presentes_agora', v_presentes,
    'escalados_hoje', v_escalados,
    'batidas_sem_funcionario', (select count(*) from public.ponto_batidas b
                                 where b.empresa_id = v_empresa and b.funcionario_id is null))
    into v_ponto;

  -- tarefas do dia (atrasadas: abertas de hoje ou de dias anteriores cujo prazo já passou)
  select jsonb_build_object(
           'total', count(*) filter (where t.data = v_hoje and t.status <> 'cancelada'),
           'concluidas', count(*) filter (where t.data = v_hoje and t.status = 'concluida'),
           'pendentes', count(*) filter (where t.data = v_hoje and t.status in ('pendente', 'em_andamento')),
           'atrasadas', count(*) filter (where t.status in ('pendente', 'em_andamento')
                                          and (t.data < v_hoje
                                               or (t.data = v_hoje and t.horario_limite is not null
                                                   and public.ponto_instante_escala(t.data, t.horario_limite, v_fuso, v_virada)
                                                       < public.agora()))))
    into v_tarefas
    from public.tarefas t
   where t.empresa_id = v_empresa and t.data between v_hoje - 31 and v_hoje;

  -- sincronização (só status, nunca segredos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'integracao_id', i.id, 'tipo', i.tipo, 'nome', i.nome, 'ativa', i.ativa,
           'ultimo_sucesso_em', i.ultimo_sucesso_em, 'ultimo_status', i.ultimo_status, 'ultimo_erro', i.ultimo_erro,
           'executando', exists (select 1 from public.sync_execucoes s where s.integracao_id = i.id and s.status = 'executando')
                      or exists (select 1 from public.sync_solicitacoes s
                                  where s.integracao_id = i.id and s.status in ('pendente', 'em_andamento')))
           order by i.tipo, i.nome, i.id), '[]'::jsonb)
    into v_sync
    from public.integracoes i
   where i.empresa_id = v_empresa;

  -- reservas e ocorrências (adendo extras/ocorrências/reservas R.4 / O.4): telefone e ocorrências só para G A M
  v_operar := public.pode_operar(v_empresa) is true;

  return jsonb_build_object(
    'empresa_id', v_empresa, 'dia_trabalho', v_hoje, 'ontem', v_ontem,
    'faturamento', v_fat, 'servico', v_serv, 'ponto', v_ponto, 'tarefas', v_tarefas, 'sincronizacao', v_sync,
    'reservas', public.reservas_painel(v_empresa, v_hoje, v_operar),
    'ocorrencias', case when v_operar then public.ocorrencias_resumo_empresa(v_empresa, 30) end);
end $$;
comment on function public.painel_do_dia(uuid) is '[api] Painel do dia de trabalho (§10.7).';-- =====================================================================================================
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

commit;
select 'parte 12 de 17 instalada' as resultado;

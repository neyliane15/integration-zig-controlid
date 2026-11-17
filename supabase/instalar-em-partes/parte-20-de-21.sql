-- Meu Dia de Gerente — instalação do banco, PARTE 20 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000300_importar_afd.sql, 20261006000310_rhid.sql, 20261006000320_rhid_horarios.sql, 20261006000330_ocorrencias_ponto.sql. Não edite à mão.

begin;
-- ------------------------------------------------------------- ligar funcionários (CPF do AFD)
-- Liga o CPF/PIS do AFD ou do RHiD (usuário do equipamento) a um funcionário — inclusive provisório da escala ("Garçom 1") —,
-- opcionalmente renomeando-o com o nome do AFD e gravando o CPF/PIS na ficha. As batidas pendentes passam ao funcionário
-- e os dias são reapurados (gatilho §7.8).
create or replace function public.ponto_afd_ligar(
  p_controlid_usuario uuid, p_funcionario uuid, p_renomear boolean default false, p_cadastrar_documento boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v public.controlid_usuarios;
  v_tipo text;
  f public.funcionarios;
  v_nome text;
  v_renomeado boolean := false;
  v_documento boolean := false;
begin
  select * into v from public.controlid_usuarios where id = p_controlid_usuario;
  if not found then raise exception 'Usuário do equipamento não encontrado' using errcode = 'P0002'; end if;
  if not public.pode_operar(v.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  select i.tipo into v_tipo from public.integracoes i where i.id = v.integracao_id;
  -- relógio REP (rede ou arquivo) ou RHiD (nuvem): os dois guardam os CPFs/PIS em controlid_usuarios
  if v_tipo is null or v_tipo not in ('controlid_rep', 'rhid') then
    raise exception 'Tipo de integração incompatível' using errcode = '22023';
  end if;
  if p_funcionario is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  select * into f from public.funcionarios where id = p_funcionario;
  if not found then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if f.empresa_id <> v.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;

  if coalesce(p_cadastrar_documento, false) then
    if v.cpf is not null and f.cpf is distinct from v.cpf then
      if exists (select 1 from public.funcionarios x where x.empresa_id = v.empresa_id and x.cpf = v.cpf and x.id <> f.id) then
        raise exception 'CPF já cadastrado em outro funcionário' using errcode = '23505';
      end if;
      update public.funcionarios set cpf = v.cpf where id = f.id;
      v_documento := true;
    elsif v.cpf is null and v.pis is not null and f.pis is distinct from v.pis then
      update public.funcionarios set pis = v.pis where id = f.id;
      v_documento := true;
    end if;
  end if;

  perform public.funcionario_vincular_controlid(v.id, f.id);

  v_nome := public.nome_proprio(v.nome);
  if coalesce(p_renomear, false) and v_nome is not null and v_nome is distinct from f.nome then
    update public.funcionarios set nome = v_nome where id = f.id;
    v_renomeado := true;
  end if;

  return jsonb_build_object(
    'funcionario_id', f.id,
    'nome', coalesce(case when v_renomeado then v_nome end, f.nome),
    'renomeado', v_renomeado,
    'documento_cadastrado', v_documento,
    'batidas', (select count(*) from public.ponto_batidas b
                 where b.integracao_id = v.integracao_id and b.pessoa_externa = v.user_id_externo and b.funcionario_id = f.id));
end $$;
comment on function public.ponto_afd_ligar(uuid, uuid, boolean, boolean) is
  '[api] Liga o CPF/PIS do AFD/RHiD (relógio controlid_rep ou rhid) a um funcionário (renomear e gravar o documento na ficha são opcionais) (G A M).';

-- Usuários do relógio (CPF/PIS) com batidas ainda sem funcionário — a lista do "Ligar funcionários".
create or replace function public.ponto_afd_pendentes(p_integracao uuid)
returns table(controlid_usuario_id uuid, cpf text, pis text, nome text, nome_sugerido text, quantidade int,
              primeira date, ultima date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes;
begin
  select * into ig from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not public.pode_operar(ig.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if ig.tipo not in ('controlid_rep', 'rhid') then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  return query
  select c.id, c.cpf, c.pis, c.nome, public.nome_proprio(c.nome), count(b.id)::int, min(b.data_trabalho), max(b.data_trabalho)
    from public.controlid_usuarios c
    left join public.ponto_batidas b
      on b.integracao_id = c.integracao_id and b.pessoa_externa = c.user_id_externo and b.funcionario_id is null
   where c.integracao_id = ig.id and c.funcionario_id is null
   group by c.id, c.cpf, c.pis, c.nome
  having count(b.id) > 0 or not c.removido_no_equipamento
   order by count(b.id) desc, c.nome nulls last, c.user_id_externo;
end $$;
comment on function public.ponto_afd_pendentes(uuid) is
  '[api] CPF/PIS do relógio (controlid_rep ou rhid) sem funcionário, com as batidas pendentes (G A M).';-- =====================================================================================================
-- 20261006000310_rhid.sql — integração RHiD (nuvem da Control iD) pela API oficial (docs/referencias/rhid-swagger.json)
-- O relógio REP da loja (iDClass, Portaria 671) não é alcançável pela rede, mas sincroniza com o RHiD; o N8N
-- ("MDG · RHiD · Importar") faz login no RHiD, lê as pessoas (GET /person) e baixa o AFD 671 de cada equipamento
-- (GET /report/afd/download671, e o do coletor REP-P) a partir do último NSR. Aqui ficam:
--   · ingestao_rhid_pessoas  → reaproveita ingestao_controlid_usuarios (id = CPF; vínculo automático matrícula/CPF)
--   · ingestao_rhid_batidas  → reaproveita ingestao_controlid_batidas (id_externo = "<equipamento>|<NSR>", origem
--                              controlid_rep) e mantém o cursor por equipamento {nsr_por_equipamento: {id: ultimo_nsr}}
--   · integracao_trocar_para_rhid → troca um relógio controlid_rep (por rede ou por arquivo) por um RHiD sem perder vínculos
-- O tipo 'rhid' (checks, parâmetros padrão, segredos {email, senha, dominio}, escopos, tipos de execução rhid_pessoas e
-- rhid_batidas) está nas listas da …0120 (os checks precisam aceitar 'rhid' já na reaplicação das migrações).
-- Idempotente. Contrato: docs/CONTRATO-ADENDO-rhid.md.
-- =====================================================================================================

-- ------------------------------------------------------------------ auxiliares
-- CPF/PIS do RHiD (número inteiro na API: perde os zeros à esquerda) → 11 dígitos; vazio/zero/maior que 11 → null.
create or replace function public.rhid_documento(p_valor jsonb) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when d ~ '^[0-9]{1,11}$' and d !~ '^0+$' then lpad(d, 11, '0') end
    from (select regexp_replace(coalesce(p_valor #>> '{}', ''), '[^0-9]', '', 'g') as d) x
$$;
comment on function public.rhid_documento(jsonb) is '[interno] CPF/PIS do RHiD (número) → 11 dígitos com zeros à esquerda (ou null).';

-- ---------------------------------------------------------------- pessoas (GET /person)
-- p_pessoas: os PersonDTO do RHiD como vieram ({id, cpf, pis, name, registration, status, ...}). Snapshot completo:
-- quem não vier é marcado removido_no_equipamento (a ingestão do Control iD faz isso). Pessoa sem CPF é ignorada
-- (Portaria 671: o REP identifica pelo CPF).
create or replace function public.ingestao_rhid_pessoas(p_integracao uuid, p_pessoas jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig       public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  v_itens  jsonb := '[]'::jsonb;
  x        jsonb;
  v_cpf    text;
  v_sem    int := 0;
  v_res    jsonb;
begin
  p_pessoas := public.ingestao_lista(p_pessoas);
  if jsonb_array_length(p_pessoas) > 20000 then
    raise exception 'Lista maior que 20000 pessoas' using errcode = '22023';
  end if;
  for x in select value from jsonb_array_elements(p_pessoas) loop
    v_cpf := case when jsonb_typeof(x) = 'object' then public.rhid_documento(x -> 'cpf') end;
    if v_cpf is null then
      v_sem := v_sem + 1;
      continue;
    end if;
    v_itens := v_itens || jsonb_build_object(
      'id', v_cpf, 'cpf', v_cpf, 'pis', public.rhid_documento(x -> 'pis'),
      'name', coalesce(public.ingestao_texto(x -> 'name'), public.ingestao_texto(x -> 'socialName')),
      'registration', public.ingestao_texto(x -> 'registration'));
  end loop;
  v_res := public.ingestao_controlid_usuarios(ig.id, v_itens);
  return v_res || jsonb_build_object('lidos', jsonb_array_length(p_pessoas), 'sem_cpf', v_sem,
                                     'ignorados', coalesce((v_res ->> 'ignorados')::int, 0) + v_sem);
end $$;
comment on function public.ingestao_rhid_pessoas(uuid, jsonb) is
  '[servico] Pessoas do RHiD (GET /person) → usuários do relógio por CPF + vínculo automático (reaproveita a do Control iD).';

-- ----------------------------------------------------- batidas (AFD 671 de um equipamento)
-- p_equipamento: id do equipamento no RHiD (REP-P: idCompany + 99000000; coletor REP-P: "c<id>" para não colidir NSR).
-- p_marcacoes: saída de lerAfd (n8n/controlid/lib/afd.mjs): [{nsr, instante (com fuso -03:00), cpf | pis}].
-- Marcação já importada por outra fonte (mesmo CPF e instante: AFD enviado pelo site, REP por rede, ou o mesmo registro
-- no AFD do REP-P e no do coletor) conta como duplicada.
create or replace function public.ingestao_rhid_batidas(p_integracao uuid, p_equipamento text, p_marcacoes jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig        public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  v_equip   text := btrim(coalesce(p_equipamento, ''));
  v_itens   jsonb := '[]'::jsonb;
  x         jsonb;
  v_nsr     text;
  v_max     numeric;
  v_doc     text;
  v_inst    timestamptz;
  v_fuso    text;
  v_outra   int := 0;
  v_res     jsonb;
  v_atual   numeric;
begin
  if v_equip !~ '^c?[0-9]{1,12}$' then
    raise exception 'Equipamento inválido' using errcode = '22023';
  end if;
  p_marcacoes := public.ingestao_lista(p_marcacoes);
  if jsonb_array_length(p_marcacoes) > 2000 then
    raise exception 'Lote maior que 2000 itens' using errcode = '22023';
  end if;
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;
  for x in select value from jsonb_array_elements(p_marcacoes) loop
    if jsonb_typeof(x) <> 'object' then
      v_itens := v_itens || jsonb_build_array(x);  -- a ingestão conta como inválido
      continue;
    end if;
    v_nsr := regexp_replace(coalesce(public.ingestao_texto(x -> 'nsr'), public.ingestao_texto(x -> 'id_externo'), ''), '[^0-9]', '', 'g');
    v_nsr := case when v_nsr = '' then null else coalesce(nullif(ltrim(v_nsr, '0'), ''), '0') end;
    if v_nsr is not null and (v_max is null or v_nsr::numeric > v_max) then v_max := v_nsr::numeric; end if;
    -- já veio por outra fonte (mesmo CPF/PIS e instante, origem REP, outra integração da empresa)?
    v_doc := coalesce(public.rhid_documento(x -> 'cpf'), public.rhid_documento(x -> 'pis'));
    begin
      v_inst := case when x ? 'instante' then public.ingestao_ler_instante(x ->> 'instante', v_fuso, 'com_fuso')
                     else public.ingestao_ler_instante(x ->> 'instante_local', v_fuso, 'sem_fuso') end;
    exception when others then
      v_inst := null;
    end;
    if v_doc is not null and v_inst is not null and exists (
         select 1 from public.ponto_batidas b
          where b.empresa_id = ig.empresa_id and b.origem = 'controlid_rep'
            and b.pessoa_externa = v_doc and b.instante = v_inst
            and not (b.integracao_id = ig.id and b.id_externo = v_equip || '|' || v_nsr)) then
      v_outra := v_outra + 1;
      continue;
    end if;
    v_itens := v_itens || ((x - 'id_externo' - 'nsr')
                           || jsonb_build_object('id_externo', case when v_nsr is null then null else v_equip || '|' || v_nsr end));
  end loop;

  v_res := public.ingestao_controlid_batidas(ig.id, v_itens);

  -- cursor por equipamento: nunca regride
  if v_max is not null then
    select (i.cursor -> 'nsr_por_equipamento' ->> v_equip)::numeric into v_atual from public.integracoes i where i.id = ig.id;
    if v_atual is null or v_max > v_atual then
      update public.integracoes i
         set cursor = i.cursor || jsonb_build_object('nsr_por_equipamento',
                        coalesce(case when jsonb_typeof(i.cursor -> 'nsr_por_equipamento') = 'object'
                                      then i.cursor -> 'nsr_por_equipamento' end, '{}'::jsonb)
                        || jsonb_build_object(v_equip, v_max))
       where i.id = ig.id;
    end if;
  end if;

  return v_res || jsonb_build_object(
    'lidos', jsonb_array_length(p_marcacoes),
    'duplicados', coalesce((v_res ->> 'duplicados')::int, 0) + v_outra,
    'ja_importadas_por_outra_fonte', v_outra,
    'equipamento', v_equip,
    'ultimo_nsr', (select i.cursor -> 'nsr_por_equipamento' -> v_equip from public.integracoes i where i.id = ig.id),
    'cursor', (select i.cursor from public.integracoes i where i.id = ig.id));
end $$;
comment on function public.ingestao_rhid_batidas(uuid, text, jsonb) is
  '[servico] Marcações do AFD 671 de um equipamento do RHiD (id_externo equipamento|NSR) + cursor por equipamento.';

-- ------------------------------------------------- trocar um relógio controlid_rep por RHiD
-- O tipo da integração é imutável: cria a integração 'rhid', copia os usuários do relógio (CPF) com os vínculos
-- (automáticos e manuais) e desativa a antiga. As batidas já importadas ficam na antiga e continuam valendo no ponto.
create or replace function public.integracao_trocar_para_rhid(p_integracao uuid, p_nome text default null) returns uuid
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v    public.integracoes;
  v_id uuid;
begin
  select * into v from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not public.pode_administrar(v.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if v.tipo <> 'controlid_rep' then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:trocar_rhid:' || v.id::text, 0));
  -- já trocada antes? devolve a mesma
  select i.id into v_id from public.integracoes i
   where i.empresa_id = v.empresa_id and i.tipo = 'rhid' and i.parametros ->> 'substitui' = v.id::text
   order by i.criado_em limit 1;
  if v_id is null then
    insert into public.integracoes (empresa_id, tipo, nome, ativa, parametros, intervalo_minutos)
    values (v.empresa_id, 'rhid', coalesce(nullif(btrim(p_nome), ''), 'Relógio de ponto (RHiD)'), true,
            jsonb_build_object('substitui', v.id::text), greatest(v.intervalo_minutos, 60))
    returning id into v_id;
  end if;
  insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, registration, nome, cpf, pis,
                                         funcionario_id, vinculo, removido_no_equipamento, visto_em)
  select c.empresa_id, v_id, c.user_id_externo, c.registration, c.nome, c.cpf, c.pis,
         c.funcionario_id, c.vinculo, c.removido_no_equipamento, c.visto_em
    from public.controlid_usuarios c
   where c.integracao_id = v.id and c.user_id_externo ~ '^[0-9]{11}$'
  on conflict (integracao_id, user_id_externo) do nothing;
  update public.integracoes set ativa = false where id = v.id and ativa;
  return v_id;
end $$;
comment on function public.integracao_trocar_para_rhid(uuid, text) is
  '[api] Troca um relógio Control iD REP (rede ou arquivo) por uma integração RHiD, mantendo os vínculos (A M).';-- =====================================================================================================
-- 20261006000320_rhid_horarios.sql — horário previsto de cada dia vindo do RHiD (adendo RHiD §R.9)
-- O RHiD já sabe o horário contratual de cada pessoa, as folgas da escala e os feriados. O N8N ("MDG · RHiD · Importar")
-- lê a apuração do RHiD (GET /apuracao_ponto, uma pessoa por chamada) dos funcionários ligados e grava aqui, por dia:
--   previsto_minutos (0 em folga/feriado), horarios (entradas/saídas previstas), folga, feriado e o saldo do RHiD.
-- A apuração do ponto (ponto_calcular_dia, …0200) usa este previsto no lugar da jornada/escala, então o saldo do dia é
-- trabalhado − previsto, como no RHiD (folga/feriado trabalhado = tudo positivo).
-- Idempotente.
-- =====================================================================================================

create table if not exists public.ponto_previsto_externo (
  funcionario_id         uuid not null references public.funcionarios (id) on delete cascade,
  data                   date not null,
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  integracao_id          uuid references public.integracoes (id) on delete cascade,
  previsto_minutos       int not null check (previsto_minutos between 0 and 1440),
  horarios               time[] not null default '{}',
  folga                  boolean not null default false,
  feriado                text,
  saldo_externo_minutos  int,
  atualizado_em          timestamptz not null default now(),
  primary key (funcionario_id, data)
);
-- tolerância diária do horário do RHiD (lim_min_diario_horas_extras / _faltas; CLT = 10): diferença até ela zera o saldo
alter table public.ponto_previsto_externo add column if not exists tolerancia_extra_minutos int not null default 0
  check (tolerancia_extra_minutos between 0 and 120);
alter table public.ponto_previsto_externo add column if not exists tolerancia_falta_minutos int not null default 0
  check (tolerancia_falta_minutos between 0 and 120);
create index if not exists ponto_previsto_externo_empresa_idx on public.ponto_previsto_externo (empresa_id, data);
create index if not exists ponto_previsto_externo_integracao_idx on public.ponto_previsto_externo (integracao_id);
comment on table public.ponto_previsto_externo is
  '[api:leitura] Previsto do dia vindo do RHiD (horário contratual, folga, feriado); prevalece sobre jornada e escala.';

alter table public.ponto_previsto_externo enable row level security;
drop policy if exists ponto_previsto_externo_ler on public.ponto_previsto_externo;
create policy ponto_previsto_externo_ler on public.ponto_previsto_externo for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

-- tipo de execução novo (a lista também está na …0120, para a reaplicação das migrações)
alter table public.sync_execucoes drop constraint if exists sync_execucoes_tipo_check;
alter table public.sync_execucoes add constraint sync_execucoes_tipo_check
  check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                  'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                  'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento', 'tagme_importar',
                  'rhid_pessoas', 'rhid_batidas', 'rhid_horarios'));

-- Usado por ponto_calcular_dia (…0200). Sem linha → nulls (vale a jornada/escala).
-- (a assinatura ganhou as tolerâncias: recria; ponto_calcular_dia só a chama em tempo de execução)
do $$
begin
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.ponto_previsto_externo_dia(uuid, date)')
               and coalesce(array_length(p.proargnames, 1), 0) <> 6) then
    drop function public.ponto_previsto_externo_dia(uuid, date);
  end if;
end $$;
create or replace function public.ponto_previsto_externo_dia(p_funcionario uuid, p_data date,
  out previsto_minutos int, out horarios time[], out tolerancia_extra_minutos int, out tolerancia_falta_minutos int)
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select x.previsto_minutos, x.horarios, x.tolerancia_extra_minutos, x.tolerancia_falta_minutos
    from public.ponto_previsto_externo x
   where x.funcionario_id = p_funcionario and x.data = p_data
$$;
comment on function public.ponto_previsto_externo_dia(uuid, date) is
  '[interno] Previsto do dia vindo do RHiD (minutos, horários, tolerâncias) — null se não houver.';

-- CPFs do RHiD ligados a funcionário (o N8N só pede a apuração desses).
create or replace function public.ingestao_rhid_vinculados(p_integracao uuid) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
begin
  return coalesce((
    select jsonb_agg(c.user_id_externo order by c.user_id_externo)
      from public.controlid_usuarios c
      join public.funcionarios f on f.id = c.funcionario_id
     where c.integracao_id = ig.id and c.funcionario_id is not null and f.ativo), '[]'::jsonb);
end $$;
comment on function public.ingestao_rhid_vinculados(uuid) is
  '[servico] CPFs (user_id_externo) do RHiD ligados a funcionário ativo.';

-- p_dias: [{cpf, data, previsto_minutos, horarios: ["08:00", …], folga, feriado, saldo_minutos, tolerancia_extra_minutos,
--           tolerancia_falta_minutos}] ou {cpf, data, sem_horario: true} (pessoa sem horário no RHiD: apaga o previsto do dia
--           e volta a valer a jornada/escala). Grava só o que mudou e reapura os dias alterados. Atualiza cursor.horarios_em.
create or replace function public.ingestao_rhid_horarios(p_integracao uuid, p_dias jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig        public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  x         jsonb;
  v_cpf     text;
  v_func    uuid;
  v_data    date;
  v_prev    int;
  v_hor     time[];
  v_folga   boolean;
  v_feriado text;
  v_saldo   int;
  v_tol_e   int;
  v_tol_f   int;
  v_sem_hor boolean;
  v_apag    int := 0;
  v_mudou   boolean;
  v_grav    int := 0;
  v_iguais  int := 0;
  v_sem     int := 0;
  v_inval   int := 0;
  r         record;
begin
  p_dias := public.ingestao_lista(p_dias);
  if jsonb_array_length(p_dias) > 20000 then
    raise exception 'Lista maior que 20000 dias' using errcode = '22023';
  end if;
  create temp table if not exists pg_temp.rhid_horarios_alterados (funcionario_id uuid, data date) on commit drop;
  delete from pg_temp.rhid_horarios_alterados where true;  -- Supabase (pg_safeupdate) recusa DELETE sem WHERE

  for x in select value from jsonb_array_elements(p_dias) loop
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item'; end if;
      v_cpf := public.rhid_documento(x -> 'cpf');
      v_data := (x ->> 'data')::date;
      v_prev := (x ->> 'previsto_minutos')::int;
      v_folga := coalesce((x ->> 'folga')::boolean, false);
      v_feriado := nullif(btrim(coalesce(x ->> 'feriado', '')), '');
      v_saldo := (x ->> 'saldo_minutos')::int;
      v_sem_hor := coalesce((x ->> 'sem_horario')::boolean, false);
      v_tol_e := least(greatest(coalesce((x ->> 'tolerancia_extra_minutos')::int, 0), 0), 120);
      v_tol_f := least(greatest(coalesce((x ->> 'tolerancia_falta_minutos')::int, 0), 0), 120);
      if v_sem_hor then v_prev := 0; end if;
      v_hor := coalesce((select array_agg(h::time order by o)
                           from jsonb_array_elements_text(case when jsonb_typeof(x -> 'horarios') = 'array'
                                                               then x -> 'horarios' else '[]'::jsonb end)
                                with ordinality t(h, o)), '{}');
      if v_cpf is null or v_data is null or v_prev is null or v_prev < 0 or v_prev > 1440 then raise exception 'item'; end if;
      if v_folga or v_feriado is not null then v_prev := 0; end if;
    exception when others then
      v_inval := v_inval + 1;
      continue;
    end;

    select c.funcionario_id into v_func
      from public.controlid_usuarios c
     where c.integracao_id = ig.id and c.user_id_externo = v_cpf and c.funcionario_id is not null;
    if v_func is null then
      v_sem := v_sem + 1;
      continue;
    end if;

    if v_sem_hor then
      delete from public.ponto_previsto_externo p where p.funcionario_id = v_func and p.data = v_data;
      if found then
        insert into pg_temp.rhid_horarios_alterados values (v_func, v_data);
        v_apag := v_apag + 1;
      else
        v_iguais := v_iguais + 1;
      end if;
      continue;
    end if;

    select (p.previsto_minutos, p.horarios, p.folga, p.feriado, p.saldo_externo_minutos,
            p.tolerancia_extra_minutos, p.tolerancia_falta_minutos)
           is distinct from (v_prev, v_hor, v_folga, v_feriado, v_saldo, v_tol_e, v_tol_f)
      into v_mudou
      from public.ponto_previsto_externo p
     where p.funcionario_id = v_func and p.data = v_data;
    if v_mudou is false then
      v_iguais := v_iguais + 1;
      continue;
    end if;

    insert into public.ponto_previsto_externo as p (
      funcionario_id, data, empresa_id, integracao_id, previsto_minutos, horarios, folga, feriado, saldo_externo_minutos,
      tolerancia_extra_minutos, tolerancia_falta_minutos)
    values (v_func, v_data, ig.empresa_id, ig.id, v_prev, v_hor, v_folga, v_feriado, v_saldo, v_tol_e, v_tol_f)
    on conflict (funcionario_id, data) do update set
      integracao_id = excluded.integracao_id, previsto_minutos = excluded.previsto_minutos, horarios = excluded.horarios,
      folga = excluded.folga, feriado = excluded.feriado, saldo_externo_minutos = excluded.saldo_externo_minutos,
      tolerancia_extra_minutos = excluded.tolerancia_extra_minutos,
      tolerancia_falta_minutos = excluded.tolerancia_falta_minutos, atualizado_em = now();
    insert into pg_temp.rhid_horarios_alterados values (v_func, v_data);
    v_grav := v_grav + 1;
  end loop;

  for r in select a.funcionario_id, min(a.data) as ini, max(a.data) as fim
             from pg_temp.rhid_horarios_alterados a group by a.funcionario_id loop
    perform public.ponto_apurar(r.funcionario_id, r.ini, r.fim);
  end loop;

  update public.integracoes i set cursor = i.cursor || jsonb_build_object('horarios_em', now()) where i.id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_dias), 'gravados', v_grav, 'apagados', v_apag, 'iguais', v_iguais,
                            'sem_funcionario', v_sem, 'invalidos', v_inval,
                            'ignorados', v_sem + v_inval,
                            'funcionarios_reapurados', (select count(distinct a.funcionario_id) from pg_temp.rhid_horarios_alterados a));
end $$;
comment on function public.ingestao_rhid_horarios(uuid, jsonb) is
  '[servico] Previsto por dia da apuração do RHiD (horário, folga, feriado) → ponto_previsto_externo + reapuração.';-- =====================================================================================================
-- 20261006000330_ocorrencias_ponto.sql — faltas e atrasos nas ocorrências
-- Ocorrências passam a mostrar, além de advertências e suspensões:
--   · faltas: as registradas no sistema (funcionario_faltas, com/sem justificativa) e os dias de ponto "ausente"
--     (previsto pela jornada / horário do RHiD, encerrado, sem batida) que ainda não foram registrados;
--   · atrasos: ponto_dias.atraso_minutos > 0 — 1ª batida × entrada prevista (deslocada para a chegada da escala do dia).
-- Idempotente.
-- =====================================================================================================

-- "4h00" a partir de minutos (para o previsto de um dia de falta)
create or replace function public.minutos_em_horas(p_minutos int) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when p_minutos is null then null
              else (p_minutos / 60)::text || 'h' || lpad((p_minutos % 60)::text, 2, '0') end
$$;
comment on function public.minutos_em_horas(int) is '[interno] Minutos em texto "7h20".';

commit;
select 'parte 20 de 21 instalada' as resultado;

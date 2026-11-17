-- =====================================================================================================
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
  '[api] Troca um relógio Control iD REP (rede ou arquivo) por uma integração RHiD, mantendo os vínculos (A M).';

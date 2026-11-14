-- Meu Dia de Gerente — instalação do banco, PARTE 11 DE 17.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000220_comissoes.sql, 20261006000230_ingestao.sql. Não edite à mão.

begin;
-- ================================================================ detalhe (adendo E.3.4)
create or replace function public.comissao_detalhe(p_fechamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return jsonb_build_object(
    'fechamento', to_jsonb(fc),
    'servico_dias', (
      select jsonb_agg(jsonb_build_object('data', g::date, 'servico_zig_centavos',
               coalesce((select sum(i.valor_total) from public.zig_vendas_itens i
                          where i.empresa_id = fc.empresa_id and i.tipo = 'Tip' and i.data_operacao = g::date
                            and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo)), 0)::bigint)
               order by g)
        from generate_series(fc.data_inicio::timestamp, fc.data_fim::timestamp, interval '1 day') g),
    'dias', coalesce((
      select jsonb_agg(jsonb_build_object(
               'data', rd.data, 'servico_zig_centavos', rd.servico_zig_centavos, 'ajuste_centavos', rd.ajuste_centavos,
               'servico_bruto_centavos', rd.servico_bruto_centavos, 'retencao_centavos', rd.retencao_centavos,
               'base_centavos', rd.base_centavos, 'soma_pontos', rd.soma_pontos, 'participantes', rd.participantes,
               'sem_presenca', rd.sem_presenca, 'sem_participantes', rd.sem_participantes,
               'rateio', coalesce((
                 select jsonb_agg(jsonb_build_object('item_id', ri.item_id, 'pontos', ri.pontos,
                                                     'valor_centavos', ri.valor_centavos, 'fallback', ri.fallback)
                                  order by it.funcionario_nome collate "C", (it.tipo = 'extra'),
                                           coalesce(it.funcionario_id, it.extra_id) nulls last, it.id)
                   from public.comissao_rateio_itens_dia ri join public.comissao_itens it on it.id = ri.item_id
                  where ri.fechamento_id = rd.fechamento_id and ri.data = rd.data), '[]'::jsonb))
             order by rd.data)
        from public.comissao_rateio_dias rd where rd.fechamento_id = fc.id), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', it.id, 'tipo', it.tipo, 'funcionario_id', it.funcionario_id, 'extra_id', it.extra_id,
               'nome', it.funcionario_nome, 'cargo', it.cargo, 'incluido', it.incluido, 'pontos', it.pontos,
               'pontos_manual', it.pontos_manual, 'dias_presentes', it.dias_presentes,
               'pontos_efetivos', it.pontos_efetivos, 'valor_centavos', it.valor_centavos,
               'entrada', case
                 when it.tipo = 'extra' then coalesce((
                   select jsonb_agg(jsonb_build_object('data', d.data, 'presente', true, 'pontos', d.pontos) order by d.data)
                     from public.diarias d
                    where d.extra_id = it.extra_id and d.data between fc.data_inicio and fc.data_fim), '[]'::jsonb)
                 when it.funcionario_id is null then '[]'::jsonb
                 else (
                   select jsonb_agg(jsonb_build_object(
                            'data', g::date,
                            'presente', coalesce((select pd.batidas_validas > 0 from public.ponto_dias pd
                                                   where pd.funcionario_id = it.funcionario_id and pd.data = g::date), false),
                            'pontos', coalesce(public.comissao_pontos_vigentes(it.funcionario_id, g::date), 0))
                          order by g)
                     from generate_series(fc.data_inicio::timestamp, fc.data_fim::timestamp, interval '1 day') g)
               end)
             order by it.funcionario_nome collate "C", (it.tipo = 'extra'), coalesce(it.funcionario_id, it.extra_id) nulls last, it.id)
        from public.comissao_itens it where it.fechamento_id = fc.id), '[]'::jsonb));
end $$;
comment on function public.comissao_detalhe(uuid) is '[api] Fechamento com rateio por dia e entradas da prévia (G A M).';-- =====================================================================================================
-- 20261006000230_ingestao.sql — backend-2
-- RPCs de ingestão chamadas pelo N8N com service_role (todas [servico], idempotentes).
-- Contrato: §10.8, §11.2, §11.4–§11.6.
-- =====================================================================================================

-- ================================================================ auxiliares
create or replace function public.ingestao_integracao_validar(p_integracao uuid, p_tipos text[])
returns public.integracoes language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare i public.integracoes;
begin
  select * into i from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not i.ativa then raise exception 'Integração inativa' using errcode = '22023'; end if;
  if not (i.tipo = any (p_tipos)) then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  return i;
end $$;
comment on function public.ingestao_integracao_validar(uuid, text[]) is '[interno] Integração existe, ativa e do tipo certo (§11.2).';

-- Lê um instante: ISO com fuso (Z/offset) como veio; sem fuso, no fuso informado.
create or replace function public.ingestao_ler_instante(p_texto text, p_fuso text, p_exigir text default null)
returns timestamptz language plpgsql stable set search_path = public, extensions, pg_temp as $$
declare v_com_fuso boolean;
begin
  if p_texto is null or btrim(p_texto) = '' then return null; end if;
  p_texto := btrim(p_texto);
  v_com_fuso := p_texto ~* '(z|[+-][0-9]{2}(:?[0-9]{2})?)$' and p_texto ~ '[T ][0-9]{2}:[0-9]{2}';
  if p_exigir = 'com_fuso' and not v_com_fuso then raise exception 'instante sem fuso'; end if;
  if p_exigir = 'sem_fuso' and v_com_fuso then raise exception 'instante_local com fuso'; end if;
  if v_com_fuso then return p_texto::timestamptz; end if;
  return p_texto::timestamp at time zone p_fuso;
end $$;
comment on function public.ingestao_ler_instante(text, text, text) is '[interno] Converte texto ISO em timestamptz (sem fuso = fuso da empresa).';

create or replace function public.ingestao_centavos(p_valor jsonb)
returns bigint language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when p_valor is null or p_valor = 'null'::jsonb or btrim(p_valor #>> '{}') = '' then 0
              else round((p_valor #>> '{}')::numeric)::bigint end
$$;
comment on function public.ingestao_centavos(jsonb) is '[interno] Valor da Zig (centavos) → bigint; null → 0.';

create or replace function public.ingestao_texto(p_valor jsonb)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select nullif(btrim(p_valor #>> '{}'), '')
$$;
comment on function public.ingestao_texto(jsonb) is '[interno] jsonb escalar → texto aparado (vazio → null).';

create or replace function public.ingestao_loja_validar(p_empresa uuid, p_loja text)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_loja is null or not exists (select 1 from public.zig_lojas l where l.empresa_id = p_empresa and l.loja_id_externo = p_loja) then
    raise exception 'Loja não encontrada' using errcode = 'P0002';
  end if;
end $$;
comment on function public.ingestao_loja_validar(uuid, text) is '[interno] Loja existe em zig_lojas da empresa.';

create or replace function public.ingestao_lista(p_itens jsonb)
returns jsonb language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_itens is null or p_itens = 'null'::jsonb then return '[]'::jsonb; end if;
  if jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  return p_itens;
end $$;
comment on function public.ingestao_lista(jsonb) is '[interno] Garante array JSON.';

-- ======================================================== Control iD: batidas (§11.4)
create or replace function public.ingestao_controlid_batidas(p_integracao uuid, p_batidas jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig          public.integracoes;
  v_fuso      text;
  v_eventos   jsonb;
  v_rep       boolean;
  x           jsonb;
  v_idx       int := -1;
  v_lidos     int := 0;
  v_gravados  int := 0;
  v_ignorados int := 0;
  v_dups      int := 0;
  v_semfunc   int := 0;
  v_dias      int := 0;
  v_erros     jsonb := '[]'::jsonb;
  v_nerros    int := 0;
  v_idext     text;
  v_pessoa    text;
  v_instante  timestamptz;
  v_func      uuid;
  v_id        uuid;
  v_data      date;
  v_max_id    numeric;
  v_max_idtxt text;
  v_max_inst  timestamptz;
  v_cursor    jsonb;
  v_afetados  text[] := '{}';
  v_par       text;
  v_motivo    text;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  p_batidas := public.ingestao_lista(p_batidas);
  if jsonb_array_length(p_batidas) > 2000 then
    raise exception 'Lote maior que 2000 itens' using errcode = '22023';
  end if;
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;
  v_rep := ig.tipo = 'controlid_rep';
  v_eventos := coalesce(ig.parametros -> 'eventos_validos', '[7]'::jsonb);
  if jsonb_typeof(v_eventos) <> 'array' then v_eventos := '[7]'::jsonb; end if;

  for x in select value from jsonb_array_elements(p_batidas) loop
    v_idx := v_idx + 1;
    v_lidos := v_lidos + 1;
    v_motivo := null;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      v_idext := coalesce(public.ingestao_texto(x -> 'id_externo'), public.ingestao_texto(x -> 'nsr'));
      if v_idext is null then raise exception 'id_externo ausente'; end if;
      if v_rep and v_idext ~ '^[0-9]+$' then
        v_idext := coalesce(nullif(ltrim(v_idext, '0'), ''), '0');
      end if;
      if (x ? 'instante' and x -> 'instante' <> 'null'::jsonb) = (x ? 'instante_local' and x -> 'instante_local' <> 'null'::jsonb) then
        raise exception 'informe instante ou instante_local';
      end if;
      begin
        if x ? 'instante' and x -> 'instante' <> 'null'::jsonb then
          v_instante := public.ingestao_ler_instante(x ->> 'instante', v_fuso, 'com_fuso');
        else
          v_instante := public.ingestao_ler_instante(x ->> 'instante_local', v_fuso, 'sem_fuso');
        end if;
      exception when others then
        raise exception 'instante inválido';
      end;
      if v_instante is null then raise exception 'instante inválido'; end if;

      if v_rep then
        v_pessoa := regexp_replace(coalesce(public.ingestao_texto(x -> 'cpf'), public.ingestao_texto(x -> 'pis'), ''), '[^0-9]', '', 'g');
        if v_pessoa = '' then raise exception 'sem CPF/PIS'; end if;
      else
        v_pessoa := public.ingestao_texto(x -> 'user_id');
        if x ? 'evento' and x -> 'evento' <> 'null'::jsonb and not (v_eventos @> jsonb_build_array(x -> 'evento')
                                                                 or v_eventos @> jsonb_build_array((x ->> 'evento')::numeric)) then
          v_motivo := 'evento';
        elsif v_pessoa is null or v_pessoa = '0' then
          v_motivo := 'sem_usuario';
        end if;
      end if;
    exception when others then
      v_ignorados := v_ignorados + 1;
      v_nerros := v_nerros + 1;
      if v_nerros <= 20 then
        v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm);
      end if;
      continue;
    end;

    -- cursor considera todo item bem formado (inclusive ignorados por evento e já existentes)
    if v_idext ~ '^[0-9]+$' then
      if v_max_id is null or v_idext::numeric > v_max_id then v_max_id := v_idext::numeric; end if;
    elsif v_max_idtxt is null or v_idext > v_max_idtxt then
      v_max_idtxt := v_idext;
    end if;
    if v_max_inst is null or v_instante > v_max_inst then v_max_inst := v_instante; end if;

    if v_motivo is not null then
      v_ignorados := v_ignorados + 1;
      continue;
    end if;

    -- resolve funcionário (§7.1)
    v_func := null;
    if v_rep then
      select f.id into v_func from public.funcionarios f
       where f.empresa_id = ig.empresa_id
         and (case when x ? 'cpf' and public.ingestao_texto(x -> 'cpf') is not null then f.cpf else f.pis end) = v_pessoa
       limit 1;
    else
      select cu.funcionario_id into v_func from public.controlid_usuarios cu
       where cu.integracao_id = ig.id and cu.user_id_externo = v_pessoa;
    end if;

    insert into public.ponto_batidas (empresa_id, funcionario_id, integracao_id, origem, id_externo, pessoa_externa, instante)
    values (ig.empresa_id, v_func, ig.id, ig.tipo, v_idext, v_pessoa, v_instante)
    on conflict (integracao_id, id_externo) do nothing
    returning id, data_trabalho into v_id, v_data;

    if v_id is null then
      v_dups := v_dups + 1;
    else
      v_gravados := v_gravados + 1;
      if v_func is null then
        v_semfunc := v_semfunc + 1;
      else
        v_par := v_func::text || '|' || v_data::text;
        if not (v_par = any (v_afetados)) then v_afetados := v_afetados || v_par; end if;
      end if;
    end if;
    v_id := null;
  end loop;

  -- apura cada (funcionário, dia) afetado uma vez
  foreach v_par in array v_afetados loop
    v_dias := v_dias + public.ponto_apurar(split_part(v_par, '|', 1)::uuid, split_part(v_par, '|', 2)::date,
                                           split_part(v_par, '|', 2)::date);
  end loop;

  -- cursor (máximos)
  v_cursor := ig.cursor;
  if v_rep then
    if v_max_id is not null and (v_cursor ->> 'ultimo_nsr' is null or v_max_id > (v_cursor ->> 'ultimo_nsr')::numeric) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_nsr', v_max_id);
    end if;
  else
    if v_max_id is not null and (v_cursor ->> 'ultimo_id' is null or (v_cursor ->> 'ultimo_id') !~ '^[0-9]+$'
                                 or v_max_id > (v_cursor ->> 'ultimo_id')::numeric) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_id', v_max_id::text);
    elsif v_max_id is null and v_max_idtxt is not null
          and (v_cursor ->> 'ultimo_id' is null or v_max_idtxt > (v_cursor ->> 'ultimo_id')) then
      v_cursor := v_cursor || jsonb_build_object('ultimo_id', v_max_idtxt);
    end if;
  end if;
  if v_max_inst is not null and (v_cursor ->> 'ultimo_instante' is null
                                 or v_max_inst > (v_cursor ->> 'ultimo_instante')::timestamptz) then
    v_cursor := v_cursor || jsonb_build_object('ultimo_instante', v_max_inst);
  end if;
  if v_cursor is distinct from ig.cursor then
    update public.integracoes set cursor = v_cursor where id = ig.id;
  end if;

  return jsonb_build_object('lidos', v_lidos, 'gravados', v_gravados, 'ignorados', v_ignorados, 'duplicados', v_dups,
                            'sem_funcionario', v_semfunc, 'dias_apurados', v_dias, 'cursor', v_cursor)
         || case when v_nerros > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_controlid_batidas(uuid, jsonb) is '[servico] Ingestão idempotente de batidas Control iD (§11.4).';

-- ======================================================== Zig (§11.5)
create or replace function public.ingestao_zig_lojas(p_integracao uuid, p_lojas jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v_idx int := -1; v_lidos int := 0; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_erros jsonb := '[]'::jsonb; v_id text; v_nome text; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  p_lojas := public.ingestao_lista(p_lojas);
  for x in select value from jsonb_array_elements(p_lojas) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    v_id := case when jsonb_typeof(x) = 'object' then public.ingestao_texto(x -> 'id') end;
    v_nome := case when jsonb_typeof(x) = 'object' then coalesce(public.ingestao_texto(x -> 'name'), public.ingestao_texto(x -> 'nome')) end;
    if v_id is null then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', 'id ausente'); end if;
      continue;
    end if;
    insert into public.zig_lojas as l (empresa_id, integracao_id, loja_id_externo, nome, visto_em)
    values (ig.empresa_id, ig.id, v_id, coalesce(v_nome, v_id), public.agora())
    on conflict (empresa_id, loja_id_externo) do update
      set nome = coalesce(v_nome, l.nome), integracao_id = excluded.integracao_id, visto_em = excluded.visto_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_ins + v_atu, 'ignorados', v_ign, 'inseridos', v_ins, 'atualizados', v_atu)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_lojas(uuid, jsonb) is '[servico] Upsert das lojas da Zig (preserva sincronizar).';

create or replace function public.ingestao_zig_tipo(p_tipo text)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select coalesce((select t from unnest(array['Normal', 'Couvert', 'ZigCard', 'Entrance', 'Tip']) t
                    where lower(t) = lower(btrim(p_tipo))), 'Outro')
$$;
comment on function public.ingestao_zig_tipo(text) is '[interno] type da Zig → tipo (desconhecido = Outro).';

create or replace function public.ingestao_zig_saida_produtos(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; v_fuso text; x jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0;
  v_rem int; v_erros jsonb := '[]'::jsonb; v_unit bigint; v_qtd numeric; v_desc bigint; v_tipo_orig text;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;

  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_vendas_itens:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_vendas_itens where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;

  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'transactionId') is null then raise exception 'transactionId ausente'; end if;
      v_unit := public.ingestao_centavos(x -> 'unitValue');
      v_qtd := coalesce((public.ingestao_texto(x -> 'count'))::numeric, 0);
      v_desc := public.ingestao_centavos(x -> 'discountValue');
      v_tipo_orig := public.ingestao_texto(x -> 'type');
      insert into public.zig_vendas_itens (
        empresa_id, loja_id_externo, data_operacao, transaction_id, transaction_date, event_id, event_date, invoice_id,
        product_id, product_sku, product_name, product_category, tipo, tipo_original, unit_value, quantidade,
        fractional_amount, fraction_unit, discount_value, valor_total, employee_name, additions)
      values (
        ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'transactionId'),
        public.ingestao_ler_instante(x ->> 'transactionDate', v_fuso),
        public.ingestao_texto(x -> 'eventId'),
        left(public.ingestao_texto(x -> 'eventDate'), 10)::date,
        public.ingestao_texto(x -> 'invoiceId'),
        public.ingestao_texto(x -> 'productId'), public.ingestao_texto(x -> 'productSku'),
        public.ingestao_texto(x -> 'productName'), public.ingestao_texto(x -> 'productCategory'),
        public.ingestao_zig_tipo(v_tipo_orig), v_tipo_orig, v_unit, v_qtd,
        (public.ingestao_texto(x -> 'fractionalAmount'))::numeric, public.ingestao_texto(x -> 'fractionUnit'),
        v_desc, round(v_unit * v_qtd)::bigint - v_desc,
        public.ingestao_texto(x -> 'employeeName'),
        case when jsonb_typeof(x -> 'additions') = 'array' then x -> 'additions' else '[]'::jsonb end);
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;

  if ig.cursor ->> 'ultimo_dia' is null or p_data > (ig.cursor ->> 'ultimo_dia')::date then
    update public.integracoes set cursor = cursor || jsonb_build_object('ultimo_dia', p_data) where id = ig.id;
  end if;

  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_saida_produtos(uuid, text, date, jsonb) is '[servico] Substitui os itens vendidos do dia/loja (/erp/saida-produtos).';

create or replace function public.ingestao_zig_faturamento(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
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
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_faturamento:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_faturamento where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'paymentId') is null then raise exception 'paymentId ausente'; end if;
      insert into public.zig_faturamento (empresa_id, loja_id_externo, data_operacao, event_id, event_date, payment_id,
                                          payment_name, valor)
      values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'eventId'),
              left(public.ingestao_texto(x -> 'eventDate'), 10)::date,
              (public.ingestao_texto(x -> 'paymentId'))::int,
              coalesce(public.ingestao_texto(x -> 'paymentName'), 'Forma ' || public.ingestao_texto(x -> 'paymentId')),
              public.ingestao_centavos(coalesce(x -> 'value', x -> 'valor', x -> 'totalValue')));
      v_grav := v_grav + 1;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_faturamento(uuid, text, date, jsonb) is '[servico] Substitui o faturamento do dia/loja (/erp/faturamento).';

create or replace function public.ingestao_zig_faturamento_bandeiras(p_integracao uuid, p_loja text, p_data date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; x jsonb; v jsonb; v_idx int := -1; v_lidos int := 0; v_grav int := 0; v_ign int := 0; v_rem int;
  v_erros jsonb := '[]'::jsonb; v_valores jsonb;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['zig']);
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  perform public.ingestao_loja_validar(ig.empresa_id, p_loja);
  p_itens := public.ingestao_lista(p_itens);
  -- (revisão 2) Serializa cargas simultâneas do mesmo dia/loja (agendador × "Sincronizar agora"): sem isto, duas
  -- transações apagavam o dia ao mesmo tempo e AMBAS inseriam o lote → itens duplicados (serviço e comissão em dobro).
  perform pg_advisory_xact_lock(hashtextextended('mdg:zig_faturamento_bandeiras:' || ig.empresa_id || ':' || p_loja || ':' || p_data, 0));
  delete from public.zig_faturamento_bandeiras
   where empresa_id = ig.empresa_id and loja_id_externo = p_loja and data_operacao = p_data;
  get diagnostics v_rem = row_count;
  for x in select value from jsonb_array_elements(p_itens) loop
    v_idx := v_idx + 1; v_lidos := v_lidos + 1;
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item inválido'; end if;
      if public.ingestao_texto(x -> 'paymentId') is null then raise exception 'paymentId ausente'; end if;
      v_valores := case when jsonb_typeof(x -> 'values') = 'array' then x -> 'values' else '[]'::jsonb end;
      for v in select value from jsonb_array_elements(v_valores) loop
        insert into public.zig_faturamento_bandeiras (empresa_id, loja_id_externo, data_operacao, event_id, payment_id,
                                                      payment_name, card_brand, valor)
        values (ig.empresa_id, p_loja, p_data, public.ingestao_texto(x -> 'eventId'),
                (public.ingestao_texto(x -> 'paymentId'))::int, public.ingestao_texto(x -> 'paymentName'),
                coalesce(public.ingestao_texto(v -> 'cardBrand'), public.ingestao_texto(v -> 'brand')),
                public.ingestao_centavos(coalesce(v -> 'totalValue', v -> 'value', v -> 'valor')));
        v_grav := v_grav + 1;
      end loop;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then v_erros := v_erros || jsonb_build_object('indice', v_idx, 'motivo', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('lidos', v_lidos, 'gravados', v_grav, 'ignorados', v_ign, 'removidos', v_rem)
         || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;
end $$;
comment on function public.ingestao_zig_faturamento_bandeiras(uuid, text, date, jsonb) is '[servico] Substitui o faturamento por bandeira do dia/loja (cada values[] vira uma linha).';

commit;
select 'parte 11 de 17 instalada' as resultado;

-- Meu Dia de Gerente — instalação do banco, PARTE 19 DE 20.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000290_comissao_presenca.sql, 20261006000300_importar_afd.sql, 20261006000310_rhid.sql. Não edite à mão.

begin;
create or replace function public.extras_importar(p_itens jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_linha jsonb; v_n int := 0; v_criados int := 0; v_atualizados int := 0; v_dias int := 0;
  v_erros jsonb := '[]'; v_pend uuid[] := '{}'; v_nome text; v_doc text; v_pontos numeric; v_valor numeric; v_extra uuid;
  v_qtd int; v_dia jsonb; v_data date; v_dpontos numeric; v_dvalor numeric; x public.extras; v_dias_linha int;
  v_criou boolean; v_diaria public.diarias; v_tem_pontos boolean; v_pend_dia boolean; v_msg text;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'Lista de extras inválida' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) > 1000 then
    raise exception 'Máximo de 1000 linhas por importação' using errcode = '22023';
  end if;

  for v_linha in select e from jsonb_array_elements(p_itens) e loop
    v_n := v_n + 1;
    begin
      if jsonb_typeof(v_linha) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
      v_nome := nullif(btrim(coalesce(v_linha ->> 'nome', '')), '');
      if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
      v_doc := nullif(btrim(coalesce(v_linha ->> 'documento', '')), '');
      v_tem_pontos := v_linha ? 'pontos' and v_linha -> 'pontos' <> 'null'::jsonb;
      v_pontos := public.extras_imp_num(v_linha -> 'pontos', 'Pontos inválidos');
      if v_pontos is not null and (v_pontos < 0 or v_pontos > 9999.99 or v_pontos <> round(v_pontos, 2)) then
        raise exception 'Pontos inválidos' using errcode = '22023';
      end if;
      v_tem_pontos := v_pontos is not null;
      v_valor := public.extras_imp_num(v_linha -> 'valor_diaria_centavos', 'Valor inválido');
      if v_valor is not null and (v_valor < 0 or v_valor > 100000000 or v_valor <> round(v_valor)) then
        raise exception 'Valor inválido' using errcode = '22023';
      end if;
      if v_linha ? 'dias_trabalhados' and v_linha -> 'dias_trabalhados' <> 'null'::jsonb
         and jsonb_typeof(v_linha -> 'dias_trabalhados') <> 'array' then
        raise exception 'Linha inválida' using errcode = '22023';
      end if;

      -- casamento: documento normalizado; senão nome normalizado (entre os sem documento, quando há documento)
      v_extra := null;
      if v_doc is not null then
        select x2.id into v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_documento(x2.documento) = public.extras_normalizar_documento(v_doc)
         order by x2.criado_em, x2.id limit 1;
      end if;
      if v_extra is null then
        select count(*), min(x2.id::text)::uuid into v_qtd, v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_nome(x2.nome) = public.extras_normalizar_nome(v_nome)
           and (v_doc is null or x2.documento is null);
        if v_qtd > 1 then
          raise exception 'Mais de um extra com este nome: informe o documento' using errcode = '22023';
        end if;
      end if;

      v_criou := v_extra is null;
      if v_criou then
        insert into public.extras (empresa_id, nome, funcao, telefone, documento, pontos_padrao, pontos_pendente,
                                   valor_diaria_centavos, criado_por)
        values (v_empresa, v_nome, nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''),
                nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), v_doc, coalesce(v_pontos, 0), not v_tem_pontos,
                v_valor::bigint, public.meu_perfil_id())
        returning id into v_extra;
      else
        update public.extras e
           set funcao = coalesce(nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''), e.funcao),
               telefone = coalesce(nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), e.telefone),
               documento = coalesce(v_doc, e.documento),
               valor_diaria_centavos = coalesce(v_valor::bigint, e.valor_diaria_centavos),
               ativo = true
         where e.id = v_extra;
        if v_tem_pontos then perform public.extra_definir_pontuacao(v_extra, v_pontos); end if;
      end if;
      select * into x from public.extras where id = v_extra;

      v_dias_linha := 0;
      for v_dia in select d from jsonb_array_elements(coalesce(nullif(v_linha -> 'dias_trabalhados', 'null'::jsonb), '[]')) d loop
        if jsonb_typeof(v_dia) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
        v_data := public.extras_imp_data(v_dia -> 'data');
        if v_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
        v_dpontos := public.extras_imp_num(v_dia -> 'pontos', 'Pontos inválidos');
        v_dvalor := public.extras_imp_num(v_dia -> 'valor_centavos', 'Valor inválido');
        if v_dvalor is not null and v_dvalor <> round(v_dvalor) then raise exception 'Valor inválido' using errcode = '22023'; end if;
        v_pend_dia := v_dpontos is null and x.pontos_pendente;
        v_dpontos := case when v_pend_dia then 0 else coalesce(v_dpontos, x.pontos_padrao) end;
        v_dvalor := coalesce(v_dvalor, x.valor_diaria_centavos);
        perform public.diaria_validar_valores(v_empresa, v_data, v_dpontos, v_dvalor::bigint, true);
        perform public.diaria_checar_trava(v_empresa, v_data);
        select * into v_diaria from public.diarias where extra_id = x.id and data = v_data;
        if v_diaria.id is null then
          insert into public.diarias (empresa_id, tipo, extra_id, pessoa_nome, data, funcao, pontos, pontos_pendente,
                                      valor_centavos, criado_por, criado_por_nome)
          values (v_empresa, 'extra', x.id, x.nome, v_data, x.funcao, v_dpontos, v_pend_dia, v_dvalor::bigint,
                  public.meu_perfil_id(), public.ponto_nome_autor());
        else
          update public.diarias set pontos = v_dpontos, pontos_pendente = v_pend_dia, valor_centavos = v_dvalor::bigint
           where id = v_diaria.id;
        end if;
        v_dias_linha := v_dias_linha + 1;
      end loop;

      v_dias := v_dias + v_dias_linha;
      if v_criou then v_criados := v_criados + 1; else v_atualizados := v_atualizados + 1; end if;
      select * into x from public.extras where id = v_extra;
      if x.pontos_pendente and not (x.id = any (v_pend)) then v_pend := v_pend || x.id; end if;
      if not x.pontos_pendente then v_pend := array_remove(v_pend, x.id); end if;
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v_erros := v_erros || jsonb_build_object('linha', v_n, 'mensagem', v_msg);
    end;
  end loop;

  return jsonb_build_object('lidos', v_n, 'criados', v_criados, 'atualizados', v_atualizados, 'dias_lancados', v_dias,
                            'pendentes_pontuacao', coalesce(array_length(v_pend, 1), 0), 'erros', v_erros);
end $$;
comment on function public.extras_importar(jsonb, uuid) is
  '[api] Importa extras em lote (upsert por documento ou nome) com dias trabalhados; sem pontos = pontuação pendente (G A M).';-- =====================================================================================================
-- 20261006000300_importar_afd.sql — full-stack (RHiD / arquivo AFD)
-- Importação do AFD pelo site: o RHiD (nuvem da Control iD) exporta o AFD do relógio REP (Relatórios → Relatório de AFDs);
-- o navegador lê o arquivo (n8n/controlid/lib/afd.mjs) e manda as marcações em lotes para ponto_importar_afd, que reaproveita
-- ingestao_controlid_batidas (idempotência por NSR, vínculo por CPF/PIS, batidas pendentes sem funcionário, reapuração, cursor).
-- Também: relógio "por arquivo" sem segredos (parametros.fonte = 'arquivo', fora do N8N) e o atalho "Ligar funcionários".
-- Idempotente. Contrato: §7.1, §11.4, §12.4 e docs/CONTRATO.md §7.9 (importação do AFD).
-- =====================================================================================================

-- ------------------------------------------------------------------ auxiliares
-- "CARLA  DE SOUZA" → "Carla de Souza" (o nome do AFD vem em maiúsculas).
create or replace function public.nome_proprio(p_nome text) returns text
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare
  v_partes text[];
  v_saida  text[] := '{}';
  v_p      text;
  v_i      int := 0;
begin
  if p_nome is null or btrim(p_nome) = '' then return null; end if;
  p_nome := btrim(regexp_replace(p_nome, '\s+', ' ', 'g'));
  -- maiúsculas/minúsculas com acento independem do locale do banco (ICU); sem ICU, cai no locale do banco
  begin
    p_nome := initcap(lower(p_nome collate "und-x-icu") collate "und-x-icu");
  exception when others then
    p_nome := initcap(lower(p_nome));
  end;
  v_partes := regexp_split_to_array(p_nome, ' ');
  foreach v_p in array v_partes loop
    v_i := v_i + 1;
    if v_i > 1 and lower(v_p) in ('da', 'de', 'do', 'das', 'dos', 'e') then
      v_saida := v_saida || lower(v_p);
    else
      v_saida := v_saida || v_p;
    end if;
  end loop;
  return array_to_string(v_saida, ' ');
end $$;
comment on function public.nome_proprio(text) is '[interno] Nome em maiúsculas → nome próprio (partículas de/da/do/dos/das/e em minúsculas).';

-- Documento só com dígitos, 11 posições; senão null.
create or replace function public.afd_documento(p_valor jsonb) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when d ~ '^[0-9]{11}$' and d !~ '^0+$' then d end
    from (select regexp_replace(coalesce(p_valor #>> '{}', ''), '[^0-9]', '', 'g') as d) x
$$;
comment on function public.afd_documento(jsonb) is '[interno] CPF/PIS do AFD → 11 dígitos (ou null).';

-- ------------------------------------------------------- relógio de ponto por arquivo (RHiD)
-- Devolve o relógio "por arquivo" da empresa (cria se não houver): tipo controlid_rep, sem segredos, fora do N8N.
create or replace function public.ponto_integracao_arquivo(p_empresa uuid default null) returns uuid
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid := public.resolver_empresa(p_empresa, 'operar');
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('mdg:integracao_arquivo:' || v_empresa::text, 0));
  select i.id into v_id from public.integracoes i
   where i.empresa_id = v_empresa and i.tipo = 'controlid_rep' and i.parametros ->> 'fonte' = 'arquivo'
   order by i.ativa desc, i.criado_em, i.id limit 1;
  if v_id is not null then
    update public.integracoes set ativa = true where id = v_id and not ativa;
    return v_id;
  end if;
  insert into public.integracoes (empresa_id, tipo, nome, parametros, intervalo_minutos)
  values (v_empresa, 'controlid_rep', 'Relógio de ponto (RHiD/arquivo)',
          '{"modelo": "RHiD", "fonte": "arquivo", "identificador": "cpf", "dias_retroativos": 2}'::jsonb, 1440)
  returning id into v_id;
  return v_id;
end $$;
comment on function public.ponto_integracao_arquivo(uuid) is
  '[api] Relógio de ponto por arquivo (RHiD/AFD) da empresa — cria sem URL/login se não houver (G A M).';

-- --------------------------------------------------------------------- importar AFD
create or replace function public.ponto_importar_afd(
  p_integracao uuid, p_marcacoes jsonb, p_empregados jsonb default '[]', p_arquivo_nome text default null
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig          public.integracoes;
  v_exec      uuid;
  v_total     int;
  v_ini       int := 0;
  v_lote      jsonb;
  r           jsonb;
  v_lidas     int := 0;
  v_gravadas  int := 0;
  v_ignoradas int := 0;
  v_dups      int := 0;
  v_dias      int := 0;
  v_erros     jsonb := '[]'::jsonb;
  e           jsonb;
  v_cpf       text;
  v_pis       text;
  v_doc       text;
  v_nome      text;
  v_novo      boolean;
  v_emp_lidos int := 0;
  v_emp_novos int := 0;
  v_emp_atual int := 0;
  v_auto      int := 0;
  v_docs      text[];
  v_nsrs      text[];
  u           record;
  v_func      uuid;
  v_semfunc   jsonb;
  v_ini_per   date;
  v_fim_per   date;
  v_res       jsonb;
begin
  select * into ig from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not public.pode_operar(ig.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if ig.tipo <> 'controlid_rep' then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  if not ig.ativa then raise exception 'Integração inativa' using errcode = '22023'; end if;
  p_marcacoes := public.ingestao_lista(p_marcacoes);
  p_empregados := public.ingestao_lista(coalesce(p_empregados, '[]'::jsonb));
  v_total := jsonb_array_length(p_marcacoes);
  if v_total > 5000 then raise exception 'Lote maior que 5000 marcações' using errcode = '22023'; end if;
  if jsonb_array_length(p_empregados) > 5000 then raise exception 'Lote maior que 5000 empregados' using errcode = '22023'; end if;

  -- cursor e ultimo_* da integração são do serviço; aqui o usuário importa em nome dele (integracoes_antes_gravar)
  perform set_config('app.ingestao_arquivo', '1', true);
  v_exec := public.ingestao_sync_iniciar('controlid_batidas', 'manual', 'Importar AFD (arquivo)', null, ig.id);

  -- 1) empregados do AFD (registro tipo 5) → usuários do equipamento (aparecem na tela de vínculo)
  for e in select value from jsonb_array_elements(p_empregados) loop
    continue when jsonb_typeof(e) <> 'object';
    v_cpf := public.afd_documento(e -> 'cpf');
    v_pis := case when v_cpf is null then public.afd_documento(e -> 'pis') end;
    v_doc := coalesce(v_cpf, v_pis);
    continue when v_doc is null;
    v_emp_lidos := v_emp_lidos + 1;
    v_nome := nullif(btrim(regexp_replace(coalesce(e ->> 'nome', ''), '\s+', ' ', 'g')), '');
    insert into public.controlid_usuarios as c (empresa_id, integracao_id, user_id_externo, nome, cpf, pis, visto_em)
    values (ig.empresa_id, ig.id, v_doc, v_nome, v_cpf, v_pis, public.agora())
    on conflict (integracao_id, user_id_externo) do update
       set nome = coalesce(excluded.nome, c.nome), cpf = coalesce(excluded.cpf, c.cpf), pis = coalesce(excluded.pis, c.pis),
           visto_em = excluded.visto_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_emp_novos := v_emp_novos + 1; else v_emp_atual := v_emp_atual + 1; end if;
  end loop;

  -- 2) CPF/PIS das marcações sem usuário ainda (AFD sem registro tipo 5 no período)
  select coalesce(array_agg(distinct d), '{}') into v_docs
    from (select coalesce(public.afd_documento(x -> 'cpf'), public.afd_documento(x -> 'pis')) as d
            from jsonb_array_elements(p_marcacoes) x where jsonb_typeof(x) = 'object') q
   where d is not null;
  insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, cpf, pis, visto_em)
  select ig.empresa_id, ig.id, q.d, case when q.cpf then q.d end, case when not q.cpf then q.d end, public.agora()
    from (select distinct on (coalesce(public.afd_documento(x -> 'cpf'), public.afd_documento(x -> 'pis')))
                 coalesce(public.afd_documento(x -> 'cpf'), public.afd_documento(x -> 'pis')) as d,
                 public.afd_documento(x -> 'cpf') is not null as cpf
            from jsonb_array_elements(p_marcacoes) x where jsonb_typeof(x) = 'object') q
   where q.d is not null
  on conflict (integracao_id, user_id_externo) do nothing;
  v_docs := v_docs || coalesce((select array_agg(distinct coalesce(public.afd_documento(x -> 'cpf'), public.afd_documento(x -> 'pis')))
                                  from jsonb_array_elements(p_empregados) x where jsonb_typeof(x) = 'object'), '{}');

  -- 3) vínculo automático pelo CPF/PIS da ficha (único na empresa, livre neste equipamento; nunca desfaz vínculo manual)
  for u in
    select c.id, c.cpf, c.pis from public.controlid_usuarios c
     where c.integracao_id = ig.id and c.funcionario_id is null and c.vinculo is null and c.user_id_externo = any (v_docs)
     order by c.user_id_externo
  loop
    select min(f.id::text)::uuid into v_func from public.funcionarios f
     where f.empresa_id = ig.empresa_id
       and ((u.cpf is not null and f.cpf = u.cpf) or (u.pis is not null and f.pis = u.pis))
       and not exists (select 1 from public.controlid_usuarios x where x.integracao_id = ig.id and x.funcionario_id = f.id)
    having count(*) = 1;
    if v_func is not null then
      update public.controlid_usuarios set funcionario_id = v_func, vinculo = 'automatico' where id = u.id;
      v_auto := v_auto + 1;
    end if;
  end loop;

  -- 4) marcações: a mesma ingestão do N8N, em lotes de 2000
  while v_ini < v_total loop
    select coalesce(jsonb_agg(x.value order by x.ordinality), '[]'::jsonb) into v_lote
      from jsonb_array_elements(p_marcacoes) with ordinality x
     where x.ordinality > v_ini and x.ordinality <= v_ini + 2000;
    r := public.ingestao_controlid_batidas(ig.id, v_lote);
    v_lidas := v_lidas + (r ->> 'lidos')::int;
    v_gravadas := v_gravadas + (r ->> 'gravados')::int;
    v_ignoradas := v_ignoradas + (r ->> 'ignorados')::int;
    v_dups := v_dups + (r ->> 'duplicados')::int;
    v_dias := v_dias + (r ->> 'dias_apurados')::int;
    if r ? 'erros' and jsonb_array_length(v_erros) < 20 then
      select v_erros || coalesce(jsonb_agg(jsonb_build_object('indice', (x ->> 'indice')::int + v_ini, 'motivo', x ->> 'motivo')), '[]'::jsonb)
        into v_erros from jsonb_array_elements(r -> 'erros') x;
      if jsonb_array_length(v_erros) > 20 then
        select jsonb_agg(x.value order by x.ordinality) into v_erros
          from jsonb_array_elements(v_erros) with ordinality x where x.ordinality <= 20;
      end if;
    end if;
    v_ini := v_ini + 2000;
  end loop;

  -- 5) resumo: período lido e CPFs/PIS ainda sem funcionário (com o nome do AFD, quando veio)
  select coalesce(array_agg(distinct coalesce(nullif(ltrim(t, '0'), ''), '0')), '{}') into v_nsrs
    from (select coalesce(public.ingestao_texto(x -> 'id_externo'), public.ingestao_texto(x -> 'nsr')) as t
            from jsonb_array_elements(p_marcacoes) x where jsonb_typeof(x) = 'object') q
   where t ~ '^[0-9]+$';
  select min(b.data_trabalho), max(b.data_trabalho) into v_ini_per, v_fim_per
    from public.ponto_batidas b where b.integracao_id = ig.id and b.id_externo = any (v_nsrs);
  select coalesce(jsonb_agg(jsonb_build_object('cpf', s.cpf, 'pis', s.pis, 'nome', s.nome, 'quantidade', s.n,
                                               'controlid_usuario_id', s.id) order by s.n desc, s.nome nulls last, s.doc), '[]'::jsonb)
    into v_semfunc
    from (select b.pessoa_externa as doc, count(*)::int as n, c.id, c.nome,
                 coalesce(c.cpf, case when c.pis is null then b.pessoa_externa end) as cpf, c.pis
            from public.ponto_batidas b
            left join public.controlid_usuarios c on c.integracao_id = b.integracao_id and c.user_id_externo = b.pessoa_externa
           where b.integracao_id = ig.id and b.funcionario_id is null and b.pessoa_externa = any (v_docs)
           group by b.pessoa_externa, c.id, c.nome, c.cpf, c.pis) s;

  v_res := jsonb_build_object(
    'lidas', v_lidas, 'gravadas', v_gravadas, 'duplicadas', v_dups, 'ignoradas', v_ignoradas,
    'sem_funcionario', v_semfunc, 'dias_reapurados', v_dias,
    'periodo', jsonb_build_object('inicio', v_ini_per, 'fim', v_fim_per),
    'empregados', jsonb_build_object('lidos', v_emp_lidos, 'novos', v_emp_novos, 'atualizados', v_emp_atual,
                                     'vinculados_automaticamente', v_auto),
    'execucao_id', v_exec)
    || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end;

  update public.sync_execucoes set periodo_inicio = v_ini_per, periodo_fim = v_fim_per where id = v_exec;
  perform public.ingestao_sync_finalizar(
    v_exec, case when v_ignoradas > 0 then 'parcial' else 'sucesso' end, v_lidas, v_gravadas, v_ignoradas, null,
    jsonb_build_object('origem', 'arquivo', 'arquivo', nullif(btrim(coalesce(p_arquivo_nome, '')), ''),
                       'duplicadas', v_dups, 'sem_funcionario', jsonb_array_length(v_semfunc), 'dias_reapurados', v_dias,
                       'empregados', v_res -> 'empregados', 'importado_por', public.meu_perfil_id())
    || case when jsonb_array_length(v_erros) > 0 then jsonb_build_object('erros', v_erros) else '{}'::jsonb end);
  perform set_config('app.ingestao_arquivo', '', true);
  return v_res;
end $$;
comment on function public.ponto_importar_afd(uuid, jsonb, jsonb, text) is
  '[api] Importa marcações do AFD (lido no navegador) e empregados (tipo 5) num relógio REP — mesma regra da ingestão (G A M).';

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

commit;
select 'parte 19 de 20 instalada' as resultado;

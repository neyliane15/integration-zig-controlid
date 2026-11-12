-- Meu Dia de Gerente — instalação do banco, PARTE 10 DE 14.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000220_comissoes.sql, 20261006000230_ingestao.sql. Não edite à mão.

begin;
create or replace function public.comissao_calcular(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  fc        record;
  v_zig     bigint;
  v_bruto   bigint;
  v_ret     bigint;
  v_base    bigint;
  v_dias    int;
  v_soma    numeric;
  v_resto   bigint;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento for update;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;

  -- 1–3. serviço, retenção, base
  select coalesce(sum(i.valor_total), 0) into v_zig
    from public.zig_vendas_itens i
   where i.empresa_id = fc.empresa_id and i.tipo = 'Tip'
     and i.data_operacao between fc.data_inicio and fc.data_fim
     and (fc.loja_id_externo is null or i.loja_id_externo = fc.loja_id_externo);
  v_bruto := greatest(0, v_zig + fc.servico_ajuste_centavos);
  v_ret := round(v_bruto::numeric * fc.percentual_retencao / 100);
  v_base := v_bruto - v_ret;
  v_dias := fc.data_fim - fc.data_inicio + 1;

  -- 4b. (adendo E.1) quem tem pontos extras no período entra (pontos base 0) e os extras são relidos
  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, pontos)
  select fc.empresa_id, p_fechamento, f.id, f.nome, f.cargo, 0
    from public.funcionarios f
   where f.empresa_id = fc.empresa_id
     and exists (select 1 from public.comissao_pontos_extras x
                  where x.funcionario_id = f.id and x.data between fc.data_inicio and fc.data_fim)
     and not exists (select 1 from public.comissao_itens it where it.fechamento_id = p_fechamento and it.funcionario_id = f.id);
  update public.comissao_itens it
     set pontos_extras = coalesce((select sum(x.pontos) from public.comissao_pontos_extras x
                                    where x.funcionario_id = it.funcionario_id
                                      and x.data between fc.data_inicio and fc.data_fim), 0)
   where it.fechamento_id = p_fechamento and it.funcionario_id is not null;

  -- 5–6. dias trabalhados e pontos efetivos (extras somados depois da proporção, sem proporcionalizar)
  update public.comissao_itens it
     set dias_trabalhados = case when it.funcionario_id is null then it.dias_trabalhados
                                 else (select count(*) from public.ponto_dias d
                                        where d.funcionario_id = it.funcionario_id
                                          and d.data between fc.data_inicio and fc.data_fim
                                          and d.batidas_validas > 0) end
   where it.fechamento_id = p_fechamento;
  update public.comissao_itens it
     set pontos_efetivos = case when not it.incluido then 0
                                when fc.proporcional_dias then round(it.pontos * it.dias_trabalhados / v_dias, 6) + it.pontos_extras
                                else it.pontos + it.pontos_extras end
   where it.fechamento_id = p_fechamento;

  select coalesce(sum(it.pontos_efetivos), 0) into v_soma from public.comissao_itens it where it.fechamento_id = p_fechamento;

  if v_soma = 0 then
    update public.comissao_itens set valor_centavos = 0 where fechamento_id = p_fechamento;
  else
    -- 9. maior resto — aritmética EXATA: piso = div(base × pe, soma) e resto = mod(base × pe, soma)
    -- (mesmo denominador para todos, então comparar o resto inteiro = comparar a parte fracionária; a divisão
    -- numérica com escala finita podia arredondar o piso para cima em valores extremos).
    -- Desempate por nome com collate "C" (ordem de código de caractere, igual à prévia do front em
    -- web/src/lib/comissao.ts), independente da collation do banco do Supabase.
    with c as (
      select it.id, div(v_base * it.pontos_efetivos, v_soma) as piso
        from public.comissao_itens it where it.fechamento_id = p_fechamento
    )
    update public.comissao_itens it set valor_centavos = c.piso::bigint
      from c where it.id = c.id;
    select v_base - coalesce(sum(valor_centavos), 0) into v_resto
      from public.comissao_itens where fechamento_id = p_fechamento;
    with ordem as (
      select it.id
        from public.comissao_itens it
       where it.fechamento_id = p_fechamento and it.pontos_efetivos > 0
       order by mod(v_base * it.pontos_efetivos, v_soma) desc,
                it.pontos_efetivos desc, it.funcionario_nome collate "C" asc, it.funcionario_id asc nulls last, it.id
       limit v_resto
    )
    update public.comissao_itens it set valor_centavos = it.valor_centavos + 1
      from ordem where it.id = ordem.id;
  end if;

  update public.comissao_fechamentos
     set servico_zig_centavos = v_zig,
         servico_bruto_centavos = v_bruto,
         retencao_centavos = v_ret,
         base_distribuivel_centavos = v_base,
         dias_periodo = v_dias,
         soma_pontos_efetivos = v_soma,
         valor_ponto_centavos = case when v_soma = 0 then null else round(v_base / v_soma, 6) end,
         calculado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_calcular(uuid) is '[interno] Recalcula um fechamento em rascunho (§9).';

-- Carrega o fechamento e checa permissão de operação (G A M) e status rascunho.
create or replace function public.comissao_rascunho_para_editar(p_fechamento uuid)
returns public.comissao_fechamentos language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  return fc;
end $$;
comment on function public.comissao_rascunho_para_editar(uuid) is '[interno] Fechamento em rascunho editável pelo usuário?';

-- ================================================================ RPCs
create or replace function public.comissao_criar_fechamento(p_data_inicio date, p_data_fim date, p_titulo text default null,
                                                            p_loja text default null, p_proporcional_dias boolean default false,
                                                            p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid; v_pct numeric;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.ponto_validar_periodo(p_data_inicio, p_data_fim, 93);
  p_loja := nullif(btrim(p_loja), '');
  if p_loja is not null and not exists (select 1 from public.zig_lojas l
                                         where l.empresa_id = v_empresa and l.loja_id_externo = p_loja) then
    raise exception 'Loja não encontrada' using errcode = 'P0002';
  end if;
  select e.comissao_percentual_retencao into v_pct from public.empresas e where e.id = v_empresa;

  insert into public.comissao_fechamentos (empresa_id, titulo, data_inicio, data_fim, loja_id_externo, percentual_retencao,
                                           proporcional_dias, criado_por)
  values (v_empresa,
          coalesce(nullif(btrim(p_titulo), ''),
                   'Comissão ' || to_char(p_data_inicio, 'DD/MM') || ' a ' || to_char(p_data_fim, 'DD/MM/YYYY')),
          p_data_inicio, p_data_fim, p_loja, coalesce(v_pct, 20), coalesce(p_proporcional_dias, false), auth.uid())
  returning id into v_id;

  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, pontos)
  select v_empresa, v_id, f.id, f.nome, f.cargo, pv.pontos
    from public.funcionarios f
    cross join lateral (select public.comissao_pontos_vigentes(f.id, p_data_fim) as pontos) pv
   where f.empresa_id = v_empresa and f.ativo and f.participa_comissao
     and (f.data_admissao is null or f.data_admissao <= p_data_fim)
     and (f.data_desligamento is null or f.data_desligamento >= p_data_inicio)
     and pv.pontos > 0;

  perform public.comissao_calcular(v_id);
  return v_id;
end $$;
comment on function public.comissao_criar_fechamento(date, date, text, text, boolean, uuid) is '[api] Cria rascunho de comissão com os participantes e calcula.';

create or replace function public.comissao_atualizar_fechamento(p_fechamento uuid, p_titulo text, p_servico_ajuste_centavos bigint,
                                                                p_percentual_retencao numeric, p_proporcional_dias boolean,
                                                                p_observacoes text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  if p_percentual_retencao is not null and (p_percentual_retencao < 0 or p_percentual_retencao > 100) then
    raise exception 'Percentual de retenção inválido' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set titulo = coalesce(nullif(btrim(p_titulo), ''), titulo),
         servico_ajuste_centavos = coalesce(p_servico_ajuste_centavos, servico_ajuste_centavos),
         percentual_retencao = coalesce(p_percentual_retencao, percentual_retencao),
         proporcional_dias = coalesce(p_proporcional_dias, proporcional_dias),
         observacoes = nullif(btrim(p_observacoes), '')
   where id = p_fechamento;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_atualizar_fechamento(uuid, text, bigint, numeric, boolean, text) is '[api] Edita parâmetros do rascunho e recalcula.';

create or replace function public.comissao_definir_item(p_fechamento uuid, p_funcionario uuid, p_pontos numeric,
                                                        p_incluido boolean default true)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos; f record; v_pontos numeric;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  select * into f from public.funcionarios where id = p_funcionario;
  if not found then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if f.empresa_id <> fc.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  v_pontos := coalesce(p_pontos, public.comissao_pontos_vigentes(f.id, fc.data_fim));
  if v_pontos < 0 or v_pontos > 999999.99 then raise exception 'Pontos inválidos' using errcode = '22023'; end if;

  insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, incluido, pontos)
  values (fc.empresa_id, p_fechamento, f.id, f.nome, f.cargo, coalesce(p_incluido, true), v_pontos)
  on conflict (fechamento_id, funcionario_id) do update
    set funcionario_nome = excluded.funcionario_nome, cargo = excluded.cargo,
        incluido = excluded.incluido, pontos = excluded.pontos;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_definir_item(uuid, uuid, numeric, boolean) is '[api] Inclui/atualiza participante (snapshot de nome/cargo) e recalcula.';

create or replace function public.comissao_remover_item(p_fechamento uuid, p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  if exists (select 1 from public.comissao_pontos_extras x
              where x.funcionario_id = p_funcionario and x.data between fc.data_inicio and fc.data_fim) then
    -- com extras no período ele voltaria no próximo cálculo: só desmarca (adendo E.1)
    update public.comissao_itens set incluido = false where fechamento_id = p_fechamento and funcionario_id = p_funcionario;
  else
    delete from public.comissao_itens where fechamento_id = p_fechamento and funcionario_id = p_funcionario;
  end if;
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_remover_item(uuid, uuid) is '[api] Remove participante do rascunho (com extras no período: só desmarca) e recalcula.';

create or replace function public.comissao_recalcular(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  perform public.comissao_calcular(p_fechamento);
end $$;
comment on function public.comissao_recalcular(uuid) is '[api] Relê serviço e presença e recalcula o rascunho.';

create or replace function public.comissao_fechar(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  select * into fc from public.comissao_fechamentos where id = p_fechamento;
  if not found then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(fc.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if public.pode_administrar(fc.empresa_id) is not true then
    raise exception 'Somente o administrador fecha a comissão' using errcode = '42501';
  end if;
  if fc.status = 'fechado' then raise exception 'Fechamento já está fechado' using errcode = '22023'; end if;
  perform public.comissao_calcular(p_fechamento);
  if not exists (select 1 from public.comissao_fechamentos where id = p_fechamento and soma_pontos_efetivos > 0) then
    raise exception 'Fechamento sem participantes' using errcode = '22023';
  end if;
  update public.comissao_fechamentos
     set status = 'fechado', fechado_por = auth.uid(), fechado_em = public.agora()
   where id = p_fechamento;
end $$;
comment on function public.comissao_fechar(uuid) is '[api] Recalcula e fecha (administrador). Depois é imutável.';

create or replace function public.comissao_excluir_rascunho(p_fechamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare fc public.comissao_fechamentos;
begin
  fc := public.comissao_rascunho_para_editar(p_fechamento);
  delete from public.comissao_fechamentos where id = p_fechamento;
end $$;
comment on function public.comissao_excluir_rascunho(uuid) is '[api] Exclui um rascunho de comissão.';-- =====================================================================================================
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

commit;
select 'parte 10 de 14 instalada' as resultado;

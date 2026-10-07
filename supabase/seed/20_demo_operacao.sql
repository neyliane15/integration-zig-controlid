-- =====================================================================================================
-- Carga de demonstração — operação (backend-2). Depende de 10_demo_base.sql (empresa A "Bar Bossa Nova").
-- Gera, RELATIVO ao dia de trabalho atual:
--   * batidas (REP iDClass) dos últimos 14 dias para os 5 funcionários de A, conforme a escala, com
--     uma volta de intervalo faltando (Carla, anteontem), um dia com batidas ímpares (Bruno) e uma ausência (Davi);
--   * dados da Zig dos últimos 30 dias (itens por garçom com Tips, faturamento por forma, bandeiras, compradores);
--   * um fechamento de comissão FECHADO do mês anterior e um RASCUNHO do mês corrente.
-- Idempotente: batidas por (integração, id_externo); dias da Zig só se ainda vazios; fechamentos só se não existirem.
-- Rodar como dono do banco (SQL Editor / psql), depois das migrações e de 10_demo_base.sql.
-- =====================================================================================================

do $$
declare
  v_empresa  constant uuid := 'a0000000-0000-4000-8000-00000000000a';
  v_rep      constant uuid := 'a0000000-0000-4000-8000-000000000103';
  v_zig      constant uuid := 'a0000000-0000-4000-8000-000000000101';
  v_loja     constant text := 'loja-1';
  e          record;
  f          record;
  jd         record;
  v_hoje     date;
  v_dia      date;
  v_slots    time[];
  v_i        int;
  v_ts       timestamptz;
  v_impar    date;
  v_ausente  date;
  v_jit      int;
  -- Zig
  v_garcom   text;
  v_t        int;
  v_n        int;
  v_k        int;
  v_trans    text;
  v_prod     int;
  v_qtd      int;
  v_soma     bigint;
  v_total    bigint;
  v_tip      bigint;
  v_produtos constant text[] := array['Chopp 300ml', 'Caipirinha', 'Porção de fritas', 'Água com gás', 'Refrigerante',
                                      'Bolinho de bacalhau', 'Gin tônica', 'Picanha na chapa'];
  v_precos   constant int[] := array[1200, 2600, 3900, 700, 800, 4200, 3500, 8900];
  v_categ    constant text[] := array['Bebidas', 'Drinks', 'Petiscos', 'Bebidas', 'Bebidas', 'Petiscos', 'Drinks', 'Pratos'];
  v_ini_mes  date;
  v_ini_ant  date;
  v_fim_ant  date;
  v_fech     uuid;
begin
  select * into e from public.empresas where id = v_empresa;
  if not found then
    raise notice '20_demo_operacao: empresa demo A não existe (rode 10_demo_base.sql antes) — nada a fazer';
    return;
  end if;
  v_hoje := public.dia_de_trabalho(public.agora(), v_empresa);

  -- ------------------------------------------------------------------------------ batidas (14 dias)
  if exists (select 1 from public.integracoes where id = v_rep) then
    for f in
      select fu.id, right(fu.id::text, 3) as cod, fu.cpf
        from public.funcionarios fu
       where fu.empresa_id = v_empresa and fu.cpf is not null
       order by fu.id
    loop
      -- dia ímpar do Bruno e ausência do Davi: o último dia de escala a partir de hoje − 3 / hoje − 5
      v_impar := null; v_ausente := null;
      for v_dia in select g::date from generate_series(v_hoje - 14, v_hoje - 1, interval '1 day') g order by 1 desc loop
        if exists (select 1 from public.funcionario_jornadas fj join public.jornada_dias x on x.jornada_id = fj.jornada_id
                    where fj.funcionario_id = f.id and fj.vigente_desde <= v_dia and x.dia_semana = extract(dow from v_dia)) then
          if v_impar is null and v_dia <= v_hoje - 3 then v_impar := v_dia; end if;
          if v_ausente is null and v_dia <= v_hoje - 5 then v_ausente := v_dia; end if;
        end if;
      end loop;

      for v_dia in select g::date from generate_series(v_hoje - 14, v_hoje - 1, interval '1 day') g loop
        select x.* into jd
          from public.funcionario_jornadas fj
          join public.jornada_dias x on x.jornada_id = fj.jornada_id and x.dia_semana = extract(dow from v_dia)
         where fj.funcionario_id = f.id and fj.vigente_desde <= v_dia
         order by fj.vigente_desde desc
         limit 1;
        continue when not found;
        continue when f.cod = '304' and v_dia = v_ausente;                       -- Davi faltou
        v_slots := array[jd.entrada, jd.saida_intervalo, jd.volta_intervalo, jd.saida];
        for v_i in 1 .. 4 loop
          continue when v_slots[v_i] is null;
          continue when f.cod = '303' and v_dia = v_hoje - 2 and v_i = 3;        -- Carla: sem volta do intervalo
          v_jit := (abs(hashtext(f.cod || v_dia::text || v_i)) % 9) - 4;         -- −4..+4 min
          v_ts := public.ponto_instante_escala(v_dia, v_slots[v_i], e.fuso, e.virada_dia) + make_interval(mins => v_jit);
          insert into public.ponto_batidas (empresa_id, integracao_id, funcionario_id, origem, id_externo, pessoa_externa, instante)
          values (v_empresa, v_rep, f.id, 'controlid_rep', 'demo-' || f.cod || '-' || v_dia || '-' || v_i, f.cpf, v_ts)
          on conflict on constraint ponto_batidas_externa_uk do nothing;
        end loop;
        if f.cod = '302' and v_dia = v_impar then                                -- Bruno: batida extra (ímpar)
          v_ts := public.ponto_instante_escala(v_dia, jd.saida, e.fuso, e.virada_dia) + interval '47 minutes';
          insert into public.ponto_batidas (empresa_id, integracao_id, funcionario_id, origem, id_externo, pessoa_externa, instante)
          values (v_empresa, v_rep, f.id, 'controlid_rep', 'demo-' || f.cod || '-' || v_dia || '-5', f.cpf, v_ts)
          on conflict on constraint ponto_batidas_externa_uk do nothing;
        end if;
      end loop;
    end loop;
    perform public.ponto_apurar_empresa(v_empresa, v_hoje - 14, v_hoje);
    -- A demonstração só tem batidas dos últimos 14 dias: descarta a apuração anterior (feita pelos gatilhos ao
    -- cadastrar as escalas), que seria só uma fila de "sem batidas" sem significado.
    delete from public.ponto_alarmes where empresa_id = v_empresa and data < v_hoje - 14;
    delete from public.ponto_dias where empresa_id = v_empresa and data < v_hoje - 14;
  end if;

  -- ------------------------------------------------------------------------------ Zig (30 dias)
  if exists (select 1 from public.integracoes where id = v_zig) then
    insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome)
    values (v_empresa, v_zig, v_loja, 'Bossa Nova Salão')
    on conflict (empresa_id, loja_id_externo) do nothing;

    for v_dia in select g::date from generate_series(v_hoje - 30, v_hoje - 1, interval '1 day') g loop
      continue when exists (select 1 from public.zig_vendas_itens
                             where empresa_id = v_empresa and loja_id_externo = v_loja and data_operacao = v_dia);
      v_total := 0;
      foreach v_garcom in array array['Ana Souza', 'Bruno Lima', 'Davi Rocha'] loop
        v_n := 3 + abs(hashtext(v_garcom || v_dia::text)) % 5 + case when extract(dow from v_dia) in (5, 6) then 4 else 0 end;
        for v_t in 1 .. v_n loop
          v_trans := 'demo-' || to_char(v_dia, 'YYYYMMDD') || '-' || left(v_garcom, 1) || v_t;
          v_soma := 0;
          for v_k in 1 .. 1 + abs(hashtext(v_trans)) % 3 loop
            v_prod := 1 + abs(hashtext(v_trans || v_k)) % 8;
            v_qtd := 1 + abs(hashtext(v_trans || 'q' || v_k)) % 3;
            insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, transaction_date,
              product_id, product_name, product_category, tipo, tipo_original, unit_value, quantidade, discount_value, valor_total,
              employee_name)
            values (v_empresa, v_loja, v_dia, v_trans,
              public.ponto_instante_escala(v_dia, time '18:00' + make_interval(mins => (v_t * 23) % 360), e.fuso, e.virada_dia),
              v_prod::text, v_produtos[v_prod], v_categ[v_prod], 'Normal', 'Normal', v_precos[v_prod], v_qtd, 0,
              v_precos[v_prod] * v_qtd, v_garcom);
            v_soma := v_soma + v_precos[v_prod] * v_qtd;
          end loop;
          v_tip := round(v_soma * 0.10);
          insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, product_name, tipo,
            tipo_original, unit_value, quantidade, valor_total, employee_name)
          values (v_empresa, v_loja, v_dia, v_trans, 'Serviço (10%)', 'Tip', 'Tip', v_tip, 1, v_tip, v_garcom);
          insert into public.zig_compradores (empresa_id, loja_id_externo, data_operacao, transaction_id, products_value, tip_value)
          values (v_empresa, v_loja, v_dia, v_trans, v_soma, v_tip);
          v_total := v_total + v_soma + v_tip;
        end loop;
      end loop;

      insert into public.zig_faturamento (empresa_id, loja_id_externo, data_operacao, payment_id, payment_name, valor) values
        (v_empresa, v_loja, v_dia, 1, 'Crédito', round(v_total * 0.45)),
        (v_empresa, v_loja, v_dia, 2, 'Débito', round(v_total * 0.25)),
        (v_empresa, v_loja, v_dia, 3, 'Pix', round(v_total * 0.25)),
        (v_empresa, v_loja, v_dia, 4, 'Dinheiro', v_total - round(v_total * 0.45) - 2 * round(v_total * 0.25));
      insert into public.zig_faturamento_bandeiras (empresa_id, loja_id_externo, data_operacao, payment_id, payment_name, card_brand, valor) values
        (v_empresa, v_loja, v_dia, 1, 'Crédito', 'Visa', round(round(v_total * 0.45) * 0.6)),
        (v_empresa, v_loja, v_dia, 1, 'Crédito', 'Mastercard', round(v_total * 0.45) - round(round(v_total * 0.45) * 0.6));
    end loop;
    update public.integracoes set cursor = cursor || jsonb_build_object('ultimo_dia', v_hoje - 1)
     where id = v_zig and coalesce((cursor ->> 'ultimo_dia')::date, '-infinity') < v_hoje - 1;
  end if;

  -- ------------------------------------------------------------------------------ comissões
  v_ini_mes := date_trunc('month', v_hoje)::date;
  v_ini_ant := (v_ini_mes - interval '1 month')::date;
  v_fim_ant := v_ini_mes - 1;
  if not exists (select 1 from public.comissao_fechamentos
                  where empresa_id = v_empresa and data_inicio = v_ini_ant and data_fim = v_fim_ant) then
    v_fech := public.comissao_criar_fechamento(v_ini_ant, v_fim_ant, null, null, false, v_empresa);
    perform public.comissao_fechar(v_fech);
  end if;
  if not exists (select 1 from public.comissao_fechamentos
                  where empresa_id = v_empresa and data_inicio = v_ini_mes and status = 'rascunho') then
    v_fech := public.comissao_criar_fechamento(v_ini_mes, v_hoje, null, null, true, v_empresa);
    perform public.comissao_atualizar_fechamento(v_fech, null, 0, null, null, 'Prévia do mês corrente (proporcional aos dias trabalhados).');
  end if;
end $$;

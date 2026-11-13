-- =====================================================================================================
-- Carga de demonstração — extras, ocorrências e reservas (adendo extras/ocorrências/reservas).
-- Depende de 10_demo_base.sql e 20_demo_operacao.sql. Datas RELATIVAS ao dia de trabalho atual.
--   * A "Bar Bossa Nova": advertência do Davi (há 5 dias), suspensão da Eva (hoje e amanhã), dois extras (freelas)
--     cadastrados — Marcos Freitas (garçom, 5 pontos, R$ 180) e Júlia Ramos (cozinha, 3 pontos, R$ 150) — com dias
--     trabalhados nos últimos dias (fora de comissão fechada; o rascunho do mês é recalculado e os inclui), um extra
--     inativo, valor padrão de diária da Eva, diária paga da Eva (ontem, só custo) e 5 reservas de hoje (uma cancelada);
--   * B "Cantina Roma": advertência do Paolo, um extra com um dia trabalhado, diária do Paolo e uma reserva.
-- Idempotente (cada bloco só roda se ainda não houver o registro de demonstração). Rodar como dono do banco.
-- =====================================================================================================

do $$
declare
  a      constant uuid := 'a0000000-0000-4000-8000-00000000000a';
  b      constant uuid := 'b0000000-0000-4000-8000-00000000000b';
  davi   constant uuid := 'a0000000-0000-4000-8000-000000000304';
  eva    constant uuid := 'a0000000-0000-4000-8000-000000000305';
  paolo  constant uuid := 'b0000000-0000-4000-8000-000000000301';
  v_hoje date;
  v_hb   date;
  v_fech uuid;
  v_marcos uuid;
  v_julia uuid;
  v_d int;
begin
  if not exists (select 1 from public.empresas where id = a) then return; end if;
  v_hoje := public.dia_de_trabalho(public.agora(), a);
  v_hb := public.dia_de_trabalho(public.agora(), b);

  -- ocorrências
  if not exists (select 1 from public.funcionario_ocorrencias where funcionario_id = davi and motivo = 'Atrasos recorrentes (demo)') then
    perform public.ocorrencia_criar(davi, 'advertencia', v_hoje - 5, 'Atrasos recorrentes (demo)',
                                    'Três atrasos acima de 20 minutos na mesma semana.');
  end if;
  if not exists (select 1 from public.funcionario_ocorrencias where funcionario_id = eva and motivo = 'Falta sem aviso (demo)') then
    perform public.ocorrencia_criar(eva, 'suspensao', v_hoje, 'Falta sem aviso (demo)', 'Segunda falta sem aviso no mês.',
                                    2, v_hoje);
  end if;
  if exists (select 1 from public.empresas where id = b)
     and not exists (select 1 from public.funcionario_ocorrencias where funcionario_id = paolo) then
    perform public.ocorrencia_criar(paolo, 'advertencia', v_hb - 3, 'Uniforme incompleto (demo)');
  end if;

  -- extras (freelas) e dias trabalhados — só em dias fora de fechamento de comissão fechado
  if not exists (select 1 from public.extras where empresa_id = a and nome = 'Júlia Ramos') then
    v_marcos := public.extra_criar('Marcos Freitas', 'Garçom', 5, 18000, '11988880001', null, 'Freela de fim de semana (demo)', a);
    v_julia := public.extra_criar('Júlia Ramos', 'Cozinha', 3, 15000, null, null, null, a);
    perform public.extra_atualizar(public.extra_criar('Pedro Alves', 'Bar', 4, 16000, null, null, null, a),
                                   'Pedro Alves', 'Bar', 4, 16000, null, null, false, 'Não trabalha mais com a casa (demo)');
    for v_d in 0 .. 3 loop
      if not public.comissao_periodo_fechado(a, v_hoje - v_d) then
        if v_d in (0, 1, 3) then
          perform public.diaria_lancar(v_hoje - v_d, v_marcos, null, case when v_d = 0 then 6 end, null, null,
                                       case when v_d = 0 then 'Evento de sexta' end, v_d > 0, null);
        end if;
        if v_d in (0, 2) then
          perform public.diaria_lancar(v_hoje - v_d, v_julia, null, null, null, null, null, false, null);
        end if;
      end if;
    end loop;
    for v_fech in select id from public.comissao_fechamentos
                   where empresa_id = a and status = 'rascunho' and data_fim >= v_hoje - 3 loop
      perform public.comissao_recalcular(v_fech);
    end loop;
  end if;
  if exists (select 1 from public.empresas where id = b) and not exists (select 1 from public.extras where empresa_id = b) then
    v_marcos := public.extra_criar('Giovanni Bianchi', 'Garçom', 4, 14000, null, null, null, b);
    if not public.comissao_periodo_fechado(b, v_hb) then
      perform public.diaria_lancar(v_hb, v_marcos, null, null, null, null, null, false, null);
    end if;
  end if;

  -- diárias de funcionário (só custo)
  if not exists (select 1 from public.funcionario_valores_diaria where funcionario_id = eva) then
    perform public.funcionario_definir_valor_diaria(eva, 15000);
  end if;
  if not exists (select 1 from public.diarias where empresa_id = a and tipo = 'funcionario') then
    perform public.diaria_lancar(v_hoje - 1, null, eva, null, null, null, 'Cobertura do almoço', true, v_hoje - 1);
  end if;
  if exists (select 1 from public.empresas where id = b)
     and not exists (select 1 from public.diarias where empresa_id = b and tipo = 'funcionario') then
    perform public.funcionario_definir_valor_diaria(paolo, 12000);
    perform public.diaria_lancar(v_hb, null, paolo, null, null, null, null, false, null);
  end if;

  -- reservas de hoje
  if not exists (select 1 from public.reservas where empresa_id = a and data = v_hoje) then
    perform public.reserva_criar(v_hoje, '19:30', 'Maria Lima', 4, '11999990001', 'Salão', '12', 'Aniversário', 'confirmada', null, a);
    perform public.reserva_criar(v_hoje, '20:00', 'João Pereira', 2, '11999990002', 'Varanda', null, null, 'confirmada', null, a);
    perform public.reserva_criar(v_hoje, '20:30', 'Família Andrade', 8, '11999990003', 'Salão', '20', 'Cadeira de bebê', 'pendente', null, a);
    perform public.reserva_criar(v_hoje, '21:00', 'Luiza Prado', 3, null, null, null, null, 'confirmada', null, a);
    perform public.reserva_criar(v_hoje, '21:30', 'Rafael Costa', 2, '11999990005', null, null, 'Cancelou por telefone', 'cancelada', null, a);
  end if;
  if exists (select 1 from public.empresas where id = b) and not exists (select 1 from public.reservas where empresa_id = b) then
    perform public.reserva_criar(v_hb, '20:00', 'Giulia Rossi', 6, '19999990001', null, '7', null, 'confirmada', null, b);
  end if;
end $$;

-- =====================================================================================================
-- Carga de demonstração — extras, ocorrências e reservas (adendo extras/ocorrências/reservas).
-- Depende de 10_demo_base.sql e 20_demo_operacao.sql. Datas RELATIVAS ao dia de trabalho atual.
--   * A "Bar Bossa Nova": advertência do Davi (há 5 dias), suspensão da Eva (hoje e amanhã), pontos extras da Ana
--     (hoje, entram no rascunho do mês, recalculado), valor padrão de diária da Eva, diária paga da Eva (ontem),
--     diária a pagar de um freelancer avulso (hoje) e 5 reservas de hoje (uma cancelada);
--   * B "Cantina Roma": advertência do Paolo, pontos extras, diária e uma reserva.
-- Idempotente (cada bloco só roda se ainda não houver o registro de demonstração). Rodar como dono do banco.
-- =====================================================================================================

do $$
declare
  a      constant uuid := 'a0000000-0000-4000-8000-00000000000a';
  b      constant uuid := 'b0000000-0000-4000-8000-00000000000b';
  ana    constant uuid := 'a0000000-0000-4000-8000-000000000301';
  davi   constant uuid := 'a0000000-0000-4000-8000-000000000304';
  eva    constant uuid := 'a0000000-0000-4000-8000-000000000305';
  paolo  constant uuid := 'b0000000-0000-4000-8000-000000000301';
  v_hoje date;
  v_hb   date;
  v_fech uuid;
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

  -- pontos extras (hoje: sempre dentro do rascunho do mês corrente, nunca de um fechamento fechado)
  if not exists (select 1 from public.comissao_pontos_extras where funcionario_id = ana) then
    perform public.comissao_extra_lancar(ana, v_hoje, 2, 'Cobriu folga (demo)');
    for v_fech in select id from public.comissao_fechamentos
                   where empresa_id = a and status = 'rascunho' and v_hoje between data_inicio and data_fim loop
      perform public.comissao_recalcular(v_fech);
    end loop;
  end if;
  if exists (select 1 from public.empresas where id = b)
     and not exists (select 1 from public.comissao_pontos_extras where funcionario_id = paolo) then
    perform public.comissao_extra_lancar(paolo, v_hb, 1.5, 'Meta batida (demo)');
  end if;

  -- diárias
  if not exists (select 1 from public.funcionario_valores_diaria where funcionario_id = eva) then
    perform public.funcionario_definir_valor_diaria(eva, 15000);
  end if;
  if not exists (select 1 from public.diarias where empresa_id = a) then
    perform public.diaria_lancar(v_hoje - 1, eva, null, null, null, 'Cobertura do almoço', true, v_hoje - 1, a);
    perform public.diaria_lancar(v_hoje, null, 'Marcos Freitas (freela)', 'Garçom', 18000, 'Evento de sexta', false, null, a);
  end if;
  if exists (select 1 from public.empresas where id = b) and not exists (select 1 from public.diarias where empresa_id = b) then
    perform public.funcionario_definir_valor_diaria(paolo, 12000);
    perform public.diaria_lancar(v_hb, paolo, null, null, null, null, false, null, b);
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

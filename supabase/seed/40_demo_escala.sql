-- =====================================================================================================
-- Carga de demonstração — escala rotativa (docs/CONTRATO-ADENDO-escala.md §S.10).
-- Depende de 10_demo_base.sql (e roda depois de 20/30). Datas RELATIVAS ao dia de trabalho atual.
--   * A "Bar Bossa Nova": âncora = segunda-feira da semana atual (dias anteriores ficam fora da escala; o ponto já apurado
--     não muda); Salão (caminho 1: Ana SEG,TER → Bruno QUA,QUI → Carla SEG,DOM; chegada 17:00), Bar (Davi, folga fixa
--     SEG,TER, chegada 17:30), Cozinha (Eva, folga fixa DOM); Bruno troca com a Ana o primeiro dia futuro em que um folga e o
--     outro trabalha; Carla com férias de hoje + 7 a hoje + 9.
--   * B "Cantina Roma": setor Salão com Paolo (folga fixa SEG) e um ajuste de chegada daqui a 2 dias.
-- Idempotente (só roda se a empresa ainda não tem escala). Rodar como dono do banco.
-- =====================================================================================================

do $$
declare
  a      constant uuid := 'a0000000-0000-4000-8000-00000000000a';
  b      constant uuid := 'b0000000-0000-4000-8000-00000000000b';
  ana    constant uuid := 'a0000000-0000-4000-8000-000000000301';
  bruno  constant uuid := 'a0000000-0000-4000-8000-000000000302';
  carla  constant uuid := 'a0000000-0000-4000-8000-000000000303';
  davi   constant uuid := 'a0000000-0000-4000-8000-000000000304';
  eva    constant uuid := 'a0000000-0000-4000-8000-000000000305';
  paolo  constant uuid := 'b0000000-0000-4000-8000-000000000301';
  v_hoje date;
  v_setor uuid;
  v_d date;
begin
  if exists (select 1 from public.empresas where id = a) and not exists (select 1 from public.escala_config where empresa_id = a) then
    v_hoje := public.dia_de_trabalho(public.agora(), a);
    perform public.escala_configurar(v_hoje - (extract(isodow from v_hoje)::int - 1), 0, a);
    v_setor := public.escala_salvar_setor('Salão', 1, 0, null, a);
    perform public.escala_definir_membros(v_setor, jsonb_build_array(
      jsonb_build_object('funcionario_id', ana, 'folgas_base', jsonb_build_array(0, 1), 'chegada_padrao', '17:00', 'caminho', 1, 'posicao', 1),
      jsonb_build_object('funcionario_id', bruno, 'folgas_base', jsonb_build_array(2, 3), 'chegada_padrao', '17:00', 'caminho', 1, 'posicao', 2),
      jsonb_build_object('funcionario_id', carla, 'folgas_base', jsonb_build_array(0, 6), 'chegada_padrao', '17:00', 'caminho', 1, 'posicao', 3)));
    v_setor := public.escala_salvar_setor('Bar', 2, 0, null, a);
    perform public.escala_salvar_membro(v_setor, davi, '{0,1}', '17:30');
    v_setor := public.escala_salvar_setor('Cozinha', 3, 0, null, a);
    perform public.escala_salvar_membro(v_setor, eva, '{6}');
    select x.data into v_d
      from public.escala_calcular(a, v_hoje + 1, v_hoje + 14, ana) x
      join public.escala_calcular(a, v_hoje + 1, v_hoje + 14, bruno) y on y.data = x.data
     where x.status in ('trabalha', 'folga') and y.status in ('trabalha', 'folga') and x.status <> y.status
     order by x.data limit 1;
    if v_d is not null then
      perform public.escala_trocar(bruno, v_d, ana, null, 'Troca combinada entre eles (demo)');
    end if;
    -- férias só se não houver abono do funcionário nesses dias
    if not exists (select 1 from public.ponto_abonos where funcionario_id = carla and data between v_hoje + 7 and v_hoje + 9) then
      perform public.escala_ajustar_periodo(carla, v_hoje + 7, v_hoje + 9, 'ferias', 'Férias (demo)');
    end if;
  end if;

  if exists (select 1 from public.funcionarios where id = paolo) and not exists (select 1 from public.escala_config where empresa_id = b) then
    v_hoje := public.dia_de_trabalho(public.agora(), b);
    perform public.escala_configurar(v_hoje - (extract(isodow from v_hoje)::int - 1), 0, b);
    v_setor := public.escala_salvar_setor('Salão', 1, 0, null, b);
    perform public.escala_salvar_membro(v_setor, paolo, '{0}');
    perform public.escala_ajustar(paolo, v_hoje + 2, null, '18:00', 'Chega mais tarde (demo)');
  end if;
end $$;

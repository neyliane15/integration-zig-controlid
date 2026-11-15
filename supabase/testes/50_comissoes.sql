-- 50_comissoes.sql (b2) — comissão: vetor obrigatório do §9 (padrão e proporcional), soma exata em centavos,
-- ciclo rascunho → fechado imutável, snapshot, permissões e isolamento; rateio diário (adendo extras v2, E.3).
begin;
-- ------------------------------------------------------------------ cenário comum b2 (dentro da transação)
-- Relógio fixo, duas empresas (A = SP, B = Manaus), usuários de todos os papéis, jornada "Salão noite" (só sábado).
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e2000000-0000-4000-8000-00000000000a', 'Teste b2 A', 'America/Sao_Paulo', '05:00'),
  ('e2000000-0000-4000-8000-00000000000b', 'Teste b2 B', 'America/Manaus', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e2000000-0000-4000-8000-000000000a01', 'b2.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e2000000-0000-4000-8000-000000000a02', 'b2.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e2000000-0000-4000-8000-000000000a03', 'b2.lei.a@teste.local', '{"nome":"Leitura A"}'),
  ('e2000000-0000-4000-8000-000000000b01', 'b2.adm.b@teste.local', '{"nome":"Adm B"}'),
  ('e2000000-0000-4000-8000-000000000f01', 'b2.master@teste.local', '{"nome":"Master b2"}');
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a03';
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000b' where id = 'e2000000-0000-4000-8000-000000000b01';
update public.perfis set papel = 'master', empresa_id = null where id = 'e2000000-0000-4000-8000-000000000f01';
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e2000000-0000-4000-8000-000000000201', 'e2000000-0000-4000-8000-00000000000a', 'Salão noite b2', 5, 10),
  ('e2000000-0000-4000-8000-000000000202', 'e2000000-0000-4000-8000-00000000000b', 'Turno B', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values
  ('e2000000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) select 'e2000000-0000-4000-8000-000000000202', d, '09:00', '17:00' from generate_series(1, 5) d;
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, pontos_comissao, data_admissao, zig_employee_name) values
  ('e2000000-0000-4000-8000-000000000301', 'e2000000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', '52998224725', 10, '2026-01-01', 'Ana Souza'),
  ('e2000000-0000-4000-8000-000000000302', 'e2000000-0000-4000-8000-00000000000a', 'Bruno Lima', 'Garçom', '11144477735', 10, '2026-01-01', 'Bruno Lima'),
  ('e2000000-0000-4000-8000-000000000303', 'e2000000-0000-4000-8000-00000000000a', 'Carla Dias', 'Cumim', '39053344705', 6, '2026-01-01', 'Carla Dias'),
  ('e2000000-0000-4000-8000-000000000304', 'e2000000-0000-4000-8000-00000000000a', 'Davi Rocha', 'Bartender', '15350946056', 8, '2026-01-01', 'Davi Rocha'),
  ('e2000000-0000-4000-8000-000000000305', 'e2000000-0000-4000-8000-00000000000a', 'Eva Martins', 'Cozinha', '71428793860', 4, '2026-01-01', null),
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-00000000000b', 'Paolo B2', 'Garçom', null, 5, '2026-01-01', 'Paolo');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e2000000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e2000000-0000-4000-8000-000000000301','e2000000-0000-4000-8000-000000000302',
                    'e2000000-0000-4000-8000-000000000303','e2000000-0000-4000-8000-000000000304',
                    'e2000000-0000-4000-8000-000000000305']::uuid[]) f;
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde) values
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-000000000202', '2026-09-01');
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e2000000-0000-4000-8000-000000000101', 'e2000000-0000-4000-8000-00000000000a', 'zig', 'Zig b2', '{"rede":"r"}'),
  ('e2000000-0000-4000-8000-000000000102', 'e2000000-0000-4000-8000-00000000000a', 'controlid_acesso', 'iDFace b2', '{}'),
  ('e2000000-0000-4000-8000-000000000103', 'e2000000-0000-4000-8000-00000000000a', 'controlid_rep', 'iDClass b2', '{}'),
  ('e2000000-0000-4000-8000-000000000111', 'e2000000-0000-4000-8000-00000000000b', 'zig', 'Zig B b2', '{}'),
  ('e2000000-0000-4000-8000-000000000112', 'e2000000-0000-4000-8000-00000000000b', 'controlid_rep', 'REP B b2', '{}');
-- ------------------------------------------------------------------ fim do cenário comum

-- Serviço (Tips) de setembro: R$ 10.000,00 em duas lojas + R$ 999,99 fora do período
insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000101', 'loja-1', 'Salão'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000101', 'loja-2', 'Terraço');
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total) values
  ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-09-01', 'a', 'Tip', 600000, 1, 600000),
  ('e2000000-0000-4000-8000-00000000000a', 'loja-2', '2026-09-30', 'b', 'Tip', 400000, 1, 400000),
  ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-09-15', 'c', 'Normal', 50000, 1, 50000),
  ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-10-01', 'd', 'Tip', 99999, 1, 99999);
-- presença: todos com batida válida em todos os dias de setembro; Eva só em 15 dias
update public.ponto_dias set batidas_validas = 2
 where data between '2026-09-01' and '2026-09-30'
   and (funcionario_id <> 'e2000000-0000-4000-8000-000000000305' or data <= '2026-09-15');

create temp table fx (nome text primary key, id uuid) on commit drop;
grant all on fx to authenticated;

select teste.como('b2.ger.a@teste.local');
insert into fx select 'f1', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', p_modo_rateio => 'periodo');
create temp view fc as select * from public.comissao_fechamentos where id = (select id from fx where nome = 'f1');
create temp view it as select * from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1');
grant select on fc, it to authenticated;

select teste.ok('rascunho criado com título padrão e retenção da empresa',
  (select (status, titulo, percentual_retencao, servico_zig_centavos, dias_periodo, criado_por, modo_rateio)
     = ('rascunho'::text, 'Comissão 01/09 a 30/09/2026'::text, 20.00, 1000000::bigint, 30, 'e2000000-0000-4000-8000-000000000a02'::uuid, 'periodo'::text) from fc));
select teste.ok('modo período: tabelas de detalhe vazias', not exists (select 1 from public.comissao_rateio_dias where fechamento_id = (select id from fx where nome = 'f1')));
select teste.erro('modo de rateio inválido', $$select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', p_modo_rateio => 'semanal')$$,
  'Modo de rateio inválido', '22023');
select teste.ok('participantes: os 5 de A com pontos vigentes (snapshot de nome e cargo)',
  (select array_agg(funcionario_nome || '/' || cargo || '/' || pontos order by funcionario_nome) from it)
  = array['Ana Souza/Garçom/10.00', 'Bruno Lima/Garçom/10.00', 'Carla Dias/Cumim/6.00', 'Davi Rocha/Bartender/8.00', 'Eva Martins/Cozinha/4.00']);

select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, -5000, null, null, '  ');
select teste.ok('§9: bruto 995000, retenção 199000, base 796000, soma 38, valor do ponto 20947,368421',
  (select (servico_ajuste_centavos, servico_bruto_centavos, retencao_centavos, base_distribuivel_centavos, soma_pontos_efetivos, valor_ponto_centavos, observacoes)
     is not distinct from (-5000::bigint, 995000::bigint, 199000::bigint, 796000::bigint, 38::numeric, 20947.368421::numeric, null::text) from fc));
select teste.ok('§9: maior resto (Davi, Ana, Bruno +1)',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from it)
  = array['Ana Souza=209474', 'Bruno Lima=209474', 'Carla Dias=125684', 'Davi Rocha=167579', 'Eva Martins=83789']);
select teste.ok('§9: soma exata = base', (select sum(valor_centavos) from it) = 796000);
select teste.ok('dias trabalhados contados por ponto_dias.batidas_validas > 0',
  (select array_agg(dias_trabalhados order by funcionario_nome) from it) = array[30, 30, 30, 30, 15]);

select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), 'Comissão setembro', -5000, 20, true, 'Proporcional');
select teste.ok('§9 proporcional: Eva pe 2, soma 36, valor do ponto 22111,111111',
  (select (soma_pontos_efetivos, valor_ponto_centavos, titulo, observacoes) = (36::numeric, 22111.111111::numeric, 'Comissão setembro'::text, 'Proporcional'::text) from fc)
  and (select pontos_efetivos from it where funcionario_nome = 'Eva Martins') = 2);
select teste.ok('§9 proporcional: Davi 176889, Carla 132667, total 796000',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from it)
  = array['Ana Souza=221111', 'Bruno Lima=221111', 'Carla Dias=132667', 'Davi Rocha=176889', 'Eva Martins=44222']
  and (select sum(valor_centavos) from it) = 796000);

-- soma exata para muitas bases/pontos (propriedade)
do $$
declare v_base bigint; v_aj bigint; v_ok boolean := true; v_id uuid := (select id from fx where nome = 'f1');
begin
  perform public.comissao_definir_item(v_id, 'e2000000-0000-4000-8000-000000000301', 3.33);
  perform public.comissao_definir_item(v_id, 'e2000000-0000-4000-8000-000000000302', 0.01);
  perform public.comissao_definir_item(v_id, 'e2000000-0000-4000-8000-000000000303', 7.77);
  foreach v_aj in array array[-1000000, -999999, -999990, -500001, -123457, -1, 0, 1, 7, 99999, 3333333] loop
    perform public.comissao_atualizar_fechamento(v_id, null, v_aj, 13.37, true, null);
    select base_distribuivel_centavos into v_base from public.comissao_fechamentos where id = v_id;
    if v_base <> (select sum(valor_centavos) from public.comissao_itens where fechamento_id = v_id)
       or exists (select 1 from public.comissao_itens where fechamento_id = v_id and valor_centavos < 0) then
      v_ok := false;
    end if;
  end loop;
  perform teste.ok('propriedade: Σ valores = base para 11 bases diferentes (retenção 13,37%, pontos fracionários)', v_ok);
end $$;
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, -2000000, null, null, null);
select teste.ok('bruto nunca negativo', (select (servico_bruto_centavos, retencao_centavos, base_distribuivel_centavos) = (0::bigint, 0::bigint, 0::bigint) from fc)
  and (select sum(valor_centavos) from it) = 0);
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, 0, 0, false, null);
select teste.ok('retenção 0%: base = bruto', (select base_distribuivel_centavos from fc) = 1000000);
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, 1, 100, false, null);
select teste.ok('retenção 100%: base 0', (select (retencao_centavos, base_distribuivel_centavos) = (1000001::bigint, 0::bigint) from fc));
select teste.erro('retenção > 100 recusada', $$select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, 0, 100.01, false, null)$$,
  'Percentual de retenção inválido', '22023');
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, 0, 20, false, null);

-- itens: excluir da divisão, remover, outra empresa
select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000302', 10, false);
select teste.ok('item não incluído: pe 0 e valor 0', (select (pontos_efetivos, valor_centavos) = (0::numeric, 0::bigint) from it where funcionario_nome = 'Bruno Lima'));
select public.comissao_remover_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000303');
select teste.ok('item removido e total redistribuído', (select count(*) from it) = 4 and (select sum(valor_centavos) from it) = 800000);
select teste.erro('funcionário de outra empresa', $$select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000391', 1)$$,
  'Funcionário de outra empresa', '22023');
select teste.erro('pontos negativos', $$select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000303', -1)$$,
  'Pontos inválidos', '22023');
select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000303', null);
select teste.ok('definir item sem pontos usa os vigentes', (select pontos from it where funcionario_nome = 'Carla Dias') = 6);

-- loja e validações de criação
insert into fx select 'f_loja', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', 'Só terraço', 'loja-2', p_modo_rateio => 'periodo');
select teste.ok('fechamento por loja só soma os Tips da loja', (select servico_zig_centavos from public.comissao_fechamentos
   where id = (select id from fx where nome = 'f_loja')) = 400000);
select teste.erro('loja inexistente', $$select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', null, 'loja-x')$$, 'Loja não encontrada', 'P0002');
select teste.erro('período máximo de 93 dias', $$select public.comissao_criar_fechamento('2026-01-01', '2026-09-30')$$, 'Período máximo de 93 dias', '22023');
select teste.erro('período invertido', $$select public.comissao_criar_fechamento('2026-09-30', '2026-09-01')$$, 'Período inválido', '22023');
select public.comissao_excluir_rascunho((select id from fx where nome = 'f_loja'));
select teste.ok('rascunho excluído (com itens)', not exists (select 1 from public.comissao_fechamentos where id = (select id from fx where nome = 'f_loja'))
  and not exists (select 1 from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f_loja')));

-- sem participantes
insert into fx select 'vazio', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', 'Vazio', p_modo_rateio => 'periodo');
select public.comissao_definir_item((select id from fx where nome = 'vazio'), f, 1, false)
  from unnest(array['e2000000-0000-4000-8000-000000000301','e2000000-0000-4000-8000-000000000302','e2000000-0000-4000-8000-000000000303',
                    'e2000000-0000-4000-8000-000000000304','e2000000-0000-4000-8000-000000000305']::uuid[]) f;
select teste.ok('soma 0: valor do ponto null', (select (soma_pontos_efetivos, valor_ponto_centavos) is not distinct from (0::numeric, null::numeric)
   from public.comissao_fechamentos where id = (select id from fx where nome = 'vazio')));

-- fechar
select teste.erro('gerente não fecha', $$select public.comissao_fechar((select id from fx where nome = 'f1'))$$,
  'Somente o administrador fecha a comissão', '42501');
select teste.como('b2.adm.a@teste.local');
select teste.erro('fechar sem participantes', $$select public.comissao_fechar((select id from fx where nome = 'vazio'))$$,
  'Fechamento sem participantes', '22023');
-- serviço mudou depois do último cálculo: fechar recalcula
select teste.como_dono();
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total)
values ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-09-20', 'e', 'Tip', 10000, 1, 10000);
select teste.como('b2.adm.a@teste.local');
select public.comissao_fechar((select id from fx where nome = 'f1'));
select teste.ok('fechado: recalculado (serviço 1010000), autor e data', (select (status, servico_zig_centavos, fechado_por, fechado_em)
   = ('fechado'::text, 1010000::bigint, 'e2000000-0000-4000-8000-000000000a01'::uuid, '2026-10-06 12:00-03'::timestamptz) from fc)
  and (select sum(valor_centavos) from it) = (select base_distribuivel_centavos from fc));
select teste.erro('fechado: não atualiza', $$select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), 'x', 0, 20, false, null)$$,
  'Fechamento já está fechado', '22023');
select teste.erro('fechado: não define item', $$select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000301', 1)$$,
  'Fechamento já está fechado');
select teste.erro('fechado: não remove item', $$select public.comissao_remover_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000301')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: não recalcula', $$select public.comissao_recalcular((select id from fx where nome = 'f1'))$$, 'Fechamento já está fechado');
select teste.erro('fechado: não exclui', $$select public.comissao_excluir_rascunho((select id from fx where nome = 'f1'))$$, 'Fechamento já está fechado');
select teste.erro('fechado: não fecha de novo', $$select public.comissao_fechar((select id from fx where nome = 'f1'))$$, 'Fechamento já está fechado');
select teste.como('b2.master@teste.local');
select teste.erro('fechado: nem o master altera', $$select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), 'x', 0, 20, false, null)$$,
  'Fechamento já está fechado');
select teste.como_dono();
select teste.erro('fechado: UPDATE direto (dono) recusado', $$update public.comissao_fechamentos set titulo = 'x' where id = (select id from fx where nome = 'f1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: DELETE direto (dono) recusado', $$delete from public.comissao_fechamentos where id = (select id from fx where nome = 'f1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: UPDATE de item recusado', $$update public.comissao_itens set valor_centavos = 0 where fechamento_id = (select id from fx where nome = 'f1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: DELETE de item recusado', $$delete from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: INSERT de item recusado', $$insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_nome, pontos)
  values ('e2000000-0000-4000-8000-00000000000a', (select id from fx where nome = 'f1'), 'x', 1)$$, 'Fechamento já está fechado');
create temp table antes on commit drop as select * from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1');
delete from public.funcionarios where id = 'e2000000-0000-4000-8000-000000000304';
select teste.ok('excluir funcionário: item do fechado sobrevive (snapshot) com funcionario_id null',
  (select (funcionario_id, funcionario_nome, valor_centavos) is not distinct from (null::uuid, 'Davi Rocha'::text,
          (select valor_centavos from antes where funcionario_nome = 'Davi Rocha')) from public.comissao_itens
     where fechamento_id = (select id from fx where nome = 'f1') and funcionario_nome = 'Davi Rocha'));

-- permissões e isolamento
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura não vê comissões', teste.contar('select * from public.comissao_fechamentos') = 0
  and teste.contar('select * from public.comissao_itens') = 0);
select teste.erro('leitura não cria fechamento', $$select public.comissao_criar_fechamento('2026-09-01', '2026-09-30')$$, 'Sem permissão', '42501');
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B não vê comissões de A', teste.contar('select * from public.comissao_fechamentos') = 0);
select teste.erro('admin B não recalcula fechamento de A', $$select public.comissao_recalcular((select id from fx where nome = 'vazio'))$$, 'Sem permissão', '42501');
select teste.erro('fechamento inexistente', $$select public.comissao_recalcular(gen_random_uuid())$$, 'Fechamento não encontrado', 'P0002');
select teste.erro('authenticated não escreve direto', $$insert into public.comissao_fechamentos (empresa_id, titulo, data_inicio, data_fim, percentual_retencao)
  values ('e2000000-0000-4000-8000-00000000000b', 'x', '2026-09-01', '2026-09-02', 20)$$, null, '42501');
select teste.como('b2.adm.a@teste.local');
select teste.ok('admin A vê os fechamentos de A', teste.contar('select * from public.comissao_fechamentos') = 2);
select teste.ok('padrão de fechamento novo é o rateio diário', (select column_default from information_schema.columns
   where table_schema = 'public' and table_name = 'comissao_fechamentos' and column_name = 'modo_rateio') like '''diario''%');

-- excluir a empresa inteira (master) apaga em cascata até o fechado
select teste.como_dono();
delete from public.empresas where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('exclusão da empresa em cascata leva o fechamento fechado', not exists (select 1 from public.comissao_fechamentos
   where empresa_id = 'e2000000-0000-4000-8000-00000000000a') and not exists (select 1 from public.comissao_itens
   where empresa_id = 'e2000000-0000-4000-8000-00000000000a'));

-- =====================================================================================================
-- Rateio diário (adendo extras v2, E.3): vetores V1–V5, fallback, extra, manual, sem participantes, fechado imutável
-- e propriedade Σ valores = Σ bases (centavo a centavo).
-- =====================================================================================================
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e2000000-0000-4000-8000-00000000000c', 'Teste b2 C', 'America/Sao_Paulo', '05:00');
insert into public.funcionarios (id, empresa_id, nome, cargo, pontos_comissao, data_admissao) values
  ('e2000000-0000-4000-8000-000000000c01', 'e2000000-0000-4000-8000-00000000000c', 'Ana Souza', 'Garçom', 10, '2026-01-01'),
  ('e2000000-0000-4000-8000-000000000c02', 'e2000000-0000-4000-8000-00000000000c', 'Bruno Lima', 'Garçom', 10, '2026-01-01'),
  ('e2000000-0000-4000-8000-000000000c03', 'e2000000-0000-4000-8000-00000000000c', 'Carla Dias', 'Cumim', 6, '2026-01-01');
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e2000000-0000-4000-8000-000000000c91', 'e2000000-0000-4000-8000-00000000000c', 'zig', 'Zig C', '{}');
insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome) values
  ('e2000000-0000-4000-8000-00000000000c', 'e2000000-0000-4000-8000-000000000c91', 'loja-c', 'Salão C');
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total) values
  ('e2000000-0000-4000-8000-00000000000c', 'loja-c', '2026-09-01', 'c1', 'Tip', 100000, 1, 100000),
  ('e2000000-0000-4000-8000-00000000000c', 'loja-c', '2026-09-02', 'c2', 'Tip', 50001, 1, 50001),
  ('e2000000-0000-4000-8000-00000000000c', 'loja-c', '2026-09-03', 'c3', 'Tip', 30000, 1, 30000);
-- presença: 01/09 Ana, Bruno, Carla; 02/09 Ana, Carla; 03/09 ninguém (fallback)
insert into public.ponto_dias (funcionario_id, data, empresa_id, batidas_validas, situacao, encerrado)
select f, d::date, 'e2000000-0000-4000-8000-00000000000c', 0, 'ausente', true
  from unnest(array['e2000000-0000-4000-8000-000000000c01', 'e2000000-0000-4000-8000-000000000c02',
                    'e2000000-0000-4000-8000-000000000c03']::uuid[]) f,
       generate_series('2026-08-01'::date, '2026-09-03'::date, interval '1 day') d
on conflict (funcionario_id, data) do update set batidas_validas = 0;
update public.ponto_dias set batidas_validas = 2, situacao = 'completo'
 where (funcionario_id, data) in (('e2000000-0000-4000-8000-000000000c01', '2026-09-01'), ('e2000000-0000-4000-8000-000000000c02', '2026-09-01'),
                                  ('e2000000-0000-4000-8000-000000000c03', '2026-09-01'), ('e2000000-0000-4000-8000-000000000c01', '2026-09-02'),
                                  ('e2000000-0000-4000-8000-000000000c03', '2026-09-02'));

select teste.como('b2.master@teste.local');
create temp table fd (nome text primary key, id uuid) on commit drop;
grant all on fd to authenticated;
insert into fd select 'marcos', public.extra_criar('Marcos Freitas', 'Garçom', 5, 18000, p_empresa => 'e2000000-0000-4000-8000-00000000000c');
insert into fd select 'm1', public.diaria_lancar('2026-09-01', (select id from fd where nome = 'marcos'));
insert into fd select 'm2', public.diaria_lancar('2026-09-02', (select id from fd where nome = 'marcos'), null, 7.5);
insert into fd select 'v1', public.comissao_criar_fechamento('2026-09-01', '2026-09-03', p_empresa => 'e2000000-0000-4000-8000-00000000000c');
create temp view dfc as select * from public.comissao_fechamentos where id = (select id from fd where nome = 'v1');
create temp view dit as select * from public.comissao_itens where fechamento_id = (select id from fd where nome = 'v1');
create temp view ddia as select * from public.comissao_rateio_dias where fechamento_id = (select id from fd where nome = 'v1');
create temp view dri as select ri.*, it.funcionario_nome from public.comissao_rateio_itens_dia ri join public.comissao_itens it on it.id = ri.item_id
  where ri.fechamento_id = (select id from fd where nome = 'v1');
grant select on dfc, dit, ddia, dri to authenticated;

select teste.ok('diário é o padrão; extra lançado entra sozinho', (select modo_rateio from dfc) = 'diario'
  and (select array_agg(funcionario_nome || '/' || tipo order by funcionario_nome) from dit)
      = array['Ana Souza/funcionario', 'Bruno Lima/funcionario', 'Carla Dias/funcionario', 'Marcos Freitas/extra']);
select teste.ok('V1: dias (serviço, retenção, base, soma, participantes, fallback)',
  (select array_agg(data || '=' || servico_zig_centavos || '/' || ajuste_centavos || '/' || retencao_centavos || '/' || base_centavos
                    || '/' || soma_pontos || '/' || participantes || '/' || sem_presenca order by data) from ddia)
  = array['2026-09-01=100000/0/20000/80000/31.00/4/false', '2026-09-02=50001/0/10000/40001/23.50/3/false',
          '2026-09-03=30000/0/6000/24000/26.00/3/true']);
select teste.ok('V1: valores por dia (maior resto por dia, desempate por nome)',
  (select array_agg(to_char(data, 'DD') || ':' || funcionario_nome || '=' || valor_centavos || case when fallback then '*' else '' end
                    order by data, funcionario_nome) from dri)
  = array['01:Ana Souza=25807', '01:Bruno Lima=25806', '01:Carla Dias=15484', '01:Marcos Freitas=12903',
          '02:Ana Souza=17022', '02:Carla Dias=10213', '02:Marcos Freitas=12766',
          '03:Ana Souza=9231*', '03:Bruno Lima=9231*', '03:Carla Dias=5538*']);
select teste.ok('V1: totais dos itens e do fechamento',
  (select array_agg(funcionario_nome || '=' || valor_centavos || '/' || pontos || '/' || dias_presentes || '/' || pontos_efetivos
                    order by funcionario_nome) from dit)
  = array['Ana Souza=52060/10.00/2/30.000000', 'Bruno Lima=35037/10.00/1/20.000000', 'Carla Dias=31235/6.00/2/18.000000',
          'Marcos Freitas=25669/6.25/2/12.500000']
  and (select (servico_zig_centavos, servico_bruto_centavos, retencao_centavos, base_distribuivel_centavos, soma_pontos_efetivos,
               dias_sem_presenca, dias_sem_participantes)
         = (180001::bigint, 180001::bigint, 36000::bigint, 144001::bigint, 80.5::numeric, 1, 0) from dfc)
  and (select sum(valor_centavos) from dit) = 144001);

select public.comissao_atualizar_fechamento((select id from fd where nome = 'v1'), null, 1000, null, null, null);
select teste.ok('V2: ajuste +1000 repartido pelo serviço (555, 278, 167)',
  (select array_agg(ajuste_centavos || '/' || retencao_centavos || '/' || base_centavos order by data) from ddia)
  = array['555/20111/80444', '278/10056/40223', '167/6033/24134']
  and (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from dit)
      = array['Ana Souza=52348', 'Bruno Lima=35231', 'Carla Dias=31410', 'Marcos Freitas=25812']
  and (select (retencao_centavos, base_distribuivel_centavos) = (36200::bigint, 144801::bigint) from dfc));
select public.comissao_atualizar_fechamento((select id from fd where nome = 'v1'), null, -500, null, null, null);
select teste.ok('V3: ajuste −500 (−278, −139, −83)',
  (select array_agg(ajuste_centavos || '/' || servico_bruto_centavos || '/' || base_centavos order by data) from ddia)
  = array['-278/99722/79778', '-139/49862/39890', '-83/29917/23934']
  and (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from dit)
      = array['Ana Souza=51915', 'Bruno Lima=34940', 'Carla Dias=31149', 'Marcos Freitas=25598']
  and (select sum(valor_centavos) from dit) = 143602);
select public.comissao_atualizar_fechamento((select id from fd where nome = 'v1'), null, -180501, null, null, null);
select teste.ok('V5: ajuste ≤ −serviço zera tudo (presentes gravados com valor 0, sem fallback)',
  (select bool_and(servico_bruto_centavos = 0 and base_centavos = 0 and not sem_presenca) from ddia)
  and (select count(*) from dri) = 7 and (select sum(valor_centavos) from dri) = 0
  and (select (servico_bruto_centavos, base_distribuivel_centavos, dias_sem_presenca) = (0::bigint, 0::bigint, 0) from dfc));

-- pontos manuais: valem em todos os dias (presença e fallback); null volta para o automático
select public.comissao_atualizar_fechamento((select id from fd where nome = 'v1'), null, 0, null, null, null);
select public.comissao_definir_item((select id from fd where nome = 'v1'), 'e2000000-0000-4000-8000-000000000c02', 20);
select teste.ok('pontos manuais do funcionário usados no dia e no fallback',
  (select array_agg(to_char(data, 'DD') || '=' || pontos order by data) from dri where funcionario_nome = 'Bruno Lima') = array['01=20.00', '03=20.00']
  and (select pontos_manual from dit where funcionario_nome = 'Bruno Lima')
  and (select sum(valor_centavos) from dit) = 144001);
select public.comissao_definir_item((select id from fd where nome = 'v1'), 'e2000000-0000-4000-8000-000000000c02', null);
select teste.ok('p_pontos null: automático de novo (V1)', not (select pontos_manual from dit where funcionario_nome = 'Bruno Lima')
  and (select valor_centavos from dit where funcionario_nome = 'Bruno Lima') = 35037);

-- tirar o extra: incluido = false e não volta sozinho
select public.comissao_definir_extra((select id from fd where nome = 'v1'), (select id from fd where nome = 'marcos'), false);
select public.comissao_recalcular((select id from fd where nome = 'v1'));
select teste.ok('extra tirado continua fora após recalcular; base do dia vai para os funcionários',
  (select (incluido, valor_centavos) = (false, 0::bigint) from dit where funcionario_nome = 'Marcos Freitas')
  and (select sum(valor_centavos) from dit) = 144001);
select public.comissao_definir_extra((select id from fd where nome = 'v1'), (select id from fd where nome = 'marcos'), true);
insert into fd select 'zeca', public.extra_criar('Zeca', null, 2, 100, p_empresa => 'e2000000-0000-4000-8000-00000000000c');
select teste.erro('incluir extra sem dias no período', $$select public.comissao_definir_extra((select id from fd where nome = 'v1'), (select id from fd where nome = 'zeca'), true)$$,
  'Extra sem dias lançados no período', '22023');

-- detalhe para o front
create temp table det on commit drop as select public.comissao_detalhe((select id from fd where nome = 'v1')) as j;
grant select on det to authenticated;
select teste.ok('comissao_detalhe: chaves, servico_dias, dias com rateio, itens com entrada',
  (select array_agg(k order by k) from det, jsonb_object_keys(j) k) = array['dias', 'fechamento', 'itens', 'servico_dias']
  and (select jsonb_path_query_array(j, '$.servico_dias[*].servico_zig_centavos') from det) = '[100000, 50001, 30000]'
  and (select jsonb_array_length(j -> 'dias' -> 0 -> 'rateio') from det) = 4
  and (select (j -> 'dias' -> 2 ->> 'sem_presenca')::boolean from det)
  and (select jsonb_path_query_array(j, '$.itens[*].nome') from det) = '["Ana Souza", "Bruno Lima", "Carla Dias", "Marcos Freitas"]'
  and (select jsonb_path_query_array(j, '$.itens[0].entrada[*].presente') from det) = '[true, true, false]'
  and (select j -> 'itens' -> 3 -> 'entrada' from det) = '[{"data": "2026-09-01", "pontos": 5.00, "pendente": false, "presente": true}, {"data": "2026-09-02", "pontos": 7.50, "pendente": false, "presente": true}]');

-- dia sem ninguém para ratear: fechar é recusado
select public.comissao_definir_item((select id from fd where nome = 'v1'), f, null, false)
  from unnest(array['e2000000-0000-4000-8000-000000000c01', 'e2000000-0000-4000-8000-000000000c02', 'e2000000-0000-4000-8000-000000000c03']::uuid[]) f;
select teste.ok('só o extra: dias 1 e 2 para ele, dia 3 sem participantes',
  (select dias_sem_participantes from dfc) = 1 and (select valor_centavos from dit where funcionario_nome = 'Marcos Freitas') = 80000 + 40001
  and (select sem_participantes from ddia where data = '2026-09-03'));
select teste.erro('fechar com dia sem participantes', $$select public.comissao_fechar((select id from fd where nome = 'v1'))$$,
  'Há dias com serviço sem participantes para ratear', '22023');
select public.comissao_definir_item((select id from fd where nome = 'v1'), f, null, true)
  from unnest(array['e2000000-0000-4000-8000-000000000c01', 'e2000000-0000-4000-8000-000000000c02', 'e2000000-0000-4000-8000-000000000c03']::uuid[]) f;

-- V4: sem serviço, ajuste +100, retenção 0% → 34, 33, 33
select teste.como_dono();
delete from public.zig_vendas_itens where empresa_id = 'e2000000-0000-4000-8000-00000000000c';
select teste.como('b2.master@teste.local');
select public.comissao_atualizar_fechamento((select id from fd where nome = 'v1'), null, 100, 0, null, null);
select teste.ok('V4: ajuste sem serviço repartido igual (34, 33, 33)',
  (select array_agg(ajuste_centavos order by data) from ddia) = array[34::bigint, 33, 33]
  and (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from dit)
      = array['Ana Souza=38', 'Bruno Lima=24', 'Carla Dias=22', 'Marcos Freitas=16']);

-- fechar e imutabilidade do detalhe; trava dos dias do extra
select public.comissao_fechar((select id from fd where nome = 'v1'));
select teste.ok('fechado (diário)', (select status from dfc) = 'fechado');
select teste.erro('fechado: lançar dia de extra no período', $$select public.diaria_lancar('2026-09-03', (select id from fd where nome = 'marcos'))$$,
  'Período de comissão já fechado', '22023');
insert into fd select 'm_jul', public.diaria_lancar('2026-07-20', (select id from fd where nome = 'marcos'));
select teste.erro('um lançamento por extra por dia', $$select public.diaria_lancar('2026-07-20', (select id from fd where nome = 'marcos'))$$,
  'Extra já tem dia lançado em 20/07/2026', '23505');
select public.diaria_excluir((select id from fd where nome = 'm_jul'));
select teste.erro('fechado: mudar pontos do dia', $$select public.diaria_atualizar((select id from fd where nome = 'm1'), null, 9, null, null, null, null, null)$$,
  'Período de comissão já fechado', '22023');
select teste.erro('fechado: mover o dia para fora', $$select public.diaria_atualizar((select id from fd where nome = 'm1'), '2026-07-21', null, null, null, null, null, null)$$,
  'Período de comissão já fechado', '22023');
select teste.erro('fechado: excluir o dia', $$select public.diaria_excluir((select id from fd where nome = 'm1'))$$, 'Período de comissão já fechado', '22023');
select public.diaria_atualizar((select id from fd where nome = 'm1'), null, null, 20000, 'Cumim', 'Ajuda no evento', true, '2026-09-05');
select public.diaria_marcar_paga((select id from fd where nome = 'm2'), true);
select teste.ok('fechado: valor, função, observação e pagamento continuam editáveis',
  (select (valor_centavos, funcao, observacao, pago, pago_em, pontos) = (20000::bigint, 'Cumim'::text, 'Ajuda no evento'::text, true, '2026-09-05'::date, 5.00::numeric)
     from public.diarias where id = (select id from fd where nome = 'm1'))
  and (select pago_em from public.diarias where id = (select id from fd where nome = 'm2')) = '2026-10-06');
select teste.erro('fechado: extra com dias não é excluído', $$select public.extra_excluir((select id from fd where nome = 'marcos'))$$,
  'Extra com dias lançados: desative em vez de excluir', '22023');
select teste.como_dono();
select teste.erro('fechado: UPDATE do detalhe diário recusado', $$update public.comissao_rateio_dias set base_centavos = 0 where fechamento_id = (select id from fd where nome = 'v1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: DELETE do rateio por item recusado', $$delete from public.comissao_rateio_itens_dia where fechamento_id = (select id from fd where nome = 'v1')$$,
  'Fechamento já está fechado');
select teste.erro('fechado: INSERT no detalhe recusado', $$insert into public.comissao_rateio_dias (fechamento_id, empresa_id, data) values ((select id from fd where nome = 'v1'), 'e2000000-0000-4000-8000-00000000000c', '2026-09-10')$$,
  'Fechamento já está fechado');
select teste.erro('item: funcionário e extra ao mesmo tempo é recusado', $$insert into public.comissao_itens (fechamento_id, empresa_id, tipo, funcionario_id, extra_id, funcionario_nome, pontos)
  values ((select id from fd where nome = 'v1'), 'e2000000-0000-4000-8000-00000000000c', 'extra', 'e2000000-0000-4000-8000-000000000c01', (select id from fd where nome = 'marcos'), 'x', 1)$$, null, null);

-- propriedade (agosto, 31 dias): serviço/presença/extras pseudoaleatórios, vários ajustes e retenções
select setseed(0.5);
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total)
select 'e2000000-0000-4000-8000-00000000000c', 'loja-c', d::date, 'p' || d::date, 'Tip', v, 1, v
  from generate_series('2026-08-01'::date, '2026-08-31'::date, interval '1 day') d,
       lateral (select case when random() < 0.15 then 0 else (random() * 300000)::bigint + 1 end as v) x;
update public.ponto_dias set batidas_validas = case when random() < 0.55 then 2 else 0 end
 where empresa_id = 'e2000000-0000-4000-8000-00000000000c' and data between '2026-08-01' and '2026-08-31';
update public.ponto_dias set batidas_validas = 0   -- dias sem ninguém → fallback
 where empresa_id = 'e2000000-0000-4000-8000-00000000000c' and data in ('2026-08-07', '2026-08-15', '2026-08-23');
select teste.como('b2.master@teste.local');
insert into fd select 'rita', public.extra_criar('Rita Gomes', 'Bar', 3.33, 12000, p_empresa => 'e2000000-0000-4000-8000-00000000000c');
select public.diaria_lancar(d::date, (select id from fd where nome = case when extract(day from d)::int % 2 = 0 then 'marcos' else 'rita' end),
                            null, round((random() * 9)::numeric, 2))
  from generate_series('2026-08-01'::date, '2026-08-31'::date, interval '1 day') d where random() < 0.5 and d::date <> '2026-08-15';
insert into fd select 'prop', public.comissao_criar_fechamento('2026-08-01', '2026-08-31', p_empresa => 'e2000000-0000-4000-8000-00000000000c');
do $$
declare v_id uuid := (select id from fd where nome = 'prop'); v_aj bigint; v_pct numeric; v_ok boolean := true; v_fb int := 0;
begin
  perform public.comissao_definir_item(v_id, 'e2000000-0000-4000-8000-000000000c03', 7.77);
  foreach v_aj in array array[-9999999, -1234567, -5000, -1, 0, 1, 7, 333, 99999, 3333333] loop
    foreach v_pct in array array[0, 13.37, 20, 33.33, 100] loop
      perform public.comissao_atualizar_fechamento(v_id, null, v_aj, v_pct, null, null);
      if (select sum(ajuste_centavos) from public.comissao_rateio_dias where fechamento_id = v_id) <> v_aj
         or (select (base_distribuivel_centavos, retencao_centavos, servico_bruto_centavos)
                    is distinct from (select (sum(base_centavos)::bigint, sum(retencao_centavos)::bigint, sum(servico_bruto_centavos)::bigint)
                                        from public.comissao_rateio_dias where fechamento_id = v_id)
               from public.comissao_fechamentos where id = v_id)
         or (select sum(valor_centavos) from public.comissao_itens where fechamento_id = v_id)
            <> (select base_distribuivel_centavos from public.comissao_fechamentos where id = v_id)
         or exists (select 1 from public.comissao_rateio_dias rd where rd.fechamento_id = v_id
                       and rd.base_centavos <> coalesce((select sum(ri.valor_centavos) from public.comissao_rateio_itens_dia ri
                                                          where ri.fechamento_id = v_id and ri.data = rd.data), 0))
         or exists (select 1 from public.comissao_rateio_itens_dia ri join public.comissao_rateio_dias rd
                      on rd.fechamento_id = ri.fechamento_id and rd.data = ri.data
                     where ri.fechamento_id = v_id and ri.valor_centavos - div(rd.base_centavos * ri.pontos, rd.soma_pontos) not in (0, 1))
         or exists (select 1 from public.comissao_itens where fechamento_id = v_id and valor_centavos < 0) then
        v_ok := false;
      end if;
      v_fb := v_fb + (select dias_sem_presenca from public.comissao_fechamentos where id = v_id);
    end loop;
  end loop;
  perform teste.ok('propriedade diária: Σ ajustes = ajuste, Σ dias = totais, Σ valores = Σ bases (por dia e no total), piso/piso+1 — 50 combinações', v_ok);
  perform teste.ok('propriedade diária: cenário tem fallback e extras',
    v_fb > 0 and (select count(*) from public.comissao_itens where fechamento_id = v_id and tipo = 'extra') = 2);
end $$;

select teste.como('b2.lei.a@teste.local');
select teste.erro('leitura não vê o detalhe', $$select public.comissao_detalhe((select id from fd where nome = 'v1'))$$, 'Sem permissão', '42501');
select teste.ok('leitura não enxerga as tabelas de detalhe', teste.contar('select * from public.comissao_rateio_dias') = 0
  and teste.contar('select * from public.comissao_rateio_itens_dia') = 0);
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não vê detalhe de C', $$select public.comissao_detalhe((select id from fd where nome = 'v1'))$$, 'Sem permissão', '42501');
select teste.erro('detalhe inexistente', $$select public.comissao_detalhe(gen_random_uuid())$$, 'Fechamento não encontrado', 'P0002');
select teste.como_dono();

rollback;

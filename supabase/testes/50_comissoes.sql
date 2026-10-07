-- 50_comissoes.sql (b2) — comissão: vetor obrigatório do §9 (padrão e proporcional), soma exata em centavos,
-- ciclo rascunho → fechado imutável, snapshot, permissões e isolamento.
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
insert into fx select 'f1', public.comissao_criar_fechamento('2026-09-01', '2026-09-30');
create temp view fc as select * from public.comissao_fechamentos where id = (select id from fx where nome = 'f1');
create temp view it as select * from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1');
grant select on fc, it to authenticated;

select teste.ok('rascunho criado com título padrão e retenção da empresa',
  (select (status, titulo, percentual_retencao, servico_zig_centavos, dias_periodo, criado_por)
     = ('rascunho'::text, 'Comissão 01/09 a 30/09/2026'::text, 20.00, 1000000::bigint, 30, 'e2000000-0000-4000-8000-000000000a02'::uuid) from fc));
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
insert into fx select 'f_loja', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', 'Só terraço', 'loja-2');
select teste.ok('fechamento por loja só soma os Tips da loja', (select servico_zig_centavos from public.comissao_fechamentos
   where id = (select id from fx where nome = 'f_loja')) = 400000);
select teste.erro('loja inexistente', $$select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', null, 'loja-x')$$, 'Loja não encontrada', 'P0002');
select teste.erro('período máximo de 93 dias', $$select public.comissao_criar_fechamento('2026-01-01', '2026-09-30')$$, 'Período máximo de 93 dias', '22023');
select teste.erro('período invertido', $$select public.comissao_criar_fechamento('2026-09-30', '2026-09-01')$$, 'Período inválido', '22023');
select public.comissao_excluir_rascunho((select id from fx where nome = 'f_loja'));
select teste.ok('rascunho excluído (com itens)', not exists (select 1 from public.comissao_fechamentos where id = (select id from fx where nome = 'f_loja'))
  and not exists (select 1 from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f_loja')));

-- sem participantes
insert into fx select 'vazio', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', 'Vazio');
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

-- excluir a empresa inteira (master) apaga em cascata até o fechado
select teste.como_dono();
delete from public.empresas where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('exclusão da empresa em cascata leva o fechamento fechado', not exists (select 1 from public.comissao_fechamentos
   where empresa_id = 'e2000000-0000-4000-8000-00000000000a') and not exists (select 1 from public.comissao_itens
   where empresa_id = 'e2000000-0000-4000-8000-00000000000a'));

rollback;

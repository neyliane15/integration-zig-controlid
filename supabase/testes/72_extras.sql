-- 72_extras.sql — Extras v2 (adendo E): cadastro de extras (freelas), dias trabalhados (extra com pontos / funcionário só custo),
-- trava por fechamento fechado, extra no modo período (V6), gastos_periodo; permissões (leitura não vê) e isolamento.
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

-- Serviço de setembro (R$ 10.000,00) e presença como no 50_comissoes (Eva só 15 dias)
insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000101', 'loja-1', 'Salão');
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total) values
  ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-09-01', 'a', 'Tip', 1000000, 1, 1000000),
  ('e2000000-0000-4000-8000-00000000000a', 'loja-1', '2026-10-02', 'd', 'Tip', 99999, 1, 99999);
update public.ponto_dias set batidas_validas = 2
 where data between '2026-09-01' and '2026-09-30'
   and (funcionario_id <> 'e2000000-0000-4000-8000-000000000305' or data <= '2026-09-15');

create temp table fx (nome text primary key, id uuid) on commit drop;
grant all on fx to authenticated;

-- ------------------------------------------------------------------ cadastro de extras (E.1)
select teste.como('b2.ger.a@teste.local');
insert into fx select 'marcos', public.extra_criar('  Marcos Freitas ', 'Garçom', 5, 18000, ' 11999990000 ', '', 'Freela de sábado');
insert into fx select 'julia', public.extra_criar('Júlia Ramos', 'Cozinha', 3, 15000);
insert into fx select 'zeca', public.extra_criar('Zeca', null, null, null);
select teste.ok('extra criado (textos aparados, vazio → null)',
  (select (nome, funcao, telefone, documento, pontos_padrao, valor_diaria_centavos, ativo, observacoes, empresa_id)
          is not distinct from ('Marcos Freitas'::text, 'Garçom'::text, '11999990000'::text, null::text, 5.00::numeric, 18000::bigint, true,
                                'Freela de sábado'::text, 'e2000000-0000-4000-8000-00000000000a'::uuid)
     from public.extras where id = (select id from fx where nome = 'marcos'))
  and (select (pontos_padrao, valor_diaria_centavos) is not distinct from (0::numeric, null::bigint) from public.extras where id = (select id from fx where nome = 'zeca')));
select teste.erro('extra sem nome', $$select public.extra_criar('  ')$$, 'Informe o nome', '22023');
select teste.erro('extra com pontos de 3 casas', $$select public.extra_criar('X', null, 1.234)$$, 'Pontos inválidos', '22023');
select teste.erro('extra com pontos acima do limite', $$select public.extra_criar('X', null, 10000)$$, 'Pontos inválidos', '22023');
select teste.erro('extra com valor negativo', $$select public.extra_criar('X', null, 1, -1)$$, 'Valor inválido', '22023');
select public.extra_atualizar((select id from fx where nome = 'zeca'), 'Zeca Pagodinho', 'Bar', 2.5, 9000, null, '123', false, null);
select teste.ok('extra atualizado (substitui tudo) e inativo',
  (select (nome, funcao, pontos_padrao, valor_diaria_centavos, documento, ativo) = ('Zeca Pagodinho'::text, 'Bar'::text, 2.5::numeric, 9000::bigint, '123'::text, false)
     from public.extras where id = (select id from fx where nome = 'zeca')));
select teste.ok('listar: só ativos por padrão, em ordem de nome',
  (select array_agg(nome order by 1) from (select nome from public.extras_listar()) l) = array['Júlia Ramos', 'Marcos Freitas']
  and (select count(*) from public.extras_listar(true)) = 3);
select teste.erro('extra inativo não recebe dia', $$select public.diaria_lancar('2026-09-10', (select id from fx where nome = 'zeca'))$$, 'Extra inativo', '22023');
select public.extra_excluir((select id from fx where nome = 'zeca'));
select teste.ok('extra sem dias é excluído', not exists (select 1 from public.extras where id = (select id from fx where nome = 'zeca')));
select teste.erro('extra inexistente', $$select public.extra_excluir(gen_random_uuid())$$, 'Extra não encontrado', 'P0002');

-- ------------------------------------------------------------------ dias trabalhados (E.2)
insert into fx select 'm10', public.diaria_lancar('2026-09-10', (select id from fx where nome = 'marcos'), null, null, null, null, null, true, '2026-09-11');
insert into fx select 'm11', public.diaria_lancar('2026-09-11', (select id from fx where nome = 'marcos'));
insert into fx select 'm12', public.diaria_lancar('2026-09-12', (select id from fx where nome = 'marcos'), null, 5, 18000, ' ', ' Evento ');
select teste.ok('dia do extra usa pontos, valor e função do cadastro',
  (select (tipo, pessoa_nome, funcao, pontos, valor_centavos, pago, pago_em, fechado) is not distinct from
          ('extra'::text, 'Marcos Freitas'::text, 'Garçom'::text, 5.00::numeric, 18000::bigint, true, '2026-09-11'::date, false)
     from public.diarias_listar('2026-09-01', '2026-10-06') where id = (select id from fx where nome = 'm10'))
  and (select observacao from public.diarias where id = (select id from fx where nome = 'm12')) = 'Evento');
select teste.erro('um lançamento por extra por dia', $$select public.diaria_lancar('2026-09-11', (select id from fx where nome = 'marcos'))$$,
  'Extra já tem dia lançado em 11/09/2026', '23505');
select teste.erro('nem extra nem funcionário', $$select public.diaria_lancar('2026-09-11')$$, 'Informe o extra ou o funcionário', '22023');
select teste.erro('extra e funcionário juntos', $$select public.diaria_lancar('2026-09-11', (select id from fx where nome = 'marcos'), 'e2000000-0000-4000-8000-000000000301')$$,
  'Informe o extra ou o funcionário', '22023');
select teste.erro('pontos inválidos no dia', $$select public.diaria_lancar('2026-09-13', (select id from fx where nome = 'marcos'), null, -1)$$, 'Pontos inválidos', '22023');
select teste.erro('diária de funcionário com pontos', $$select public.diaria_lancar('2026-09-13', null, 'e2000000-0000-4000-8000-000000000301', 2, 100)$$,
  'Diária de funcionário não tem pontos', '22023');
select teste.erro('funcionário sem valor padrão nem valor', $$select public.diaria_lancar('2026-09-13', null, 'e2000000-0000-4000-8000-000000000301')$$,
  'Informe o valor da diária', '22023');
insert into fx select 'xs', public.extra_criar('Sem Valor', null, 1);
select teste.erro('extra sem valor padrão nem valor', $$select public.diaria_lancar('2026-09-13', (select id from fx where nome = 'xs'))$$, 'Informe o valor da diária');
select teste.erro('valor negativo', $$select public.diaria_lancar('2026-09-13', (select id from fx where nome = 'marcos'), null, null, -1)$$, 'Valor inválido');
select teste.erro('data fora do limite', $$select public.diaria_lancar('2025-01-01', (select id from fx where nome = 'marcos'))$$, 'Data fora do limite');
select teste.erro('sem data', $$select public.diaria_lancar(null, (select id from fx where nome = 'marcos'))$$, 'Informe a data');
select public.funcionario_definir_valor_diaria('e2000000-0000-4000-8000-000000000305', 15000);
insert into fx select 'd_eva', public.diaria_lancar('2026-09-30', null, 'e2000000-0000-4000-8000-000000000305');
insert into fx select 'd_eva2', public.diaria_lancar('2026-09-30', null, 'e2000000-0000-4000-8000-000000000305', null, 1000);
select teste.ok('diária de funcionário: valor padrão, cargo, sem pontos, pode repetir o dia',
  (select (tipo, pessoa_nome, funcao, pontos, valor_centavos, pago, extra_id) is not distinct from
          ('funcionario'::text, 'Eva Martins'::text, 'Cozinha'::text, null::numeric, 15000::bigint, false, null::uuid)
     from public.diarias_listar('2026-09-01', '2026-10-06', 'funcionario') where id = (select id from fx where nome = 'd_eva')));
select public.diaria_excluir((select id from fx where nome = 'd_eva2'));
select teste.ok('valores padrão de funcionário listados', (select array_agg(valor_diaria_centavos) from public.funcionario_valores_diaria_listar()) = array[15000::bigint]);
insert into fx select 'x_tmp', public.diaria_lancar('2026-10-04', (select id from fx where nome = 'julia'));
select public.diaria_atualizar((select id from fx where nome = 'x_tmp'), '2026-10-05', 3.5, null, 'Salão', 'troca', true, null);
select teste.ok('atualizar dia: data, pontos, função, observação, pago (null mantém o valor)',
  (select (data, pontos, valor_centavos, funcao, observacao, pago, pago_em) = ('2026-10-05'::date, 3.5::numeric, 15000::bigint, 'Salão'::text, 'troca'::text, true, '2026-10-06'::date)
     from public.diarias where id = (select id from fx where nome = 'x_tmp')));
select public.diaria_atualizar((select id from fx where nome = 'x_tmp'), null, 3, null, null, null, null, null);
select teste.ok('atualizar com nulls: mantém data, valor e pagamento; função volta ao padrão',
  (select (data, pontos, funcao, observacao, pago) is not distinct from ('2026-10-05'::date, 3::numeric, 'Cozinha'::text, null::text, true)
     from public.diarias where id = (select id from fx where nome = 'x_tmp')));
select public.diaria_marcar_paga((select id from fx where nome = 'x_tmp'), false);
select public.diaria_marcar_paga((select id from fx where nome = 'x_tmp'), true, '2026-10-05');
select teste.erro('diária inexistente', $$select public.diaria_excluir(gen_random_uuid())$$, 'Diária não encontrada', 'P0002');
select teste.erro('tipo inválido no filtro', $$select * from public.diarias_listar('2026-09-01', '2026-10-06', 'avulso')$$, 'Tipo inválido', '22023');
select teste.ok('filtros por extra e por pago', (select count(*) from public.diarias_listar('2026-09-01', '2026-10-06', null, (select id from fx where nome = 'marcos'))) = 3
  and (select count(*) from public.diarias_listar('2026-09-01', '2026-10-06', null, null, null, true)) = 2);
select teste.erro('extra com dias não é excluído', $$select public.extra_excluir((select id from fx where nome = 'marcos'))$$,
  'Extra com dias lançados: desative em vez de excluir', '22023');

-- ------------------------------------------------------------------ V6: modo período + extra (E.3.3)
insert into fx select 'f1', public.comissao_criar_fechamento('2026-09-01', '2026-09-30', p_modo_rateio => 'periodo');
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, -5000, null, null, null);
create temp view it as select * from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1');
grant select on it to authenticated;
select teste.ok('V6: extra com 15 pontos em 30 dias vale pe 0,5 (Carla, Marcos e Davi +1)',
  (select array_agg(funcionario_nome || '=' || valor_centavos || '/' || pontos_efetivos order by funcionario_nome) from it)
  = array['Ana Souza=206753/10.000000', 'Bruno Lima=206753/10.000000', 'Carla Dias=124052/6.000000', 'Davi Rocha=165403/8.000000',
          'Eva Martins=82701/4.000000', 'Marcos Freitas=10338/0.500000']
  and (select sum(valor_centavos) from it) = 796000
  and (select (tipo, extra_id, pontos, dias_presentes) = ('extra'::text, (select id from fx where nome = 'marcos'), 5.00::numeric, 3) from it where funcionario_nome = 'Marcos Freitas'));
select teste.ok('pontos extras da v1 não existem mais',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'comissao_itens' and column_name = 'pontos_extras')
  and to_regclass('public.comissao_pontos_extras') is null
  and to_regprocedure('public.comissao_extra_lancar(uuid, date, numeric, text)') is null);

-- fechar: dias do extra no período ficam travados (pontos/data/existência); pagamento/valor livres
select teste.como('b2.adm.a@teste.local');
select public.comissao_fechar((select id from fx where nome = 'f1'));
select teste.erro('lançar dia de extra em período fechado', $$select public.diaria_lancar('2026-09-15', (select id from fx where nome = 'marcos'))$$,
  'Período de comissão já fechado', '22023');
select teste.erro('excluir dia de extra de período fechado', $$select public.diaria_excluir((select id from fx where nome = 'm11'))$$,
  'Período de comissão já fechado', '22023');
select teste.erro('mover dia de fora para dentro do período fechado', $$select public.diaria_atualizar((select id from fx where nome = 'x_tmp'), '2026-09-20', null, null, null, null, null, null)$$,
  'Período de comissão já fechado', '22023');
select teste.passa('pagar dia de extra de período fechado', $$select public.diaria_marcar_paga((select id from fx where nome = 'm11'), false)$$);
select teste.passa('diária de funcionário em período fechado é livre (só custo)',
  $$select public.diaria_excluir(public.diaria_lancar('2026-09-20', null, 'e2000000-0000-4000-8000-000000000301', null, 100))$$);
select teste.ok('listar: fechado = true só para dias de extra no período fechado',
  (select array_agg(tipo || '/' || fechado order by data, tipo) from public.diarias_listar('2026-09-01', '2026-09-30'))
  = array['extra/true', 'extra/true', 'extra/true', 'funcionario/false']);
select teste.como_dono();
create temp table fx_f1 on commit drop as select id from fx where nome = 'f1';
grant select on fx_f1 to service_role;
select teste.como_servico();
select teste.ok('exportação: itens com tipo/extra_id/dias_presentes (sem pontos_extras) e "dias"',
  (select bool_and(i ? 'tipo' and i ? 'extra_id' and i ? 'dias_presentes' and not i ? 'pontos_extras')
     from jsonb_array_elements(public.ingestao_fechamento_exportar((select id from fx_f1)) -> 'itens') i)
  and public.ingestao_fechamento_exportar((select id from fx_f1)) -> 'dias' = '[]'::jsonb);
select teste.como_dono();

-- ------------------------------------------------------------------ gastos_periodo (E.5)
select teste.como('b2.ger.a@teste.local');
insert into fx select 'f2', public.comissao_criar_fechamento('2026-10-01', '2026-10-06');   -- diário: Tip de 99999 em 02/10, sem presença
create temp table g on commit drop as select public.gastos_periodo('2026-09-01', '2026-10-06') as j;
grant select on g to authenticated;
select teste.ok('gastos: chaves de primeiro nível',
  (select array_agg(k order by k) from g, jsonb_object_keys(j) k) = array['empresa_id', 'fechamentos', 'fim', 'inicio', 'por_dia', 'por_pessoa', 'totais']);
select teste.ok('gastos: totais (diárias de extras e funcionário; comissão fechada 796000; prevista 79999 do rateio diário)',
  (select j -> 'totais' from g) = '{"diarias_pagas": 33000, "diarias_a_pagar": 51000, "diarias": 84000, "diarias_qtd": 5,
     "diarias_extras": 69000, "diarias_funcionarios": 15000,
     "comissoes_fechadas": 796000, "comissoes_previstas": 79999, "total": 880000, "total_com_previsto": 959999}'::jsonb);
select teste.ok('gastos: por_dia (um por dia; período em data_fim; diário no próprio dia)',
  (select jsonb_array_length(j -> 'por_dia') from g) = 36
  and (select sum((d ->> 'total')::bigint) from g, jsonb_array_elements(j -> 'por_dia') d) = 880000
  and (select (d ->> 'comissoes_fechadas')::bigint + (d ->> 'diarias_a_pagar')::bigint from g, jsonb_array_elements(j -> 'por_dia') d where d ->> 'data' = '2026-09-30') = 796000 + 15000
  and (select (d ->> 'comissoes_previstas')::bigint from g, jsonb_array_elements(j -> 'por_dia') d where d ->> 'data' = '2026-10-02') = 79999);
select teste.ok('gastos: por_pessoa (extra por x:, funcionário por f:, soma = total)',
  (select sum((p ->> 'total')::bigint) from g, jsonb_array_elements(j -> 'por_pessoa') p) = 880000
  and (select (p ->> 'chave', p ->> 'tipo', (p ->> 'diarias_qtd')::int, (p ->> 'total')::bigint)
         = ('x:' || (select id from fx where nome = 'marcos'), 'extra', 3, 54000 + 10338::bigint)
         from g, jsonb_array_elements(j -> 'por_pessoa') p where p ->> 'nome' = 'Marcos Freitas')
  and (select (p ->> 'chave', p ->> 'tipo', (p ->> 'total')::bigint) = ('f:e2000000-0000-4000-8000-000000000305', 'funcionario', 15000 + 82701::bigint)
         from g, jsonb_array_elements(j -> 'por_pessoa') p where p ->> 'nome' = 'Eva Martins'));
select teste.ok('gastos: fechamentos que contribuem, com valor no período',
  (select array_agg(f ->> 'status' || '/' || (f ->> 'modo_rateio') || '/' || (f ->> 'valor_no_periodo_centavos') order by f ->> 'data_fim')
     from g, jsonb_array_elements(j -> 'fechamentos') f) = array['fechado/periodo/796000', 'rascunho/diario/79999']);
select teste.ok('gastos: diário conta só os dias dentro do período',
  (public.gastos_periodo('2026-10-03', '2026-10-06') -> 'totais' ->> 'comissoes_previstas')::bigint = 0
  and (public.gastos_periodo('2026-10-02', '2026-10-02') -> 'totais' ->> 'comissoes_previstas')::bigint = 79999);
select teste.erro('gastos: período máximo 366', $$select public.gastos_periodo('2025-01-01', '2026-10-06')$$, 'Período máximo de 366 dias');

-- ------------------------------------------------------------------ permissões e isolamento
select teste.como('b2.lei.a@teste.local');
select teste.erro('leitura não vê gastos', $$select public.gastos_periodo('2026-09-01', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.erro('leitura não cria extra', $$select public.extra_criar('X')$$, 'Sem permissão', '42501');
select teste.erro('leitura não lista extras', $$select * from public.extras_listar()$$, 'Sem permissão', '42501');
select teste.erro('leitura não lança dia', $$select public.diaria_lancar('2026-10-05', (select id from fx where nome = 'julia'))$$, 'Sem permissão', '42501');
select teste.erro('leitura não lista diárias', $$select * from public.diarias_listar('2026-09-01', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.ok('leitura não enxerga extras (dados pessoais), diárias nem valores padrão',
  teste.contar('select * from public.extras') = 0 and teste.contar('select * from public.diarias') = 0
  and teste.contar('select * from public.funcionario_valores_diaria') = 0);
select teste.erro('leitura não define valor de diária', $$select public.funcionario_definir_valor_diaria('e2000000-0000-4000-8000-000000000301', 1)$$, 'Sem permissão');
select teste.erro('authenticated não escreve direto em extras', $$insert into public.extras (empresa_id, nome) values ('e2000000-0000-4000-8000-00000000000a', 'x')$$, null, '42501');
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não lança dia para extra de A', $$select public.diaria_lancar('2026-10-05', (select id from fx where nome = 'julia'))$$, 'Sem permissão');
select teste.erro('admin B não edita extra de A', $$select public.extra_atualizar((select id from fx where nome = 'julia'), 'x', null, 0, null, null, null, true, null)$$, 'Sem permissão');
select teste.erro('admin B não mexe em diária de A', $$select public.diaria_excluir((select id from fx where nome = 'd_eva'))$$, 'Sem permissão');
select teste.erro('admin B não lista extras de A', $$select * from public.extras_listar(false, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.ok('admin B não vê extras de A', teste.contar('select * from public.extras') = 0);
insert into fx select 'fb', public.comissao_criar_fechamento('2026-10-01', '2026-10-06');
select teste.erro('extra de outra empresa no fechamento', $$select public.comissao_definir_extra((select id from fx where nome = 'fb'), (select id from fx where nome = 'julia'), true)$$,
  'Extra de outra empresa', '22023');
select teste.ok('admin B: gastos da própria empresa zerados', (public.gastos_periodo('2026-10-01', '2026-10-06') -> 'totais' ->> 'total')::bigint = 0);
select teste.erro('admin B não vê gastos de A', $$select public.gastos_periodo('2026-09-01', '2026-10-06', 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.como('b2.master@teste.local');
select teste.ok('master vê gastos de A', (public.gastos_periodo('2026-09-01', '2026-10-06', 'e2000000-0000-4000-8000-00000000000a') -> 'totais' ->> 'total')::bigint = 880000);
select teste.como_dono();
rollback;

-- 40_zig.sql (b2) — ingestão Zig (lojas, saída de produtos, faturamento, bandeiras, compradores), idempotência
-- "substitui o dia", RPCs de vendas, venda por garçom e permissões.
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

select teste.como_servico();
select teste.ok('lojas: 2 inseridas, 1 ignorada (sem id)',
  public.ingestao_zig_lojas('e2000000-0000-4000-8000-000000000101',
    '[{"id": "loja-1", "name": "Salão"}, {"id": 2, "name": "Terraço"}, {"name": "sem id"}]')
  @> '{"lidos": 3, "gravados": 2, "ignorados": 1, "inseridos": 2, "atualizados": 0}');
select teste.ok('loja com id numérico vira texto', exists (select 1 from public.zig_lojas where loja_id_externo = '2'
   and empresa_id = 'e2000000-0000-4000-8000-00000000000a'));
select teste.erro('integração de outro tipo', $$select public.ingestao_zig_lojas('e2000000-0000-4000-8000-000000000102', '[]')$$,
  'Tipo de integração incompatível');
select teste.erro('integração inexistente', $$select public.ingestao_zig_lojas(gen_random_uuid(), '[]')$$, 'Integração não encontrada', 'P0002');

-- administrador desliga a sincronização de uma loja e tenta renomear (só `sincronizar` muda)
select teste.como('b2.adm.a@teste.local');
update public.zig_lojas set sincronizar = false, nome = 'Hackeado' where loja_id_externo = '2';
select teste.ok('admin muda só `sincronizar`', (select (sincronizar, nome) = (false, 'Terraço'::text) from public.zig_lojas where loja_id_externo = '2'
   and empresa_id = 'e2000000-0000-4000-8000-00000000000a'));
select teste.como('b2.ger.a@teste.local');
update public.zig_lojas set sincronizar = true where loja_id_externo = '2';
select teste.como_dono();
select teste.ok('gerente não altera lojas (RLS)', (select sincronizar from public.zig_lojas where loja_id_externo = '2'
   and empresa_id = 'e2000000-0000-4000-8000-00000000000a') = false);
select teste.como_servico();
select teste.ok('reimportar lojas: atualiza nome e preserva `sincronizar`',
  public.ingestao_zig_lojas('e2000000-0000-4000-8000-000000000101', '[{"id": "loja-1", "name": "Salão Principal"}, {"id": "2", "name": "Terraço"}]')
  @> '{"inseridos": 0, "atualizados": 2}');
select teste.ok('reimportação preservou sincronizar e atualizou o nome', (select sincronizar from public.zig_lojas where loja_id_externo = '2' and empresa_id = 'e2000000-0000-4000-8000-00000000000a') = false
  and (select nome from public.zig_lojas where loja_id_externo = 'loja-1' and empresa_id = 'e2000000-0000-4000-8000-00000000000a') = 'Salão Principal');

-- saída de produtos (formato cru da API)
create temp table itens (j jsonb) on commit drop;
grant select on itens to service_role;
insert into itens values ($$[
  {"transactionId": "t1", "transactionDate": "2026-10-05T21:10:00", "productId": 10, "productSku": "CHOPP", "productName": "Chopp",
   "productCategory": "Bebidas", "unitValue": 1500, "count": 2, "discountValue": 0, "employeeName": "Ana Souza", "type": "Normal",
   "eventId": 77, "eventDate": "2026-10-05T00:00:00", "invoiceId": "NF1", "additions": null},
  {"transactionId": "t1", "transactionDate": "2026-10-05T21:10:00Z", "productName": "Couvert", "unitValue": 1000, "count": 1,
   "discountValue": 200, "employeeName": "  ana souza ", "type": "Couvert"},
  {"transactionId": "t1", "productName": "Serviço", "unitValue": 380, "count": 1, "employeeName": "Ana Souza", "type": "Tip"},
  {"transactionId": "t2", "transactionDate": "2026-10-05T22:10:00-03:00", "productName": "Porção", "unitValue": 999, "count": 1.5,
   "discountValue": null, "employeeName": "Bruno Lima", "type": "Normal", "fractionalAmount": 1.5, "fractionUnit": "kg",
   "additions": [{"name": "Molho"}]},
  {"transactionId": "t3", "productName": "Gorjeta avulsa", "unitValue": 500, "count": 1, "employeeName": "", "type": "Gift"},
  {"transactionId": "t2", "productName": "Serviço", "unitValue": 150, "count": 1, "employeeName": "Bruno Lima", "type": "Tip"},
  {"productName": "sem transação", "unitValue": 1, "count": 1, "type": "Normal"}
]$$);
select teste.ok('saída de produtos: 6 gravados, 1 ignorado com índice do erro',
  (select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05', j) from itens)
  @> '{"lidos": 7, "gravados": 6, "ignorados": 1, "removidos": 0, "erros": [{"indice": 6}]}');
select teste.ok('valor_total = round(unit × qtd) − desconto (1499 = round(1498,5))',
  (select array_agg(valor_total order by id) from public.zig_vendas_itens where empresa_id = 'e2000000-0000-4000-8000-00000000000a')
  = array[3000, 800, 380, 1499, 500, 150]::bigint[]);
select teste.ok('mapeamentos: tipo desconhecido → Outro (cru preservado), employee vazio → null, additions null → [], ids texto, eventDate data',
  (select (tipo, tipo_original, employee_name) is not distinct from ('Outro'::text, 'Gift'::text, null::text)
     from public.zig_vendas_itens where transaction_id = 't3')
  and (select (additions, product_id, event_id, event_date, invoice_id, employee_name)
               = ('[]'::jsonb, '10'::text, '77'::text, '2026-10-05'::date, 'NF1'::text, 'Ana Souza'::text)
         from public.zig_vendas_itens where product_sku = 'CHOPP')
  and (select employee_name from public.zig_vendas_itens where product_name = 'Couvert') = 'ana souza');
select teste.ok('transactionDate: sem fuso = fuso da empresa; com Z/offset como veio',
  (select transaction_date from public.zig_vendas_itens where product_sku = 'CHOPP') = '2026-10-05 21:10:00-03'
  and (select transaction_date from public.zig_vendas_itens where product_name = 'Couvert') = '2026-10-05 21:10:00Z'
  and (select transaction_date from public.zig_vendas_itens where product_name = 'Porção') = '2026-10-05 22:10:00-03');
select teste.ok('cursor.ultimo_dia gravado', (select cursor ->> 'ultimo_dia' from public.integracoes
   where id = 'e2000000-0000-4000-8000-000000000101') = '2026-10-05');
-- reimportar o mesmo dia = mesmo resultado
select teste.ok('reimportar o dia substitui (removidos 6, gravados 6)',
  (select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05', j) from itens)
  @> '{"gravados": 6, "removidos": 6}');
select teste.ok('mesma quantidade após reimportar', (select count(*) from public.zig_vendas_itens where empresa_id = 'e2000000-0000-4000-8000-00000000000a') = 6);
select teste.ok('dia anterior não rebaixa o cursor',
  public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-01', '[]') @> '{"lidos": 0, "gravados": 0}');
select teste.ok('cursor mantido', (select cursor ->> 'ultimo_dia' from public.integracoes where id = 'e2000000-0000-4000-8000-000000000101') = '2026-10-05');
select teste.erro('loja inexistente', $$select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'loja-x', '2026-10-05', '[]')$$,
  'Loja não encontrada', 'P0002');
select teste.erro('loja de outra empresa', $$select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000111', 'loja-1', '2026-10-05', '[]')$$,
  'Loja não encontrada', 'P0002');
select teste.erro('itens que não são lista', $$select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05', '{"a":1}')$$,
  'Lista de itens inválida', '22023');

-- faturamento, bandeiras, compradores
select teste.ok('faturamento 05/10 loja-1', public.ingestao_zig_faturamento('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05',
  '[{"paymentId": 1, "paymentName": "Crédito", "value": 4000, "eventId": 77, "eventDate": "2026-10-05"},
    {"paymentId": 3, "paymentName": "Pix", "value": 2329}]') @> '{"gravados": 2}');
select public.ingestao_zig_faturamento('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-04', '[{"paymentId": 1, "paymentName": "Crédito", "value": 1000}]');
select public.ingestao_zig_faturamento('e2000000-0000-4000-8000-000000000101', '2', '2026-10-05', '[{"paymentId": 1, "paymentName": "Crédito", "value": 500}]');
select teste.ok('reimportar faturamento substitui', public.ingestao_zig_faturamento('e2000000-0000-4000-8000-000000000101', '2', '2026-10-05',
  '[{"paymentId": 1, "paymentName": "Crédito", "value": 500}]') @> '{"gravados": 1, "removidos": 1}');
select teste.ok('bandeiras: cada values[] vira uma linha', public.ingestao_zig_faturamento_bandeiras('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05',
  '[{"paymentId": 1, "paymentName": "Crédito", "values": [{"cardBrand": "Visa", "totalValue": 2500}, {"cardBrand": "Master", "totalValue": 1500}]}]')
  @> '{"lidos": 1, "gravados": 2}');
select teste.ok('soma das bandeiras', (select sum(valor) from public.zig_faturamento_bandeiras where empresa_id = 'e2000000-0000-4000-8000-00000000000a') = 4000);
select teste.ok('compradores sem dados pessoais', public.ingestao_zig_compradores('e2000000-0000-4000-8000-000000000101', 'loja-1', '2026-10-05',
  '[{"transactionId": "t1", "productsValue": 3800, "tipValue": 380, "userName": "Fulano", "userDocument": "12345678900", "userPhone": "11999", "userEmail": "f@x"},
    {"transactionId": "t2", "productsValue": 1499, "tipValue": 150, "userDocumentType": "CPF"}]') @> '{"gravados": 2}'
  and (select count(*) from information_schema.columns where table_name = 'zig_compradores'
         and column_name ~ '(user|document|phone|email|nome|name)') = 0);

-- leitura das vendas
select teste.como('b2.lei.a@teste.local');
select teste.ok('vendas_resumo 04–05/10', (select (faturamento, vendas, servico, descontos, transacoes, servico_compradores)
   = (7829::bigint, 5799::bigint, 530::bigint, 200::bigint, 3::bigint, 530::bigint)
   from public.vendas_resumo('2026-10-04', '2026-10-05')));
select teste.ok('vendas_resumo filtrado por loja', (select faturamento from public.vendas_resumo('2026-10-04', '2026-10-05', '2')) = 500);
select teste.ok('vendas_resumo vazio = zeros (1 linha)', (select (faturamento, vendas, servico, transacoes) = (0::bigint, 0::bigint, 0::bigint, 0::bigint)
   from public.vendas_resumo('2026-01-01', '2026-01-31')) and (select count(*) from public.vendas_resumo('2026-01-01', '2026-01-31')) = 1);
select teste.ok('faturamento por dia com zeros', (select array_agg(valor order by data) from public.vendas_faturamento_por_dia('2026-10-03', '2026-10-05'))
  = array[0, 1000, 6829]::bigint[]);
select teste.ok('faturamento por forma (valor desc)', (select array_agg(payment_name || '=' || valor) from public.vendas_faturamento_por_forma('2026-10-04', '2026-10-05'))
  = array['Crédito=5500', 'Pix=2329']);
create temp table g on commit drop as select * from public.vendas_por_garcom('2026-10-05', '2026-10-05');
select teste.ok('por garçom: ordem e agrupamento por nome normalizado', (select array_agg(coalesce(employee_name, '(sem)')) from g)
  = array['Ana Souza', 'Bruno Lima', '(sem)']);
select teste.ok('por garçom: Ana (vendas, serviço, quantidade, transações, vínculo)',
  (select (funcionario_id, funcionario_nome, quantidade, valor_vendas, valor_servico, transacoes)
     = ('e2000000-0000-4000-8000-000000000301'::uuid, 'Ana Souza'::text, 3::numeric, 3800::bigint, 380::bigint, 1::bigint)
     from g where employee_name = 'Ana Souza'));
select teste.ok('por garçom: Bruno 1,5 un', (select (quantidade, valor_vendas, valor_servico) = (1.5, 1499::bigint, 150::bigint) from g where employee_name = 'Bruno Lima'));
select teste.ok('por garçom: sem garçom sem funcionário', (select (funcionario_id, valor_vendas) is not distinct from (null::uuid, 500::bigint)
   from g where employee_name is null));
select teste.como('b2.ger.a@teste.local');
update public.funcionarios set zig_employee_name = '  BRUNO LIMA ' where id = 'e2000000-0000-4000-8000-000000000302';
update public.funcionarios set zig_employee_name = null where id = 'e2000000-0000-4000-8000-000000000301';
select teste.ok('vínculo garçom ↔ funcionário é feito na leitura (renomear corrige o histórico)',
  (select funcionario_id from public.vendas_por_garcom('2026-10-05', '2026-10-05') where employee_name = 'Bruno Lima') = 'e2000000-0000-4000-8000-000000000302'
  and (select funcionario_id from public.vendas_por_garcom('2026-10-05', '2026-10-05') where employee_name = 'Ana Souza') is null);
select teste.ok('gerente lê compradores', teste.contar('select * from public.zig_compradores') = 2);

-- permissões e isolamento
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura vê itens e faturamento, mas não compradores', teste.contar('select * from public.zig_vendas_itens') = 6
  and teste.contar('select * from public.zig_faturamento') = 4 and teste.contar('select * from public.zig_compradores') = 0);
select teste.erro('vendas: máx. 366 dias', $$select * from public.vendas_resumo('2025-01-01', '2026-10-05')$$, 'Período máximo de 366 dias', '22023');
select teste.erro('vendas: período inválido', $$select * from public.vendas_resumo('2026-10-05', '2026-10-01')$$, 'Período inválido', '22023');
select teste.erro('leitura não chama ingestão', $$select public.ingestao_zig_lojas('e2000000-0000-4000-8000-000000000101', '[]')$$, null, '42501');
select teste.erro('leitura não altera lojas (só admin)', $$insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome)
  values ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000101', 'z', 'z')$$, null, '42501');
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B não vê nada da Zig de A', teste.contar('select * from public.zig_vendas_itens') = 0
  and teste.contar('select * from public.zig_faturamento') = 0 and teste.contar('select * from public.zig_lojas') = 0
  and teste.contar('select * from public.zig_faturamento_bandeiras') = 0 and teste.contar('select * from public.zig_compradores') = 0);
select teste.erro('admin B não consulta vendas de A', $$select * from public.vendas_resumo('2026-10-01', '2026-10-05', null, 'e2000000-0000-4000-8000-00000000000a')$$,
  'Sem permissão', '42501');
select teste.ok('vendas de B zeradas', (select faturamento from public.vendas_resumo('2026-10-01', '2026-10-05')) = 0);
select teste.como(null);
select teste.erro('anon não lê vendas', $$select * from public.zig_vendas_itens$$, null, '42501');
select teste.erro('anon não chama vendas_resumo', $$select * from public.vendas_resumo('2026-10-01', '2026-10-05')$$, null, '42501');
select teste.como_dono();

rollback;

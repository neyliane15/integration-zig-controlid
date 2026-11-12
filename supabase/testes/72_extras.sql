-- 72_extras.sql — Extras (adendo E): pontos extras na comissão (vetores E.1), fechado imutável, diárias e gastos_periodo;
-- permissões (leitura não vê valores) e isolamento entre empresas.
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
-- Fábio: sem pontos base (só terá extras)
insert into public.funcionarios (id, empresa_id, nome, cargo, pontos_comissao, data_admissao) values
  ('e2000000-0000-4000-8000-000000000306', 'e2000000-0000-4000-8000-00000000000a', 'Fábio Nunes', 'Garçom', 0, '2026-01-01');

create temp table fx (nome text primary key, id uuid) on commit drop;
grant all on fx to authenticated;
create temp view it as select * from public.comissao_itens where fechamento_id = (select id from fx where nome = 'f1');
grant select on it to authenticated;

select teste.como('b2.ger.a@teste.local');
insert into fx select 'f1', public.comissao_criar_fechamento('2026-09-01', '2026-09-30');
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, -5000, null, null, null);
select teste.ok('vetor 1: sem extras, §9 inalterado e Fábio (0 pontos) fora',
  (select array_agg(funcionario_nome || '=' || valor_centavos || '/' || pontos_extras order by funcionario_nome) from it)
  = array['Ana Souza=209474/0.00', 'Bruno Lima=209474/0.00', 'Carla Dias=125684/0.00', 'Davi Rocha=167579/0.00', 'Eva Martins=83789/0.00']);

-- lançamentos
insert into fx select 'x_eva', public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000305', '2026-09-10', 1, 'Cobriu folga');
insert into fx select 'x_fab1', public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000306', '2026-09-20', 1, 'Meta batida');
insert into fx select 'x_fab2', public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000306', '2026-09-30', 2, 'Meta batida');
insert into fx select 'x_out', public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-10-01', 5, 'Fora do período');
select teste.ok('rascunho não muda sozinho ao lançar extra', (select sum(pontos_extras) from it) = 0 and (select count(*) from it) = 5);
select teste.erro('pontos extras 0', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-10', 0, 'x')$$, 'Pontos extras inválidos', '22023');
select teste.erro('pontos extras acima de 9999,99', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-10', 10000, 'x')$$, 'Pontos extras inválidos');
select teste.erro('pontos extras com 3 casas', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-10', 1.234, 'x')$$, 'Pontos extras inválidos');
select teste.erro('extra sem motivo', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-10', 1, '  ')$$, 'Informe o motivo');
select teste.erro('extra sem data', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', null, 1, 'x')$$, 'Informe a data');

select public.comissao_recalcular((select id from fx where nome = 'f1'));
select teste.ok('vetor 3: Eva +1 e Fábio só com 3 extras (entra com pontos 0)',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from it)
  = array['Ana Souza=189524', 'Bruno Lima=189524', 'Carla Dias=113714', 'Davi Rocha=151619', 'Eva Martins=94762', 'Fábio Nunes=56857']);
select teste.ok('vetor 3: Fábio pontos 0, extras 3, pe 3; soma 42; total = base',
  (select (pontos, pontos_extras, pontos_efetivos, incluido) = (0::numeric, 3::numeric, 3::numeric, true) from it where funcionario_nome = 'Fábio Nunes')
  and (select soma_pontos_efetivos from public.comissao_fechamentos where id = (select id from fx where nome = 'f1')) = 42
  and (select sum(valor_centavos) from it) = 796000);

-- vetor 2: proporcional + Carla 1,5 (sem os extras de Eva/Fábio)
select public.comissao_extra_excluir((select id from fx where nome = 'x_eva'));
select public.comissao_extra_excluir((select id from fx where nome = 'x_fab1'));
select public.comissao_extra_excluir((select id from fx where nome = 'x_fab2'));
insert into fx select 'x_carla', public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000303', '2026-09-05', 1.5, 'Cobriu folga');
select public.comissao_atualizar_fechamento((select id from fx where nome = 'f1'), null, -5000, 20, true, null);
select teste.ok('vetor 2: proporcional + Carla 1,5 extra (extras não proporcionalizados)',
  (select array_agg(funcionario_nome || '=' || valor_centavos || '/' || pontos_efetivos order by funcionario_nome) from it)
  = array['Ana Souza=212267/10.000000', 'Bruno Lima=212267/10.000000', 'Carla Dias=159200/7.500000', 'Davi Rocha=169813/8.000000',
          'Eva Martins=42453/2.000000', 'Fábio Nunes=0/0.000000']
  and (select sum(valor_centavos) from it) = 796000);

-- remover quem tem extras no período só desmarca
select public.comissao_remover_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000303');
select teste.ok('remover item com extras: fica com incluido = false e pe 0',
  (select (incluido, pontos_efetivos, valor_centavos) = (false, 0::numeric, 0::bigint) from it where funcionario_nome = 'Carla Dias'));
select public.comissao_remover_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000306');
select teste.ok('remover item sem extras: apaga', not exists (select 1 from it where funcionario_nome = 'Fábio Nunes'));
select public.comissao_definir_item((select id from fx where nome = 'f1'), 'e2000000-0000-4000-8000-000000000303', null, true);

-- listagem
select teste.ok('listar extras do período (rascunho: fechado = false)',
  (select array_agg(funcionario_nome || '/' || pontos || '/' || fechado order by data) from public.comissao_extras_listar('2026-09-01', '2026-10-06'))
  = array['Carla Dias/1.50/false', 'Ana Souza/5.00/false']);

-- fechar: período imutável para extras
select teste.como('b2.adm.a@teste.local');
select public.comissao_fechar((select id from fx where nome = 'f1'));
select teste.erro('lançar extra em período fechado', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-15', 1, 'x')$$,
  'Período de comissão já fechado', '22023');
select teste.erro('excluir extra de período fechado', $$select public.comissao_extra_excluir((select id from fx where nome = 'x_carla'))$$,
  'Período de comissão já fechado', '22023');
select teste.passa('extra fora do período fechado continua livre', $$select public.comissao_extra_excluir((select id from fx where nome = 'x_out'))$$);
select teste.ok('listar: fechado = true no período fechado',
  (select bool_and(fechado) from public.comissao_extras_listar('2026-09-01', '2026-09-30')));
select teste.ok('exportação traz pontos_extras dos itens',
  (select bool_and(i ? 'pontos_extras') from jsonb_array_elements(public.ingestao_fechamento_exportar((select id from fx where nome = 'f1')) -> 'itens') i));

-- permissões e isolamento (extras)
select teste.como('b2.lei.a@teste.local');
select teste.erro('leitura não lança extra', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-10-05', 1, 'x')$$, 'Sem permissão', '42501');
select teste.erro('leitura não lista extras', $$select * from public.comissao_extras_listar('2026-09-01', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.ok('leitura não enxerga a tabela de extras', teste.contar('select * from public.comissao_pontos_extras') = 0);
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não lança extra em funcionário de A', $$select public.comissao_extra_lancar('e2000000-0000-4000-8000-000000000301', '2026-10-05', 1, 'x')$$, 'Sem permissão');
select teste.ok('admin B não vê extras de A', teste.contar('select * from public.comissao_pontos_extras') = 0);
select teste.erro('admin B não lista extras de A', $$select * from public.comissao_extras_listar('2026-09-01', '2026-10-06', null, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');

-- ------------------------------------------------------------------ diárias
select teste.como('b2.ger.a@teste.local');
select public.funcionario_definir_valor_diaria('e2000000-0000-4000-8000-000000000305', 15000);
insert into fx select 'd_eva', public.diaria_lancar('2026-09-30', 'e2000000-0000-4000-8000-000000000305');
select teste.ok('diária do funcionário usa valor padrão, nome e cargo',
  (select (pessoa_nome, funcao, valor_centavos, pago, pago_em, avulso) is not distinct from ('Eva Martins'::text, 'Cozinha'::text, 15000::bigint, false, null::date, false)
     from public.diarias_listar('2026-09-01', '2026-10-06') where id = (select id from fx where nome = 'd_eva')));
insert into fx select 'd_freela', public.diaria_lancar('2026-10-05', null, '  Marcos Freitas ', 'Garçom', 18000, 'Evento', true);
select teste.ok('diária avulsa paga: pago_em = dia atual',
  (select (pessoa_nome, avulso, pago, pago_em, observacao) = ('Marcos Freitas'::text, true, true, '2026-10-06'::date, 'Evento'::text)
     from public.diarias_listar('2026-10-01', '2026-10-06') where id = (select id from fx where nome = 'd_freela')));
select teste.erro('diária sem funcionário nem nome', $$select public.diaria_lancar('2026-10-05', null, '  ', null, 100)$$, 'Informe o funcionário ou o nome', '22023');
select teste.erro('avulso sem valor', $$select public.diaria_lancar('2026-10-05', null, 'Zé', null, null)$$, 'Informe o valor da diária');
select teste.erro('funcionário sem valor padrão nem valor', $$select public.diaria_lancar('2026-10-05', 'e2000000-0000-4000-8000-000000000301')$$, 'Informe o valor da diária');
select teste.erro('valor negativo', $$select public.diaria_lancar('2026-10-05', null, 'Zé', null, -1)$$, 'Valor inválido');
select teste.erro('data fora do limite', $$select public.diaria_lancar('2025-01-01', null, 'Zé', null, 100)$$, 'Data fora do limite');
select public.diaria_marcar_paga((select id from fx where nome = 'd_eva'), true, '2026-10-01');
select teste.ok('marcar paga com data', (select (pago, pago_em) = (true, '2026-10-01'::date) from public.diarias where id = (select id from fx where nome = 'd_eva')));
select public.diaria_marcar_paga((select id from fx where nome = 'd_eva'), false);
select teste.ok('desmarcar limpa pago_em', (select (pago, pago_em) is not distinct from (false, null::date) from public.diarias where id = (select id from fx where nome = 'd_eva')));
insert into fx select 'd_x', public.diaria_lancar('2026-10-04', null, 'Temporário', null, 5000);
select public.diaria_atualizar((select id from fx where nome = 'd_x'), '2026-10-03', 'e2000000-0000-4000-8000-000000000301', null, 'Caixa', 7000, 'troca', true, '2026-10-04');
select teste.ok('atualizar diária: passa a ser do funcionário, valor e pagamento',
  (select (funcionario_id, pessoa_nome, funcao, valor_centavos, pago_em) = ('e2000000-0000-4000-8000-000000000301'::uuid, 'Ana Souza'::text, 'Caixa'::text, 7000::bigint, '2026-10-04'::date)
     from public.diarias where id = (select id from fx where nome = 'd_x')));
select public.diaria_excluir((select id from fx where nome = 'd_x'));
select teste.ok('excluir diária', not exists (select 1 from public.diarias where id = (select id from fx where nome = 'd_x')));
select teste.erro('diária inexistente', $$select public.diaria_excluir(gen_random_uuid())$$, 'Diária não encontrada', 'P0002');
select teste.ok('filtro por pago', (select count(*) from public.diarias_listar('2026-09-01', '2026-10-06', null, true)) = 1
  and (select count(*) from public.diarias_listar('2026-09-01', '2026-10-06', null, false)) = 1);
select teste.ok('valores padrão listados', (select array_agg(valor_diaria_centavos) from public.funcionario_valores_diaria_listar()) = array[15000::bigint]);

-- ------------------------------------------------------------------ gastos_periodo
insert into fx select 'f2', public.comissao_criar_fechamento('2026-10-01', '2026-10-06');
create temp table g on commit drop as select public.gastos_periodo('2026-09-01', '2026-10-06') as j;
grant select on g to authenticated;
select teste.ok('gastos: chaves de primeiro nível',
  (select array_agg(k order by k) from g, jsonb_object_keys(j) k) = array['empresa_id', 'fechamentos', 'fim', 'inicio', 'por_dia', 'por_pessoa', 'totais']);
select teste.ok('gastos: totais (diárias 15000 a pagar + 18000 pagas; comissão fechada 796000; prevista 79999)',
  (select j -> 'totais' from g) = '{"diarias_pagas": 18000, "diarias_a_pagar": 15000, "diarias": 33000, "diarias_qtd": 2,
     "comissoes_fechadas": 796000, "comissoes_previstas": 79999, "total": 829000, "total_com_previsto": 908999}'::jsonb);
select teste.ok('gastos: por_dia tem um registro por dia e soma = total',
  (select jsonb_array_length(j -> 'por_dia') from g) = 36
  and (select sum((d ->> 'total')::bigint) from g, jsonb_array_elements(j -> 'por_dia') d) = 829000
  and (select (d ->> 'comissoes_fechadas')::bigint from g, jsonb_array_elements(j -> 'por_dia') d where d ->> 'data' = '2026-09-30') = 796000
  and (select (d ->> 'diarias_a_pagar')::bigint from g, jsonb_array_elements(j -> 'por_dia') d where d ->> 'data' = '2026-09-30') = 15000);
select teste.ok('gastos: por_pessoa soma = total; Eva = diária + comissão; freela avulso',
  (select sum((p ->> 'total')::bigint) from g, jsonb_array_elements(j -> 'por_pessoa') p) = 829000
  and (select (p ->> 'total')::bigint from g, jsonb_array_elements(j -> 'por_pessoa') p where p ->> 'nome' = 'Eva Martins') = 15000 + 42453
  and (select (p ->> 'chave', (p ->> 'avulso')::boolean, (p ->> 'diarias_qtd')::int) = ('a:marcos freitas', true, 1)
         from g, jsonb_array_elements(j -> 'por_pessoa') p where p ->> 'nome' = 'Marcos Freitas')
  and (select (p ->> 'chave') from g, jsonb_array_elements(j -> 'por_pessoa') p where p ->> 'nome' = 'Ana Souza') = 'f:e2000000-0000-4000-8000-000000000301');
select teste.ok('gastos: fechamentos do período (fechado e rascunho)',
  (select array_agg(f ->> 'status' order by f ->> 'data_fim') from g, jsonb_array_elements(j -> 'fechamentos') f) = array['fechado', 'rascunho']);
select teste.erro('gastos: período máximo 366', $$select public.gastos_periodo('2025-01-01', '2026-10-06')$$, 'Período máximo de 366 dias');

select teste.como('b2.lei.a@teste.local');
select teste.erro('leitura não vê gastos', $$select public.gastos_periodo('2026-09-01', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.erro('leitura não lança diária', $$select public.diaria_lancar('2026-10-05', null, 'Zé', null, 100)$$, 'Sem permissão', '42501');
select teste.erro('leitura não lista diárias', $$select * from public.diarias_listar('2026-09-01', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.ok('leitura não enxerga diárias nem valores padrão',
  teste.contar('select * from public.diarias') = 0 and teste.contar('select * from public.funcionario_valores_diaria') = 0);
select teste.erro('leitura não define valor de diária', $$select public.funcionario_definir_valor_diaria('e2000000-0000-4000-8000-000000000301', 1)$$, 'Sem permissão');
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não lança diária para funcionário de A', $$select public.diaria_lancar('2026-10-05', 'e2000000-0000-4000-8000-000000000301', null, null, 100)$$, 'Sem permissão');
select teste.erro('admin B não lança avulso na empresa A', $$select public.diaria_lancar('2026-10-05', null, 'Zé', null, 100, null, false, null, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.erro('admin B não mexe em diária de A', $$select public.diaria_excluir((select id from fx where nome = 'd_eva'))$$, 'Sem permissão');
select teste.ok('admin B: gastos da própria empresa zerados', (public.gastos_periodo('2026-10-01', '2026-10-06') -> 'totais' ->> 'total')::bigint = 0);
select teste.erro('admin B não vê gastos de A', $$select public.gastos_periodo('2026-09-01', '2026-10-06', 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.como('b2.master@teste.local');
select teste.ok('master vê gastos de A', (public.gastos_periodo('2026-09-01', '2026-10-06', 'e2000000-0000-4000-8000-00000000000a') -> 'totais' ->> 'total')::bigint = 829000);
select teste.como_dono();
rollback;

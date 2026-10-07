-- 56_comissao_desempate.sql (revisão 1) — rateio do maior resto: desempate por nome igual ao do front
-- (ordem de código de caractere = collate "C"), independente da collation do banco, e soma exata em valores extremos.
-- Vetor espelhado em web/src/lib/comissao.test.ts ("desempate por nome em ordem de código de caractere").
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();

insert into public.empresas (id, nome) values ('e5600000-0000-4000-8000-00000000000a', 'Teste desempate');
insert into public.funcionarios (id, empresa_id, nome, pontos_comissao, data_admissao) values
  ('e5600000-0000-4000-8000-000000000301', 'e5600000-0000-4000-8000-00000000000a', 'Bruno', 1, '2026-01-01'),
  ('e5600000-0000-4000-8000-000000000302', 'e5600000-0000-4000-8000-00000000000a', 'ana', 1, '2026-01-01'),
  ('e5600000-0000-4000-8000-000000000303', 'e5600000-0000-4000-8000-00000000000a', 'Ágata', 1, '2026-01-01');

-- Simula um banco com collation linguística (o Supabase não usa "C"): a coluna passa a ordenar ana < Ágata < Bruno.
alter table public.comissao_itens alter column funcionario_nome type text collate "pt-BR-x-icu";

create temp table fx (id uuid) on commit drop;
insert into fx select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', null, null, false,
                                                       'e5600000-0000-4000-8000-00000000000a');
-- base = 100 centavos (só ajuste, retenção 0%), 3 participantes com 1 ponto: 33 + 33 + 33 e sobra 1 centavo
select public.comissao_atualizar_fechamento((select id from fx), null, 100, 0, false, null);

select teste.ok('base 100 distribuída exatamente',
  (select sum(valor_centavos) from public.comissao_itens where fechamento_id = (select id from fx)) = 100);
select teste.ok('centavo extra vai para "Bruno" (ordem de código de caractere: B < a < Á), como no front',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome collate "C")
     from public.comissao_itens where fechamento_id = (select id from fx))
  = array['Bruno=34', 'ana=33', 'Ágata=33']);

-- funcionario_id null (snapshot de funcionário excluído) vai para o fim do desempate (nulls last), como no front
update public.comissao_itens set funcionario_nome = 'Mesmo Nome' where fechamento_id = (select id from fx);
delete from public.funcionarios where id = 'e5600000-0000-4000-8000-000000000301';   -- vira snapshot sem id
select public.comissao_recalcular((select id from fx));
select teste.ok('nomes iguais: o menor funcionario_id leva o centavo e o snapshot sem id fica por último',
  (select array_agg(coalesce(funcionario_id::text, 'null') || '=' || valor_centavos order by funcionario_id nulls last)
     from public.comissao_itens where fechamento_id = (select id from fx))
  = array['e5600000-0000-4000-8000-000000000302=34', 'e5600000-0000-4000-8000-000000000303=33', 'null=33']);

-- Valores extremos: soma sempre exata (piso e resto por div/mod, sem divisão numérica arredondada)
insert into public.funcionarios (empresa_id, nome, pontos_comissao, data_admissao)
select 'e5600000-0000-4000-8000-00000000000a', 'Extra ' || g, (array[999999.99, 0.01, 333333.33, 7.77])[1 + g % 4], '2026-01-01'
  from generate_series(1, 37) g;
create temp table fx2 (id uuid) on commit drop;
insert into fx2 select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', null, null, false,
                                                        'e5600000-0000-4000-8000-00000000000a');
select public.comissao_atualizar_fechamento((select id from fx2), null, 999999999999937, 13.37, false, null);
select teste.ok('valores extremos: Σ valor_centavos = base distribuível',
  (select sum(i.valor_centavos) = f.base_distribuivel_centavos
     from public.comissao_itens i join public.comissao_fechamentos f on f.id = i.fechamento_id
    where f.id = (select id from fx2) group by f.base_distribuivel_centavos));
select teste.ok('valores extremos: cada valor = piso exato ou piso + 1',
  not exists (select 1 from public.comissao_itens i join public.comissao_fechamentos f on f.id = i.fechamento_id
               where f.id = (select id from fx2)
                 and i.valor_centavos - div(f.base_distribuivel_centavos * i.pontos_efetivos, f.soma_pontos_efetivos) not in (0, 1)));
rollback;

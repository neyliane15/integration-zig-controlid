-- Comissão: todos os funcionários que participam aparecem no fechamento, mesmo com 0 ponto (o gerente pontua ali mesmo).
-- Rascunhos já criados ganham quem ficou de fora (só os ativos que participam e estavam no período). Idempotente.
do $$
declare r record;
begin
  for r in select fc.id, fc.empresa_id, fc.data_inicio, fc.data_fim from public.comissao_fechamentos fc where fc.status = 'rascunho'
  loop
    insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, cargo, pontos)
    select r.empresa_id, r.id, f.id, f.nome, f.cargo, coalesce(public.comissao_pontos_vigentes(f.id, r.data_fim), 0)
      from public.funcionarios f
     where f.empresa_id = r.empresa_id and f.ativo and f.participa_comissao
       and (f.data_admissao is null or f.data_admissao <= r.data_fim)
       and (f.data_desligamento is null or f.data_desligamento >= r.data_inicio)
       and not exists (select 1 from public.comissao_itens it where it.fechamento_id = r.id and it.funcionario_id = f.id);
    if found then perform public.comissao_calcular(r.id); end if;
  end loop;
end $$;

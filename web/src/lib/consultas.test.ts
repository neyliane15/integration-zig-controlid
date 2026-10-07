import { expect, it } from 'vitest'
import { chaves } from './consultas'
import { atalhosPeriodo } from '@/componentes/ui'

it('query keys seguem o §14.8', () => {
  expect(chaves.painel('e')).toEqual(['painel', 'e'])
  expect(chaves.pontoDia('e', '2026-10-06')).toEqual(['ponto-dia', 'e', '2026-10-06'])
  expect(chaves.controlidUsuarios(undefined)).toEqual(['controlid-usuarios', null])
  expect(chaves.vendas('e', 'resumo', 'a', 'b', null)).toEqual(['vendas', 'e', 'resumo', 'a', 'b', null])
  expect(chaves.empresas()).toEqual(['empresas'])
})

it('atalhos de período', () => {
  const a = Object.fromEntries(atalhosPeriodo('2026-10-06').map((x) => [x.id, [x.inicio, x.fim]]))
  expect(a.hoje).toEqual(['2026-10-06', '2026-10-06'])
  expect(a.ontem).toEqual(['2026-10-05', '2026-10-05'])
  expect(a['7dias']).toEqual(['2026-09-30', '2026-10-06'])
  expect(a.mes).toEqual(['2026-10-01', '2026-10-06'])
  expect(a['mes-anterior']).toEqual(['2026-09-01', '2026-09-30'])
  const m = Object.fromEntries(atalhosPeriodo('2026-03-01').map((x) => [x.id, [x.inicio, x.fim]]))
  expect(m['mes-anterior']).toEqual(['2026-02-01', '2026-02-28'])
})

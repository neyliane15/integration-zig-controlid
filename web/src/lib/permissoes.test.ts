import { expect, it } from 'vitest'
import type { Papel } from '@/tipos/banco'
import { ehMaster, podeAdministrar, podeOperar, podeVerComissoes } from './permissoes'
import { rotuloPapel } from './rotulos'

it('matriz de papéis (§3)', () => {
  const linha = (p: Papel) => [ehMaster(p), podeAdministrar(p), podeOperar(p), podeVerComissoes(p)]
  expect(linha('master')).toEqual([true, true, true, true])
  expect(linha('administrador')).toEqual([false, true, true, true])
  expect(linha('gerente')).toEqual([false, false, true, true])
  expect(linha('leitura')).toEqual([false, false, false, false])
  expect(rotuloPapel.leitura).toBe('Somente leitura')
})

// Testes do leitor de AFD. Rodam com `node --test n8n/controlid/lib/` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { lerAfd, lerLinhaAfd, resumoAfd, deduplicarPorIdExterno, emLotes, separarLotes } from './afd.mjs'

const { describe, it } = process.env.VITEST ? await import('vitest') : await import('node:test')
const DADOS = join(dirname(fileURLToPath(import.meta.url)), '__dados__')
const ler = (nome) => readFileSync(join(DADOS, nome), 'latin1')

describe('AFD Portaria 671', () => {
  const r = lerAfd(ler('afd-671.txt'))

  it('lê marcações tipo 3 e tipo 7, com CRLF', () => {
    assert.deepEqual(r.marcacoes.map((m) => m.nsr), [2, 3, 4, 6, 8, 9])
    assert.equal(r.layouts['671'], 6)
    assert.equal(r.layouts['1510'], 0)
  })

  it('converte data-hora com fuso e CPF de 12 posições', () => {
    assert.deepEqual(r.marcacoes[0], { id_externo: '2', nsr: 2, instante: '2026-10-05T17:02:00-03:00', cpf: '52998224725' })
    assert.equal(r.marcacoes[4].instante, '2026-10-06T09:15:00-02:00') // tipo 7, outro fuso
    assert.equal(r.marcacoes[4].cpf, '39053344705')
    assert.equal(r.marcacoes[5].instante, '2026-10-06T10:00:00+00:00')
  })

  it('ignora cabeçalho, empresa, ajuste de relógio, empregado e trailer; conta NSR repetido', () => {
    assert.deepEqual(r.outros_registros, { 1: 1, 2: 1, 4: 1, 5: 1, 9: 1 })
    assert.equal(r.duplicadas, 1)
    assert.equal(r.ignoradas.length, 0)
  })

  it('aceita só o tipo 3 quando pedido', () => {
    const s = lerAfd(ler('afd-671.txt'), { tipos: ['3'] })
    assert.equal(s.marcacoes.some((m) => m.nsr === 8), false)
    assert.equal(s.outros_registros['7'], 1)
  })
})

describe('AFD Portaria 1510 (legado)', () => {
  const r = lerAfd(ler('afd-1510.txt'))
  it('lê marcações com instante_local e PIS', () => {
    assert.deepEqual(r.marcacoes, [
      { id_externo: '2', nsr: 2, instante_local: '2026-10-05T17:02:00', pis: '12345678901' },
      { id_externo: '3', nsr: 3, instante_local: '2026-10-05T21:30:00', pis: '12345678901' },
      { id_externo: '6', nsr: 6, instante_local: '2026-10-06T01:00:00', pis: '10987654321' },
    ])
    assert.equal(r.layouts['1510'], 3)
    assert.equal(r.ignoradas.length, 0)
    assert.deepEqual(r.outros_registros, { 1: 1, 2: 1, 4: 1, 5: 1, 9: 1 })
  })
})

describe('AFD corrompido', () => {
  const r = lerAfd(readFileSync(join(DADOS, 'afd-corrompido.txt'), 'utf8'))
  it('aproveita as linhas boas (inclusive com BOM e espaços no fim)', () => {
    assert.deepEqual(r.marcacoes.map((m) => m.nsr), [10, 19])
  })
  it('lista as linhas ruins com o motivo', () => {
    const motivos = r.ignoradas.map((x) => `${x.linha}:${x.motivo}`)
    assert.deepEqual(motivos, [
      '3:linha curta demais',
      '4:NSR não numérico',
      '5:data-hora inválida',
      '6:CPF inválido',
      '7:registro 671 incompleto',
      '8:CPF inválido',
      '9:data-hora inválida',
      '10:data-hora inválida',
      '11:registro 1510 incompleto',
      '12:NSR zerado',
    ])
    assert.equal(r.outros_registros.q, 1) // "lixo qualquer"
  })
  it('resumo para detalhes limita a 20 exemplos', () => {
    const muitas = Array.from({ length: 30 }, (_, i) => `${String(i + 1).padStart(9, '0')}3xx`).join('\n')
    const s = resumoAfd(lerAfd(muitas))
    assert.equal(s.ignoradas, 30)
    assert.equal(s.exemplos_ignoradas.length, 20)
  })
})

describe('linha a linha', () => {
  it('vazia e texto nulo', () => {
    assert.equal(lerLinhaAfd(''), null)
    assert.equal(lerLinhaAfd('   \r'), null)
    assert.deepEqual(lerAfd(null).marcacoes, [])
    assert.deepEqual(lerAfd('').marcacoes, [])
  })
  it('aceita \\r sozinho como quebra de linha', () => {
    const t = '0000000013051020261702012345678901\r0000000023051020261800012345678901'
    assert.equal(lerAfd(t).marcacoes.length, 2)
  })
  it('PIS com 12 dígitos significativos é inválido', () => {
    assert.deepEqual(lerLinhaAfd('0000000013051020261702112345678901'), { ignorada: 'PIS inválido' })
  })
  it('fuso inválido', () => {
    assert.deepEqual(lerLinhaAfd('0000000013' + '2026-10-05T17:02:00-9900' + '052998224725ABCD'), { ignorada: 'fuso inválido' })
  })
})

describe('lotes', () => {
  it('deduplica por id_externo e divide em lotes', () => {
    const lista = [{ id_externo: '1' }, { id_externo: '2' }, { id_externo: '1' }, null, { id_externo: '3' }]
    assert.deepEqual(deduplicarPorIdExterno(lista).map((x) => x.id_externo), ['1', '2', '3'])
    assert.deepEqual(emLotes([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]])
    assert.deepEqual(emLotes([], 2), [])
  })
  it('separarLotes: REP lê o AFD; acesso usa as batidas; erro/vazio → sem_lote', () => {
    const rep = separarLotes({ ok: true, afd: ler('afd-671.txt') }, 4)
    assert.equal(rep.length, 2)
    assert.equal(rep[0].lote.length, 4)
    assert.equal(rep[0].total_lotes, 2)
    assert.equal(rep[0].afd_resumo.marcacoes, 6)
    const acesso = separarLotes({ ok: true, batidas: [{ id_externo: 'a' }, { id_externo: 'a' }] })
    assert.deepEqual(acesso, [{ lote: [{ id_externo: 'a' }], indice: 0, total_lotes: 1, afd_resumo: null }])
    assert.deepEqual(separarLotes({ ok: false, erro: 'x' }), [{ sem_lote: true, afd_resumo: null }])
    assert.equal(separarLotes({ ok: true, afd: '' })[0].sem_lote, true)
  })
})

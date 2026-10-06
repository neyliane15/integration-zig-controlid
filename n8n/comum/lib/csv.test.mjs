// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import { campoCsv, gerarCsv, centavosCsv, minutosCsv, dataCsv, numeroCsv, slug, nomeArquivoCsv, csvComissao } from './csv.mjs'

const { test } = process.env.VITEST ? await import('vitest') : await import('node:test')

// Vetor do contrato §9 (como sairia de ingestao_fechamento_exportar).
const FECHAMENTO = {
  fechamento: {
    id: 'f1', empresa_nome: 'Bar Bossa Nova', titulo: 'Comissão 01/09 a 30/09/2026', data_inicio: '2026-09-01', data_fim: '2026-09-30',
    status: 'fechado', servico_zig_centavos: 1000000, servico_ajuste_centavos: -5000, servico_bruto_centavos: 995000,
    percentual_retencao: 20, retencao_centavos: 199000, base_distribuivel_centavos: 796000, valor_ponto_centavos: 20947.368421,
  },
  itens: [
    { funcionario_nome: 'Ana Souza', cargo: 'Garçom', incluido: true, pontos: 10, dias_trabalhados: 30, pontos_efetivos: 10, valor_centavos: 209474 },
    { funcionario_nome: 'Bruno Lima', cargo: 'Garçom', incluido: true, pontos: 10, dias_trabalhados: 30, pontos_efetivos: 10, valor_centavos: 209474 },
    { funcionario_nome: 'Carla Dias', cargo: 'Cumim', incluido: true, pontos: 6, dias_trabalhados: 30, pontos_efetivos: 6, valor_centavos: 125684 },
    { funcionario_nome: 'Davi Rocha', cargo: 'Bartender', incluido: true, pontos: 8, dias_trabalhados: 30, pontos_efetivos: 8, valor_centavos: 167579 },
    { funcionario_nome: 'Eva Martins', cargo: 'Cozinha', incluido: true, pontos: 4, dias_trabalhados: 15, pontos_efetivos: 4, valor_centavos: 83789 },
    { funcionario_nome: 'Fulano "Zé"; Silva', cargo: null, incluido: false, pontos: 2.5, dias_trabalhados: 0, pontos_efetivos: 0, valor_centavos: 0 },
  ],
}

test('campos: aspas, booleanos e nulos', () => {
  assert.equal(campoCsv(null), '')
  assert.equal(campoCsv(undefined), '')
  assert.equal(campoCsv(true), 'Sim')
  assert.equal(campoCsv(false), 'Não')
  assert.equal(campoCsv('a;b'), '"a;b"')
  assert.equal(campoCsv('diz "oi"'), '"diz ""oi"""')
  assert.equal(campoCsv('linha\nnova'), '"linha\nnova"')
  assert.equal(campoCsv(12), '12')
})

test('gerarCsv: BOM, \\r\\n em toda linha e linha em branco após o preâmbulo', () => {
  const s = gerarCsv(['A', 'B'], [[1, 'x']], [['P', 'q']])
  assert.equal(s, '﻿P;q\r\n\r\nA;B\r\n1;x\r\n')
  assert.equal(gerarCsv(['A'], []), '﻿A\r\n')
})

test('formatadores', () => {
  assert.equal(centavosCsv(209474), '2094,74')
  assert.equal(centavosCsv(-5000), '-50,00')
  assert.equal(centavosCsv(5), '0,05')
  assert.equal(centavosCsv(null), '')
  assert.equal(minutosCsv(-206), '-03:26')
  assert.equal(minutosCsv(450), '07:30')
  assert.equal(dataCsv('2026-10-06'), '06/10/2026')
  assert.equal(numeroCsv(10, 2), '10')
  assert.equal(numeroCsv(2.5, 2), '2,5')
  assert.equal(numeroCsv('7.333333', 6), '7,333333')
  assert.equal(slug('Bar Bossa Nova — São João!'), 'bar-bossa-nova-sao-joao')
  assert.equal(slug('***'), 'empresa')
  assert.equal(nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-09-01', '2026-09-30'), 'comissao_bar-bossa-nova_2026-09-01_2026-09-30.csv')
  assert.equal(nomeArquivoCsv('ponto', 'X', '2026-09-01', '2026-09-01'), 'ponto_x_2026-09-01.csv')
})

test('csvComissao: vetor do §9', () => {
  const r = csvComissao(FECHAMENTO)
  assert.equal(r.nome, 'comissao_bar-bossa-nova_2026-09-01_2026-09-30.csv')
  assert.equal(r.linhas, 6)
  const linhas = r.conteudo.split('\r\n')
  assert.ok(r.conteudo.startsWith('﻿Período;01/09/2026 a 30/09/2026\r\n'))
  assert.ok(r.conteudo.endsWith('\r\n'))
  assert.deepEqual(linhas.slice(1, 10), [
    'Serviço Zig (R$);10000,00', 'Ajuste (R$);-50,00', 'Serviço bruto (R$);9950,00', 'Retenção (%);20', 'Retenção (R$);1990,00',
    'Base distribuível (R$);7960,00', 'Valor do ponto (R$);209,47', 'Status;Fechado', '',
  ])
  assert.equal(linhas[10], 'Funcionário;Cargo;Incluído;Pontos;Dias trabalhados;Pontos efetivos;Valor (R$)')
  assert.equal(linhas[11], 'Ana Souza;Garçom;Sim;10;30;10;2094,74')
  assert.equal(linhas[14], 'Davi Rocha;Bartender;Sim;8;30;8;1675,79')
  assert.equal(linhas[16], '"Fulano ""Zé""; Silva";;Não;2,5;0;0;0,00')
  assert.equal(linhas[17], 'Total;;;38;;38;7960,00')
  // Σ valores = base
  const soma = FECHAMENTO.itens.reduce((s, i) => s + i.valor_centavos, 0)
  assert.equal(soma, 796000)
})

test('csvComissao: sem participantes → valor do ponto vazio', () => {
  const r = csvComissao({ fechamento: { ...FECHAMENTO.fechamento, valor_ponto_centavos: null, status: 'rascunho' }, itens: [] })
  assert.match(r.conteudo, /Valor do ponto \(R\$\);\r\n/)
  assert.match(r.conteudo, /Status;Rascunho\r\n/)
  assert.throws(() => csvComissao({ fechamento: {} }), /período/)
})

// Só no vitest (que entende TypeScript): a saída tem de ser idêntica à de web/src/lib/csv.ts.
if (process.env.VITEST) {
  test('idêntico ao web/src/lib/csv.ts', async () => {
    const web = await import('../../../web/src/lib/csv.ts')
    const pre = [['Período', '01/09/2026 a 30/09/2026'], ['Obs', 'tem; ponto e "aspas"']]
    const linhas = [['Ana', true, null, 10, 'a\nb'], ['Bruno', false, undefined, 2.5, '']]
    assert.equal(gerarCsv(['A', 'B', 'C', 'D', 'E'], linhas, pre), web.gerarCsv(['A', 'B', 'C', 'D', 'E'], linhas, pre))
    for (const c of [0, 5, 209474, -5000, -1, 123456789]) assert.equal(centavosCsv(c), web.centavosCsv(c))
    for (const m of [0, 450, -206, 1439, -1]) assert.equal(minutosCsv(m), web.minutosCsv(m))
    assert.equal(dataCsv('2026-10-06'), web.dataCsv('2026-10-06'))
    for (const s of ['Bar Bossa Nova', 'Ação & Cia', '']) assert.equal(slug(s), web.slug(s))
    assert.equal(nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-09-01', '2026-09-30'), web.nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-09-01', '2026-09-30'))
  })
}

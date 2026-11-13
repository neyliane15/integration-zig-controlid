// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest).
import assert from 'node:assert/strict'
import { campoCsv, gerarCsv, centavosCsv, minutosCsv, dataCsv, numeroCsv, slug, nomeArquivoCsv, csvComissao } from './csv.mjs'

const { test } = process.env.VITEST ? await import('vitest') : await import('node:test')

// Vetor V1 do adendo E.3.3 (modo diário; como sairia de ingestao_fechamento_exportar).
const FECHAMENTO = {
  fechamento: {
    id: 'f1', empresa_nome: 'Bar Bossa Nova', titulo: 'Comissão 01/09 a 03/09/2026', data_inicio: '2026-09-01', data_fim: '2026-09-03',
    status: 'fechado', modo_rateio: 'diario', servico_zig_centavos: 180001, servico_ajuste_centavos: 0, servico_bruto_centavos: 180001,
    percentual_retencao: 20, retencao_centavos: 36000, base_distribuivel_centavos: 144001, valor_ponto_centavos: 1788.832298,
    dias_sem_presenca: 1, dias_sem_participantes: 0,
  },
  itens: [
    { funcionario_nome: 'Ana Souza', tipo: 'funcionario', cargo: 'Garçom', incluido: true, pontos: 10, dias_presentes: 2, dias_trabalhados: 2, pontos_efetivos: 30, valor_centavos: 52060 },
    { funcionario_nome: 'Bruno Lima', tipo: 'funcionario', cargo: 'Garçom', incluido: true, pontos: 10, dias_presentes: 1, dias_trabalhados: 1, pontos_efetivos: 20, valor_centavos: 35037 },
    { funcionario_nome: 'Carla Dias', tipo: 'funcionario', cargo: 'Cumim', incluido: true, pontos: '6.00', dias_presentes: 2, dias_trabalhados: 2, pontos_efetivos: 18, valor_centavos: 31235 },
    { funcionario_nome: 'Marcos Freitas', tipo: 'extra', cargo: 'Garçom', incluido: true, pontos: '6.25', dias_presentes: 2, dias_trabalhados: 2, pontos_efetivos: 12.5, valor_centavos: 25669 },
    { funcionario_nome: 'Fulano "Zé"; Silva', tipo: 'funcionario', cargo: null, incluido: false, pontos: 2.5, dias_presentes: 0, dias_trabalhados: 0, pontos_efetivos: 0, valor_centavos: 0 },
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

test('csvComissao: vetor V1 (modo diário, adendo E.4)', () => {
  const r = csvComissao(FECHAMENTO)
  assert.equal(r.nome, 'comissao_bar-bossa-nova_2026-09-01_2026-09-03.csv')
  assert.equal(r.linhas, 5)
  const linhas = r.conteudo.split('\r\n')
  assert.ok(r.conteudo.startsWith('\ufeffPeríodo;01/09/2026 a 03/09/2026\r\n'))
  assert.ok(r.conteudo.endsWith('\r\n'))
  assert.deepEqual(linhas.slice(1, 12), [
    'Modo de rateio;Diário', 'Serviço Zig (R$);1800,01', 'Ajuste (R$);0,00', 'Serviço bruto (R$);1800,01', 'Retenção (%);20',
    'Retenção (R$);360,00', 'Base distribuível (R$);1440,01', 'Valor do ponto (R$);17,89', 'Status;Fechado', 'Dias sem presença registrada;1', '',
  ])
  assert.equal(linhas[12], 'Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)')
  assert.equal(linhas[13], 'Ana Souza;Funcionário;Garçom;Sim;10;2;520,60')
  assert.equal(linhas[15], 'Carla Dias;Funcionário;Cumim;Sim;6;2;312,35')
  assert.equal(linhas[16], 'Marcos Freitas;Extra;Garçom;Sim;6,25;2;256,69')
  assert.equal(linhas[17], '"Fulano ""Zé""; Silva";Funcionário;;Não;2,5;0;0,00')
  assert.equal(linhas[18], 'Total;;;;32,25;7;1440,01')
  assert.equal(FECHAMENTO.itens.reduce((s, i) => s + i.valor_centavos, 0), 144001)
})

test('csvComissao: modo período (sem a linha de dias sem presença); dias_trabalhados como reserva', () => {
  const itens = FECHAMENTO.itens.map(({ dias_presentes, ...i }) => i)
  const linhas = csvComissao({ fechamento: { ...FECHAMENTO.fechamento, modo_rateio: 'periodo' }, itens }).conteudo.split('\r\n')
  assert.equal(linhas[1], 'Modo de rateio;Por período')
  assert.equal(linhas[10], '')
  assert.equal(linhas[11], 'Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)')
  assert.equal(linhas[12], 'Ana Souza;Funcionário;Garçom;Sim;10;2;520,60')
  // sem modo (fechamento antigo) = por período
  const antigo = csvComissao({ fechamento: { ...FECHAMENTO.fechamento, modo_rateio: undefined }, itens: [] }).conteudo.split('\r\n')
  assert.equal(antigo[1], 'Modo de rateio;Por período')
  assert.equal(antigo[12], 'Total;;;;0;0;0,00')
})

test('csvComissao: sem participantes → valor do ponto vazio', () => {
  const r = csvComissao({ fechamento: { ...FECHAMENTO.fechamento, valor_ponto_centavos: null, status: 'rascunho' }, itens: [] })
  assert.match(r.conteudo, /Valor do ponto \(R\$\);\r\n/)
  assert.match(r.conteudo, /Status;Rascunho\r\n/)
  assert.throws(() => csvComissao({ fechamento: {} }), /período/)
})

test('(revisão 2) injeção de fórmula neutralizada; números nossos intactos', () => {
  assert.equal(gerarCsv(['x'], [['=HYPERLINK("u")'], ['@A'], ['-1'], ['-03:26'], ['+5+5']]),
    '\ufeffx\r\n"\'=HYPERLINK(""u"")"\r\n\'@A\r\n-1\r\n-03:26\r\n\'+5+5\r\n')
})

// Só no vitest (que entende TypeScript): a saída tem de ser idêntica à de web/src/lib/csv.ts.
if (process.env.VITEST) {
  test('idêntico ao web/src/lib/csv.ts', async () => {
    const web = await import('../../../web/src/lib/csv.ts')
    const pre = [['Período', '01/09/2026 a 30/09/2026'], ['Obs', 'tem; ponto e "aspas"']]
    const linhas = [['Ana', true, null, 10, 'a\nb'], ['Bruno', false, undefined, 2.5, ''], ['=1+1', '@x', '-50,00', '-2+3', '\tx']]
    assert.equal(gerarCsv(['A', 'B', 'C', 'D', 'E'], linhas, pre), web.gerarCsv(['A', 'B', 'C', 'D', 'E'], linhas, pre))
    for (const c of [0, 5, 209474, -5000, -1, 123456789]) assert.equal(centavosCsv(c), web.centavosCsv(c))
    for (const m of [0, 450, -206, 1439, -1]) assert.equal(minutosCsv(m), web.minutosCsv(m))
    assert.equal(dataCsv('2026-10-06'), web.dataCsv('2026-10-06'))
    for (const s of ['Bar Bossa Nova', 'Ação & Cia', '']) assert.equal(slug(s), web.slug(s))
    assert.equal(nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-09-01', '2026-09-30'), web.nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-09-01', '2026-09-30'))
  })
}

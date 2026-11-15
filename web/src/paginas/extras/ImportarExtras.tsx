/**
 * Importar extras (adendo extras v3, §E.7.6): arquivo CSV (ou Excel salvo como CSV) de "outro sistema do Macaw" → colunas reconhecidas
 * (ou escolhidas) → prévia → `extras_importar` → resultado com erros por linha e quantos ficaram com pontuação pendente.
 */
import { useId, useMemo, useRef, useState } from 'react'
import { AlertTriangle, CheckCircle2, Download, FileUp } from 'lucide-react'
import { Botao, Campo, Modal, Selecao, Selo } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useImportarExtras } from '@/consultas/extras'
import { baixarCsv } from '@/lib/csv'
import { formatarCentavos, formatarData } from '@/lib/formato'
import { pontosTexto } from '@/lib/extras'
import {
  CAMPOS_EXTRA,
  LIMITE_EXTRAS_IMPORTACAO,
  MODELO_CSV_EXTRAS,
  converterExtras,
  lerCsv,
  linhasDoItem,
  paraImportacao,
  reconhecerColunasExtras,
  type CampoExtra,
  type MapeamentoExtras,
} from '@/lib/extrasCsv'
import type { ResultadoImportacaoExtras } from '@/tipos/banco'

export function baixarModeloExtras() {
  baixarCsv('modelo-extras.csv', MODELO_CSV_EXTRAS)
}

export function ImportarExtras({ aberto, aoFechar, aoVerPendentes }: { aberto: boolean; aoFechar(): void; aoVerPendentes(): void }) {
  const avisos = useAvisos()
  const importar = useImportarExtras()
  const entrada = useRef<HTMLInputElement>(null)
  const id = useId()
  const [arquivo, setArquivo] = useState<string | null>(null)
  const [matriz, setMatriz] = useState<string[][] | null>(null)
  const [mapa, setMapa] = useState<MapeamentoExtras | null>(null)
  const [resultado, setResultado] = useState<(ResultadoImportacaoExtras & { linhasErro: { linhas: number[]; mensagem: string }[] }) | null>(null)

  const cabecalho = matriz?.[0] ?? []
  const dados = useMemo(() => (matriz ? matriz.slice(1) : []), [matriz])
  const conversao = useMemo(() => (mapa ? converterExtras(dados, mapa) : null), [dados, mapa])
  const faltando = mapa ? CAMPOS_EXTRA.filter((c) => c.obrigatorio && mapa[c.id] == null) : []
  const totalDias = conversao?.extras.reduce((t, x) => t + x.dias_trabalhados.length, 0) ?? 0

  const limpar = () => {
    setArquivo(null)
    setMatriz(null)
    setMapa(null)
    setResultado(null)
  }
  const fechar = () => {
    limpar()
    aoFechar()
  }

  const escolher = async (f: File | undefined) => {
    if (!f) return
    if (f.size > 5 * 1024 * 1024) return avisos.erro('Arquivo grande demais (máximo 5 MB)')
    if (/\.xlsx?$/i.test(f.name)) return avisos.erro('Salve a planilha como CSV (Arquivo → Salvar como → CSV) e escolha de novo')
    let texto = await f.text()
    if (texto.includes('�')) texto = new TextDecoder('windows-1252').decode(await f.arrayBuffer())
    const m = lerCsv(texto, undefined, true)
    while (m.length && m[m.length - 1]!.every((c) => c.trim() === '')) m.pop()
    if (m.length < 2) return avisos.erro('O arquivo não tem extras (precisa de cabeçalho + ao menos uma linha)')
    setArquivo(f.name)
    setMatriz(m)
    setMapa(reconhecerColunasExtras(m[0] ?? []))
    setResultado(null)
  }

  const mudarCampo = (campo: CampoExtra, coluna: string) =>
    setMapa((atual) => {
      if (!atual) return atual
      const novo = { ...atual }
      const indice = coluna === '' ? null : Number(coluna)
      if (indice != null) for (const c of CAMPOS_EXTRA) if (novo[c.id] === indice) novo[c.id] = null
      novo[campo] = indice
      return novo
    })

  const enviar = async () => {
    if (!conversao || conversao.extras.length === 0) return
    if (conversao.extras.length > LIMITE_EXTRAS_IMPORTACAO) return avisos.erro(`Máximo de ${LIMITE_EXTRAS_IMPORTACAO} linhas por importação`)
    try {
      const r = await importar.mutateAsync(paraImportacao(conversao.extras))
      setResultado({ ...r, linhasErro: r.erros.map((e) => ({ linhas: linhasDoItem(conversao.extras, e.linha), mensagem: e.mensagem })) })
      avisos.sucesso(`Extras importados: ${r.criados} novo(s), ${r.atualizados} atualizado(s)`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const textoLinhas = (ls: number[]) => (ls.length ? `Linha ${ls.join(', ')}` : 'Linha ?')

  return (
    <Modal
      aberto={aberto}
      aoFechar={fechar}
      largura="g"
      titulo="Importar extras"
      rodape={
        resultado ? (
          <>
            {resultado.pendentes_pontuacao > 0 && (
              <Botao
                variante="secundario"
                onClick={() => {
                  fechar()
                  aoVerPendentes()
                }}
              >
                Preencher pontuação
              </Botao>
            )}
            <Botao onClick={fechar}>Concluir</Botao>
          </>
        ) : (
          <>
            <Botao variante="secundario" onClick={fechar}>
              Cancelar
            </Botao>
            <Botao
              onClick={enviar}
              carregando={importar.isPending}
              disabled={!conversao || conversao.extras.length === 0 || faltando.length > 0}
              icone={<FileUp aria-hidden />}
            >
              {conversao && conversao.extras.length > 0 ? `Importar ${conversao.extras.length} extra(s)` : 'Importar'}
            </Botao>
          </>
        )
      }
    >
      {resultado ? (
        <div className="flex flex-col gap-4" data-teste="resultado-importacao">
          <p className="flex items-center gap-2 font-display text-lg text-creme">
            <CheckCircle2 aria-hidden className="size-5 text-sucesso" /> Importação concluída
          </p>
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              ['Novos', resultado.criados],
              ['Atualizados', resultado.atualizados],
              ['Dias lançados', resultado.dias_lancados],
              ['Pontuação pendente', resultado.pendentes_pontuacao],
            ].map(([r, n]) => (
              <div key={r} className="rounded-entrada border border-borda bg-cartao-2/50 p-3">
                <dt className="text-xs text-lavanda">{r}</dt>
                <dd className="numero text-xl font-semibold text-creme">{n}</dd>
              </div>
            ))}
          </dl>
          {resultado.pendentes_pontuacao > 0 && (
            <p className="flex items-start gap-2 rounded-entrada border border-alerta/40 bg-alerta/10 p-3 text-sm text-alerta">
              <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
              {resultado.pendentes_pontuacao} extra(s) ficaram com pontuação pendente: não entram na comissão e o fechamento fica bloqueado até preencher.
            </p>
          )}
          {resultado.dias_lancados > 0 && (
            <p className="text-xs text-lavanda">Tem rascunho de comissão no período? Abra e clique em Recalcular para incluir os dias importados.</p>
          )}
          {resultado.linhasErro.length > 0 && (
            <section>
              <h3 className="mb-1 flex items-center gap-2 text-sm font-semibold text-perigo">
                <Selo tom="perigo">{resultado.linhasErro.length} com erro</Selo> não importados
              </h3>
              <ul className="flex max-h-40 flex-col gap-1 overflow-auto text-xs text-perigo">
                {resultado.linhasErro.map((e, k) => (
                  <li key={k}>
                    {textoLinhas(e.linhas)}: {e.mensagem}
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
      ) : !matriz ? (
        <div className="flex flex-col gap-4">
          <p className="text-sm leading-relaxed text-lavanda">
            Exporte a lista de freelas do outro sistema (ou monte uma planilha) e salve como CSV. Uma linha por extra — ou uma linha por dia trabalhado da
            mesma pessoa. Extras já cadastrados são reconhecidos pelo documento (ou pelo nome) e atualizados, não duplicados.{' '}
            <strong className="text-creme">Pontos em branco = pontuação pendente</strong>: o extra não entra na comissão até você preencher.
          </p>
          <input
            ref={entrada}
            id={id}
            type="file"
            accept=".csv,text/csv,text/plain"
            className="sr-only"
            onChange={(e) => {
              void escolher(e.target.files?.[0])
              e.target.value = ''
            }}
          />
          <label htmlFor={id} className="sr-only">
            Arquivo CSV de extras
          </label>
          <div className="flex flex-wrap gap-2">
            <Botao icone={<FileUp aria-hidden />} onClick={() => entrada.current?.click()}>
              Escolher arquivo CSV
            </Botao>
            <Botao variante="secundario" icone={<Download aria-hidden />} onClick={baixarModeloExtras}>
              Baixar modelo
            </Botao>
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="min-w-0 truncate text-sm text-creme">
              <span className="font-semibold">{arquivo}</span> · <span className="numero">{dados.length}</span> linha(s)
            </p>
            <Botao variante="fantasma" tamanho="p" onClick={limpar}>
              Trocar arquivo
            </Botao>
          </div>

          <section aria-labelledby={`${id}-mapa`}>
            <h3 id={`${id}-mapa`} className="mb-1 font-display text-lg text-creme">
              Colunas
            </h3>
            <p className="mb-3 text-xs text-lavanda">Reconhecemos o que deu pelo nome. Ajuste o que estiver errado ou vazio.</p>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {CAMPOS_EXTRA.map((c) => (
                <Campo key={c.id} rotulo={c.rotulo} htmlFor={`${id}-${c.id}`} obrigatorio={c.obrigatorio} ajuda={c.ajuda}>
                  <Selecao id={`${id}-${c.id}`} value={mapa?.[c.id] ?? ''} onChange={(e) => mudarCampo(c.id, e.target.value)}>
                    <option value="">— não usar —</option>
                    {cabecalho.map((h, i) => (
                      <option key={i} value={i}>
                        {h.trim() || `Coluna ${i + 1}`}
                      </option>
                    ))}
                  </Selecao>
                </Campo>
              ))}
            </div>
            {faltando.length > 0 && (
              <p role="alert" className="mt-3 flex items-center gap-1.5 text-sm text-perigo">
                <AlertTriangle aria-hidden className="size-4" /> Escolha a coluna de: {faltando.map((f) => f.rotulo).join(', ')}.
              </p>
            )}
          </section>

          {conversao && faltando.length === 0 && (
            <section aria-labelledby={`${id}-previa`} data-teste="previa-extras">
              <h3 id={`${id}-previa`} className="mb-2 flex flex-wrap items-center gap-2 font-display text-lg text-creme">
                Prévia
                <Selo tom="sucesso">{conversao.extras.length} extra(s)</Selo>
                {totalDias > 0 && <Selo tom="info">{totalDias} dia(s)</Selo>}
                {conversao.semPontos > 0 && <Selo tom="alerta">{conversao.semPontos} sem pontuação</Selo>}
                {conversao.erros.length > 0 && <Selo tom="perigo">{conversao.erros.length} com problema</Selo>}
              </h3>
              <div className="max-h-72 overflow-auto rounded-entrada border border-borda">
                <table className="w-full min-w-[600px] border-collapse text-sm">
                  <thead className="sticky top-0 bg-cartao-2">
                    <tr className="text-left text-[11px] tracking-[0.12em] text-lavanda uppercase">
                      <th scope="col" className="px-3 py-2">Linha</th>
                      <th scope="col" className="px-3 py-2">Extra</th>
                      <th scope="col" className="px-3 py-2 text-right">Diária</th>
                      <th scope="col" className="px-3 py-2 text-right">Pontos</th>
                      <th scope="col" className="px-3 py-2">Dias</th>
                    </tr>
                  </thead>
                  <tbody>
                    {conversao.extras.slice(0, 200).map((x) => (
                      <tr key={x.linhas.join('-')} className="border-t border-borda align-top">
                        <td className="numero px-3 py-2 text-lavanda">{x.linhas.join(', ')}</td>
                        <td className="px-3 py-2">
                          <p className="font-semibold text-creme">{x.nome}</p>
                          <p className="text-xs text-lavanda">{[x.funcao, x.documento, x.telefone].filter(Boolean).join(' · ') || '—'}</p>
                        </td>
                        <td className="numero px-3 py-2 text-right">{x.valor_diaria_centavos == null ? '—' : formatarCentavos(x.valor_diaria_centavos)}</td>
                        <td className="px-3 py-2 text-right">
                          {x.pontos == null ? <Selo tom="alerta">Pendente</Selo> : <span className="numero">{pontosTexto(x.pontos)}</span>}
                        </td>
                        <td className="numero px-3 py-2 text-xs text-lavanda">
                          {x.dias_trabalhados.length ? x.dias_trabalhados.map((d) => formatarData(d.data).slice(0, 5)).join(', ') : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {conversao.extras.length > 200 && <p className="mt-2 text-xs text-lavanda">Mostrando os 200 primeiros.</p>}
              {conversao.semPontos > 0 && (
                <p className="mt-2 text-xs text-alerta">
                  Sem pontos: extras novos ficam com pontuação pendente (extras já cadastrados mantêm a pontuação que têm).
                </p>
              )}
              {conversao.erros.length > 0 && (
                <ul className="mt-3 flex max-h-32 flex-col gap-1 overflow-auto text-xs text-perigo">
                  {conversao.erros.slice(0, 50).map((e) => (
                    <li key={e.linha}>
                      Linha <span className="numero">{e.linha}</span>: {e.mensagem} (ignorada)
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}
        </div>
      )}
    </Modal>
  )
}

/**
 * Importação de reservas por CSV: escolher arquivo → reconhecer colunas (ou o usuário escolhe) → prévia → enviar.
 */
import { useId, useMemo, useRef, useState } from 'react'
import { AlertTriangle, Download, FileUp } from 'lucide-react'
import { Botao, Campo, Modal, Selecao, Selo } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { baixarCsv } from '@/lib/csv'
import { formatarData } from '@/lib/formato'
import { rotuloStatusReserva } from '@/lib/rotulos'
import {
  CAMPOS_RESERVA,
  MODELO_CSV_RESERVAS,
  converterReservas,
  lerCsv,
  reconhecerColunas,
  type CampoReserva,
  type Mapeamento,
  type ReservaLida,
} from '@/lib/reservasCsv'

const LIMITE_LINHAS = 2000

export function baixarModeloReservas() {
  baixarCsv('modelo-reservas.csv', MODELO_CSV_RESERVAS)
}

export function ImportarCsv({
  aberto,
  aoFechar,
  aoEnviar,
  enviando,
}: {
  aberto: boolean
  aoFechar(): void
  aoEnviar(reservas: ReservaLida[], arquivo: string): Promise<void>
  enviando: boolean
}) {
  const avisos = useAvisos()
  const entrada = useRef<HTMLInputElement>(null)
  const id = useId()
  const [arquivo, setArquivo] = useState<string | null>(null)
  const [matriz, setMatriz] = useState<string[][] | null>(null)
  const [mapa, setMapa] = useState<Mapeamento | null>(null)

  const cabecalho = matriz?.[0] ?? []
  const dados = useMemo(() => (matriz ? matriz.slice(1) : []), [matriz])
  const resultado = useMemo(() => (mapa ? converterReservas(dados, mapa) : null), [dados, mapa])
  const faltando = mapa ? CAMPOS_RESERVA.filter((c) => c.obrigatorio && mapa[c.id] == null) : []

  const limpar = () => {
    setArquivo(null)
    setMatriz(null)
    setMapa(null)
  }

  const fechar = () => {
    limpar()
    aoFechar()
  }

  const escolher = async (f: File | undefined) => {
    if (!f) return
    if (f.size > 5 * 1024 * 1024) return avisos.erro('Arquivo grande demais (máximo 5 MB)')
    let texto = await f.text()
    // planilhas antigas salvam em Latin-1: se apareceu o caractere de substituição, relê como windows-1252
    if (texto.includes('�')) texto = new TextDecoder('windows-1252').decode(await f.arrayBuffer())
    const m = lerCsv(texto)
    if (m.length < 2) return avisos.erro('O arquivo não tem linhas de reserva (precisa de cabeçalho + ao menos uma linha)')
    if (m.length - 1 > LIMITE_LINHAS) return avisos.erro(`No máximo ${LIMITE_LINHAS} reservas por arquivo`)
    setArquivo(f.name)
    setMatriz(m)
    setMapa(reconhecerColunas(m[0] ?? []))
  }

  const mudarCampo = (campo: CampoReserva, coluna: string) => {
    setMapa((atual) => {
      if (!atual) return atual
      const novo = { ...atual }
      const indice = coluna === '' ? null : Number(coluna)
      // uma coluna só pode alimentar um campo
      if (indice != null) for (const c of CAMPOS_RESERVA) if (novo[c.id] === indice) novo[c.id] = null
      novo[campo] = indice
      return novo
    })
  }

  const enviar = async () => {
    if (!resultado || resultado.reservas.length === 0) return
    await aoEnviar(resultado.reservas, arquivo ?? 'arquivo.csv')
    limpar()
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={fechar}
      largura="g"
      titulo="Importar reservas (CSV)"
      rodape={
        <>
          <Botao variante="secundario" onClick={fechar}>
            Cancelar
          </Botao>
          <Botao
            onClick={enviar}
            carregando={enviando}
            disabled={!resultado || resultado.reservas.length === 0 || faltando.length > 0}
            icone={<FileUp aria-hidden />}
          >
            {resultado && resultado.reservas.length > 0 ? `Importar ${resultado.reservas.length} reserva(s)` : 'Importar'}
          </Botao>
        </>
      }
    >
      {!matriz ? (
        <div className="flex flex-col gap-4">
          <p className="text-sm leading-relaxed text-lavanda">
            Exporte as reservas no painel da Tagme (waitlist.tagme.com.br → Reservas → exportar) ou use uma planilha própria salva como CSV.
            Separador <span className="numero">;</span> ou <span className="numero">,</span>, datas <span className="numero">dd/mm/aaaa</span> ou{' '}
            <span className="numero">aaaa-mm-dd</span>. Reservas com o mesmo código são atualizadas, não duplicadas.
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
          <div className="flex flex-wrap gap-2">
            <Botao icone={<FileUp aria-hidden />} onClick={() => entrada.current?.click()}>
              Escolher arquivo CSV
            </Botao>
            <Botao variante="secundario" icone={<Download aria-hidden />} onClick={baixarModeloReservas}>
              Baixar modelo
            </Botao>
          </div>
          <label htmlFor={id} className="sr-only">
            Arquivo CSV de reservas
          </label>
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
              {CAMPOS_RESERVA.map((c) => (
                <Campo key={c.id} rotulo={c.rotulo} htmlFor={`${id}-${c.id}`} obrigatorio={c.obrigatorio}>
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

          {resultado && faltando.length === 0 && (
            <section aria-labelledby={`${id}-previa`}>
              <h3 id={`${id}-previa`} className="mb-2 flex flex-wrap items-center gap-2 font-display text-lg text-creme">
                Prévia
                <Selo tom="sucesso">{resultado.reservas.length} ok</Selo>
                {resultado.erros.length > 0 && <Selo tom="perigo">{resultado.erros.length} com problema</Selo>}
              </h3>
              <div className="max-h-72 overflow-auto rounded-entrada border border-borda">
                <table className="w-full min-w-[560px] border-collapse text-sm">
                  <thead className="sticky top-0 bg-cartao-2">
                    <tr className="text-left text-[11px] tracking-[0.12em] text-lavanda uppercase">
                      <th scope="col" className="px-3 py-2">Linha</th>
                      <th scope="col" className="px-3 py-2">Cliente</th>
                      <th scope="col" className="px-3 py-2">Data</th>
                      <th scope="col" className="px-3 py-2">Hora</th>
                      <th scope="col" className="px-3 py-2 text-right">Pessoas</th>
                      <th scope="col" className="px-3 py-2">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {resultado.reservas.slice(0, 200).map((r) => (
                      <tr key={r.linha} className="border-t border-borda">
                        <td className="numero px-3 py-2 text-lavanda">{r.linha}</td>
                        <td className="px-3 py-2 text-creme">{r.nome}</td>
                        <td className="numero px-3 py-2">{formatarData(r.data)}</td>
                        <td className="numero px-3 py-2">{r.hora ?? '—'}</td>
                        <td className="numero px-3 py-2 text-right">{r.pessoas}</td>
                        <td className="px-3 py-2">{rotuloStatusReserva[r.status]}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {resultado.reservas.length > 200 && <p className="mt-2 text-xs text-lavanda">Mostrando as 200 primeiras.</p>}
              {resultado.erros.length > 0 && (
                <ul className="mt-3 flex max-h-32 flex-col gap-1 overflow-auto text-xs text-perigo">
                  {resultado.erros.slice(0, 50).map((e) => (
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

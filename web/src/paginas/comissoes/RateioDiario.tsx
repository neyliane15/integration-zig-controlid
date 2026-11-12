/**
 * Detalhe do rateio diário (adendo E.3): uma linha por dia com serviço, retenção, base e participantes; expande para ver quanto
 * coube a cada um. Dias "sem presença registrada" foram rateados entre todos os funcionários incluídos (fallback).
 */
import { useState } from 'react'
import clsx from 'clsx'
import { AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react'
import { Botao, Cartao, FOCO, Selo } from '@/componentes/ui'
import type { DiaCalculado, ItemCalculado } from '@/lib/comissao'
import { diaSemanaCurto, formatarCentavos, formatarData } from '@/lib/formato'

const fmtPontos = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })

export function RateioDiario({ dias, itens, previa }: { dias: DiaCalculado[]; itens: ItemCalculado[]; previa: boolean }) {
  const [abertos, setAbertos] = useState<Set<string>>(() => new Set())
  const [mostrarVazios, setMostrarVazios] = useState(false)
  const comMovimento = dias.filter((d) => d.servicoBrutoCentavos > 0 || d.participantes > 0 || d.semParticipantes)
  const lista = mostrarVazios ? dias : comMovimento
  const alternar = (data: string) =>
    setAbertos((s) => {
      const n = new Set(s)
      if (n.has(data)) n.delete(data)
      else n.add(data)
      return n
    })
  const todosAbertos = lista.length > 0 && lista.every((d) => abertos.has(d.data))

  return (
    <Cartao
      sobrancelha={`${comMovimento.length} de ${dias.length} dia(s) com movimento${previa ? ' · prévia' : ''}`}
      titulo="Rateio por dia"
      semPreenchimento
      acoes={
        <>
          {dias.length !== comMovimento.length && (
            <Botao variante="fantasma" tamanho="p" onClick={() => setMostrarVazios((v) => !v)}>
              {mostrarVazios ? 'Ocultar dias sem serviço' : 'Mostrar todos os dias'}
            </Botao>
          )}
          {lista.length > 0 && (
            <Botao variante="fantasma" tamanho="p" onClick={() => setAbertos(todosAbertos ? new Set() : new Set(lista.map((d) => d.data)))}>
              {todosAbertos ? 'Recolher todos' : 'Expandir todos'}
            </Botao>
          )}
        </>
      }
    >
      {lista.length === 0 ? (
        <p className="px-5 pb-5 text-sm text-lavanda sm:px-6 sm:pb-6">Nenhum dia com serviço no período.</p>
      ) : (
        <ul className="border-t border-borda">
          {/* cabeçalho (desktop) */}
          <li aria-hidden className="hidden grid-cols-[minmax(0,1.3fr)_repeat(4,minmax(0,1fr))_minmax(0,1.2fr)] gap-3 bg-cartao-2/70 px-6 py-2.5 text-[11px] font-bold tracking-[0.14em] text-lavanda uppercase md:grid">
            <span>Dia</span>
            <span className="text-right">Serviço</span>
            <span className="text-right">Retenção</span>
            <span className="text-right">Base</span>
            <span className="text-right">Pontos</span>
            <span className="text-right">Participantes</span>
          </li>
          {lista.map((d) => {
            const aberto = abertos.has(d.data)
            const idPainel = `rateio-${d.data}`
            return (
              <li key={d.data} className={clsx('border-t border-borda first:border-t-0', d.semParticipantes && 'bg-perigo/5', d.semPresenca && 'bg-alerta/5')}>
                <button
                  type="button"
                  aria-expanded={aberto}
                  aria-controls={idPainel}
                  onClick={() => alternar(d.data)}
                  className={clsx('grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 px-5 py-3 text-left text-sm hover:bg-cartao-2/50 sm:px-6 md:grid-cols-[minmax(0,1.3fr)_repeat(4,minmax(0,1fr))_minmax(0,1.2fr)]', FOCO)}
                >
                  <span className="col-span-2 flex min-w-0 items-center gap-2 md:col-span-1">
                    {aberto ? <ChevronDown aria-hidden className="size-4 shrink-0 text-lavanda" /> : <ChevronRight aria-hidden className="size-4 shrink-0 text-lavanda" />}
                    <span className="numero font-semibold text-creme">{formatarData(d.data)}</span>
                    <span className="text-xs text-lavanda">{diaSemanaCurto(d.data)}</span>
                    {d.semPresenca && <Selo tom="alerta">Sem presença</Selo>}
                    {d.semParticipantes && <Selo tom="perigo">Sem participantes</Selo>}
                  </span>
                  <span className="numero hidden text-right md:block">{formatarCentavos(d.servicoBrutoCentavos)}</span>
                  <span className="numero hidden text-right text-perigo md:block">{d.retencaoCentavos ? `−${formatarCentavos(d.retencaoCentavos)}` : '—'}</span>
                  <span className="numero text-right font-semibold text-ouro-claro md:order-none">{formatarCentavos(d.baseCentavos)}</span>
                  <span className="numero hidden text-right md:block">{d.somaPontos ? fmtPontos(d.somaPontos) : '—'}</span>
                  <span className="col-span-3 text-xs text-lavanda md:col-span-1 md:text-right md:text-sm">
                    <span className="md:hidden">
                      Serviço {formatarCentavos(d.servicoBrutoCentavos)} · retenção {formatarCentavos(d.retencaoCentavos)} ·{' '}
                    </span>
                    {d.participantes} participante(s)
                  </span>
                </button>
                {aberto && (
                  <div id={idPainel} className="px-5 pb-4 sm:px-6">
                    {d.semPresenca && (
                      <p className="mb-3 flex items-start gap-2 rounded-entrada border border-alerta/40 bg-alerta/10 p-3 text-sm text-alerta">
                        <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
                        Dia sem presença registrada — rateado entre todos os funcionários incluídos.
                      </p>
                    )}
                    {d.semParticipantes && (
                      <p className="mb-3 flex items-start gap-2 rounded-entrada border border-perigo/40 bg-perigo/10 p-3 text-sm text-perigo">
                        <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
                        Serviço sem ninguém para ratear (nenhum funcionário incluído com pontos). Inclua alguém ou ajuste o serviço para fechar.
                      </p>
                    )}
                    {d.ajusteCentavos !== 0 && (
                      <p className="mb-2 text-xs text-lavanda">
                        Serviço da Zig {formatarCentavos(d.servicoZigCentavos)} · parte do ajuste {formatarCentavos(d.ajusteCentavos, { sinal: true })}
                      </p>
                    )}
                    {d.rateio.length > 0 && (
                      <table className="w-full text-sm">
                        <caption className="sr-only">Rateio de {formatarData(d.data)}</caption>
                        <thead>
                          <tr className="text-[11px] font-bold tracking-[0.12em] text-lavanda uppercase">
                            <th scope="col" className="py-1.5 text-left">Participante</th>
                            <th scope="col" className="py-1.5 text-right">Pontos</th>
                            <th scope="col" className="py-1.5 text-right">Valor</th>
                          </tr>
                        </thead>
                        <tbody>
                          {d.rateio.map((r) => {
                            const it = itens[r.indice]
                            return (
                              <tr key={r.indice} className="border-t border-borda/60">
                                <td className="py-2 pr-2">
                                  <span className="flex min-w-0 flex-wrap items-center gap-1.5 text-creme">
                                    <span className="truncate">{it?.nome}</span>
                                    {it?.tipo === 'extra' && <Selo tom="info">Extra</Selo>}
                                  </span>
                                </td>
                                <td className="numero py-2 text-right">{fmtPontos(r.pontos)}</td>
                                <td className="numero py-2 text-right font-semibold whitespace-nowrap text-ouro-claro">
                                  {formatarCentavos(r.valorCentavos)}
                                  {r.centavoExtra && (
                                    <span className="ml-1 text-[10px] text-lavanda" title="Recebeu +1 centavo no arredondamento pelo maior resto">
                                      +1¢
                                    </span>
                                  )}
                                </td>
                              </tr>
                            )
                          })}
                        </tbody>
                      </table>
                    )}
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </Cartao>
  )
}

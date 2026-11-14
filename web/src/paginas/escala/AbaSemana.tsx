/**
 * Abas "Geral" (visão por setor) e "<setor>" (dia → quem trabalha/folga, grade da semana, caminho do rodízio).
 * Fonte: `escala_semana` (regra sem ajustes; semana do dia de trabalho atual).
 */
import { useState } from 'react'
import clsx from 'clsx'
import { ArrowRight, RotateCcw } from 'lucide-react'
import { Cartao, FOCO, Pilulas } from '@/componentes/ui'
import type { EscalaSemana, EscalaSetorSemana } from '@/tipos/banco'
import { DIAS_SEMANA, horaParaChegada, indiceSegunda } from '@/lib/escala'
import { formatarDataCurta, somarDias } from '@/lib/formato'

export const CHIP = 'inline-flex items-center rounded-lg px-2.5 py-1 text-[13px] font-semibold'
export const CHIP_TRABALHA = 'bg-acento-suave text-ouro-claro'
export const CHIP_FOLGA = 'bg-folga-suave text-perigo'

function Dica({ children }: { children: React.ReactNode }) {
  return <p className="mt-3 text-xs leading-relaxed text-lavanda">{children}</p>
}

function rotuloSemana(s: EscalaSemana): string {
  const fim = somarDias(s.semana_inicio, 6)
  return `${formatarDataCurta(s.semana_inicio)} a ${formatarDataCurta(fim)}`
}

// ------------------------------------------------------------------ Geral
export function AbaGeral({ semana, aoAbrirSetor }: { semana: EscalaSemana; aoAbrirSetor(id: string): void }) {
  const [visao, setVisao] = useState<'semana' | 'base'>('semana')
  const total = semana.setores.reduce((a, s) => a + s.total, 0)
  const contagem = (s: EscalaSetorSemana) => (visao === 'semana' ? s.na_escala_semana : s.na_escala_base)
  const todos = visao === 'semana' ? semana.na_escala_semana : semana.na_escala_base
  return (
    <Cartao
      sobrancelha={`Visão geral · ${total} na escala`}
      titulo="Quantos trabalham em cada dia"
      acoes={
        <Pilulas<'semana' | 'base'>
          rotulo="Semana mostrada"
          opcoes={[
            { id: 'semana', rotulo: `Esta semana (${rotuloSemana(semana)})` },
            { id: 'base', rotulo: 'Semana base' },
          ]}
          valor={visao}
          aoMudar={setVisao}
        />
      }
    >
      <div className="-mx-1 overflow-x-auto px-1">
        <table className="w-full min-w-[520px] border-separate border-spacing-y-1 text-sm">
          <thead>
            <tr className="text-xs font-semibold text-lavanda">
              <th className="px-2 py-1 text-left font-semibold">Setor</th>
              <th className="px-1 py-1 font-semibold">Total</th>
              {DIAS_SEMANA.map((d) => (
                <th key={d} className="px-1 py-1 font-semibold">
                  {d}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {semana.setores.map((s) => (
              <tr key={s.id} className="bg-noite">
                <td className="rounded-l-[10px] p-0">
                  <button
                    type="button"
                    onClick={() => aoAbrirSetor(s.id)}
                    className={clsx('w-full px-2.5 py-2 text-left font-semibold text-creme hover:text-ouro-claro', FOCO)}
                  >
                    {s.nome}
                  </button>
                </td>
                <td className="text-center">
                  <span className={clsx(CHIP, CHIP_TRABALHA, 'numero min-w-9 justify-center px-1 text-xs')}>{s.total}</span>
                </td>
                {contagem(s).map((n, i) => (
                  <td key={i} className={clsx('numero py-2 text-center text-creme', i === 6 && 'rounded-r-[10px]')}>
                    {n}
                  </td>
                ))}
              </tr>
            ))}
            <tr className="font-bold text-ouro-claro">
              <td className="border-t border-borda px-2.5 pt-2.5">Todos</td>
              <td className="numero border-t border-borda pt-2.5 text-center">{total}</td>
              {todos.map((n, i) => (
                <td key={i} className="numero border-t border-borda pt-2.5 text-center">
                  {n}
                </td>
              ))}
            </tr>
          </tbody>
        </table>
      </div>
      <Dica>
        Os números por dia indicam quem está na escala (sem contar férias e ajustes do dia). Toque em um setor para ver os detalhes; use a
        aba Escala do mês para ajustar dias e copiar para o Excel.
      </Dica>
    </Cartao>
  )
}

// ------------------------------------------------------------------ Setor
export function AbaSetor({ semana, setorId, hoje }: { semana: EscalaSemana; setorId: string; hoje: string }) {
  const setor = semana.setores.find((s) => s.id === setorId)
  const hojeIdx = indiceSegunda(new Date(`${hoje}T12:00:00Z`).getUTCDay())
  const [dia, setDia] = useState(hojeIdx)
  const [destaque, setDestaque] = useState<string | null>(null)
  const [visao, setVisao] = useState<'semana' | 'base'>('semana')
  if (!setor) return null
  const folgas = (m: EscalaSetorSemana['membros'][number]) => (visao === 'semana' ? m.folgas_semana : m.folgas_base)
  const trabalham = setor.membros.filter((m) => !m.folgas_semana.includes(dia))
  const folgam = setor.membros.filter((m) => m.folgas_semana.includes(dia))
  const fixas = setor.membros.filter((m) => m.caminho == null)
  const dataDia = somarDias(semana.semana_inicio, dia)

  return (
    <div className="grid min-w-0 gap-5">
      <Cartao sobrancelha="Escolha um dia" titulo={`${setor.nome} · ${DIAS_SEMANA[dia]} ${formatarDataCurta(dataDia)}`}>
        <div role="radiogroup" aria-label="Dia da semana" className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
          {DIAS_SEMANA.map((d, i) => (
            <button
              key={d}
              type="button"
              role="radio"
              aria-checked={i === dia}
              onClick={() => setDia(i)}
              className={clsx(
                'min-h-9 shrink-0 rounded-pilula border px-3.5 text-sm font-semibold transition-colors',
                FOCO,
                i === dia ? 'border-ouro bg-ouro text-tinta-ouro' : 'border-borda bg-cartao text-creme hover:border-borda-forte',
              )}
            >
              {d}
            </button>
          ))}
        </div>
        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <div>
            <h3 className="mb-2 text-xs font-semibold tracking-[0.06em] text-lavanda uppercase">Trabalham ({trabalham.length})</h3>
            <div className="flex flex-wrap gap-1.5" data-teste="trabalham">
              {trabalham.length
                ? trabalham.map((m) => (
                    <span key={m.funcionario_id} className={clsx(CHIP, CHIP_TRABALHA)}>
                      {m.nome}
                      {m.chegada_padrao ? ` · ${horaParaChegada(m.chegada_padrao)}` : ''}
                    </span>
                  ))
                : '—'}
            </div>
          </div>
          <div>
            <h3 className="mb-2 text-xs font-semibold tracking-[0.06em] text-lavanda uppercase">Folgam ({folgam.length})</h3>
            <div className="flex flex-wrap gap-1.5" data-teste="folgam">
              {folgam.length
                ? folgam.map((m) => (
                    <span key={m.funcionario_id} className={clsx(CHIP, CHIP_FOLGA)}>
                      {m.nome}
                    </span>
                  ))
                : <span className="text-sm text-lavanda">Ninguém</span>}
            </div>
          </div>
        </div>
        <Dica>Pela regra do rodízio na semana de {rotuloSemana(semana)}; ajustes e férias do dia aparecem na Escala do mês.</Dica>
      </Cartao>

      <Cartao
        sobrancelha="Grade semanal"
        titulo={visao === 'semana' ? `Semana de ${rotuloSemana(semana)}` : 'Semana base'}
        acoes={
          <Pilulas<'semana' | 'base'>
            rotulo="Semana da grade"
            opcoes={[
              { id: 'semana', rotulo: 'Esta semana' },
              { id: 'base', rotulo: 'Semana base' },
            ]}
            valor={visao}
            aoMudar={setVisao}
          />
        }
      >
        <div className="-mx-1 overflow-x-auto px-1">
          <table className="w-full min-w-[480px] border-separate border-spacing-y-1 text-sm">
            <thead>
              <tr>
                <th />
                {DIAS_SEMANA.map((d, i) => (
                  <th key={d} className="p-0">
                    <button
                      type="button"
                      onClick={() => setDia(i)}
                      className={clsx(
                        'w-full px-1 py-1 text-xs font-semibold',
                        FOCO,
                        i === dia ? 'text-ouro-claro underline underline-offset-4' : 'text-lavanda hover:text-creme',
                      )}
                    >
                      {d}
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {setor.membros.map((m) => {
                const hl = destaque === m.funcionario_id
                return (
                  <tr key={m.funcionario_id} className={hl ? 'bg-acento-suave' : 'bg-noite'}>
                    <td className="rounded-l-[10px] p-0">
                      <button
                        type="button"
                        aria-pressed={hl}
                        onClick={() => setDestaque(hl ? null : m.funcionario_id)}
                        className={clsx('w-full truncate px-2.5 py-2 text-left font-semibold text-creme', FOCO)}
                      >
                        {m.nome}
                      </button>
                    </td>
                    {DIAS_SEMANA.map((d, j) => {
                      const f = folgas(m).includes(j)
                      return (
                        <td key={d} className={clsx('px-1 py-2 text-center', j === 6 && 'rounded-r-[10px]')}>
                          <span
                            className={clsx(
                              'inline-block w-full max-w-11 rounded-lg py-1 text-[11px] font-semibold',
                              f ? CHIP_FOLGA : CHIP_TRABALHA,
                            )}
                          >
                            {f ? 'Folga' : '●'}
                          </span>
                        </td>
                      )
                    })}
                  </tr>
                )
              })}
              <tr className="font-bold text-ouro-claro">
                <td className="border-t border-borda px-2.5 pt-2.5">Na escala</td>
                {(visao === 'semana' ? setor.na_escala_semana : setor.na_escala_base).map((n, i) => (
                  <td key={i} className="numero border-t border-borda pt-2.5 text-center">
                    {n}
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
        <Dica>Toque no nome para destacar a pessoa e em um dia para ver a equipe daquele dia.</Dica>
      </Cartao>

      <Cartao sobrancelha="Rodízio" titulo="Caminho a seguir">
        {setor.caminhos.length === 0 && <p className="text-sm text-lavanda">Nenhum caminho de rodízio neste setor.</p>}
        <div className="flex flex-col gap-2">
          {setor.caminhos.map((c) => (
            <div key={c.caminho} className="flex flex-wrap items-center gap-1.5" aria-label={`Caminho ${c.caminho}`}>
              <span className="mr-1 text-xs font-semibold text-lavanda">{c.caminho}.</span>
              {c.nomes.map((n, i) => (
                <span key={c.funcionarios[i] ?? i} className="inline-flex items-center gap-1.5">
                  {i > 0 && <ArrowRight aria-hidden className="size-3.5 text-lavanda" />}
                  <span className={clsx(CHIP, CHIP_TRABALHA)}>{n}</span>
                </span>
              ))}
              <RotateCcw aria-label="volta ao início" className="ml-1 size-3.5 text-lavanda" />
            </div>
          ))}
        </div>
        {fixas.length > 0 && (
          <p className="mt-3 text-sm text-lavanda">
            Folga fixa: {fixas.map((m) => m.nome).join(', ')}
          </p>
        )}
        <Dica>A cada semana, cada pessoa assume a folga da próxima posição do caminho. Ao chegar ao fim, volta ao início.</Dica>
      </Cartao>
    </div>
  )
}

/**
 * Dias do participante no fechamento: para cada dia, o que o sistema achou (ponto, escala, ausência…) e a marcação à mão
 * — Automático, Trabalhou ou Folga. Serve para quem não bate ponto nem está na escala (ex.: ADM, manutenção).
 */
import type { ComissaoDetalheItem } from '@/tipos/banco'
import { Botao, Modal, Pilulas } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useDefinirPresencaDia } from '@/consultas/comissoes'
import { rotuloMotivoPresenca } from '@/lib/rotulos'
import { diaSemanaCurto, formatarData } from '@/lib/formato'

type Marcacao = 'auto' | 'trabalhou' | 'folga'

type Entrada = ComissaoDetalheItem['entrada'][number]

const marcacaoDe = (e: Entrada): Marcacao => (e.origem === 'manual' ? 'trabalhou' : e.motivo === 'folga_manual' ? 'folga' : 'auto')

const ORIGEM: Record<string, string> = {
  ponto: 'Trabalhou (bateu o ponto)',
  escala: 'Trabalhou (escala)',
  regra: 'Ausência que recebe neste fechamento',
  manual: 'Trabalhou (marcado à mão)',
}

function situacao(e: Entrada): string {
  if (e.presente) return ORIGEM[e.origem ?? ''] ?? 'Trabalhou'
  if (e.fallback) return 'Sem ponto e sem escala: entra nos dias com serviço'
  return e.motivo ? rotuloMotivoPresenca[e.motivo] : 'Não trabalhou'
}

export function DiasDoParticipante({
  item,
  fechamentoId,
  rascunho,
  aoFechar,
}: {
  item: ComissaoDetalheItem | null
  fechamentoId: string
  rascunho: boolean
  aoFechar(): void
}) {
  const avisos = useAvisos()
  const definir = useDefinirPresencaDia()

  const marcar = async (e: Entrada, m: Marcacao) => {
    if (!item?.funcionario_id) return
    try {
      await definir.mutateAsync({
        id: fechamentoId,
        funcionarioId: item.funcionario_id,
        data: e.data,
        presente: m === 'auto' ? null : m === 'trabalhou',
      })
    } catch (err) {
      avisos.erro(err)
    }
  }

  return (
    <Modal
      aberto={!!item}
      aoFechar={aoFechar}
      largura="m"
      titulo={item ? `Dias de ${item.nome}` : ''}
      rodape={
        <Botao variante="secundario" onClick={aoFechar}>
          Fechar
        </Botao>
      }
    >
      <p className="mb-3 text-sm text-lavanda">
        Marque <strong className="text-creme">Folga</strong> nos dias em que a pessoa não trabalhou, ou{' '}
        <strong className="text-creme">Trabalhou</strong> para incluir um dia. <strong className="text-creme">Automático</strong> usa o
        ponto, a escala e as ausências. Vale só para este fechamento.
      </p>
      <ul className="divide-y divide-borda" data-teste="dias-participante">
        {(item?.entrada ?? []).map((e) => (
          <li key={e.data} className="grid gap-2 py-2.5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:gap-4">
            <div className="min-w-0">
              <p className="numero font-semibold text-creme">
                {formatarData(e.data)} <span className="text-xs font-normal text-lavanda">{diaSemanaCurto(e.data)}</span>
              </p>
              <p className="text-xs text-lavanda">{situacao(e)}</p>
            </div>
            <Pilulas<Marcacao>
              rotulo={`Dia ${formatarData(e.data)}`}
              opcoes={[
                { id: 'auto', rotulo: 'Automático' },
                { id: 'trabalhou', rotulo: 'Trabalhou' },
                { id: 'folga', rotulo: 'Folga' },
              ]}
              valor={marcacaoDe(e)}
              desabilitado={!rascunho || definir.isPending || e.motivo === 'fora_vinculo'}
              aoMudar={(m) => marcar(e, m)}
            />
          </li>
        ))}
      </ul>
    </Modal>
  )
}

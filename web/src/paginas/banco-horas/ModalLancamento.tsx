/**
 * Lançamento manual no banco de horas (ajuste, compensação, pagamento, saldo inicial). Dono: frontend-2.
 */
import { useId, useState } from 'react'
import type { TipoLancamento } from '@/tipos/banco'
import { AreaTexto, Botao, Campo, Entrada, EntradaData, Modal, Selecao } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { useLancarBancoHoras } from '@/consultas/bancoHoras'
import { formatarMinutos } from '@/lib/formato'
import { rotuloTipoLancamento } from '@/lib/rotulos'
import { lerDuracao } from '@/lib/ponto'

const AJUDA: Record<TipoLancamento, string> = {
  ajuste: 'Correção manual do saldo (crédito ou débito).',
  compensacao: 'Folga compensada: normalmente debita horas.',
  pagamento: 'Horas pagas em folha: debita do saldo.',
  saldo_inicial: 'Saldo no INÍCIO do dia escolhido (substitui tudo o que veio antes). Só administrador.',
}

const SINAL_PADRAO: Record<TipoLancamento, 1 | -1> = { ajuste: 1, compensacao: -1, pagamento: -1, saldo_inicial: 1 }

export function ModalLancamento({
  aberto,
  aoFechar,
  funcionarioId: fixo,
  dataPadrao,
  permitirSaldoInicial,
}: {
  aberto: boolean
  aoFechar(): void
  funcionarioId?: string | null
  dataPadrao: string
  permitirSaldoInicial: boolean
}) {
  const avisos = useAvisos()
  const lancar = useLancarBancoHoras()
  const [funcionarioId, setFuncionarioId] = useState<string | null>(fixo ?? null)
  const [tipo, setTipo] = useState<TipoLancamento>('ajuste')
  const [sinal, setSinal] = useState<1 | -1>(1)
  const [duracao, setDuracao] = useState('')
  const [data, setData] = useState<string | null>(dataPadrao)
  const [motivo, setMotivo] = useState('')
  const id = useId()

  const lido = lerDuracao(duracao)
  const minutos = lido == null ? null : Math.abs(lido) * (duracao.trim().startsWith('-') ? -1 : sinal)
  const tipos: TipoLancamento[] = permitirSaldoInicial ? ['ajuste', 'compensacao', 'pagamento', 'saldo_inicial'] : ['ajuste', 'compensacao', 'pagamento']

  const salvar = async () => {
    if (!funcionarioId) return avisos.erro('Escolha o funcionário')
    if (!data) return avisos.erro('Informe a data')
    if (minutos == null || (minutos === 0 && tipo !== 'saldo_inicial')) return avisos.erro('Informe as horas (ex.: 2h30)')
    if (!motivo.trim()) return avisos.erro('Informe o motivo')
    try {
      await lancar.mutateAsync({ funcionarioId, data, tipo, minutos, motivo: motivo.trim() })
      avisos.sucesso('Lançamento registrado')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo="Lançamento no banco de horas"
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={lancar.isPending} onClick={salvar}>
            Lançar
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {!fixo && (
          <div className="sm:col-span-2">
            <Campo rotulo="Funcionário" htmlFor={`${id}-f`} obrigatorio>
              <SeletorFuncionario id={`${id}-f`} valor={funcionarioId} aoMudar={setFuncionarioId} somenteAtivos />
            </Campo>
          </div>
        )}
        <Campo rotulo="Tipo" htmlFor={`${id}-t`} ajuda={AJUDA[tipo]}>
          <Selecao
            id={`${id}-t`}
            value={tipo}
            onChange={(e) => {
              const t = e.target.value as TipoLancamento
              setTipo(t)
              setSinal(SINAL_PADRAO[t])
            }}
          >
            {tipos.map((t) => (
              <option key={t} value={t}>
                {rotuloTipoLancamento[t]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <Campo rotulo="Data" htmlFor={`${id}-d`} obrigatorio>
          <EntradaData id={`${id}-d`} valor={data} aoMudar={setData} />
        </Campo>
        <Campo rotulo="Crédito ou débito" htmlFor={`${id}-s`}>
          <Selecao id={`${id}-s`} value={sinal} onChange={(e) => setSinal(Number(e.target.value) as 1 | -1)}>
            <option value={1}>Crédito (+)</option>
            <option value={-1}>Débito (−)</option>
          </Selecao>
        </Campo>
        <Campo
          rotulo="Horas"
          htmlFor={`${id}-h`}
          obrigatorio
          erro={duracao && lido == null ? 'Use 2h30, 02:30 ou minutos (150)' : null}
          ajuda={minutos != null ? `Vai lançar ${formatarMinutos(minutos, { sinal: true })}` : 'Ex.: 2h30, 1h, 45min, 02:30'}
        >
          <Entrada id={`${id}-h`} className="numero" value={duracao} onChange={(e) => setDuracao(e.target.value)} autoComplete="off" placeholder="2h30" />
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Motivo" htmlFor={`${id}-m`} obrigatorio>
            <AreaTexto id={`${id}-m`} value={motivo} onChange={(e) => setMotivo(e.target.value)} className="min-h-16" />
          </Campo>
        </div>
      </div>
    </Modal>
  )
}

/**
 * Modais de ação do ponto (incluir/ajustar batida, justificar alarme, abonar). Dono: frontend-2.
 * Toda ação manual exige motivo (auditada em ponto_ajustes).
 */
import { useId, useState } from 'react'
import type { BatidaEspelho, TipoAbono } from '@/tipos/banco'
import { AreaTexto, Botao, Campo, EntradaData, EntradaHora, Modal, Selecao, Selo } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useAbonar, useDesconsiderarBatida, useEditarBatida, useIncluirBatida, useJustificarAlarmes, useRestaurarBatida } from '@/consultas/ponto'
import { formatarData, formatarDataHora, formatarHora } from '@/lib/formato'
import { rotuloOrigemBatida, rotuloTipoAbono } from '@/lib/rotulos'
import { diaDeTrabalho, instanteDoHorario } from '@/lib/ponto'

const MOTIVOS_RAPIDOS = ['Esqueceu de bater', 'Equipamento sem energia/rede', 'Batida em duplicidade', 'Trabalho externo', 'Correção de horário']

function MotivoCampo({ valor, aoMudar, id, rotulo = 'Motivo' }: { valor: string; aoMudar(v: string): void; id: string; rotulo?: string }) {
  return (
    <Campo rotulo={rotulo} htmlFor={id} obrigatorio ajuda="Fica registrado na auditoria do ponto.">
      <AreaTexto id={id} value={valor} onChange={(e) => aoMudar(e.target.value)} className="min-h-20" />
      <div className="mt-1 flex flex-wrap gap-1.5">
        {MOTIVOS_RAPIDOS.map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => aoMudar(m)}
            className="rounded-pilula border border-borda px-2.5 py-1 text-xs text-lavanda hover:border-ouro/60 hover:text-creme focus-visible:outline-2 focus-visible:outline-ouro"
          >
            {m}
          </button>
        ))}
      </div>
    </Campo>
  )
}

/** Incluir batida manual num dia de trabalho (hora antes da virada cai no dia civil seguinte). */
export function ModalIncluirBatida({
  aberto,
  aoFechar,
  funcionarioId,
  funcionarioNome,
  data,
  horaSugerida,
  fuso,
  virada,
}: {
  aberto: boolean
  aoFechar(): void
  funcionarioId: string
  funcionarioNome: string
  data: string
  horaSugerida?: string | null
  fuso: string
  virada: string
}) {
  const avisos = useAvisos()
  const incluir = useIncluirBatida()
  const [hora, setHora] = useState<string | null>(horaSugerida ?? null)
  const [motivo, setMotivo] = useState('')
  const id = useId()
  const instante = hora ? instanteDoHorario(data, hora, fuso, virada) : null
  const futuro = instante ? instante.getTime() > Date.now() : false

  const salvar = async () => {
    if (!instante) return avisos.erro('Informe o horário')
    if (!motivo.trim()) return avisos.erro('Informe o motivo')
    try {
      await incluir.mutateAsync({ funcionarioId, instante: instante.toISOString(), motivo: motivo.trim() })
      avisos.sucesso('Batida incluída. O dia foi recalculado.')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo="Incluir batida"
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={incluir.isPending} onClick={salvar} disabled={!hora || !motivo.trim() || futuro}>
            Incluir batida
          </Botao>
        </>
      }
    >
      <p className="mb-4 text-sm text-lavanda">
        {funcionarioNome} · dia de trabalho <span className="numero text-creme">{formatarData(data)}</span>
      </p>
      <div className="flex flex-col gap-4">
        <Campo
          rotulo="Horário"
          htmlFor={`${id}-h`}
          obrigatorio
          erro={futuro ? 'Horário no futuro' : null}
          ajuda={instante ? `Será gravada em ${formatarDataHora(instante.toISOString(), fuso)}` : `Antes de ${virada} conta como madrugada do dia seguinte.`}
        >
          <EntradaHora id={`${id}-h`} valor={hora} aoMudar={setHora} />
        </Campo>
        <MotivoCampo id={`${id}-m`} valor={motivo} aoMudar={setMotivo} />
      </div>
    </Modal>
  )
}

/** Ações sobre uma batida existente: desconsiderar, restaurar ou corrigir o horário. */
export function ModalBatida({
  batida,
  aoFechar,
  funcionarioId,
  data,
  fuso,
  virada,
}: {
  batida: BatidaEspelho | null
  aoFechar(): void
  funcionarioId: string
  data: string
  fuso: string
  virada: string
}) {
  const avisos = useAvisos()
  const desconsiderar = useDesconsiderarBatida()
  const restaurar = useRestaurarBatida()
  const editar = useEditarBatida()
  const [motivo, setMotivo] = useState('')
  const [modo, setModo] = useState<'acoes' | 'corrigir'>('acoes')
  const [hora, setHora] = useState<string | null>(batida ? formatarHora(batida.instante, fuso) : null)
  const id = useId()
  if (!batida) return null
  const ocupado = desconsiderar.isPending || restaurar.isPending || editar.isPending

  const executar = async (acao: 'desconsiderar' | 'restaurar' | 'corrigir') => {
    if (!motivo.trim()) return avisos.erro('Informe o motivo')
    try {
      if (acao === 'desconsiderar') await desconsiderar.mutateAsync({ batidaId: batida.id, motivo: motivo.trim() })
      else if (acao === 'restaurar') await restaurar.mutateAsync({ batidaId: batida.id, motivo: motivo.trim() })
      else {
        if (!hora) return avisos.erro('Informe o novo horário')
        const instante = instanteDoHorario(diaDeTrabalho(batida.instante, fuso, virada) || data, hora, fuso, virada)
        if (instante.getTime() > Date.now()) return avisos.erro('Horário no futuro')
        await editar.mutateAsync({ batidaId: batida.id, funcionarioId, instante: instante.toISOString(), motivo: motivo.trim() })
      }
      avisos.sucesso(acao === 'desconsiderar' ? 'Batida desconsiderada' : acao === 'restaurar' ? 'Batida restaurada' : 'Horário corrigido')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      titulo={`Batida das ${formatarHora(batida.instante, fuso)}`}
      rodape={
        modo === 'corrigir' ? (
          <>
            <Botao variante="secundario" onClick={() => setModo('acoes')}>
              Voltar
            </Botao>
            <Botao carregando={editar.isPending} disabled={!motivo.trim() || !hora} onClick={() => executar('corrigir')}>
              Salvar correção
            </Botao>
          </>
        ) : (
          <>
            <Botao variante="secundario" onClick={aoFechar}>
              Fechar
            </Botao>
            {!batida.desconsiderada && (
              <Botao variante="secundario" onClick={() => setModo('corrigir')} disabled={ocupado}>
                Corrigir horário
              </Botao>
            )}
            {batida.desconsiderada ? (
              <Botao carregando={restaurar.isPending} disabled={!motivo.trim() || ocupado} onClick={() => executar('restaurar')}>
                Restaurar
              </Botao>
            ) : (
              <Botao variante="perigo" carregando={desconsiderar.isPending} disabled={!motivo.trim() || ocupado} onClick={() => executar('desconsiderar')}>
                Desconsiderar
              </Botao>
            )}
          </>
        )
      }
    >
      <div className="mb-4 flex flex-wrap items-center gap-2 text-sm">
        <span className="numero text-creme">{formatarDataHora(batida.instante, fuso)}</span>
        <Selo tom={batida.origem === 'manual' ? 'info' : 'neutro'}>{rotuloOrigemBatida[batida.origem]}</Selo>
        {batida.desconsiderada && <Selo tom="perigo">Desconsiderada</Selo>}
        {batida.duplicada && <Selo tom="alerta">Duplicada (ignorada no cálculo)</Selo>}
      </div>
      {batida.motivo && <p className="mb-4 text-sm text-lavanda">Motivo anterior: {batida.motivo}</p>}
      {modo === 'corrigir' && (
        <div className="mb-4">
          <Campo rotulo="Horário correto" htmlFor={`${id}-h`} ajuda="A batida original é desconsiderada e uma batida manual é incluída.">
            <EntradaHora id={`${id}-h`} valor={hora} aoMudar={setHora} />
          </Campo>
        </div>
      )}
      <MotivoCampo id={`${id}-m`} valor={motivo} aoMudar={setMotivo} />
    </Modal>
  )
}

/** Justificar um ou vários alarmes. */
export function ModalJustificar({ ids, aoFechar, titulo }: { ids: string[]; aoFechar(): void; titulo?: string }) {
  const avisos = useAvisos()
  const justificar = useJustificarAlarmes()
  const [texto, setTexto] = useState('')
  const id = useId()
  if (ids.length === 0) return null
  const salvar = async () => {
    if (!texto.trim()) return avisos.erro('Informe a justificativa')
    try {
      const r = await justificar.mutateAsync({ ids, justificativa: texto.trim() })
      if (r.erros.length) avisos.info(`${r.ok} justificado(s); ${r.erros.length} não puderam ser justificados.`)
      else avisos.sucesso(ids.length > 1 ? `${r.ok} alarmes justificados` : 'Alarme justificado')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }
  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      titulo={titulo ?? (ids.length > 1 ? `Justificar ${ids.length} alarmes` : 'Justificar alarme')}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={justificar.isPending} disabled={!texto.trim()} onClick={salvar}>
            Justificar
          </Botao>
        </>
      }
    >
      <p className="mb-3 text-sm text-lavanda">Justificar não altera o saldo. Para corrigir horas, inclua a batida que faltou ou abone o dia.</p>
      <Campo rotulo="Justificativa" htmlFor={id} obrigatorio>
        <AreaTexto id={id} value={texto} onChange={(e) => setTexto(e.target.value)} />
      </Campo>
    </Modal>
  )
}

const TIPOS_ABONO: TipoAbono[] = ['folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro']

/** Abonar um ou mais dias (do funcionário ou da empresa toda). */
export function ModalAbonar({
  aberto,
  aoFechar,
  funcionarioId,
  funcionarioNome,
  inicio: inicioPadrao,
}: {
  aberto: boolean
  aoFechar(): void
  funcionarioId: string | null
  funcionarioNome?: string
  inicio: string
}) {
  const avisos = useAvisos()
  const abonar = useAbonar()
  const [inicio, setInicio] = useState<string | null>(inicioPadrao)
  const [fim, setFim] = useState<string | null>(inicioPadrao)
  const [tipo, setTipo] = useState<TipoAbono>('atestado')
  const [motivo, setMotivo] = useState('')
  const id = useId()
  const salvar = async () => {
    if (!inicio || !fim || fim < inicio) return avisos.erro('Período inválido')
    try {
      const n = await abonar.mutateAsync({ inicio, fim, tipo, motivo: motivo.trim() || null, funcionarioId })
      avisos.sucesso(`${n} dia(s) abonado(s)`)
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }
  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo="Abonar dia(s)"
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={abonar.isPending} onClick={salvar}>
            Abonar
          </Botao>
        </>
      }
    >
      <p className="mb-4 text-sm text-lavanda">
        {funcionarioId ? funcionarioNome : 'Empresa toda (ex.: feriado)'} · dia abonado não tem horas previstas nem alarmes.
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo rotulo="De" htmlFor={`${id}-i`}>
          <EntradaData id={`${id}-i`} valor={inicio} aoMudar={(v) => { setInicio(v); if (v && (!fim || fim < v)) setFim(v) }} />
        </Campo>
        <Campo rotulo="Até" htmlFor={`${id}-f`}>
          <EntradaData id={`${id}-f`} valor={fim} min={inicio ?? undefined} aoMudar={setFim} />
        </Campo>
        <Campo rotulo="Tipo" htmlFor={`${id}-t`}>
          <Selecao id={`${id}-t`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoAbono)}>
            {TIPOS_ABONO.map((t) => (
              <option key={t} value={t}>
                {rotuloTipoAbono[t]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Motivo" htmlFor={`${id}-m`}>
            <AreaTexto id={`${id}-m`} value={motivo} onChange={(e) => setMotivo(e.target.value)} className="min-h-16" />
          </Campo>
        </div>
      </div>
    </Modal>
  )
}

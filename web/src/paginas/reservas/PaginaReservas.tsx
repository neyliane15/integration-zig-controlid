/**
 * /reservas (`?de&ate&status`) — reservas do dia/período (Tagme, manuais e importadas por CSV). Adendo R.
 * Todos veem; G A M cadastram, editam, mudam status, cancelam, excluem e importam. Leitura não vê telefone/e-mail.
 */
import { useEffect, useId, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import clsx from 'clsx'
import { CalendarCheck, Download, FileUp, Pencil, Phone, Plus, Trash2, Users, XCircle } from 'lucide-react'
import type { Reserva, StatusReserva } from '@/tipos/banco'
import {
  AreaTexto,
  Botao,
  CabecalhoPagina,
  Campo,
  Cartao,
  Entrada,
  EntradaData,
  EntradaHora,
  ErroCarga,
  FOCO,
  FiltroPeriodo,
  Indicador,
  Modal,
  Selecao,
  Selo,
  Esqueleto,
  Vazio,
  type Tom,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useCancelarReserva, useExcluirReserva, useImportarReservas, useMudarStatusReserva, useReservas, useSalvarReserva } from '@/consultas/reservas'
import { diasDoPeriodo } from '@/lib/comissao'
import { diaSemanaCurto, formatarData, somarDias } from '@/lib/formato'
import { podeOperar } from '@/lib/permissoes'
import { rotuloOrigemReserva, rotuloStatusReserva } from '@/lib/rotulos'
import { usePerfil } from '@/lib/sessao'
import type { ReservaLida } from '@/lib/reservasCsv'
import { ImportarCsv, baixarModeloReservas } from './ImportarCsv'

const RE_DATA = /^\d{4}-\d{2}-\d{2}$/
export const STATUS_RESERVA: StatusReserva[] = ['confirmada', 'pendente', 'sentada', 'concluida', 'cancelada', 'nao_compareceu']
export const TOM_STATUS_RESERVA: Record<StatusReserva, Tom> = {
  confirmada: 'sucesso',
  pendente: 'ouro',
  sentada: 'info',
  concluida: 'neutro',
  cancelada: 'perigo',
  nao_compareceu: 'alerta',
}

export function PaginaReservas() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const de = params.get('de')
  const ate = params.get('ate')
  const inicio = de && RE_DATA.test(de) ? de : hoje
  const fim = ate && RE_DATA.test(ate) && ate >= inicio ? ate : inicio
  const filtroStatus = params.get('status')
  const longo = diasDoPeriodo(inicio, fim) > 93
  const reservas = useReservas(inicio, longo ? inicio : fim)
  const importar = useImportarReservas()
  const [modal, setModal] = useState<{ reserva: Reserva | null } | null>(null)
  const [importando, setImportando] = useState(false)

  const mudarPeriodo = (i: string, f: string) => {
    const p = new URLSearchParams(params)
    p.set('de', i)
    p.set('ate', f)
    setParams(p, { replace: true })
  }
  const mudarStatus = (s: string | null) => {
    const p = new URLSearchParams(params)
    if (s) p.set('status', s)
    else p.delete('status')
    setParams(p, { replace: true })
  }

  const todas = reservas.data ?? []
  const visiveis = filtroStatus ? todas.filter((r) => r.status === filtroStatus) : todas
  const ativas = todas.filter((r) => r.status !== 'cancelada')
  const porDia = useMemo(() => {
    const m = new Map<string, Reserva[]>()
    for (const r of visiveis) m.set(r.data, [...(m.get(r.data) ?? []), r])
    return [...m.entries()]
  }, [visiveis])

  const atalhos = [
    { rotulo: 'Hoje', i: hoje, f: hoje },
    { rotulo: 'Amanhã', i: somarDias(hoje, 1), f: somarDias(hoje, 1) },
    { rotulo: 'Próximos 7 dias', i: hoje, f: somarDias(hoje, 6) },
    { rotulo: 'Ontem', i: somarDias(hoje, -1), f: somarDias(hoje, -1) },
  ]

  const enviarCsv = async (linhas: ReservaLida[]) => {
    try {
      const r = await importar.mutateAsync(linhas)
      const partes = [`${r.inseridos} nova(s)`, `${r.atualizados} atualizada(s)`]
      if (r.ignorados > 0) partes.push(`${r.ignorados} ignorada(s)`)
      if (r.erros.length > 0) {
        const detalhes = r.erros
          .slice(0, 3)
          .map((e) => `linha ${(linhas[e.indice]?.linha ?? e.indice + 2)}: ${e.motivo}`)
          .join('; ')
        avisos.erro(`Importação parcial: ${partes.join(', ')}. ${detalhes}`)
      } else avisos.sucesso(`Reservas importadas: ${partes.join(', ')}`)
      setImportando(false)
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="mx-auto w-full max-w-6xl">
      <CabecalhoPagina
        sobrancelha="Salão"
        titulo={
          <>
            Reservas <span className="titulo-italico">{inicio === fim ? (inicio === hoje ? 'de hoje' : `de ${formatarData(inicio)}`) : 'do período'}</span>
          </>
        }
        subtitulo="Da Tagme, lançadas à mão ou importadas do CSV exportado no painel da Tagme."
        acoes={
          operar && (
            <>
              <Botao variante="secundario" icone={<FileUp aria-hidden />} onClick={() => setImportando(true)}>
                Importar CSV
              </Botao>
              <Botao icone={<Plus aria-hidden />} onClick={() => setModal({ reserva: null })}>
                Nova reserva
              </Botao>
            </>
          )
        }
      />

      <Cartao className="mb-5">
        <FiltroPeriodo inicio={inicio} fim={fim} aoMudar={mudarPeriodo} atalhos={false} />
        <div className="mt-3 flex flex-wrap gap-1.5" role="group" aria-label="Atalhos de período">
          {atalhos.map((a) => {
            const ativo = a.i === inicio && a.f === fim
            return (
              <button
                key={a.rotulo}
                type="button"
                aria-pressed={ativo}
                onClick={() => mudarPeriodo(a.i, a.f)}
                className={clsx(
                  'h-8 rounded-pilula border px-3 text-xs font-semibold transition-colors',
                  ativo ? 'border-ouro/60 bg-ouro/10 text-ouro-claro' : 'border-borda text-lavanda hover:border-borda-forte hover:text-creme',
                  FOCO,
                )}
              >
                {a.rotulo}
              </button>
            )
          })}
        </div>
        {longo && (
          <p role="alert" className="mt-3 text-sm text-perigo">
            Período máximo de 93 dias — mostrando só {formatarData(inicio)}.
          </p>
        )}
      </Cartao>

      {reservas.error ? (
        <ErroCarga erro={reservas.error} aoTentar={() => reservas.refetch()} />
      ) : reservas.isLoading ? (
        <div className="flex flex-col gap-3" aria-busy="true">
          <span className="sr-only">Carregando reservas…</span>
          <Esqueleto className="h-24 rounded-cartao" />
          <Esqueleto className="h-48 rounded-cartao" />
        </div>
      ) : (
        <div className="flex flex-col gap-5">
          <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-4">
            <Indicador rotulo="Reservas" valor={ativas.length} tom="ouro" detalhe="Sem as canceladas" />
            <Indicador rotulo="Pessoas" valor={ativas.reduce((s, r) => s + r.pessoas, 0)} />
            <Indicador rotulo="Sentadas" valor={todas.filter((r) => r.status === 'sentada' || r.status === 'concluida').length} tom="info" />
            <Indicador
              rotulo="Canceladas"
              valor={todas.filter((r) => r.status === 'cancelada').length}
              tom="perigo"
              detalhe={`${todas.filter((r) => r.status === 'nao_compareceu').length} não compareceram`}
            />
          </div>

          <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por status">
            {[null, ...STATUS_RESERVA].map((s) => {
              const ativo = (filtroStatus ?? null) === s
              const n = s ? todas.filter((r) => r.status === s).length : todas.length
              return (
                <button
                  key={s ?? 'todas'}
                  type="button"
                  aria-pressed={ativo}
                  onClick={() => mudarStatus(s)}
                  className={clsx(
                    'h-8 rounded-pilula border px-3 text-xs font-semibold transition-colors',
                    ativo ? 'border-ouro/60 bg-ouro/10 text-ouro-claro' : 'border-borda text-lavanda hover:border-borda-forte hover:text-creme',
                    FOCO,
                  )}
                >
                  {s ? rotuloStatusReserva[s] : 'Todas'} <span className="numero ml-0.5 opacity-80">{n}</span>
                </button>
              )
            })}
          </div>

          {porDia.length === 0 ? (
            <Vazio
              icone={<CalendarCheck aria-hidden />}
              titulo={todas.length === 0 ? 'Nenhuma reserva no período' : 'Nenhuma reserva com este status'}
              descricao={
                operar
                  ? 'Lance as reservas à mão ou importe o CSV exportado no painel da Tagme (waitlist.tagme.com.br).'
                  : 'As reservas lançadas pela gerência aparecem aqui.'
              }
              acao={
                operar ? (
                  <div className="flex flex-wrap justify-center gap-2">
                    <Botao icone={<Plus aria-hidden />} onClick={() => setModal({ reserva: null })}>
                      Nova reserva
                    </Botao>
                    <Botao variante="secundario" icone={<Download aria-hidden />} onClick={baixarModeloReservas}>
                      Modelo de CSV
                    </Botao>
                  </div>
                ) : undefined
              }
            />
          ) : (
            porDia.map(([data, lista]) => (
              <Cartao
                key={data}
                semPreenchimento
                sobrancelha={diaSemanaCurto(data)}
                titulo={formatarData(data)}
                acoes={
                  <span className="text-sm text-lavanda">
                    <span className="numero text-creme">{lista.filter((r) => r.status !== 'cancelada').length}</span> reserva(s) ·{' '}
                    <span className="numero text-creme">{lista.filter((r) => r.status !== 'cancelada').reduce((s, r) => s + r.pessoas, 0)}</span> pessoa(s)
                  </span>
                }
              >
                <ul className="divide-y divide-borda border-t border-borda">
                  {lista.map((r) => (
                    <LinhaReserva key={r.id} r={r} operar={operar} aoEditar={() => setModal({ reserva: r })} />
                  ))}
                </ul>
              </Cartao>
            ))
          )}
        </div>
      )}

      <ModalReserva aberto={!!modal} reserva={modal?.reserva ?? null} dataPadrao={inicio} aoFechar={() => setModal(null)} />
      <ImportarCsv aberto={importando} aoFechar={() => setImportando(false)} aoEnviar={enviarCsv} enviando={importar.isPending} />
    </div>
  )
}

function LinhaReserva({ r, operar, aoEditar }: { r: Reserva; operar: boolean; aoEditar(): void }) {
  const avisos = useAvisos()
  const mudar = useMudarStatusReserva()
  const cancelar = useCancelarReserva()
  const excluir = useExcluirReserva()
  const id = useId()
  const tagme = r.origem === 'tagme'
  const apagada = r.status === 'cancelada' || r.status === 'nao_compareceu'

  const trocar = async (status: StatusReserva) => {
    try {
      await mudar.mutateAsync({ id: r.id, status })
      avisos.sucesso(`${r.nome_cliente}: ${rotuloStatusReserva[status]}`)
    } catch (e) {
      avisos.erro(e)
    }
  }
  const doCancelar = async () => {
    if (!(await avisos.confirmar({ titulo: `Cancelar a reserva de ${r.nome_cliente}?`, textoConfirmar: 'Cancelar reserva', perigo: true }))) return
    try {
      await cancelar.mutateAsync(r.id)
      avisos.sucesso('Reserva cancelada')
    } catch (e) {
      avisos.erro(e)
    }
  }
  const doExcluir = async () => {
    if (!(await avisos.confirmar({ titulo: `Excluir a reserva de ${r.nome_cliente}?`, mensagem: 'Prefira cancelar para manter o histórico.', textoConfirmar: 'Excluir', perigo: true })))
      return
    try {
      await excluir.mutateAsync(r.id)
      avisos.sucesso('Reserva excluída')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <li className="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:gap-4 sm:px-6">
      <div className="flex min-w-0 flex-1 items-start gap-4">
        <span className={clsx('numero w-14 shrink-0 pt-0.5 text-lg', apagada ? 'text-lavanda-escuro line-through' : 'text-ouro-claro')}>
          {r.horario ? r.horario.slice(0, 5) : '—'}
        </span>
        <div className="min-w-0 flex-1">
          <p className={clsx('flex flex-wrap items-center gap-2 font-semibold', apagada ? 'text-lavanda' : 'text-creme')}>
            <span className="min-w-0 break-words">{r.nome_cliente}</span>
            <span className="inline-flex items-center gap-1 text-sm font-normal text-lavanda">
              <Users aria-hidden className="size-3.5" />
              <span className="numero">{r.pessoas}</span>
              <span className="sr-only">pessoa(s)</span>
            </span>
          </p>
          <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-lavanda">
            {(r.area || r.mesa) && <span>{[r.area, r.mesa && `mesa ${r.mesa}`].filter(Boolean).join(' · ')}</span>}
            {r.telefone && (
              <a href={`tel:${r.telefone.replace(/[^\d+]/g, '')}`} className={`inline-flex items-center gap-1 hover:text-creme ${FOCO}`}>
                <Phone aria-hidden className="size-3" />
                <span className="numero">{r.telefone}</span>
              </a>
            )}
            <span>{rotuloOrigemReserva[r.origem]}</span>
          </p>
          {r.observacao && <p className="mt-1 text-sm break-words text-lavanda">{r.observacao}</p>}
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-1.5 sm:gap-2">
        {operar ? (
          <>
            <label htmlFor={`${id}-st`} className="sr-only">
              Status da reserva de {r.nome_cliente}
            </label>
            <div className="w-40">
              <Selecao id={`${id}-st`} className="h-9 text-sm" value={r.status} disabled={mudar.isPending} onChange={(e) => trocar(e.target.value as StatusReserva)}>
                {STATUS_RESERVA.map((s) => (
                  <option key={s} value={s}>
                    {rotuloStatusReserva[s]}
                  </option>
                ))}
              </Selecao>
            </div>
            {!tagme && <Botao variante="fantasma" tamanho="p" aria-label={`Editar reserva de ${r.nome_cliente}`} icone={<Pencil aria-hidden />} onClick={aoEditar} />}
            {r.status !== 'cancelada' && (
              <Botao variante="fantasma" tamanho="p" aria-label={`Cancelar reserva de ${r.nome_cliente}`} icone={<XCircle aria-hidden />} onClick={doCancelar} />
            )}
            {!tagme && <Botao variante="fantasma" tamanho="p" aria-label={`Excluir reserva de ${r.nome_cliente}`} icone={<Trash2 aria-hidden />} onClick={doExcluir} />}
          </>
        ) : (
          <Selo tom={TOM_STATUS_RESERVA[r.status]}>{rotuloStatusReserva[r.status]}</Selo>
        )}
      </div>
    </li>
  )
}

function ModalReserva({ aberto, reserva, dataPadrao, aoFechar }: { aberto: boolean; reserva: Reserva | null; dataPadrao: string; aoFechar(): void }) {
  const avisos = useAvisos()
  const salvar = useSalvarReserva()
  const id = useId()
  const [data, setData] = useState<string | null>(dataPadrao)
  const [horario, setHorario] = useState<string | null>(null)
  const [nome, setNome] = useState('')
  const [pessoas, setPessoas] = useState('2')
  const [telefone, setTelefone] = useState('')
  const [email, setEmail] = useState('')
  const [area, setArea] = useState('')
  const [mesa, setMesa] = useState('')
  const [observacao, setObservacao] = useState('')
  const [status, setStatus] = useState<StatusReserva>('confirmada')
  const [tentou, setTentou] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setData(reserva?.data ?? dataPadrao)
    setHorario(reserva?.horario?.slice(0, 5) ?? null)
    setNome(reserva?.nome_cliente ?? '')
    setPessoas(String(reserva?.pessoas ?? 2))
    setTelefone(reserva?.telefone ?? '')
    setEmail(reserva?.email ?? '')
    setArea(reserva?.area ?? '')
    setMesa(reserva?.mesa ?? '')
    setObservacao(reserva?.observacao ?? '')
    setStatus(reserva?.status ?? 'confirmada')
    setTentou(false)
  }, [aberto, reserva, dataPadrao])

  const n = Number(pessoas)
  const erros = {
    data: !data ? 'Informe a data' : null,
    nome: !nome.trim() ? 'Informe o nome do cliente' : null,
    pessoas: !Number.isInteger(n) || n < 1 || n > 500 ? 'Número de pessoas inválido' : null,
    email: email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ? 'E-mail inválido' : null,
  }
  const vazio = (s: string) => s.trim() || null

  const enviar = async () => {
    setTentou(true)
    const primeiro = Object.values(erros).find(Boolean)
    if (primeiro) return avisos.erro(primeiro)
    try {
      await salvar.mutateAsync({
        id: reserva?.id,
        dados: {
          data: data!,
          horario,
          nomeCliente: nome.trim(),
          pessoas: n,
          telefone: vazio(telefone),
          email: vazio(email),
          area: vazio(area),
          mesa: vazio(mesa),
          observacao: vazio(observacao),
          status,
        },
      })
      avisos.sucesso(reserva ? 'Reserva atualizada' : 'Reserva cadastrada')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo={reserva ? 'Editar reserva' : 'Nova reserva'}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao onClick={enviar} carregando={salvar.isPending}>
            {reserva ? 'Salvar' : 'Cadastrar'}
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Campo rotulo="Nome do cliente" htmlFor={`${id}-n`} obrigatorio erro={tentou ? erros.nome : null}>
            <Entrada id={`${id}-n`} value={nome} maxLength={200} onChange={(e) => setNome(e.target.value)} autoComplete="off" />
          </Campo>
        </div>
        <Campo rotulo="Data" htmlFor={`${id}-d`} obrigatorio erro={tentou ? erros.data : null}>
          <EntradaData id={`${id}-d`} valor={data} aoMudar={setData} />
        </Campo>
        <Campo rotulo="Horário" htmlFor={`${id}-h`}>
          <EntradaHora id={`${id}-h`} valor={horario} aoMudar={setHorario} />
        </Campo>
        <Campo rotulo="Pessoas" htmlFor={`${id}-p`} obrigatorio erro={tentou ? erros.pessoas : null}>
          <Entrada id={`${id}-p`} type="number" min={1} max={500} inputMode="numeric" className="numero" value={pessoas} onChange={(e) => setPessoas(e.target.value)} />
        </Campo>
        <Campo rotulo="Status" htmlFor={`${id}-s`}>
          <Selecao id={`${id}-s`} value={status} onChange={(e) => setStatus(e.target.value as StatusReserva)}>
            {STATUS_RESERVA.map((s) => (
              <option key={s} value={s}>
                {rotuloStatusReserva[s]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <Campo rotulo="Telefone" htmlFor={`${id}-t`}>
          <Entrada id={`${id}-t`} type="tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} />
        </Campo>
        <Campo rotulo="E-mail" htmlFor={`${id}-e`} erro={tentou ? erros.email : null}>
          <Entrada id={`${id}-e`} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </Campo>
        <Campo rotulo="Área / ambiente" htmlFor={`${id}-a`}>
          <Entrada id={`${id}-a`} value={area} placeholder="Ex.: Varanda" onChange={(e) => setArea(e.target.value)} />
        </Campo>
        <Campo rotulo="Mesa" htmlFor={`${id}-m`}>
          <Entrada id={`${id}-m`} value={mesa} onChange={(e) => setMesa(e.target.value)} />
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação" htmlFor={`${id}-o`}>
            <AreaTexto id={`${id}-o`} className="min-h-20" value={observacao} placeholder="Aniversário, cadeirinha, alergia…" onChange={(e) => setObservacao(e.target.value)} />
          </Campo>
        </div>
      </div>
    </Modal>
  )
}

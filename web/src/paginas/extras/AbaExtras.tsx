/**
 * Aba "Extras" — cadastro de freelas/diaristas (adendo E.1): nome, função, contato, pontuação padrão e valor da diária.
 */
import { useEffect, useId, useState } from 'react'
import { AlertTriangle, CalendarPlus, Check, FileUp, Pencil, Plus, Power, Search, Trash2, UserRoundPlus } from 'lucide-react'
import type { Extra } from '@/tipos/banco'
import { AreaTexto, Botao, Campo, Cartao, Entrada, EntradaMoeda, ErroCarga, Interruptor, Modal, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useAtivarExtra, useDefinirPontuacao, useExcluirExtra, useExtras, useSalvarExtra } from '@/consultas/extras'
import { ImportarExtras } from './ImportarExtras'
import { filtrarExtras, formatarTelefone, lerPontos, pontosTexto } from '@/lib/extras'
import { formatarCentavos, formatarData } from '@/lib/formato'

export function AbaExtras({
  aoLancarDia,
  soPendentes = false,
  aoMudarPendentes,
}: {
  aoLancarDia(extraId: string): void
  soPendentes?: boolean
  aoMudarPendentes?(v: boolean): void
}) {
  const avisos = useAvisos()
  const [inativos, setInativos] = useState(false)
  const [busca, setBusca] = useState('')
  const lista = useExtras(inativos)
  const ativar = useAtivarExtra()
  const excluir = useExcluirExtra()
  const [modal, setModal] = useState<{ extra: Extra | null } | null>(null)
  const [importando, setImportando] = useState(false)
  const pendentes = (lista.data ?? []).filter((x) => x.pontos_pendente)
  const linhas = filtrarExtras(soPendentes ? pendentes : (lista.data ?? []), busca)
  const idBusca = useId()

  const alternarAtivo = async (x: Extra) => {
    if (x.ativo) {
      const ok = await avisos.confirmar({
        titulo: `Desativar ${x.nome}?`,
        mensagem: 'Os dias já lançados continuam valendo; só não dá para lançar dias novos até reativar.',
        textoConfirmar: 'Desativar',
      })
      if (!ok) return
    }
    try {
      await ativar.mutateAsync({ extra: x, ativo: !x.ativo })
      avisos.sucesso(x.ativo ? `${x.nome} desativado` : `${x.nome} reativado`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const apagar = async (x: Extra) => {
    if (!(await avisos.confirmar({ titulo: `Excluir o cadastro de ${x.nome}?`, textoConfirmar: 'Excluir', perigo: true }))) return
    try {
      await excluir.mutateAsync(x.id)
      avisos.sucesso('Cadastro excluído')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const colunas: Coluna<Extra>[] = [
    {
      id: 'nome',
      titulo: 'Extra',
      render: (x) => (
        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-2 font-semibold text-creme">
            <span className="truncate">{x.nome}</span>
            {!x.ativo && <Selo>Inativo</Selo>}
            {x.pontos_pendente && <Selo tom="alerta">Pontuação pendente</Selo>}
          </p>
          <p className="text-xs text-lavanda">{[x.funcao, formatarTelefone(x.telefone)].filter(Boolean).join(' · ') || '—'}</p>
        </div>
      ),
    },
    {
      id: 'pontos',
      titulo: 'Pontos',
      alinhar: 'direita',
      render: (x) => (x.pontos_pendente ? <PontuacaoRapida extra={x} /> : <span className="numero">{pontosTexto(x.pontos_padrao)}</span>),
    },
    {
      id: 'diaria',
      titulo: 'Diária',
      alinhar: 'direita',
      render: (x) => <span className="numero">{x.valor_diaria_centavos == null ? '—' : formatarCentavos(x.valor_diaria_centavos)}</span>,
    },
    {
      id: 'dias',
      titulo: 'Dias lançados',
      alinhar: 'direita',
      ocultarNoCelular: true,
      render: (x) => (
        <span className="numero text-lavanda">
          {x.dias_lancados}
          {x.ultimo_dia && <span className="block text-[11px]">último {formatarData(x.ultimo_dia)}</span>}
        </span>
      ),
    },
    {
      id: 'acoes',
      titulo: '',
      alinhar: 'direita',
      render: (x) => (
        <div className="flex justify-end gap-1">
          {x.ativo && (
            <Botao variante="secundario" tamanho="p" icone={<CalendarPlus aria-hidden />} aria-label={`Lançar dia de ${x.nome}`} onClick={() => aoLancarDia(x.id)}>
              <span className="hidden sm:inline">Lançar dia</span>
            </Botao>
          )}
          <Botao variante="fantasma" tamanho="p" icone={<Pencil aria-hidden />} aria-label={`Editar ${x.nome}`} onClick={() => setModal({ extra: x })} />
          <Botao
            variante="fantasma"
            tamanho="p"
            icone={<Power aria-hidden />}
            aria-label={x.ativo ? `Desativar ${x.nome}` : `Reativar ${x.nome}`}
            title={x.ativo ? 'Desativar' : 'Reativar'}
            disabled={ativar.isPending}
            onClick={() => alternarAtivo(x)}
          />
          {x.dias_lancados === 0 && (
            <Botao variante="fantasma" tamanho="p" icone={<Trash2 aria-hidden />} aria-label={`Excluir ${x.nome}`} onClick={() => apagar(x)} />
          )}
        </div>
      ),
    },
  ]

  return (
    <Cartao
      titulo="Cadastro de extras"
      sobrancelha={`${(lista.data ?? []).filter((x) => x.ativo).length} ativo(s)`}
      acoes={
        <>
          <Botao variante="secundario" tamanho="p" icone={<FileUp aria-hidden />} onClick={() => setImportando(true)}>
            Importar extras
          </Botao>
          <Botao tamanho="p" icone={<Plus aria-hidden />} onClick={() => setModal({ extra: null })}>
            Novo extra
          </Botao>
        </>
      }
    >
      {pendentes.length > 0 && (
        <div role="status" data-teste="aviso-pontuacao-pendente" className="mb-4 flex flex-wrap items-center gap-3 rounded-entrada border border-alerta/50 bg-alerta/10 p-3 text-sm text-alerta">
          <AlertTriangle aria-hidden className="size-4 shrink-0" />
          <span className="min-w-0 flex-1 basis-56">
            <strong>{pendentes.length} extra(s) com pontuação pendente.</strong> Não entram na comissão e bloqueiam o fechamento até você preencher os pontos.
          </span>
          {!soPendentes && aoMudarPendentes && (
            <Botao variante="secundario" tamanho="p" onClick={() => aoMudarPendentes(true)}>
              Ver só os pendentes
            </Botao>
          )}
        </div>
      )}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="relative min-w-0 flex-1 basis-56">
          <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-lavanda" />
          <label htmlFor={idBusca} className="sr-only">
            Buscar extra
          </label>
          <Entrada id={idBusca} className="pl-10" placeholder="Buscar por nome, função, telefone ou documento" value={busca} onChange={(e) => setBusca(e.target.value)} />
        </div>
        <Interruptor rotulo="Mostrar inativos" marcado={inativos} aoMudar={setInativos} />
        {aoMudarPendentes && (
          <Interruptor rotulo={`Só pontuação pendente (${pendentes.length})`} marcado={soPendentes} aoMudar={aoMudarPendentes} />
        )}
      </div>
      {lista.error ? (
        <ErroCarga erro={lista.error} aoTentar={() => lista.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={linhas}
          chave={(x) => x.id}
          carregando={lista.isLoading}
          vazio={
            soPendentes ? (
              <Vazio titulo="Nenhum extra com pontuação pendente" descricao="Tudo preenchido: os extras entram na comissão normalmente." />
            ) : busca.trim() ? (
              <Vazio titulo="Nenhum extra encontrado" descricao="Confira a busca ou mostre os inativos." />
            ) : (
              <Vazio
                icone={<UserRoundPlus aria-hidden />}
                titulo="Nenhum extra cadastrado"
                descricao="Cadastre os freelas e diaristas com a pontuação e o valor da diária de costume."
                acao={
                  <Botao icone={<Plus aria-hidden />} onClick={() => setModal({ extra: null })}>
                    Novo extra
                  </Botao>
                }
              />
            )
          }
        />
      )}
      <ModalExtra aberto={!!modal} extra={modal?.extra ?? null} aoFechar={() => setModal(null)} />
      <ImportarExtras aberto={importando} aoFechar={() => setImportando(false)} aoVerPendentes={() => aoMudarPendentes?.(true)} />
    </Cartao>
  )
}

/** Edição rápida da pontuação de um extra pendente (direto na lista): grava no cadastro e nos dias pendentes. */
function PontuacaoRapida({ extra }: { extra: Extra }) {
  const avisos = useAvisos()
  const definir = useDefinirPontuacao()
  const [texto, setTexto] = useState('')
  const salvar = async () => {
    const n = lerPontos(texto)
    if (n == null) return avisos.erro('Pontos inválidos (0 a 9999,99)')
    try {
      const dias = await definir.mutateAsync({ extraId: extra.id, pontos: n })
      avisos.sucesso(`Pontuação de ${extra.nome} definida${dias ? ` (${dias} dia(s) atualizado(s))` : ''}`)
    } catch (e) {
      avisos.erro(e)
    }
  }
  return (
    <span className="flex items-center justify-end gap-1">
      {extra.dias_pendentes > 0 && <span className="hidden text-[11px] text-alerta lg:inline">{extra.dias_pendentes} dia(s)</span>}
      <Entrada
        aria-label={`Pontos de ${extra.nome}`}
        className="numero h-9! w-20! px-2! text-right"
        inputMode="decimal"
        placeholder="—"
        value={texto}
        invalido={texto.trim() !== '' && lerPontos(texto) == null}
        onChange={(e) => setTexto(e.target.value.replace(/[^\d,.]/g, ''))}
        onKeyDown={(e) => e.key === 'Enter' && void salvar()}
      />
      <Botao
        tamanho="p"
        variante="secundario"
        icone={<Check aria-hidden />}
        aria-label={`Salvar pontos de ${extra.nome}`}
        carregando={definir.isPending}
        disabled={texto.trim() === ''}
        onClick={() => void salvar()}
      />
    </span>
  )
}

export function ModalExtra({
  aberto,
  extra,
  aoFechar,
  aoSalvar,
  nomeInicial,
}: {
  aberto: boolean
  extra: Extra | null
  aoFechar(): void
  /** chamado com o id depois de salvar (ex.: lançar o dia em seguida) */
  aoSalvar?(id: string): void
  nomeInicial?: string
}) {
  const avisos = useAvisos()
  const salvar = useSalvarExtra()
  const id = useId()
  const [nome, setNome] = useState('')
  const [funcao, setFuncao] = useState('')
  const [telefone, setTelefone] = useState('')
  const [documento, setDocumento] = useState('')
  const [pontos, setPontos] = useState('')
  const [valor, setValor] = useState<number | null>(null)
  const [observacoes, setObservacoes] = useState('')
  const [ativo, setAtivo] = useState(true)
  const [tentou, setTentou] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setNome(extra?.nome ?? nomeInicial ?? '')
    setFuncao(extra?.funcao ?? '')
    setTelefone(extra?.telefone ?? '')
    setDocumento(extra?.documento ?? '')
    setPontos(extra && !extra.pontos_pendente ? pontosTexto(extra.pontos_padrao) : '')
    setValor(extra?.valor_diaria_centavos ?? null)
    setObservacoes(extra?.observacoes ?? '')
    setAtivo(extra?.ativo ?? true)
    setTentou(false)
  }, [aberto, extra, nomeInicial])

  const pendente = !!extra?.pontos_pendente
  const pontosVazio = pontos.trim() === ''
  const pontosLidos = pontosVazio ? (pendente ? null : 0) : lerPontos(pontos)
  const erros = {
    nome: !nome.trim() ? 'Informe o nome' : null,
    pontos: !pontosVazio && pontosLidos == null ? 'Pontos inválidos (0 a 9999,99)' : null,
    valor: valor != null && (valor < 0 || valor > 100_000_000) ? 'Valor inválido' : null,
  }

  const enviar = async () => {
    setTentou(true)
    const primeiro = Object.values(erros).find(Boolean)
    if (primeiro) return avisos.erro(primeiro)
    try {
      const novoId = await salvar.mutateAsync({
        id: extra?.id,
        dados: {
          nome: nome.trim(),
          funcao: funcao.trim() || null,
          pontosPadrao: pontosLidos,
          valorDiariaCentavos: valor,
          telefone: telefone.trim() || null,
          documento: documento.trim() || null,
          observacoes: observacoes.trim() || null,
          ativo,
        },
      })
      avisos.sucesso(extra ? 'Cadastro atualizado' : `${nome.trim()} cadastrado`)
      aoSalvar?.(novoId)
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo={extra ? `Editar ${extra.nome}` : 'Novo extra'}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao onClick={enviar} carregando={salvar.isPending}>
            {extra ? 'Salvar' : 'Cadastrar'}
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Campo rotulo="Nome" htmlFor={`${id}-n`} obrigatorio erro={tentou ? erros.nome : null}>
            <Entrada id={`${id}-n`} value={nome} maxLength={120} autoComplete="off" onChange={(e) => setNome(e.target.value)} />
          </Campo>
        </div>
        <Campo rotulo="Função" htmlFor={`${id}-f`} ajuda="Ex.: Garçom, Cozinha, Bar">
          <Entrada id={`${id}-f`} value={funcao} maxLength={80} onChange={(e) => setFuncao(e.target.value)} />
        </Campo>
        <Campo rotulo="Telefone" htmlFor={`${id}-t`}>
          <Entrada id={`${id}-t`} type="tel" inputMode="tel" value={telefone} maxLength={40} autoComplete="off" onChange={(e) => setTelefone(e.target.value)} />
        </Campo>
        <Campo
          rotulo="Pontuação padrão"
          htmlFor={`${id}-p`}
          erro={tentou ? erros.pontos : null}
          ajuda={pendente ? 'Pontuação pendente: preencha para o extra entrar na comissão (vale também para os dias já lançados).' : 'Pontos de comissão em cada dia trabalhado.'}
        >
          <Entrada
            id={`${id}-p`}
            className="numero"
            inputMode="decimal"
            placeholder="0"
            value={pontos}
            invalido={tentou && !!erros.pontos}
            onChange={(e) => setPontos(e.target.value.replace(/[^\d,.]/g, ''))}
          />
        </Campo>
        <Campo rotulo="Valor da diária" htmlFor={`${id}-v`} erro={tentou ? erros.valor : null} ajuda="Em branco: informar a cada dia.">
          <EntradaMoeda id={`${id}-v`} centavos={valor} aoMudar={setValor} />
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Documento" htmlFor={`${id}-d`} ajuda="CPF ou RG (opcional).">
            <Entrada id={`${id}-d`} value={documento} maxLength={40} autoComplete="off" onChange={(e) => setDocumento(e.target.value)} />
          </Campo>
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Observações" htmlFor={`${id}-o`}>
            <AreaTexto id={`${id}-o`} className="min-h-16" value={observacoes} onChange={(e) => setObservacoes(e.target.value)} />
          </Campo>
        </div>
        {extra && (
          <div className="sm:col-span-2">
            <Interruptor rotulo="Ativo (pode receber dias novos)" marcado={ativo} aoMudar={setAtivo} />
          </div>
        )}
      </div>
    </Modal>
  )
}

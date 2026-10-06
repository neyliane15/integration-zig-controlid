/** /integracoes/:id — detalhe: visão geral, configuração (A M), lojas Zig, usuários e envio Control iD. Dono: frontend-1. */
import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Send, Store, Trash2, Upload } from 'lucide-react'
import type { StatusEnvioControlId } from '@/tipos/banco'
import { Abas, Botao, CabecalhoPagina, Cartao, Carregando, ErroCarga, Interruptor, Selo, Tabela, Vazio, type Tom } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoSincronizar, SeloStatusIntegracao } from '@/componentes/integracoes/comum'
import { FormularioIntegracao } from '@/componentes/integracoes/FormularioIntegracao'
import { HistoricoExecucoes } from '@/componentes/integracoes/HistoricoExecucoes'
import { VinculoControlId } from '@/componentes/dominio/VinculoControlId'
import {
  useEnviosControlId,
  useExcluirIntegracao,
  useIntegracao,
  useLojasZig,
  useMarcarLojaZig,
  useReenviarControlId,
  useSolicitacoesAbertas,
} from '@/consultas/integracoes'
import { formatarDataHora, formatarRelativo } from '@/lib/formato'
import { podeAdministrar } from '@/lib/permissoes'
import { rotuloOperacaoEnvio, rotuloStatusEnvio, rotuloTipoIntegracao } from '@/lib/rotulos'
import { useEmpresaAtual, usePerfil } from '@/lib/sessao'

type Aba = 'geral' | 'configuracao' | 'lojas' | 'usuarios' | 'envio'

export function PaginaIntegracao() {
  const { id } = useParams()
  const perfil = usePerfil()
  const admin = podeAdministrar(perfil.papel)
  const { empresaId } = useEmpresaAtual()
  const consulta = useIntegracao(id)
  const abertas = useSolicitacoesAbertas(empresaId)
  const excluir = useExcluirIntegracao()
  const avisos = useAvisos()
  const navegar = useNavigate()
  const [aba, setAba] = useState<Aba>('geral')

  if (consulta.isPending) return <Carregando />
  if (consulta.isError) return <ErroCarga erro={consulta.error} aoTentar={() => void consulta.refetch()} />
  const i = consulta.data
  if (!i)
    return (
      <Vazio
        titulo="Integração não encontrada"
        acao={
          <Link to="/integracoes" className="text-sm font-semibold text-ouro hover:underline">
            Voltar às integrações
          </Link>
        }
      />
    )

  const ehControlId = i.tipo !== 'zig'
  const executando = (abertas.data ?? []).some((s) => s.integracao_id === i.id)
  const abas: { id: Aba; rotulo: string }[] = [
    { id: 'geral', rotulo: 'Visão geral' },
    { id: 'configuracao', rotulo: admin ? 'Configuração' : 'Parâmetros' },
    ...(i.tipo === 'zig' ? [{ id: 'lojas' as Aba, rotulo: 'Lojas' }] : []),
    ...(ehControlId ? [{ id: 'usuarios' as Aba, rotulo: 'Usuários do equipamento' }, { id: 'envio' as Aba, rotulo: 'Envio' }] : []),
  ]

  async function apagar() {
    const ok = await avisos.confirmar({
      titulo: `Excluir "${i!.nome}"?`,
      mensagem: 'As credenciais e o histórico de sincronização desta integração serão apagados. Os dados já importados continuam.',
      textoConfirmar: 'Excluir',
      perigo: true,
    })
    if (!ok) return
    excluir.mutate(i!.id, {
      onSuccess: () => {
        avisos.sucesso('Integração excluída.')
        navegar('/integracoes', { replace: true })
      },
      onError: avisos.erro,
    })
  }

  return (
    <div className="surgir">
      <Link to="/integracoes" className="mb-4 inline-flex items-center gap-1.5 text-sm font-semibold text-lavanda hover:text-creme">
        <ArrowLeft aria-hidden className="size-4" /> Integrações
      </Link>
      <CabecalhoPagina
        sobrancelha={rotuloTipoIntegracao[i.tipo]}
        titulo={i.nome}
        subtitulo={
          <span className="flex flex-wrap items-center gap-2">
            <SeloStatusIntegracao ativa={i.ativa} status={i.ultimo_status} executando={executando} />
            <span>Último sucesso {formatarRelativo(i.ultimo_sucesso_em)}</span>
          </span>
        }
        acoes={
          <>
            {i.ativa && <BotaoSincronizar empresaId={empresaId} integracaoId={i.id} tamanho="m" desabilitado={executando} />}
            {admin && (
              <Botao variante="perigo" icone={<Trash2 aria-hidden />} onClick={apagar} carregando={excluir.isPending}>
                Excluir
              </Botao>
            )}
          </>
        }
      />

      <div className="mb-6">
        <Abas<Aba> abas={abas} ativa={aba} aoMudar={setAba} />
      </div>

      {aba === 'geral' && (
        <div className="flex flex-col gap-5">
          {i.ultimo_status === 'erro' && i.ultimo_erro && (
            <Cartao sobrancelha="Último erro" className="border-perigo/30">
              <p className="text-sm text-creme">{i.ultimo_erro}</p>
              {i.ultima_execucao_em && <p className="mt-2 text-xs text-lavanda">em {formatarDataHora(i.ultima_execucao_em)}</p>}
            </Cartao>
          )}
          <HistoricoExecucoes empresaId={empresaId} integracaoId={i.id} />
        </div>
      )}

      {aba === 'configuracao' && empresaId && (
        <Cartao>
          <FormularioIntegracao key={i.atualizado_em} empresaId={empresaId} tipo={i.tipo} integracao={i} somenteLeitura={!admin} />
        </Cartao>
      )}

      {aba === 'lojas' && <LojasZig empresaId={empresaId} integracaoId={i.id} admin={admin} />}

      {aba === 'usuarios' && (
        <div className="flex flex-col gap-4">
          <p className="text-sm text-lavanda">
            Usuários lidos do equipamento e o funcionário correspondente. O vínculo automático usa matrícula, CPF ou PIS.
          </p>
          <VinculoControlId integracaoId={i.id} />
        </div>
      )}

      {aba === 'envio' && (
        <EnvioControlId
          empresaId={empresaId}
          integracaoId={i.id}
          ativo={!!(i.parametros as { envio?: { ativo?: boolean } }).envio?.ativo}
          admin={admin}
          aoConfigurar={() => setAba('configuracao')}
        />
      )}
    </div>
  )
}

function LojasZig({ empresaId, integracaoId, admin }: { empresaId: string | null; integracaoId: string; admin: boolean }) {
  const lojas = useLojasZig(empresaId, integracaoId)
  const marcar = useMarcarLojaZig()
  const avisos = useAvisos()
  if (lojas.isError) return <ErroCarga erro={lojas.error} aoTentar={() => void lojas.refetch()} />
  return (
    <Tabela
      carregando={lojas.isPending}
      linhas={lojas.data ?? []}
      chave={(l) => l.id}
      vazio={<Vazio icone={<Store aria-hidden />} titulo="Nenhuma loja ainda" descricao="As lojas da rede aparecem depois da primeira sincronização." />}
      colunas={[
        { id: 'nome', titulo: 'Loja', render: (l) => <span className="font-semibold">{l.nome}</span> },
        { id: 'id', titulo: 'Id na Zig', render: (l) => <span className="numero text-sm text-lavanda">{l.loja_id_externo}</span> },
        { id: 'visto', titulo: 'Vista', ocultarNoCelular: true, render: (l) => <span className="text-sm text-lavanda">{formatarRelativo(l.visto_em)}</span> },
        {
          id: 'sinc',
          titulo: 'Sincronizar',
          alinhar: 'direita',
          render: (l) => (
            <Interruptor
              rotulo={<span className="sr-only">Sincronizar {l.nome}</span>}
              marcado={l.sincronizar}
              desabilitado={!admin || marcar.isPending}
              aoMudar={(v) => marcar.mutate({ id: l.id, sincronizar: v }, { onError: avisos.erro })}
            />
          ),
        },
      ]}
    />
  )
}

const TOM_ENVIO: Record<StatusEnvioControlId, Tom> = {
  pendente: 'info',
  enviando: 'info',
  enviado: 'sucesso',
  erro: 'perigo',
  aguardando: 'alerta',
}

function EnvioControlId({
  empresaId,
  integracaoId,
  ativo,
  admin,
  aoConfigurar,
}: {
  empresaId: string | null
  integracaoId: string
  ativo: boolean
  admin: boolean
  aoConfigurar(): void
}) {
  const envios = useEnviosControlId(empresaId, integracaoId)
  const reenviar = useReenviarControlId()
  const avisos = useAvisos()

  if (!ativo)
    return (
      <Vazio
        icone={<Send aria-hidden />}
        titulo="Envio desligado"
        descricao="Ligue “Enviar dados para o equipamento” para que o cadastro de funcionários (nome, matrícula, CPF, cartões, senha e foto) alimente este equipamento."
        acao={admin ? <Botao variante="secundario" onClick={aoConfigurar}>Abrir configuração</Botao> : undefined}
      />
    )

  const linhas = envios.data ?? []
  const contagem = linhas.reduce<Partial<Record<StatusEnvioControlId, number>>>((a, e) => ({ ...a, [e.status]: (a[e.status] ?? 0) + 1 }), {})
  const problemas = linhas.filter((e) => e.status === 'erro' || e.status === 'aguardando' || e.status === 'pendente' || e.status === 'enviando')

  return (
    <div className="flex flex-col gap-5">
      <Cartao
        sobrancelha="Fila de envio"
        titulo="Sistema → equipamento"
        acoes={
          <>
            {(contagem.erro ?? 0) > 0 && (
              <Botao
                variante="secundario"
                tamanho="p"
                carregando={reenviar.isPending}
                onClick={() =>
                  reenviar.mutate(
                    { integracaoId, empresaId },
                    { onSuccess: (n) => avisos.sucesso(`${n} envio(s) voltaram para a fila.`), onError: avisos.erro },
                  )
                }
              >
                Reenviar com erro
              </Botao>
            )}
            <BotaoSincronizar
              empresaId={empresaId}
              integracaoId={integracaoId}
              escopo="exportar_funcionarios"
              rotulo="Enviar funcionários ao equipamento"
              variante="primario"
            />
          </>
        }
      >
        {envios.isError ? (
          <ErroCarga erro={envios.error} aoTentar={() => void envios.refetch()} />
        ) : (
          <div className="flex flex-wrap gap-2">
            {(Object.keys(rotuloStatusEnvio) as StatusEnvioControlId[]).map((s) => (
              <Selo key={s} tom={(contagem[s] ?? 0) > 0 ? TOM_ENVIO[s] : 'neutro'}>
                {rotuloStatusEnvio[s]}: <span className="numero">{contagem[s] ?? 0}</span>
              </Selo>
            ))}
          </div>
        )}
      </Cartao>

      <Tabela
        carregando={envios.isPending}
        linhas={problemas}
        chave={(e) => e.id}
        vazio={<Vazio icone={<Upload aria-hidden />} titulo="Tudo enviado" descricao="O equipamento está igual ao cadastro." />}
        colunas={[
          {
            id: 'quem',
            titulo: 'Funcionário',
            render: (e) => <span className="font-semibold">{e.alvo === 'horarios' ? 'Horários de acesso' : (e.funcionario_nome ?? '—')}</span>,
          },
          { id: 'op', titulo: 'Operação', render: (e) => rotuloOperacaoEnvio[e.operacao] },
          { id: 'status', titulo: 'Status', render: (e) => <Selo tom={TOM_ENVIO[e.status]}>{rotuloStatusEnvio[e.status]}</Selo> },
          {
            id: 'motivo',
            titulo: 'Motivo',
            render: (e) => <span className="text-sm text-lavanda">{e.erro ?? (e.pendente_desde ? `Na fila ${formatarRelativo(e.pendente_desde)}` : '—')}</span>,
          },
          { id: 'tent', titulo: 'Tentativas', alinhar: 'direita', ocultarNoCelular: true, render: (e) => <span className="numero">{e.tentativas}</span> },
        ]}
      />
    </div>
  )
}

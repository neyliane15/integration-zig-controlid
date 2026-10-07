/** /integracoes — cartões por integração, sincronizar agora, criar (A M), histórico. Dono: frontend-1. */
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import clsx from 'clsx'
import { ChevronRight, Clock, Plus, PlugZap, RefreshCw } from 'lucide-react'
import type { Integracao, TipoIntegracao } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Cartao, ErroCarga, Esqueleto, FOCO, Modal, Selo, Vazio } from '@/componentes/ui'
import { BotaoSincronizar, IconeIntegracao, SeloStatusIntegracao } from '@/componentes/integracoes/comum'
import { FormularioIntegracao } from '@/componentes/integracoes/FormularioIntegracao'
import { HistoricoExecucoes } from '@/componentes/integracoes/HistoricoExecucoes'
import { useIntegracoes, useSolicitacoesAbertas } from '@/consultas/integracoes'
import { formatarRelativo } from '@/lib/formato'
import { podeAdministrar } from '@/lib/permissoes'
import { rotuloStatusSolicitacao, rotuloTipoIntegracao } from '@/lib/rotulos'
import { useEmpresaAtual, usePerfil } from '@/lib/sessao'

const DESCRICAO_TIPO: Record<TipoIntegracao, string> = {
  zig: 'Vendas, faturamento por forma de pagamento e serviço (10%) para as comissões.',
  controlid_acesso: 'Batidas de iDFace, iDFlex ou iDAccess usadas como ponto, e envio do cadastro ao equipamento.',
  controlid_rep: 'Marcações do relógio de ponto iDClass (AFD), com envio opcional do cadastro.',
}

export function PaginaIntegracoes() {
  const perfil = usePerfil()
  const admin = podeAdministrar(perfil.papel)
  const { empresaId } = useEmpresaAtual()
  const integracoes = useIntegracoes(empresaId)
  const abertas = useSolicitacoesAbertas(empresaId)
  const [novoTipo, setNovoTipo] = useState<TipoIntegracao | 'escolher' | null>(null)
  const navegar = useNavigate()

  const lista = integracoes.data ?? []
  const nomes = Object.fromEntries(lista.map((i) => [i.id, i.nome]))
  const fila = abertas.data ?? []

  return (
    <div className="surgir">
      <CabecalhoPagina
        sobrancelha="Ajustes"
        titulo={
          <>
            Integra<span className="titulo-italico">ções</span>
          </>
        }
        subtitulo="Zig e Control iD conversando com a sua rotina. O N8N busca os dados no horário e quando você pede."
        acoes={
          <>
            {lista.some((i) => i.ativa) && <BotaoSincronizar empresaId={empresaId} rotulo="Sincronizar tudo" tamanho="m" />}
            {admin && (
              <Botao icone={<Plus aria-hidden />} onClick={() => setNovoTipo('escolher')}>
                Nova integração
              </Botao>
            )}
          </>
        }
      />

      {fila.length > 0 && (
        <div role="status" className="mb-5 flex flex-wrap items-center gap-3 rounded-entrada border border-info/30 bg-info/5 px-4 py-3 text-sm text-creme">
          <RefreshCw aria-hidden className="size-4 animate-spin text-info" />
          {fila.length === 1 ? '1 sincronização' : `${fila.length} sincronizações`} em andamento:{' '}
          {fila
            .slice(0, 4)
            .map((s) => `${s.integracao_id ? (nomes[s.integracao_id] ?? 'Integração') : 'Empresa'} (${rotuloStatusSolicitacao[s.status].toLowerCase()})`)
            .join(', ')}
          . Atualiza sozinho.
        </div>
      )}

      {integracoes.isError ? (
        <ErroCarga erro={integracoes.error} aoTentar={() => void integracoes.refetch()} />
      ) : integracoes.isPending ? (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {[0, 1, 2].map((i) => (
            <Esqueleto key={i} className="h-52 rounded-cartao" />
          ))}
        </div>
      ) : lista.length === 0 ? (
        <Vazio
          icone={<PlugZap aria-hidden />}
          titulo="Nenhuma integração ainda"
          descricao="Conecte a Zig para ver vendas e comissões, e o Control iD para o ponto da equipe."
          acao={admin ? <Botao icone={<Plus aria-hidden />} onClick={() => setNovoTipo('escolher')}>Nova integração</Botao> : undefined}
        />
      ) : (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {lista.map((i) => (
            <CartaoIntegracao key={i.id} i={i} empresaId={empresaId} executando={fila.some((s) => s.integracao_id === i.id)} />
          ))}
        </div>
      )}

      <section className="mt-10">
        <div className="mb-4">
          <p className="sobrancelha">Histórico</p>
          <h2 className="mt-1.5 font-display text-2xl text-creme">Últimas execuções</h2>
        </div>
        <HistoricoExecucoes empresaId={empresaId} nomes={nomes} />
      </section>

      <Modal
        aberto={novoTipo != null}
        aoFechar={() => setNovoTipo(null)}
        titulo={novoTipo && novoTipo !== 'escolher' ? `Nova integração · ${rotuloTipoIntegracao[novoTipo]}` : 'Nova integração'}
        largura={novoTipo === 'escolher' ? 'm' : 'g'}
      >
        {novoTipo === 'escolher' ? (
          <ul className="flex flex-col gap-3">
            {(['zig', 'controlid_acesso', 'controlid_rep'] as TipoIntegracao[]).map((t) => (
              <li key={t}>
                <button
                  type="button"
                  onClick={() => setNovoTipo(t)}
                  className={clsx(
                    'flex w-full items-center gap-4 rounded-entrada border border-borda bg-entrada p-4 text-left transition-colors hover:border-ouro/60 hover:bg-cartao-2',
                    FOCO,
                  )}
                >
                  <IconeIntegracao tipo={t} />
                  <span className="min-w-0 flex-1">
                    <span className="block font-semibold text-creme">{rotuloTipoIntegracao[t]}</span>
                    <span className="mt-0.5 block text-sm text-lavanda">{DESCRICAO_TIPO[t]}</span>
                  </span>
                  <ChevronRight aria-hidden className="size-4 text-lavanda" />
                </button>
              </li>
            ))}
          </ul>
        ) : novoTipo && empresaId ? (
          <FormularioIntegracao
            empresaId={empresaId}
            tipo={novoTipo}
            aoCancelar={() => setNovoTipo(null)}
            aoSalvar={(id) => {
              setNovoTipo(null)
              navegar(`/integracoes/${id}`)
            }}
          />
        ) : null}
      </Modal>
    </div>
  )
}

function CartaoIntegracao({ i, empresaId, executando }: { i: Integracao; empresaId: string | null; executando: boolean }) {
  const envioAtivo = i.tipo !== 'zig' && !!(i.parametros as { envio?: { ativo?: boolean } }).envio?.ativo
  const modelo = (i.parametros as { modelo?: string }).modelo
  return (
    <Cartao className="flex flex-col">
      <div className="flex items-start gap-3">
        <IconeIntegracao tipo={i.tipo} />
        <div className="min-w-0 flex-1">
          <Link to={`/integracoes/${i.id}`} className={clsx('block truncate rounded font-display text-xl text-creme hover:text-ouro-claro', FOCO)}>
            {i.nome}
          </Link>
          <p className="truncate text-sm text-lavanda">
            {rotuloTipoIntegracao[i.tipo]}
            {modelo ? ` · ${modelo}` : ''}
          </p>
        </div>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        <SeloStatusIntegracao ativa={i.ativa} status={i.ultimo_status} executando={executando} />
        {envioAtivo && <Selo tom="ouro">Envio ligado</Selo>}
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">Último sucesso</dt>
          <dd className="mt-0.5 text-creme">{formatarRelativo(i.ultimo_sucesso_em)}</dd>
        </div>
        <div>
          <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">Frequência</dt>
          <dd className="mt-0.5 flex items-center gap-1.5 text-creme">
            <Clock aria-hidden className="size-3.5 text-lavanda" />
            {i.intervalo_minutos < 60 ? `${i.intervalo_minutos} min` : `${i.intervalo_minutos / 60} h`}
          </dd>
        </div>
      </dl>
      {i.ultimo_status === 'erro' && i.ultimo_erro && (
        <p className="mt-3 line-clamp-2 rounded-entrada border border-perigo/30 bg-perigo/5 px-3 py-2 text-xs text-perigo" title={i.ultimo_erro}>
          {i.ultimo_erro}
        </p>
      )}
      <div className="mt-auto flex flex-wrap items-center justify-between gap-2 pt-5">
        <Link to={`/integracoes/${i.id}`} className={clsx('inline-flex items-center gap-1 rounded text-sm font-semibold text-ouro hover:text-ouro-claro', FOCO)}>
          Detalhes <ChevronRight aria-hidden className="size-4" />
        </Link>
        {i.ativa && <BotaoSincronizar empresaId={empresaId} integracaoId={i.id} desabilitado={executando} />}
      </div>
    </Cartao>
  )
}

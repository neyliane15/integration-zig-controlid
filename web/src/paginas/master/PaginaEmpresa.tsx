/** /master/empresas/:id — detalhe da empresa (M): situação, operar nela, usuários, excluir. Dono: frontend-1. */
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Power, Trash2 } from 'lucide-react'
import { Botao, CabecalhoPagina, Cartao, Carregando, ErroCarga, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { formatarCnpj, useAtualizarEmpresa, useEmpresa, useExcluirEmpresa } from '@/consultas/empresas'
import { formatarData } from '@/lib/formato'
import { useEmpresaAtual } from '@/lib/sessao'
import { UsuariosDaEmpresa } from '../configuracoes/UsuariosDaEmpresa'

export function PaginaEmpresa() {
  const { id } = useParams()
  const consulta = useEmpresa(id)
  const atualizar = useAtualizarEmpresa()
  const excluir = useExcluirEmpresa()
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { empresaId, definirEmpresa } = useEmpresaAtual()

  if (consulta.isPending) return <Carregando />
  if (consulta.isError) return <ErroCarga erro={consulta.error} aoTentar={() => void consulta.refetch()} />
  const e = consulta.data
  if (!e)
    return (
      <Vazio
        titulo="Empresa não encontrada"
        acao={
          <Link to="/master/empresas" className="text-sm font-semibold text-ouro hover:underline">
            Voltar às empresas
          </Link>
        }
      />
    )

  async function alternarAtiva() {
    const ok = await avisos.confirmar({
      titulo: e!.ativa ? `Desativar ${e!.nome}?` : `Reativar ${e!.nome}?`,
      mensagem: e!.ativa ? 'Ninguém da empresa conseguirá entrar até reativar. Os dados são mantidos.' : 'Os usuários voltam a ter acesso.',
      textoConfirmar: e!.ativa ? 'Desativar' : 'Reativar',
      perigo: e!.ativa,
    })
    if (ok)
      atualizar.mutate(
        { id: e!.id, dados: { ativa: !e!.ativa } },
        { onSuccess: () => avisos.sucesso(e!.ativa ? 'Empresa desativada.' : 'Empresa reativada.'), onError: avisos.erro },
      )
  }

  async function apagar() {
    const ok = await avisos.confirmar({
      titulo: `Excluir ${e!.nome} definitivamente?`,
      mensagem: 'Apaga a empresa e TODOS os dados dela (funcionários, ponto, vendas, comissões, usuários). Não pode ser desfeito.',
      textoConfirmar: 'Excluir tudo',
      perigo: true,
    })
    if (!ok) return
    excluir.mutate(e!.id, {
      onSuccess: () => {
        if (empresaId === e!.id) definirEmpresa(null)
        avisos.sucesso('Empresa excluída.')
        navegar('/master/empresas', { replace: true })
      },
      onError: avisos.erro,
    })
  }

  return (
    <div className="surgir">
      <Link to="/master/empresas" className="mb-4 inline-flex items-center gap-1.5 text-sm font-semibold text-lavanda hover:text-creme">
        <ArrowLeft aria-hidden className="size-4" /> Empresas
      </Link>
      <CabecalhoPagina
        sobrancelha="Empresa"
        titulo={e.nome}
        subtitulo={
          <span className="flex flex-wrap items-center gap-2">
            {e.ativa ? <Selo tom="sucesso">Ativa</Selo> : <Selo tom="perigo">Inativa</Selo>}
            <span className="numero">{formatarCnpj(e.cnpj)}</span>
            <span>· desde {formatarData(e.criado_em.slice(0, 10))}</span>
          </span>
        }
        acoes={
          <>
            {empresaId !== e.id ? (
              <Botao
                onClick={() => {
                  definirEmpresa(e.id)
                  navegar('/')
                }}
              >
                Operar nesta empresa
              </Botao>
            ) : (
              <Selo tom="ouro">Selecionada</Selo>
            )}
            <Botao variante="secundario" icone={<Power aria-hidden />} onClick={alternarAtiva} carregando={atualizar.isPending}>
              {e.ativa ? 'Desativar' : 'Reativar'}
            </Botao>
            <Botao variante="perigo" icone={<Trash2 aria-hidden />} onClick={apagar} carregando={excluir.isPending}>
              Excluir
            </Botao>
          </>
        }
      />
      <Cartao sobrancelha="Acesso" titulo="Usuários da empresa">
        <UsuariosDaEmpresa empresaId={e.id} />
      </Cartao>
    </div>
  )
}

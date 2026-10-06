/** /master/empresas — empresas da plataforma (M): criar com administrador, ativar/desativar, excluir. Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Building2, Plus } from 'lucide-react'
import type { Empresa } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Campo, Entrada, ErroCarga, Modal, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { formatarCnpj, limparCnpj, useCriarEmpresaMaster, useEmpresas } from '@/consultas/empresas'
import { formatarData } from '@/lib/formato'
import { normalizar } from '@/lib/formato'
import { useEmpresaAtual } from '@/lib/sessao'

export function PaginaEmpresas() {
  const empresas = useEmpresas()
  const { empresaId, definirEmpresa } = useEmpresaAtual()
  const navegar = useNavigate()
  const [busca, setBusca] = useState('')
  const [nova, setNova] = useState(false)

  const lista = (empresas.data ?? []).filter((e) => !busca || normalizar(e.nome).includes(normalizar(busca)) || (e.cnpj ?? '').includes(busca.replace(/\D/g, '') || '@'))

  const colunas: Coluna<Empresa>[] = [
    {
      id: 'nome',
      titulo: 'Empresa',
      render: (e) => (
        <span className="flex flex-col">
          <span className="font-semibold text-creme">
            {e.nome}
            {e.id === empresaId && <span className="ml-2 text-xs font-normal text-ouro">(selecionada)</span>}
          </span>
          <span className="numero text-xs text-lavanda">{formatarCnpj(e.cnpj)}</span>
        </span>
      ),
    },
    { id: 'cidade', titulo: 'Cidade', ocultarNoCelular: true, render: (e) => <span className="text-sm text-lavanda">{[e.cidade, e.uf].filter(Boolean).join(' / ') || '—'}</span> },
    { id: 'desde', titulo: 'Desde', render: (e) => <span className="numero text-sm text-lavanda">{formatarData(e.criado_em.slice(0, 10))}</span> },
    { id: 'situacao', titulo: 'Situação', render: (e) => (e.ativa ? <Selo tom="sucesso">Ativa</Selo> : <Selo tom="perigo">Inativa</Selo>) },
  ]

  return (
    <div className="surgir">
      <CabecalhoPagina
        sobrancelha="Plataforma"
        titulo={
          <>
            Empre<span className="titulo-italico">sas</span>
          </>
        }
        subtitulo="Todos os estabelecimentos que usam o Meu Dia de Gerente."
        acoes={
          <Botao icone={<Plus aria-hidden />} onClick={() => setNova(true)}>
            Nova empresa
          </Botao>
        }
      />
      <div className="mb-4 max-w-sm">
        <label htmlFor="busca-empresa" className="sr-only">
          Buscar empresa
        </label>
        <Entrada id="busca-empresa" type="search" placeholder="Buscar por nome ou CNPJ" value={busca} onChange={(e) => setBusca(e.target.value)} />
      </div>
      {empresas.isError ? (
        <ErroCarga erro={empresas.error} aoTentar={() => void empresas.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={lista}
          chave={(e) => e.id}
          carregando={empresas.isPending}
          aoClicarLinha={(e) => navegar(`/master/empresas/${e.id}`)}
          vazio={<Vazio icone={<Building2 aria-hidden />} titulo={busca ? 'Nenhuma empresa encontrada' : 'Nenhuma empresa ainda'} />}
        />
      )}
      <Modal aberto={nova} aoFechar={() => setNova(false)} titulo="Nova empresa">
        {nova && (
          <FormularioNovaEmpresa
            aoConcluir={(id) => {
              setNova(false)
              if (id) {
                definirEmpresa(id)
                navegar(`/master/empresas/${id}`)
              }
            }}
          />
        )}
      </Modal>
    </div>
  )
}

function FormularioNovaEmpresa({ aoConcluir }: { aoConcluir(id: string | null): void }) {
  const criar = useCriarEmpresaMaster()
  const avisos = useAvisos()
  const [f, setF] = useState({ nome: '', cnpj: '', adminNome: '', adminEmail: '', adminSenha: '' })
  const [erro, setErro] = useState<string | null>(null)
  const m = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF((a) => ({ ...a, [k]: e.target.value }))

  function enviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!f.nome.trim()) return setErro('Informe o nome')
    const cnpj = limparCnpj(f.cnpj)
    if (cnpj && cnpj.length !== 14) return setErro('O CNPJ deve ter 14 dígitos.')
    if (!f.adminNome.trim()) return setErro('Informe o nome do administrador.')
    if (!/^\S+@\S+\.\S+$/.test(f.adminEmail.trim())) return setErro('E-mail inválido')
    if (f.adminSenha.length < 6) return setErro('A senha deve ter pelo menos 6 caracteres')
    criar.mutate(
      { nome: f.nome.trim(), cnpj, adminEmail: f.adminEmail.trim(), adminSenha: f.adminSenha, adminNome: f.adminNome.trim() },
      {
        onSuccess: (id) => {
          avisos.sucesso('Empresa criada com o administrador.')
          aoConcluir(id)
        },
        onError: avisos.erro,
      },
    )
  }

  return (
    <form onSubmit={enviar} noValidate className="flex flex-col gap-5">
      {erro && (
        <p role="alert" className="rounded-entrada border border-perigo/40 bg-perigo/10 px-4 py-3 text-sm text-creme">
          {erro}
        </p>
      )}
      <p className="sobrancelha">Estabelecimento</p>
      <div className="grid gap-5 sm:grid-cols-2">
        <Campo rotulo="Nome" htmlFor="ne-nome" obrigatorio>
          <Entrada id="ne-nome" value={f.nome} onChange={m('nome')} />
        </Campo>
        <Campo rotulo="CNPJ" htmlFor="ne-cnpj">
          <Entrada id="ne-cnpj" inputMode="numeric" value={f.cnpj} onChange={m('cnpj')} />
        </Campo>
      </div>
      <p className="sobrancelha mt-2">Primeiro administrador</p>
      <div className="grid gap-5 sm:grid-cols-2">
        <Campo rotulo="Nome" htmlFor="ne-anome" obrigatorio>
          <Entrada id="ne-anome" value={f.adminNome} onChange={m('adminNome')} />
        </Campo>
        <Campo rotulo="E-mail" htmlFor="ne-aemail" obrigatorio>
          <Entrada id="ne-aemail" type="email" autoComplete="off" value={f.adminEmail} onChange={m('adminEmail')} />
        </Campo>
        <Campo rotulo="Senha inicial" htmlFor="ne-asenha" obrigatorio ajuda="Pelo menos 6 caracteres.">
          <Entrada id="ne-asenha" type="text" autoComplete="new-password" value={f.adminSenha} onChange={m('adminSenha')} />
        </Campo>
      </div>
      <div className="flex justify-end gap-2 border-t border-borda pt-5">
        <Botao variante="secundario" onClick={() => aoConcluir(null)}>
          Cancelar
        </Botao>
        <Botao type="submit" carregando={criar.isPending}>
          Criar empresa
        </Botao>
      </div>
    </form>
  )
}

/** /comecar — perfil logado sem empresa cria o estabelecimento (`criar_minha_empresa`). Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Botao, Campo, Entrada } from '@/componentes/ui'
import { AlertaAcesso, LayoutAcesso, LINK_SECUNDARIO } from '@/componentes/acesso/LayoutAcesso'
import { TelaCarregandoSessao } from '@/componentes/layout/TelaEstado'
import { limparCnpj } from '@/consultas/empresas'
import { useSessao } from '@/lib/sessao'
import { chamarRpc, mensagemDeErro } from '@/lib/supabase'

export function PaginaComecar() {
  const { sessao, perfil, carregando, recarregar, sair } = useSessao()
  const navegar = useNavigate()
  const [nome, setNome] = useState('')
  const [cnpj, setCnpj] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  if (carregando) return <TelaCarregandoSessao />
  if (!sessao) return <Navigate to="/entrar" replace />
  if (perfil && (perfil.papel === 'master' || perfil.empresa_id)) return <Navigate to="/" replace />

  async function criar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!nome.trim()) return setErro('Informe o nome')
    const c = limparCnpj(cnpj)
    if (c && c.length !== 14) return setErro('O CNPJ deve ter 14 dígitos.')
    setEnviando(true)
    try {
      await chamarRpc('criar_minha_empresa', { p_nome: nome.trim(), p_cnpj: c })
      await recarregar()
      navegar('/', { replace: true })
    } catch (err) {
      setErro(mensagemDeErro(err))
    } finally {
      setEnviando(false)
    }
  }

  const primeiroNome = perfil?.nome.split(' ')[0]

  return (
    <LayoutAcesso
      titulo={primeiroNome ? `Bem-vindo, ${primeiroNome}.` : 'Bem-vindo.'}
      italico="Qual é a sua casa?"
      subtitulo="Cadastre o seu estabelecimento. Você será o administrador e poderá convidar a equipe depois."
      rodape={
        <button type="button" onClick={() => void sair()} className={LINK_SECUNDARIO}>
          Sair
        </button>
      }
    >
      {erro && <AlertaAcesso>{erro}</AlertaAcesso>}
      <form onSubmit={criar} noValidate className="flex flex-col gap-5">
        <Campo rotulo="Nome do estabelecimento" htmlFor="nome-empresa" obrigatorio>
          <Entrada id="nome-empresa" placeholder="Ex.: Bar Bossa Nova" value={nome} onChange={(e) => setNome(e.target.value)} autoFocus />
        </Campo>
        <Campo rotulo="CNPJ" htmlFor="cnpj" ajuda="Opcional. Só números ou com pontuação.">
          <Entrada id="cnpj" inputMode="numeric" placeholder="00.000.000/0000-00" value={cnpj} onChange={(e) => setCnpj(e.target.value)} />
        </Campo>
        <Botao type="submit" tamanho="g" className="mt-1 w-full" carregando={enviando}>
          Criar estabelecimento
        </Botao>
      </form>
    </LayoutAcesso>
  )
}

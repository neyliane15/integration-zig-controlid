/** /redefinir-senha — chega pelo link do e-mail (sessão de recuperação) e grava a senha nova. Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Botao, Campo } from '@/componentes/ui'
import { AlertaAcesso, EntradaSenha, LayoutAcesso, LINK_SECUNDARIO } from '@/componentes/acesso/LayoutAcesso'
import { useAvisos } from '@/componentes/avisos'
import { useSessao } from '@/lib/sessao'
import { mensagemDeErro, supabase } from '@/lib/supabase'

export function PaginaRedefinirSenha() {
  const { sessao, carregando } = useSessao()
  const avisos = useAvisos()
  const navegar = useNavigate()
  const [senha, setSenha] = useState('')
  const [confirmacao, setConfirmacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function salvar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (senha.length < 6) return setErro('A senha deve ter pelo menos 6 caracteres')
    if (senha !== confirmacao) return setErro('As senhas não conferem.')
    setEnviando(true)
    const { error } = await supabase.auth.updateUser({ password: senha })
    setEnviando(false)
    if (error) return setErro(mensagemDeErro(error))
    avisos.sucesso('Senha alterada.')
    navegar('/', { replace: true })
  }

  const semSessao = !carregando && !sessao

  return (
    <LayoutAcesso
      titulo="Crie uma senha"
      italico="nova."
      subtitulo="Use pelo menos 6 caracteres. Depois é só entrar normalmente."
      rodape={
        <Link to="/entrar" className={LINK_SECUNDARIO}>
          Voltar para entrar
        </Link>
      }
    >
      {semSessao ? (
        <AlertaAcesso>
          Este link expirou ou já foi usado.{' '}
          <Link to="/recuperar-senha" className="font-bold text-ouro underline">
            Peça um novo
          </Link>
          .
        </AlertaAcesso>
      ) : (
        <>
          {erro && <AlertaAcesso>{erro}</AlertaAcesso>}
          <form onSubmit={salvar} noValidate className="flex flex-col gap-5">
            <Campo rotulo="Nova senha" htmlFor="senha">
              <EntradaSenha id="senha" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} autoFocus />
            </Campo>
            <Campo rotulo="Repita a senha" htmlFor="confirmacao">
              <EntradaSenha
                id="confirmacao"
                autoComplete="new-password"
                value={confirmacao}
                onChange={(e) => setConfirmacao(e.target.value)}
              />
            </Campo>
            <Botao type="submit" tamanho="g" className="w-full" carregando={enviando || carregando}>
              Salvar senha
            </Botao>
          </form>
        </>
      )}
    </LayoutAcesso>
  )
}

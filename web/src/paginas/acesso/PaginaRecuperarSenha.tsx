/** /recuperar-senha — envia o link de redefinição por e-mail. Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { Botao, Campo, Entrada } from '@/componentes/ui'
import { AlertaAcesso, LayoutAcesso, LINK_OURO, LINK_SECUNDARIO } from '@/componentes/acesso/LayoutAcesso'
import { configuracaoAusente, mensagemDeErro, supabase } from '@/lib/supabase'

export function PaginaRecuperarSenha() {
  const [email, setEmail] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [enviado, setEnviado] = useState(false)

  async function enviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) {
      setErro('Informe um e-mail válido.')
      return
    }
    setEnviando(true)
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/redefinir-senha`,
    })
    setEnviando(false)
    if (error) setErro(mensagemDeErro(error))
    else setEnviado(true)
  }

  return (
    <LayoutAcesso
      titulo="Esqueceu a senha?"
      italico="A gente resolve."
      subtitulo="Informe seu e-mail e enviaremos um link para criar uma senha nova."
      rodape={
        <>
          <Link to="/entrar" className={LINK_SECUNDARIO}>
            Voltar para entrar
          </Link>
          <Link to="/criar-conta" className={LINK_OURO}>
            Criar conta
          </Link>
        </>
      }
    >
      {erro && <AlertaAcesso>{erro}</AlertaAcesso>}
      {enviado ? (
        <AlertaAcesso tom="sucesso">
          Pronto! Se <strong>{email.trim()}</strong> tiver cadastro, o link chega em instantes. Confira também a caixa de spam.
        </AlertaAcesso>
      ) : (
        <form onSubmit={enviar} noValidate className="flex flex-col gap-5">
          <Campo rotulo="E-mail" htmlFor="email">
            <Entrada
              id="email"
              type="email"
              autoComplete="email"
              inputMode="email"
              placeholder="voce@seubar.com.br"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
            />
          </Campo>
          <Botao type="submit" tamanho="g" className="w-full" carregando={enviando} disabled={configuracaoAusente}>
            Enviar link
          </Botao>
        </form>
      )}
    </LayoutAcesso>
  )
}

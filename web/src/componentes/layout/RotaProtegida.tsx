/**
 * Guardas de rota (contrato §14.2). Dono: frontend-1.
 * - sem sessão → /entrar (lembrando para onde ia)
 * - perfil sem empresa (não master) → /comecar
 * - perfil ou empresa inativos → "Acesso desativado"
 */
import type { ReactNode } from 'react'
import { Link, Navigate, useLocation } from 'react-router-dom'
import { LogOut, RotateCcw, ShieldAlert } from 'lucide-react'
import type { Papel } from '@/tipos/banco'
import { useSessao } from '@/lib/sessao'
import { configuracaoAusente, mensagemDeErro } from '@/lib/supabase'
import { Botao, Vazio } from '../ui'
import { TelaCarregandoSessao, TelaEstado } from './TelaEstado'

export function RotaProtegida({ children }: { children: ReactNode }) {
  const { carregando, sessao, perfil, empresa, erroPerfil, sair, recarregar } = useSessao()
  const local = useLocation()

  if (configuracaoAusente) return <Navigate to="/entrar" replace />
  if (carregando) return <TelaCarregandoSessao />
  if (!sessao) return <Navigate to="/entrar" replace state={{ de: local.pathname + local.search }} />

  if (erroPerfil)
    return (
      <TelaEstado
        titulo="Não conseguimos"
        italico="abrir seu perfil."
        acoes={
          <>
            <Botao tamanho="g" onClick={() => void recarregar()} icone={<RotateCcw aria-hidden />}>
              Tentar de novo
            </Botao>
            <Botao tamanho="g" variante="secundario" onClick={() => void sair()} icone={<LogOut aria-hidden />}>
              Sair
            </Botao>
          </>
        }
      >
        {mensagemDeErro(erroPerfil)}
      </TelaEstado>
    )

  if (!perfil || !perfil.ativo)
    return <AcessoDesativado motivo={!perfil ? 'Seu perfil ainda não foi criado.' : 'Seu usuário foi desativado.'} />

  if (perfil.papel !== 'master') {
    if (!perfil.empresa_id) return <Navigate to="/comecar" replace />
    if (!empresa || !empresa.ativa) return <AcessoDesativado motivo="O acesso deste estabelecimento está desativado." />
  }

  return <>{children}</>
}

function AcessoDesativado({ motivo }: { motivo: string }) {
  const { sair, perfil } = useSessao()
  return (
    <TelaEstado
      titulo="Acesso"
      italico="desativado."
      acoes={
        <Botao tamanho="g" variante="secundario" onClick={() => void sair()} icone={<LogOut aria-hidden />}>
          Sair{perfil ? ` de ${perfil.email}` : ''}
        </Botao>
      }
    >
      {motivo} Fale com o administrador do seu estabelecimento para reativar.
    </TelaEstado>
  )
}

/** Mostra o conteúdo só se a regra de papel permitir; senão, aviso dentro da casca. */
export function SoPara({ permitir, children }: { permitir(p: Papel): boolean; children: ReactNode }) {
  const { perfil } = useSessao()
  if (perfil && permitir(perfil.papel)) return <>{children}</>
  return (
    <div className="mx-auto max-w-xl pt-10">
      <Vazio
        principal
        icone={<ShieldAlert aria-hidden />}
        titulo="Sem permissão"
        descricao="Seu papel não dá acesso a esta área. Se precisar, peça ao administrador."
        acao={
          <Link to="/" className="text-sm font-semibold text-ouro underline-offset-4 hover:underline">
            Voltar ao painel
          </Link>
        }
      />
    </div>
  )
}

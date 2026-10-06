/** /usuarios — usuários da empresa (A M). Dono: frontend-1. */
import { CabecalhoPagina, Carregando } from '@/componentes/ui'
import { useEmpresaAtual } from '@/lib/sessao'
import { UsuariosDaEmpresa } from './UsuariosDaEmpresa'

export function PaginaUsuarios() {
  const { empresaId, empresa } = useEmpresaAtual()
  return (
    <div className="surgir">
      <CabecalhoPagina
        sobrancelha="Ajustes"
        titulo={
          <>
            Usuá<span className="titulo-italico">rios</span>
          </>
        }
        subtitulo={`Quem acessa ${empresa?.nome ?? 'a empresa'} e o que cada um pode fazer.`}
      />
      {empresaId ? <UsuariosDaEmpresa empresaId={empresaId} /> : <Carregando />}
    </div>
  )
}

/** * — página não encontrada. Dono: frontend-1. */
import { Link } from 'react-router-dom'
import { Compass } from 'lucide-react'
import { Vazio } from '@/componentes/ui'

export function PaginaNaoEncontrada() {
  return (
    <div className="mx-auto max-w-lg pt-10">
      <p className="sobrancelha mb-3 text-center">Erro 404</p>
      <Vazio
        principal
        icone={<Compass aria-hidden />}
        titulo="Página não encontrada"
        descricao="O endereço pode ter mudado ou não existir mais."
        acao={
          <Link to="/" className="inline-flex h-11 items-center rounded-entrada bg-ouro px-5 text-sm font-bold text-tinta-ouro hover:bg-ouro-claro">
            Voltar ao painel
          </Link>
        }
      />
    </div>
  )
}

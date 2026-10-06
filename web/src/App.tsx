/**
 * Rotas do app (contrato §14.3). Dono: frontend-1.
 * Páginas são named exports sem props, carregadas com React.lazy.
 */
import { lazy, Suspense, type ReactNode } from 'react'
import { Route, Routes } from 'react-router-dom'
import type { Papel } from '@/tipos/banco'
import { ehMaster, podeAdministrar, podeOperar, podeVerComissoes } from '@/lib/permissoes'
import { Casca } from '@/componentes/layout/Casca'
import { RotaProtegida, SoPara } from '@/componentes/layout/RotaProtegida'
import { TelaCarregandoSessao } from '@/componentes/layout/TelaEstado'

// ---------------------------------------------------------------- acesso (f1)
const PaginaEntrar = lazy(() => import('./paginas/acesso/PaginaEntrar').then((m) => ({ default: m.PaginaEntrar })))
const PaginaRecuperarSenha = lazy(() =>
  import('./paginas/acesso/PaginaRecuperarSenha').then((m) => ({ default: m.PaginaRecuperarSenha })),
)
const PaginaRedefinirSenha = lazy(() =>
  import('./paginas/acesso/PaginaRedefinirSenha').then((m) => ({ default: m.PaginaRedefinirSenha })),
)
const PaginaCriarConta = lazy(() => import('./paginas/acesso/PaginaCriarConta').then((m) => ({ default: m.PaginaCriarConta })))
const PaginaComecar = lazy(() => import('./paginas/acesso/PaginaComecar').then((m) => ({ default: m.PaginaComecar })))

// ------------------------------------------------------------------ app (f1)
const PaginaPainel = lazy(() => import('./paginas/painel/PaginaPainel').then((m) => ({ default: m.PaginaPainel })))
const PaginaIntegracoes = lazy(() =>
  import('./paginas/integracoes/PaginaIntegracoes').then((m) => ({ default: m.PaginaIntegracoes })),
)
const PaginaIntegracao = lazy(() => import('./paginas/integracoes/PaginaIntegracao').then((m) => ({ default: m.PaginaIntegracao })))
const PaginaConfiguracoes = lazy(() =>
  import('./paginas/configuracoes/PaginaConfiguracoes').then((m) => ({ default: m.PaginaConfiguracoes })),
)
const PaginaUsuarios = lazy(() => import('./paginas/configuracoes/PaginaUsuarios').then((m) => ({ default: m.PaginaUsuarios })))
const PaginaEmpresas = lazy(() => import('./paginas/master/PaginaEmpresas').then((m) => ({ default: m.PaginaEmpresas })))
const PaginaEmpresa = lazy(() => import('./paginas/master/PaginaEmpresa').then((m) => ({ default: m.PaginaEmpresa })))
const PaginaNaoEncontrada = lazy(() => import('./paginas/PaginaNaoEncontrada').then((m) => ({ default: m.PaginaNaoEncontrada })))

// ----------------------------------------------------------------- operação (f2)
const PaginaFuncionarios = lazy(() =>
  import('./paginas/funcionarios/PaginaFuncionarios').then((m) => ({ default: m.PaginaFuncionarios })),
)
const PaginaFuncionario = lazy(() => import('./paginas/funcionarios/PaginaFuncionario').then((m) => ({ default: m.PaginaFuncionario })))
const PaginaJornadas = lazy(() => import('./paginas/funcionarios/PaginaJornadas').then((m) => ({ default: m.PaginaJornadas })))
const PaginaPontoDia = lazy(() => import('./paginas/ponto/PaginaPontoDia').then((m) => ({ default: m.PaginaPontoDia })))
const PaginaEspelho = lazy(() => import('./paginas/ponto/PaginaEspelho').then((m) => ({ default: m.PaginaEspelho })))
const PaginaAlarmes = lazy(() => import('./paginas/ponto/PaginaAlarmes').then((m) => ({ default: m.PaginaAlarmes })))
const PaginaBancoHoras = lazy(() => import('./paginas/banco-horas/PaginaBancoHoras').then((m) => ({ default: m.PaginaBancoHoras })))
const PaginaExtratoBancoHoras = lazy(() =>
  import('./paginas/banco-horas/PaginaExtratoBancoHoras').then((m) => ({ default: m.PaginaExtratoBancoHoras })),
)
const PaginaVendas = lazy(() => import('./paginas/vendas/PaginaVendas').then((m) => ({ default: m.PaginaVendas })))
const PaginaComissoes = lazy(() => import('./paginas/comissoes/PaginaComissoes').then((m) => ({ default: m.PaginaComissoes })))
const PaginaFechamento = lazy(() => import('./paginas/comissoes/PaginaFechamento').then((m) => ({ default: m.PaginaFechamento })))
const PaginaTarefas = lazy(() => import('./paginas/tarefas/PaginaTarefas').then((m) => ({ default: m.PaginaTarefas })))
const PaginaRotinas = lazy(() => import('./paginas/tarefas/PaginaRotinas').then((m) => ({ default: m.PaginaRotinas })))

function So({ permitir, children }: { permitir(p: Papel): boolean; children: ReactNode }) {
  return <SoPara permitir={permitir}>{children}</SoPara>
}

export function App() {
  return (
    <Suspense fallback={<TelaCarregandoSessao />}>
      <Routes>
        {/* públicas */}
        <Route path="/entrar" element={<PaginaEntrar />} />
        <Route path="/recuperar-senha" element={<PaginaRecuperarSenha />} />
        <Route path="/redefinir-senha" element={<PaginaRedefinirSenha />} />
        <Route path="/criar-conta" element={<PaginaCriarConta />} />
        <Route path="/comecar" element={<PaginaComecar />} />

        {/* protegidas, dentro da casca */}
        <Route
          element={
            <RotaProtegida>
              <Casca />
            </RotaProtegida>
          }
        >
          <Route index element={<PaginaPainel />} />

          <Route path="/funcionarios" element={<PaginaFuncionarios />} />
          <Route path="/funcionarios/jornadas" element={<PaginaJornadas />} />
          <Route path="/funcionarios/novo" element={<PaginaFuncionario />} />
          <Route path="/funcionarios/:id" element={<PaginaFuncionario />} />

          <Route path="/ponto" element={<PaginaPontoDia />} />
          <Route path="/ponto/funcionario/:id" element={<PaginaEspelho />} />
          <Route path="/ponto/alarmes" element={<PaginaAlarmes />} />

          <Route path="/banco-de-horas" element={<PaginaBancoHoras />} />
          <Route path="/banco-de-horas/:id" element={<PaginaExtratoBancoHoras />} />

          <Route path="/vendas" element={<PaginaVendas />} />

          <Route path="/comissoes" element={<So permitir={podeVerComissoes}><PaginaComissoes /></So>} />
          <Route path="/comissoes/:id" element={<So permitir={podeVerComissoes}><PaginaFechamento /></So>} />

          <Route path="/tarefas" element={<PaginaTarefas />} />
          <Route path="/tarefas/rotinas" element={<So permitir={podeOperar}><PaginaRotinas /></So>} />

          <Route path="/integracoes" element={<So permitir={podeOperar}><PaginaIntegracoes /></So>} />
          <Route path="/integracoes/:id" element={<So permitir={podeOperar}><PaginaIntegracao /></So>} />

          <Route path="/configuracoes" element={<So permitir={podeOperar}><PaginaConfiguracoes /></So>} />
          <Route path="/usuarios" element={<So permitir={podeAdministrar}><PaginaUsuarios /></So>} />

          <Route path="/master/empresas" element={<So permitir={ehMaster}><PaginaEmpresas /></So>} />
          <Route path="/master/empresas/:id" element={<So permitir={ehMaster}><PaginaEmpresa /></So>} />

          <Route path="*" element={<PaginaNaoEncontrada />} />
        </Route>
      </Routes>
    </Suspense>
  )
}

/**
 * /escala (`?aba=geral|mes|equipe|s-<setorId>&mes=AAAA-MM`) — escala rotativa 5x2 (adendo escala v2), réplica do modelo do
 * cliente (docs/referencias/escala-macaw-v3.html) com os funcionários cadastrados. L G A M veem; G A M editam.
 * Não depende de ponto nem de integração (§S.6).
 */
import { useState } from "react";
import { useSearchParams } from "react-router-dom";
import { CalendarRange, LayoutTemplate, Plus } from "lucide-react";
import {
  Abas,
  Botao,
  CabecalhoPagina,
  Campo,
  Carregando,
  Entrada,
  ErroCarga,
  Modal,
  Vazio,
} from "@/componentes/ui";
import { useAvisos } from "@/componentes/avisos";
import { useContextoEmpresa } from "@/consultas/funcionarios";
import {
  useAplicarModeloMacaw,
  useEscalaSemana,
  useSalvarSetor,
} from "@/consultas/escala";
import { usePerfil } from "@/lib/sessao";
import { podeOperar } from "@/lib/permissoes";
import { AbaGeral, AbaSetor } from "./AbaSemana";
import { AbaEquipe } from "./AbaEquipe";
import { AbaMes } from "./AbaMes";

export function PaginaEscala() {
  const { hoje } = useContextoEmpresa();
  const perfil = usePerfil();
  const editar = podeOperar(perfil.papel);
  const [params, setParams] = useSearchParams();
  const semana = useEscalaSemana(hoje);
  const mes = /^\d{4}-\d{2}$/.test(params.get("mes") ?? "")
    ? params.get("mes")!
    : hoje.slice(0, 7);

  const mudar = (novo: Record<string, string | null>) => {
    const p = new URLSearchParams(params);
    for (const [k, v] of Object.entries(novo)) {
      if (v == null) p.delete(k);
      else p.set(k, v);
    }
    setParams(p, { replace: true });
  };

  const setores = semana.data?.setores ?? [];
  const ids = ["geral", ...setores.map((s) => `s-${s.id}`), "equipe", "mes"];
  const pedida = params.get("aba") ?? "geral";
  const aba = ids.includes(pedida) ? pedida : "geral";
  const vazia = !!semana.data && setores.length === 0;

  return (
    <div className="mx-auto w-full max-w-7xl min-w-0">
      <CabecalhoPagina
        sobrancelha="Equipe"
        titulo={
          <>
            Escala <span className="titulo-italico">5x2 do mês</span>
          </>
        }
        subtitulo="Folgas por setor com rodízio semanal automático. Clique na escala do mês para ajustar um dia."
      />
      {semana.isLoading ? (
        <Carregando texto="Carregando a escala…" />
      ) : semana.error ? (
        <ErroCarga erro={semana.error} aoTentar={() => void semana.refetch()} />
      ) : vazia ? (
        <EscalaVazia
          editar={editar}
          aoMontar={() => mudar({ aba: "equipe" })}
        />
      ) : (
        <>
          <Abas<string>
            abas={[
              { id: "geral", rotulo: "Geral" },
              ...setores.map((s) => ({ id: `s-${s.id}`, rotulo: s.nome })),
              {
                id: "equipe",
                rotulo: editar ? "Equipe e configuração" : "Equipe",
              },
              { id: "mes", rotulo: "Escala do mês" },
            ]}
            ativa={aba}
            aoMudar={(a) => mudar({ aba: a })}
          />
          <div className="mt-5 min-w-0">
            {aba === "geral" && semana.data && (
              <AbaGeral
                semana={semana.data}
                aoAbrirSetor={(id) => mudar({ aba: `s-${id}` })}
              />
            )}
            {aba.startsWith("s-") && semana.data && (
              <AbaSetor
                key={aba}
                semana={semana.data}
                setorId={aba.slice(2)}
                hoje={hoje}
              />
            )}
            {aba === "equipe" && semana.data && (
              <AbaEquipe semana={semana.data} editar={editar} hoje={hoje} />
            )}
            {aba === "mes" && (
              <AbaMes mes={mes} aoMudarMes={(m) => mudar({ mes: m })} />
            )}
          </div>
        </>
      )}
    </div>
  );
}

/** Empresa sem setores: montar pelo modelo Macaw (33 posições) ou do zero. */
function EscalaVazia({
  editar,
  aoMontar,
}: {
  editar: boolean;
  aoMontar(): void;
}) {
  const avisos = useAvisos();
  const aplicar = useAplicarModeloMacaw();
  const salvarSetor = useSalvarSetor();
  const [zero, setZero] = useState(false);
  const [nome, setNome] = useState("Salão");

  async function montarModelo() {
    const ok = await avisos.confirmar({
      titulo: "Montar a escala a partir do modelo Macaw?",
      mensagem: (
        <>
          Cria os setores Salão, Maître, Areia, Bar, ASG e Cozinha com as 33
          posições, caminhos e folgas do modelo. Funcionários já cadastrados com
          o mesmo nome da posição (ex.: “Garçom 1”) são aproveitados; para as
          demais posições são criados funcionários provisórios (sem ponto e com
          0 ponto de comissão) que você pode renomear na aba Equipe.
        </>
      ),
      textoConfirmar: "Montar escala",
    });
    if (!ok) return;
    try {
      const r = await aplicar.mutateAsync({ ancora: null });
      avisos.sucesso(
        `Escala montada: ${r.setores} setor(es), ${r.membros} posição(ões) e ${r.funcionarios_criados} funcionário(s) provisório(s).`,
      );
      aoMontar();
    } catch (e) {
      avisos.erro(e);
    }
  }

  async function criarSetor() {
    try {
      await salvarSetor.mutateAsync({ nome: nome.trim() });
      avisos.sucesso("Setor criado. Agora adicione as pessoas e as folgas.");
      setZero(false);
      aoMontar();
    } catch (e) {
      avisos.erro(e);
    }
  }

  return (
    <>
      <Vazio
        icone={<CalendarRange aria-hidden />}
        titulo="A escala ainda não foi montada"
        descricao={
          editar
            ? "Monte a escala a partir do modelo da casa (6 setores, rodízio 5x2) ou comece do zero com os seus setores. Não precisa de ponto nem de integração."
            : "Peça ao gerente ou administrador para montar a escala da equipe."
        }
        acao={
          editar && (
            <div className="flex flex-wrap justify-center gap-2">
              <Botao
                icone={<LayoutTemplate aria-hidden />}
                carregando={aplicar.isPending}
                onClick={() => void montarModelo()}
              >
                Montar escala a partir do modelo Macaw
              </Botao>
              <Botao
                variante="secundario"
                icone={<Plus aria-hidden />}
                onClick={() => setZero(true)}
              >
                Montar do zero
              </Botao>
            </div>
          )
        }
      />
      <Modal
        aberto={zero}
        aoFechar={() => setZero(false)}
        titulo="Primeiro setor"
        largura="p"
        rodape={
          <>
            <Botao variante="fantasma" onClick={() => setZero(false)}>
              Cancelar
            </Botao>
            <Botao
              carregando={salvarSetor.isPending}
              disabled={!nome.trim()}
              onClick={() => void criarSetor()}
            >
              Criar setor
            </Botao>
          </>
        }
      >
        <Campo
          rotulo="Nome do setor"
          htmlFor="escala-primeiro-setor"
          ajuda="Ex.: Salão, Bar, Cozinha. Você pode criar outros depois."
        >
          <Entrada
            id="escala-primeiro-setor"
            value={nome}
            maxLength={40}
            onChange={(e) => setNome(e.target.value)}
          />
        </Campo>
      </Modal>
    </>
  );
}

/**
 * Escala rotativa (adendo escala v2): leituras `escala_mes` / `escala_semana` e escritas por RPC.
 * O ajuste de um dia (`escala_ajustar`) é otimista: a célula muda na hora e volta se o banco recusar.
 */
import {
  useMutation,
  useQuery,
  useQueryClient,
  type QueryClient,
} from "@tanstack/react-query";
import type {
  EscalaDiaFuncionario,
  EscalaMembroEntrada,
  EscalaMes,
  StatusAjusteEscala,
} from "@/tipos/banco";
import { chamarRpc } from "@/lib/supabase";
import { chaves, invalidar, invalidarPonto } from "@/lib/consultas";
import { useEmpresaAtual } from "@/lib/sessao";
import { statusAutomatico } from "@/lib/escala";

const num = (v: unknown) => Number(v) || 0;
const hhmm = (v: string | null | undefined) => (v ? v.slice(0, 5) : null);

function normalizarMes(m: EscalaMes): EscalaMes {
  return {
    ...m,
    fase: m.fase == null ? null : num(m.fase),
    dias: (m.dias ?? []).map((d) => ({
      ...d,
      dia_semana: num(d.dia_semana),
      semana: d.semana == null ? null : num(d.semana),
    })),
    na_escala: (m.na_escala ?? []).map(num),
    setores: (m.setores ?? []).map((s) => ({
      ...s,
      fase: num(s.fase),
      caminhos: (s.caminhos ?? []).map((c) => ({
        caminho: num(c.caminho),
        funcionarios: c.funcionarios ?? [],
      })),
      na_escala: (s.na_escala ?? []).map(num),
      membros: (s.membros ?? []).map((x) => ({
        ...x,
        chegada_padrao: hhmm(x.chegada_padrao),
        folgas_base: (x.folgas_base ?? []).map(num),
        caminho: x.caminho == null ? null : num(x.caminho),
        posicao: x.posicao == null ? null : num(x.posicao),
        trabalha: num(x.trabalha),
        folgas: num(x.folgas),
        ferias: num(x.ferias),
        faltas: num(x.faltas),
        dias: (x.dias ?? []).map((d) => ({ ...d, chegada: hhmm(d.chegada), falta: d.falta ?? null })),
      })),
    })),
  };
}

export function useEscalaMes(anoMes: string) {
  const { empresaId } = useEmpresaAtual();
  return useQuery({
    queryKey: chaves.escalaMes(empresaId, anoMes),
    enabled: !!empresaId && /^\d{4}-\d{2}$/.test(anoMes),
    queryFn: async () =>
      normalizarMes(
        await chamarRpc("escala_mes", {
          p_ano_mes: anoMes,
          p_empresa: empresaId,
        }),
      ),
  });
}

export function useEscalaSemana(data: string | null) {
  const { empresaId } = useEmpresaAtual();
  return useQuery({
    queryKey: chaves.escalaSemana(empresaId, data),
    enabled: !!empresaId,
    queryFn: async () => {
      const s = await chamarRpc("escala_semana", {
        p_data: data,
        p_empresa: empresaId,
      });
      return {
        ...s,
        semana: s.semana == null ? null : num(s.semana),
        na_escala_base: (s.na_escala_base ?? []).map(num),
        na_escala_semana: (s.na_escala_semana ?? []).map(num),
        setores: (s.setores ?? []).map((x) => ({
          ...x,
          total: num(x.total),
          fase: num(x.fase),
          caminhos: (x.caminhos ?? []).map((c) => ({
            ...c,
            caminho: num(c.caminho),
          })),
          na_escala_base: (x.na_escala_base ?? []).map(num),
          na_escala_semana: (x.na_escala_semana ?? []).map(num),
          membros: (x.membros ?? []).map((m) => ({
            ...m,
            chegada_padrao: hhmm(m.chegada_padrao),
            folgas_base: (m.folgas_base ?? []).map(num),
            folgas_semana: (m.folgas_semana ?? []).map(num),
            caminho: m.caminho == null ? null : num(m.caminho),
            posicao: m.posicao == null ? null : num(m.posicao),
          })),
        })),
      };
    },
  });
}

// ------------------------------------------------------------------ recontagem local (otimista)

/** Recalcula contagens (por membro, `na_escala` do setor e total) depois de mexer em células. */
export function recontar(m: EscalaMes): EscalaMes {
  const total = m.dias.map(() => 0);
  const setores = m.setores.map((s) => {
    const na = m.dias.map(() => 0);
    const membros = s.membros.map((x) => {
      let trabalha = 0;
      let folgas = 0;
      let ferias = 0;
      let faltas = 0;
      x.dias.forEach((d, j) => {
        if (d.falta) faltas++;
        if (d.status === "trabalha") {
          trabalha++;
          na[j]!++;
          total[j]!++;
        } else if (d.status === "folga") folgas++;
        else if (d.status === "ferias") ferias++;
      });
      return { ...x, trabalha, folgas, ferias, faltas };
    });
    return { ...s, membros, na_escala: na };
  });
  return { ...m, setores, na_escala: total };
}

/** Aplica o novo estado de um dia no cache (sem ir ao banco). */
export function aplicarDia(
  m: EscalaMes,
  funcionarioId: string,
  data: string,
  novo: { status: StatusAjusteEscala | null; chegada: string | null },
): EscalaMes {
  const j = m.dias.findIndex((d) => d.data === data);
  if (j < 0) return m;
  const info = m.dias[j]!;
  const setores = m.setores.map((s) => {
    if (!s.membros.some((x) => x.funcionario_id === funcionarioId)) return s;
    return {
      ...s,
      membros: s.membros.map((x) => {
        if (x.funcionario_id !== funcionarioId) return x;
        const dias = x.dias.slice();
        const atual = dias[j]!;
        if (atual.status === "fora") return x;
        const auto =
          info.semana == null
            ? "trabalha"
            : statusAutomatico(
                funcionarioId,
                info.semana,
                info.dia_semana,
                s,
                m.fase ?? 0,
              );
        const status = novo.status ?? auto;
        dias[j] = {
          ...atual,
          status,
          origem: novo.status ? "ajuste" : "auto",
          chegada:
            status === "trabalha" ? (novo.chegada ?? x.chegada_padrao) : null,
          ajustado: !!(novo.status || novo.chegada),
        };
        return { ...x, dias };
      }),
    };
  });
  return recontar({ ...m, setores });
}

/** Grava no cache o objeto-dia devolvido pelo banco. */
function gravarDias(m: EscalaMes, itens: EscalaDiaFuncionario[]): EscalaMes {
  let mudou = false;
  const setores = m.setores.map((s) => ({
    ...s,
    membros: s.membros.map((x) => {
      const meus = itens.filter((i) => i.funcionario_id === x.funcionario_id);
      if (!meus.length) return x;
      return {
        ...x,
        dias: x.dias.map((d) => {
          const i = meus.find((y) => y.data === d.data);
          if (!i) return d;
          mudou = true;
          return {
            data: d.data,
            status: i.status,
            origem: i.origem,
            chegada: hhmm(i.chegada),
            ajustado: i.ajustado,
            motivo: i.motivo,
            falta: "falta" in i ? (i.falta ?? null) : (d.falta ?? null),
          };
        }),
      };
    }),
  }));
  return mudou ? recontar({ ...m, setores }) : m;
}

const CHAVE_AJUSTE = ["escala-ajustar"] as const;

function aoTerminarAjuste(qc: QueryClient) {
  // só recarrega quando a última edição em andamento terminar (senão uma resposta velha apagaria a célula digitada)
  if (qc.isMutating({ mutationKey: CHAVE_AJUSTE }) <= 1) {
    void invalidar(qc, "escala-mes");
    void invalidarPonto(qc);
  }
}

export interface ArgsAjuste {
  anoMes: string;
  funcionarioId: string;
  data: string;
  /** null = automático */
  status: StatusAjusteEscala | null;
  /** 'HH:MM' ou null = padrão */
  chegada: string | null;
  motivo?: string | null;
}

/** Ajusta um dia (otimista). */
export function useAjustarDia() {
  const qc = useQueryClient();
  const { empresaId } = useEmpresaAtual();
  return useMutation({
    mutationKey: CHAVE_AJUSTE,
    mutationFn: (a: ArgsAjuste) =>
      chamarRpc("escala_ajustar", {
        p_funcionario: a.funcionarioId,
        p_data: a.data,
        p_status: a.status,
        p_chegada: a.chegada,
        p_motivo: a.motivo ?? null,
      }),
    onMutate: async (a) => {
      const chave = chaves.escalaMes(empresaId, a.anoMes);
      await qc.cancelQueries({ queryKey: chave });
      const antes = qc.getQueryData<EscalaMes>(chave);
      if (antes)
        qc.setQueryData(
          chave,
          aplicarDia(antes, a.funcionarioId, a.data, {
            status: a.status,
            chegada: a.chegada,
          }),
        );
      return { chave, antes };
    },
    onError: (_e, _a, ctx) => {
      if (ctx?.antes) qc.setQueryData(ctx.chave, ctx.antes);
    },
    onSuccess: (dia, _a, ctx) => {
      const atual = ctx ? qc.getQueryData<EscalaMes>(ctx.chave) : undefined;
      if (ctx && atual && dia)
        qc.setQueryData(ctx.chave, gravarDias(atual, [dia]));
    },
    onSettled: () => aoTerminarAjuste(qc),
  });
}

function useMutacaoEscala<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: async () => {
      await invalidar(
        qc,
        "escala-mes",
        "escala-semana",
        "funcionarios",
        "funcionario",
      );
      void invalidarPonto(qc);
    },
  });
}

export function useAjustarPeriodo() {
  return useMutacaoEscala(
    (a: {
      funcionarioId: string;
      inicio: string;
      fim: string;
      status: StatusAjusteEscala | null;
      motivo?: string | null;
    }) =>
      chamarRpc("escala_ajustar_periodo", {
        p_funcionario: a.funcionarioId,
        p_inicio: a.inicio,
        p_fim: a.fim,
        p_status: a.status,
        p_motivo: a.motivo ?? null,
      }),
  );
}

export function useTrocarFolga() {
  return useMutacaoEscala(
    (a: {
      funcionarioA: string;
      dataA: string;
      funcionarioB: string | null;
      dataB: string | null;
      motivo?: string | null;
    }) =>
      chamarRpc("escala_trocar", {
        p_funcionario_a: a.funcionarioA,
        p_data_a: a.dataA,
        p_funcionario_b: a.funcionarioB,
        p_data_b: a.dataB,
        p_motivo: a.motivo ?? null,
      }),
  );
}

export function useConfigurarEscala() {
  const { empresaId } = useEmpresaAtual();
  return useMutacaoEscala((a: { ancora: string; fase: number }) =>
    chamarRpc("escala_configurar", {
      p_ancora: a.ancora,
      p_fase: a.fase,
      p_empresa: empresaId,
    }),
  );
}

export function useAplicarModeloMacaw() {
  const { empresaId } = useEmpresaAtual();
  return useMutacaoEscala((a: { ancora: string | null }) =>
    chamarRpc("escala_aplicar_modelo_macaw", {
      p_empresa: empresaId,
      p_ancora: a.ancora,
    }),
  );
}

export function useSalvarSetor() {
  const { empresaId } = useEmpresaAtual();
  return useMutacaoEscala(
    (a: {
      id?: string | null;
      nome: string;
      ordem?: number | null;
      fase?: number;
    }) =>
      chamarRpc("escala_salvar_setor", {
        p_nome: a.nome,
        p_ordem: a.ordem ?? null,
        p_fase: a.fase ?? 0,
        p_setor: a.id ?? null,
        p_empresa: empresaId,
      }),
  );
}

export function useExcluirSetor() {
  return useMutacaoEscala((setorId: string) =>
    chamarRpc("escala_excluir_setor", { p_setor: setorId }),
  );
}

export interface DadosMembro {
  folgasBase: number[];
  chegadaPadrao: string | null;
  caminho: number | null;
  posicao: number | null;
}

export function useSalvarMembro() {
  return useMutacaoEscala(
    (a: {
      setorId: string;
      funcionarioId: string;
      dados: DadosMembro;
      ordem?: number | null;
    }) =>
      chamarRpc("escala_salvar_membro", {
        p_setor: a.setorId,
        p_funcionario: a.funcionarioId,
        p_folgas_base: [...a.dados.folgasBase].sort((x, y) => x - y),
        p_chegada_padrao: a.dados.chegadaPadrao,
        p_caminho: a.dados.caminho,
        p_posicao: a.dados.caminho == null ? null : a.dados.posicao,
        p_ordem: a.ordem ?? null,
      }),
  );
}

export function useDefinirMembros() {
  return useMutacaoEscala(
    (a: { setorId: string; membros: EscalaMembroEntrada[] }) =>
      chamarRpc("escala_definir_membros", {
        p_setor: a.setorId,
        p_membros: a.membros,
      }),
  );
}

export function useRemoverMembro() {
  return useMutacaoEscala((funcionarioId: string) =>
    chamarRpc("escala_remover_membro", { p_funcionario: funcionarioId }),
  );
}

export function useAdicionarFuncionarioEscala() {
  return useMutacaoEscala(
    (a: {
      setorId: string;
      nome: string;
      cargo: string | null;
      dados: DadosMembro;
    }) =>
      chamarRpc("escala_adicionar_funcionario", {
        p_setor: a.setorId,
        p_nome: a.nome.trim(),
        p_cargo: a.cargo?.trim() || null,
        p_folgas_base: [...a.dados.folgasBase].sort((x, y) => x - y),
        p_chegada_padrao: a.dados.chegadaPadrao,
        p_caminho: a.dados.caminho,
        p_posicao: a.dados.caminho == null ? null : a.dados.posicao,
      }),
  );
}

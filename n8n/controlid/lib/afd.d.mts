// Tipos do leitor de AFD (afd.mjs) para o front (web/src/lib/afd.ts importa a mesma lib — fonte única).
export interface MarcacaoAfd {
  id_externo: string
  nsr: number
  instante?: string
  instante_local?: string
  cpf?: string
  pis?: string
}
export interface EmpregadoAfd {
  nsr: number
  operacao: 'I' | 'A' | 'E'
  cpf?: string
  pis?: string
  nome: string | null
}
export interface LeituraAfd {
  marcacoes: MarcacaoAfd[]
  empregados: EmpregadoAfd[]
  ignoradas: { linha: number; motivo: string; conteudo: string }[]
  total_linhas: number
  outros_registros: Record<string, number>
  duplicadas: number
  layouts: { '671': number; '1510': number }
}
export function lerAfd(texto: string | null | undefined, opcoes?: { tipos?: string[] }): LeituraAfd
export function lerLinhaAfd(linha: string, tipos?: string[]): unknown
export function lerEmpregadoAfd(linha: string): EmpregadoAfd | null
export function resumoAfd(leitura: LeituraAfd): Record<string, unknown>
export function emLotes<T>(lista: T[], tamanho?: number): T[][]

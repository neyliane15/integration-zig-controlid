/** Revisão 2: mensagens de erro do Postgres/PostgREST nunca chegam em inglês à tela (amostra de erros reais do banco). */
import { describe, expect, it, vi } from 'vitest'

vi.mock('@supabase/supabase-js', () => ({ createClient: () => ({}) }))

describe('mensagemDeErro — português', async () => {
  const { mensagemDeErro } = await import('./supabase')
  const casos: [string, string][] = [
    ['date/time field value out of range: "2026-02-30"', 'Data inválida'],
    ['invalid input syntax for type date: "abc"', 'Data inválida'],
    ['invalid input syntax for type uuid: "x"', 'Registro não encontrado'],
    ['numeric field overflow', 'Número fora do limite permitido'],
    ['value "99999999999" is out of range for type integer', 'Número fora do limite permitido'],
    ['duplicate key value violates unique constraint "x"', 'Já existe um registro igual'],
    ['update or delete on table "jornadas" violates foreign key constraint "y" on table "z"', 'Registro relacionado não encontrado ou ainda em uso'],
    ['new row for relation "x" violates check constraint "y"', 'Valor inválido'],
    ['permission denied for table comissao_itens', 'Sem permissão'],
    ['canceling statement due to statement timeout', 'A consulta demorou demais. Tente um período menor.'],
    ['Fechamento já está fechado', 'Fechamento já está fechado'],
  ]
  for (const [en, pt] of casos) it(en, () => expect(mensagemDeErro({ message: en })).toBe(pt))
})

/**
 * Exportação CSV no formato único do contrato §13 (mesmo formato de n8n/comum/lib/csv.mjs). Dono: frontend-1.
 *
 * - UTF-8 com BOM, separador `;`, TODA linha termina em `\r\n` (inclusive a última).
 * - Aspas duplas quando o campo tem `;`, `"`, `\r` ou `\n` (aspas internas dobradas).
 * - `null`/`undefined` → vazio; `true`/`false` → `Sim`/`Não`; números como `String(n)` (dinheiro e minutos:
 *   converta antes com `centavosCsv` / `minutosCsv`).
 * - `preambulo` (opcional): linhas escritas antes do cabeçalho, seguidas AUTOMATICAMENTE de uma linha em branco.
 */
import { centavosParaTexto, formatarData, minutosHHMM } from './formato'

const BOM = '﻿'
const FIM = '\r\n'

function campo(v: unknown): string {
  if (v == null) return ''
  const texto = typeof v === 'boolean' ? (v ? 'Sim' : 'Não') : String(v)
  return /[;"\r\n]/.test(texto) ? `"${texto.replace(/"/g, '""')}"` : texto
}

function linha(valores: readonly unknown[]): string {
  return valores.map(campo).join(';') + FIM
}

export function gerarCsv(cabecalho: string[], linhas: unknown[][], preambulo?: string[][]): string {
  let saida = BOM
  if (preambulo && preambulo.length > 0) {
    for (const l of preambulo) saida += linha(l)
    saida += FIM
  }
  saida += linha(cabecalho)
  for (const l of linhas) saida += linha(l)
  return saida
}

/** Dispara o download no navegador. */
export function baixarCsv(nome: string, conteudo: string): void {
  const blob = new Blob([conteudo], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nome.endsWith('.csv') ? nome : `${nome}.csv`
  a.rel = 'noopener'
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** 209474 → "2094,74"; null → "". */
export function centavosCsv(c: number | null | undefined): string {
  return c == null ? '' : centavosParaTexto(c)
}

/** -206 → "-03:26"; null → "". */
export function minutosCsv(m: number | null | undefined): string {
  return m == null ? '' : minutosHHMM(m)
}

/** "2026-10-06" → "06/10/2026"; null → "". */
export function dataCsv(iso: string | null | undefined): string {
  return iso ? formatarData(iso) : ''
}

/** "Bar Bossa Nova" → "bar-bossa-nova" (nome de arquivo, §13). */
export function slug(s: string): string {
  return (
    s
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'empresa'
  )
}

/** `<tipo>_<empresa-slug>_<aaaa-mm-dd>[_<aaaa-mm-dd>].csv` (§13). */
export function nomeArquivoCsv(tipo: string, empresa: string, inicio: string, fim?: string | null): string {
  return `${tipo}_${slug(empresa)}_${inicio}${fim && fim !== inicio ? `_${fim}` : ''}.csv`
}

/**
 * Tema claro/escuro/automático (paleta do cliente, contrato §14.1). Dono: frontend-1.
 * Sem escolha salva, segue o sistema operacional (prefers-color-scheme). A escolha fica em localStorage['mdg:tema']
 * e vira `data-theme` no <html> (o index.html aplica antes do CSS para não piscar).
 */
import { useCallback, useState } from "react";

export type Tema = "auto" | "claro" | "escuro";
const CHAVE = "mdg:tema";

export function lerTema(): Tema {
  try {
    const t = localStorage.getItem(CHAVE);
    return t === "claro" || t === "escuro" ? t : "auto";
  } catch {
    return "auto";
  }
}

export function aplicarTema(t: Tema): void {
  const raiz = document.documentElement;
  if (t === "auto") delete raiz.dataset.theme;
  else raiz.dataset.theme = t === "claro" ? "light" : "dark";
  try {
    if (t === "auto") localStorage.removeItem(CHAVE);
    else localStorage.setItem(CHAVE, t);
  } catch {
    /* navegação privada: vale só nesta aba */
  }
}

export function useTema(): [Tema, (t: Tema) => void] {
  const [tema, setTema] = useState<Tema>(lerTema);
  const definir = useCallback((t: Tema) => {
    aplicarTema(t);
    setTema(t);
  }, []);
  return [tema, definir];
}

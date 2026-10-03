// =============================================================================
// bora-mods · register.ts — liga os cinco mods POR ORDEM.
//
// A ordem dos `on` é a ordem da cadeia: a tranca vem primeiro, para que nada
// (nem as aprovações automáticas) passe à frente de uma proibição.
// O motor só aceita UM gancho sem filtro por evento em cada plugin: esse é o
// da tranca; os outros mods usam um filtro "apanha tudo" no mesmo evento.
// =============================================================================
import type { Register } from 'claude-code'

import { registarCi } from './ci'
import { registarContador } from './contador'
import { registarContexto } from './contexto'
import { registarTranca } from './tranca'
import { registarVigia } from './vigia'

export const register: Register = on => {
  registarTranca(on) // 1 · bora-tranca
  registarVigia(on) // 2 · bora-vigia
  registarContador(on) // 3 · bora-contador
  registarCi(on) // 4 · bora-ci
  registarContexto(on) // 5 · bora-contexto
}

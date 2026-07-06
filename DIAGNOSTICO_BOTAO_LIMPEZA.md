# Diagnóstico — botão "Trabalha também em Limpeza?" não aparecia ao estafeta

**Data:** 2026-07-06 · App `pt.boraapp.bora` · Missão multi-papel (estafeta ⇄ limpeza)

## TL;DR
**Bug de COLOCAÇÃO**, confirmado por leitura de código (não suposição). O tile da Limpeza
foi editado *dentro* de um bloco `if (role == AuthRole.client)` — por isso **nunca** aparece
quando a app está no papel de **estafeta**. Não tem nada a ver com `cleaning_enabled`, nem com
o `approval_status`, nem com os dados da conta do Danilo (que estão perfeitos).

---

## Evidência

### 1. Código (causa raiz)
`lib/screens/profile_screen.dart`:
- **Linha 569:** `if (role == AuthRole.client)` abre o `_SectionCard` "Quick links".
- **Linhas 667–684 (dentro desse bloco):** o `ListTile` da Limpeza, com texto role-aware
  (`_roles.hasCleaner ? 'A minha Limpeza' : 'Trabalha também em Limpeza?'`).

Como o tile está **inteiramente dentro do bloco client-only**, quando `role == AuthRole.driver`
essa secção nem é construída → o convite é invisível para o estafeta. O commit `multipapel/2`
(`d47263b`) mudou o *texto* do tile para ser ciente do papel, mas deixou-o no sítio errado
(secção do cliente). A intenção declarada no próprio commit era o estafeta ver — logo, regressão.

### 2. `cleaning_enabled` é irrelevante no cliente Flutter
`grep -r "cleaning_enabled" lib/` → **0 resultados**. A visibilidade do botão nunca dependeu
deste setting. Portanto `platform_settings.cleaning_enabled=true` estar certo no servidor não
muda nada — o botão continua invisível ao driver por causa da colocação.

### 3. Dados da conta do Danilo (via Supabase MCP) — perfeitos
Tabela `drivers` (telefone `+351931992662`): **2 contas de estafeta, ambas `approved`,
`is_banned=false`, `deleted_at=null`:**

| user_id | nome | approval_status | banido | deleted | criada |
|---|---|---|---|---|---|
| `4f61dd31-…ded7` | Danilo | approved | não | não | 2026-06-26 |
| `503a2e09-…67f1` | Danilo Fulfaro | approved | não | não | 2026-05-21 |

→ Conta 100% elegível. A hipótese "está banido/soft-deleted/não-aprovado" fica **descartada**.
*(Nota: a verificação da tabela `cleaners` apanhou 502s transitórios do proxy MCP; é
não-bloqueante — o tile é role-aware, mostra "A minha Limpeza" se já for cleaner, senão o convite.)*

> Observação lateral (fora do âmbito, não corrigido): há **duas** linhas de estafeta aprovado
> para o mesmo telefone. Não afeta este bug, mas vale rever/deduplicar mais tarde.

---

## Correção aplicada
`lib/screens/profile_screen.dart` — adicionado o **mesmo** tile da Limpeza (role-aware) à
secção visível ao estafeta (`if (role == AuthRole.driver)`, dentro do `_SectionCard` das
"Permissões de pedidos"). O tile do cliente ficou **intacto** (não partir o que funciona).

Comportamento após o fix, no perfil do estafeta:
- Sem linha em `cleaners` → **"Trabalha também em Limpeza?"** (convite) → abre `CleanerHomeScreen`.
- Já é profissional de limpeza → **"A minha Limpeza"** (gerir).
- Ao voltar do `CleanerHomeScreen`, recarrega o resumo (`_loadRoles`) — texto atualiza sozinho.

## Validação
- Chão anti-trapaça do Juiz: ver resultado no commit.
- `flutter analyze` no ficheiro tocado: sem novos erros.
- Testes de `roles_service` (9) inalterados (o fix não toca nessa lógica pura).
- Teste mental: driver aprovado sem cleaner → secção driver renderiza → tile presente → convite. ✅

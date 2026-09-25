# Diagnóstico — "Não foi possível enviar a candidatura" (profissional de limpeza)

**Data:** 2026-07-06 · Ecrã `lib/screens/cleaner/cleaner_apply_screen.dart` → `CleanerStore.apply` → RPC `cleaner_apply`

## TL;DR
O **backend está 100% funcional** — provei-o executando a própria RPC a impersonar a conta do
Danilo (rollback) e verificando buckets/RLS/overloads. A submissão **não falha no servidor**. A
hipótese principal do briefing (geocoding em falta a causar o erro) foi **DESMENTIDA**: `base_lat`/
`base_lng` são **NULLABLE** e a RPC aceita `null` sem erro. A causa do erro é **client-side/runtime**
(rede/dispositivo), só visível no log do telemóvel. Fiz as duas correções corretas: (1) mensagens de
erro específicas + marcador de fase que **revela** a causa real no próximo teste; (2) geocoding real
da zona base (bug legítimo, mesmo não sendo a causa do toast).

---

## O que foi VERIFICADO em produção (evidência, não suposição)

| Verificação | Método | Resultado |
|---|---|---|
| RPC `cleaner_apply` funciona p/ o Danilo | executei-a via MCP a impersonar `sub=4f61dd31…` com os mesmos params do app (lat/lng **null**), dentro de tx com `RAISE`→**rollback** | ✅ devolveu linha `cleaners` válida (`approval_status=pending`) |
| Overload ambíguo (PGRST203) | `pg_proc` p/ `cleaner_apply` | ✅ só **1** função (11 args). Sem ambiguidade |
| `base_lat`/`base_lng` NOT NULL? | DDL `cleaners` | ❌ são **NULLABLE** → null não causa erro |
| Coluna NOT NULL sem default em falta no INSERT | DDL vs INSERT da RPC | ✅ todas cobertas (`name` fornecido) |
| Bucket `cleaner-documents` | `storage.buckets` | ✅ existe, privado, **sem** limite de tamanho/mime |
| RLS de upload (`cleaners_upload_own_docs`) | avaliei a expressão `WITH CHECK` p/ o path `4f61dd31…/id_doc_*.jpg` | ✅ **passa** (`folder[1] == auth.uid()`) |
| `application_already_exists` | procurei linha `cleaners` do Danilo | ❌ **não existe** → não é este o erro |
| Parsing `CleanerProfile.fromSupabase` | leitura de código | ✅ defensivo (`as num?`, nullable, defaults) — não lança |
| `_cleaning_notify_admin` | corpo da função | ✅ tem `EXCEPTION WHEN OTHERS THEN NULL` — nunca propaga |

**Conclusão:** todos os componentes do lado servidor estão verdes. O toast genérico veio de uma
exceção **no cliente** (upload de foto/documento ou a chamada) que **não reproduz** no backend.
As causas plausíveis restantes são todas runtime/dispositivo: ligação de rede no momento do upload,
leitura do ficheiro escolhido, ou um build a apontar para estado diferente.

> Nota importante: como **não** consegui confirmar a causa exata do erro (adb logcat não disponível
> nesta sessão), NÃO apliquei um "fix" a fingir que resolve o toast. Apliquei o que é correto e
> seguro, sendo a melhoria da mensagem de erro **a ferramenta que revela a causa real** no próximo teste.

---

## Correções aplicadas (`cleaner_apply_screen.dart` — só UI, zero backend, zero zonas protegidas)

### PASSO 3 (obrigatório) — mensagens de erro específicas + fase
- Introduzido um marcador `stage` (`coords` → `uploads` → `apply`) que diz **onde** falhou.
- O `catch` agora mapeia: `application_already_exists`, `name_required`, `phone_required`,
  `not_authenticated`/`42501` (sessão expirada), e **erros de storage** (StorageException/row-level/
  Bucket/Unauthorized) → *"Não conseguimos enviar a foto ou o documento. Verifica a ligação…"*.
- `debugPrint('CleanerApply submit FAILED stage=$stage error=$e')` → o próximo `adb logcat` mostra
  a fase e o erro real. **Nunca mais fica só o genérico.**

### PASSO 2A (bug real) — geocoding da zona base
- O campo de texto livre "Zona base" passou a usar o **`AddressAutocompleteField`** (o MESMO widget
  das outras moradas da app — send_package, carry_groceries, errand, endereços do cliente). Ao
  escolher uma sugestão, resolve `lat/lng`.
- Fallback: se escreveu sem escolher sugestão (o caso do Danilo com "rua do torreão"), no submit
  tenta `geocodeAddress(texto)` com o mesmo serviço. `null` continua a ser aceite (não bloqueia).
- `CleanerStore.apply` já tinha os parâmetros `baseLat`/`baseLng` (não usados) — agora são enviados.

**Impacto:** antes, TODA candidatura criava um cleaner **sem coordenadas** → o matching/dispatch por
distância nunca o encontraria. Agora fica localizado.

## Validação feita
- `dart analyze lib/screens/cleaner/cleaner_apply_screen.dart` → **No issues found!**
- Chão anti-trapaça do Juiz → **CLEAN**.
- Teste da RPC em prod (impersonando o Danilo, com rollback) → cria linha `pending` correctamente,
  e aparece no admin (a lista de aprovação filtra por `approval_status='pending'`).

## Limites do teste (honestidade)
- Não corri o geocoding real (Google) daqui — precisa do dispositivo/app. O código compila e reutiliza
  o serviço já em produção nos outros formulários.
- A causa exata do toast só será confirmada quando o Danilo instalar o próximo build e a mensagem
  específica (ou o `logcat` com `stage=…`) apontar a fase. Peço que reporte o que aparecer.

## Bugs encontrados fora do scope (reportados, não corrigidos)
- **Contas de estafeta duplicadas:** o Danilo tem **2** linhas `drivers` aprovadas com o mesmo
  telefone (`4f61dd31…` e `503a2e09…`). Não afeta este fluxo, mas vale deduplicar.

# notify-tvde-driver — textos de ENCOMENDA (pronto, NÃO publicado)

21/10/2026 · fechar-pendencias A1 · ronda 1 do revisor. Substitui a proposta da 1.ª entrega.

**Está pronto em `a1/notify-tvde-driver/`:**

| Ficheiro | O que é |
|---|---|
| `v22_no_ar.ts` | a v22 do ar (12/10). Tirada do commit `ab056aa3`, que é exactamente o que está publicado: conferido contra o `get_edge_function` de 21/10 (sem `keys.ts`, `serviceKey` do env, cabeçalho v22, mesmos ramos). md5 `d6d28e6a776c40a23810daceac478baa`. |
| `aplicar_encomendas_sobre_v22.py` | as 24 trocas por âncora (cada uma tem de aparecer exactamente as vezes esperadas, senão aborta) |
| `index.ts` | o resultado: v22 + só os textos de encomenda. md5 `eb45b7afa48365e14835cca4d03e232d`. Sintaxe verificada com `deno fmt --check` (as duas versões lêem-se; só diferem na formatação que já tinham). |

O que muda (só quando `tvde_rides.ride_kind = 'encomendas'`; passageiros recebem o texto de
sempre): oferta "📦 Nova encomenda!" (e `rideKind` nos dados), fila "📦 Encomenda em fila",
atribuída "📦 Ficaste com uma encomenda", passada "Encomenda passada a outro estafeta",
cancelada "Entrega cancelada", reservas "📦 Encomenda marcada para aceitar" e "outro estafeta".
O corpo da oferta continua "Ganhas €x · origem -> destino" — o número grande é o ganho.

**Porque não publiquei:** o ficheiro do repo (`supabase/functions/notify-tvde-driver/index.ts`) está
À FRENTE do ar com a troca de chave do Bloco G (`keys.ts`/`secretKey()`), que não pode ir junto; e é
a função que toca todas as ofertas de passageiros.

**No dia de ligar `tvde_encomendas_enabled`:**
1. `get_edge_function notify-tvde-driver` → gravar como `v22_no_ar.ts`; o md5 tem de ser o de cima
   (se não for, o ar mudou: correr o `.py` sobre a versão nova e rever o diff).
2. `python aplicar_encomendas_sobre_v22.py v22_no_ar.ts index.ts` e `diff v22_no_ar.ts index.ts`.
3. Publicar o `index.ts` desta pasta (só ele, sem `_shared/keys.ts`), `verify_jwt` = true como hoje.
4. Prova: a próxima oferta real de passageiros sai com "🚗 Nova corrida!" e `push_enviado`; uma
   encomenda demo (motoristas reais protegidos) com "📦 Nova encomenda!".

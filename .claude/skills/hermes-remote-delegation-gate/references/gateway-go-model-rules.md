# Gateway OpenCode Go — Model Selection Rules

Reference for the inference gateway that feeds the juiz/orquestrador gating
orders before they reach the remote PC. Wrong model → pipeline stalls.

## Auth (endpoint-specific)

| Endpoint | Header |
|----------|--------|
| `/v1/messages` | `x-api-key: <key>` |
| `/chat/completions` | `Authorization: Bearer <key>` |

Swapping the header style gives 401 "chave inválida". Use the right one per
endpoint.

## User-Agent (Cloudflare)

Cloudflare blocks bare-Python requests with 403 (code 1010). **Always set a
User-Agent** on any HTTP call (`curl`, Python `requests`, etc.):
`Mozilla/5.0 ... Hermes-Agent/1.0` or similar. No UA = 403.

## Reasoning models (glm-5.2 etc.)

Reasoning models "think" before answering. If `max_tokens` is set low:
- The thinking phase consumes the entire token budget.
- The final answer is **empty** — `SAIDA-VAZIA`.

**Fix:** raise `max_tokens` substantially when using reasoning models, or the
response will be silently empty.

## Tools support (the critical rule for the juiz)

The juiz/orquestrador sends requests **with tools** (function calling). Not all
gateway models accept `tools` in the request:

| Model | Tools support | Notes |
|-------|--------------|-------|
| `glm-5.2` (reasoning) | ❌ 422 | Rejects `tools` in request — **cannot be used as agent/juiz** |
| `minimax-m3` | ✅ | Works with tools |
| `qwen3.7-max` | ✅ | Works with tools |
| `kimi-k3` | ✅ | Transient provider failures — retry resolves |

**Diagnosing JUIZ-SEM-VEREDITO:** if the active Hermes model is `glm-5.2` and the
juiz never returns a verdict line, the model gave 422 (tools rejected) or empty
(reasoning ate the budget). The fix is to switch the juiz/orquestrador model to
`minimax-m3` or `qwen3.7-max` — both accept tools.

## Quota (shared, weekly)

The gateway's quota is **weekly** and **shared** across all consumers:
motores (orchestration) + Buzz + Hermes + OpenCode app. Heavy consumption on
one consumer can exhaust the weekly pool for all. Monitor usage and spread load
when possible.

## Quick reference: symptom → fix

| Symptom | Cause | Fix |
|---------|-------|-----|
| 401 "chave inválida" | wrong header style for endpoint | use `x-api-key` for `/v1/messages`, `Bearer` for `/chat/completions` |
| 403 code 1010 | missing User-Agent (Cloudflare) | always set UA |
| `SAIDA-VAZIA` (empty result) | reasoning model + low `max_tokens` | raise `max_tokens` |
| 422 with tools | `glm-5.2` rejects tools | switch to `minimax-m3` or `qwen3.7-max` |
| `JUIZ-SEM-VEREDITO` (mass) | juiz model is `glm-5.2` | switch juiz model to a tools-capable one |
| Transient failure (`kimi-k3`) | provider flakiness | retry once |
| 429 quota exhausted | shared weekly pool empty | wait for reset, reduce load |
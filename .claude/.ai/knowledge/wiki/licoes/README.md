---
id: licoes-index
tipo: conceito
origem: [prompt Danilo Fase Final Bloco 4]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🎓 LIÇÕES — memória de experiência (problema → falhas → solução)

> Cada lição: **problema** → **tentativas que falharam** → **porquê falharam** → **solução definitiva**.
> ⚠️ **REGRA ANTI-LIXO:** uma lição só fica no permanente se virar **regra generalizável**.
> Relato de incidente isolado que não vira regra em 14 dias → morre no [[inbox]] como tudo o resto.

## Índice (semeado com lições reais da saga do Córtex)
| Lição | Regra em 1 linha |
|---|---|
| [[docker-exec-user-hermes]] | `docker exec` — escolher o **user** certo (`-u hermes` p/ env; `-u root` p/ dirs root-owned) |
| [[verificar-fonte-de-sync]] | Num sync, auditar a **FONTE**, não só o destino |
| [[verificar-estado-antes-de-reexecutar]] | Antes de reexecutar, `git log` o estado real — **verificar > reexecutar** |
| [[onde-vive-a-trava]] | Mapear **onde** vive um guard antes de o testar (a Trava é hook repo-side, não `engine` no VPS) |
| [[confirmar-ferramenta-antes-de-prometer]] | Confirmar que a ferramenta **existe** antes de prometer o passo |

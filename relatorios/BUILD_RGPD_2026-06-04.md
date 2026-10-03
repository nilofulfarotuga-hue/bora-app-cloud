# Build RGPD — 2026-06-04

## Status final
- workflow_dispatch adicionado: SIM
- Novo run disparado: SIM
- Run status: SUCCESS
- Play Internal upload: SIM

## Workflow info
- Run ID: 26936778872
- URL: https://github.com/nilofulfarotuga-hue/bora-app-cloud/actions/runs/26936778872
- Commit: 8b61e34 — "ci: adiciona workflow_dispatch ao build_android para permitir disparo…"
- Duração: ~29 minutos (07:12:49 → 07:41:35 UTC)

## Conteúdo do build
- Inclui os 5 commits RGPD: SIM (af3e27a, 3d7a1af, 49a544e, dcc3fd1, fbf6182)
- Inclui novo commit CI: SIM (8b61e34 — adiciona workflow_dispatch)
- versionCode: bump automático aplicado pelo CI (step "Bump versionCode" + "Commit versionCode bump" — ambos SUCCESS)

## Resultado
- Step de upload Play: SUCCESS ("Upload to Google Play (Internal Testing)" — 07:38:29 → 07:41:28)
- AAB gerado: SIM (step "Build appbundle (release)" SUCCESS — 07:13:45 → 07:38:29, ~25 min)
- Todos os 17 steps do job concluídos com SUCCESS

## Próximos passos
Confirmar no Google Play Console que o novo build aparece em Internal Testing com os 5 commits RGPD ativos; em seguida promover para testers e validar fluxo de consentimento RGPD no Samsung A36.

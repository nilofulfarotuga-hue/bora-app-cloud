---
id: memoria-claude-ai-digest-2026-10-08-c2-apple
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-08
zona: verde
confianca: alta
estado: atual
---

# C2 Apple: notificações urgentes no iPhone

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-08-c2-apple`, origem `claude-code`, atualizada em 2026-10-08T06:14:10.262756+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 08 c2 apple · memoria claude.ai · claude_ai_memoria

O que funciona agora: o App ID pt.boraapp.bora tem a capacidade Time Sensitive Notifications ligada (no portal PT chama-se "Notificações urgentes"; a API da Apple não aceita ligar esta capacidade, só ler). O perfil "Bora App Store" foi recriado pela API (XYAWYNHCQS, ACTIVE, traz a chave time-sensitive). O ios/Runner/Runner.entitlements pede com.apple.developer.usernotifications.time-sensitive. As funções do servidor já mandavam interruption-level time-sensitive na oferta (notify-driver v42, notify-tvde-driver v21, notify-driver-assigned v3) — não se tocou no servidor nem no despacho. Mudança no CI: o build_ios.yml deixou de usar o segredo IOS_PROVISIONING_PROFILE_B64 (ficou com o perfil invalidado e não se conseguiu trocar, cofre de credenciais fechado no modo sem ecrã) e passa a pedir o perfil à Apple em cada build com .github/scripts/ios_perfil.py, que falha se o perfil não trouxer todas as chaves do entitlements. Como se usa: capacidade nova = ligar no portal, recriar o perfil pela API, pôr a chave no entitlements; não é preciso mexer em segredos. Prova: commit 0893651f empurrado pela VPS; CI build-ios 175 verde (A e B), Android 508 verde, Web 202 verde; build 175 VALID no App Store Connect; e2e_log id 3155 run_id c2-apple-20261008. O que falta: a versão 1.0.13 que está em revisão leva a build 173, sem a chave; a 175 só chega aos motoristas na próxima versão submetida. Critical Alerts não se pediu.

# Auditoria iOS — matriz de ecrãs (ponto 1 da ordem de 2026-09-10)

> Regra: nada fica "provavelmente bem". Cada linha só passa a ✅ com prova
> lida de um log de corrida do CI (`[varredura] ok: "<ecrã>" com N textos`)
> ou de um IPA aberto. ❌ = provou-se que fecha ou fica vazio. ⬜ = por provar.
> A varredura automática é `integration_test/varredura_ecras_test.dart`; o
> portão estático é `test/ios_info_plist_test.dart`.

## Causas nativas já provadas (build 63, lida de dentro do IPA)

| Causa | Efeito | Ecrãs atingidos | Correcção | Prova |
|---|---|---|---|---|
| `GoogleMapsApiKey` vazia | SDK aborta ao criar o 1.º mapa (`GMSServicesException`, SIGABRT) | acompanhamento do pedido, Bora Motorista (pedir boleia), acompanhar boleia, início do estafeta, mapa do estafeta, TVDE do motorista (início, oferta, corrida activa), mapa admin — **10 ecrãs** | chave por xcconfig em todos os caminhos de build (`f76c92c8`) | relatório do simulador na corrida 34495605864; `provar_ipa.py` |
| `NSFaceIDUsageDescription` ausente | iOS mata a app ao pedir biometria (TCC) | entrar com biometria (cliente, estafeta, parceiro), confirmar pagamento com biometria | chave no Info.plist (`3a4256d1`) | `provar_63.py` (AUSENTE na 63) + doc Apple |

## Entrada (todos os perfis)

| Linha | Como se prova | Estado |
|---|---|---|
| Folha de privacidade → Aceitar tudo | varredura | ⬜ |
| Escolha de perfil (Sou Cliente / Estafeta / Parceiro) | varredura | ⬜ |
| Entrar por email — cliente `demo@bora.app` | varredura | ⬜ |
| Entrar por email — estafeta `demo-estafeta@bora.app` | varredura | ⬜ |
| Entrar por email — parceiro `demo-parceiro@bora.app` | varredura | ⬜ |
| Entrar com biometria | simulador NÃO cobre; portão estático (`NSFaceIDUsageDescription`) + iPhone real | ⬜ |
| Criar conta (registo) | varredura abre o ecrã | ⬜ |
| Recuperar palavra-passe (ecrã) | varredura abre o ecrã | ⬜ |
| Recuperar palavra-passe (email sai mesmo) | envio real 2026-09-10 16:49:47 → chegou de `nao-responder@boraguarda.com` | ✅ |
| Apagar conta (caminho + aviso, sem apagar) | varredura | ⬜ |

## Cliente — mosaicos do início

| Mosaico | Abre o quê | Mapa? | Estado |
|---|---|---|---|
| Restaurantes | lista de restaurantes | não | ⬜ |
| Supermercados | lista de mercados | não | ⬜ |
| Farmácia | lista/loja | não | ⬜ |
| Lojas | lista de lojas | não | ⬜ |
| Enviar Encomenda | formulário | não | ⬜ |
| Levar Compras | formulário | não | ⬜ |
| Favores | formulário de favor | não | ⬜ |
| Reservar Mesa | reservas | não | ⬜ |
| Beleza | prestadores de serviços | não | ⬜ |
| Limpeza | assistente de limpeza | não | ⬜ |
| Bora Motorista | pedir boleia | **sim** | ⬜ |
| Festas | lista | não | ⬜ |
| Sobremesas | lista | não | ⬜ |
| Lavagem Auto | serviço (só com categoria aberta) | não | ⬜ |

## Cliente — separadores e ecrãs de pedido

| Linha | Mapa? | Estado |
|---|---|---|
| Entregas (lista de pedidos) | não | ⬜ |
| Reservas | não | ⬜ |
| Perfil | não | ⬜ |
| Acompanhamento do pedido (abre sozinho com estafeta atribuído) | **sim** | ⬜ |
| Detalhe do pedido → cartão "O teu estafeta" → Chat | não | ⬜ |
| Chat → bandeira → denunciar / bloquear / desbloquear | não | ⬜ |

## Estafeta

| Linha | Mapa? | Estado |
|---|---|---|
| Início do estafeta | **sim** | ⬜ |
| Ganhos (tooltip) | não | ⬜ |
| Perfil (tooltip) | não | ⬜ |
| Definições | não | ⬜ |
| TVDE motorista: início / oferta / corrida activa | **sim** | ⬜ (exige documentos TVDE aprovados — a conta demo não tem) |

## Parceiro (`demo-parceiro@bora.app`, loja "Loja Demo Bora")

| Linha | Mapa? | Estado |
|---|---|---|
| Painel do parceiro | não | ⬜ |
| Gerir produtos | não | ⬜ |
| Horários de funcionamento | não | ⬜ |
| Ver detalhe de ganhos / Extrato | não | ⬜ |
| Reservas Pro | não | ⬜ |
| Chamar estafeta | não (lista) | ⬜ |

## O que o simulador não cobre e como fica coberto

- **Biometria**: portão estático no `flutter test` + a gravação no iPhone real.
- **Push real**: FCM não corre no simulador; a chave APNs está ligada ao Firebase (bloco -5 do estado).
- **TVDE do motorista**: precisa de documentos aprovados; fica ⬜ com razão escrita, não "provavelmente bem".

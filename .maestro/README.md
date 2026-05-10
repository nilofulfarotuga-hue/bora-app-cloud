# Bora App — Maestro E2E

Cobertura E2E de TODOS os fluxos da app: cliente, parceiro, estafeta, admin.

## 1. Instalar Maestro

### macOS / Linux / WSL
```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

### Windows (Git Bash / PowerShell)
1. Garante que tens **Java JDK 11+** instalado (`java --version`).
2. Em Git Bash:
   ```bash
   curl -Ls "https://get.maestro.mobile.dev" | bash
   ```
3. Adiciona `$HOME/.maestro/bin` ao `PATH`.
4. Confirma: `maestro --version`.

> Maestro não tem instalador nativo Windows. Se preferires, usa **WSL** ou descarrega o JAR de
> https://github.com/mobile-dev-inc/maestro/releases/latest e cria um wrapper.

## 2. Pré-requisitos para correr

- **Android device/emulador** com a app `com.example.bora_app` instalada (build debug ou release).
- **OU iOS** — alterar `appId` em todos os YAMLs para `com.example.boraApp`.
- Sessão de cliente/parceiro/admin previamente registada na DB Supabase
  (`nilofulfarotuga@gmail.com`, `teste9@bora` etc.) com palavra-passe definida.

## 3. Variáveis de ambiente (opcionais — têm defaults)

| Variável | Default |
|---|---|
| `MAESTRO_CLIENT_EMAIL`    | `nilofulfarotuga@gmail.com` |
| `MAESTRO_CLIENT_PASSWORD` | `123456` |
| `MAESTRO_PARTNER_EMAIL`   | `teste9@bora` |
| `MAESTRO_PARTNER_PASSWORD`| `123456` |
| `MAESTRO_DRIVER_PHONE`    | `910000000` |
| `MAESTRO_DRIVER_PASSWORD` | `123456` |
| `MAESTRO_ADMIN_EMAIL`     | igual a `CLIENT_EMAIL` |
| `MAESTRO_ADMIN_PASSWORD`  | `123456` |

Override pela CLI:
```bash
maestro test -e MAESTRO_CLIENT_PASSWORD=outraSenha flows/cliente/01_registo_login.yaml
```

## 4. Correr

```bash
# Tudo (24 flows)
./.maestro/run_all.sh

# Só flows de cliente
./.maestro/run_all.sh cliente

# Um único flow
maestro test .maestro/flows/parceiro/05_reservas_pendentes.yaml

# Inspeccionar UI ao vivo (recomendado para refinar selectors)
maestro studio
```

## 5. Estrutura

```
.maestro/
├── config.yaml                # appId central (referência)
├── README.md                  # este ficheiro
├── run_all.sh                 # runner sequencial
├── _shared/                   # sub-flows (login_*) reutilizados via runFlow
│   ├── login_admin.yaml
│   ├── login_cliente.yaml
│   ├── login_estafeta.yaml
│   └── login_parceiro.yaml
└── flows/
    ├── admin/      (3 flows)
    ├── cliente/   (10 flows)
    ├── estafeta/   (3 flows)
    └── parceiro/   (8 flows)
```

## 6. Cobertura — 24 flows

### Cliente (10)
01 Registo / Login · 02 Pedido restaurante (golden) · 03 Pedido supermercado · 04 Reservar mesa €3 (verifica breakdown €1+€2) · 05 Fila de espera · 06 Carteira + Tokens · 07 Histórico pedidos · 08 Chatbot Bora IA · 09 Cancelar pedido · 10 Notificações

### Parceiro (8)
01 Login · 02 Aceitar pedido · 03 Rejeitar pedido · 04 Gerir produtos · 05 Reservas pendentes (badge laranja) · 06 Reservas futuras (BUG 3) · 07 Walk-in · 08 Ganhos (verifica secção Reservas)

### Estafeta (3)
01 Login · 02 Aceitar entrega → recolhido → entregue · 03 Ver ganhos + tokens

### Admin (3)
01 Login · 02 Lista de pedidos · 03 Acerto reservas parceiros

## 7. Caveats importantes

1. **Selectors text-based:** estes flows foram escritos por análise estática do código
   Flutter — sem inspecção da UI rendered. Alguns labels podem precisar de ajuste fino.
   Usa `maestro studio` para refinar contra a UI real.

2. **Pre-condições não geradas:** flows `09_cancelar_pedido` e `02_aceitar_pedido` (parceiro)
   assumem que existe um pedido activo. Sem dados, o flow termina silenciosamente via
   `runFlow` guard `when:` (não falha o build).

3. **Stripe E2E:** o flow `04_reserva_mesa.yaml` **NÃO** confirma o pagamento (apenas valida
   o ecrã). Confirmar manualmente em ambiente de teste com o Stripe **Test mode** habilitado.

4. **Independência:** cada flow chama `launchApp: clearState: true` + login próprio. Ordem de
   execução não importa.

5. **Push/realtime:** flows não validam push notifications nem realtime. Para isso usar
   `maestro studio` em modo gravação com 2 dispositivos.

6. **CI:** para correr em CI (GitHub Actions), ver
   https://maestro.mobile.dev/cloud/run-maestro-in-ci-cd — recomendado **Maestro Cloud**.

## 8. Refinar selectors após primeira run

```bash
maestro studio   # abre browser inspector
# 1. Navega até ao ecrã alvo
# 2. Clica nos elementos para ver o seletor real
# 3. Copia para o YAML correspondente
```

## 9. Ligação com bugs/features

Os flows incluem assertions específicas para validar features recentes:

- `flows/cliente/04_reserva_mesa.yaml` → BUG checkout breakdown €1+€2 (commit cd041b2)
- `flows/parceiro/05_reservas_pendentes.yaml` → BUG 1 badge dashboard
- `flows/parceiro/06_reservas_futuras.yaml` → BUG 3 separador Futuras
- `flows/parceiro/08_ganhos.yaml` → secção Reservas (commit cd041b2)
- `flows/admin/03_acerto_semanal.yaml` → AdminPartnerSettlementsScreen + RPC

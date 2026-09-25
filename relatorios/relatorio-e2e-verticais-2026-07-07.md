# Relatório E2E — verticais (continuação) — 2026-07-07

Branch: `autonomous-night-2026-04-29` · 1 telemóvel (Redmi `N75LTG5X5DSKDMV4`, build 370) ·
pagamentos só em dinheiro · MODO PROTECÇÃO TOTAL (dinheiro real = PROPOSE-ONLY).

## TL;DR

- **Limpeza — candidatura profissional: PASSA (E2E completo, provado na BD).** Foto + documento
  via galeria, submissão criou a linha em `cleaners` (`approval_status=pending`). **Confirma o fix
  do build 370** (`cca53c3`, MIME `image/jpg→image/jpeg`): o documento subiu como `.jpg` sem o 400.
- **Mercados: BLOQUEADO pelo dispositivo (não é bug de código).** O Redmi tem **1,8 GB de RAM
  total** (classe Android Go). O catálogo carrega, mas a **pesquisa de produto** faz o
  low-memory-killer do Android despejar a app para o ecrã inicial (confirmado no logcat). Ver §2 —
  é um achado real e importante para o mercado-alvo (telemóveis baratos).
- **TVDE / autocomplete de morada:** os fixes de UI (mapa heading-up + overlay de sugestões) estão
  **commitados e pushed** (`0e39a71`), mas **só verificáveis na próxima build do CI** — o device
  tem a build 370 e a compilação local é proibida.
- **Test data criado** (a limpar via MCP): 1 linha em `public.cleaners` + 2 ficheiros no Storage
  (ver §7, com SQL pronto).

---

## 1) Limpeza — candidatura profissional — ✅ PASSA

**Fluxo validado ponta-a-ponta** (`.maestro/flows/cliente/16_limpeza_candidatura.yaml`):

1. Perfil → tile **"Trabalha também em Limpeza?"** (aparece porque o cliente ainda não é cleaner).
2. Ecrã intro **"Limpezas — Profissional / Ganha com limpezas"** → botão **"Quero candidatar-me"**.
3. Formulário **"Ser profissional de limpeza"**:
   - **Foto de perfil \*** (obrigatória) → seletor de galeria do sistema → imagem escolhida.
   - **Documento de identificação (BI/CC) \*** (obrigatório) → galeria → imagem escolhida.
   - Nome completo + Telemóvel.
4. **"Enviar candidatura"** → snackbar **"Candidatura enviada! Vamos rever em breve. 💚"**.

**Prova na BD** (`public.cleaners`, cliente `nilofulfarotuga@gmail.com`):

| campo | valor |
|---|---|
| id | `4d2868b5-2912-43e5-843d-404788268a97` |
| name / phone | Teste E2E Limpeza / 912345678 |
| approval_status | **pending** (correto — espera aprovação do admin) |
| has_photo | **true** (avatar subiu para o bucket público) |
| docs.id_doc | `c9fccf85-…/id_doc_1783438902560.jpg` (subiu como `.jpg`) |
| created_at | 2026-07-07 15:41:43 UTC |

**Confirmação do fix `cca53c3`:** antes, o upload do documento dava **400** por MIME `image/jpg`
inválido. Agora o `.jpg` subiu sem erro e a candidatura fechou. ✅ O fix do build 370 funciona.

**Agendamento + split 85/15** já tinha ficado **PASSA** na corrida noturna (split provado na BD:
€45,00 → cleaner €38,25 / Bora €6,75 = 85/15). Vertical Limpeza **fechada**.

---

## 2) Mercados — ⛔ BLOQUEADO pelo dispositivo (achado real)

`.maestro/flows/cliente/15_mercado_loja.yaml` (paramétrico por loja). O que **passou**:

- Lista de supermercados → abrir **Continente**.
- Catálogo carrega: cabeçalho mostra **Entrega €2,50** + ETA (modelo não-parceiro com markup
  runtime — coerente com as regras de negócio).

O que **bloqueou** (3 tentativas, com e sem memória livre):

- Ao **pesquisar um produto** ("leite"), a app **desaparece para o ecrã inicial** a meio do teste.
- **Causa confirmada no logcat:** `lowmemorykiller: Kill … reason: device is not responding` a
  matar processos em cadeia. O Redmi tem **MemTotal ≈ 1,8 GB** (Android Go / MediaTek). O catálogo
  de mercado (grelha de imagens) + Google Maps + a pesquisa esgotam a RAM e o SO **despeja a
  própria Bora**.

**Não é bug de selector nem de lógica** — é limitação de RAM do aparelho. Mas é um **achado de
produto relevante**: num telemóvel de 2 GB (muito comum no mercado-alvo PT/BR), o utilizador pode
ver a app **fechar sozinha ao navegar no mercado**. Sugestão (a decidir, não implementado):
reduzir a pegada de memória do catálogo (lazy-load / thumbnails menores / limitar imagens em
memória) e testar num aparelho ≥3 GB para separar "limitação do device" de "pegada da app".

**Estado:** catálogo + preços validados; compra completa **não testável neste device** por RAM.

---

## 3) TVDE — 🔧 fixes pushed, verificação on-device pendente da próxima build

- **Mapa do cliente heading-up** (paridade com o motorista) + **flip do overlay de sugestões**
  quando falta espaço abaixo do campo: `0e39a71` (pushed). `flutter analyze` limpo nos 2 ficheiros.
- **`est_fare_cents = 0`**: analisado — **não é bug**. Corridas cobertas pelo plano gravam 0 por
  design; `driver_earn`/`bora_cut` batem com a regra coberta×0,85. Detalhe em
  `relatorios/relatorio-fix-tvde-mapa-2026-07-07.md`.
- **Observação de negócio (PROPOSE-ONLY):** cancelamento tardio numa corrida coberta custa €0 ao
  cliente (usa `est_fare_cents`=0). Confirmar se é o desejado — **não** foi criado RPC financeiro.
- Verificação visual (mapa a rodar, lista acima do teclado) **fica para a próxima build do CI** —
  o device tem a 370 e build local é proibida.

---

## 4) Delivery (restaurante) — validado na corrida noturna; re-teste limitado

O browse + carrinho de restaurantes ficou **PASSA** na corrida noturna (Cliente 8/10). O re-teste
completo agora tem o **mesmo risco de despejo por memória** dos mercados (catálogo com imagens) e
criaria pedido/dispatch reais. Decisão: **não re-executar** para não re-provar a alto custo/risco
o que a noite já mostrou. Sem regressão conhecida.

---

## 5) Bloqueados / N/A neste setup (documentado, não testado)

- **Reservas — chegada / no-show:** exige **€2 reais** (pré-pagamento) e um **2.º device (parceiro)**.
  Fora do envelope (dinheiro real) e do setup (1 telemóvel). **PROPOSE-ONLY / PARCIAL.**
- **Favores (morada):** usa o `AddressAutocompleteField`. O fix do overlay (sugestões acima do
  teclado) **não está na build 370** (foi pushed depois) → no device as sugestões ainda ficam atrás
  do teclado, logo a automação não as alcança. **Re-testar na próxima build.**
- **Transversais** (chat 2-atores, push cruzado, biometria): **N/A com 1 telemóvel**. Notificações
  in-app validáveis, o resto precisa de 2 dispositivos.

---

## 6) Fixes commitados nesta linha que aguardam a próxima build do CI

| Commit | O quê | Verificação |
|---|---|---|
| `0e39a71` | TVDE mapa heading-up + flip do overlay de sugestões | próxima build (device tem 370) |
| `cca53c3` | Upload de documento MIME `image/jpg→image/jpeg` | **✅ confirmado hoje** (§1) |

---

## 7) Test data a limpar (via MCP) — o Danilo decide

Criado 1 registo real de teste (a `cleaners` não tem flag `is_test`, por isso vai listado):

- **Tabela `public.cleaners`** — id `4d2868b5-2912-43e5-843d-404788268a97`
- **Storage** — avatar (bucket público de cleaners) + documento
  `c9fccf85-03ee-4efc-83bf-613f211a78ff/id_doc_1783438902560.jpg` (bucket privado de docs)

SQL pronto (apaga a candidatura de teste):

```sql
DELETE FROM public.cleaners WHERE id = '4d2868b5-2912-43e5-843d-404788268a97';
-- Storage: remover o avatar e o doc pelos caminhos acima (Storage → buckets de cleaners).
```

---

## 8) Ficheiros novos

- `.maestro/flows/cliente/15_mercado_loja.yaml` — fluxo paramétrico de mercado (catálogo→pesquisa).
- `.maestro/flows/cliente/16_limpeza_candidatura.yaml` — candidatura de limpeza E2E (com uploads).

## Lições de automação (para o próximo)

- **Device de 1,8 GB despeja a app em fluxos com muitas imagens** — testar mercados/delivery
  pesados só num aparelho ≥3 GB, ou aceitar que a automação lá não fecha.
- **Seletor `.*€.*` / acentos:** o € e "também/Histórico" saem partidos no terminal mas o match é
  pelo ficheiro (UTF-8). Ainda assim, preferir **selectors ASCII-safe** (`em Limpeza`, `Saldo Bora`)
  para evitar dúvidas.
- **Seletor de galeria do sistema:** `tapOn point: "17%,32%"` acerta a 1.ª miniatura de forma
  fiável (funcionou para foto **e** documento).
- **Botão no fundo do formulário:** `scrollUntilVisible` com `centerElement:false` +
  `visibilityPercentage:20` — centrar a 100% falha quando o elemento já está no fundo.
- **App estrangeira a roubar foreground:** `am force-stop <pkg>` antes de correr; o `launchApp`
  não recupera se outra app saltar a meio.

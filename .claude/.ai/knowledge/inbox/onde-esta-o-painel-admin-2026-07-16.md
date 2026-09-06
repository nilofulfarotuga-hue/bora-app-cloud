---
id: onde-esta-o-painel-admin-2026-07-16
tipo: relatorio
zona: verde (só leitura de configuração e de rotas, nada de dinheiro tocado)
criada: 2026-07-16
autor: claude.ai (investigação "onde está o painel admin no telemóvel")
---

# Onde está o painel admin, a partir do telemóvel (2026-07-16)

Pergunta do Danilo: onde é que ele chega ao painel admin a partir do telemóvel? Resposta ponto
a ponto, feita só por leitura de código e configuração (nenhuma alteração foi feita).

## (1) O painel admin está publicado na internet? — NÃO ESTÁ

Procurei no repositório todos os sítios onde normalmente se configura um site publicado:
`firebase.json`, `.firebaserc`, `vercel.json`, `netlify.toml` — **nenhum destes ficheiros
existe**. Também olhei para os dois ficheiros que fazem builds automáticos no GitHub
(`.github/workflows/build_android.yml` e `.github/workflows/dart.yml`) — **os dois só fazem
build do Android (o `.apk`)**. Não há nenhum passo de `flutter build web`, nem de publicar
nada num site, nem no Firebase Hosting, nem na Vercel, nem em lado nenhum.

Existe uma pasta `web/` no projeto (com `index.html`, `favicon.png`, ícones, `manifest.json`),
mas isso é só o esqueleto que o Flutter cria automaticamente quando se liga o suporte a "web"
num projeto — não quer dizer que esteja publicado. É como ter a porta pronta numa casa que
ainda não tem endereço postal.

**Conclusão clara: o painel admin NÃO tem nenhum link/URL público na internet.** Hoje em dia,
a única forma de o abrir é correndo o próprio código no computador (por exemplo com o comando
`flutter run -d chrome`, que abre o Chrome do PC) ou instalando a própria app Bora normal no
telemóvel — o painel admin faz parte da MESMA app que os clientes usam, não é um site à parte.

## (2) Como se faz login como admin

Não há um "login de admin" separado — usa-se o login normal da app (o mesmo ecrã de sempre)
com uma conta que tenha a etiqueta de admin guardada no Supabase (o servidor que guarda os
dados). Essa etiqueta chama-se `app_metadata.role = 'admin'` e fica dentro da sessão da conta
depois do login — é como um crachá invisível colado à conta, que o telemóvel não pode
falsificar porque vem do servidor.

Depois do login normal, a app olha para esse crachá (ficheiro
`lib/services/auth_admin_service.dart`) e, se disser "admin", mostra um botão extra
"Painel Admin" no ecrã de Perfil que os utilizadores normais nunca veem.

(Nota: os e-mails de admin conhecidos são `nilofulfarotuga@gmail.com` e
`nilofulfaro@gmail.com` — ver memória do Cortex `user_admin_emails`.)

## (3) Caminho de cliques até ao ecrã da Central de Autonomia (AdminRobotSuggestionsScreen)

1. Abrir a app e fazer login com a conta de admin.
2. Ir ao ecrã **"Perfil"** (o menu normal de perfil do utilizador).
3. Lá em baixo aparece um botão verde **"Painel Admin"** (só aparece para quem tem o crachá
   de admin) — tocar nele.
4. Isso abre o **Painel Admin** (uma lista de cartões, um por funcionalidade de gestão).
5. Descer a lista até encontrar o cartão **"🎛️ Central de Autonomia"** (ícone de "hub"),
   com o texto "Aprovar/rejeitar + placar de paridade, kill switch e dial" — tocar nele.
6. Isso abre o ecrã que o Danilo conhece como a Central — onde aparecem as sugestões do
   robô, os níveis (verde/amarelo/vermelho), o histórico e as propostas da zona vermelha.

Não há nenhum atalho direto (tipo link ou botão no menu principal) — é sempre por este
caminho: Perfil → Painel Admin → Central de Autonomia.

## (4) Esse ecrã funciona no telemóvel (ecrã pequeno) ou só no computador?

Pela leitura do código (`lib/screens/admin/admin_robot_suggestions_screen.dart`), o ecrã foi
construído com os mesmos blocos de construção usados no resto da app do telemóvel: listas que
deslizam para baixo, texto pequeno, caixas que se ajustam à largura do ecrã ("Expanded"),
sem tabelas largas fixas nem nada pensado só para ecrã grande de computador. Ou seja, foi
escrito do mesmo jeito "para telemóvel" que todo o resto da app Bora.

Não encontrei nenhum ajuste especial pensado para computador/tablet (não há código que diga
"se o ecrã for largo, mostra assim; se for estreito, mostra assado"), mas também não há nada
que dependa de um ecrã grande. Como toda a app já é pensada para telemóvel, este ecrã deve
aparecer bem num telemóvel — mas isto é uma leitura de código, não foi testado ao vivo num
telemóvel real (a ordem foi só de investigação, sem correr a app).

## (5) O que faltaria para publicar o painel na internet

Hoje não há NADA meio-feito para isto — nem um `firebase.json` de rascunho, nem um projeto
Firebase ligado, nem uma conta Vercel/Netlify referida em lado nenhum do repositório. Seria
preciso, do zero:

1. Criar/ligar um projeto de hospedagem (o mais comum para apps Flutter é o **Firebase
   Hosting**, porque o Bora já usa outras coisas da Google, mas podia ser outro serviço).
2. Adicionar essa configuração ao repositório (o tal `firebase.json` que hoje não existe).
3. Acrescentar um passo no GitHub Actions que faça `flutter build web` e depois publique
   essa pasta gerada no serviço escolhido — hoje o `.github/workflows/` só sabe fazer o
   `.apk` do Android, teria de ganhar este passo novo.
4. Decidir um domínio/endereço (por exemplo algo como `admin.boraapp.pt`, é só um exemplo).

Isto é trabalho de infraestrutura (não mexe em dinheiro nem em zona protegida), mas é uma
peça nova a construir — não existe hoje nem parcialmente.

---

**Resumo direto para o Danilo:** hoje, no telemóvel, só chegas ao painel admin abrindo a
própria app Bora (a mesma dos clientes), fazendo login com a tua conta de admin, e indo a
Perfil → Painel Admin → Central de Autonomia. Não há nenhum link de internet para abrir isto
no browser do telemóvel — isso teria de ser construído.

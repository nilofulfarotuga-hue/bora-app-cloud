# Ficha legal do motorista TVDE — 23/09/2026

run_id `motorista-ficha-legal-2026-09-23`, sessão Claude Code na nuvem, ramo `autonomous-night-2026-04-29`.

## Acessos

Base de dados Supabase `ojykpzwqrtusfeakzrna`, por MCP. Contas usadas nas provas: a tua conta de motorista boraappbora@gmail.com (id 4f61dd31) e a tua conta de admin e passageiro nilofulfarotuga@gmail.com (id c9fccf85). Para provar os e-mails abri uma sessão da conta boraappbora com um link de uso único gerado pela API de admin, sem tocar em palavra-passe nenhuma. Não criei contas. Repositório bora-site acrescentado a esta sessão, ramo novo `motorista-ficha-legal-2026-09-23`, pedido de junção em rascunho https://github.com/nilofulfarotuga-hue/bora-site/pull/1.

## O que NÃO ficou feito

Primeiro, a página pública de verificação ainda não está no ar. Está pronta e provada, mas o bora-site só se publica a correr `deploy-cloudflare.sh` com o token da Cloudflare, e esse token só existe no teu PC. Até lá, quem ler o QR cai na página "não encontrada" do site. O endereço vive em `platform_settings.fiscalizacao_verificar_base_url`, por isso muda-se sem nova versão da app.

Segundo, o formulário de candidatura de motorista não ganhou os campos novos. A ficha preenche-se depois: há um botão "Preencher a ficha legal" no ecrã de candidatura em análise, e "Atualizar os meus dados" dentro do ecrã de fiscalização. Pus assim porque a candidatura cria a conta antes de existir o registo de motorista, e meter lá doze campos mais cinco datas atrasava a inscrição.

Terceiro, ninguém tem a ficha preenchida ainda. Hoje o semáforo do painel mostra "não preenchido" em todos os cinco motoristas. O bloqueio só trava documento com data vencida; campo vazio não trava, de propósito, para não te deixar a ti e aos outros motoristas offline no dia em que a versão chega.

Quarto, os ecrãs Flutter não foram provados na web nem no telemóvel: o web app só se atualiza com este push. Estão provados pelo `flutter analyze` e pelos testes.

Quinto, fatura não foi feita, como a ordem mandava. Só recibo.

## Bloco 1, os dados

Não havia onde guardar certificado TVDE, carta, dístico, inspeção, seguro nem operador. A tabela `tvde_driver_documents` existe mas está vazia e nenhum ecrã escreve lá. Criei a tabela `motorista_ficha_legal`, uma linha por pessoa ligada ao `user_id`, com número e validade do certificado do IMT, número e validade da carta, ano do carro, número e validade do dístico, validade da inspeção, seguradora, apólice, validade do seguro, se cobre passageiros, e nome, NIF e licença do operador quando o motorista trabalha para uma frota. Nome, foto, NIF, matrícula, marca e modelo e cor continuam a viver onde já viviam, na tabela dos motoristas, para não haver duas matrículas. Os dados da Bora como plataforma ficam em `platform_settings`: nome Bora, NIF e licença vazios, e vazio aparece como "em processo". Migração `20260923183444`. Prova em rollback com a tua conta de motorista: gravou, e o semáforo deu certificado válido por 586 dias, carta a expirar em 17 dias, inspeção expirada há 22 dias.

## Bloco 2, o ecrã Fiscalização

Na app do motorista há agora um botão "Mostrar à autoridade" sempre à vista no mapa, e o mesmo com o ícone de polícia no menu de cima. Abre em ecrã inteiro, fundo branco e letra grande: foto e nome, certificado e carta com validades, a matrícula em letras enormes, marca, modelo, cor, ano, dístico, inspeção, seguro, operador e plataforma, a viagem em curso ou a última com hora de início, origem, destino, preço, forma de pagamento e o passageiro só com a inicial, o semáforo dos documentos e o QR para a página pública. Sem rede mostra a última cópia guardada no telemóvel e diz a que horas foi tirada. O botão "Enviar cópia por e-mail" manda um PDF ao próprio motorista. Prova: chegou à caixa boraappbora às 19h40 de Lisboa, com o anexo `ficha-fiscalizacao-bora.pdf` e o link de verificação.

## Bloco 3, a página pública

`boraguarda.com/verificar/<código>` mostra os mesmos dados sem NIF, sem morada, sem apólice e sem nada do passageiro, com a hora em que o código foi gerado e a hora da consulta. O código dura 24 horas e o ecrã reaproveita-o enquanto tiver mais de uma hora de vida, para o QR não mudar a cada abertura. A função que a página chama só lê. Prova: como utilizador anónimo, o código verdadeiro devolveu os dados com NIF vazio; um código inventado devolveu "inválido"; a página desenhada a 390 píxeis diz "Dados confirmados pela Bora" ou "NÃO foram confirmados pela Bora", sem rolagem lateral. Capturas em `.claude/.ai/provas/motorista-ficha-legal-2026-09-23/`.

## Bloco 4, o recibo da viagem

Já existia o "Pago 5,00 € · MB Way", mas sem a taxa discriminada e sem e-mail. Agora, quando a viagem passa a finalizada, o passageiro recebe por e-mail o recibo com o serviço de transporte, a taxa de intermediação da Bora numa linha própria, o valor, os descontos quando os houver e a forma de pagamento, com a nota de que não substitui fatura. Na app, o histórico e o ecrã da viagem têm "Recibo", com botão para reenviar por e-mail. Os números só são lidos do que a corrida já gravou: a divisão só aparece quando motorista mais Bora dá exatamente o valor da viagem; nas corridas de pacote ida e volta em que isso não bate, mostra o total e a razão, em vez de inventar. Prova: a tua viagem de 5,00 € ao Hospital Sousa Martins chegou à caixa boraappbora com "Serviço de transporte 4,00 €, Taxa de intermediação Bora 1,00 €, Valor da viagem 5,00 €, MB Way". O envio automático para a tua conta de passageiro deu resposta 200 do Resend. Desliga-se em `platform_settings.tvde_recibo_email_auto`.

## Bloco 5, o painel admin

"Documentos TVDE" no menu passou a ser "Documentos dos motoristas": semáforo de cinco pontos por motorista, filtros por expirado, a expirar em 30 dias, não preenchido e tudo válido, editar a ficha de qualquer motorista com registo na auditoria, exportar CSV, o interruptor do bloqueio e os campos do NIF e da licença da Bora. O ecrã antigo de aprovação de ficheiros foi para "Arquivado" com o motivo escrito. Todos os dias às 08h00 UTC corre o aviso: ao motorista, por notificação e dentro da app, 30 dias antes e no dia em que expira, e a ti no painel, uma vez por documento e data. O bloqueio de ficar online com documento expirado está ligado por defeito e só vale para motoristas de passageiros: o servidor recusa, e a app pergunta antes e mostra "Documento expirado" com o botão para atualizar a ficha. Provas em rollback: bloqueio recusou com "DOCUMENTO_EXPIRADO: Inspeção periódica"; o aviso correu duas vezes e só avisou na primeira; a edição pelo admin escreveu uma linha na auditoria; um motorista a chamar a função do painel foi recusado.

## Bloco 6, fecho

`flutter analyze` sem erros; os sete avisos que aparecem são de ficheiros que não toquei. Os 796 testes passam, com 17 novos em `test/motorista_ficha_legal_test.dart`. O chão anti-trapaça do Juiz deu limpo e o verificador de identidade do estafeta também. Push feito, o CI sobe o versionCode.

## Segurança, apanhado e fechado durante a missão

Descobri que o Supabase dá permissão de execução a utilizadores anónimos em cada função nova, e que "revoke from public" não a tira. Durante uns quatro minutos as funções internas desta missão, incluindo a que escreve a ficha de qualquer motorista, estiveram chamáveis sem sessão. Fechei nome a nome na migração `20260923183704` e confirmei: anónimo só chega à função da página pública. Confirmei também que nada foi escrito nessa janela: zero fichas e zero motoristas alterados.

## Dinheiro

Nada desta missão mexe em preços, comissões, pagamentos ou tokens. O recibo só lê valores já gravados.

## Encontrado fora do âmbito, não corrigido

Um. A tabela `tvde_driver_documents` nunca pode receber documentos do motorista: a regra de acesso compara com o id da conta, mas a coluna aponta para a linha do motorista, que é outro número em todos os motoristas.

Dois. O `deploy-cloudflare.sh` do bora-site não copia o ficheiro `_headers`, por isso a regra de não guardar em cache as páginas de provas nunca chegou ao ar.

Três. A função `notify-admin-message` só existe em produção, não está no repositório.

Quatro. A chave do Resend só envia; não deixa ler o estado de um e-mail, por isso a entrega só se prova pela caixa de correio.

Cinco. Há corridas finalizadas em que o ganho do motorista mais a parte da Bora não dá o valor da viagem, por exemplo 2,00 € de valor com 4,40 € mais 1,60 € repartidos, em corridas com paragens ou pacote.

## Para o Danilo

Só uma coisa, e é no PC: publicar o bora-site com `bash deploy-cloudflare.sh` depois de juntar o pedido 1. O loop do PC pode fazê-lo sozinho; deixei a ordem no Córtex. E quando a empresa tiver NIF e licença de operador de plataforma, escreve-os no ecrã "Documentos dos motoristas" e o "em processo" desaparece de todo o lado.

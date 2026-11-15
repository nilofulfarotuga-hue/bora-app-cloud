# Publicar o #19: pronto e o que falta (15/11, 15:20)

Pronto: notas da versão em PT-PT para a Play (454 de 500 letras), a App Store (842) e a web, e o texto para colar nas notas do iPhone (NOTAS_DA_VERSAO.md).
Pronto: juntar não dá conflitos; o #19 está 93 commits à frente e 0 atrás da produção e não mexe no número da versão.
Falta: os testes do iPhone acabarem verdes no último commit (às 15:20 a #305 estava à espera; a última verde foi a #289). A "302" da ordem do Danilo foi cancelada por entrar um commit novo.
Falta: trocar o ios/notas_de_versao.json antes de juntar, senão a 1.0.44 sai com as notas da 1.0.43.
Falta no servidor antes de publicar: caixas 29, 52, 33 e 51, e as de dinheiro 30, 31 e 32 (com a migração C3 antes da 32), só com testes verdes.
Pode ficar para depois: caixas 48, 49 e 50, a P5.3 da 63, e a 64.
Depois da web: pôr app.boraguarda.com/apagar-conta na Play Console; hoje esse endereço ainda mostra a app e não a página.
Cuidado: o CI não envia as Novidades para a Play, o teste do Android no emulador só corre depois de juntar, e a web e o iPhone publicam mesmo que o Android falhe.
Nota: a entrada com a Apple está ligada no servidor desde as 14:26 (registo 9283); não vai nas notas porque não é novidade desta versão.

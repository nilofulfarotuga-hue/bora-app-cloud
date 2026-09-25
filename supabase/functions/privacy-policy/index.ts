import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (_req: Request) => {
  const html = `<!DOCTYPE html>
<html lang="pt">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Política de Privacidade — Bora App</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; line-height: 1.6; }
    h1 { color: #16A34A; }
    h2 { color: #16A34A; margin-top: 30px; }
    p { margin: 10px 0; }
  </style>
</head>
<body>
  <h1>Política de Privacidade</h1>
  <p><strong>Bora App</strong> — pt.boraapp.bora</p>
  <p><em>Última atualização: 17 de junho de 2026</em></p>

  <h2>1. Informações que Recolhemos</h2>
  <p>A Bora App recolhe as seguintes informações quando utiliza a nossa aplicação:</p>
  <ul>
    <li>Nome, endereço de email e número de telefone</li>
    <li>Morada de entrega e localização geográfica (para serviços de entrega)</li>
    <li>Informações de pagamento (processadas de forma segura pelo Stripe)</li>
    <li>Histórico de encomendas e preferências</li>
    <li>Dados do dispositivo e token de notificação (Firebase FCM)</li>
  </ul>

  <h2>2. Como Utilizamos as Suas Informações</h2>
  <p>Utilizamos os seus dados para:</p>
  <ul>
    <li>Processar e entregar as suas encomendas</li>
    <li>Enviar notificações sobre o estado das encomendas</li>
    <li>Melhorar os nossos serviços</li>
    <li>Cumprir obrigações legais e fiscais</li>
    <li>Comunicar promoções e novidades (apenas com o seu consentimento)</li>
  </ul>

  <h2>3. Partilha de Dados</h2>
  <p>Os seus dados são partilhados apenas com:</p>
  <ul>
    <li><strong>Parceiros de entrega</strong> — nome e morada para concluir a entrega</li>
    <li><strong>Stripe</strong> — processamento seguro de pagamentos</li>
    <li><strong>Google Firebase</strong> — notificações push</li>
    <li><strong>Supabase</strong> — armazenamento seguro de dados</li>
  </ul>
  <p>Nunca vendemos os seus dados a terceiros.</p>

  <h2>4. Segurança dos Dados</h2>
  <p>Utilizamos encriptação SSL/TLS, Row Level Security (RLS) na base de dados e autenticação segura para proteger os seus dados. Os pagamentos são processados pelo Stripe e nunca armazenamos dados de cartão de crédito.</p>

  <h2>5. Os Seus Direitos (RGPD)</h2>
  <p>Ao abrigo do Regulamento Geral de Proteção de Dados (RGPD), tem direito a:</p>
  <ul>
    <li>Aceder aos seus dados pessoais</li>
    <li>Corrigir dados incorretos</li>
    <li>Solicitar a eliminação dos seus dados</li>
    <li>Opor-se ao tratamento dos seus dados</li>
    <li>Portabilidade dos dados</li>
  </ul>

  <h2>6. Retenção de Dados</h2>
  <p>Conservamos os seus dados enquanto mantiver uma conta ativa. Após eliminação da conta, os dados são removidos no prazo de 30 dias, exceto onde exigido por lei para fins fiscais ou legais.</p>

  <h2>7. Cookies e Rastreamento</h2>
  <p>A aplicação móvel Bora App não utiliza cookies. Utilizamos apenas dados técnicos essenciais ao funcionamento do serviço.</p>

  <h2>8. Menores</h2>
  <p>A Bora App não é destinada a menores de 18 anos. Não recolhemos intencionalmente dados de menores.</p>

  <h2>9. Contacto</h2>
  <p>Para exercer os seus direitos ou esclarecer dúvidas sobre privacidade, contacte-nos:</p>
  <p>📧 <strong>privacidade@boraapp.pt</strong></p>
  <p>A Bora App é operada em conformidade com a legislação portuguesa e europeia de proteção de dados.</p>

  <h2>10. Alterações a Esta Política</h2>
  <p>Podemos atualizar esta política periodicamente. Notificaremos os utilizadores de alterações significativas através da aplicação.</p>

  <hr style="margin-top:40px;">
  <p style="color:#888;font-size:0.9em;">© 2026 Bora App. Todos os direitos reservados.</p>
</body>
</html>`;

  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' }
  });
});

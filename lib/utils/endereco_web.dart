// lib/utils/endereco_web.dart — troca o endereço na barra do navegador sem
// recarregar a página (history.replaceState). Fora da web não faz nada.
//
// Serve o ecrã de nova palavra-passe (16/11/2026): depois de o link do email
// ser gasto, o `token_hash` sai da barra para recarregar a página não voltar
// a tentar um link já usado e mostrar "Ligação inválida".
import 'endereco_web_stub.dart'
    if (dart.library.html) 'endereco_web_browser.dart' as impl;

/// Põe [fragmento] (ex.: `/` ou `/redefinir-palavra-passe`) como único
/// fragmento do endereço actual, sem query string. Nunca lança.
void trocarEnderecoWeb(String fragmento) => impl.trocarEnderecoWebImpl(fragmento);

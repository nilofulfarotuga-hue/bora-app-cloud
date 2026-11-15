import 'package:supabase_flutter/supabase_flutter.dart';

/// Há sessão iniciada? Nunca lança: sem Supabase iniciado (testes, arranque)
/// conta como "não há".
///
/// app-15-11 (varredura 9166, n.º 17): o visitante sem conta chamava funções
/// que pedem sessão e o servidor recusava-as ~400 vezes por dia (401). Quem
/// usa isto sai antes de ir ao servidor, com o mesmo resultado de antes.
bool temSessao() {
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

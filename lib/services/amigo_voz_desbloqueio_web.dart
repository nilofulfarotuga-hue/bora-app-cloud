// O AMIGO (09/11/2026, m11 adendo 4): o Safari do iPhone (e o Chrome do Android) só deixam a página
// falar (speechSynthesis) depois de um toque da pessoa. Regista, no próprio documento, um ouvinte do
// PRIMEIRO toque/clique/tecla que diz uma fala vazia — corre dentro do gesto (o ouvinte é do navegador,
// não espera pelo Flutter) e desbloqueia a voz; as falas seguintes do Amigo já saem.
// (Vive em Dart e não no web/index.html porque esse ficheiro tem uma chave e a trava não o deixa gravar.)
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _instalado = false;
const _eventos = ['touchend', 'pointerup', 'click', 'keydown'];

void amigoDesbloquearVozNoPrimeiroToque() {
  if (_instalado) return;
  _instalado = true;
  try {
    final doc = globalContext['document'] as JSObject?;
    if (doc == null || !globalContext.has('speechSynthesis')) return;
    var feito = false;
    late final JSFunction ouvinte;
    ouvinte = ((JSAny? _) {
      if (feito) return;
      feito = true;
      try {
        final synth = globalContext['speechSynthesis'] as JSObject;
        final criar = globalContext['SpeechSynthesisUtterance'] as JSFunction;
        final u = criar.callAsConstructor<JSObject>(' '.toJS);
        u['volume'] = 0.toJS;
        u['lang'] = 'pt-PT'.toJS;
        synth.callMethod('speak'.toJS, u);
        synth.callMethod('getVoices'.toJS);
        globalContext['__amigoVozDesbloqueada'] = true.toJS;
      } catch (_) {}
      for (final t in _eventos) {
        doc.callMethod('removeEventListener'.toJS, t.toJS, ouvinte, true.toJS);
      }
    }).toJS;
    for (final t in _eventos) {
      doc.callMethod('addEventListener'.toJS, t.toJS, ouvinte, true.toJS);
    }
  } catch (_) {
    // sem isto o Amigo continua a funcionar: só a 1.ª fala pode precisar de um toque
  }
}

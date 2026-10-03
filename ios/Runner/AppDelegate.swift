import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Chave do Google Maps para iOS (missão ios-lancamento, 2026-09-08).
    //
    // PORQUE ISTO TEM DE ESTAR AQUI: no Android o `google_maps_flutter` lê a
    // chave do AndroidManifest, mas no iOS o SDK exige que ela seja entregue
    // ao GMSServices ANTES de o motor Flutter arrancar. Sem esta linha o mapa
    // desenha-se cinzento e vazio — e o mapa aparece no acompanhamento do
    // pedido, que é exactamente o que o revisor da Apple vai abrir.
    //
    // A chave NÃO está no código: o repositório é público. Vem de uma entrada
    // do Info.plist (`GoogleMapsApiKey`), que por sua vez é preenchida no build
    // a partir da definição `GOOGLE_MAPS_API_KEY`, injectada pelo CI a partir
    // de um segredo. Em desenvolvimento local, sem definição, fica vazia e o
    // mapa não carrega — mas a app arranca na mesma, em vez de rebentar.
    if let chave = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
       !chave.isEmpty,
       !chave.hasPrefix("$(") {
      GMSServices.provideAPIKey(chave)
    } else {
      NSLog("[Bora] Sem chave do Google Maps para iOS — o mapa vai aparecer vazio.")
    }

    // Janela do Flutter para o Stripe (2026-10-03, cartão "só a rodar").
    //
    // PORQUE: o plugin do Stripe (stripe_ios 11.5) procura de onde apresentar
    // a folha do cartão em `UIApplication.shared.delegate?.window`. Com UIScene
    // (Info.plist → SceneDelegate) a janela vive na cena e este `window` fica
    // vazio; o plugin cai num `UIViewController()` solto, fora de qualquer
    // janela, a folha nunca aparece e `presentPaymentSheet` nunca devolve —
    // o cliente vê o botão a rodar para sempre (Divan 02/10, Danilo 21/09:
    // nenhum cartão de iPhone passou). No Android não há cena, por isso lá
    // funcionava. Assim que a janela do Flutter fica activa, damo-la ao
    // AppDelegate; o desafio 3D Secure usa o mesmo caminho.
    NotificationCenter.default.addObserver(
      forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { [weak self] nota in
      guard let janela = nota.object as? UIWindow,
            janela.rootViewController is FlutterViewController else { return }
      self?.window = janela
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Garante que `self.window` é a janela visível do Flutter. Devolve `false`
  /// se não houver nenhuma — a app trata isso como "o cartão não vai abrir".
  @discardableResult
  func ligarJanelaAoStripe() -> Bool {
    if let actual = window, actual.windowScene != nil, actual.rootViewController != nil {
      return true
    }
    let janelas = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    if let flutter = janelas.first(where: { $0.rootViewController is FlutterViewController })
        ?? janelas.first(where: { $0.isKeyWindow }) {
      window = flutter
      return true
    }
    return false
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Canal nativo `pt.boraapp.bora/native` — o par iOS do que a MainActivity.kt
    // já faz no Android (missão paridade-3-plataformas, 2026-09-21).
    //
    // PORQUE EXISTE: o logger de crash do Flutter (main.dart) pede
    // `getDeviceDiagnostics` por este canal para preencher `app_version` e
    // `device_model` em `debug_crash_logs`. No Android a MainActivity responde;
    // no iOS não havia ninguém do outro lado, e 223 crashes de iPhone
    // chegaram à base sem versão nem modelo — impossível saber a que build
    // pertence um crash. Os outros métodos do canal (só Android:
    // canUseFullScreenIntent, etc.) continuam a devolver "não implementado",
    // exactamente como antes.
    let canal = FlutterMethodChannel(
      name: "pt.boraapp.bora/native",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    canal.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getDeviceDiagnostics":
        result(AppDelegate.diagnosticoDoAparelho())
      // Pagamento com cartão (2026-10-03): antes de abrir a folha do Stripe a
      // app pede para ligar a janela; depois pergunta se a folha apareceu
      // mesmo. Se não aparecer no tempo limite, a app avisa o cliente em vez
      // de rodar para sempre.
      case "prepararFolhaStripe":
        result(self?.ligarJanelaAoStripe() ?? false)
      case "folhaStripeVisivel":
        result(self?.window?.rootViewController?.presentedViewController != nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Versão da app, modelo do aparelho e versão do iOS — o mesmo formato que
  /// o Android devolve ("1.0.1+115", "Apple iPhone15,2", "iOS 18.1").
  private static func diagnosticoDoAparelho() -> [String: String] {
    let info = Bundle.main.infoDictionary
    let nome = info?["CFBundleShortVersionString"] as? String ?? ""
    let numero = info?["CFBundleVersion"] as? String ?? ""

    // Identificador de hardware (ex.: "iPhone15,2"); UIDevice.model só diz
    // "iPhone". Lido de utsname sem ponteiros: percorre-se a tupla por Mirror.
    var sistema = utsname()
    uname(&sistema)
    let maquina = Mirror(reflecting: sistema.machine).children.reduce(into: "") { acc, filho in
      if let valor = filho.value as? Int8, valor != 0 {
        acc.append(Character(UnicodeScalar(UInt8(bitPattern: valor))))
      }
    }
    let modelo = maquina.isEmpty ? UIDevice.current.model : maquina

    return [
      "app_version": "\(nome)+\(numero)",
      "device_model": "Apple \(modelo)",
      // A coluna chama-se android_version por herança; aqui vai o sistema.
      "android_version": "iOS \(UIDevice.current.systemVersion)",
    ]
  }
}

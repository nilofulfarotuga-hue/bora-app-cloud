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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    canal.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceDiagnostics":
        result(AppDelegate.diagnosticoDoAparelho())
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

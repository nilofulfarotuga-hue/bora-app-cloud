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
  }
}

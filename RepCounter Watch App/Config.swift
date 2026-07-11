import Foundation

// Configuracion de la app. Cambia el token por el tuyo (GYM_DEVICE_TOKEN del
// .env del servidor). La URL ya es la de tu Life Hub.
enum Config {
    static let baseURL = "https://dmghub.app"
    static let deviceToken = "edb06d6e6ba08c54649d5825564034f0"
    // Clave de la app (APP_PASSWORD): para marcar hábitos/comidas como hechos,
    // que van por los endpoints normales /api/* con Bearer (el device token
    // solo vale para /api/gym/device/*).
    static let appPassword = "BpbEXYlKaUh04zTMydiIzmJ0G32TARTR"
}

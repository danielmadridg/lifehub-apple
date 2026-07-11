# Life Hub iOS — app nativa en SwiftUI

Reescritura nativa de la SPA de Life Hub. Habla con el MISMO backend
FastAPI del VPS (`/api/*`, puerto 8011). Cero cambios de servidor.

## Estructura

```
ios/
├── project.yml                    # Config de XcodeGen (genera el .xcodeproj)
└── LifeHub/
    ├── App/
    │   ├── LifeHubApp.swift       # @main + AppState (sesión, URL servidor)
    │   ├── AuthGateView.swift     # Pantalla de clave (valida contra /api/today)
    │   └── RootView.swift         # TabView: Hoy · Gym · Comida · Dinero · Más
    ├── Core/
    │   ├── APIClient.swift        # Cliente HTTP (Bearer, 401 → logout, multipart)
    │   ├── Endpoints.swift        # Un método por endpoint (espejo de api.ts)
    │   ├── Models.swift           # Structs Codable (espejo de types.ts)
    │   ├── Keychain.swift         # La clave vive en Keychain, no en UserDefaults
    │   ├── Me.swift               # Datos de Daniel + BMR/TDEE + discos (espejo de me.ts)
    │   ├── Theme.swift            # Café oscuro + naranja brasa, serif display
    │   └── Components.swift       # Screen, LoadView, ErrorCard, CoachCard, skeletons
    └── Features/
        ├── Home/                  # Saludo + coach IA + pendientes + resumen
        ├── Routines/              # Hoy (marcar/deshacer, rachas) + heatmap 28 días
        ├── Nutrition/             # Macros (anillos + IA), dieta semanal, compra
        ├── Gym/                   # Rutinas, entreno (recomendación, PRs, descanso
        │                          #   2:30, discos/lado), progreso 1RM, salud
        ├── Tasks/                 # Tareas + notas rápidas
        ├── Modules/               # Correo, Agenda, Estudios
        ├── Finance/               # Patrimonio EUR + curva + Alpaca/Bitvavo
        └── Settings/              # CRUD de hábitos, conexiones, sesión
```

## Compilar (necesitas un Mac con Xcode 15+)

```bash
brew install xcodegen
cd ios
xcodegen generate        # crea LifeHub.xcodeproj
open LifeHub.xcodeproj
```

Sin XcodeGen: crea en Xcode un proyecto iOS App (SwiftUI, iOS 17) llamado
`LifeHub` y arrastra la carpeta `LifeHub/` al target. Añade al Info.plist:
`NSAppTransportSecurity > NSAllowsArbitraryLoads = YES` (el backend va por
HTTP) y `NSPhotoLibraryUsageDescription`.

Para instalarla en el iPhone sin pagar cuenta de desarrollador: firma con tu
Apple ID (Signing & Capabilities → Team personal). Caduca cada 7 días; con
cuenta de pago, no.

## Primer arranque

1. La app pide clave y servidor (por defecto `http://46.225.208.226:8011`).
2. La clave es `APP_PASSWORD` del backend. Se valida contra `/api/today`
   y se guarda en Keychain.
3. Un 401 en cualquier llamada cierra sesión y vuelve a la pantalla de clave.

## Decisiones

- **Mismo backend, cero duplicación de lógica**: recomendación de peso,
  rachas, PRs y cachés viven en el servidor. La app solo pinta.
- **Modelos en snake_case**: espejo 1:1 del JSON del backend y de
  `frontend/src/types.ts`. Menos bugs de mapeo a cambio de estilo Swift.
- **Pull-to-refresh universal**: `Screen` recrea su contenido al tirar
  (o llama al `refresh` que le pasen), y los `.task` de carga se relanzan.
- **Fotos de progreso**: `AsyncImage` con `?token=` en la URL (las imágenes
  no mandan header Authorization — mismo truco que la web).
- **Notificaciones**: siguen llegando por Telegram desde el backend. El
  módulo web-push del navegador no aplica en app nativa; si algún día
  quieres push de APNs, es proyecto aparte.

## Qué NO tiene (a propósito)

- Cola offline de series (la web la tiene en localStorage). Primera
  versión nativa: requiere red en el gym. Fácil de añadir después.
- Pitido WebAudio del temporizador: se sustituye por hápticos.
- Modo carrusel de la barra de navegación: TabView nativa.

# RepCounter — contador de reps para Apple Watch → Life Hub

App de watchOS que cuenta repeticiones por el movimiento de la muñeca y las
registra en Life Hub (tu backend). Cuenta con `CoreMotion`, mantiene el reloj
despierto con una sesión de HealthKit, y manda cada serie a la API.

## Qué ya está hecho (backend, en producción)

- `GET  /api/gym/device/today` → rutina de hoy + ejercicios (con peso recomendado).
- `POST /api/gym/device/set`   → registra una serie `{exercise_id, weight, reps}`;
  crea/usa el entreno activo solo. Aparece igual que si la metieras en la app.
- Auth por cabecera **`X-Device-Token`** (no usa tu contraseña principal).
  El valor está en el `.env` del servidor como `GYM_DEVICE_TOKEN` (te lo paso yo).

## Requisitos

- Mac **Apple Silicon** con **macOS 26** + **Xcode 26.3**.
- iPhone + Apple Watch **emparejados**, ambos con **Modo desarrollador** ON.
- Tu Apple ID (gratis vale; caduca a los 7 días. Con Developer Program dura 1 año).

## Pasos en Xcode

1. **Crear proyecto:** File → New → Project → **watchOS → App** → nombre
   `RepCounter`, interface **SwiftUI**.
2. **Añadir estos archivos** al target de la Watch App (arrástralos al proyecto y
   marca "Copy items" + target = Watch App). Borra el `ContentView.swift` de
   ejemplo:
   - `RepCounterApp.swift` (entrada + las 2 vistas)
   - `Config.swift`, `Models.swift`, `API.swift`
   - `RepDetector.swift`, `WorkoutSession.swift`, `Store.swift`
3. **Pega tu token** en `Config.swift` → `deviceToken = "..."` (te lo paso yo).
4. **Capabilities** (target Watch App → Signing & Capabilities → **+ Capability**):
   - **HealthKit**.
   - **Background Modes** → marca **Workout processing** (para que no se duerma).
5. **Info.plist** (o pestaña Info del target) → añade estas descripciones:
   - `NSHealthShareUsageDescription` = "Para mantener el conteo activo durante la serie."
   - `NSHealthUpdateUsageDescription` = "Para la sesión de entrenamiento."
   - `NSMotionUsageDescription` = "Para contar las repeticiones por el movimiento."
6. **Firmar:** Signing & Capabilities → "Automatically manage signing" → tu Apple ID.
7. **Elige tu Apple Watch** como destino (arriba) y pulsa **▶ Run**. La 1ª vez el
   iPhone/Watch pedirá confiar el certificado.

> Atajo: con **Claude dentro de Xcode (26.3)** puedes decirle *"crea el proyecto
> watchOS con estos archivos, añade HealthKit + Workout processing + las claves de
> Info.plist y arréglame los errores de compilación"* y te lo deja montado.

## Cómo se usa

1. Abre la app en el reloj → carga los ejercicios de hoy.
2. Toca un ejercicio → ajusta el **peso con la corona** (sale el recomendado) →
   **Empezar serie**.
3. Haz las reps (las cuenta en pantalla) → **Terminar serie** → se guarda en Life Hub.

## Calibración (el bucle contigo)

El conteo se afina en `RepDetector.swift`, 3 parámetros:
- `threshold` (1.15) — cuánto movimiento cuenta como rep. Sube si cuenta de más.
- `refractory` (0.45 s) — tiempo mínimo entre reps. Sube si dobla conteos rápidos.
- `rearmFactor` (0.6) — cuándo se "rearma" para la siguiente.

Me dices en qué ejercicio cuenta mal (ej. "curl contó 9 de 10") y ajusto los
valores (o metemos un modelo Core ML por ejercicio). Precisión esperada:
~75-85% en curl/press, peor en compuestos/pierna.

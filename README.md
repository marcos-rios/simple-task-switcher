# simple-task-switcher

Task switcher para macOS, solo texto (sin íconos ni previews), open source y para uso personal. AppKit, sin dependencias externas.

## Estado

Fase 3: archivo de configuración, varias pantallas, apps ocultas o minimizadas, filtro de apps sin ventanas, instalación y arranque al iniciar sesión.

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Proyecto base, Option+Tab, panel con lista de apps | hecha |
| 2 | Orden MRU, interacción completa de teclado | hecha |
| 3 | Config, varias pantallas, apps ocultas o minimizadas, pantalla completa, filtros, login | en prueba |
| 4 | (opcional) Ventanas individuales | pendiente |
| 5 | (opcional) Reemplazar Cmd+Tab con CGEventTap | pendiente |

## Uso

| Tecla | Acción |
|---|---|
| Option+Tab | Abre el switcher con la 2.ª app seleccionada; con Option apretado, cada Tab avanza |
| Shift+Option+Tab | Retrocede (si el panel está cerrado, lo abre con la última app seleccionada) |
| Soltar Option | Activa la app seleccionada |
| ↑ / ↓, Tab / Shift+Tab | Mueven la selección |
| Enter | Activa la app seleccionada |
| Esc o clic afuera | Cancela |

El modificador se puede cambiar a Control con `hotkey-modifier` (ver Configuración).

Desde el menú, "Show Switcher" abre el panel sin Option apretado. En ese caso queda abierto hasta Enter, Esc o un clic afuera.

Si la app elegida no tiene ninguna ventana visible en el Space actual (minimizada, en otro Space o sin ventanas), se activa como si hicieras clic en su ícono del Dock. AppKit des-minimiza una ventana en ese caso. Las apps ocultas con ⌘H se muestran antes de activarlas.

## Configuración

Archivo: `~/.config/simple-task-switcher/config`. Es opcional: si no existe, se usan los defaults.

- En el menú de la barra, **Open Config** crea el archivo (con todas las claves comentadas y sus defaults) si no existe, y lo abre.
- **Reload Config** vuelve a leerlo. También se lee al arrancar. No hay recarga automática.
- **Formato:** líneas `clave = valor`.
  - Las líneas que empiezan con `#` son comentarios y las vacías se ignoran.
  - No hay comillas, secciones ni escapes.
  - Las listas se arman repitiendo la clave.
- **Errores:** una clave desconocida o un valor inválido se ignoran, y se escribe una línea en la consola con el número de línea y el motivo. Se ve en la consola de Xcode o en Console.app filtrando por `SimpleTaskSwitcher`.

| Clave | Valores | Default | Descripción |
|---|---|---|---|
| `hotkey-modifier` | `option`, `control` | `option` | Modificador que se mantiene con Tab. `command` no está soportado: el sistema consume Cmd+Tab antes (fase 5). |
| `screen` | `mouse`, `focused` | `mouse` | Pantalla del panel: la del puntero o la de la ventana al frente. |
| `show-hidden-apps` | `true`, `false` | `true` | Mostrar apps ocultas con ⌘H. |
| `show-windowless-apps` | `true`, `false` | `true` | Mostrar apps sin ventanas. Con `false` se ocultan (es una heurística, ver Permisos). |
| `exclude` | bundle ID | ninguno | No listar esa app. Repetible. |
| `launch-at-login` | `true`, `false` | `false` | Arrancar al iniciar sesión. Solo tiene efecto con la app en `/Applications`. |
| `font-size` | entero 10–40 | `15` | Tamaño de letra de la lista. |

Ejemplo:

```
hotkey-modifier = option
screen = focused
show-windowless-apps = false
exclude = com.apple.finder
exclude = com.apple.systempreferences
launch-at-login = true
```

Para saber el bundle ID de una app: `osascript -e 'id of app "Nombre"'`.

## Requisitos

- macOS 14 o superior, Xcode (probado con Xcode 27.2, Swift 6).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) solo si cambiás `project.yml`: `brew install xcodegen`.

## Compilar y correr

1. Abrí `SimpleTaskSwitcher.xcodeproj` en Xcode.
2. Elegí el esquema **SimpleTaskSwitcher**, con destino **My Mac**.
3. Apretá ⌘R.

El `.xcodeproj` se genera a partir de `project.yml`. Si editás `project.yml`, regeneralo con `xcodegen generate`. Agregar archivos nuevos dentro de `Sources/` también requiere regenerar.

Compilar desde la terminal sin cambiar `xcode-select`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SimpleTaskSwitcher.xcodeproj -scheme SimpleTaskSwitcher build
```

## Instalar para uso diario

```sh
make install
```

`make install`:
1. Compila en Release a `build/`.
2. Cierra la instancia que esté corriendo.
3. Copia la app a `/Applications` y la abre.

`make build` solo compila. `make project` regenera el `.xcodeproj`.

- La firma es ad-hoc. Una app compilada localmente no tiene atributo de cuarentena, así que Gatekeeper no la bloquea.
- Para arrancar al iniciar sesión, usá `launch-at-login = true` y después Reload Config. La app usa `SMAppService.mainApp` (API pública de macOS 13+) y aparece en Ajustes > General > Ítems de inicio. Si macOS pide aprobación, queda una línea en la consola y se activa ahí.
- Si corrés la app desde Xcode, `launch-at-login` se ignora, para no registrar una copia temporal de DerivedData.

## Estructura

```
project.yml               Spec de XcodeGen (configuración del proyecto)
Sources/main.swift        Punto de entrada manual (sin storyboard ni nib)
Sources/AppDelegate.swift Barra de menú, hotkeys, MRU, filtros, pantallas, activación, login
Sources/Config.swift      Archivo de configuración: defaults, parser y plantilla
Sources/HotKey.swift      Hotkey global con Carbon RegisterEventHotKey
Sources/SwitcherPanel.swift Panel flotante non-activating
Makefile                  make build / make install / make project
```

## Configuración del proyecto

- `LSUIElement = YES`: sin ícono en el Dock ni barra de menú propia.
- Sin storyboard ni nib (`NSPrincipalClass = NSApplication` y `main.swift` manual).
- App Sandbox desactivado y Hardened Runtime activado.
- Bundle ID fijo: `dev.simpletaskswitcher.SimpleTaskSwitcher`.
- Deployment target: macOS 14. Swift 6 con strict concurrency. También compila en Swift 5 y en Swift 6 con default isolation `MainActor`.
- Firma ad-hoc (`-`) mientras no haga falta ningún permiso. La build Release sale con Hardened Runtime (`flags=0x10002(adhoc,runtime)`). La Debug de Xcode no lo aplica.

## Permisos

**Fase 1: ninguno.** `RegisterEventHotKey` (Carbon) es una API pública que registra una combinación concreta. El sistema le avisa a la app solo cuando se aprieta esa combinación, no le deja leer el resto del teclado, así que no pide Input Monitoring ni Accessibility. Para listar apps con `NSWorkspace.runningApplications` tampoco hace falta permiso, y mostrar un panel propio tampoco. Por eso alcanza con la firma ad-hoc, aunque cambie el cdhash en cada build.

**Fase 2: en principio, ninguno.** Para detectar cuándo se suelta Option, un timer de unos 30 ms lee `NSEvent.modifierFlags`, una propiedad de clase que no requiere permisos. Los Tab siguientes llegan como el mismo hotkey.
- Incertidumbre: no está confirmado que Shift+Option+Tab llegue. En macOS 15 hubo restricciones con hotkeys que usan solo Option.
- Si Option+Tab no llega, hay dos fallbacks: otra combinación (por ejemplo Ctrl+Option+Tab) o `CGEventTap`, que sí pide permisos.
- Activación: desde macOS 14 es cooperativa, así que `NSRunningApplication.activate()` llamada desde una app inactiva puede no funcionar. El fallback público es `NSWorkspace.openApplication(at:configuration:)` con `activates = true`.

**Fase 3: ninguno.**
- **Detección de ventanas:** se usa `CGWindowListCopyWindowInfo`, pero solo para leer el PID dueño, la capa, el alpha y los bounds de cada ventana, que no requieren Screen Recording. Solo los títulos (`kCGWindowName`) lo requieren, y no se usan.
  - Sirve para filtrar apps sin ventanas y para `screen = focused`.
  - Una app "tiene ventanas" si alguna ventana suya cumple tres condiciones: capa 0, alpha mayor que 0 y por lo menos 50×50.
  - Cuentan también las minimizadas y las que están en otros Spaces.
- **Minimizadas:** des-minimizar una ventana concreta requiere Accessibility. Sin permisos no se puede distinguir una ventana minimizada de una en otro Space. Por eso se usa la vía del Dock (`NSWorkspace.openApplication`, que manda "reopen").
- **Ocultas:** `NSRunningApplication.unhide()` no pide permisos.
- **Login:** `SMAppService` no pide permisos de TCC. Puede pedir aprobación en Ítems de inicio.

**Fase 4: Screen Recording**, para leer títulos de ventana con `CGWindowListCopyWindowInfo`. La alternativa es sacarlos con la API de Accessibility.

**Fase 5: Accessibility**, para un event tap activo que consuma Cmd+Tab. Input Monitoring alcanza solo para un tap listen-only, que no consume la tecla.

### Firma estable (desde la fase 4)

TCC (el sistema de permisos) identifica la app por su *designated requirement*. Con firma ad-hoc, ese requirement es el cdhash, que cambia en cada build, y entonces macOS vuelve a pedir el permiso. Para evitarlo:

- Firmar con **Apple Development** usando el Personal Team (Apple ID gratuito) o con un certificado autofirmado de Keychain, y mantener el bundle ID fijo.
- Comprobarlo antes y después de recompilar: `codesign -d -r- SimpleTaskSwitcher.app`. El requirement tiene que quedar igual.
- No se asume que renovar el certificado invalide los permisos. Se verifica con el mismo comando.
- Si un permiso se traba: `tccutil reset <Servicio> dev.simpletaskswitcher.SimpleTaskSwitcher`. El servicio es, por ejemplo, `Accessibility` o `ScreenCapture`.

# simple-task-switcher

Task switcher para macOS, solo texto (sin íconos ni previews), open source y para uso personal. AppKit, sin dependencias externas.

## Estado

Fase 1: Option+Tab abre un panel flotante con la lista de apps abiertas.

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Proyecto base, Option+Tab, panel con lista de apps | en prueba |
| 2 | Orden MRU, interacción completa de teclado | pendiente |
| 3 | Varias pantallas, apps ocultas o minimizadas, pantalla completa, filtros | pendiente |
| 4 | (opcional) Ventanas individuales | pendiente |
| 5 | (opcional) Reemplazar Cmd+Tab con CGEventTap | pendiente |

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

## Estructura

```
project.yml               Spec de XcodeGen (configuración del proyecto)
Sources/main.swift        Punto de entrada manual (sin storyboard ni nib)
Sources/AppDelegate.swift Ícono en la barra de menú, hotkey, armado de la lista
Sources/HotKey.swift      Hotkey global con Carbon RegisterEventHotKey
Sources/SwitcherPanel.swift Panel flotante non-activating
```

## Configuración del proyecto

- `LSUIElement = YES`: sin ícono en el Dock ni barra de menú propia.
- Sin storyboard ni nib (`NSPrincipalClass = NSApplication` y `main.swift` manual).
- App Sandbox desactivado y Hardened Runtime activado.
- Bundle ID fijo: `dev.simpletaskswitcher.SimpleTaskSwitcher`.
- Deployment target: macOS 14. Swift 6 con strict concurrency. También compila en Swift 5 y en Swift 6 con default isolation `MainActor`.
- Fase 1: firma ad-hoc (`-`). Nota: Xcode no aplica Hardened Runtime cuando firma ad-hoc. Se aplica al firmar con Apple Development.

## Permisos

**Fase 1: ninguno.** `RegisterEventHotKey` (Carbon) es una API pública que registra una combinación concreta. El sistema le avisa a la app solo cuando se aprieta esa combinación, no le deja leer el resto del teclado, así que no pide Input Monitoring ni Accessibility. Para listar apps con `NSWorkspace.runningApplications` tampoco hace falta permiso, y mostrar un panel propio tampoco. Por eso alcanza con la firma ad-hoc, aunque cambie el cdhash en cada build.

**Fase 2: en principio, ninguno.** Para detectar cuándo se suelta Option, un timer de unos 30 ms lee `NSEvent.modifierFlags`, una propiedad de clase que no requiere permisos. Los Tab siguientes llegan como el mismo hotkey.
- Incertidumbre: no está confirmado que Shift+Option+Tab llegue. En macOS 15 hubo restricciones con hotkeys que usan solo Option.
- Si Option+Tab no llega, hay dos fallbacks: otra combinación (por ejemplo Ctrl+Option+Tab) o `CGEventTap`, que sí pide permisos.
- Activación: desde macOS 14 es cooperativa, así que `NSRunningApplication.activate()` llamada desde una app inactiva puede no funcionar. El fallback público es `NSWorkspace.openApplication(at:configuration:)` con `activates = true`.

**Fase 4: Screen Recording**, para leer títulos de ventana con `CGWindowListCopyWindowInfo`. La alternativa es sacarlos con la API de Accessibility.

**Fase 5: Accessibility**, para un event tap activo que consuma Cmd+Tab. Input Monitoring alcanza solo para un tap listen-only, que no consume la tecla.

### Firma estable (desde la fase 4)

TCC (el sistema de permisos) identifica la app por su *designated requirement*. Con firma ad-hoc, ese requirement es el cdhash, que cambia en cada build, y entonces macOS vuelve a pedir el permiso. Para evitarlo:

- Firmar con **Apple Development** usando el Personal Team (Apple ID gratuito) o con un certificado autofirmado de Keychain, y mantener el bundle ID fijo.
- Comprobarlo antes y después de recompilar: `codesign -d -r- SimpleTaskSwitcher.app`. El requirement tiene que quedar igual.
- No se asume que renovar el certificado invalide los permisos. Se verifica con el mismo comando.
- Si un permiso se traba: `tccutil reset <Servicio> dev.simpletaskswitcher.SimpleTaskSwitcher`. El servicio es, por ejemplo, `Accessibility` o `ScreenCapture`.

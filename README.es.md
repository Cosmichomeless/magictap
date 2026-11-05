# MagicTap

**Tocar para hacer clic en el Magic Mouse de Apple, en macOS.**

macOS solo ofrece *Tocar para hacer clic* en trackpads. MagicTap es una pequeña
app de barra de menús, de código abierto, que lo añade al Magic Mouse:

| Gesto | Acción |
|---|---|
| Toque con un dedo | Clic izquierdo |
| Toque con dos dedos | Clic derecho |

Los clics físicos siguen funcionando igual. Sin icono en el Dock, sin ventanas,
sin telemetría y sin acceso a la red.

[Read in English](README.md)

> **Estado: prototipo inicial (v0.1).** La lógica de reconocimiento tiene tests
> unitarios, pero los umbrales están ajustados "a ojo" y la capa multitáctil usa
> una API privada de Apple. Mira [Limitaciones](#limitaciones).

## Requisitos

- macOS 13 o superior (desarrollado en macOS 27)
- Xcode o el toolchain de Swift (para compilar desde el código)
- Un Apple Magic Mouse (Lightning o USB-C)

## Compilar e instalar

```sh
git clone https://github.com/Cosmichomeless/magictap.git
cd magictap
scripts/build-app.sh --install     # compila, firma ad-hoc y copia a ~/Applications
open ~/Applications/MagicTap.app
```

La primera vez, macOS pide permiso de **Accesibilidad** (hace falta para generar
los clics). Actívalo en
*Ajustes del Sistema → Privacidad y seguridad → Accesibilidad*.

Sin `--install`, el script solo genera `build/MagicTap.app`.

## Uso

Pulsa el icono del ratón en la barra de menús:

- **Enabled** — interruptor general.
- **Tap → left click** / **Two-finger tap → right click** — activa o desactiva cada gesto.
- **Launch at login** — solo funciona desde la `.app` empaquetada.

### Probar sin hacer clics

```sh
swift run MagicTap --debug
```

`--debug` imprime cada fotograma táctil y cada toque reconocido, y **nunca
genera clics**. Sirve para comprobar que tu ratón se detecta y ver cómo son tus toques.

## Cómo se reconoce un toque

Un contacto cuenta como toque solo si se cumple **todo** esto:

1. Dura entre 20 ms y 200 ms.
2. Los dedos casi no se mueven (no es un scroll ni un deslizamiento).
3. El cursor no se mueve más de 4 puntos (no estás simplemente moviendo el ratón).
4. No hay una pulsación física del botón mientras tanto.
5. Se usó exactamente un dedo (clic izquierdo) o dos (clic derecho).

Estos valores están en [`TapConfig`](Sources/MagicTapCore/TapDetector.swift).
La arquitectura, la API privada y la resolución de problemas están en
[docs/how-it-works.md](docs/how-it-works.md).

## Desarrollo

```sh
swift build      # compilar
swift test       # tests unitarios del reconocimiento de toques
```

## Limitaciones

- **API privada.** Los datos táctiles salen del framework no documentado
  `MultitouchSupport`. Una actualización de macOS puede romperlo y la app no
  puede publicarse en la Mac App Store. Los símbolos se resuelven en ejecución,
  así que si falta alguno aparece un error en vez de un cierre inesperado.
- **Toques accidentales.** La superficie del Magic Mouse es grande y la mano
  descansa sobre ella. Las comprobaciones de duración, movimiento y recorrido
  del cursor reducen los falsos clics, pero no los eliminan.
- **Permiso tras recompilar.** Con la firma ad-hoc por defecto, macOS vuelve a
  pedir Accesibilidad tras cada compilación. Usa `SIGN_IDENTITY` con un
  certificado estable para evitarlo.
- **Solo Magic Mouse.** Los trackpads se ignoran a propósito: ya tienen
  tocar-para-hacer-clic nativo.

## Licencia

[MIT](LICENSE). Proyecto independiente, sin relación con Apple ni respaldado por
ella. *Magic Mouse* es una marca registrada de Apple Inc.

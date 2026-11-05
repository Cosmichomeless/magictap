import AppKit

// `MagicTap --debug` prints raw touch frames and recognized taps to stdout
// and never injects clicks. Useful to tune thresholds and verify the device.
let debug = CommandLine.arguments.contains("--debug")
if debug { setvbuf(stdout, nil, _IONBF, 0) } // show frames immediately, even when piped

let app = NSApplication.shared
let delegate = AppDelegate(debug: debug)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

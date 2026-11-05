import Foundation

// Thin bridge to Apple's PRIVATE MultitouchSupport framework.
//
// The framework has no public headers, so the symbols are resolved at runtime
// with dlopen/dlsym. If a future macOS removes or changes them, `load()`
// returns nil and the app reports the problem instead of crashing at launch.
// See docs/how-it-works.md for the struct layout and how it was verified.

typealias MTDevice = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDevice?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void

struct MultitouchAPI {
    let createList: @convention(c) () -> Unmanaged<CFArray>?
    let registerCallback: @convention(c) (MTDevice, MTContactCallback) -> Void
    let unregisterCallback: @convention(c) (MTDevice, MTContactCallback) -> Void
    let start: @convention(c) (MTDevice, Int32) -> Int32
    let stop: @convention(c) (MTDevice) -> Int32
    let isBuiltIn: @convention(c) (MTDevice) -> Bool
    let surfaceDimensions: @convention(c) (MTDevice, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    let familyID: @convention(c) (MTDevice, UnsafeMutablePointer<Int32>) -> Int32
    let deviceID: @convention(c) (MTDevice, UnsafeMutablePointer<UInt64>) -> Int32

    static func load() -> MultitouchAPI? {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }

        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }

        guard
            let createList = symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
            let register = symbol("MTRegisterContactFrameCallback", as: (@convention(c) (MTDevice, MTContactCallback) -> Void).self),
            let unregister = symbol("MTUnregisterContactFrameCallback", as: (@convention(c) (MTDevice, MTContactCallback) -> Void).self),
            let start = symbol("MTDeviceStart", as: (@convention(c) (MTDevice, Int32) -> Int32).self),
            let stop = symbol("MTDeviceStop", as: (@convention(c) (MTDevice) -> Int32).self),
            let isBuiltIn = symbol("MTDeviceIsBuiltIn", as: (@convention(c) (MTDevice) -> Bool).self),
            let dims = symbol("MTDeviceGetSensorSurfaceDimensions", as: (@convention(c) (MTDevice, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self),
            let family = symbol("MTDeviceGetFamilyID", as: (@convention(c) (MTDevice, UnsafeMutablePointer<Int32>) -> Int32).self),
            let deviceID = symbol("MTDeviceGetDeviceID", as: (@convention(c) (MTDevice, UnsafeMutablePointer<UInt64>) -> Int32).self)
        else { return nil }

        return MultitouchAPI(
            createList: createList,
            registerCallback: register,
            unregisterCallback: unregister,
            start: start,
            stop: stop,
            isBuiltIn: isBuiltIn,
            surfaceDimensions: dims,
            familyID: family,
            deviceID: deviceID
        )
    }
}

/// Layout of one `MTTouch` record as delivered to the contact callback.
/// Only the fields we need are read, at fixed offsets, instead of mirroring
/// the whole (undocumented) C struct.
enum MTTouchLayout {
    static let stride = 96
    static let stateOffset = 20
    static let xOffset = 32
    static let yOffset = 36

    /// MTTouchState: 3 = making contact, 4 = touching. Other values are
    /// hover/lingering/leaving states that must not count as a finger.
    static func isTouching(_ state: Int32) -> Bool { state == 3 || state == 4 }
}

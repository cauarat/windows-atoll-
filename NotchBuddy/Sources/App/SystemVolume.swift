import CoreAudio
import Foundation

/// The output volume of whatever the Mac is playing through.
///
/// Deliberately the smallest thing that answers the question. Not a mixer: no
/// per-application levels, no picking a different output device. One number
/// for the default output, the same one the keyboard's volume keys move, so
/// the slider in the player and the keys never disagree.
///
/// CoreAudio reports "no such property" for a device with no volume control of
/// its own — some USB interfaces and most HDMI outputs — and the honest answer
/// there is nil, which the player reads as "do not show a slider".
enum SystemVolume {

    private static var defaultOutputDevice: AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    /// `'vmvc'` — the virtual main volume.
    ///
    /// Written as its four-character code because the constant for it lives in
    /// `AudioHardwareService`, which Apple deprecated without replacing this
    /// particular selector. It is the one the volume keys move: a device whose
    /// channels have separate levels still reports a single figure here, which
    /// is what a slider wants.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    private static var volumeAddress: AudioObjectPropertyAddress { .init(
        mSelector: virtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain) }

    private static var muteAddress: AudioObjectPropertyAddress { .init(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain) }

    /// 0…1, or nil when the current output has no volume of its own.
    static var level: Float? {
        guard let device = defaultOutputDevice else { return nil }
        var a = volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr
        else { return nil }
        return clamp(value)
    }

    static func setLevel(_ newValue: Float) {
        var a = volumeAddress
        guard let device = defaultOutputDevice,
              AudioObjectHasProperty(device, &a),
              isSettable(device, &a)
        else { return }
        var v = clamp(newValue)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &a, 0, nil, size, &v)
        // Moving the slider off zero un-mutes, because a slider that moves and
        // changes nothing is worse than no slider.
        if v > 0 { setMuted(false) }
    }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice else { return false }
        var a = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &a),
              AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        var a = muteAddress
        guard let device = defaultOutputDevice,
              AudioObjectHasProperty(device, &a),
              isSettable(device, &a)
        else { return }
        var v: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &a, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &v)
    }

    private static func isSettable(_ device: AudioDeviceID,
                                   _ address: UnsafeMutablePointer<AudioObjectPropertyAddress>) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, address, &settable) == noErr
            && settable.boolValue
    }

    /// Out of range is a programming mistake, not a reason to deafen anybody.
    static func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }
}

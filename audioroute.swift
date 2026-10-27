// audioroute: show which processes run audio output on which device, or move the system default
// output (and alert-sound output) to a device by UID. Streams that follow the default re-home with it.
//   audioroute status
//   audioroute list                    every device that has an output, with its UID
//   audioroute set <device-UID>        e.g. BuiltInSpeakerDevice, AA-BB-CC-DD-EE-FF:output
import CoreAudio
import Foundation

let sys = AudioObjectID(kAudioObjectSystemObject)

func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func u32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var a = addr(sel, scope); var v: UInt32 = 0; var sz = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr ? v : nil
}

func str(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel); var v: Unmanaged<CFString>?; var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr, let s = v else { return "?" }
    // Names and UIDs come from drivers and devices; a tab or newline in one would forge output records.
    let bad = CharacterSet.controlCharacters.union(.newlines)
    return String(String.UnicodeScalarView((s.takeRetainedValue() as String).unicodeScalars.filter { !bad.contains($0) }))
}

func ids(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var a = addr(sel, scope); var sz: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &sz) == noErr, sz > 0 else { return [] }
    var out = [AudioObjectID](repeating: 0, count: Int(sz) / MemoryLayout<AudioObjectID>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &out) == noErr ? out : []
}

func status() {
    let def = u32(sys, kAudioHardwarePropertyDefaultOutputDevice) ?? 0
    print("default\t\(str(def, kAudioDevicePropertyDeviceUID))\t\(str(def, kAudioObjectPropertyName))")
    for p in ids(sys, kAudioHardwarePropertyProcessObjectList) where u32(p, kAudioProcessPropertyIsRunningOutput) == 1 {
        let pid = u32(p, kAudioProcessPropertyPID) ?? 0
        let devs = ids(p, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput)
            .map { str($0, kAudioDevicePropertyDeviceUID) }.joined(separator: ",")
        print("output\t\(pid)\t\(str(p, kAudioProcessPropertyBundleID))\t\(devs)")
    }
}

func list() {
    for d in ids(sys, kAudioHardwarePropertyDevices) {
        var a = addr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput); var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(d, &a, 0, nil, &sz) == noErr, sz > 0 else { continue }
        print("device\t\(str(d, kAudioDevicePropertyDeviceUID))\t\(str(d, kAudioObjectPropertyName))")
    }
}

func set(_ uid: String) -> Int32 {
    guard let dev = ids(sys, kAudioHardwarePropertyDevices).first(where: { str($0, kAudioDevicePropertyDeviceUID) == uid }) else {
        FileHandle.standardError.write("no device with UID \(uid)\n".data(using: .utf8)!); return 2
    }
    for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
        var a = addr(sel); var v = dev
        let rv = AudioObjectSetPropertyData(sys, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &v)
        if rv != noErr { FileHandle.standardError.write("set selector \(sel) failed: \(rv)\n".data(using: .utf8)!); return 1 }
    }
    return 0
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "status": status()
case "list": list()
case "set" where args.count == 3: exit(set(args[2]))
default:
    FileHandle.standardError.write("usage: audioroute status | audioroute list | audioroute set <device-UID>\n".data(using: .utf8)!); exit(64)
}

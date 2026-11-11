import Carbon

@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return false }
        let identifier = EventHotKeyID(signature: 0x43544C56, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey), identifier,
                                  GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
}

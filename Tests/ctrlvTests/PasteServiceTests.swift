import AppKit
import Observation
import Testing
@testable import ctrlv

@Test @MainActor func directPasteTracksPermissionGrantAndRevocation() async {
    var allowed = false
    let service = PasteService(accessCheck: { allowed })
    #expect(!service.isEnabled)

    await confirmation("Permission grant updates observable UI state") { changed in
        withObservationTracking {
            _ = service.isEnabled
        } onChange: {
            changed()
        }
        allowed = true
        service.refresh()
    }
    #expect(service.isEnabled)

    await confirmation("Permission revocation updates observable UI state") { changed in
        withObservationTracking {
            _ = service.isEnabled
        } onChange: {
            changed()
        }
        allowed = false
        service.refresh()
    }
    #expect(!service.isEnabled)
}

@Test @MainActor func directPasteRechecksAccessBeforeSending() async {
    var allowed = true
    let service = PasteService(accessCheck: { allowed })
    allowed = false
    // The target is never activated when permission is unavailable.
    let message = await service.paste(into: .current)
    #expect(!service.isEnabled)
    #expect(message?.contains("Accessibility") == true)
}

@Test @MainActor func cancelledPasteDoesNotActivateTarget() async {
    var accessChecks = 0
    let service = PasteService(accessCheck: { accessChecks += 1; return true })
    let task = Task { @MainActor in await service.paste(into: .current) }
    task.cancel()
    let message = await task.value
    #expect(message?.contains("cancelled") == true)
    #expect(accessChecks == 1)
}

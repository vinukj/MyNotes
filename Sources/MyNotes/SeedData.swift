import Foundation

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// test store with notes a person can create in the app.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        guard model.notes.isEmpty else { return }
        let samples: [(String, String)] = [
            ("Book the dentist", "Call on Monday and ask for the earliest appointment."),
            ("Local-first software", "Three ideas: keep data on-device, make search immediate, and keep export simple."),
            ("Renew passport", "Check the photo requirements before filling in the form."),
            ("Weekend trip", "Compare the train times and reserve a place to stay."),
            ("Call Anna", "Ask how the new job is going."),
            ("Photo library backup", "Copy the originals to the external drive before the trip."),
            ("Groceries", "Coffee, oat milk, tomatoes, and bread."),
            ("Quarterly review", "Start with the projects that made the biggest difference."),
        ]
        for sample in samples {
            guard let note = model.addNote() else { continue }
            note.title = sample.0
            note.body = sample.1
            model.saveNote(note)
        }
        model.refreshNotes()
        model.selectedNoteID = nil
    }
}

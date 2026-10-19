# Vehicle Docs Vault — 1.0 (1)

Native iPhone application for iOS 16 and later. English interface. No account, advertising, purchase flow, analytics service, or remote backend.

## Completed source changes

- Vehicle, document, part, replacement, tire set, tire change, note and reminder create/edit flows use persistent local records.
- Record and attachment saves commit together. A failed file operation does not partially create a record or archive the document being replaced.
- Attachment transfers disable saving until loading finishes. Images and PDFs are checked before being accepted; protected PDFs need an unlocked copy.
- Replacement and tire-change history retains item names after a related card is removed. Archiving a historical record does not require recreating its removed item.
- Search refreshes after record mutations. Time-sensitive statuses refresh while the app is active and after returning from the background.
- Notifications open their associated record over the current screen, preserving an existing editing session. Foreground alerts are displayed.
- Recurrence uses an original calendar anchor to preserve month-end dates. Completing a recurring reminder creates its next occurrence.
- Import, export, backup and attachment staging perform file work through a background actor.
- JSON exports include referenced records, related vehicles and attachment bytes. CSV contains complete serialized record details as well as readable columns.
- Imports validate identifiers, relationships, cover ownership, attachment paths, file lengths and media. Restore writes new files before atomically committing their metadata; the current vault remains intact on a failed restore.
- Import preserves a backup of the current vault. If the current vault is damaged or incomplete, a raw recovery copy is preserved before restoration.
- A dedicated recovery screen prevents a failed database read from being mistaken for an empty vault.
- Client identifiers are generated UUIDs and are persisted locally. Restoring another backup retains this installation's current client identifier.
- Vehicle, record and attachment editors protect unsaved changes and provide a Done action for numeric keyboards. Editing vehicle details retains a cover selected from the photo gallery.
- Image thumbnails and PDF first-page previews render away from the main thread with a bounded memory cache. Full-screen images are downsampled to a maximum edge of 4096 pixels; PDF opening is asynchronous.
- Imported images use their detected format. Other decodable image formats are converted to PNG before staging, without image conversion in the UI.
- The image viewer centers fitted content, zooms around the double-tapped position and refits after rotation.
- Shared text, status labels and buttons support Dynamic Type. Home quick actions adapt to screen width; charts scale with text size and use horizontal gestures to explore values.
- Empty search and filtered collections offer a direct clear action. Archived vehicle timelines remain readable, and archived records do not expose active installation or completion actions.
- Backup creation and restoration are serialized as one operation. Export file type and category selection are captured when preparation starts.
- Attachment deletion runs off the main thread. Reset attempts cleanup of every file even if one cannot be removed, refreshes the backup list and reports incomplete erasure.

## Packaging

- Marketing version: 1.0. Build: 1.
- Bundle identifier: com.app.vehicledocsvault.
- Shared scheme archives the Release configuration.
- Privacy manifest declares no tracking, collection or required-reason API access. The current source uses no UserDefaults, file timestamp, disk-capacity or system-uptime APIs.
- Only notification authorization is requested explicitly. Photos are selected with PhotosPicker; images and PDFs are selected through the system file picker.
- A single attachment is limited to 50 MB, an editing batch to 128 MB, and a JSON transfer to 512 MB. CSV excludes binary attachments.

## Outstanding release verification

At the user's request, no build, tests, simulator or device run was performed. Source inspection is not runtime verification, and no signed archive was produced.

The project has no Development Team selected. Select the intended signing team, verify the bundle identifier and signing profile, then archive Release and validate the archive before uploading. Exercise the app's data, document-provider, PDF and notification flows on a physical device before submission.

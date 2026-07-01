//
//  AlbumViewController+DocumentUpload.swift
//  piwigo
//
//  Adds the ability to upload arbitrary documents (PDF, etc.) from the iOS
//  Files app directly into the local Piwigo album, at original quality.
//

import UIKit
import UniformTypeIdentifiers
import piwigoKit
import uploadKit

extension AlbumViewController: UIDocumentPickerDelegate {

    // Action sheet letting the user pick the upload source: Photo Library or Files.
    @objc func presentUploadSourceChoice() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Photo Library", comment: "Photo Library"),
            style: .default, handler: { [self] _ in checkPhotoLibraryAccess() }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Files", comment: "Files"),
            style: .default, handler: { [self] _ in presentDocumentPicker() }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("alertCancelButton", comment: "Cancel"),
            style: .cancel, handler: nil))

        // iPad: anchor the popover to the Add button.
        alert.popoverPresentationController?.sourceView = addButton
        alert.popoverPresentationController?.sourceRect = addButton.bounds
        present(alert, animated: true)
    }

    @MainActor
    func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .pageSheet
        present(picker, animated: true)
    }

    // MARK: - UIDocumentPickerDelegate
    public func documentPicker(_ controller: UIDocumentPickerViewController,
                               didPickDocumentsAt urls: [URL]) {
        guard urls.isEmpty == false else { return }

        // Stage each picked file into the Uploads directory with a "-dat-" id so
        // the upload pipeline recognises it as a document to send as-is.
        let stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        var requests = [UploadProperties]()
        for (idx, url) in urls.enumerated() {
            let ext = url.pathExtension.lowercased()
            let identifier = "\(kClipboardPrefix)\(stamp)\(kDataSuffix)\(idx)"
            let stagedName = ext.isEmpty ? identifier : "\(identifier).\(ext)"
            let staged = DataDirectories.appUploadsDirectory.appendingPathComponent(stagedName)

            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: url, to: staged)
            } catch {
                continue
            }

            var request = UploadProperties(localIdentifier: identifier, category: categoryId)
            request.fileName = url.lastPathComponent          // keep the original name
            request.fileType = pwgImageFileType.pdf.rawValue
            requests.append(request)
        }
        guard requests.isEmpty == false else { return }

        // Hand the requests to the upload queue, mirroring the photo/video flow.
        Task(priority: .utility) { @UploadManagerActor in
            do {
                let uploadIDs = try await UploadManager.shared.importUploads(from: requests)
                UploadVars.shared.isPaused = false
                #if os(iOS) && !targetEnvironment(macCatalyst)
                if #available(iOS 26.0, *) {
                    if UploadVars.shared.isContinuedProcessingTaskActive == false {
                        UploadManager.shared.runContinuedUploadTask()
                    }
                } else {
                    await UploadManagerActor.shared.addUploadsToPrepare(withIDs: uploadIDs)
                    await UploadManagerActor.shared.processNextUpload()
                }
                #endif
            } catch {
                // Import failures surface in the upload queue UI.
            }
        }
    }
}

//
//  AlbumViewController+Upload.swift
//  piwigo
//
//  Created by Eddy Lelièvre-Berna on 12/04/2024.
//  Copyright © 2024 Piwigo.org. All rights reserved.
//

import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers
import piwigoKit
import uploadKit

extension AlbumViewController
{
    // MARK: Toolbar Buttons (iOS 26+)
    func getUploadQueueBarButton(withTitle title: String? = nil) -> UIBarButtonItem? {
        guard let title = title
        else { return nil }
        
        let button = UIBarButtonItem()
        button.style = .plain
        button.target = self
        button.action = #selector(didTapUploadQueueButton)
        button.accessibilityIdentifier = "showUploadQueue"
        if title == "⚠️" {
            let config = UIImage.SymbolConfiguration(pointSize: 17)
            button.image = UIImage(systemName: "photo.badge.exclamationmark", withConfiguration: config)
        } else {
            button.title = title
        }
        return button
    }
    
    
    // MARK: - Button Management
    @MainActor @available(iOS 26.0, *)
    private func setNavBarWithUploadQueueButton() {
        // Show upload queue button only in default album
        guard [0, AlbumVars.shared.defaultCategory].contains(categoryId),
              uploadQueueBarButton != nil
        else { return }
        
        // Reset the navigation bar
        switch view.traitCollection.userInterfaceIdiom {
        case .phone:
            // Search and other buttons in the toolbar
            navigationItem.preferredSearchBarPlacement = .integratedButton
            let searchBarButton = navigationItem.searchBarPlacementBarButtonItem
            let toolBarItems = [uploadQueueBarButton, .space(), addAlbumBarButton, searchBarButton].compactMap { $0 }
            navigationController?.setToolbarHidden(false, animated: true)
            setToolbarItems(toolBarItems, animated: true)
            
        case .pad:
            // Right side of the navigation bar
            navigationItem.preferredSearchBarPlacement = .integrated
            let items = [discoverBarButton, addAlbumBarButton, .fixedSpace(16.0), uploadQueueBarButton].compactMap { $0 }
            navigationItem.setRightBarButtonItems(items, animated: true)
            
        default:
            preconditionFailure("!!! Interface not managed !!!")
        }
    }
    
    @MainActor @available(iOS 26.0, *)
    func setNavBarWithUploadQueueButton(andNberOfUploads nberOfUploads: Int) {
        guard [0, AlbumVars.shared.defaultCategory].contains(categoryId),
              nberOfUploads > 0
        else { return }
        
        if (!NetworkVars.shared.isConnectedToWiFi && UploadVars.shared.wifiOnlyUploading) ||
            [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) ||
            ProcessInfo.processInfo.isLowPowerModeEnabled {
            if uploadQueueBarButton == nil {
                uploadQueueBarButton = getUploadQueueBarButton(withTitle: "⚠️")!
                setNavBarWithUploadQueueButton()
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: 17)
                uploadQueueBarButton?.image = UIImage(systemName: "photo.badge.exclamationmark", withConfiguration: config)
            }
        } else {
            // Set number of uploads
            let nber = String(format: "%lu", UInt(nberOfUploads))
            if uploadQueueBarButton == nil {
                uploadQueueBarButton = getUploadQueueBarButton(withTitle: nber)!
                setNavBarWithUploadQueueButton()
            }
            else if let currentTitle = uploadQueueBarButton?.title,
                      nber.compare(currentTitle) == .orderedSame,
                      uploadQueueBarButton?.isHidden ?? true == false {
                // Nothing changed ► NOP
                return
            } else {
                uploadQueueBarButton?.image = nil
                uploadQueueBarButton?.title = nber
            }
        }
    }
    
    @MainActor @available(iOS 26.0, *)
    func setNavBarWithoutUploadQueueButton() {
        // The upload queue button is only presented in the default album
        guard [0, AlbumVars.shared.defaultCategory].contains(categoryId)
        else { return }
        
        // Reset the navigation bar
        switch view.traitCollection.userInterfaceIdiom {
        case .phone:
            // Search and other buttons in the toolbar
            navigationItem.preferredSearchBarPlacement = .integratedButton
            let searchBarButton = navigationItem.searchBarPlacementBarButtonItem
            let toolBarItems = [.space(), addAlbumBarButton, searchBarButton].compactMap { $0 }
            navigationController?.setToolbarHidden(false, animated: true)
            setToolbarItems(toolBarItems, animated: true)
            
        case .pad:
            // Right side of the navigation bar
            navigationItem.preferredSearchBarPlacement = .integrated
            let items = [discoverBarButton, addAlbumBarButton, .fixedSpace(16.0)].compactMap { $0 }
            navigationItem.setRightBarButtonItems(items, animated: true)
            
        default:
            preconditionFailure("!!! Interface not managed !!!")
        }
        
        // Deinitialise the button
        uploadQueueBarButton = nil
    }
    
    @MainActor
    @objc func updateNberOfUploads(_ notification: Notification?) {
        // Update main header if necessary
        setTableViewMainHeader()

        // Update upload queue button only in default album
        guard [0, AlbumVars.shared.defaultCategory].contains(categoryId),
              let nberOfUploads = (notification?.userInfo?["nberOfUploadsToComplete"] as? Int)
        else { return }

        // Show/hide upload queue button
        if #available(iOS 26.0, *) {
            if nberOfUploads <= 0 {
                setNavBarWithoutUploadQueueButton()
            } else {
                setNavBarWithUploadQueueButton(andNberOfUploads: nberOfUploads)
            }
        }
        else {
            // Fallback on previous version
            if nberOfUploads <= 0 {
                hideOldUploadQueueButton()
            } else {
                updateOldButton(withNberOfUploads: nberOfUploads)
            }
        }
    }
    
    
    // MARK: - Upload Actions
    @objc func didTapUploadImagesButton() {
        // Hide CreateAlbum and UploadImages buttons
        hideOptionalButtons { [self] in
            // Let the user choose the source: Photo Library or Files (documents)
            presentUploadSourceChoice()

            // Reset appearance and action of Add button
            showAddButton { [self] in
                addButton.removeTarget(self, action: #selector(didCancelTapAddButton), for: .touchUpInside)
                addButton.addTarget(self, action: #selector(didTapAddButton), for: .touchUpInside)
            }

            // Show button on the left of the Add button if needed
            if ![0, AlbumVars.shared.defaultCategory].contains(categoryId) {
                // Show Home button if not in root or default album
                showHomeAlbumButtonIfNeeded()
            }
        }
    }
    
    @objc func checkPhotoLibraryAccess() {
        PhotosFetch.shared.checkPhotoLibraryAuthorizationStatus(for: PHAccessLevel.readWrite, for: self, onAccess: { [self] in
            // Open local albums view controller in new navigation controller
            DispatchQueue.main.async {
                self.presentLocalAlbums()
            }
        }, onDeniedAccess: { })
    }
    
    @MainActor
    private func presentLocalAlbums() {
        // Open local albums view controller in new navigation controller
        let localAlbumsSB = UIStoryboard(name: "LocalAlbumsViewController", bundle: nil)
        guard let localAlbumsVC = localAlbumsSB.instantiateViewController(withIdentifier: "LocalAlbumsViewController") as? LocalAlbumsViewController
        else { preconditionFailure("Cloud not load LocalAlbumsViewController") }
        localAlbumsVC.categoryId = categoryId
        localAlbumsVC.categoryCurrentCounter = albumData.currentCounter
        localAlbumsVC.albumDelegate = self
        localAlbumsVC.user = user
        let navController = UINavigationController(rootViewController: localAlbumsVC)
        navController.modalTransitionStyle = .coverVertical
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }

    @MainActor
    @objc func didTapUploadQueueButton() {
        // Open upload queue controller in new navigation controller
        let uploadQueueSB = UIStoryboard(name: "UploadQueueViewController", bundle: nil)
        guard let uploadQueueVC = uploadQueueSB.instantiateViewController(withIdentifier: "UploadQueueViewController") as? UploadQueueViewController
        else { preconditionFailure("Could not load UploadQueueViewController") }
        let navController = UINavigationController(rootViewController: uploadQueueVC)
        navController.modalTransitionStyle = .coverVertical
        navController.modalPresentationStyle = .formSheet
        present(navController, animated: true)
    }
}


// MARK: - AlbumViewControllerDelegate Methods
extension AlbumViewController: @MainActor AlbumViewControllerDelegate {
    func didSelectCurrentCounter(value: Int64) {
        albumData.currentCounter = value    // Don't save this change also here to prevent a crash (conflict)
    }
}


// MARK: - Document (Files app) uploads
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

    // MARK: UIDocumentPickerDelegate
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

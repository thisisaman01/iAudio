//
//  RecordingSessionsViewController.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//


import Foundation
import UIKit
import SwiftData
import AVFoundation
import Combine

class RecordingSessionsViewController: UIViewController {
    
    // MARK: - Properties
    private let audioManager = AudioRecordingManager()
    private let transcriptionService = TranscriptionService.shared
    private var sessions: [RecordingSession] = []
    private var filteredSessions: [RecordingSession] = []
    
    // UI Components
    private let tableView = UITableView()
    private let recordButton = UIButton(type: .custom)
    private let searchController = UISearchController(searchResultsController: nil)
    private let recordingStatusView = UIView()
    private let recordingLabel = UILabel()
    private let durationLabel = UILabel()
    private let audioLevelView = UIProgressView()
    private let emptyStateView = UIView()
    private let emptyStateLabel = UILabel()
    private let transcriptionStatusView = UIView()
    private let transcriptionLabel = UILabel()
    
    // Combine support - managed locally
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("📱 RecordingSessionsViewController viewDidLoad")
        setupModelContexts()
        setupUI()
        setupConstraints()
        setupBindings()
        setupEmptyState()
        setupNotificationListeners() // ⚡ NEW
        loadSessions()
        startAutoRefreshTimer()
    }

    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("🔄 View will appear - refreshing sessions")
        loadSessions()
        
        // ⚡ ADDED: Force refresh after a short delay to catch any pending updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadSessions()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // ⚡ ADDED: Additional refresh after view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.loadSessions()
        }
    }
  
    
    // ⚡ DEBUGGING: Add method to check current transcription status
    private func debugTranscriptionStatus() {
        print("🔍 DEBUG: Current sessions status:")
        for (index, session) in sessions.enumerated() {
            print("  Session \(index): \(session.title)")
            print("    Total segments: \(session.totalSegments)")
            print("    Transcribed: \(session.transcribedSegments)")
            print("    Progress: \(Int(session.transcriptionProgress * 100))%")
            print("    Completed: \(session.isCompleted)")
            
            for segment in session.segments {
                let hasTranscription = segment.transcription != nil
                print("    Segment \(segment.segmentIndex): \(segment.transcriptionStatus) (has transcription: \(hasTranscription))")
            }
        }
    }

    // ⚡ ADDED: Public method to trigger immediate refresh (for testing)
    @objc public func triggerImmediateRefresh() {
        print("🚀 Triggered immediate refresh")
        debugTranscriptionStatus()
        loadSessions()
    }
    
    // ⚡ NEW: Notification listeners for instant updates
    private func setupNotificationListeners() {
        // Listen for transcription completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transcriptionCompleted),
            name: Notification.Name("TranscriptionCompleted"),
            object: nil
        )
        
        // Listen for app becoming active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // ⚡ NEW: Instant UI update when transcription completes
    @objc private func transcriptionCompleted(notification: Notification) {
        print("🎯 Received transcription completion notification")
        
        if let userInfo = notification.userInfo,
           let segmentId = userInfo["segmentId"] as? UUID,
           let sessionId = userInfo["sessionId"] as? UUID {
            print("📊 Transcription completed for segment \(segmentId) in session \(sessionId)")
        }
        
        // ⚡ IMMEDIATE: Force UI refresh
        DispatchQueue.main.async {
            print("🚀 Forcing immediate UI refresh for transcription completion")
            self.loadSessions()
        }
        
        // ⚡ FOLLOW-UP: Additional refresh to ensure persistence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadSessions()
        }
    }

    // ⚡ NEW: Refresh when app becomes active
    @objc private func appBecameActive() {
        print("📱 App became active - refreshing UI")
        loadSessions()
    }
    private func setupModelContexts() {
        // Pass ModelContext to AudioRecordingManager
        audioManager.modelContext = modelContext
        
        // Pass ModelContext to TranscriptionService
        transcriptionService.modelContext = modelContext
        
        print("✅ ModelContext set on managers")
    }
    
    // ⚡ CLEANUP: Remove notification observers
    deinit {
        print("🗑️ RecordingSessionsViewController deinit")
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Audio Recordings"
        view.backgroundColor = .systemBackground
        
        // Navigation bar setup
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Settings",
            style: .plain,
            target: self,
            action: #selector(settingsButtonTapped)
        )
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Export",
            style: .plain,
            target: self,
            action: #selector(exportButtonTapped)
        )
        
        // Search controller
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search recordings and transcriptions..."
        searchController.searchBar.searchBarStyle = .minimal
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
        // Table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RecordingSessionTableViewCell.self, forCellReuseIdentifier: "SessionCell")
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(refreshSessions), for: .valueChanged)
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.backgroundColor = .systemGroupedBackground
        
        // Record button
        recordButton.backgroundColor = .systemRed
        recordButton.layer.cornerRadius = 35
        recordButton.setTitle("●", for: .normal)
        recordButton.setTitle("■", for: .selected)
        recordButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordButton.layer.shadowColor = UIColor.black.cgColor
        recordButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        recordButton.layer.shadowRadius = 4
        recordButton.layer.shadowOpacity = 0.3
        
        // Recording status view
        recordingStatusView.backgroundColor = .systemBackground
        recordingStatusView.layer.borderWidth = 1
        recordingStatusView.layer.borderColor = UIColor.systemGray4.cgColor
        recordingStatusView.layer.cornerRadius = 8
        recordingStatusView.isHidden = true
        
        recordingLabel.text = "Recording..."
        recordingLabel.font = .systemFont(ofSize: 16, weight: .medium)
        recordingLabel.textColor = .systemRed
        
        durationLabel.text = "00:00"
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        durationLabel.textColor = .label
        
        audioLevelView.progressTintColor = .systemGreen
        audioLevelView.trackTintColor = .systemGray5
        audioLevelView.layer.cornerRadius = 2
        
        // Transcription status view
        transcriptionStatusView.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        transcriptionStatusView.layer.borderWidth = 1
        transcriptionStatusView.layer.borderColor = UIColor.systemBlue.cgColor
        transcriptionStatusView.layer.cornerRadius = 8
        transcriptionStatusView.isHidden = true
        
        transcriptionLabel.text = "Processing transcriptions..."
        transcriptionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        transcriptionLabel.textColor = .systemBlue
        transcriptionLabel.textAlignment = .center
        
        // Add subviews
        [tableView, recordButton, recordingStatusView, emptyStateView, transcriptionStatusView].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        [recordingLabel, durationLabel, audioLevelView].forEach {
            recordingStatusView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        transcriptionStatusView.addSubview(transcriptionLabel)
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupEmptyState() {
        emptyStateLabel.text = "No recordings yet\n\nTap the red button to start recording.\nYour recordings will be automatically transcribed and saved here."
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabel
        
        let microphoneImageView = UIImageView(image: UIImage(systemName: "mic.circle"))
        microphoneImageView.contentMode = .scaleAspectFit
        microphoneImageView.tintColor = .systemGray3
        microphoneImageView.translatesAutoresizingMaskIntoConstraints = false
        
        emptyStateView.addSubview(microphoneImageView)
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            microphoneImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            microphoneImageView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -40),
            microphoneImageView.widthAnchor.constraint(equalToConstant: 80),
            microphoneImageView.heightAnchor.constraint(equalToConstant: 80),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateLabel.topAnchor.constraint(equalTo: microphoneImageView.bottomAnchor, constant: 20),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: emptyStateView.trailingAnchor, constant: -20)
        ])
        
        emptyStateView.isHidden = true
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Recording status view
            recordingStatusView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            recordingStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recordingStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recordingStatusView.heightAnchor.constraint(equalToConstant: 80),
            
            recordingLabel.topAnchor.constraint(equalTo: recordingStatusView.topAnchor, constant: 16),
            recordingLabel.leadingAnchor.constraint(equalTo: recordingStatusView.leadingAnchor, constant: 16),
            
            durationLabel.topAnchor.constraint(equalTo: recordingLabel.topAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: recordingStatusView.trailingAnchor, constant: -16),
            
            audioLevelView.topAnchor.constraint(equalTo: recordingLabel.bottomAnchor, constant: 12),
            audioLevelView.leadingAnchor.constraint(equalTo: recordingStatusView.leadingAnchor, constant: 16),
            audioLevelView.trailingAnchor.constraint(equalTo: recordingStatusView.trailingAnchor, constant: -16),
            audioLevelView.heightAnchor.constraint(equalToConstant: 4),
            
            // Transcription status view
            transcriptionStatusView.topAnchor.constraint(equalTo: recordingStatusView.bottomAnchor, constant: 8),
            transcriptionStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            transcriptionStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            transcriptionStatusView.heightAnchor.constraint(equalToConstant: 40),
            
            transcriptionLabel.centerXAnchor.constraint(equalTo: transcriptionStatusView.centerXAnchor),
            transcriptionLabel.centerYAnchor.constraint(equalTo: transcriptionStatusView.centerYAnchor),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: transcriptionStatusView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -16),
            
            // Empty state view
            emptyStateView.topAnchor.constraint(equalTo: transcriptionStatusView.bottomAnchor, constant: 8),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -16),
            
            // Record button
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    // ⚡ OPTIMIZED: Real-time transcription status updates
    private func setupBindings() {
        // Audio manager bindings
        audioManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isRecording: Bool) in
                self?.recordingStatusView.isHidden = !isRecording
                self?.recordButton.isSelected = isRecording
                self?.recordButton.backgroundColor = isRecording ? .systemGray : .systemRed
                
                if !isRecording {
                    print("🚀 Recording stopped - immediate UI refresh")
                    self?.loadSessions()
                    
                    // ⚡ ADDED: Multiple refresh waves to catch transcription updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.loadSessions()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self?.loadSessions()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self?.loadSessions()
                    }
                }
            }
            .store(in: &cancellables)
        
        audioManager.$recordingDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (duration: TimeInterval) in
                self?.durationLabel.text = self?.formatDuration(duration)
            }
            .store(in: &cancellables)
        
        audioManager.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (level: Float) in
                self?.audioLevelView.progress = level
            }
            .store(in: &cancellables)
        
        audioManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (errorMessage: String?) in
                if let error = errorMessage {
                    self?.showErrorAlert(message: error)
                }
            }
            .store(in: &cancellables)
        
        // ⚡ FIXED: More aggressive transcription service bindings
        transcriptionService.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isProcessing: Bool) in
                let shouldShow = isProcessing
                self?.transcriptionStatusView.isHidden = !shouldShow
                
                if shouldShow {
                    self?.transcriptionLabel.text = "⚡ Transcribing now..."
                }
                
                // ⚡ ADDED: Force refresh when transcription starts/stops
                self?.loadSessions()
            }
            .store(in: &cancellables)
        
        transcriptionService.$pendingTranscriptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (pendingCount: Int) in
                if pendingCount > 0 {
                    self?.transcriptionStatusView.isHidden = false
                    self?.transcriptionLabel.text = "⏳ \(pendingCount) transcriptions pending"
                }
                
                // ⚡ FORCE: Always refresh UI when pending count changes
                self?.loadSessions()
            }
            .store(in: &cancellables)
        
        transcriptionService.$completedTranscriptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (completedCount: Int) in
                print("🎯 Transcription completed count: \(completedCount)")
                
                // ⚡ IMMEDIATE: Force UI refresh when transcription completes
                self?.loadSessions()
                
                // ⚡ FOLLOW-UP: Additional refresh to ensure UI is updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.loadSessions()
                }
            }
            .store(in: &cancellables)
    }

    // ⚡ ADDED: Force refresh method for manual triggering
    @objc private func forceRefreshUI() {
        print("🔄 Force refreshing UI...")
        loadSessions()
    }

    // ⚡ ADDED: Auto-refresh timer for transcription updates
    private func startAutoRefreshTimer() {
        var refreshInterval: TimeInterval = 1.0 // Start with 1 second
        
        func scheduleNextRefresh() {
            DispatchQueue.main.asyncAfter(deadline: .now() + refreshInterval) { [weak self] in
                guard let self = self else { return }
                
                let hasProcessingSessions = self.sessions.contains { session in
                    session.totalSegments > 0 && session.transcribedSegments < session.totalSegments
                }
                
                if hasProcessingSessions {
                    print("🔄 Auto-refresh (interval: \(refreshInterval)s)")
                    self.loadSessions()
                    
                    // ⚡ EXPONENTIAL BACKOFF: Increase interval but cap at 5 seconds
                    refreshInterval = min(5.0, refreshInterval * 1.2)
                    scheduleNextRefresh()
                } else {
                    print("⏹️ All transcriptions complete - stopping auto-refresh")
                    refreshInterval = 1.0 // Reset for next time
                }
            }
        }
        
        scheduleNextRefresh()
    }

    
    // MARK: - Data Management
 
    // ⚡ OPTIMIZED: Faster session loading with smart caching
    private func loadSessions() {
        print("🔄⚡ Fast loading sessions...")
        
        guard let context = modelContext else {
            print("❌ No ModelContext available")
            updateEmptyState()
            tableView.refreshControl?.endRefreshing()
            showErrorAlert(message: "Database not available. Please restart the app.")
            return
        }
        
        print("✅⚡ ModelContext available, fast fetching data...")
        
        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
            )
            
            let fetchedSessions = try context.fetch(descriptor)
            print("✅⚡ Fast fetched \(fetchedSessions.count) sessions")
            
            // ⚡ FIXED: Better change detection that includes transcription updates
            let hasChanges = hasSessionChanges(oldSessions: sessions, newSessions: fetchedSessions)
            
            self.sessions = fetchedSessions
            self.filteredSessions = fetchedSessions
            
            // ⚡ ALWAYS UPDATE UI: Force refresh to ensure transcription updates show
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.updateEmptyState()
                if hasChanges {
                    print("✅⚡ Fast UI updated with transcription changes")
                } else {
                    print("✅⚡ Fast UI refreshed")
                }
            }
            
            DispatchQueue.main.async {
                self.tableView.refreshControl?.endRefreshing()
            }
            
        } catch {
            print("❌ Failed to fetch sessions: \(error)")
            DispatchQueue.main.async {
                self.tableView.refreshControl?.endRefreshing()
                self.updateEmptyState()
                self.showErrorAlert(message: "Failed to load recordings: \(error.localizedDescription)")
            }
        }
    }

    // ⚡ NEW: Better change detection for transcription updates
    private func hasSessionChanges(oldSessions: [RecordingSession], newSessions: [RecordingSession]) -> Bool {
        // Check if count changed
        if oldSessions.count != newSessions.count {
            return true
        }
        
        // Check if any transcription status changed
        for (old, new) in zip(oldSessions, newSessions) {
            if old.transcribedSegments != new.transcribedSegments ||
               old.totalSegments != new.totalSegments ||
               old.transcriptionProgress != new.transcriptionProgress {
                print("📊 Detected transcription changes for: \(new.title)")
                print("   Transcribed: \(old.transcribedSegments) → \(new.transcribedSegments)")
                print("   Total: \(old.totalSegments) → \(new.totalSegments)")
                return true
            }
            
            // Check if any segment transcription completed
            for segment in new.segments {
                if let transcription = segment.transcription {
                    print("✅ Found completed transcription for segment \(segment.segmentIndex): '\(transcription.text.prefix(30))...'")
                    return true
                }
            }
        }
        
        return false
    }
    
    private func updateEmptyState() {
        let isEmpty = filteredSessions.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        
        if isEmpty {
            print("📭 Showing empty state")
        } else {
            print("📋 Showing \(filteredSessions.count) sessions")
        }
    }
    
    @objc private func refreshSessions() {
        print("🔄 Manual refresh triggered")
        
        // ⚡ VISUAL: Show refresh control immediately
        if let refreshControl = tableView.refreshControl {
            refreshControl.beginRefreshing()
        }
        
        loadSessions()
        
        // ⚡ FOLLOW-UP: Ensure refresh control stops
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.tableView.refreshControl?.endRefreshing()
        }
    }
    
    // MARK: - Actions
    @objc private func recordButtonTapped() {
        if audioManager.isRecording {
            print("⏹️ Stopping recording")
            audioManager.stopRecording()
        } else {
            print("🎤 Starting recording process")
            requestMicrophonePermission { [weak self] granted in
                if granted {
                    self?.startNewRecording()
                } else {
                    self?.showPermissionDeniedAlert()
                }
            }
        }
    }
    
    @objc private func settingsButtonTapped() {
        let settingsVC = SettingsViewController()
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }
    
    @objc private func exportButtonTapped() {
        guard !sessions.isEmpty else {
            showErrorAlert(message: "No recordings to export")
            return
        }
        
        let alertController = UIAlertController(title: "Export Recordings", message: "Choose export format", preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "Export All Transcriptions (Text)", style: .default) { [weak self] _ in
            self?.exportAllTranscriptions()
        })
        
        alertController.addAction(UIAlertAction(title: "Export Selected Recording", style: .default) { [weak self] _ in
            self?.showExportSelection()
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }
        
        present(alertController, animated: true)
    }
    
    private func startNewRecording() {
        let alertController = UIAlertController(title: "New Recording", message: "Enter a title for this recording", preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.placeholder = "Recording title"
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            textField.text = "Recording \(formatter.string(from: Date()))"
        }
        
        let startAction = UIAlertAction(title: "Start", style: .default) { [weak self] _ in
            let title = alertController.textFields?.first?.text ?? "Untitled Recording"
            print("🎤 Starting recording: \(title)")
            
            // Clear any previous errors
            self?.audioManager.errorMessage = nil
            
            // Start recording
            self?.audioManager.startRecording(title: title)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(startAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    // MARK: - Export Functions
    private func exportAllTranscriptions() {
        var allText = "iAudio - Complete Transcription Export\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium
        
        allText += "Generated: \(dateFormatter.string(from: Date()))\n"
        allText += "Total Recordings: \(sessions.count)\n\n"
        
        for session in sessions.sorted(by: { $0.createdDate < $1.createdDate }) {
            allText += "═══════════════════════════════════════\n"
            allText += "📝 \(session.title)\n"
            allText += "📅 \(dateFormatter.string(from: session.createdDate))\n"
            allText += "⏱️ Duration: \(formatDuration(session.duration))\n"
            allText += "═══════════════════════════════════════\n\n"
            
            let sortedSegments = session.segments.sorted { $0.segmentIndex < $1.segmentIndex }
            
            if sortedSegments.isEmpty {
                allText += "(No transcription segments available)\n\n"
            } else {
                for segment in sortedSegments {
                    if let transcription = segment.transcription {
                        let timeRange = "[\(formatDuration(segment.startTime)) - \(formatDuration(segment.endTime))]"
                        allText += "\(timeRange) \(transcription.text)\n\n"
                    }
                }
            }
            
            allText += "\n"
        }
        
        let activityVC = UIActivityViewController(activityItems: [allText], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }
        
        present(activityVC, animated: true)
    }
    
    private func showExportSelection() {
        let alert = UIAlertController(title: "Export Selection", message: "This feature allows selecting specific recordings for export", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Coming Soon", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Helper Methods
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let audioSession = AVAudioSession.sharedInstance()
        
        switch audioSession.recordPermission {
        case .granted:
            print("🎤 Microphone permission already granted")
            completion(true)
        case .denied:
            print("🚫 Microphone permission denied")
            completion(false)
        case .undetermined:
            print("❓ Requesting microphone permission")
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    print(granted ? "✅ Microphone permission granted" : "❌ Microphone permission denied")
                    completion(granted)
                }
            }
        @unknown default:
            print("❓ Unknown microphone permission status")
            completion(false)
        }
    }
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Microphone Permission Required",
            message: "Please enable microphone access in Settings to record audio. This app needs microphone access to record and transcribe audio.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Table View Data Source & Delegate
extension RecordingSessionsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSessions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath) as! RecordingSessionTableViewCell
        let session = filteredSessions[indexPath.row]
        cell.configure(with: session)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let session = filteredSessions[indexPath.row]
        let detailVC = SessionDetailViewController(session: session)
        detailVC.modelContext = modelContext
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let session = filteredSessions[indexPath.row]
            deleteSession(session, at: indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let session = filteredSessions[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let share = UIAction(title: "Share Transcription", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareSession(session)
            }
            
            let export = UIAction(title: "Export Audio", image: UIImage(systemName: "arrow.down.doc")) { [weak self] _ in
                self?.exportSessionAudio(session)
            }
            
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                if let index = self?.filteredSessions.firstIndex(where: { $0.id == session.id }) {
                    self?.deleteSession(session, at: IndexPath(row: index, section: 0))
                }
            }
            
            return UIMenu(title: session.title, children: [share, export, delete])
        }
    }
    
    private func shareSession(_ session: RecordingSession) {
        let transcriptionText = generateTranscriptionText(for: session)
        let activityVC = UIActivityViewController(activityItems: [transcriptionText], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(activityVC, animated: true)
    }
    
    private func exportSessionAudio(_ session: RecordingSession) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsDirectory.appendingPathComponent(session.audioFilePath)
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            showErrorAlert(message: "Audio file not found")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [audioURL], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(activityVC, animated: true)
    }
    
    private func generateTranscriptionText(for session: RecordingSession) -> String {
        var text = "📝 \(session.title)\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium
        
        text += "📅 \(dateFormatter.string(from: session.createdDate))\n"
        text += "⏱️ Duration: \(formatDuration(session.duration))\n\n"
        
        let sortedSegments = session.segments.sorted { $0.segmentIndex < $1.segmentIndex }
        
        if sortedSegments.isEmpty {
            text += "(No transcription available)"
        } else {
            for segment in sortedSegments {
                if let transcription = segment.transcription {
                    let timeRange = "[\(formatDuration(segment.startTime)) - \(formatDuration(segment.endTime))]"
                    text += "\(timeRange) \(transcription.text)\n\n"
                }
            }
        }
        
        return text
    }
    
    private func deleteSession(_ session: RecordingSession, at indexPath: IndexPath) {
        guard let context = modelContext else {
            showErrorAlert(message: "Database context not available")
            return
        }
        
        print("🗑️ Deleting session: \(session.title)")
        
        // Delete audio files
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            try FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(session.audioFilePath))
            print("✅ Deleted main audio file")
        } catch {
            print("⚠️ Failed to delete main audio file: \(error)")
        }
        
        for segment in session.segments {
            do {
                try FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(segment.audioFilePath))
                print("✅ Deleted segment file")
            } catch {
                print("⚠️ Failed to delete segment file: \(error)")
            }
        }
        
        // Delete from model
        context.delete(session)
        
        do {
            try context.save()
            print("✅ Session deleted from database")
        } catch {
            print("❌ Failed to save after deletion: \(error)")
            showErrorAlert(message: "Failed to delete session: \(error.localizedDescription)")
            return
        }
        
        // Update UI
        if let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: sessionIndex)
        }
        filteredSessions.remove(at: indexPath.row)
        
        tableView.deleteRows(at: [indexPath], with: .fade)
        updateEmptyState()
    }
}

// MARK: - Search Results Updating
extension RecordingSessionsViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else { return }
        
        if searchText.isEmpty {
            filteredSessions = sessions
        } else {
            filteredSessions = sessions.filter { session in
                // Search in title
                if session.title.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in transcription text
                return session.segments.contains { segment in
                    segment.transcription?.text.localizedCaseInsensitiveContains(searchText) ?? false
                }
            }
        }
        
        tableView.reloadData()
        updateEmptyState()
    }
}

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

// MARK: - Thread-Safe Data Manager Actor
@MainActor
final class SessionDataManager: ObservableObject {
    @Published var sessions: [RecordingSession] = []
    @Published var isLoading = false
    
    private var modelContext: ModelContext?
    private var refreshWorkItem: DispatchWorkItem?
    
    func configure(with context: ModelContext) {
        self.modelContext = context
    }
    
    func loadSessions() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        refreshWorkItem?.cancel()
        
        guard let context = modelContext else {
            print("❌ No ModelContext available")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
            )
            
            let fetchedSessions = try context.fetch(descriptor)
            print("🔄⚡ Fast fetched \(fetchedSessions.count) sessions")
            
            let hasChanges = hasSessionChanges(oldSessions: sessions, newSessions: fetchedSessions)
            
            sessions = fetchedSessions
            
            if hasChanges {
                print("✅⚡ Detected transcription changes - force UI update")
            }
            
        } catch {
            print("❌ Failed to fetch sessions: \(error)")
        }
    }
    
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
    
    func deleteSession(_ session: RecordingSession) async throws {
        guard let context = modelContext else {
            throw SessionError.noContext
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(session.audioFilePath))
            }
            
            for segment in session.segments {
                group.addTask {
                    try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(segment.audioFilePath))
                }
            }
        }
        
        context.delete(session)
        try context.save()
        sessions.removeAll { $0.id == session.id }
    }
    

    
    deinit {
        refreshWorkItem?.cancel()
    }
}

enum SessionError: Error {
    case noContext
    case deletionFailed
}

// MARK: - Main View Controller
final class RecordingSessionsViewController: UIViewController {
    
    // MARK: - Properties
    private let audioManager = AudioRecordingManager()
    private let transcriptionService = TranscriptionService.shared
    private let dataManager = SessionDataManager()
    
    private var filteredSessions: [RecordingSession] = []
    private var refreshWorkItem: DispatchWorkItem?
    private var autoRefreshTask: Task<Void, Never>?
    
    // UI Components
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .systemGroupedBackground
        table.separatorStyle = .singleLine
        table.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 120
        table.sectionHeaderTopPadding = 0
        table.contentInsetAdjustmentBehavior = .automatic
        table.keyboardDismissMode = .onDrag
        table.isPrefetchingEnabled = true
        table.remembersLastFocusedIndexPath = true
        
        table.sectionHeaderHeight = 0
        table.sectionFooterHeight = 0
        table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
        table.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNonzeroMagnitude))
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        table.refreshControl = refreshControl
        
        table.register(AppleStyleSessionCell.self, forCellReuseIdentifier: "SessionCell")
        return table
    }()
    
    private lazy var recordButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 35
        button.setTitle("●", for: .normal)
        button.setTitle("■", for: .selected)
        button.titleLabel?.font = .systemFont(ofSize: 28, weight: .medium)
        button.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        
        // Apple-style shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.2
        button.layer.masksToBounds = false
        
        return button
    }()
    
    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Search recordings and transcriptions..."
        controller.searchBar.searchBarStyle = .minimal
        return controller
    }()
    
    // Status views - only show when needed
    private lazy var recordingStatusView: RecordingStatusView = {
        let view = RecordingStatusView()
        view.isHidden = true
        return view
    }()
    
    private lazy var transcriptionStatusView: TranscriptionStatusView = {
        let view = TranscriptionStatusView()
        view.isHidden = true
        return view
    }()
    
    private lazy var emptyStateView: AppleStyleEmptyStateView = {
        let view = AppleStyleEmptyStateView()
        view.isHidden = true
        return view
    }()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupBindings()
        setupModelContexts()
        setupNotificationListeners()
        
        Task {
            await dataManager.loadSessions()
        }
        
        startIntelligentRefresh()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Task {
            await dataManager.loadSessions()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelRefreshOperations()
    }
    
    deinit {
        cancelRefreshOperations()
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    // MARK: - Setup Methods
    private func setupUI() {
        title = "Recordings"
        view.backgroundColor = .systemGroupedBackground
        
        // Apple-style navigation setup
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsButtonTapped)
        )
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportButtonTapped)
        )
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        
        // Add main views
        [tableView, emptyStateView, recordingStatusView, transcriptionStatusView, recordButton].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    private func setupConstraints() {
        // Create dynamic top constraint for table view
        let tableTopConstraint = tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        tableTopConstraint.priority = UILayoutPriority(999)
        
        // Status views constraints - positioned at top when visible
        let recordingTopConstraint = recordingStatusView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        let transcriptionTopConstraint = transcriptionStatusView.topAnchor.constraint(equalTo: recordingStatusView.bottomAnchor, constant: 8)
        let tableTopWithStatusConstraint = tableView.topAnchor.constraint(equalTo: transcriptionStatusView.bottomAnchor, constant: 8)
        
        // Initially deactivate status constraints
        recordingTopConstraint.isActive = false
        transcriptionTopConstraint.isActive = false
        tableTopWithStatusConstraint.isActive = false
        
        NSLayoutConstraint.activate([
            // Recording status view
            recordingStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recordingStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recordingStatusView.heightAnchor.constraint(equalToConstant: 80),
            
            // Transcription status view
            transcriptionStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            transcriptionStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            transcriptionStatusView.heightAnchor.constraint(equalToConstant: 50),
            
            // Table view - fills available space
            tableTopConstraint,
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            
            // Empty state
            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            
            // Record button - Apple-style positioning
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70)
        ])
        
        // Store constraints for dynamic updates
        self.recordingTopConstraint = recordingTopConstraint
        self.transcriptionTopConstraint = transcriptionTopConstraint
        self.tableTopConstraint = tableTopConstraint
        self.tableTopWithStatusConstraint = tableTopWithStatusConstraint
    }
    
    // Constraint references for dynamic layout
    private var recordingTopConstraint: NSLayoutConstraint!
    private var transcriptionTopConstraint: NSLayoutConstraint!
    private var tableTopConstraint: NSLayoutConstraint!
    private var tableTopWithStatusConstraint: NSLayoutConstraint!
    
    private func setupBindings() {
        // Data manager bindings
        dataManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateSessions(sessions)
            }
            .store(in: &cancellables)
        
        dataManager.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if !isLoading {
                    self?.tableView.refreshControl?.endRefreshing()
                }
            }
            .store(in: &cancellables)
        
        audioManager.$isRecording
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] isRecording in
                self?.updateRecordingState(isRecording)
                
                if !isRecording {
                    print("🚀 Recording stopped - triggering multiple refresh waves")
                    Task {
                        await self?.dataManager.loadSessions()
                        
                        // ⚡ MULTIPLE REFRESH WAVES: Catch transcription updates
                        try? await Task.sleep(for: .seconds(1))
                        await self?.dataManager.loadSessions()
                        
                        try? await Task.sleep(for: .seconds(3))
                        await self?.dataManager.loadSessions()
                        
                        try? await Task.sleep(for: .seconds(5))
                        await self?.dataManager.loadSessions()
                    }
                }
            }
            .store(in: &cancellables)
        
        audioManager.$recordingDuration
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] duration in
                self?.recordingStatusView.updateDuration(duration)
            }
            .store(in: &cancellables)
        
        audioManager.$audioLevel
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.recordingStatusView.updateAudioLevel(level)
            }
            .store(in: &cancellables)
        
        audioManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.showErrorAlert(message: error)
            }
            .store(in: &cancellables)
        
        // ⚡ ENHANCED: More aggressive transcription service bindings
        transcriptionService.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                let shouldShow = isProcessing
                self?.transcriptionStatusView.isHidden = !shouldShow
                self?.updateConstraintsForStatusVisibility()
                
                if shouldShow {
                    self?.transcriptionStatusView.updateStatus(isProcessing: true, pendingCount: 0)
                }
                
                // ⚡ FORCE: Always refresh UI when transcription starts/stops
                Task {
                    await self?.dataManager.loadSessions()
                }
            }
            .store(in: &cancellables)
        
        transcriptionService.$pendingTranscriptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pendingCount in
                if pendingCount > 0 {
                    self?.transcriptionStatusView.isHidden = false
                    self?.transcriptionStatusView.updateStatus(isProcessing: false, pendingCount: pendingCount)
                    self?.updateConstraintsForStatusVisibility()
                }
                
                // ⚡ FORCE: Always refresh UI when pending count changes
                Task {
                    await self?.dataManager.loadSessions()
                }
            }
            .store(in: &cancellables)
        
        transcriptionService.$completedTranscriptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completedCount in
                print("🎯 Transcription completed count: \(completedCount)")
                
                // ⚡ IMMEDIATE: Force UI refresh when transcription completes
                Task {
                    await self?.dataManager.loadSessions()
                    
                    // ⚡ FOLLOW-UP: Additional refresh to ensure UI is updated
                    try? await Task.sleep(for: .milliseconds(500))
                    await self?.dataManager.loadSessions()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupModelContexts() {
        audioManager.modelContext = modelContext
        transcriptionService.modelContext = modelContext
        dataManager.configure(with: modelContext!)
    }
    
    private func setupNotificationListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transcriptionCompleted),
            name: Notification.Name("TranscriptionCompleted"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Data Management (ENHANCED)
    private func updateSessions(_ sessions: [RecordingSession]) {
        let wasEmpty = filteredSessions.isEmpty
        
        if searchController.isActive, let searchText = searchController.searchBar.text, !searchText.isEmpty {
            filteredSessions = filterSessions(sessions, with: searchText)
        } else {
            filteredSessions = sessions
        }
        
        let isEmpty = filteredSessions.isEmpty
        
        // ⚡ ALWAYS UPDATE UI: Force refresh to ensure transcription updates show
        print("🔄 Updating sessions UI - \(filteredSessions.count) sessions")
        tableView.reloadData()
        
        // Smooth transitions for empty state
        if wasEmpty != isEmpty {
            UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) {
                self.emptyStateView.isHidden = !isEmpty
                self.tableView.isHidden = isEmpty
            }
        } else {
            emptyStateView.isHidden = !isEmpty
            tableView.isHidden = isEmpty
        }
    }
    
    private func filterSessions(_ sessions: [RecordingSession], with searchText: String) -> [RecordingSession] {
        return sessions.filter { session in
            if session.title.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            return session.segments.contains { segment in
                segment.transcription?.text.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    // MARK: - UI Updates with Dynamic Layout
    private func updateRecordingState(_ isRecording: Bool) {
        recordButton.isSelected = isRecording
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.recordButton.backgroundColor = isRecording ? .systemGray : .systemRed
            self.recordingStatusView.isHidden = !isRecording
            self.updateConstraintsForStatusVisibility()
        }
        
        if !isRecording {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await dataManager.loadSessions()
            }
        }
    }
    
    private func updateTranscriptionStatus(isProcessing: Bool, pendingCount: Int) {
        let shouldShow = isProcessing || pendingCount > 0
        
        if shouldShow {
            transcriptionStatusView.updateStatus(
                isProcessing: isProcessing,
                pendingCount: pendingCount
            )
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.transcriptionStatusView.isHidden = !shouldShow
            self.updateConstraintsForStatusVisibility()
        }
    }
    
    private func updateConstraintsForStatusVisibility() {
        let hasRecording = !recordingStatusView.isHidden
        let hasTranscription = !transcriptionStatusView.isHidden
        
        // Deactivate all dynamic constraints
        recordingTopConstraint.isActive = false
        transcriptionTopConstraint.isActive = false
        tableTopConstraint.isActive = false
        tableTopWithStatusConstraint.isActive = false
        
        if hasRecording || hasTranscription {
            if hasRecording {
                recordingTopConstraint.isActive = true
            }
            if hasTranscription {
                transcriptionTopConstraint.isActive = true
            }
            tableTopWithStatusConstraint.isActive = true
        } else {
            tableTopConstraint.isActive = true
        }
        
        view.layoutIfNeeded()
    }
    
    // MARK: - Intelligent Refresh System (RESTORED)
    private func startIntelligentRefresh() {
        autoRefreshTask = Task { [weak self] in
            var refreshInterval: TimeInterval = 1.0 // Start with 1 second
            
            func scheduleNextRefresh() {
                guard let self = self else { return }
                
                Task {
                    try? await Task.sleep(for: .seconds(refreshInterval))
                    
                    guard !Task.isCancelled else { return }
                    
                    let hasProcessingSessions = await self.dataManager.sessions.contains { session in
                        session.totalSegments > 0 && session.transcribedSegments < session.totalSegments
                    }
                    
                    if hasProcessingSessions {
                        print("🔄 Auto-refresh (interval: \(refreshInterval)s)")
                        await self.dataManager.loadSessions()
                        
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
    }
    
    //  Instant UI update when transcription completes
    @objc private func transcriptionCompleted(notification: Notification) {
        print("🎯 Received transcription completion notification")
        
        if let userInfo = notification.userInfo,
           let segmentId = userInfo["segmentId"] as? UUID,
           let sessionId = userInfo["sessionId"] as? UUID {
            print("📊 Transcription completed for segment \(segmentId) in session \(sessionId)")
        }
        
    // IMMEDIATE: Force UI refresh
        Task {
            print("🚀 Forcing immediate UI refresh for transcription completion")
            await dataManager.loadSessions()
            
            // ⚡ FOLLOW-UP: Additional refresh to ensure persistence
            try? await Task.sleep(for: .milliseconds(500))
            await dataManager.loadSessions()
        }
    }
    
    @objc private func appBecameActive() {
        print("📱 App became active - refreshing UI")
        Task {
            await dataManager.loadSessions()
        }
    }
    
    @objc public func triggerImmediateRefresh() {
        print("🚀 Triggered immediate refresh")
        debugTranscriptionStatus()
        Task {
            await dataManager.loadSessions()
        }
    }
    
    //  DEBUGGING: Add method to check current transcription status
    private func debugTranscriptionStatus() {
        print("🔍 DEBUG: Current sessions status:")
        for (index, session) in dataManager.sessions.enumerated() {
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
    
    private func cancelRefreshOperations() {
        refreshWorkItem?.cancel()
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
    
    // MARK: - Actions (ENHANCED)
    @objc private func handleRefresh() {
        print("🔄 Manual refresh triggered")
        
        //  VISUAL: Show refresh control immediately
        if let refreshControl = tableView.refreshControl {
            refreshControl.beginRefreshing()
        }
        
        Task {
            await dataManager.loadSessions()
            
            // ⚡ FOLLOW-UP: Ensure refresh control stops
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                self.tableView.refreshControl?.endRefreshing()
            }
        }
    }
    

    @objc private func recordButtonTapped() {
        if audioManager.isRecording {
            audioManager.stopRecording()
        } else {
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
        guard !dataManager.sessions.isEmpty else {
            showErrorAlert(message: "No recordings to export")
            return
        }
        
        let alertController = UIAlertController(title: "Export Recordings", message: "Choose export format", preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "Export All Transcriptions (Text)", style: .default) { [weak self] _ in
            self?.exportAllTranscriptions()
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }
        
        present(alertController, animated: true)
    }
    
    // MARK: - Helper Methods
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
            self?.audioManager.startRecording(title: title)
        }
        
        alertController.addAction(startAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    private func exportAllTranscriptions() {
        var allText = "iAudio - Complete Transcription Export\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium
        
        allText += "Generated: \(dateFormatter.string(from: Date()))\n"
        allText += "Total Recordings: \(dataManager.sessions.count)\n\n"
        
        for session in dataManager.sessions.sorted(by: { $0.createdDate < $1.createdDate }) {
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
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let audioSession = AVAudioSession.sharedInstance()
        
        switch audioSession.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Microphone Permission Required",
            message: "Please enable microphone access in Settings to record audio.",
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath) as! AppleStyleSessionCell
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
            
            Task {
                do {
                    try await dataManager.deleteSession(session)
                    
                    if let index = filteredSessions.firstIndex(where: { $0.id == session.id }) {
                        filteredSessions.remove(at: index)
                        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                    }
                } catch {
                    await MainActor.run {
                        showErrorAlert(message: "Failed to delete session: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let session = filteredSessions[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let share = UIAction(title: "Share Transcription", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareSession(session)
            }
            
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                Task {
                    try? await self?.dataManager.deleteSession(session)
                }
            }
            
            return UIMenu(title: session.title, children: [share, delete])
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
}

// MARK: - Search Results Updating
extension RecordingSessionsViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else { return }
        
        refreshWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            if searchText.isEmpty {
                self.filteredSessions = self.dataManager.sessions
            } else {
                self.filteredSessions = self.filterSessions(self.dataManager.sessions, with: searchText)
            }
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.emptyStateView.isHidden = !self.filteredSessions.isEmpty
                self.tableView.isHidden = self.filteredSessions.isEmpty
            }
        }
        
        refreshWorkItem = workItem
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}

// MARK: - Custom Status Views
class RecordingStatusView: UIView {
    
    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var topRowStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        return stack
    }()
    
    private lazy var recordingLabel: UILabel = {
        let label = UILabel()
        label.text = "● Recording..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .systemRed
        return label
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.text = "00:00"
        label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    private lazy var audioLevelView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = .systemGreen
        progress.trackTintColor = .systemGray5
        progress.layer.cornerRadius = 2
        progress.clipsToBounds = true
        return progress
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemRed.withAlphaComponent(0.3).cgColor
        
        addSubview(stackView)
        
        topRowStack.addArrangedSubview(recordingLabel)
        topRowStack.addArrangedSubview(durationLabel)
        
        stackView.addArrangedSubview(topRowStack)
        stackView.addArrangedSubview(audioLevelView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            
            audioLevelView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }
    
    func updateDuration(_ duration: TimeInterval) {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }
    
    func updateAudioLevel(_ level: Float) {
        audioLevelView.setProgress(level, animated: true)
    }
}

class TranscriptionStatusView: UIView {
    
    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemBlue
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .systemBlue.withAlphaComponent(0.1)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }
    
    func updateStatus(isProcessing: Bool, pendingCount: Int) {
        if pendingCount > 0 {
            label.text = "⏳ \(pendingCount) transcriptions pending"
        } else if isProcessing {
            label.text = "⚡ Transcribing..."
        }
    }
}

// MARK: - Apple-Style Empty State View
class AppleStyleEmptyStateView: UIView {
    
    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var microphoneImageView: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 64, weight: .medium)
        imageView.image = UIImage(systemName: "mic.circle.fill", withConfiguration: config)
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Recordings Yet"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap the record button to create your first audio recording. All recordings will be automatically transcribed and saved here."
        label.font = .systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(contentStackView)
        
        contentStackView.addArrangedSubview(microphoneImageView)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            
            microphoneImageView.widthAnchor.constraint(equalToConstant: 80),
            microphoneImageView.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
}

// MARK: - Enhanced Apple-Style Table View Cell with Real-time Progress
class AppleStyleSessionCell: UITableViewCell {
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var metadataStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillProportionally
        return stack
    }()
    
    private lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }()
    
    private lazy var statusStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .systemBlue
        return label
    }()
    
    //  Progress indicator for real-time transcription updates
    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = .systemBlue
        progress.trackTintColor = .systemGray5
        progress.layer.cornerRadius = 2
        progress.clipsToBounds = true
        progress.isHidden = true
        return progress
    }()
    
    private lazy var segmentCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.isHidden = true
        return label
    }()
    
    private lazy var transcriptionPreviewLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()
    
    private lazy var mainStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .default
        
        contentView.addSubview(mainStackView)
        
        metadataStackView.addArrangedSubview(dateLabel)
        metadataStackView.addArrangedSubview(durationLabel)
        
        statusStackView.addArrangedSubview(statusLabel)
        statusStackView.addArrangedSubview(segmentCountLabel)
        
        mainStackView.addArrangedSubview(titleLabel)
        mainStackView.addArrangedSubview(metadataStackView)
        mainStackView.addArrangedSubview(statusStackView)
        mainStackView.addArrangedSubview(progressView)
        mainStackView.addArrangedSubview(transcriptionPreviewLabel)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            progressView.heightAnchor.constraint(equalToConstant: 3)
        ])
    }
    
    func configure(with session: RecordingSession) {
        titleLabel.text = session.title
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateLabel.text = dateFormatter.string(from: session.createdDate)
        
        durationLabel.text = formatDuration(session.duration)
        
        // ⚡ ENHANCED: Real-time status with progress tracking
        if session.totalSegments == 0 {
            statusLabel.text = "Processing..."
            statusLabel.textColor = .systemOrange
            progressView.isHidden = true
            segmentCountLabel.isHidden = true
        } else if session.transcribedSegments < session.totalSegments {
            statusLabel.text = "Transcribing"
            statusLabel.textColor = .systemBlue
            
            // ⚡ SHOW PROGRESS: Real-time transcription progress
            progressView.isHidden = false
            progressView.progress = session.transcriptionProgress
            
            segmentCountLabel.isHidden = false
            segmentCountLabel.text = "(\(session.transcribedSegments)/\(session.totalSegments))"
            
            print("📊 Cell showing progress: \(session.transcribedSegments)/\(session.totalSegments) = \(session.transcriptionProgress)")
        } else {
            statusLabel.text = "Complete"
            statusLabel.textColor = .systemGreen
            progressView.isHidden = true
            segmentCountLabel.isHidden = true
        }
        
        //  Transcription preview with real-time updates
        let transcriptionText = session.segments
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .compactMap { $0.transcription?.text }
            .joined(separator: " ")
        
        if transcriptionText.isEmpty {
            if session.totalSegments > 0 && session.transcribedSegments == 0 {
                transcriptionPreviewLabel.text = "Transcription in progress..."
                transcriptionPreviewLabel.textColor = .systemBlue
            } else {
                transcriptionPreviewLabel.text = "No transcription available"
                transcriptionPreviewLabel.textColor = .tertiaryLabel
            }
        } else {
            transcriptionPreviewLabel.text = transcriptionText
            transcriptionPreviewLabel.textColor = .secondaryLabel
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

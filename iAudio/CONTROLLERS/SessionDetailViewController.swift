//
//  SessionDetailViewController.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import UIKit
import SwiftData
import Combine

class SessionDetailViewController: UIViewController {
    
    private let session: RecordingSession
    private let audioPlayerManager = AudioPlayerManager()
    private var cancellables = Set<AnyCancellable>()
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressView = UIProgressView()
    private let playButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let tableView = UITableView()
    private let statsView = UIView()
    private let segmentCountLabel = UILabel()
    private let transcriptionStatusLabel = UILabel()
    
    // Audio playback controls
    private let audioControlsView = UIView()
    private let playbackProgressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let playbackRateButton = UIButton(type: .system)
    
    init(session: RecordingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupAudioBindings()
        configureContent()
        loadAudioSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshContent()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop playback when leaving the view
        audioPlayerManager.stop()
    }
    
    private func setupUI() {
        title = "Recording Details"
        view.backgroundColor = .systemBackground
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareButtonTapped)
        )
        
        // Header view setup
        headerView.backgroundColor = .systemGray6
        headerView.layer.cornerRadius = 12
        
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.numberOfLines = 0
        
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        durationLabel.textColor = .label
        
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .systemGray5
        progressView.layer.cornerRadius = 2
        
        // Audio controls setup
        audioControlsView.backgroundColor = .systemBackground
        audioControlsView.layer.borderWidth = 1
        audioControlsView.layer.borderColor = UIColor.systemGray4.cgColor
        audioControlsView.layer.cornerRadius = 12
        
        // Playback buttons
        playButton.setTitle("▶︎", for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .medium)
        playButton.backgroundColor = .systemBlue
        playButton.setTitleColor(.white, for: .normal)
        playButton.layer.cornerRadius = 22
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        
        pauseButton.setTitle("⏸", for: .normal)
        pauseButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        pauseButton.backgroundColor = .systemOrange
        pauseButton.setTitleColor(.white, for: .normal)
        pauseButton.layer.cornerRadius = 22
        pauseButton.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)
        pauseButton.isEnabled = false
        
        stopButton.setTitle("⏹", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        stopButton.backgroundColor = .systemRed
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 22
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)
        stopButton.isEnabled = false
        
        // Playback progress slider
        playbackProgressSlider.minimumValue = 0
        playbackProgressSlider.maximumValue = 1
        playbackProgressSlider.value = 0
        playbackProgressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        playbackProgressSlider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        
        // Time labels
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        currentTimeLabel.text = "00:00"
        currentTimeLabel.textAlignment = .left
        
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        totalTimeLabel.text = "00:00"
        totalTimeLabel.textAlignment = .right
        
        // Playback rate button
        playbackRateButton.setTitle("1.0x", for: .normal)
        playbackRateButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        playbackRateButton.backgroundColor = .systemGray6
        playbackRateButton.layer.cornerRadius = 12
        playbackRateButton.addTarget(self, action: #selector(playbackRateButtonTapped), for: .touchUpInside)
        
        // Action buttons
        exportButton.setTitle("⤴ Export", for: .normal)
        exportButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        exportButton.backgroundColor = .systemGreen
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.layer.cornerRadius = 8
        exportButton.addTarget(self, action: #selector(exportButtonTapped), for: .touchUpInside)
        
        deleteButton.setTitle("🗑 Delete", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        deleteButton.backgroundColor = .systemRed
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.layer.cornerRadius = 8
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        
        // Stats view
        statsView.backgroundColor = .systemBackground
        statsView.layer.borderWidth = 1
        statsView.layer.borderColor = UIColor.systemGray4.cgColor
        statsView.layer.cornerRadius = 8
        
        segmentCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        segmentCountLabel.textAlignment = .center
        
        transcriptionStatusLabel.font = .systemFont(ofSize: 14)
        transcriptionStatusLabel.textAlignment = .center
        transcriptionStatusLabel.textColor = .secondaryLabel
        
        // Table view setup
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SegmentTableViewCell.self, forCellReuseIdentifier: "SegmentCell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        [headerView, audioControlsView, statsView, tableView].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        [titleLabel, dateLabel, durationLabel, progressView, exportButton, deleteButton].forEach {
            headerView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        [playButton, pauseButton, stopButton, playbackProgressSlider, currentTimeLabel, totalTimeLabel, playbackRateButton].forEach {
            audioControlsView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        [segmentCountLabel, transcriptionStatusLabel].forEach {
            statsView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Header view
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -16),
            
            durationLabel.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            progressView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            // Action buttons
            exportButton.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            exportButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            exportButton.heightAnchor.constraint(equalToConstant: 36),
            exportButton.widthAnchor.constraint(equalToConstant: 80),
            
            deleteButton.topAnchor.constraint(equalTo: exportButton.topAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),
            deleteButton.widthAnchor.constraint(equalToConstant: 80),
            deleteButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16),
            
            // Audio controls view
            audioControlsView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            audioControlsView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            audioControlsView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            audioControlsView.heightAnchor.constraint(equalToConstant: 120),
            
            // Playback buttons
            playButton.topAnchor.constraint(equalTo: audioControlsView.topAnchor, constant: 16),
            playButton.leadingAnchor.constraint(equalTo: audioControlsView.leadingAnchor, constant: 16),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            
            pauseButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            pauseButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
            pauseButton.widthAnchor.constraint(equalToConstant: 44),
            pauseButton.heightAnchor.constraint(equalToConstant: 44),
            
            stopButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: pauseButton.trailingAnchor, constant: 12),
            stopButton.widthAnchor.constraint(equalToConstant: 44),
            stopButton.heightAnchor.constraint(equalToConstant: 44),
            
            playbackRateButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
            playbackRateButton.trailingAnchor.constraint(equalTo: audioControlsView.trailingAnchor, constant: -16),
            playbackRateButton.widthAnchor.constraint(equalToConstant: 50),
            playbackRateButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Progress slider and time labels
            currentTimeLabel.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 16),
            currentTimeLabel.leadingAnchor.constraint(equalTo: audioControlsView.leadingAnchor, constant: 16),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 50),
            
            totalTimeLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            totalTimeLabel.trailingAnchor.constraint(equalTo: audioControlsView.trailingAnchor, constant: -16),
            totalTimeLabel.widthAnchor.constraint(equalToConstant: 50),
            
            playbackProgressSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            playbackProgressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            playbackProgressSlider.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -8),
            
            // Stats view
            statsView.topAnchor.constraint(equalTo: audioControlsView.bottomAnchor, constant: 16),
            statsView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            statsView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            statsView.heightAnchor.constraint(equalToConstant: 60),
            
            segmentCountLabel.topAnchor.constraint(equalTo: statsView.topAnchor, constant: 8),
            segmentCountLabel.leadingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: 16),
            segmentCountLabel.trailingAnchor.constraint(equalTo: statsView.trailingAnchor, constant: -16),
            
            transcriptionStatusLabel.topAnchor.constraint(equalTo: segmentCountLabel.bottomAnchor, constant: 4),
            transcriptionStatusLabel.leadingAnchor.constraint(equalTo: segmentCountLabel.leadingAnchor),
            transcriptionStatusLabel.trailingAnchor.constraint(equalTo: segmentCountLabel.trailingAnchor),
            transcriptionStatusLabel.bottomAnchor.constraint(equalTo: statsView.bottomAnchor, constant: -8),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: statsView.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 400),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupAudioBindings() {
        // Observe playback state
        audioPlayerManager.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.playButton.isEnabled = !isPlaying
                self?.pauseButton.isEnabled = isPlaying
                self?.stopButton.isEnabled = isPlaying
            }
            .store(in: &cancellables)
        
        // Observe playback progress
        audioPlayerManager.$playbackProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.playbackProgressSlider.value = progress
            }
            .store(in: &cancellables)
        
        // Observe current time
        audioPlayerManager.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime in
                self?.currentTimeLabel.text = self?.formatDuration(currentTime)
            }
            .store(in: &cancellables)
        
        // Observe duration
        audioPlayerManager.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.totalTimeLabel.text = self?.formatDuration(duration)
            }
            .store(in: &cancellables)
        
        // Observe playback rate
        audioPlayerManager.$playbackRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.playbackRateButton.setTitle("\(String(format: "%.1f", rate))x", for: .normal)
            }
            .store(in: &cancellables)
        
        // Observe errors
        audioPlayerManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                if let error = errorMessage {
                    self?.showErrorAlert(message: error)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadAudioSession() {
        // Load the session into the audio player
        audioPlayerManager.loadSession(session)
    }
    
    private func configureContent() {
        titleLabel.text = session.title
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        dateLabel.text = dateFormatter.string(from: session.createdDate)
        
        durationLabel.text = formatDuration(session.duration)
        progressView.progress = session.transcriptionProgress
        
        refreshContent()
    }
    
    private func refreshContent() {
        let totalSegments = session.totalSegments
        let transcribedSegments = session.transcribedSegments
        
        segmentCountLabel.text = "\(totalSegments) audio segments"
        
        if totalSegments == 0 {
            transcriptionStatusLabel.text = "Processing audio into segments..."
        } else if transcribedSegments == totalSegments {
            transcriptionStatusLabel.text = "All segments transcribed ✓"
        } else {
            transcriptionStatusLabel.text = "\(transcribedSegments) of \(totalSegments) segments transcribed"
        }
        
        tableView.reloadData()
    }
    
    // MARK: - Audio Control Actions
    @objc private func playButtonTapped() {
        audioPlayerManager.play()
    }
    
    @objc private func pauseButtonTapped() {
        audioPlayerManager.pause()
    }
    
    @objc private func stopButtonTapped() {
        audioPlayerManager.stop()
    }
    
    @objc private func sliderValueChanged() {
        let newTime = TimeInterval(playbackProgressSlider.value) * audioPlayerManager.duration
        audioPlayerManager.seek(to: newTime)
    }
    
    @objc private func sliderTouchEnded() {
        // Resume updating if was playing
        // This is automatically handled by the AudioPlayerManager
    }
    
    @objc private func playbackRateButtonTapped() {
        let alertController = UIAlertController(title: "Playback Speed", message: "Choose playback speed", preferredStyle: .actionSheet)
        
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        
        for speed in speeds {
            let title = "\(String(format: "%.2f", speed))x"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.audioPlayerManager.setPlaybackRate(speed)
            }
            if speed == audioPlayerManager.playbackRate {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = playbackRateButton
            popover.sourceRect = playbackRateButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    @objc private func exportButtonTapped() {
        let alertController = UIAlertController(title: "Export Options", message: "Choose what to export", preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "Export Transcription Text", style: .default) { [weak self] _ in
            self?.exportTranscription()
        })
        
        alertController.addAction(UIAlertAction(title: "Export Audio File", style: .default) { [weak self] _ in
            self?.exportAudio()
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    @objc private func deleteButtonTapped() {
        let alertController = UIAlertController(
            title: "Delete Recording",
            message: "Are you sure you want to delete '\(session.title)'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteRecording()
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    private func deleteRecording() {
        guard let context = modelContext else {
            showErrorAlert(message: "Database context not available")
            return
        }
        
        print("🗑️ Deleting session: \(session.title)")
        
        // Stop any current playback
        audioPlayerManager.stop()
        
        // Delete audio files
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Delete main audio file
        do {
            let mainAudioURL = documentsDirectory.appendingPathComponent(session.audioFilePath)
            if FileManager.default.fileExists(atPath: mainAudioURL.path) {
                try FileManager.default.removeItem(at: mainAudioURL)
                print("✅ Deleted main audio file")
            }
        } catch {
            print("⚠️ Failed to delete main audio file: \(error)")
        }
        
        // Delete segment files
        for segment in session.segments {
            do {
                let segmentURL = documentsDirectory.appendingPathComponent(segment.audioFilePath)
                if FileManager.default.fileExists(atPath: segmentURL.path) {
                    try FileManager.default.removeItem(at: segmentURL)
                    print("✅ Deleted segment file: \(segment.audioFilePath)")
                }
            } catch {
                print("⚠️ Failed to delete segment file: \(error)")
            }
        }
        
        // Delete from database
        context.delete(session)
        
        do {
            try context.save()
            print("✅ Session deleted from database")
            
            // Navigate back to the main list
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
            
        } catch {
            print("❌ Failed to save after deletion: \(error)")
            showErrorAlert(message: "Failed to delete recording: \(error.localizedDescription)")
        }
    }
    
    private func exportTranscription() {
        let transcriptionText = generateTranscriptionText()
        let activityVC = UIActivityViewController(activityItems: [transcriptionText], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    private func exportAudio() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsDirectory.appendingPathComponent(session.audioFilePath)
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            let alert = UIAlertController(title: "File Not Found", message: "The audio file could not be found.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [audioURL], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func shareButtonTapped() {
        exportTranscription()
    }
    
    private func generateTranscriptionText() -> String {
        var text = "📝 \(session.title)\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        text += "📅 \(dateFormatter.string(from: session.createdDate))\n"
        
        text += "⏱️ Duration: \(formatDuration(session.duration))\n"
        text += "🔢 Segments: \(session.totalSegments)\n\n"
        
        let sortedSegments = session.segments.sorted { $0.segmentIndex < $1.segmentIndex }
        
        if sortedSegments.isEmpty {
            text += "(No segments available)"
        } else {
            for segment in sortedSegments {
                if let transcription = segment.transcription {
                    let timeRange = "[\(formatDuration(segment.startTime)) - \(formatDuration(segment.endTime))]"
                    text += "\(timeRange) \(transcription.text)\n\n"
                } else {
                    let timeRange = "[\(formatDuration(segment.startTime)) - \(formatDuration(segment.endTime))]"
                    text += "\(timeRange) [Transcription not available]\n\n"
                }
            }
        }
        
        return text
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    deinit {
        cancellables.removeAll()
        audioPlayerManager.stop()
    }
}

extension SessionDetailViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return session.segments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SegmentCell", for: indexPath) as! SegmentTableViewCell
        let sortedSegments = session.segments.sorted { $0.segmentIndex < $1.segmentIndex }
        cell.configure(with: sortedSegments[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Transcription Segments"
    }
}

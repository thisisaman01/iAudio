//
//  AudioRecordingManager.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import AVFoundation
import Combine
import UIKit
import SwiftData

class AudioRecordingManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var segmentTimer: Timer?
    
    @Published var isRecording = false
    @Published var currentSession: RecordingSession?
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
    
    private let segmentDuration: TimeInterval = 30.0
    private var currentSegmentStartTime: TimeInterval = 0
    private let documentsDirectory: URL
    
    // SwiftData context for saving
    weak var modelContext: ModelContext?
    
    // MARK: - Initialization
    override init() {
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        super.init()
        setupNotifications()
    }
    
    // MARK: - Audio Session Setup
    private func setupRecordingAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Stop any current audio session
            try audioSession.setActive(false)
            
            // Configure for recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            
            print("✅ Recording audio session configured successfully")
        } catch {
            handleError("Failed to setup recording audio session: \(error.localizedDescription)")
        }
    }
    
    private func resetAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
            print("✅ Audio session deactivated")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Recording Control
    func startRecording(title: String) {
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }
        
        print("🎤 Starting recording: \(title)")
        
        // Setup audio session specifically for recording
        setupRecordingAudioSession()
        
        do {
            let sessionFileName = "session_\(Date().timeIntervalSince1970).m4a"
            let sessionFileURL = documentsDirectory.appendingPathComponent(sessionFileName)
            
            // Create recording session and save to SwiftData immediately
            let session = RecordingSession(title: title, audioFilePath: sessionFileName)
            currentSession = session
            
            // Save session to SwiftData
            saveSessionToDatabase(session)
            
            // Configure audio settings for high quality recording
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128000
            ]
            
            // Create and configure audio recorder
            audioRecorder = try AVAudioRecorder(url: sessionFileURL, settings: audioSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            
            // Give a small delay to ensure audio session is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Start recording
                let success = self.audioRecorder?.record() ?? false
                
                if success {
                    self.isRecording = true
                    self.recordingDuration = 0
                    self.currentSegmentStartTime = 0
                    
                    self.startTimers()
                    
                    print("✅ Recording started successfully")
                    print("🎵 Saving audio to: \(sessionFileURL.path)")
                    
                    // Clear any previous error
                    self.errorMessage = nil
                    
                } else {
                    self.handleError("Failed to start audio recorder - please try again")
                    self.resetAudioSession()
                }
            }
            
        } catch {
            handleError("Failed to start recording: \(error.localizedDescription)")
            resetAudioSession()
            print("❌ Recording setup error: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        print("⏹️ Stopping recording")
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        isRecording = false
        stopTimers()
        
        // Finalize current session
        if let session = currentSession {
            session.duration = recordingDuration
            session.isCompleted = true
            
            // Create final segment if needed
            if recordingDuration > currentSegmentStartTime {
                createAudioSegment(startTime: currentSegmentStartTime, endTime: recordingDuration)
            }
            
            // Update session in database
            updateSessionInDatabase(session)
            print("✅ Recording completed: \(session.title) - Duration: \(formatDuration(recordingDuration))")
            
            // ⚡ IMMEDIATE: Trigger final transcription processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.triggerFinalTranscription()
            }
        }
        
        currentSession = nil
        recordingDuration = 0
        audioLevel = 0
        
        // Reset audio session to allow playback
        resetAudioSession()
    }
    
    func pauseRecording() {
        guard isRecording else { return }
        print("⏸️ Pausing recording")
        audioRecorder?.pause()
        stopTimers()
    }
    
    func resumeRecording() {
        guard isRecording else { return }
        print("▶️ Resuming recording")
        let success = audioRecorder?.record() ?? false
        if success {
            startTimers()
        } else {
            handleError("Failed to resume recording")
        }
    }
    
    // MARK: - SwiftData Operations
    private func saveSessionToDatabase(_ session: RecordingSession) {
        guard let context = modelContext else {
            print("❌ No ModelContext available for saving session")
            return
        }
        
        do {
            context.insert(session)
            try context.save()
            print("✅ Session saved to database: \(session.title)")
        } catch {
            print("❌ Failed to save session: \(error)")
            handleError("Failed to save recording session: \(error.localizedDescription)")
        }
    }
    
    private func updateSessionInDatabase(_ session: RecordingSession) {
        guard let context = modelContext else {
            print("❌ No ModelContext available for updating session")
            return
        }
        
        do {
            try context.save()
            print("✅ Session updated in database: \(session.title)")
        } catch {
            print("❌ Failed to update session: \(error)")
            handleError("Failed to update recording session: \(error.localizedDescription)")
        }
    }
    
    private func saveSegmentToDatabase(_ segment: AudioSegment) {
        guard let context = modelContext else {
            print("❌ No ModelContext available for saving segment")
            return
        }
        
        do {
            context.insert(segment)
            try context.save()
            print("✅ Segment saved to database: \(segment.segmentIndex)")
        } catch {
            print("❌ Failed to save segment: \(error)")
        }
    }
    
    // MARK: - Segment Management
    private func createAudioSegment(startTime: TimeInterval, endTime: TimeInterval) {
        guard let session = currentSession else { return }
        
        print("🎬 Creating audio segment: \(formatDuration(startTime)) - \(formatDuration(endTime))")
        
        let segmentIndex = session.segments.count
        let segmentFileName = "segment_\(session.id.uuidString)_\(segmentIndex).m4a"
        
        let segment = AudioSegment(
            sessionId: session.id,
            segmentIndex: segmentIndex,
            startTime: startTime,
            endTime: endTime,
            audioFilePath: segmentFileName
        )
        
        // Set segment relationship
        segment.session = session
        session.segments.append(segment)
        session.totalSegments += 1
        
        // Save segment to database
        saveSegmentToDatabase(segment)
        
        // ✅ FIXED: Extract segment immediately and synchronously
        extractAudioSegmentSync(segment: segment)
    }
    private func extractAudioSegmentSync(segment: AudioSegment) {
        guard let session = currentSession else { return }
        
        print("✂️ Extracting audio segment: \(segment.segmentIndex)")
        
        let sessionFileURL = documentsDirectory.appendingPathComponent(session.audioFilePath)
        let segmentFileURL = documentsDirectory.appendingPathComponent(segment.audioFilePath)
        
        // Check if source file exists
        guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
            print("❌ Source audio file not found: \(sessionFileURL.path)")
            return
        }
        
        // Verify source file has content
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: sessionFileURL.path)[.size] as? UInt64 ?? 0
            print("📊 Source file size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("❌ Source file is empty")
                return
            }
        } catch {
            print("❌ Cannot read source file: \(error)")
            return
        }
        
        // ✅ FIXED: Use simpler file copying approach for immediate availability
        if segment.endTime <= recordingDuration || !isRecording {
            // Recording is complete or segment is from completed portion
            extractSegmentUsingAVAsset(segment: segment, sessionFileURL: sessionFileURL, segmentFileURL: segmentFileURL)
        } else {
            // For ongoing recording, create a simple copy and trim later
            createTemporarySegment(segment: segment, sessionFileURL: sessionFileURL, segmentFileURL: segmentFileURL)
        }
    }
    
    private func extractSegmentUsingAVAsset(segment: AudioSegment, sessionFileURL: URL, segmentFileURL: URL) {
        let asset = AVAsset(url: sessionFileURL)
        
        // Get asset duration to validate
        let assetDuration = CMTimeGetSeconds(asset.duration)
        print("📊 Asset duration: \(assetDuration)s, segment end: \(segment.endTime)s")
        
        // Ensure we don't try to extract beyond the actual file duration
        let actualEndTime = min(segment.endTime, assetDuration)
        let actualStartTime = min(segment.startTime, assetDuration)
        
        if actualStartTime >= actualEndTime {
            print("❌ Invalid segment times: \(actualStartTime) to \(actualEndTime)")
            return
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            print("❌ Failed to create export session for segment \(segment.segmentIndex)")
            return
        }
        
        exportSession.outputURL = segmentFileURL
        exportSession.outputFileType = .m4a
        
        let startCMTime = CMTime(seconds: actualStartTime, preferredTimescale: 44100)
        let durationCMTime = CMTime(seconds: actualEndTime - actualStartTime, preferredTimescale: 44100)
        exportSession.timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)
        
        // ✅ FIXED: Use synchronous export with semaphore
        let semaphore = DispatchSemaphore(value: 0)
        
        exportSession.exportAsynchronously {
            defer { semaphore.signal() }
            
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    print("✅ Segment extracted successfully: \(segment.segmentIndex)")
                    self.verifyAndQueueSegment(segment)
                case .failed:
                    print("❌ Segment extraction failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                    self.handleSegmentExtractionFailure(segment)
                case .cancelled:
                    print("⚠️ Segment extraction cancelled")
                default:
                    print("❓ Segment extraction status: \(exportSession.status)")
                }
            }
        }
        
        // Wait for export to complete (with timeout)
        let result = semaphore.wait(timeout: .now() + 10) // 10 second timeout
        
        if result == .timedOut {
            print("❌ Segment extraction timed out for segment \(segment.segmentIndex)")
            exportSession.cancelExport()
        }
    }

    // ✅ NEW: Create temporary segment for ongoing recordings
    private func createTemporarySegment(segment: AudioSegment, sessionFileURL: URL, segmentFileURL: URL) {
        // For ongoing recordings, copy the current file and we'll trim it later
        do {
            try FileManager.default.copyItem(at: sessionFileURL, to: segmentFileURL)
            print("✅ Created temporary segment file: \(segment.segmentIndex)")
            
            // Queue for transcription immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.verifyAndQueueSegment(segment)
            }
        } catch {
            print("❌ Failed to create temporary segment: \(error)")
            handleSegmentExtractionFailure(segment)
        }
    }

    // ✅ NEW: Verify segment file and queue for transcription
    private func verifyAndQueueSegment(_ segment: AudioSegment) {
        let segmentFileURL = documentsDirectory.appendingPathComponent(segment.audioFilePath)
        
        if FileManager.default.fileExists(atPath: segmentFileURL.path) {
            do {
                let fileSize = try FileManager.default.attributesOfItem(atPath: segmentFileURL.path)[.size] as? UInt64 ?? 0
                print("✅⚡ Segment file verified: \(segment.audioFilePath) (\(fileSize) bytes)")
                
                if fileSize > 1000 { // At least 1KB to have some content
                    // ⚡ IMMEDIATE: Process transcription immediately for better user experience
                    print("🚀 Triggering immediate transcription for segment \(segment.segmentIndex)")
                    
                    // Start transcription immediately instead of waiting for queue
                    DispatchQueue.main.async {
                        TranscriptionService.shared.processSegmentImmediately(segment)
                    }
                    
                    print("📋⚡ Segment immediately queued for transcription: \(segment.segmentIndex)")
                } else {
                    print("⚠️ Segment file too small: \(fileSize) bytes")
                    handleSegmentExtractionFailure(segment)
                }
            } catch {
                print("❌ Cannot verify segment file: \(error)")
                handleSegmentExtractionFailure(segment)
            }
        } else {
            print("❌ Segment file not found after extraction: \(segmentFileURL.path)")
            handleSegmentExtractionFailure(segment)
        }
    }

    // ⚡ ADDED: Real-time transcription for completed recordings
    func triggerFinalTranscription() {
        guard let session = currentSession else { return }
        
        print("🚀 Triggering final transcription for all segments")
        
        // Process any remaining segments immediately
        for segment in session.segments {
            if segment.transcription == nil && segment.transcriptionStatus == .pending {
                print("🚀 Processing remaining segment: \(segment.segmentIndex)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    TranscriptionService.shared.processSegmentImmediately(segment)
                }
            }
        }
    }

    // ✅ NEW: Handle segment extraction failures
    private func handleSegmentExtractionFailure(_ segment: AudioSegment) {
        print("❌ Segment extraction failed for segment \(segment.segmentIndex)")
        // Mark segment as failed but don't queue for transcription
        segment.transcriptionStatus = .failed
        saveSegmentUpdate(segment)
    }

    // ✅ FIXED: Better timing for segment creation
    private func createSegmentIfNeeded() {
        guard isRecording else { return }
        
        let segmentEndTime = currentSegmentStartTime + segmentDuration
        
        // Only create segment if we have enough recorded duration
        if recordingDuration >= segmentEndTime {
            print("🕐 Creating segment at \(formatDuration(recordingDuration))")
            createAudioSegment(startTime: currentSegmentStartTime, endTime: segmentEndTime)
            currentSegmentStartTime = segmentEndTime
        }
    }

    // ✅ ADD: Helper method to save segment updates
    private func saveSegmentUpdate(_ segment: AudioSegment) {
        guard let context = modelContext else { return }
        
        do {
            try context.save()
        } catch {
            print("❌ Failed to save segment update: \(error)")
        }
    }
    
    // MARK: - Timer Management
    private func startTimers() {
        // Recording duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRecordingProgress()
        }
        
        // Segment creation timer
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.createSegmentIfNeeded()
        }
    }
    
    private func stopTimers() {
        recordingTimer?.invalidate()
        segmentTimer?.invalidate()
        recordingTimer = nil
        segmentTimer = nil
    }
    
    private func updateRecordingProgress() {
        recordingDuration += 0.1
        
        // Update audio level from recorder metering
        audioRecorder?.updateMeters()
        if let recorder = audioRecorder {
            let averagePower = recorder.averagePower(forChannel: 0)
            let normalizedLevel = pow(10, averagePower / 20) // Convert dB to linear scale
            audioLevel = Float(max(0, min(1, normalizedLevel)))
        }
    }
    
//    private func createSegmentIfNeeded() {
//        let segmentEndTime = currentSegmentStartTime + segmentDuration
//        
//        if recordingDuration >= segmentEndTime {
//            createAudioSegment(startTime: currentSegmentStartTime, endTime: segmentEndTime)
//            currentSegmentStartTime = segmentEndTime
//        }
//    }
    
    // MARK: - Notification Handlers
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        print("🔔 Audio session interruption: \(type == .began ? "began" : "ended")")
        
        switch type {
        case .began:
            if isRecording {
                pauseRecording()
            }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && isRecording {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.resumeRecording()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        print("🔀 Audio route change: \(reason.rawValue)")
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Handle route changes gracefully
            if isRecording {
                // Re-setup audio session for recording
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.setupRecordingAudioSession()
                }
            }
        default:
            break
        }
    }
    
    @objc private func appWillResignActive() {
        print("📱 App will resign active")
        // Recording continues in background if proper entitlements are set
    }
    
    @objc private func appDidBecomeActive() {
        print("📱 App did become active")
        if isRecording {
            setupRecordingAudioSession()
        }
    }
    
    // MARK: - Helper Methods
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            print("❌ AudioRecordingManager Error: \(message)")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    deinit {
        print("🗑️ AudioRecordingManager deinit")
        NotificationCenter.default.removeObserver(self)
        if isRecording {
            stopRecording()
        }
        resetAudioSession()
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecordingManager: AVAudioRecorderDelegate {
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🎙️ Audio recorder finished recording successfully: \(flag)")
        
        if !flag {
            handleError("Recording failed to complete successfully")
        }
        
        // Verify file was created
        let url = recorder.url
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("📁 Recording file exists: \(fileExists) at \(url.path)")
        
        if fileExists {
            do {
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
                print("📊 Recording file size: \(fileSize) bytes")
            } catch {
                print("⚠️ Could not get file size: \(error)")
            }
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            handleError("Audio recording encode error: \(error.localizedDescription)")
        }
    }
}

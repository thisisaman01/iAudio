//
//  AudioPlayerManager.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import AVFoundation
import Combine

class AudioPlayerManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Float = 0
    @Published var playbackRate: Float = 1.0
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var currentSession: RecordingSession?
    private var isUserSeeking = false
    
    // MARK: - Audio Session Setup
    override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupPlaybackAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Stop any current audio session
            try audioSession.setActive(false)
            
            // Configure for playback only (no defaultToSpeaker needed)
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            
            print("✅ Audio playback session configured")
        } catch {
            handleError("Failed to setup audio session for playback: \(error.localizedDescription)")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
            print("✅ Playback audio session deactivated")
        } catch {
            print("⚠️ Failed to deactivate playback audio session: \(error)")
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
    }
    
    // MARK: - Public Playback Methods
    
    func loadSession(_ session: RecordingSession) {
        stop() // Stop any current playback
        
        currentSession = session
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsDirectory.appendingPathComponent(session.audioFilePath)
        
        print("🎵 Loading audio from: \(audioURL.path)")
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            handleError("Audio file not found: \(session.audioFilePath)")
            print("❌ File does not exist at path: \(audioURL.path)")
            
            // List files in documents directory for debugging
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: documentsDirectory.path)
                print("📁 Files in documents directory: \(files)")
            } catch {
                print("❌ Could not list directory contents: \(error)")
            }
            
            return
        }
        
        // Check file size
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = fileAttributes[.size] as? UInt64 ?? 0
            print("📊 Audio file size: \(fileSize) bytes")
            
            if fileSize == 0 {
                handleError("Audio file is empty")
                return
            }
        } catch {
            print("⚠️ Could not get file attributes: \(error)")
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true // Enable playback rate control
            
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            playbackProgress = 0
            
            print("✅ Audio loaded: \(session.title) - Duration: \(formatDuration(duration))")
            
            // Clear any previous error
            DispatchQueue.main.async {
                self.errorMessage = nil
            }
            
        } catch {
            handleError("Failed to load audio: \(error.localizedDescription)")
            print("❌ Audio loading error details: \(error)")
        }
    }
    
    func play() {
        guard let player = audioPlayer else {
            handleError("No audio loaded")
            return
        }
        
        // Setup audio session for playback
        setupPlaybackAudioSession()
        
        // Small delay to ensure audio session is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            player.rate = self.playbackRate
            
            if player.play() {
                self.isPlaying = true
                self.isPaused = false
                self.startPlaybackTimer()
                print("▶️ Playback started at rate \(self.playbackRate)x")
            } else {
                self.handleError("Failed to start playback")
            }
        }
    }
    
    func pause() {
        guard let player = audioPlayer else { return }
        
        player.pause()
        isPlaying = false
        isPaused = true
        stopPlaybackTimer()
        print("⏸️ Playback paused at \(formatDuration(currentTime))")
    }
    
    func stop() {
        guard let player = audioPlayer else { return }
        
        player.stop()
        player.currentTime = 0
        
        isPlaying = false
        isPaused = false
        currentTime = 0
        playbackProgress = 0
        
        stopPlaybackTimer()
        deactivateAudioSession()
        print("⏹️ Playback stopped")
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        
        let clampedTime = max(0, min(time, duration))
        
        isUserSeeking = true
        player.currentTime = clampedTime
        currentTime = clampedTime
        playbackProgress = duration > 0 ? Float(clampedTime / duration) : 0
        isUserSeeking = false
        
        print("🔍 Seeked to: \(formatDuration(clampedTime))")
    }
    
    func setPlaybackRate(_ rate: Float) {
        let clampedRate = max(0.5, min(2.0, rate)) // Clamp between 0.5x and 2.0x
        playbackRate = clampedRate
        
        if let player = audioPlayer, isPlaying {
            player.rate = clampedRate
        }
        
        print("🏃 Playback rate set to: \(clampedRate)x")
    }
    
    // MARK: - Timer Management
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackProgress()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackProgress() {
        guard let player = audioPlayer, !isUserSeeking else { return }
        
        currentTime = player.currentTime
        playbackProgress = duration > 0 ? Float(currentTime / duration) : 0
        
        // Check if playback has finished
        if currentTime >= duration && isPlaying {
            DispatchQueue.main.async {
                self.handlePlaybackFinished()
            }
        }
    }
    
    private func handlePlaybackFinished() {
        isPlaying = false
        isPaused = false
        currentTime = duration
        playbackProgress = 1.0
        stopPlaybackTimer()
        deactivateAudioSession()
        
        print("✅ Playback finished")
    }
    
    // MARK: - Convenience Methods
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }
    
    func skipBackward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }
    
    func rewind() {
        seek(to: 0)
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            print("❌ AudioPlayerManager Error: \(message)")
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            if isPlaying {
                pause()
                print("🔔 Audio session interruption began - paused playback")
            }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && isPaused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.play()
                    print("🔔 Audio session interruption ended - resumed playback")
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
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged, pause playback
            if isPlaying {
                pause()
                print("🎧 Audio route changed - paused playback")
            }
        case .newDeviceAvailable:
            print("🎧 New audio device available")
        default:
            print("🎧 Audio route changed: \(reason.rawValue)")
        }
    }
    
    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
        print("🗑️ AudioPlayerManager deinitialized")
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerManager: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.handlePlaybackFinished()
            print("✅ Audio player finished playing successfully: \(flag)")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            handleError("Audio decode error: \(error.localizedDescription)")
        }
    }
}

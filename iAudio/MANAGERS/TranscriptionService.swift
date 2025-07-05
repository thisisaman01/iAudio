//
//  TranscriptionService.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import UIKit  
import Speech
import SwiftData

class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    // MARK: - Properties
    private let networkQueue = DispatchQueue(label: "transcription.network", qos: .background)
    private let processingQueue = DispatchQueue(label: "transcription.processing", qos: .background)
    private let session = URLSession.shared
    private var pendingSegments: [AudioSegment] = []
    private let maxRetries = 5
    private let baseDelay: TimeInterval = 1.0
    
    // Configuration
    private var openAIAPIKey: String = ""
    private let openAIEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    
    // Local speech recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private let speechRecognitionQueue = DispatchQueue(label: "speech.recognition", qos: .background)
    
    // Weak reference to model context
    weak var modelContext: ModelContext?
    
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var pendingTranscriptions = 0
    @Published var completedTranscriptions = 0
    @Published var failedTranscriptions = 0
    
    // MARK: - Initialization
    private init() {
        setupSpeechRecognition()
        loadAPIKey()
        startProcessingQueue()
        setupNotifications()
    }
    
    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("❌ Speech recognition not authorized: \(status)")
                @unknown default:
                    print("❓ Unknown speech recognition status")
                }
            }
        }
    }
    
    private func loadAPIKey() {
        // Try to load from Keychain first
        if let apiKey = KeychainManager.shared.getAPIKey() {
            openAIAPIKey = apiKey
            print("✅ OpenAI API key loaded from Keychain")
        } else {
            print("⚠️ No OpenAI API key found - will use local transcription only")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    // MARK: - Public Methods
    func setAPIKey(_ apiKey: String) {
        openAIAPIKey = apiKey
        KeychainManager.shared.saveAPIKey(apiKey)
        print("✅ OpenAI API key updated")
    }
    
    func queueSegmentForTranscription(_ segment: AudioSegment) {
        // ⚡ IMMEDIATE: Process on main queue for faster response
        DispatchQueue.main.async {
            self.pendingSegments.append(segment)
            self.updatePendingCount()
            print("📋⚡ Fast queued segment for transcription: \(segment.segmentIndex)")
            
            // ⚡ IMMEDIATE: Try to process immediately if not busy
            if !self.isProcessing {
                self.processNextSegment()
            }
        }
    }
    
    // MARK: - Processing Queue
    private func startProcessingQueue() {
        // ⚡ FASTER: Process segments every 0.5 seconds instead of 2 seconds
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.processNextSegment()
        }
    }
    
    private func processNextSegment() {
        processingQueue.async {
            guard !self.pendingSegments.isEmpty,
                  !self.isProcessing else { return }
            
            let segment = self.pendingSegments.removeFirst()
            self.updatePendingCount()
            
            DispatchQueue.main.async {
                self.isProcessing = true
            }
            
            if segment.retryCount >= self.maxRetries {
                print("🔄 Max retries reached, using local transcription for segment \(segment.segmentIndex)")
                self.processWithLocalTranscription(segment)
                return
            }
            
            segment.transcriptionStatus = .processing
            self.saveSegmentUpdate(segment)
            
            if self.openAIAPIKey.isEmpty {
                print("🏠 No API key, using local transcription for segment \(segment.segmentIndex)")
                // ⚡ IMMEDIATE: Process immediately instead of queuing
                self.processWithLocalTranscription(segment)
            } else {
                self.transcribeWithOpenAI(segment) { [weak self] success in
                    if !success {
                        segment.retryCount += 1
                        // ⚡ FASTER: Reduced retry delay from 2.0s to 0.5s
                        let delay = min(0.5, self?.calculateRetryDelay(for: segment.retryCount) ?? 0.5)
                        
                        print("⏰ Retrying segment \(segment.segmentIndex) in \(delay)s (attempt \(segment.retryCount))")
                        
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            self?.queueSegmentForTranscription(segment)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self?.isProcessing = false
                    }
                }
            }
        }
    }
    
    // MARK: - OpenAI Whisper Transcription
    private func transcribeWithOpenAI(_ segment: AudioSegment, completion: @escaping (Bool) -> Void) {
        guard let audioData = loadAudioData(for: segment) else {
            print("❌ Failed to load audio data for segment \(segment.segmentIndex)")
            completion(false)
            return
        }
        
        print("🌐 Transcribing segment \(segment.segmentIndex) with OpenAI Whisper")
        
        var request = URLRequest(url: URL(string: openAIEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add language field (optional)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add response_format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let startTime = Date()
        
        session.dataTask(with: request) { [weak self] data, response, error in
            let processingTime = Date().timeIntervalSince(startTime)
            
            if let error = error {
                print("❌ OpenAI transcription error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                completion(false)
                return
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                print("❌ HTTP error: \(httpResponse.statusCode)")
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("Error details: \(errorString)")
                }
                completion(false)
                return
            }
            
            guard let data = data else {
                print("❌ No response data")
                completion(false)
                return
            }
            
            do {
                let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let text = result?["text"] as? String else {
                    print("❌ No text in response")
                    completion(false)
                    return
                }
                
                // Extract confidence if available (from segments)
                var confidence: Float = 0.95
                if let segments = result?["segments"] as? [[String: Any]] {
                    let avgConfidence = segments.compactMap { $0["avg_logprob"] as? Double }
                        .reduce(0, +) / Double(segments.count)
                    confidence = Float(max(0, min(1, (avgConfidence + 1) / 2))) // Normalize logprob to 0-1
                }
                
                let transcription = TranscriptionResult(
                    segmentId: segment.id,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: confidence,
                    processingTime: processingTime,
                    transcriptionService: "OpenAI Whisper"
                )
                
                DispatchQueue.main.async {
                    segment.transcription = transcription
                    segment.transcriptionStatus = .completed
                    segment.session?.transcribedSegments += 1
                    
                    self?.saveTranscriptionResult(transcription, for: segment)
                    self?.updateCompletedCount()
                    
                    print("✅ OpenAI transcription completed for segment \(segment.segmentIndex)")
                    print("📝 Text: \(text.prefix(50))...")
                }
                
                completion(true)
                
            } catch {
                print("❌ Failed to parse OpenAI response: \(error)")
                completion(false)
            }
        }.resume()
    }
    
    // MARK: - Local Speech Recognition
    private func processWithLocalTranscription(_ segment: AudioSegment) {
        print("🏠⚡ Fast processing segment \(segment.segmentIndex) with Apple Speech Recognition")
        
        // ⚡ MAIN QUEUE: Update status on main queue
        DispatchQueue.main.async {
            segment.transcriptionStatus = .localProcessing
            self.saveSegmentUpdate(segment)
        }
        
        guard let speechRecognizer = setupSpeechRecognizer() else {
            print("❌ Speech recognizer not available")
            handleTranscriptionFailure(segment)
            return
        }
        
        guard let audioURL = getAudioURL(for: segment) else {
            print("❌ Audio file not found for segment \(segment.segmentIndex)")
            handleTranscriptionFailure(segment)
            return
        }
        
        print("🎵⚡ Fast processing audio file: \(audioURL.path)")
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .confirmation
        request.contextualStrings = ["recording", "test", "check"]
        
        let startTime = Date()
        
        speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            let processingTime = Date().timeIntervalSince(startTime)
            
            if let error = error {
                print("❌ Apple Speech recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.handleTranscriptionFailure(segment)
                }
                return
            }
            
            guard let result = result else {
                print("❌ No speech recognition result")
                DispatchQueue.main.async {
                    self?.handleTranscriptionFailure(segment)
                }
                return
            }
            
            if result.isFinal {
                let text = result.bestTranscription.formattedString
                print("🎯⚡ Fast transcription: '\(text)' (took \(String(format: "%.1f", processingTime))s)")
                
                let confidence = self?.calculateEnhancedConfidence(from: result.bestTranscription) ?? 0.8
                let cleanedText = self?.cleanupTranscriptionText(text) ?? text
                
                let transcription = TranscriptionResult(
                    segmentId: segment.id,
                    text: cleanedText,
                    confidence: confidence,
                    processingTime: processingTime,
                    transcriptionService: "Apple Speech (Fast)"
                )
                
                // ⚡ CRITICAL: All database updates on main queue
                DispatchQueue.main.async {
                    segment.transcription = transcription
                    segment.transcriptionStatus = .localCompleted
                    segment.session?.transcribedSegments += 1
                    
                    self?.saveTranscriptionResult(transcription, for: segment)
                    self?.updateCompletedCount()
                    
                    print("✅⚡ Fast Apple Speech transcription completed for segment \(segment.segmentIndex)")
                    print("📝 Final text: '\(cleanedText)'")
                    print("🎯 Confidence: \(Int(confidence * 100))%")
                    print("⏱️ Processing time: \(String(format: "%.1f", processingTime))s")
                    
                    self?.isProcessing = false
                }
            }
        }
    }
    // ✅ NEW: Better speech recognizer setup
    private func setupSpeechRecognizer() -> SFSpeechRecognizer? {
        // Try device locale first
        var recognizer = SFSpeechRecognizer(locale: Locale.current)
        
        if recognizer == nil || !recognizer!.isAvailable {
            // Fallback to English US
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        
        if recognizer == nil || !recognizer!.isAvailable {
            // Final fallback to any available recognizer
            recognizer = SFSpeechRecognizer()
        }
        
        if let recognizer = recognizer {
            print("✅ Speech recognizer ready for locale: \(recognizer.locale.identifier ?? "unknown")")
            return recognizer
        } else {
            print("❌ No speech recognizer available")
            return nil
        }
    }

    
    // ✅ ENHANCED: Better confidence calculation
    private func calculateEnhancedConfidence(from transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        
        guard !segments.isEmpty else { return 0.5 }
        
        var totalConfidence = 0.0
        var totalWeight = 0.0
        
        for segment in segments {
            let wordLength = Double(segment.substring.count)
            let weight = max(1.0, wordLength / 5.0) // Longer words get more weight
            
            totalConfidence += Double(segment.confidence) * weight
            totalWeight += weight
        }
        
        let averageConfidence = totalWeight > 0 ? totalConfidence / totalWeight : 0.5
        
        // Boost confidence for longer transcriptions
        let lengthBoost = min(0.1, Double(transcription.formattedString.count) / 500.0)
        
        return Float(max(0.3, min(1.0, averageConfidence + lengthBoost)))
    }
    
    
    // ✅ ENHANCED: Text cleanup
    private func cleanupTranscriptionText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "   ", with: " ")
        
        // Capitalize first letter if not empty
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        // If text is too short or just noise, return empty
        if cleaned.count < 3 || cleaned.lowercased().contains("uh") && cleaned.count < 10 {
            return "(No clear speech detected)"
        }
        
        return cleaned
    }
    
    private func handleTranscriptionFailure(_ segment: AudioSegment) {
        DispatchQueue.main.async {
            segment.transcriptionStatus = .failed
            self.saveSegmentUpdate(segment)
            self.updateFailedCount()
            self.isProcessing = false
            
            print("❌ Transcription failed for segment \(segment.segmentIndex)")
        }
    }
    // MARK: - Helper Methods
    private func loadAudioData(for segment: AudioSegment) -> Data? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsDirectory.appendingPathComponent(segment.audioFilePath)
        return try? Data(contentsOf: audioURL)
    }
    
    private func getAudioURL(for segment: AudioSegment) -> URL? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsDirectory.appendingPathComponent(segment.audioFilePath)
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ Audio file does not exist: \(audioURL.path)")
            return nil
        }
        
        // ✅ ADDED: Verify file has content
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? UInt64 ?? 0
            print("📊 Audio file size: \(fileSize) bytes")
            
            if fileSize < 1000 { // Less than 1KB is probably empty/corrupt
                print("❌ Audio file too small: \(fileSize) bytes")
                return nil
            }
            
            return audioURL
        } catch {
            print("❌ Cannot read audio file attributes: \(error)")
            return nil
        }
    }
    
    private func calculateRetryDelay(for retryCount: Int) -> TimeInterval {
        // ⚡ FASTER: Much shorter delays
        return min(0.5, baseDelay * 0.5 * Double(retryCount))
    }
    // ⚡ ADDED: Immediate processing for real-time segments
    func processSegmentImmediately(_ segment: AudioSegment) {
        print("🚀 Immediate processing for segment \(segment.segmentIndex)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.processWithLocalTranscription(segment)
        }
    }
    
    // MARK: - Database Operations
    private func saveSegmentUpdate(_ segment: AudioSegment) {
        DispatchQueue.main.async {
            guard let context = self.modelContext else {
                print("❌ No ModelContext available for segment update")
                return
            }
            
            do {
                try context.save()
                print("✅ Segment update saved on main queue")
            } catch {
                print("❌ Failed to save segment update: \(error)")
            }
        }
    }
    
    private func saveTranscriptionResult(_ transcription: TranscriptionResult, for segment: AudioSegment) {
        // ⚡ CRITICAL: Always update database on main queue to avoid threading issues
        DispatchQueue.main.async {
            guard let context = self.modelContext else {
                print("❌ No ModelContext available for saving transcription")
                return
            }
            
            do {
                // Set relationships properly
                transcription.segment = segment
                segment.transcription = transcription
                
                context.insert(transcription)
                try context.save()
                
                print("✅ Transcription result saved to database on main queue")
                print("📊 Segment \(segment.segmentIndex) now has transcription: '\(transcription.text.prefix(30))...'")
                
                // ⚡ NOTIFY: Send notification that transcription completed
                NotificationCenter.default.post(
                    name: Notification.Name("TranscriptionCompleted"),
                    object: nil,
                    userInfo: ["segmentId": segment.id, "sessionId": segment.sessionId]
                )
                
            } catch {
                print("❌ Failed to save transcription result: \(error)")
            }
        }
    }
    // MARK: - Statistics Updates
    private func updatePendingCount() {
        DispatchQueue.main.async {
            self.pendingTranscriptions = self.pendingSegments.count
        }
    }
    
    private func updateCompletedCount() {
        DispatchQueue.main.async {
            self.completedTranscriptions += 1
        }
    }
    
    private func updateFailedCount() {
        DispatchQueue.main.async {
            self.failedTranscriptions += 1
        }
    }
    
    // MARK: - Background Handling
    @objc private func appDidEnterBackground() {
        print("📱 App entered background - pausing transcription processing")
        // Continue processing critical transcriptions only
    }
    
    @objc private func appWillEnterForeground() {
        print("📱 App will enter foreground - resuming transcription processing")
        processNextSegment()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Keychain Manager

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.yourcompany.iAudio"
    private let apiKeyAccount = "openai-api-key"
    
    private init() {}
    
    func saveAPIKey(_ apiKey: String) {
        let data = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ API key saved to Keychain")
        } else {
            print("❌ Failed to save API key to Keychain: \(status)")
        }
    }
    
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let apiKey = String(data: data, encoding: .utf8) {
            return apiKey
        }
        
        return nil
    }
    
    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("✅ API key deleted from Keychain")
        } else {
            print("❌ Failed to delete API key from Keychain: \(status)")
        }
    }
}

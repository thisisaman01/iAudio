//
//  SettingsManager.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import UIKit
import AVFoundation

// MARK: - Settings Enums

enum AudioQuality: String, CaseIterable {
    case low = "Low (22kHz)"
    case medium = "Medium (44kHz)"
    case high = "High (48kHz)"
    case lossless = "Lossless (96kHz)"
    
    var sampleRate: Double {
        switch self {
        case .low: return 22050
        case .medium: return 44100
        case .high: return 48000
        case .lossless: return 96000
        }
    }
}

enum AudioFormat: String, CaseIterable {
    case m4a = "M4A (AAC)"
    case wav = "WAV (Uncompressed)"
    case mp3 = "MP3 (Compressed)"
    
    var fileExtension: String {
        switch self {
        case .m4a: return "m4a"
        case .wav: return "wav"
        case .mp3: return "mp3"
        }
    }
}

enum TranscriptionServiceType: String, CaseIterable {
    case openAI = "OpenAI Whisper"
    case apple = "Apple Speech Recognition"
    case auto = "Auto (OpenAI then Apple)"
    
    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .auto: return true
        case .apple: return false
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case plainText = "Plain Text"
    case markdown = "Markdown"
    case json = "JSON"
    case csv = "CSV"
    case srt = "SRT Subtitles"
    
    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        case .csv: return "csv"
        case .srt: return "srt"
        }
    }
}

// MARK: - Settings Manager

class SettingsManager {
    static let shared = SettingsManager()
    
    private let userDefaults = UserDefaults.standard
    
    private init() {
        registerDefaults()
    }
    
    private func registerDefaults() {
        userDefaults.register(defaults: [
            "audioQuality": AudioQuality.medium.rawValue,
            "segmentDuration": 30.0,
            "backgroundRecording": true,
            "audioFormat": AudioFormat.m4a.rawValue,
            "transcriptionService": TranscriptionServiceType.auto.rawValue,
            "fallbackToLocal": true,
            "maxRetryAttempts": 5,
            "autoDeleteOld": false,
            "exportFormat": ExportFormat.plainText.rawValue,
            "autoDeleteDays": 30
        ])
    }
    
    // MARK: - Audio Settings
    
    var audioQuality: AudioQuality {
        get {
            let rawValue = userDefaults.string(forKey: "audioQuality") ?? AudioQuality.medium.rawValue
            return AudioQuality(rawValue: rawValue) ?? .medium
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: "audioQuality")
        }
    }
    
    var segmentDuration: TimeInterval {
        get {
            return userDefaults.double(forKey: "segmentDuration")
        }
        set {
            userDefaults.set(newValue, forKey: "segmentDuration")
        }
    }
    
    var backgroundRecording: Bool {
        get {
            return userDefaults.bool(forKey: "backgroundRecording")
        }
        set {
            userDefaults.set(newValue, forKey: "backgroundRecording")
        }
    }
    
    var audioFormat: AudioFormat {
        get {
            let rawValue = userDefaults.string(forKey: "audioFormat") ?? AudioFormat.m4a.rawValue
            return AudioFormat(rawValue: rawValue) ?? .m4a
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: "audioFormat")
        }
    }
    
    // MARK: - Transcription Settings
    
    var transcriptionService: TranscriptionServiceType {
        get {
            let rawValue = userDefaults.string(forKey: "transcriptionService") ?? TranscriptionServiceType.auto.rawValue
            return TranscriptionServiceType(rawValue: rawValue) ?? .auto
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: "transcriptionService")
        }
    }
    
    var fallbackToLocal: Bool {
        get {
            return userDefaults.bool(forKey: "fallbackToLocal")
        }
        set {
            userDefaults.set(newValue, forKey: "fallbackToLocal")
        }
    }
    
    var maxRetryAttempts: Int {
        get {
            return userDefaults.integer(forKey: "maxRetryAttempts")
        }
        set {
            userDefaults.set(newValue, forKey: "maxRetryAttempts")
        }
    }
    
    // MARK: - Storage Settings
    
    var autoDeleteOld: Bool {
        get {
            return userDefaults.bool(forKey: "autoDeleteOld")
        }
        set {
            userDefaults.set(newValue, forKey: "autoDeleteOld")
        }
    }
    
    var autoDeleteDays: Int {
        get {
            return userDefaults.integer(forKey: "autoDeleteDays")
        }
        set {
            userDefaults.set(newValue, forKey: "autoDeleteDays")
        }
    }
    
    var exportFormat: ExportFormat {
        get {
            let rawValue = userDefaults.string(forKey: "exportFormat") ?? ExportFormat.plainText.rawValue
            return ExportFormat(rawValue: rawValue) ?? .plainText
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: "exportFormat")
        }
    }
    
    // MARK: - Audio Settings Dictionary
    
    var audioSettings: [String: Any] {
        let format: AudioFormat = audioFormat
        let quality: AudioQuality = audioQuality
        
        switch format {
        case .m4a:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: quality.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: quality.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        case .mp3:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEGLayer3),
                AVSampleRateKey: quality.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
        }
    }
    
    // MARK: - Storage Management
    
    func calculateStorageUsage() -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
            let enumerator = FileManager.default.enumerator(
                at: documentsDirectory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: nil
            )
            
            var totalSize: Int64 = 0
            var audioFileCount = 0
            
            while let url = enumerator?.nextObject() as? URL {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isDirectory != true {
                    let fileSize = resourceValues.fileSize ?? 0
                    totalSize += Int64(fileSize)
                    
                    let fileExtension = url.pathExtension.lowercased()
                    if ["m4a", "wav", "mp3", "aac"].contains(fileExtension) {
                        audioFileCount += 1
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            
            return formatter.string(fromByteCount: totalSize)
            
        } catch {
            return "Unknown"
        }
    }
    
    func getDetailedStorageInfo() -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
            let enumerator = FileManager.default.enumerator(
                at: documentsDirectory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: nil
            )
            
            var totalSize: Int64 = 0
            var audioFileCount = 0
            var audioSize: Int64 = 0
            var segmentCount = 0
            var segmentSize: Int64 = 0
            
            while let url = enumerator?.nextObject() as? URL {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isDirectory != true {
                    let fileSize = resourceValues.fileSize ?? 0
                    totalSize += Int64(fileSize)
                    
                    let fileName = url.lastPathComponent
                    let fileExtension = url.pathExtension.lowercased()
                    
                    if ["m4a", "wav", "mp3", "aac"].contains(fileExtension) {
                        if fileName.contains("session_") {
                            audioFileCount += 1
                            audioSize += Int64(fileSize)
                        } else if fileName.contains("segment_") {
                            segmentCount += 1
                            segmentSize += Int64(fileSize)
                        }
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            
            return """
            Total Storage: \(formatter.string(fromByteCount: totalSize))
            
            Audio Files: \(audioFileCount) files (\(formatter.string(fromByteCount: audioSize)))
            Segments: \(segmentCount) files (\(formatter.string(fromByteCount: segmentSize)))
            
            Tip: Delete old recordings to free up space.
            """
            
        } catch {
            return "Unable to calculate storage usage."
        }
    }
    
    // MARK: - Cleanup Methods
    
    func cleanOldFiles() {
        guard autoDeleteOld else { return }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(autoDeleteDays * 24 * 60 * 60))
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = resourceValues.creationDate,
                   creationDate < cutoffDate {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ Deleted old file: \(fileURL.lastPathComponent)")
                }
            }
            
        } catch {
            print("❌ Failed to clean old files: \(error)")
        }
    }
    
    // MARK: - Reset Methods
    
    func resetToDefaults() {
        let keys = [
            "audioQuality",
            "segmentDuration",
            "backgroundRecording",
            "audioFormat",
            "transcriptionService",
            "fallbackToLocal",
            "maxRetryAttempts",
            "autoDeleteOld",
            "exportFormat",
            "autoDeleteDays"
        ]
        
        keys.forEach { userDefaults.removeObject(forKey: $0) }
        registerDefaults()
    }
}

// MARK: - Extensions

extension SettingsManager {
    
    func exportSettingsConfiguration() -> [String: Any] {
        return [
            "audioQuality": audioQuality.rawValue,
            "segmentDuration": segmentDuration,
            "backgroundRecording": backgroundRecording,
            "audioFormat": audioFormat.rawValue,
            "transcriptionService": transcriptionService.rawValue,
            "fallbackToLocal": fallbackToLocal,
            "maxRetryAttempts": maxRetryAttempts,
            "autoDeleteOld": autoDeleteOld,
            "exportFormat": exportFormat.rawValue,
            "autoDeleteDays": autoDeleteDays
        ]
    }
    
    func importSettingsConfiguration(_ settings: [String: Any]) {
        settings.forEach { key, value in
            userDefaults.set(value, forKey: key)
        }
    }
}

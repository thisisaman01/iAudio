//
//  Model.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import SwiftData

// MARK: - Transcription Status Enum

enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case localProcessing = "localProcessing"
    case localCompleted = "localCompleted"
}

// MARK: - Recording Session Model

@Model
final class RecordingSession {
    @Attribute(.unique) var id: UUID
    var createdDate: Date
    var duration: TimeInterval
    var title: String
    var audioFilePath: String
    var isCompleted: Bool
    var totalSegments: Int
    var transcribedSegments: Int
    
    @Relationship(deleteRule: .cascade, inverse: \AudioSegment.session)
    var segments: [AudioSegment]
    
    init(title: String, audioFilePath: String) {
        self.id = UUID()
        self.createdDate = Date()
        self.duration = 0
        self.title = title
        self.audioFilePath = audioFilePath
        self.isCompleted = false
        self.totalSegments = 0
        self.transcribedSegments = 0
        self.segments = []
    }
    
    var transcriptionProgress: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(transcribedSegments) / Float(totalSegments)
    }
}

// MARK: - Audio Segment Model

@Model
final class AudioSegment {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var segmentIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var audioFilePath: String
    var transcriptionStatusRaw: String
    var retryCount: Int
    var createdDate: Date
    
    @Relationship(deleteRule: .cascade, inverse: \TranscriptionResult.segment)
    var transcription: TranscriptionResult?
    
    @Relationship
    var session: RecordingSession?
    
    init(sessionId: UUID, segmentIndex: Int, startTime: TimeInterval, endTime: TimeInterval, audioFilePath: String) {
        self.id = UUID()
        self.sessionId = sessionId
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.endTime = endTime
        self.audioFilePath = audioFilePath
        self.transcriptionStatusRaw = TranscriptionStatus.pending.rawValue
        self.retryCount = 0
        self.createdDate = Date()
    }
    
    var transcriptionStatus: TranscriptionStatus {
        get {
            return TranscriptionStatus(rawValue: transcriptionStatusRaw) ?? .pending
        }
        set {
            transcriptionStatusRaw = newValue.rawValue
        }
    }
}

// MARK: - Transcription Result Model

@Model
final class TranscriptionResult {
    @Attribute(.unique) var id: UUID
    var segmentId: UUID
    var text: String
    var confidence: Float
    var processingTime: TimeInterval
    var transcriptionService: String
    var createdDate: Date
    
    @Relationship
    var segment: AudioSegment?
    
    init(segmentId: UUID, text: String, confidence: Float, processingTime: TimeInterval, transcriptionService: String) {
        self.id = UUID()
        self.segmentId = segmentId
        self.text = text
        self.confidence = confidence
        self.processingTime = processingTime
        self.transcriptionService = transcriptionService
        self.createdDate = Date()
    }
}

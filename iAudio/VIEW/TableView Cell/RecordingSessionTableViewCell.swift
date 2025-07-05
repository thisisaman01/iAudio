//
//  RecordingSessionTableViewCell.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//


import UIKit
import SwiftData

// MARK: - Recording Session Table View Cell

class RecordingSessionTableViewCell: UITableViewCell {
    
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressView = UIProgressView()
    private let statusLabel = UILabel()
    private let segmentCountLabel = UILabel()
    private let transcriptionPreviewLabel = UILabel()
    private let statusIconImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        accessoryType = .disclosureIndicator
        
        // Title label
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        
        // Date label
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        
        // Duration label
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        durationLabel.textColor = .label
        durationLabel.textAlignment = .right
        
        // Status label
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .right
        
        // Segment count label
        segmentCountLabel.font = .systemFont(ofSize: 12)
        segmentCountLabel.textColor = .secondaryLabel
        
        // Progress view
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .systemGray5
        progressView.layer.cornerRadius = 2
        
        // Transcription preview
        transcriptionPreviewLabel.font = .systemFont(ofSize: 13)
        transcriptionPreviewLabel.textColor = .secondaryLabel
        transcriptionPreviewLabel.numberOfLines = 2
        
        // Status icon
        statusIconImageView.contentMode = .scaleAspectFit
        statusIconImageView.tintColor = .systemBlue
        
        // Add subviews
        [titleLabel, dateLabel, durationLabel, progressView, statusLabel,
         segmentCountLabel, transcriptionPreviewLabel, statusIconImageView].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Title label
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            
            // Duration label
            durationLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            durationLabel.widthAnchor.constraint(equalToConstant: 60),
            
            // Date and segment count
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            
            segmentCountLabel.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            segmentCountLabel.leadingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 12),
            segmentCountLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),
            
            // Status
            statusLabel.topAnchor.constraint(equalTo: dateLabel.topAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: statusIconImageView.leadingAnchor, constant: -4),
            
            statusIconImageView.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusIconImageView.trailingAnchor.constraint(equalTo: durationLabel.trailingAnchor),
            statusIconImageView.widthAnchor.constraint(equalToConstant: 16),
            statusIconImageView.heightAnchor.constraint(equalToConstant: 16),
            
            // Progress view
            progressView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: durationLabel.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),
            
            // Transcription preview
            transcriptionPreviewLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 6),
            transcriptionPreviewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            transcriptionPreviewLabel.trailingAnchor.constraint(equalTo: durationLabel.trailingAnchor),
            transcriptionPreviewLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    

    func configure(with session: RecordingSession) {
        titleLabel.text = session.title
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateLabel.text = dateFormatter.string(from: session.createdDate)
        
        durationLabel.text = formatDuration(session.duration)
        
        let transcribedCount = session.transcribedSegments
        let totalCount = session.totalSegments
        
        segmentCountLabel.text = "\(totalCount) segments"
        
        progressView.progress = session.transcriptionProgress
        
        // ⚡ ENHANCED: Real-time status with better indicators
        if totalCount == 0 {
            statusLabel.text = "Processing"
            statusLabel.textColor = .systemOrange
            statusIconImageView.image = UIImage(systemName: "gearshape.fill")
            statusIconImageView.tintColor = .systemOrange
            
            // ⚡ ADDED: Animated processing indicator
            let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
            rotationAnimation.toValue = NSNumber(value: Double.pi * 2.0)
            rotationAnimation.duration = 1.0
            rotationAnimation.repeatCount = .infinity
            statusIconImageView.layer.add(rotationAnimation, forKey: "rotationAnimation")
            
        } else if transcribedCount == totalCount {
            statusLabel.text = "Complete"
            statusLabel.textColor = .systemGreen
            statusIconImageView.image = UIImage(systemName: "checkmark.circle.fill")
            statusIconImageView.tintColor = .systemGreen
            statusIconImageView.layer.removeAllAnimations()
            
        } else if transcribedCount > 0 {
            statusLabel.text = "\(transcribedCount)/\(totalCount)"
            statusLabel.textColor = .systemBlue
            statusIconImageView.image = UIImage(systemName: "waveform.circle.fill")
            statusIconImageView.tintColor = .systemBlue
            
            // ⚡ ADDED: Pulsing animation for active transcription
            let pulseAnimation = CABasicAnimation(keyPath: "opacity")
            pulseAnimation.fromValue = 0.5
            pulseAnimation.toValue = 1.0
            pulseAnimation.duration = 0.8
            pulseAnimation.repeatCount = .infinity
            pulseAnimation.autoreverses = true
            statusIconImageView.layer.add(pulseAnimation, forKey: "pulseAnimation")
            
        } else {
            statusLabel.text = "Pending"
            statusLabel.textColor = .systemGray
            statusIconImageView.image = UIImage(systemName: "ellipsis.circle")
            statusIconImageView.tintColor = .systemGray
            statusIconImageView.layer.removeAllAnimations()
        }
        
        // Transcription preview with real-time updates
        let completedSegments = session.segments.filter { $0.transcription != nil }
        if let latestTranscription = completedSegments.last?.transcription?.text {
            transcriptionPreviewLabel.text = latestTranscription
            transcriptionPreviewLabel.isHidden = false
        } else if transcribedCount > 0 {
            transcriptionPreviewLabel.text = "⚡ Transcription in progress..."
            transcriptionPreviewLabel.isHidden = false
        } else {
            transcriptionPreviewLabel.text = session.isCompleted ? "No transcription available" : "⏳ Preparing transcription..."
            transcriptionPreviewLabel.isHidden = false
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

//
//  SegmentTableViewCell.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import Foundation
import UIKit

class SegmentTableViewCell: UITableViewCell {
    
    private let timeLabel = UILabel()
    private let statusLabel = UILabel()
    private let transcriptionLabel = UILabel()
    private let confidenceLabel = UILabel()
    private let serviceLabel = UILabel()
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
        
        // Time label
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeLabel.textColor = .label
        
        // Status label
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .right
        
        // Status icon
        statusIconImageView.contentMode = .scaleAspectFit
        
        // Transcription label
        transcriptionLabel.font = .systemFont(ofSize: 15)
        transcriptionLabel.textColor = .label
        transcriptionLabel.numberOfLines = 0
        
        // Confidence label
        confidenceLabel.font = .systemFont(ofSize: 11)
        confidenceLabel.textColor = .secondaryLabel
        
        // Service label
        serviceLabel.font = .systemFont(ofSize: 11)
        serviceLabel.textColor = .systemBlue
        serviceLabel.textAlignment = .right
        
        // Add subviews
        [timeLabel, statusLabel, statusIconImageView, transcriptionLabel, confidenceLabel, serviceLabel].forEach {
            contentView.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Time label
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            // Status icon
            statusIconImageView.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            statusIconImageView.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -4),
            statusIconImageView.widthAnchor.constraint(equalToConstant: 16),
            statusIconImageView.heightAnchor.constraint(equalToConstant: 16),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.widthAnchor.constraint(equalToConstant: 80),
            
            // Transcription label
            transcriptionLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 8),
            transcriptionLabel.leadingAnchor.constraint(equalTo: timeLabel.leadingAnchor),
            transcriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Confidence label
            confidenceLabel.topAnchor.constraint(equalTo: transcriptionLabel.bottomAnchor, constant: 6),
            confidenceLabel.leadingAnchor.constraint(equalTo: timeLabel.leadingAnchor),
            confidenceLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            // Service label
            serviceLabel.topAnchor.constraint(equalTo: confidenceLabel.topAnchor),
            serviceLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            serviceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: confidenceLabel.trailingAnchor, constant: 8)
        ])
    }
    
    func configure(with segment: AudioSegment) {
        let startTime = formatDuration(segment.startTime)
        let endTime = formatDuration(segment.endTime)
        timeLabel.text = "\(startTime) - \(endTime)"
        
        // Configure status and appearance based on transcription status
        switch segment.transcriptionStatus {
        case .pending:
            statusLabel.text = "Pending"
            statusLabel.textColor = .systemOrange
            statusIconImageView.image = UIImage(systemName: "clock")
            statusIconImageView.tintColor = .systemOrange
            
        case .processing:
            statusLabel.text = "Processing"
            statusLabel.textColor = .systemBlue
            statusIconImageView.image = UIImage(systemName: "waveform")
            statusIconImageView.tintColor = .systemBlue
            
        case .completed:
            statusLabel.text = "Complete"
            statusLabel.textColor = .systemGreen
            statusIconImageView.image = UIImage(systemName: "checkmark.circle.fill")
            statusIconImageView.tintColor = .systemGreen
            
        case .failed:
            statusLabel.text = "Failed"
            statusLabel.textColor = .systemRed
            statusIconImageView.image = UIImage(systemName: "xmark.circle.fill")
            statusIconImageView.tintColor = .systemRed
            
        case .localProcessing:
            statusLabel.text = "Local"
            statusLabel.textColor = .systemPurple
            statusIconImageView.image = UIImage(systemName: "cpu")
            statusIconImageView.tintColor = .systemPurple
            
        case .localCompleted:
            statusLabel.text = "Local Done"
            statusLabel.textColor = .systemGreen
            statusIconImageView.image = UIImage(systemName: "checkmark.circle")
            statusIconImageView.tintColor = .systemGreen
        }
        
        // Configure transcription content
        if let transcription = segment.transcription {
            transcriptionLabel.text = transcription.text.isEmpty ? "(No speech detected)" : transcription.text
            transcriptionLabel.textColor = transcription.text.isEmpty ? .secondaryLabel : .label
            
            confidenceLabel.text = "Confidence: \(Int(transcription.confidence * 100))%"
            serviceLabel.text = transcription.transcriptionService
            
            confidenceLabel.isHidden = false
            serviceLabel.isHidden = false
        } else {
            switch segment.transcriptionStatus {
            case .pending:
                transcriptionLabel.text = "Waiting for transcription..."
            case .processing, .localProcessing:
                transcriptionLabel.text = "Transcribing audio..."
            case .failed:
                if segment.retryCount > 0 {
                    transcriptionLabel.text = "Transcription failed (attempted \(segment.retryCount) times)"
                } else {
                    transcriptionLabel.text = "Transcription failed"
                }
            default:
                transcriptionLabel.text = "No transcription available"
            }
            
            transcriptionLabel.textColor = .secondaryLabel
            confidenceLabel.isHidden = true
            serviceLabel.isHidden = true
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}


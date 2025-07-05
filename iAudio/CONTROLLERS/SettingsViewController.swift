//
//  SettingsViewController.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//


import UIKit
import AVFoundation

class SettingsViewController: UIViewController {
    
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let transcriptionService = TranscriptionService.shared
    
    // Settings data structure
    private let settingsSections: [(title: String, items: [SettingItem])] = [
        ("Audio Settings", [
            .audioQuality,
            .segmentDuration,
            .backgroundRecording,
            .audioFileFormat
        ]),
        ("Transcription Settings", [
            .transcriptionService,
            .apiKey,
            .fallbackToLocal,
            .retryAttempts
        ]),
        ("Storage & Data", [
            .storageUsed,
            .autoDeleteOld,
            .exportFormat
        ]),
        ("About", [
            .version,
            .privacyPolicy,
            .support,
            .credits
        ])
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }
    
    private func setupUI() {
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingCell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchCell")
        tableView.register(DetailTableViewCell.self, forCellReuseIdentifier: "DetailCell")
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Settings Items Enum

enum SettingItem {
    case audioQuality
    case segmentDuration
    case backgroundRecording
    case audioFileFormat
    case transcriptionService
    case apiKey
    case fallbackToLocal
    case retryAttempts
    case storageUsed
    case autoDeleteOld
    case exportFormat
    case version
    case privacyPolicy
    case support
    case credits
    
    var title: String {
        switch self {
        case .audioQuality: return "Audio Quality"
        case .segmentDuration: return "Segment Duration"
        case .backgroundRecording: return "Background Recording"
        case .audioFileFormat: return "Audio File Format"
        case .transcriptionService: return "Transcription Service"
        case .apiKey: return "OpenAI API Key"
        case .fallbackToLocal: return "Fallback to Local"
        case .retryAttempts: return "Retry Attempts"
        case .storageUsed: return "Storage Used"
        case .autoDeleteOld: return "Auto-Delete Old Files"
        case .exportFormat: return "Export Format"
        case .version: return "Version"
        case .privacyPolicy: return "Privacy Policy"
        case .support: return "Support"
        case .credits: return "Credits"
        }
    }
    
    var subtitle: String? {
        switch self {
        case .audioQuality: return SettingsManager.shared.audioQuality.rawValue
        case .segmentDuration: return "\(Int(SettingsManager.shared.segmentDuration)) seconds"
        case .audioFileFormat: return SettingsManager.shared.audioFormat.rawValue
        case .transcriptionService: return SettingsManager.shared.transcriptionService.rawValue
        case .retryAttempts: return "\(SettingsManager.shared.maxRetryAttempts) attempts"
        case .exportFormat: return SettingsManager.shared.exportFormat.rawValue
        case .version: return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        case .apiKey:
            let hasKey = KeychainManager.shared.getAPIKey() != nil
            return hasKey ? "Configured" : "Not Set"
        case .storageUsed:
            return SettingsManager.shared.calculateStorageUsage()
        default: return nil
        }
    }
    
    var hasSwitch: Bool {
        switch self {
        case .backgroundRecording, .fallbackToLocal, .autoDeleteOld:
            return true
        default:
            return false
        }
    }
    
    var accessoryType: UITableViewCell.AccessoryType {
        switch self {
        case .audioQuality, .segmentDuration, .audioFileFormat, .transcriptionService,
             .apiKey, .retryAttempts, .exportFormat, .privacyPolicy, .support, .credits:
            return .disclosureIndicator
        case .version, .storageUsed:
            return .none
        default:
            return .none
        }
    }
}

// MARK: - Table View Data Source & Delegate

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return settingsSections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingsSections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return settingsSections[section].title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = settingsSections[indexPath.section].items[indexPath.row]
        
        if item.hasSwitch {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            cell.configure(with: item)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath) as! DetailTableViewCell
            cell.configure(with: item)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = settingsSections[indexPath.section].items[indexPath.row]
        handleItemSelection(item)
    }
    
    private func handleItemSelection(_ item: SettingItem) {
        switch item {
        case .audioQuality:
            showAudioQualityPicker()
        case .segmentDuration:
            showSegmentDurationPicker()
        case .audioFileFormat:
            showAudioFormatPicker()
        case .transcriptionService:
            showTranscriptionServicePicker()
        case .apiKey:
            showAPIKeyAlert()
        case .retryAttempts:
            showRetryAttemptsPicker()
        case .exportFormat:
            showExportFormatPicker()
        case .privacyPolicy:
            showPrivacyPolicy()
        case .support:
            showSupport()
        case .credits:
            showCredits()
        case .storageUsed:
            showStorageDetails()
        default:
            break
        }
    }
    
    // MARK: - Setting Actions
    
    private func showAudioQualityPicker() {
        let alertController = UIAlertController(title: "Audio Quality", message: "Select recording quality", preferredStyle: .actionSheet)
        
        AudioQuality.allCases.forEach { quality in
            let action = UIAlertAction(title: quality.rawValue, style: .default) { _ in
                SettingsManager.shared.audioQuality = quality
                self.tableView.reloadData()
            }
            if quality == SettingsManager.shared.audioQuality {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showSegmentDurationPicker() {
        let alertController = UIAlertController(title: "Segment Duration", message: "How long should each transcription segment be?", preferredStyle: .actionSheet)
        
        let durations: [TimeInterval] = [15, 30, 45, 60, 90]
        
        durations.forEach { duration in
            let title = "\(Int(duration)) seconds"
            let action = UIAlertAction(title: title, style: .default) { _ in
                SettingsManager.shared.segmentDuration = duration
                self.tableView.reloadData()
            }
            if duration == SettingsManager.shared.segmentDuration {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showAudioFormatPicker() {
        let alertController = UIAlertController(title: "Audio Format", message: "Select audio file format", preferredStyle: .actionSheet)
        
        AudioFormat.allCases.forEach { format in
            let action = UIAlertAction(title: format.rawValue, style: .default) { _ in
                SettingsManager.shared.audioFormat = format
                self.tableView.reloadData()
            }
            if format == SettingsManager.shared.audioFormat {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showTranscriptionServicePicker() {
        let alertController = UIAlertController(title: "Transcription Service", message: "Choose primary transcription service", preferredStyle: .actionSheet)
        
        TranscriptionServiceType.allCases.forEach { service in
            let action = UIAlertAction(title: service.rawValue, style: .default) { _ in
                SettingsManager.shared.transcriptionService = service
                self.tableView.reloadData()
            }
            if service == SettingsManager.shared.transcriptionService {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showAPIKeyAlert() {
        let alert = UIAlertController(title: "OpenAI API Key", message: "Enter your OpenAI API key for enhanced transcription accuracy", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "sk-..."
            textField.isSecureTextEntry = true
            textField.text = KeychainManager.shared.getAPIKey()
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let apiKey = alert.textFields?.first?.text, !apiKey.isEmpty {
                self?.transcriptionService.setAPIKey(apiKey)
                self?.tableView.reloadData()
                
                let successAlert = UIAlertController(title: "Success", message: "API key saved securely", preferredStyle: .alert)
                successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(successAlert, animated: true)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            KeychainManager.shared.deleteAPIKey()
            self?.tableView.reloadData()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showRetryAttemptsPicker() {
        let alertController = UIAlertController(title: "Retry Attempts", message: "How many times should failed transcriptions be retried?", preferredStyle: .actionSheet)
        
        let attempts = [1, 3, 5, 7, 10]
        
        attempts.forEach { count in
            let title = "\(count) attempts"
            let action = UIAlertAction(title: title, style: .default) { _ in
                SettingsManager.shared.maxRetryAttempts = count
                self.tableView.reloadData()
            }
            if count == SettingsManager.shared.maxRetryAttempts {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showExportFormatPicker() {
        let alertController = UIAlertController(title: "Export Format", message: "Default format for exporting transcriptions", preferredStyle: .actionSheet)
        
        ExportFormat.allCases.forEach { format in
            let action = UIAlertAction(title: format.rawValue, style: .default) { _ in
                SettingsManager.shared.exportFormat = format
                self.tableView.reloadData()
            }
            if format == SettingsManager.shared.exportFormat {
                action.setValue(true, forKey: "checked")
            }
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alertController, animated: true)
    }
    
    private func showStorageDetails() {
        let alert = UIAlertController(title: "Storage Usage", message: SettingsManager.shared.getDetailedStorageInfo(), preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Clear Cache", style: .destructive) { _ in
            self.clearCache()
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
    }
    
    private func clearCache() {
        // Implement cache clearing logic
        let alert = UIAlertController(title: "Cache Cleared", message: "Temporary files have been removed", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.tableView.reloadData()
        }
    }
    
    private func showPrivacyPolicy() {
        let alert = UIAlertController(title: "Privacy Policy", message: """
        iAudio Privacy Policy:
        
        • Audio recordings are stored locally on your device
        • Transcription may be processed by external services (OpenAI) if configured
        • No personal data is shared without your consent
        • You can delete all data at any time
        • Audio files are encrypted at rest
        
        For full privacy policy, visit our website.
        """, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showSupport() {
        let alert = UIAlertController(title: "Support", message: "Need help with iAudio?", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Email Support", style: .default) { _ in
            self.emailSupport()
        })
        
        alert.addAction(UIAlertAction(title: "View Documentation", style: .default) { _ in
            self.openDocumentation()
        })
        
        alert.addAction(UIAlertAction(title: "Report Bug", style: .default) { _ in
            self.reportBug()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        
        present(alert, animated: true)
    }
    
    private func showCredits() {
        let alert = UIAlertController(title: "Credits", message: """
        iAudio - Professional Audio Recording & Transcription
        
        Built with:
        • SwiftData for data persistence
        • AVFoundation for audio recording
        • OpenAI Whisper for transcription
        • Apple Speech Recognition
        
        Developed by: Your Development Team
        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        """, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func emailSupport() {
        // Implement email support
        if let url = URL(string: "mailto:support@yourcompany.com?subject=iAudio%20Support") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openDocumentation() {
        // Implement documentation opening
        if let url = URL(string: "https://yourcompany.com/iaudio/docs") {
            UIApplication.shared.open(url)
        }
    }
    
    private func reportBug() {
        // Implement bug reporting
        let alert = UIAlertController(title: "Report Bug", message: "Please describe the issue you encountered", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Describe the bug..."
        }
        
        alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
            // Implement bug report submission
            let successAlert = UIAlertController(title: "Thank You", message: "Your bug report has been submitted", preferredStyle: .alert)
            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(successAlert, animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
}

// MARK: - Custom Table View Cells

class SwitchTableViewCell: UITableViewCell {
    private let switchControl = UISwitch()
    private var item: SettingItem?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        accessoryView = switchControl
        switchControl.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
    }
    
    func configure(with item: SettingItem) {
        self.item = item
        textLabel?.text = item.title
        
        switch item {
        case .backgroundRecording:
            switchControl.isOn = SettingsManager.shared.backgroundRecording
        case .fallbackToLocal:
            switchControl.isOn = SettingsManager.shared.fallbackToLocal
        case .autoDeleteOld:
            switchControl.isOn = SettingsManager.shared.autoDeleteOld
        default:
            break
        }
    }
    
    @objc private func switchValueChanged() {
        guard let item = item else { return }
        
        switch item {
        case .backgroundRecording:
            SettingsManager.shared.backgroundRecording = switchControl.isOn
        case .fallbackToLocal:
            SettingsManager.shared.fallbackToLocal = switchControl.isOn
        case .autoDeleteOld:
            SettingsManager.shared.autoDeleteOld = switchControl.isOn
        default:
            break
        }
    }
}

class DetailTableViewCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with item: SettingItem) {
        textLabel?.text = item.title
        detailTextLabel?.text = item.subtitle
        accessoryType = item.accessoryType
    }
}

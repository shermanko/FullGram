import Foundation
import UIKit
import Display

final class FullGramPluginCommandBarView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    var onSelectCommand: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        self.layer.cornerRadius = 12.0
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.12
        self.layer.shadowRadius = 6.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)

        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scrollView)

        self.stackView.axis = .horizontal
        self.stackView.spacing = 6.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 6.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -6.0),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor, constant: 8.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor, constant: -8.0),
            self.stackView.heightAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.heightAnchor, constant: -12.0)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    func update(query: String, accentColor: UIColor) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let aiEnabled = FullGramAIStore.shared.isEnabled
        let pluginsEnabled = FullGramPluginManager.shared.isSystemEnabled
        let prefix = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()).lowercased() : ""
        let isCommandCandidate = trimmed.hasPrefix(".") && (!prefix.contains(" ") || prefix.hasPrefix("plug "))
        guard isCommandCandidate, (aiEnabled || pluginsEnabled) else {
            self.isHidden = true
            return false
        }
        var commands: [(command: String, description: String, pluginName: String)] = []
        if aiEnabled && (prefix.isEmpty || "ai".hasPrefix(prefix)) {
            commands.append(("ai", "Спросить ИИ о чате или задать задачу", "ИИ Ассистент"))
        }
        if pluginsEnabled {
            commands.append(contentsOf: FullGramPluginManager.shared.availableCommands().filter {
                prefix.isEmpty || $0.command.hasPrefix(prefix)
            })
        }
        guard !commands.isEmpty else {
            self.isHidden = true
            return false
        }

        for view in self.stackView.arrangedSubviews {
            self.stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in commands {
            var cfg = UIButton.Configuration.filled()
            cfg.title = ".\(item.command)"
            cfg.subtitle = item.pluginName
            cfg.baseBackgroundColor = accentColor.withAlphaComponent(0.14)
            cfg.baseForegroundColor = accentColor
            cfg.cornerStyle = .medium
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 10.0, bottom: 4.0, trailing: 10.0)
            let btn = UIButton(configuration: cfg)
            btn.accessibilityLabel = item.command
            btn.addTarget(self, action: #selector(self.chipTapped(_:)), for: .touchUpInside)
            self.stackView.addArrangedSubview(btn)
        }

        self.isHidden = false
        return true
    }

    @objc private func chipTapped(_ sender: UIButton) {
        if let cmd = sender.accessibilityLabel, !cmd.isEmpty {
            self.onSelectCommand?(".\(cmd) ")
        }
    }
}

enum FullGramFormattingAction: Int, CaseIterable {
    case ai = 0
    case bold = 1
    case italic
    case underline
    case strikethrough
    case monospace
    case spoiler
    case clear

    var shortTitle: String {
        switch self {
        case .ai: return "✨ ИИ"
        case .bold: return "Ж"
        case .italic: return "К"
        case .underline: return "Ч"
        case .strikethrough: return "З"
        case .monospace: return "</>"
        case .spoiler: return "Спойлер"
        case .clear: return "Сброс"
        }
    }

    var accessibilityName: String {
        switch self {
        case .ai: return "Спросить ИИ-ассистента"
        case .bold: return "Жирный"
        case .italic: return "Курсив"
        case .underline: return "Подчёркнутый"
        case .strikethrough: return "Зачёркнутый"
        case .monospace: return "Моноширинный"
        case .spoiler: return "Спойлер"
        case .clear: return "Сбросить форматирование"
        }
    }
}

final class FullGramFormattingBarView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    var onSelectAction: ((FullGramFormattingAction) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        self.layer.cornerRadius = 11.0
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.12
        self.layer.shadowRadius = 6.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)

        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scrollView)

        self.stackView.axis = .horizontal
        self.stackView.spacing = 6.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 4.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -4.0),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor, constant: 8.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor, constant: -8.0),
            self.stackView.heightAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.heightAnchor, constant: -8.0)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    private var appliedAccentColor: UIColor?

    func update(visible: Bool, accentColor: UIColor, isDark: Bool) {
        self.isHidden = !visible
        guard visible else { return }

        self.backgroundColor = (isDark ? UIColor(rgb: 0x1c1c1e) : UIColor(rgb: 0xf7f7f9)).withAlphaComponent(0.96)
        if self.appliedAccentColor?.isEqual(accentColor) == true && !self.stackView.arrangedSubviews.isEmpty {
            return
        }
        self.appliedAccentColor = accentColor

        for view in self.stackView.arrangedSubviews {
            self.stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for action in FullGramFormattingAction.allCases {
            var cfg = UIButton.Configuration.filled()
            var attrTitle = AttributedString(action.shortTitle)
            switch action {
            case .ai:
                attrTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
            case .bold:
                attrTitle.font = .systemFont(ofSize: 13.0, weight: .bold)
            case .italic:
                attrTitle.font = .italicSystemFont(ofSize: 13.0)
            case .underline:
                attrTitle.font = .systemFont(ofSize: 13.0, weight: .medium)
                attrTitle.underlineStyle = .single
            case .strikethrough:
                attrTitle.font = .systemFont(ofSize: 13.0, weight: .medium)
                attrTitle.strikethroughStyle = .single
            case .monospace:
                attrTitle.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
            case .spoiler, .clear:
                attrTitle.font = .systemFont(ofSize: 12.5, weight: .medium)
            }
            cfg.attributedTitle = attrTitle
            cfg.baseBackgroundColor = accentColor.withAlphaComponent(action == .clear ? 0.08 : 0.14)
            cfg.baseForegroundColor = action == .clear ? .secondaryLabel : accentColor
            cfg.cornerStyle = .medium
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 10.0, bottom: 4.0, trailing: 10.0)

            let btn = UIButton(configuration: cfg)
            btn.tag = action.rawValue
            btn.accessibilityLabel = action.accessibilityName
            btn.addTarget(self, action: #selector(self.actionTapped(_:)), for: .touchUpInside)
            self.stackView.addArrangedSubview(btn)
        }
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard let action = FullGramFormattingAction(rawValue: sender.tag) else { return }
        self.onSelectAction?(action)
    }
}

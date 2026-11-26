import Foundation
import UIKit
import Display

final class FullGramSleepTimer {
    enum Mode: Equatable {
        case off
        case minutes(Int)
        case endOfTrack
    }

    static let shared = FullGramSleepTimer()
    static let didChangeNotification = Notification.Name("FullGram.SleepTimerChanged")
    static let didFireNotification = Notification.Name("FullGram.SleepTimerFired")

    private var timer: Timer?
    private(set) var mode: Mode = .off
    private(set) var targetDate: Date?
    private var lastReportedLabel: String?

    private init() {}

    var isActive: Bool {
        return self.mode != .off
    }

    var shortLabel: String? {
        switch self.mode {
        case .off: return nil
        case .endOfTrack: return "1 трек"
        case .minutes:
            guard let targetDate = self.targetDate else { return nil }
            let sec = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
            return "\(max(1, (sec + 59) / 60))м"
        }
    }

    func set(mode: Mode) {
        let apply = { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.targetDate = nil
            let normalizedMode: Mode
            if case let .minutes(mins) = mode, mins <= 0 {
                normalizedMode = .off
            } else {
                normalizedMode = mode
            }
            self.mode = normalizedMode
            self.lastReportedLabel = nil

            if case let .minutes(mins) = normalizedMode, mins > 0 {
                self.targetDate = Date().addingTimeInterval(TimeInterval(mins * 60))
                self.lastReportedLabel = self.shortLabel
                let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self, let target = self.targetDate else { return }
                    if target.timeIntervalSinceNow <= 0 {
                        self.fire()
                    } else {
                        let nextLabel = self.shortLabel
                        if nextLabel != self.lastReportedLabel {
                            self.lastReportedLabel = nextLabel
                            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                        }
                    }
                }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func handleTrackChanged() {
        let apply = { [weak self] in
            guard let self else { return }
            if case .endOfTrack = self.mode {
                self.fire()
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func fire() {
        let apply = { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.targetDate = nil
            self.mode = .off
            NotificationCenter.default.post(name: Self.didFireNotification, object: nil)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

// MARK: - Embedded Mixer Overlay inside Audio Player

private final class FullGramPlayerMiniFader: UIControl {
    var value: Float = 0.0 {
        didSet {
            self.value = min(12.0, max(-12.0, self.value))
            self.updateGeometry()
        }
    }
    var accentColor: UIColor = .systemBlue { didSet { self.fillView.backgroundColor = self.accentColor } }

    private let dbLabel = UILabel()
    private let trackView = UIView()
    private let zeroLine = UIView()
    private let fillView = UIView()
    private let thumbView = UIView()
    private let freqLabel = UILabel()

    init(frequency: Float) {
        super.init(frame: .zero)

        self.dbLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        self.dbLabel.textColor = .white
        self.dbLabel.textAlignment = .center

        self.trackView.backgroundColor = UIColor(white: 1.0, alpha: 0.18)
        self.trackView.layer.cornerRadius = 3.0
        self.trackView.isUserInteractionEnabled = false

        self.zeroLine.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        self.zeroLine.isUserInteractionEnabled = false

        self.fillView.backgroundColor = self.accentColor
        self.fillView.layer.cornerRadius = 3.0
        self.fillView.isUserInteractionEnabled = false

        self.thumbView.backgroundColor = .white
        self.thumbView.layer.cornerRadius = 5.0
        self.thumbView.isUserInteractionEnabled = false

        self.freqLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        self.freqLabel.textColor = UIColor(white: 1.0, alpha: 0.72)
        self.freqLabel.textAlignment = .center
        self.freqLabel.text = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"

        self.addSubview(self.dbLabel)
        self.addSubview(self.trackView)
        self.trackView.addSubview(self.zeroLine)
        self.trackView.addSubview(self.fillView)
        self.addSubview(self.thumbView)
        self.addSubview(self.freqLabel)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        let h = self.bounds.height
        self.dbLabel.frame = CGRect(x: 0.0, y: 0.0, width: w, height: 14.0)
        self.freqLabel.frame = CGRect(x: 0.0, y: h - 14.0, width: w, height: 14.0)
        let trackH = max(36.0, h - 36.0)
        self.trackView.frame = CGRect(x: (w - 6.0) / 2.0, y: 18.0, width: 6.0, height: trackH)
        self.zeroLine.frame = CGRect(x: -3.0, y: trackH / 2.0 - 0.5, width: 12.0, height: 1.0)
        self.updateGeometry()
    }

    private func updateGeometry() {
        self.dbLabel.text = self.value == 0.0 ? "0" : String(format: "%+.0f", self.value)
        let th = self.trackView.bounds.height
        guard th > 0.0 else { return }
        let norm = CGFloat((12.0 - self.value) / 24.0)
        let cy = self.trackView.frame.minY + norm * th
        let midY = th / 2.0
        let relY = norm * th
        if relY <= midY {
            self.fillView.frame = CGRect(x: 0.0, y: relY, width: 6.0, height: midY - relY)
        } else {
            self.fillView.frame = CGRect(x: 0.0, y: midY, width: 6.0, height: relY - midY)
        }
        let thumbW = min(18.0, max(12.0, self.bounds.width - 6.0))
        self.thumbView.frame = CGRect(x: (self.bounds.width - thumbW) / 2.0, y: cy - 5.0, width: thumbW, height: 10.0)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.update(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.update(for: touch)
        return true
    }

    private func update(for touch: UITouch) {
        let y = touch.location(in: self.trackView).y
        let ratio = min(1.0, max(0.0, y / max(1.0, self.trackView.bounds.height)))
        var raw = Float(12.0 - ratio * 24.0)
        if abs(raw) < 0.5 { raw = 0.0 }
        else { raw = (raw * 2.0).rounded() / 2.0 }
        self.value = raw
        self.sendActions(for: .valueChanged)
    }
}

final class FullGramPlayerMixerOverlayView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let cardView = UIView()
    private let enabledSwitch = UISwitch()
    private var presetButtons: [String: UIButton] = [:]
    private var faders: [FullGramPlayerMiniFader] = []
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.blurView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.blurView)

        self.cardView.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        self.cardView.layer.cornerRadius = 20.0
        self.cardView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.cardView)

        let titleLabel = UILabel()
        titleLabel.text = "Микшер"
        titleLabel.font = .systemFont(ofSize: 18.0, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor(white: 1.0, alpha: 0.75)
        closeButton.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        self.enabledSwitch.addTarget(self, action: #selector(self.switchChanged), for: .valueChanged)
        self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = false

        let presetsRow = UIStackView()
        presetsRow.axis = .horizontal
        presetsRow.distribution = .fillEqually
        presetsRow.spacing = 6.0
        presetsRow.translatesAutoresizingMaskIntoConstraints = false
        for (idx, preset) in FullGramMixer.presets.enumerated() {
            var cfg = UIButton.Configuration.filled()
            cfg.title = preset.title(true)
            cfg.cornerStyle = .medium
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 4, bottom: 7, trailing: 4)
            let btn = UIButton(configuration: cfg)
            btn.tag = idx
            btn.addTarget(self, action: #selector(self.presetTapped(_:)), for: .touchUpInside)
            self.presetButtons[preset.id] = btn
            presetsRow.addArrangedSubview(btn)
        }

        let bandsRow = UIStackView()
        bandsRow.axis = .horizontal
        bandsRow.distribution = .fillEqually
        bandsRow.spacing = 2.0
        bandsRow.translatesAutoresizingMaskIntoConstraints = false
        for (idx, freq) in FullGramMixer.frequencies.enumerated() {
            let fader = FullGramPlayerMiniFader(frequency: freq)
            fader.tag = idx
            fader.addTarget(self, action: #selector(self.faderChanged(_:)), for: .valueChanged)
            self.faders.append(fader)
            bandsRow.addArrangedSubview(fader)
        }

        self.cardView.addSubview(titleLabel)
        self.cardView.addSubview(self.enabledSwitch)
        self.cardView.addSubview(closeButton)
        self.cardView.addSubview(presetsRow)
        self.cardView.addSubview(bandsRow)

        NSLayoutConstraint.activate([
            self.blurView.topAnchor.constraint(equalTo: self.topAnchor),
            self.blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.cardView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.cardView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14.0),
            self.cardView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14.0),

            titleLabel.topAnchor.constraint(equalTo: self.cardView.topAnchor, constant: 16.0),
            titleLabel.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 16.0),

            self.enabledSwitch.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            self.enabledSwitch.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12.0),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -14.0),
            closeButton.widthAnchor.constraint(equalToConstant: 28.0),
            closeButton.heightAnchor.constraint(equalToConstant: 28.0),

            presetsRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14.0),
            presetsRow.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 14.0),
            presetsRow.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -14.0),

            bandsRow.topAnchor.constraint(equalTo: presetsRow.bottomAnchor, constant: 16.0),
            bandsRow.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 8.0),
            bandsRow.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -8.0),
            bandsRow.heightAnchor.constraint(equalToConstant: 180.0),
            bandsRow.bottomAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: -16.0)
        ])

        self.observer = NotificationCenter.default.addObserver(forName: FullGramMixer.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        self.refresh()
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func closeTapped() { self.onClose?() }
    @objc private func switchChanged() { FullGramMixer.isEnabled = self.enabledSwitch.isOn }

    @objc private func presetTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < FullGramMixer.presets.count else { return }
        FullGramMixer.apply(preset: FullGramMixer.presets[idx])
    }

    @objc private func faderChanged(_ sender: FullGramPlayerMiniFader) {
        var gains = FullGramMixer.gains
        guard sender.tag >= 0 && sender.tag < gains.count else { return }
        gains[sender.tag] = sender.value
        FullGramMixer.presetId = nil
        FullGramMixer.gains = gains
        if !FullGramMixer.isEnabled {
            FullGramMixer.isEnabled = true
        }
    }

    private func refresh() {
        self.enabledSwitch.isOn = FullGramMixer.isEnabled
        let gains = FullGramMixer.gains
        for (idx, fader) in self.faders.enumerated() where idx < gains.count {
            if !fader.isTracking {
                fader.value = gains[idx]
            }
        }
        let selected = FullGramMixer.isEnabled ? FullGramMixer.presetId : nil
        for (id, btn) in self.presetButtons {
            var cfg = btn.configuration ?? UIButton.Configuration.filled()
            let on = id == selected
            cfg.baseBackgroundColor = on ? UIColor.systemBlue : UIColor(white: 1.0, alpha: 0.14)
            cfg.baseForegroundColor = .white
            btn.configuration = cfg
        }
    }
}

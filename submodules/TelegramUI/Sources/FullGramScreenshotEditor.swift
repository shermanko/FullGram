import Foundation
import UIKit
import ObjectiveC
import Display

/// Interactive chat screenshot editor shown after taking a screenshot in a chat.
/// Allows redacting / blurring messages or text, changing background backdrop, and sharing or saving.
final class FullGramScreenshotEditorController: UIViewController {
    private enum ToolMode {
        case blur
        case blackout
    }

    private struct BackgroundPreset {
        let name: String
        let colors: [UIColor]
    }

    private static let backgrounds: [BackgroundPreset] = [
        BackgroundPreset(name: "Без рамки", colors: []),
        BackgroundPreset(name: "Тёмный градиент", colors: [UIColor(rgb: 0x0F172A), UIColor(rgb: 0x1E293B)]),
        BackgroundPreset(name: "Космос", colors: [UIColor(rgb: 0x1E1B4B), UIColor(rgb: 0x4C1D95)]),
        BackgroundPreset(name: "Закат", colors: [UIColor(rgb: 0x991B1B), UIColor(rgb: 0xEA580C)]),
        BackgroundPreset(name: "Океан", colors: [UIColor(rgb: 0x0C4A6E), UIColor(rgb: 0x0D9488)]),
        BackgroundPreset(name: "Монохром", colors: [UIColor(rgb: 0x000000), UIColor(rgb: 0x27272A)])
    ]

    private struct RedactBox {
        let rectInImage: CGRect
        let mode: ToolMode
    }

    private let sourceImage: UIImage
    private var toolMode: ToolMode = .blur
    private var backgroundIndex: Int = 1
    private var redactions: [RedactBox] = []
    private var activeDragStart: CGPoint?
    private var activePreviewLayer: CAShapeLayer?
    private var lastLayoutOverlaySize: CGSize = .zero

    private let canvasContainer = UIView()
    private let bgGradientLayer = CAGradientLayer()
    private let imageView = UIImageView()
    private let redactionOverlayView = UIView()
    private let toolSegment = UISegmentedControl(items: ["Размытие", "Чёрный маркер"])
    private let bgButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    init(image: UIImage) {
        self.sourceImage = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(rgb: 0x0B0C10)
        self.title = "Редактор скриншота"

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Поделиться", style: .plain, target: self, action: #selector(self.shareTapped))

        self.hintLabel.text = "Проведите пальцем по сообщению или тексту, чтобы скрыть"
        self.hintLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        self.hintLabel.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.hintLabel.textAlignment = .center
        self.hintLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.hintLabel)

        self.canvasContainer.clipsToBounds = true
        self.canvasContainer.layer.cornerRadius = 18.0
        self.canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        self.canvasContainer.layer.insertSublayer(self.bgGradientLayer, at: 0)
        self.view.addSubview(self.canvasContainer)

        self.imageView.image = self.sourceImage
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.layer.cornerRadius = 14.0
        self.imageView.clipsToBounds = true
        self.imageView.isUserInteractionEnabled = true
        self.canvasContainer.addSubview(self.imageView)

        self.redactionOverlayView.backgroundColor = .clear
        self.redactionOverlayView.isUserInteractionEnabled = false
        self.imageView.addSubview(self.redactionOverlayView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        self.imageView.addGestureRecognizer(pan)

        self.toolSegment.selectedSegmentIndex = 0
        self.toolSegment.addTarget(self, action: #selector(self.toolChanged), for: .valueChanged)
        self.toolSegment.translatesAutoresizingMaskIntoConstraints = false

        self.bgButton.setTitle("Фон: Тёмный градиент", for: .normal)
        self.bgButton.titleLabel?.font = .systemFont(ofSize: 14.0, weight: .semibold)
        self.bgButton.addTarget(self, action: #selector(self.cycleBackground), for: .touchUpInside)
        self.bgButton.translatesAutoresizingMaskIntoConstraints = false

        self.undoButton.setTitle("Отменить", for: .normal)
        self.undoButton.titleLabel?.font = .systemFont(ofSize: 14.0, weight: .medium)
        self.undoButton.addTarget(self, action: #selector(self.undoTapped), for: .touchUpInside)
        self.undoButton.translatesAutoresizingMaskIntoConstraints = false

        let bottomRow = UIStackView(arrangedSubviews: [self.bgButton, self.undoButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 16.0
        bottomRow.distribution = .fillEqually
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let controls = UIStackView(arrangedSubviews: [self.toolSegment, bottomRow])
        controls.axis = .vertical
        controls.spacing = 10.0
        controls.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(controls)

        NSLayoutConstraint.activate([
            self.hintLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 8.0),
            self.hintLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.hintLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),

            self.canvasContainer.topAnchor.constraint(equalTo: self.hintLabel.bottomAnchor, constant: 10.0),
            self.canvasContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 14.0),
            self.canvasContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -14.0),
            self.canvasContainer.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -14.0),

            controls.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            controls.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            controls.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12.0)
        ])

        self.applyBackgroundPreset()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.bgGradientLayer.frame = self.canvasContainer.bounds
        let pad: CGFloat = Self.backgrounds[self.backgroundIndex].colors.isEmpty ? 0.0 : 18.0
        let avail = self.canvasContainer.bounds.insetBy(dx: pad, dy: pad)
        let imgSize = self.sourceImage.size
        guard imgSize.width > 0 && imgSize.height > 0 && avail.width > 0 && avail.height > 0 else { return }
        let scale = min(avail.width / imgSize.width, avail.height / imgSize.height)
        let fitted = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        self.imageView.frame = CGRect(
            x: avail.midX - fitted.width * 0.5,
            y: avail.midY - fitted.height * 0.5,
            width: fitted.width,
            height: fitted.height
        )
        self.redactionOverlayView.frame = self.imageView.bounds
        if self.lastLayoutOverlaySize != self.imageView.bounds.size {
            self.lastLayoutOverlaySize = self.imageView.bounds.size
            self.rebuildRedactionViews()
        }
    }

    private func applyBackgroundPreset() {
        let preset = Self.backgrounds[self.backgroundIndex]
        self.bgButton.setTitle("Фон: \(preset.name)", for: .normal)
        if preset.colors.isEmpty {
            self.bgGradientLayer.colors = nil
            self.canvasContainer.backgroundColor = .clear
            self.imageView.layer.cornerRadius = 0.0
        } else {
            self.bgGradientLayer.colors = preset.colors.map(\.cgColor)
            self.bgGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
            self.bgGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.imageView.layer.cornerRadius = 14.0
        }
        self.view.setNeedsLayout()
    }

    @objc private func toolChanged() {
        self.toolMode = self.toolSegment.selectedSegmentIndex == 0 ? .blur : .blackout
    }

    @objc private func cycleBackground() {
        self.backgroundIndex = (self.backgroundIndex + 1) % Self.backgrounds.count
        self.applyBackgroundPreset()
    }

    @objc private func undoTapped() {
        guard !self.redactions.isEmpty else { return }
        self.redactions.removeLast()
        self.rebuildRedactionViews()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.location(in: self.imageView)
        let clamped = CGPoint(
            x: min(max(0.0, pt.x), self.imageView.bounds.width),
            y: min(max(0.0, pt.y), self.imageView.bounds.height)
        )
        switch gesture.state {
        case .began:
            self.activePreviewLayer?.removeFromSuperlayer()
            self.activePreviewLayer = nil
            self.activeDragStart = clamped
            let layer = CAShapeLayer()
            layer.strokeColor = UIColor.systemYellow.cgColor
            layer.fillColor = UIColor(white: 0.0, alpha: 0.25).cgColor
            layer.lineWidth = 1.5
            layer.lineDashPattern = [4, 3]
            self.imageView.layer.addSublayer(layer)
            self.activePreviewLayer = layer
        case .changed:
            guard let start = self.activeDragStart else { return }
            let rect = CGRect(
                x: min(start.x, clamped.x),
                y: min(start.y, clamped.y),
                width: abs(clamped.x - start.x),
                height: abs(clamped.y - start.y)
            )
            self.activePreviewLayer?.path = UIBezierPath(roundedRect: rect, cornerRadius: 6.0).cgPath
        case .cancelled, .failed:
            self.activePreviewLayer?.removeFromSuperlayer()
            self.activePreviewLayer = nil
            self.activeDragStart = nil
        case .ended:
            self.activePreviewLayer?.removeFromSuperlayer()
            self.activePreviewLayer = nil
            guard let start = self.activeDragStart else { return }
            self.activeDragStart = nil
            let rect = CGRect(
                x: min(start.x, clamped.x),
                y: min(start.y, clamped.y),
                width: abs(clamped.x - start.x),
                height: abs(clamped.y - start.y)
            )
            guard rect.width >= 10.0 && rect.height >= 8.0,
                  self.imageView.bounds.width > 0,
                  self.imageView.bounds.height > 0 else { return }
            let norm = CGRect(
                x: rect.minX / self.imageView.bounds.width,
                y: rect.minY / self.imageView.bounds.height,
                width: rect.width / self.imageView.bounds.width,
                height: rect.height / self.imageView.bounds.height
            )
            self.redactions.append(RedactBox(rectInImage: norm, mode: self.toolMode))
            self.rebuildRedactionViews()
        default:
            break
        }
    }

    private func rebuildRedactionViews() {
        for sub in self.redactionOverlayView.subviews { sub.removeFromSuperview() }
        let b = self.redactionOverlayView.bounds
        for box in self.redactions {
            let frame = CGRect(
                x: box.rectInImage.minX * b.width,
                y: box.rectInImage.minY * b.height,
                width: box.rectInImage.width * b.width,
                height: box.rectInImage.height * b.height
            )
            if box.mode == .blur {
                let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
                blur.frame = frame
                blur.layer.cornerRadius = 6.0
                blur.clipsToBounds = true
                self.redactionOverlayView.addSubview(blur)
            } else {
                let bar = UIView(frame: frame)
                bar.backgroundColor = .black
                bar.layer.cornerRadius = 6.0
                self.redactionOverlayView.addSubview(bar)
            }
        }
    }

    private func renderExportImage() -> UIImage {
        self.activePreviewLayer?.removeFromSuperlayer()
        self.activePreviewLayer = nil
        self.activeDragStart = nil
        let bounds = self.canvasContainer.bounds
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            return self.sourceImage
        }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            self.canvasContainer.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    @objc private func shareTapped() {
        let exported = self.renderExportImage()
        let activity = UIActivityViewController(activityItems: [exported], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.barButtonItem = self.navigationItem.rightBarButtonItem
        }
        self.present(activity, animated: true)
    }
}

private final class FullGramScreenshotBannerButton: UIButton {
    var onTap: (() -> Void)?

    @objc func handleTap() {
        self.onTap?()
    }
}

private final class FullGramScreenshotObserverBox {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) {
        self.token = token
    }
    deinit {
        NotificationCenter.default.removeObserver(self.token)
    }
}

enum FullGramScreenshotPrompt {
    @MainActor private static var observerKey: UInt8 = 0

    @MainActor
    static func attach(to controller: UIViewController) {
        self.detach(from: controller)
        let obs = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated {
                guard let controller,
                      controller.viewIfLoaded?.window != nil,
                      controller.presentedViewController == nil,
                      let hostView = controller.view else {
                    return
                }
                let renderer = UIGraphicsImageRenderer(bounds: hostView.bounds)
                let snap = renderer.image { _ in
                    hostView.drawHierarchy(in: hostView.bounds, afterScreenUpdates: false)
                }
                self.showBanner(in: hostView, screenshot: snap, presentOn: controller)
            }
        }
        objc_setAssociatedObject(controller, &self.observerKey, FullGramScreenshotObserverBox(obs), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @MainActor
    static func detach(from controller: UIViewController) {
        if objc_getAssociatedObject(controller, &self.observerKey) != nil {
            objc_setAssociatedObject(controller, &self.observerKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }
    }

    @MainActor
    static func showBanner(in hostView: UIView, screenshot: UIImage, presentOn controller: UIViewController) {
        for sub in hostView.subviews where sub is FullGramScreenshotBannerButton {
            sub.removeFromSuperview()
        }
        let pill = FullGramScreenshotBannerButton(type: .system)
        pill.setTitle("  ✂️ Редактировать скриншот  ", for: .normal)
        pill.titleLabel?.font = .systemFont(ofSize: 14.0, weight: .semibold)
        pill.setTitleColor(.white, for: .normal)
        pill.backgroundColor = UIColor(rgb: 0x1C1C1E).withAlphaComponent(0.92)
        pill.layer.cornerRadius = 20.0
        pill.layer.borderWidth = 0.75
        pill.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.35
        pill.layer.shadowRadius = 10.0
        pill.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
        pill.sizeToFit()
        let w = max(210.0, pill.bounds.width + 16.0)
        let h: CGFloat = 40.0
        let safeBottom = hostView.safeAreaInsets.bottom
        pill.frame = CGRect(
            x: (hostView.bounds.width - w) * 0.5,
            y: hostView.bounds.height - safeBottom - 108.0,
            width: w,
            height: h
        )
        pill.alpha = 0.0
        pill.transform = CGAffineTransform(translationX: 0.0, y: 18.0)

        pill.onTap = { [weak pill, weak controller] in
            pill?.removeFromSuperview()
            guard let controller, controller.presentedViewController == nil else { return }
            let editor = FullGramScreenshotEditorController(image: screenshot)
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = .fullScreen
            controller.present(nav, animated: true)
        }
        pill.addTarget(pill, action: #selector(FullGramScreenshotBannerButton.handleTap), for: .touchUpInside)
        hostView.addSubview(pill)

        UIView.animate(withDuration: 0.24, delay: 0.0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.5) {
            pill.alpha = 1.0
            pill.transform = .identity
        }
        Task { @MainActor [weak pill] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let pill, pill.superview != nil else { return }
            UIView.animate(withDuration: 0.22, animations: {
                pill.alpha = 0.0
                pill.transform = CGAffineTransform(translationX: 0.0, y: 14.0)
            }, completion: { _ in
                pill.removeFromSuperview()
            })
        }
    }
}

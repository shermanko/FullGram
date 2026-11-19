import Foundation
import UIKit
import QuartzCore

// MARK: - BetKing / Betona Style Animated Native Casino GUI

final class FullGramCasinoBetKingViewController: UIViewController {
    enum GameMode: String, CaseIterable {
        case zeus
        case dogs
        case slots777
        case crash
        case roulette
        case coin

        var shortTitle: String {
            switch self {
            case .zeus: return "⚡ Зевс"
            case .dogs: return "🐶 Собаки"
            case .slots777: return "🎰 777"
            case .crash: return "🚀 Краш"
            case .roulette: return "🎡 Рулетка"
            case .coin: return "🪙 Монетка"
            }
        }

        var fullTitle: String {
            switch self {
            case .zeus: return "GATES OF OLYMPUS · RTP 96.5%"
            case .dogs: return "THE DOG HOUSE · RTP 96.5%"
            case .slots777: return "ROYAL SLOTS 777 · RTP 96.2%"
            case .crash: return "BETKING CRASH LIVE · RTP 97.0%"
            case .roulette: return "EUROPEAN ROULETTE · RTP 97.3%"
            case .coin: return "ROYAL COIN FLIP · RTP 98.0%"
            }
        }

        var accentColor: UIColor {
            switch self {
            case .zeus: return UIColor(red: 0.96, green: 0.72, blue: 0.18, alpha: 1.0)
            case .dogs: return UIColor(red: 0.45, green: 0.42, blue: 0.98, alpha: 1.0)
            case .slots777: return UIColor(red: 0.92, green: 0.28, blue: 0.56, alpha: 1.0)
            case .crash: return UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1.0)
            case .roulette: return UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
            case .coin: return UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
            }
        }
    }

    private enum RouletteBet: Int {
        case red = 0
        case black = 1
        case green = 2
    }

    private static let storePrefix = "fullgram.plugin.store.fg_casino."
    private static let redNumbers: Set<Int> = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

    private let onSendToChat: (String) -> Void
    private var currentGame: GameMode
    private var currentBet: Int = 100
    private var isAnimating: Bool = false
    private var lastSummaryForChat: String = ""

    // Crash live state
    private var crashLink: CADisplayLink?
    private var crashStartTime: CFTimeInterval = 0
    private var crashTargetPoint: Double = 2.0
    private var crashCurrentMult: Double = 1.0
    private var crashActiveBet: Int = 0
    private var crashRunning: Bool = false

    // Roulette & Coin state
    private var selectedRouletteBet: RouletteBet = .red
    private var selectedCoinTails: Bool = false

    // Palette (BetKing / Betona dark gold + emerald)
    private let bgDark = UIColor(red: 0.043, green: 0.059, blue: 0.102, alpha: 1.0)
    private let cardDark = UIColor(red: 0.082, green: 0.106, blue: 0.176, alpha: 1.0)
    private let cardLighter = UIColor(red: 0.118, green: 0.153, blue: 0.243, alpha: 1.0)
    private let goldColor = UIColor(red: 0.96, green: 0.72, blue: 0.18, alpha: 1.0)
    private let emeraldColor = UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1.0)

    // UI Elements
    private let topBar = UIView()
    private let brandLabel = UILabel()
    private let balancePill = UIButton(type: .system)
    private let depositButton = UIButton(type: .system)

    private let lobbyScroll = UIScrollView()
    private let lobbyStack = UIStackView()
    private var lobbyButtons: [GameMode: UIButton] = [:]

    private let stageCard = UIView()
    private let stageHeaderLabel = UILabel()
    private let freeSpinsBadge = UILabel()
    private let arenaView = UIView()
    private let winBannerLabel = UILabel()

    // Slot grid views (5x3 or 3x1)
    private var slotCellViews: [UILabel] = []
    private var spinTimer: Timer?

    // Crash views
    private let crashCurveLayer = CAShapeLayer()
    private let crashFillLayer = CAShapeLayer()
    private let crashRocketLabel = UILabel()
    private let crashMultLabel = UILabel()
    private let crashStatusLabel = UILabel()

    // Roulette views
    private let rouletteViewport = UIView()
    private let rouletteStripView = UIView()
    private let roulettePointer = UIView()
    private let rouletteResultLabel = UILabel()
    private let rouletteBetSegment = UISegmentedControl(items: ["🔴 Красное x2", "⚫️ Чёрное x2", "🟢 Зеро x36"])

    // Coin views
    private let coinDiscView = UIView()
    private let coinIconLabel = UILabel()
    private let coinSegment = UISegmentedControl(items: ["🦅 Орёл x2", "🪙 Решка x2"])

    // Bottom Bet Controls
    private let controlsCard = UIView()
    private let betAmountLabel = UILabel()
    private let betChipsStack = UIStackView()
    private let slotExtrasRow = UIStackView()
    private let anteButton = UIButton(type: .system)
    private let buyBonusButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)

    // Storage helpers (shared with Lua fg_casino)
    private var balance: Int {
        get {
            let obj = UserDefaults.standard.object(forKey: Self.storePrefix + "balance")
            if let num = obj as? NSNumber { return max(0, num.intValue) }
            if let str = obj as? String, let d = Double(str) { return max(0, Int(d.rounded())) }
            return 1000
        }
        set {
            let clamped = max(0, newValue)
            UserDefaults.standard.set(clamped, forKey: Self.storePrefix + "balance")
            if clamped > self.bestBalance {
                UserDefaults.standard.set(clamped, forKey: Self.storePrefix + "best_balance")
            }
            self.refreshBalanceUI()
        }
    }

    private var bestBalance: Int {
        let obj = UserDefaults.standard.object(forKey: Self.storePrefix + "best_balance")
        if let num = obj as? NSNumber { return num.intValue }
        return 1000
    }

    private var freeSpins: Int {
        get { (UserDefaults.standard.object(forKey: Self.storePrefix + "free_spins") as? NSNumber)?.intValue ?? 0 }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Self.storePrefix + "free_spins") }
    }

    private var bonusMult: Int {
        get { max(1, (UserDefaults.standard.object(forKey: Self.storePrefix + "bonus_mult") as? NSNumber)?.intValue ?? 1) }
        set { UserDefaults.standard.set(max(1, newValue), forKey: Self.storePrefix + "bonus_mult") }
    }

    private var anteEnabled: Bool {
        get { ((UserDefaults.standard.object(forKey: Self.storePrefix + "ante_bet") as? NSNumber)?.intValue ?? 0) == 1 }
        set { UserDefaults.standard.set(newValue ? 1 : 0, forKey: Self.storePrefix + "ante_bet") }
    }

    init(initialGame: String?, onSendToChat: @escaping (String) -> Void) {
        self.onSendToChat = onSendToChat
        let normalized = (initialGame ?? "").lowercased()
        if normalized.contains("dog") {
            self.currentGame = .dogs
        } else if normalized.contains("slot") || normalized.contains("777") {
            self.currentGame = .slots777
        } else if normalized.contains("crash") {
            self.currentGame = .crash
        } else if normalized.contains("roul") {
            self.currentGame = .roulette
        } else if normalized.contains("coin") {
            self.currentGame = .coin
        } else {
            self.currentGame = .zeus
        }
        super.init(nibName: nil, bundle: nil)
        self.overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    private final class DisplayLinkProxy: NSObject {
        weak var owner: FullGramCasinoBetKingViewController?
        @objc func tick() {
            self.owner?.crashFrameTick()
        }
    }

    private let displayLinkProxy = DisplayLinkProxy()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.displayLinkProxy.owner = self
        self.view.backgroundColor = self.bgDark
        self.title = "BETKING CASINO"

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = self.cardDark
        appearance.titleTextAttributes = [.foregroundColor: self.goldColor, .font: UIFont.systemFont(ofSize: 16.0, weight: .black)]
        self.navigationController?.navigationBar.standardAppearance = appearance
        self.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        self.navigationController?.navigationBar.tintColor = self.goldColor

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "В чат", style: .plain, target: self, action: #selector(self.shareResultTapped))

        self.buildLayout()
        self.selectGame(self.currentGame)
        self.refreshBalanceUI()
        self.refreshControlsUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopAllTimers()
    }

    private func stopAllTimers() {
        self.spinTimer?.invalidate()
        self.spinTimer = nil
        self.crashLink?.invalidate()
        self.crashLink = nil
        self.crashRunning = false
        self.isAnimating = false
    }

    // MARK: - Layout

    private func buildLayout() {
        let safe = self.view.safeAreaLayoutGuide

        // 1. Top Balance & Deposit Bar
        self.topBar.translatesAutoresizingMaskIntoConstraints = false
        self.topBar.backgroundColor = self.cardDark
        self.topBar.layer.cornerRadius = 16.0
        self.topBar.layer.borderWidth = 1.0
        self.topBar.layer.borderColor = self.goldColor.withAlphaComponent(0.28).cgColor
        self.view.addSubview(self.topBar)

        self.brandLabel.translatesAutoresizingMaskIntoConstraints = false
        self.brandLabel.text = "👑 BETKING"
        self.brandLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .black)
        self.brandLabel.textColor = self.goldColor
        self.topBar.addSubview(self.brandLabel)

        var balCfg = UIButton.Configuration.filled()
        balCfg.cornerStyle = .capsule
        balCfg.baseBackgroundColor = self.cardLighter
        balCfg.baseForegroundColor = .white
        balCfg.contentInsets = NSDirectionalEdgeInsets(top: 6.0, leading: 12.0, bottom: 6.0, trailing: 12.0)
        self.balancePill.configuration = balCfg
        self.balancePill.translatesAutoresizingMaskIntoConstraints = false
        self.balancePill.addTarget(self, action: #selector(self.depositTapped), for: .touchUpInside)
        self.topBar.addSubview(self.balancePill)

        var depCfg = UIButton.Configuration.filled()
        var depTitle = AttributedString("+ Баланс")
        depTitle.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        depCfg.attributedTitle = depTitle
        depCfg.cornerStyle = .capsule
        depCfg.baseBackgroundColor = self.emeraldColor
        depCfg.baseForegroundColor = .white
        depCfg.contentInsets = NSDirectionalEdgeInsets(top: 6.0, leading: 11.0, bottom: 6.0, trailing: 11.0)
        self.depositButton.configuration = depCfg
        self.depositButton.translatesAutoresizingMaskIntoConstraints = false
        self.depositButton.addTarget(self, action: #selector(self.depositTapped), for: .touchUpInside)
        self.topBar.addSubview(self.depositButton)

        // 2. Game Lobby Tabs (Horizontal Scroll)
        self.lobbyScroll.translatesAutoresizingMaskIntoConstraints = false
        self.lobbyScroll.showsHorizontalScrollIndicator = false
        self.view.addSubview(self.lobbyScroll)

        self.lobbyStack.translatesAutoresizingMaskIntoConstraints = false
        self.lobbyStack.axis = .horizontal
        self.lobbyStack.spacing = 8.0
        self.lobbyScroll.addSubview(self.lobbyStack)

        for game in GameMode.allCases {
            let btn = UIButton(type: .system)
            btn.tag = GameMode.allCases.firstIndex(of: game) ?? 0
            btn.addTarget(self, action: #selector(self.lobbyGameTapped(_:)), for: .touchUpInside)
            self.lobbyButtons[game] = btn
            self.lobbyStack.addArrangedSubview(btn)
        }

        // 3. Stage Card (Main Game Arena)
        self.stageCard.translatesAutoresizingMaskIntoConstraints = false
        self.stageCard.backgroundColor = self.cardDark
        self.stageCard.layer.cornerRadius = 20.0
        self.stageCard.layer.borderWidth = 1.0
        self.stageCard.layer.borderColor = UIColor.white.withAlphaComponent(0.09).cgColor
        self.stageCard.clipsToBounds = true
        self.view.addSubview(self.stageCard)

        self.stageHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        self.stageHeaderLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .bold)
        self.stageHeaderLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.stageCard.addSubview(self.stageHeaderLabel)

        self.freeSpinsBadge.translatesAutoresizingMaskIntoConstraints = false
        self.freeSpinsBadge.font = UIFont.systemFont(ofSize: 11.5, weight: .heavy)
        self.freeSpinsBadge.textColor = .black
        self.freeSpinsBadge.backgroundColor = self.goldColor
        self.freeSpinsBadge.layer.cornerRadius = 9.0
        self.freeSpinsBadge.clipsToBounds = true
        self.freeSpinsBadge.textAlignment = .center
        self.freeSpinsBadge.isHidden = true
        self.stageCard.addSubview(self.freeSpinsBadge)

        self.arenaView.translatesAutoresizingMaskIntoConstraints = false
        self.arenaView.backgroundColor = UIColor(red: 0.055, green: 0.075, blue: 0.13, alpha: 1.0)
        self.arenaView.layer.cornerRadius = 16.0
        self.arenaView.clipsToBounds = true
        self.stageCard.addSubview(self.arenaView)

        self.winBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.winBannerLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .heavy)
        self.winBannerLabel.textColor = self.goldColor
        self.winBannerLabel.textAlignment = .center
        self.winBannerLabel.numberOfLines = 2
        self.winBannerLabel.text = "Выберите ставку и нажмите старт!"
        self.stageCard.addSubview(self.winBannerLabel)

        // 4. Bottom Controls Card
        self.controlsCard.translatesAutoresizingMaskIntoConstraints = false
        self.controlsCard.backgroundColor = self.cardDark
        self.controlsCard.layer.cornerRadius = 20.0
        self.controlsCard.layer.borderWidth = 1.0
        self.controlsCard.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        self.view.addSubview(self.controlsCard)

        self.betAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        self.betAmountLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
        self.betAmountLabel.textColor = .white
        self.controlsCard.addSubview(self.betAmountLabel)

        self.betChipsStack.translatesAutoresizingMaskIntoConstraints = false
        self.betChipsStack.axis = .horizontal
        self.betChipsStack.spacing = 6.0
        self.betChipsStack.distribution = .fillEqually
        self.controlsCard.addSubview(self.betChipsStack)

        let chipDefs: [(String, Int)] = [("10", 10), ("50", 50), ("100", 100), ("500", 500), ("½", -1), ("2x", -2), ("MAX", -3)]
        for (title, tag) in chipDefs {
            var cfg = UIButton.Configuration.filled()
            var attr = AttributedString(title)
            attr.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
            cfg.attributedTitle = attr
            cfg.cornerStyle = .medium
            cfg.baseBackgroundColor = self.cardLighter
            cfg.baseForegroundColor = .white
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 6.0, leading: 2.0, bottom: 6.0, trailing: 2.0)
            let btn = UIButton(configuration: cfg)
            btn.tag = tag
            btn.addTarget(self, action: #selector(self.betChipTapped(_:)), for: .touchUpInside)
            self.betChipsStack.addArrangedSubview(btn)
        }

        self.slotExtrasRow.translatesAutoresizingMaskIntoConstraints = false
        self.slotExtrasRow.axis = .horizontal
        self.slotExtrasRow.spacing = 8.0
        self.slotExtrasRow.distribution = .fillEqually
        self.controlsCard.addSubview(self.slotExtrasRow)

        self.anteButton.addTarget(self, action: #selector(self.anteTapped), for: .touchUpInside)
        self.buyBonusButton.addTarget(self, action: #selector(self.buyBonusTapped), for: .touchUpInside)
        self.slotExtrasRow.addArrangedSubview(self.anteButton)
        self.slotExtrasRow.addArrangedSubview(self.buyBonusButton)

        self.actionButton.translatesAutoresizingMaskIntoConstraints = false
        self.actionButton.addTarget(self, action: #selector(self.mainActionTapped), for: .touchUpInside)
        self.controlsCard.addSubview(self.actionButton)

        NSLayoutConstraint.activate([
            self.topBar.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8.0),
            self.topBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12.0),
            self.topBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12.0),
            self.topBar.heightAnchor.constraint(equalToConstant: 48.0),

            self.brandLabel.leadingAnchor.constraint(equalTo: self.topBar.leadingAnchor, constant: 14.0),
            self.brandLabel.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),

            self.depositButton.trailingAnchor.constraint(equalTo: self.topBar.trailingAnchor, constant: -10.0),
            self.depositButton.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),

            self.balancePill.trailingAnchor.constraint(equalTo: self.depositButton.leadingAnchor, constant: -8.0),
            self.balancePill.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),

            self.lobbyScroll.topAnchor.constraint(equalTo: self.topBar.bottomAnchor, constant: 10.0),
            self.lobbyScroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.lobbyScroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.lobbyScroll.heightAnchor.constraint(equalToConstant: 38.0),

            self.lobbyStack.topAnchor.constraint(equalTo: self.lobbyScroll.contentLayoutGuide.topAnchor),
            self.lobbyStack.bottomAnchor.constraint(equalTo: self.lobbyScroll.contentLayoutGuide.bottomAnchor),
            self.lobbyStack.leadingAnchor.constraint(equalTo: self.lobbyScroll.contentLayoutGuide.leadingAnchor, constant: 12.0),
            self.lobbyStack.trailingAnchor.constraint(equalTo: self.lobbyScroll.contentLayoutGuide.trailingAnchor, constant: -12.0),
            self.lobbyStack.heightAnchor.constraint(equalTo: self.lobbyScroll.frameLayoutGuide.heightAnchor),

            self.stageCard.topAnchor.constraint(equalTo: self.lobbyScroll.bottomAnchor, constant: 10.0),
            self.stageCard.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12.0),
            self.stageCard.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12.0),
            self.stageCard.bottomAnchor.constraint(equalTo: self.controlsCard.topAnchor, constant: -10.0),

            self.stageHeaderLabel.topAnchor.constraint(equalTo: self.stageCard.topAnchor, constant: 10.0),
            self.stageHeaderLabel.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 14.0),

            self.freeSpinsBadge.centerYAnchor.constraint(equalTo: self.stageHeaderLabel.centerYAnchor),
            self.freeSpinsBadge.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -12.0),
            self.freeSpinsBadge.heightAnchor.constraint(equalToConstant: 20.0),

            self.arenaView.topAnchor.constraint(equalTo: self.stageHeaderLabel.bottomAnchor, constant: 8.0),
            self.arenaView.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 10.0),
            self.arenaView.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -10.0),
            self.arenaView.bottomAnchor.constraint(equalTo: self.winBannerLabel.topAnchor, constant: -8.0),

            self.winBannerLabel.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 12.0),
            self.winBannerLabel.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -12.0),
            self.winBannerLabel.bottomAnchor.constraint(equalTo: self.stageCard.bottomAnchor, constant: -10.0),
            self.winBannerLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36.0),

            self.controlsCard.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12.0),
            self.controlsCard.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12.0),
            self.controlsCard.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8.0),

            self.betAmountLabel.topAnchor.constraint(equalTo: self.controlsCard.topAnchor, constant: 12.0),
            self.betAmountLabel.leadingAnchor.constraint(equalTo: self.controlsCard.leadingAnchor, constant: 14.0),
            self.betAmountLabel.trailingAnchor.constraint(equalTo: self.controlsCard.trailingAnchor, constant: -14.0),

            self.betChipsStack.topAnchor.constraint(equalTo: self.betAmountLabel.bottomAnchor, constant: 8.0),
            self.betChipsStack.leadingAnchor.constraint(equalTo: self.controlsCard.leadingAnchor, constant: 12.0),
            self.betChipsStack.trailingAnchor.constraint(equalTo: self.controlsCard.trailingAnchor, constant: -12.0),
            self.betChipsStack.heightAnchor.constraint(equalToConstant: 32.0),

            self.slotExtrasRow.topAnchor.constraint(equalTo: self.betChipsStack.bottomAnchor, constant: 8.0),
            self.slotExtrasRow.leadingAnchor.constraint(equalTo: self.controlsCard.leadingAnchor, constant: 12.0),
            self.slotExtrasRow.trailingAnchor.constraint(equalTo: self.controlsCard.trailingAnchor, constant: -12.0),
            self.slotExtrasRow.heightAnchor.constraint(equalToConstant: 34.0),

            self.actionButton.topAnchor.constraint(equalTo: self.slotExtrasRow.bottomAnchor, constant: 10.0),
            self.actionButton.leadingAnchor.constraint(equalTo: self.controlsCard.leadingAnchor, constant: 12.0),
            self.actionButton.trailingAnchor.constraint(equalTo: self.controlsCard.trailingAnchor, constant: -12.0),
            self.actionButton.bottomAnchor.constraint(equalTo: self.controlsCard.bottomAnchor, constant: -12.0),
            self.actionButton.heightAnchor.constraint(equalToConstant: 48.0)
        ])
    }

    // MARK: - Game Switching & Arena Setup

    private func selectGame(_ game: GameMode) {
        self.stopAllTimers()
        self.currentGame = game
        self.stageHeaderLabel.text = game.fullTitle
        self.stageCard.layer.borderColor = game.accentColor.withAlphaComponent(0.35).cgColor

        for (g, btn) in self.lobbyButtons {
            var cfg = UIButton.Configuration.filled()
            var attr = AttributedString(g.shortTitle)
            attr.font = UIFont.systemFont(ofSize: 13.0, weight: .bold)
            cfg.attributedTitle = attr
            cfg.cornerStyle = .capsule
            cfg.baseBackgroundColor = (g == game) ? g.accentColor : self.cardLighter
            cfg.baseForegroundColor = (g == game) ? .black : .white
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 6.0, leading: 14.0, bottom: 6.0, trailing: 14.0)
            btn.configuration = cfg
        }

        self.arenaView.subviews.forEach { $0.removeFromSuperview() }
        self.arenaView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.slotCellViews.removeAll()

        switch game {
        case .zeus:
            self.setupSlotGrid(rows: 3, cols: 5, defaults: ["⚡", "👑", "💎", "💍", "🏆", "⏳", "💎", "⚡", "👑", "⏳", "🏆", "💍", "💎", "⚡", "👑"])
        case .dogs:
            self.setupSlotGrid(rows: 3, cols: 5, defaults: ["🐶", "🏠", "💎", "🦴", "🐾", "🎾", "🐶", "🏠", "🐾", "💎", "🦴", "🎾", "🐶", "🏠", "🦴"])
        case .slots777:
            self.setupSlotGrid(rows: 1, cols: 3, defaults: ["7️⃣", "💎", "7️⃣"])
        case .crash:
            self.setupCrashArena()
        case .roulette:
            self.setupRouletteArena()
        case .coin:
            self.setupCoinArena()
        }

        self.winBannerLabel.textColor = self.goldColor
        self.winBannerLabel.text = "Готово к игре!"
        self.refreshControlsUI()
    }

    private func setupSlotGrid(rows: Int, cols: Int, defaults: [String]) {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 8.0
        vStack.distribution = .fillEqually
        vStack.translatesAutoresizingMaskIntoConstraints = false
        self.arenaView.addSubview(vStack)

        let vPad: CGFloat = rows == 1 ? 52.0 : 12.0
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: self.arenaView.topAnchor, constant: vPad),
            vStack.bottomAnchor.constraint(equalTo: self.arenaView.bottomAnchor, constant: -vPad),
            vStack.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 12.0),
            vStack.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -12.0)
        ])

        var idx = 0
        for _ in 0 ..< rows {
            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 8.0
            hStack.distribution = .fillEqually
            for _ in 0 ..< cols {
                let lbl = UILabel()
                lbl.text = idx < defaults.count ? defaults[idx] : "💎"
                lbl.font = UIFont.systemFont(ofSize: rows == 1 ? 52.0 : 30.0)
                lbl.textAlignment = .center
                lbl.backgroundColor = self.cardLighter
                lbl.layer.cornerRadius = 12.0
                lbl.clipsToBounds = true
                lbl.layer.borderWidth = 1.0
                lbl.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
                self.slotCellViews.append(lbl)
                hStack.addArrangedSubview(lbl)
                idx += 1
            }
            vStack.addArrangedSubview(hStack)
        }
    }

    private func setupCrashArena() {
        self.crashFillLayer.fillColor = self.emeraldColor.withAlphaComponent(0.18).cgColor
        self.crashCurveLayer.strokeColor = self.emeraldColor.cgColor
        self.crashCurveLayer.fillColor = UIColor.clear.cgColor
        self.crashCurveLayer.lineWidth = 4.0
        self.crashCurveLayer.lineCap = .round
        self.arenaView.layer.addSublayer(self.crashFillLayer)
        self.arenaView.layer.addSublayer(self.crashCurveLayer)

        self.crashMultLabel.translatesAutoresizingMaskIntoConstraints = false
        self.crashMultLabel.text = "1.00x"
        self.crashMultLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 48.0, weight: .black)
        self.crashMultLabel.textColor = .white
        self.crashMultLabel.textAlignment = .center
        self.arenaView.addSubview(self.crashMultLabel)

        self.crashStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.crashStatusLabel.text = "Нажмите ВЗЛЁТ и заберите до взрыва!"
        self.crashStatusLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.crashStatusLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.crashStatusLabel.textAlignment = .center
        self.arenaView.addSubview(self.crashStatusLabel)

        self.crashRocketLabel.text = "🚀"
        self.crashRocketLabel.font = UIFont.systemFont(ofSize: 32.0)
        self.crashRocketLabel.sizeToFit()
        self.crashRocketLabel.center = CGPoint(x: 34.0, y: 180.0)
        self.arenaView.addSubview(self.crashRocketLabel)

        NSLayoutConstraint.activate([
            self.crashMultLabel.centerXAnchor.constraint(equalTo: self.arenaView.centerXAnchor),
            self.crashMultLabel.centerYAnchor.constraint(equalTo: self.arenaView.centerYAnchor, constant: -14.0),
            self.crashStatusLabel.topAnchor.constraint(equalTo: self.crashMultLabel.bottomAnchor, constant: 6.0),
            self.crashStatusLabel.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 12.0),
            self.crashStatusLabel.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -12.0)
        ])
    }

    private func setupRouletteArena() {
        self.rouletteViewport.translatesAutoresizingMaskIntoConstraints = false
        self.rouletteViewport.backgroundColor = self.bgDark
        self.rouletteViewport.layer.cornerRadius = 14.0
        self.rouletteViewport.clipsToBounds = true
        self.rouletteViewport.layer.borderWidth = 1.5
        self.rouletteViewport.layer.borderColor = self.goldColor.withAlphaComponent(0.55).cgColor
        self.arenaView.addSubview(self.rouletteViewport)

        self.rouletteViewport.addSubview(self.rouletteStripView)

        self.roulettePointer.translatesAutoresizingMaskIntoConstraints = false
        self.roulettePointer.backgroundColor = self.goldColor
        self.roulettePointer.layer.cornerRadius = 2.0
        self.rouletteViewport.addSubview(self.roulettePointer)

        self.rouletteResultLabel.translatesAutoresizingMaskIntoConstraints = false
        self.rouletteResultLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .black)
        self.rouletteResultLabel.textColor = .white
        self.rouletteResultLabel.textAlignment = .center
        self.rouletteResultLabel.text = "🎡 Выберите цвет"
        self.arenaView.addSubview(self.rouletteResultLabel)

        self.rouletteBetSegment.translatesAutoresizingMaskIntoConstraints = false
        self.rouletteBetSegment.selectedSegmentIndex = self.selectedRouletteBet.rawValue
        self.rouletteBetSegment.addTarget(self, action: #selector(self.rouletteBetChanged), for: .valueChanged)
        self.arenaView.addSubview(self.rouletteBetSegment)

        NSLayoutConstraint.activate([
            self.rouletteViewport.topAnchor.constraint(equalTo: self.arenaView.topAnchor, constant: 22.0),
            self.rouletteViewport.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 14.0),
            self.rouletteViewport.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -14.0),
            self.rouletteViewport.heightAnchor.constraint(equalToConstant: 74.0),

            self.roulettePointer.centerXAnchor.constraint(equalTo: self.rouletteViewport.centerXAnchor),
            self.roulettePointer.topAnchor.constraint(equalTo: self.rouletteViewport.topAnchor),
            self.roulettePointer.bottomAnchor.constraint(equalTo: self.rouletteViewport.bottomAnchor),
            self.roulettePointer.widthAnchor.constraint(equalToConstant: 3.0),

            self.rouletteResultLabel.topAnchor.constraint(equalTo: self.rouletteViewport.bottomAnchor, constant: 14.0),
            self.rouletteResultLabel.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 12.0),
            self.rouletteResultLabel.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -12.0),

            self.rouletteBetSegment.bottomAnchor.constraint(equalTo: self.arenaView.bottomAnchor, constant: -14.0),
            self.rouletteBetSegment.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 14.0),
            self.rouletteBetSegment.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -14.0)
        ])

        self.populateRouletteStrip(highlightNumber: nil)
    }

    private func populateRouletteStrip(highlightNumber: Int?) {
        self.rouletteStripView.subviews.forEach { $0.removeFromSuperview() }
        let tileW: CGFloat = 56.0
        let tileH: CGFloat = 58.0
        let count = 60
        self.rouletteStripView.frame = CGRect(x: 0.0, y: 8.0, width: CGFloat(count) * tileW, height: tileH)
        for i in 0 ..< count {
            let num = (i == 42 && highlightNumber != nil) ? highlightNumber! : (i * 7 + 3) % 37
            let tile = UILabel(frame: CGRect(x: CGFloat(i) * tileW + 3.0, y: 0.0, width: tileW - 6.0, height: tileH))
            tile.text = "\(num)"
            tile.font = UIFont.systemFont(ofSize: 18.0, weight: .black)
            tile.textColor = .white
            tile.textAlignment = .center
            tile.layer.cornerRadius = 10.0
            tile.clipsToBounds = true
            if num == 0 {
                tile.backgroundColor = self.emeraldColor
            } else if Self.redNumbers.contains(num) {
                tile.backgroundColor = UIColor(red: 0.85, green: 0.18, blue: 0.22, alpha: 1.0)
            } else {
                tile.backgroundColor = UIColor(red: 0.14, green: 0.17, blue: 0.23, alpha: 1.0)
            }
            self.rouletteStripView.addSubview(tile)
        }
    }

    private func setupCoinArena() {
        self.coinDiscView.translatesAutoresizingMaskIntoConstraints = false
        self.coinDiscView.backgroundColor = self.goldColor
        self.coinDiscView.layer.cornerRadius = 56.0
        self.coinDiscView.layer.borderWidth = 5.0
        self.coinDiscView.layer.borderColor = UIColor(red: 1.0, green: 0.88, blue: 0.48, alpha: 1.0).cgColor
        self.coinDiscView.layer.shadowColor = self.goldColor.cgColor
        self.coinDiscView.layer.shadowOpacity = 0.5
        self.coinDiscView.layer.shadowRadius = 18.0
        self.coinDiscView.layer.shadowOffset = .zero
        self.arenaView.addSubview(self.coinDiscView)

        self.coinIconLabel.translatesAutoresizingMaskIntoConstraints = false
        self.coinIconLabel.text = self.selectedCoinTails ? "🪙" : "🦅"
        self.coinIconLabel.font = UIFont.systemFont(ofSize: 54.0)
        self.coinIconLabel.textAlignment = .center
        self.coinDiscView.addSubview(self.coinIconLabel)

        self.coinSegment.translatesAutoresizingMaskIntoConstraints = false
        self.coinSegment.selectedSegmentIndex = self.selectedCoinTails ? 1 : 0
        self.coinSegment.addTarget(self, action: #selector(self.coinSideChanged), for: .valueChanged)
        self.arenaView.addSubview(self.coinSegment)

        NSLayoutConstraint.activate([
            self.coinDiscView.centerXAnchor.constraint(equalTo: self.arenaView.centerXAnchor),
            self.coinDiscView.centerYAnchor.constraint(equalTo: self.arenaView.centerYAnchor, constant: -18.0),
            self.coinDiscView.widthAnchor.constraint(equalToConstant: 112.0),
            self.coinDiscView.heightAnchor.constraint(equalToConstant: 112.0),

            self.coinIconLabel.centerXAnchor.constraint(equalTo: self.coinDiscView.centerXAnchor),
            self.coinIconLabel.centerYAnchor.constraint(equalTo: self.coinDiscView.centerYAnchor),

            self.coinSegment.bottomAnchor.constraint(equalTo: self.arenaView.bottomAnchor, constant: -14.0),
            self.coinSegment.leadingAnchor.constraint(equalTo: self.arenaView.leadingAnchor, constant: 24.0),
            self.coinSegment.trailingAnchor.constraint(equalTo: self.arenaView.trailingAnchor, constant: -24.0)
        ])
    }

    // MARK: - UI Refresh

    private func refreshBalanceUI() {
        var cfg = self.balancePill.configuration ?? UIButton.Configuration.filled()
        var title = AttributedString("💰 \(self.balance) 🪙")
        title.font = UIFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .bold)
        cfg.attributedTitle = title
        self.balancePill.configuration = cfg

        let fs = self.freeSpins
        if fs > 0 && (self.currentGame == .zeus || self.currentGame == .dogs) {
            self.freeSpinsBadge.isHidden = false
            self.freeSpinsBadge.text = "  🎁 FS: \(fs) (x\(self.bonusMult))  "
        } else {
            self.freeSpinsBadge.isHidden = true
        }
    }

    private func refreshControlsUI() {
        let isSlotWithExtras = (self.currentGame == .zeus || self.currentGame == .dogs)
        self.slotExtrasRow.isHidden = !isSlotWithExtras

        let effCost = (isSlotWithExtras && self.anteEnabled) ? Int((Double(self.currentBet) * 1.25).rounded()) : self.currentBet
        self.betAmountLabel.text = isSlotWithExtras && self.anteEnabled
            ? "Ставка: \(self.currentBet) 🪙 (с Ante +25%: \(effCost) 🪙)"
            : "Ставка: \(self.currentBet) 🪙"

        var anteCfg = UIButton.Configuration.filled()
        var anteTitle = AttributedString(self.anteEnabled ? "⚡ Ante +25%: ВКЛ" : "⚡ Ante +25%: ВЫКЛ")
        anteTitle.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        anteCfg.attributedTitle = anteTitle
        anteCfg.cornerStyle = .medium
        anteCfg.baseBackgroundColor = self.anteEnabled ? self.goldColor : self.cardLighter
        anteCfg.baseForegroundColor = self.anteEnabled ? .black : .white
        self.anteButton.configuration = anteCfg

        var bonusCfg = UIButton.Configuration.filled()
        var bonusTitle = AttributedString("🎁 Buy Bonus (\(self.currentBet * 100) 🪙)")
        bonusTitle.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        bonusCfg.attributedTitle = bonusTitle
        bonusCfg.cornerStyle = .medium
        bonusCfg.baseBackgroundColor = UIColor(red: 0.56, green: 0.27, blue: 0.92, alpha: 1.0)
        bonusCfg.baseForegroundColor = .white
        self.buyBonusButton.configuration = bonusCfg

        var actCfg = UIButton.Configuration.filled()
        let actText: String
        let actBg: UIColor
        let actFg: UIColor
        if self.currentGame == .crash && self.crashRunning {
            let cash = Int((Double(self.crashActiveBet) * self.crashCurrentMult).rounded())
            actText = "ЗАБРАТЬ \(String(format: "%.2fx", self.crashCurrentMult)) (+\(cash) 🪙)"
            actBg = self.emeraldColor
            actFg = .white
        } else {
            switch self.currentGame {
            case .zeus, .dogs:
                actText = self.freeSpins > 0 ? "🎁 ФРИСПИН (\(self.freeSpins))" : "⚡ КРУТИТЬ (\(effCost) 🪙)"
            case .slots777:
                actText = "🎰 КРУТИТЬ (\(self.currentBet) 🪙)"
            case .crash:
                actText = "🚀 ВЗЛЁТ (\(self.currentBet) 🪙)"
            case .roulette:
                actText = "🎡 КРУТИТЬ КОЛЕСО (\(self.currentBet) 🪙)"
            case .coin:
                actText = "🪙 БРОСИТЬ МОНЕТУ (\(self.currentBet) 🪙)"
            }
            actBg = self.currentGame.accentColor
            actFg = (self.currentGame == .zeus || self.currentGame == .coin) ? .black : .white
        }
        var actAttr = AttributedString(actText)
        actAttr.font = UIFont.systemFont(ofSize: 16.0, weight: .black)
        actCfg.attributedTitle = actAttr
        actCfg.cornerStyle = .capsule
        actCfg.baseBackgroundColor = actBg
        actCfg.baseForegroundColor = actFg
        self.actionButton.configuration = actCfg
        self.refreshBalanceUI()
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        self.stopAllTimers()
        self.dismiss(animated: true)
    }

    @objc private func shareResultTapped() {
        let msg = self.lastSummaryForChat.isEmpty
            ? "👑 BetKing Casino FullGram · Баланс: \(self.balance) 🪙 (Рекорд: \(self.bestBalance) 🪙)"
            : self.lastSummaryForChat
        self.onSendToChat(msg)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @objc private func depositTapped() {
        let alert = UIAlertController(
            title: "💰 Пополнение баланса",
            message: "Текущий баланс: \(self.balance) 🪙. Введите сумму (или выберите быстрое пополнение):",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "50000"
            tf.text = "10000"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Добавить (+)", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let addVal = Int(raw) ?? 10000
            self.balance += max(100, addVal)
            self.refreshControlsUI()
        })
        alert.addAction(UIAlertAction(title: "Установить точно", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            if let exact = Int(raw) {
                self.balance = max(0, exact)
                self.refreshControlsUI()
            }
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func lobbyGameTapped(_ sender: UIButton) {
        let all = GameMode.allCases
        guard sender.tag >= 0 && sender.tag < all.count else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        self.selectGame(all[sender.tag])
    }

    @objc private func betChipTapped(_ sender: UIButton) {
        guard !self.isAnimating && !self.crashRunning else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let bal = max(10, self.balance)
        switch sender.tag {
        case -1: self.currentBet = max(10, self.currentBet / 2)
        case -2: self.currentBet = min(bal, max(10, self.currentBet * 2))
        case -3: self.currentBet = bal
        default: self.currentBet = min(bal, max(10, sender.tag))
        }
        self.refreshControlsUI()
    }

    @objc private func anteTapped() {
        guard !self.isAnimating, self.freeSpins == 0 else { return }
        self.anteEnabled.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        self.refreshControlsUI()
    }

    @objc private func buyBonusTapped() {
        guard !self.isAnimating else { return }
        let cost = self.currentBet * 100
        guard self.balance >= cost else {
            self.winBannerLabel.textColor = .systemRed
            self.winBannerLabel.text = "Нужно \(cost) 🪙 для Buy Bonus (пополните баланс сверху!)"
            return
        }
        self.balance -= cost
        self.freeSpins += 10
        self.bonusMult = 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.winBannerLabel.textColor = self.goldColor
        self.winBannerLabel.text = "🎁 БОНУС КУПЛЕН! 10 ФРИСПИНОВ по ставке \(self.currentBet) 🪙!"
        self.refreshControlsUI()
    }

    @objc private func rouletteBetChanged() {
        self.selectedRouletteBet = RouletteBet(rawValue: self.rouletteBetSegment.selectedSegmentIndex) ?? .red
    }

    @objc private func coinSideChanged() {
        self.selectedCoinTails = self.coinSegment.selectedSegmentIndex == 1
        self.coinIconLabel.text = self.selectedCoinTails ? "🪙" : "🦅"
    }

    @objc private func mainActionTapped() {
        if self.currentGame == .crash {
            if self.crashRunning {
                self.cashoutCrash()
            } else {
                self.startCrashRound()
            }
            return
        }
        guard !self.isAnimating else { return }
        switch self.currentGame {
        case .zeus: self.playAnimatedSlots(isZeus: true)
        case .dogs: self.playAnimatedSlots(isZeus: false)
        case .slots777: self.playAnimated777()
        case .roulette: self.playAnimatedRoulette()
        case .coin: self.playAnimatedCoin()
        case .crash: break
        }
    }

    private func ensureBalanceForBet() -> Int {
        if self.balance < 10 {
            self.balance = 500
        }
        if self.currentBet > self.balance {
            self.currentBet = self.balance
        }
        return max(10, self.currentBet)
    }

    // MARK: - 1 & 2. Animated 5x3 Slots (Gates of Olympus / The Dog House)

    private func playAnimatedSlots(isZeus: Bool) {
        let isFS = self.freeSpins > 0
        let baseBet = self.ensureBalanceForBet()
        let cost = isFS ? 0 : min(self.balance, self.anteEnabled ? Int((Double(baseBet) * 1.25).rounded()) : baseBet)
        if !isFS {
            self.balance -= cost
        } else {
            self.freeSpins -= 1
        }

        self.isAnimating = true
        self.winBannerLabel.textColor = UIColor(white: 0.78, alpha: 1.0)
        self.winBannerLabel.text = isZeus ? "⚡ Вращение барабанов Олимпа…" : "🐶 Барабаны крутятся…"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let pool: [(String, Int)] = isZeus
            ? ((self.anteEnabled || isFS) ? [("💎", 26), ("⏳", 21), ("🏆", 17), ("💍", 14), ("👑", 10), ("⚡", 12)] : [("💎", 30), ("⏳", 23), ("🏆", 18), ("💍", 14), ("👑", 9), ("⚡", 6)])
            : ((self.anteEnabled || isFS) ? [("🦴", 23), ("🐾", 20), ("🎾", 17), ("💎", 14), ("🐶", 11), ("🏠", 15)] : [("🦴", 27), ("🐾", 22), ("🎾", 18), ("💎", 14), ("🐶", 11), ("🏠", 8)])
        let finalGrid: [String] = (0 ..< 15).map { _ in Self.pickWeighted(pool) }

        for cell in self.slotCellViews {
            cell.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
            cell.layer.borderWidth = 1.0
        }

        var tick = 0
        self.spinTimer?.invalidate()
        self.spinTimer = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                tick += 1
                for col in 0 ..< 5 {
                    let stopTick = 6 + col * 2
                    for row in 0 ..< 3 {
                        let idx = row * 5 + col
                        guard idx < self.slotCellViews.count else { continue }
                        let cell = self.slotCellViews[idx]
                        if tick < stopTick {
                            cell.text = pool.randomElement()?.0 ?? "💎"
                        } else if tick == stopTick {
                            cell.text = finalGrid[idx]
                            cell.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
                            UIView.animate(withDuration: 0.18, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.7) {
                                cell.transform = .identity
                            }
                            if row == 0 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                }
                if tick >= 15 {
                    timer.invalidate()
                    self.spinTimer = nil
                    self.finishSlotsRound(isZeus: isZeus, grid: finalGrid, baseBet: baseBet, cost: cost, isFS: isFS)
                }
            }
        }
    }

    private func finishSlotsRound(isZeus: Bool, grid: [String], baseBet: Int, cost: Int, isFS: Bool) {
        self.isAnimating = false
        var counts: [String: Int] = [:]
        for s in grid { counts[s, default: 0] += 1 }

        var mult = 0.0
        var highlightSymbol: String?
        var statusText = "❌ Пустой спин"

        if isZeus {
            let bolts = counts["⚡"] ?? 0
            let pays: [String: Double] = ["💎": 0.4, "⏳": 0.6, "🏆": 0.9, "💍": 1.3, "👑": 2.2]
            var bestPay = 0.0
            for (sym, base) in pays {
                let c = counts[sym] ?? 0
                if c >= 6 {
                    let cand = base * (1.0 + Double(c - 6) * 0.65)
                    if cand > bestPay {
                        bestPay = cand
                        highlightSymbol = sym
                    }
                }
            }
            if bestPay > 0 {
                let orb = (bolts > 0 || isFS) ? Self.pickZeusOrb() : 1
                if isFS && orb > 1 { self.bonusMult += orb }
                let effOrb = isFS ? max(1, self.bonusMult) : orb
                mult = bestPay * Double(effOrb)
                statusText = effOrb > 1 ? "⚡ МОЛНИЯ ЗЕВСА x\(effOrb)!" : "👑 СЫГРОВКА \(highlightSymbol ?? "")!"
            }
            if bolts >= 4 {
                self.freeSpins += isFS ? 5 : 10
                if !isFS { self.bonusMult = 1; mult = max(mult, 3.0) }
                statusText = isFS ? "⚡ РЕТРИГГЕР +5 ФРИСПИНОВ!" : "⚡ 4+ SCATTER! +10 ФРИСПИНОВ!"
            }
        } else {
            let kennels = counts["🏠"] ?? 0
            let lineW: [String: Double] = ["🦴": 0.4, "🐾": 0.6, "🎾": 0.85, "💎": 1.4, "🐶": 2.4]
            var lineSum = 0.0
            for r in 0 ..< 3 {
                var anchor = "🐶"
                for c in 0 ..< 5 {
                    let s = grid[r * 5 + c]
                    if s != "🏠" { anchor = s; break }
                }
                var streak = 0
                for c in 0 ..< 5 {
                    let s = grid[r * 5 + c]
                    if s == anchor || s == "🏠" { streak += 1 } else { break }
                }
                if streak >= 3 {
                    lineSum += (lineW[anchor] ?? 0.6) * Double(streak - 1)
                    highlightSymbol = anchor
                }
            }
            if lineSum > 0 {
                let km = kennels > 0 ? max(1, (0 ..< min(kennels, 4)).reduce(0) { acc, _ in acc + (Int.random(in: 0 ..< 10) < 7 ? 2 : 3) }) : 1
                if isFS && kennels > 0 { self.bonusMult = min(27, self.bonusMult + km) }
                let eff = isFS ? self.bonusMult : km
                mult = lineSum * Double(eff)
                statusText = eff > 1 ? "🐶 БУДКИ x\(eff) · ЗАНОС!" : "🐶 ЛИНИЯ СЫГРАЛА!"
            }
            if kennels >= 4 {
                self.freeSpins += isFS ? 5 : 10
                if !isFS { self.bonusMult = 1; mult = max(mult, 2.0) }
                statusText = "🏠 БОНУС ФРИСПИНЫ СОБАК!"
            }
        }

        let payout = Int((Double(baseBet) * mult).rounded())
        self.balance += payout
        let net = payout - cost

        if let winSym = highlightSymbol {
            for (idx, s) in grid.enumerated() where (s == winSym || s == "⚡" || s == "🏠") && idx < self.slotCellViews.count {
                let cell = self.slotCellViews[idx]
                cell.layer.borderColor = self.goldColor.cgColor
                cell.layer.borderWidth = 2.5
            }
        }

        if payout > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.winBannerLabel.textColor = self.emeraldColor
            self.winBannerLabel.text = "\(statusText)  +\(payout) 🪙"
            self.pulseBanner()
        } else {
            self.winBannerLabel.textColor = UIColor(white: 0.65, alpha: 1.0)
            self.winBannerLabel.text = "\(statusText) (\(net) 🪙)"
        }

        let title = isZeus ? "⚡ Gates of Olympus" : "🐶 The Dog House"
        self.lastSummaryForChat = "👑 BetKing · \(title)\n\(statusText) · Выплата: \(payout) 🪙 · Баланс: \(self.balance) 🪙"
        self.refreshControlsUI()
    }

    // MARK: - 3. Animated 3-Reel Slots 777

    private func playAnimated777() {
        let bet = self.ensureBalanceForBet()
        self.balance -= bet
        self.isAnimating = true
        self.winBannerLabel.textColor = UIColor(white: 0.78, alpha: 1.0)
        self.winBannerLabel.text = "🎰 Барабаны 777 вращаются…"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let pool = [("🍒", 36), ("🍋", 26), ("🔔", 18), ("💎", 13), ("7️⃣", 7)]
        let finalSyms = [Self.pickWeighted(pool), Self.pickWeighted(pool), Self.pickWeighted(pool)]
        var tick = 0
        self.spinTimer?.invalidate()
        self.spinTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                tick += 1
                for col in 0 ..< 3 {
                    guard col < self.slotCellViews.count else { continue }
                    let stopTick = 8 + col * 4
                    if tick < stopTick {
                        self.slotCellViews[col].text = pool.randomElement()?.0 ?? "🍒"
                    } else if tick == stopTick {
                        self.slotCellViews[col].text = finalSyms[col]
                        self.slotCellViews[col].transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
                        UIView.animate(withDuration: 0.22, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
                            self.slotCellViews[col].transform = .identity
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                if tick >= 17 {
                    timer.invalidate()
                    self.spinTimer = nil
                    self.isAnimating = false
                    let s1 = finalSyms[0], s2 = finalSyms[1], s3 = finalSyms[2]
                    let sevens = finalSyms.filter { $0 == "7️⃣" }.count
                    let diamonds = finalSyms.filter { $0 == "💎" }.count
                    var mult = 0.0
                    var status = "❌ Мимо!"
                    if s1 == s2 && s2 == s3 {
                        if s1 == "7️⃣" { mult = 50.0; status = "🔥 МЕГА ДЖЕКПОТ 777 (x50)!" }
                        else if s1 == "💎" { mult = 15.0; status = "💎 АЛМАЗНЫЙ ДЖЕКПОТ (x15)!" }
                        else if s1 == "🔔" { mult = 8.0; status = "🔔 3 КОЛОКОЛА (x8)!" }
                        else if s1 == "🍋" { mult = 5.0; status = "🍋 3 ЛИМОНА (x5)!" }
                        else { mult = 3.0; status = "🍒 3 ВИШНИ (x3)!" }
                    } else if sevens == 2 {
                        mult = 3.0; status = "7️⃣ Две Семёрки (x3)!"
                    } else if diamonds == 2 {
                        mult = 2.0; status = "💎 Два Алмаза (x2)!"
                    } else if s1 == s2 || s2 == s3 || s1 == s3 {
                        mult = 1.2; status = "✨ Пара (x1.2)!"
                    }
                    let payout = Int((Double(bet) * mult).rounded())
                    self.balance += payout
                    if payout > 0 {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.winBannerLabel.textColor = self.emeraldColor
                        self.winBannerLabel.text = "\(status) +\(payout) 🪙"
                        self.pulseBanner()
                    } else {
                        self.winBannerLabel.textColor = UIColor(white: 0.65, alpha: 1.0)
                        self.winBannerLabel.text = "\(status) (-\(bet) 🪙)"
                    }
                    self.lastSummaryForChat = "👑 BetKing · 🎰 777 [\(s1)|\(s2)|\(s3)]\n\(status) · Выплата: \(payout) 🪙 · Баланс: \(self.balance) 🪙"
                    self.refreshControlsUI()
                }
            }
        }
    }

    // MARK: - 4. Live Animated Crash Game (CADisplayLink)

    private func startCrashRound() {
        let bet = self.ensureBalanceForBet()
        self.balance -= bet
        self.crashActiveBet = bet
        self.crashCurrentMult = 1.0
        self.crashRunning = true
        self.crashStartTime = CACurrentMediaTime()

        if Int.random(in: 0 ..< 100) < 3 {
            self.crashTargetPoint = 1.01
        } else {
            let u = Double.random(in: 0.01 ... 0.99)
            self.crashTargetPoint = min(50.0, max(1.06, 0.97 / (1.0 - u)))
        }

        self.crashCurveLayer.strokeColor = self.emeraldColor.cgColor
        self.crashFillLayer.fillColor = self.emeraldColor.withAlphaComponent(0.18).cgColor
        self.crashMultLabel.textColor = .white
        self.crashRocketLabel.text = "🚀"
        self.crashStatusLabel.text = "Ракета летит — жми ЗАБРАТЬ!"
        self.winBannerLabel.textColor = self.emeraldColor
        self.winBannerLabel.text = "Ставка \(bet) 🪙 в игре!"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        self.crashLink?.invalidate()
        let link = CADisplayLink(target: self.displayLinkProxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        self.crashLink = link
        self.refreshControlsUI()
    }

    @objc private func crashFrameTick() {
        guard self.crashRunning else { return }
        let elapsed = max(0.0, CACurrentMediaTime() - self.crashStartTime)
        let mult = exp(elapsed * 0.24)
        self.crashCurrentMult = mult

        if mult >= self.crashTargetPoint {
            self.crashRunning = false
            self.crashLink?.invalidate()
            self.crashLink = nil
            self.crashCurveLayer.strokeColor = UIColor.systemRed.cgColor
            self.crashFillLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.20).cgColor
            self.crashMultLabel.text = String(format: "%.2fx", self.crashTargetPoint)
            self.crashMultLabel.textColor = .systemRed
            self.crashRocketLabel.text = "💥"
            self.crashStatusLabel.text = "КРАШ на \(String(format: "%.2fx", self.crashTargetPoint))!"
            self.winBannerLabel.textColor = .systemRed
            self.winBannerLabel.text = "💥 КРАШ на \(String(format: "%.2fx", self.crashTargetPoint)) (-\(self.crashActiveBet) 🪙)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.lastSummaryForChat = "👑 BetKing · 🚀 Crash\n💥 Краш на \(String(format: "%.2fx", self.crashTargetPoint)) · Баланс: \(self.balance) 🪙"
            self.refreshControlsUI()
            return
        }

        self.crashMultLabel.text = String(format: "%.2fx", mult)
        self.updateCrashCurve(elapsed: elapsed)
        self.refreshControlsUI()
    }

    private func cashoutCrash() {
        guard self.crashRunning else { return }
        self.crashRunning = false
        self.crashLink?.invalidate()
        self.crashLink = nil
        let payout = Int((Double(self.crashActiveBet) * self.crashCurrentMult).rounded())
        self.balance += payout
        self.crashMultLabel.textColor = self.emeraldColor
        self.crashStatusLabel.text = "Забрано на \(String(format: "%.2fx", self.crashCurrentMult)) (краш был \(String(format: "%.2fx", self.crashTargetPoint)))"
        self.winBannerLabel.textColor = self.emeraldColor
        self.winBannerLabel.text = "✅ ЗАБРАЛ \(String(format: "%.2fx", self.crashCurrentMult))! +\(payout) 🪙"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.pulseBanner()
        self.lastSummaryForChat = "👑 BetKing · 🚀 Crash\n✅ Забрал на \(String(format: "%.2fx", self.crashCurrentMult)) (+\(payout) 🪙) · Баланс: \(self.balance) 🪙"
        self.refreshControlsUI()
    }

    private func updateCrashCurve(elapsed: CFTimeInterval) {
        let bounds = self.arenaView.bounds
        guard bounds.width > 40, bounds.height > 40 else { return }
        let progress = min(1.0, CGFloat(elapsed / 8.0))
        let startX: CGFloat = 18.0
        let startY: CGFloat = bounds.height - 20.0
        let endX = startX + (bounds.width - 56.0) * max(0.05, progress)
        let endY = startY - (bounds.height - 56.0) * pow(max(0.05, progress), 1.35)
        let ctrlX = startX + (endX - startX) * 0.65
        let ctrlY = startY - (startY - endY) * 0.15

        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addQuadCurve(to: CGPoint(x: endX, y: endY), controlPoint: CGPoint(x: ctrlX, y: ctrlY))
        self.crashCurveLayer.path = path.cgPath

        let fillPath = UIBezierPath(cgPath: path.cgPath)
        fillPath.addLine(to: CGPoint(x: endX, y: startY))
        fillPath.close()
        self.crashFillLayer.path = fillPath.cgPath

        self.crashRocketLabel.center = CGPoint(x: endX, y: endY - 8.0)
    }

    // MARK: - 5. Animated Roulette

    private func playAnimatedRoulette() {
        let bet = self.ensureBalanceForBet()
        self.balance -= bet
        self.isAnimating = true
        let landed = Int.random(in: 0 ... 36)
        self.populateRouletteStrip(highlightNumber: landed)
        self.rouletteStripView.frame.origin.x = 0.0
        self.rouletteResultLabel.text = "🎡 Колесо крутится…"
        self.winBannerLabel.textColor = UIColor(white: 0.78, alpha: 1.0)
        self.winBannerLabel.text = "Ставка \(bet) 🪙 принята!"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let tileW: CGFloat = 56.0
        let targetCenterX = CGFloat(42) * tileW + tileW * 0.5
        let finalOffsetX = self.rouletteViewport.bounds.width * 0.5 - targetCenterX

        UIView.animate(withDuration: 2.3, delay: 0.0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.2, options: [.curveEaseOut]) {
            self.rouletteStripView.frame.origin.x = finalOffsetX
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimating = false
            let isGreen = (landed == 0)
            let isRed = Self.redNumbers.contains(landed)
            let won: Bool
            let mult: Int
            switch self.selectedRouletteBet {
            case .red: won = isRed; mult = 2
            case .black: won = !isRed && !isGreen; mult = 2
            case .green: won = isGreen; mult = 36
            }
            let badge = isGreen ? "🟢 Зеро [0]" : (isRed ? "🔴 Красное [\(landed)]" : "⚫️ Чёрное [\(landed)]")
            self.rouletteResultLabel.text = "Выпало: \(badge)"
            let payout = won ? bet * mult : 0
            self.balance += payout
            if won {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.winBannerLabel.textColor = self.emeraldColor
                self.winBannerLabel.text = "✅ ВЫИГРЫШ x\(mult)! +\(payout) 🪙"
                self.pulseBanner()
            } else {
                self.winBannerLabel.textColor = .systemRed
                self.winBannerLabel.text = "❌ Мимо (-\(bet) 🪙)"
            }
            self.lastSummaryForChat = "👑 BetKing · 🎡 Рулетка\nВыпало \(badge) · Выплата: \(payout) 🪙 · Баланс: \(self.balance) 🪙"
            self.refreshControlsUI()
        }
    }

    // MARK: - 6. Animated 3D Coin Flip

    private func playAnimatedCoin() {
        let bet = self.ensureBalanceForBet()
        self.balance -= bet
        self.isAnimating = true
        self.winBannerLabel.textColor = UIColor(white: 0.78, alpha: 1.0)
        self.winBannerLabel.text = "🪙 Монета в воздухе…"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let won = Int.random(in: 0 ..< 100) < 49
        let landedTails = self.selectedCoinTails ? won : !won

        let spin = CABasicAnimation(keyPath: "transform.rotation.y")
        spin.fromValue = 0.0
        spin.toValue = Double.pi * 10.0
        spin.duration = 0.95
        spin.timingFunction = CAMediaTimingFunction(name: .easeOut)
        self.coinDiscView.layer.add(spin, forKey: "fg.coinSpin")

        UIView.animateKeyframes(withDuration: 0.95, delay: 0.0) {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.45) {
                self.coinDiscView.transform = CGAffineTransform(scaleX: 1.24, y: 1.24).translatedBy(x: 0.0, y: -22.0)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
                self.coinDiscView.transform = .identity
            }
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimating = false
            self.coinIconLabel.text = landedTails ? "🪙" : "🦅"
            let sideName = landedTails ? "🪙 Решка" : "🦅 Орёл"
            let payout = won ? bet * 2 : 0
            self.balance += payout
            if won {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.winBannerLabel.textColor = self.emeraldColor
                self.winBannerLabel.text = "✅ Выпал \(sideName)! +\(payout) 🪙"
                self.pulseBanner()
            } else {
                self.winBannerLabel.textColor = .systemRed
                self.winBannerLabel.text = "❌ Выпал \(sideName) (-\(bet) 🪙)"
            }
            self.lastSummaryForChat = "👑 BetKing · 🪙 Монетка\nВыпал \(sideName) · Выплата: \(payout) 🪙 · Баланс: \(self.balance) 🪙"
            self.refreshControlsUI()
        }
    }

    // MARK: - Helpers

    private func pulseBanner() {
        self.winBannerLabel.transform = CGAffineTransform(scaleX: 1.14, y: 1.14)
        UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.7) {
            self.winBannerLabel.transform = .identity
        }
    }

    private static func pickWeighted(_ items: [(String, Int)]) -> String {
        let total = items.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return items.first?.0 ?? "💎" }
        var roll = Int.random(in: 0 ..< total)
        for (sym, w) in items {
            if roll < w { return sym }
            roll -= w
        }
        return items[0].0
    }

    private static func pickZeusOrb() -> Int {
        let r = Int.random(in: 0 ..< 1000)
        if r < 480 { return 2 }
        if r < 720 { return 3 }
        if r < 860 { return 5 }
        if r < 940 { return 10 }
        if r < 980 { return 25 }
        if r < 995 { return 50 }
        return 100
    }
}

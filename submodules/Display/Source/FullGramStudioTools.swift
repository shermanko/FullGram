import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation
import PDFKit
@preconcurrency import WebKit
import QuickLook
import Compression
import UniformTypeIdentifiers

private struct FullGramUncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

private func fullGramEnsureExtensionURL(for sourceURL: URL, preferredFileName: String, fallbackExtension: String) -> URL {
    let extFromName = (preferredFileName as NSString).pathExtension.lowercased()
    let targetExt = !extFromName.isEmpty ? extFromName : fallbackExtension.lowercased()
    if sourceURL.pathExtension.lowercased() == targetExt || targetExt.isEmpty {
        return sourceURL
    }
    let stem = ((preferredFileName as NSString).deletingPathExtension)
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
    let cleanStem = stem.isEmpty ? "file" : stem
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("fg_preview_\(cleanStem)_\(sourceURL.lastPathComponent).\(targetExt)")
    if !FileManager.default.fileExists(atPath: tmpURL.path) {
        if (try? FileManager.default.linkItem(at: sourceURL, to: tmpURL)) == nil {
            try? FileManager.default.copyItem(at: sourceURL, to: tmpURL)
        }
    }
    return FileManager.default.fileExists(atPath: tmpURL.path) ? tmpURL : sourceURL
}

private func fullGramDefaultNavigationBarPresentationData() -> NavigationBarPresentationData {
    return NavigationBarPresentationData(
        theme: NavigationBarTheme(
            overallDarkAppearance: UITraitCollection.current.userInterfaceStyle == .dark,
            buttonColor: UIColor.systemBlue,
            disabledButtonColor: UIColor.systemGray,
            primaryTextColor: UIColor.label,
            badgeBackgroundColor: UIColor.systemRed,
            badgeTextColor: UIColor.white,
            accentButtonColor: UIColor.systemBlue,
            accentDisabledButtonColor: UIColor.systemGray,
            accentForegroundColor: UIColor.white
        ),
        strings: NavigationBarStrings(back: "Назад", close: "Закрыть", more: "Ещё")
    )
}

// MARK: - 1. Документы (DOCX, XLSX, PDF) — Встроенный просмотрщик с поиском и извлечением текста

public final class FullGramDocumentViewerController: ViewController, UISearchBarDelegate, WKNavigationDelegate, QLPreviewControllerDataSource {
    public static func isSupportedDocument(fileName: String?, mimeType: String) -> Bool {
        let ext = ((fileName ?? "") as NSString).pathExtension.lowercased()
        if ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "csv", "rtf"].contains(ext) {
            return true
        }
        let lowerMime = mimeType.lowercased()
        return lowerMime == "application/pdf"
            || lowerMime.contains("wordprocessingml")
            || lowerMime.contains("spreadsheetml")
            || lowerMime.contains("presentationml")
            || lowerMime == "application/msword"
            || lowerMime == "application/vnd.ms-excel"
            || lowerMime == "text/csv"
            || lowerMime == "application/rtf"
    }

    private let fileURL: URL
    private let fileName: String
    private let canShare: Bool
    private let fileExtension: String

    private let searchBar = UISearchBar()
    private let segmentedControl = UISegmentedControl(items: ["Просмотр", "Текст"])
    private let statusLabel = UILabel()
    private let pdfView = PDFView()
    private let thumbnailView = PDFThumbnailView()
    private lazy var webView: WKWebView = {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        return wv
    }()
    private let textView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var topConstraint: NSLayoutConstraint?

    private var extractedText: String = ""
    private var pdfSearchSelections: [PDFSelection] = []
    private var pdfSearchIndex: Int = 0
    private var isPDF: Bool { return self.fileExtension == "pdf" }
    private var supportsTextExtraction: Bool {
        return ["pdf", "docx", "xlsx", "csv", "txt"].contains(self.fileExtension)
    }

    public init(fileURL: URL, fileName: String, canShare: Bool = true) {
        let resolvedName = fileName.isEmpty ? fileURL.lastPathComponent : fileName
        let resolvedExt = (resolvedName as NSString).pathExtension.lowercased()
        self.fileName = resolvedName
        self.fileURL = fullGramEnsureExtensionURL(for: fileURL, preferredFileName: resolvedName, fallbackExtension: resolvedExt)
        self.canShare = canShare
        self.fileExtension = resolvedExt
        super.init(navigationBarPresentationData: fullGramDefaultNavigationBarPresentationData())
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = self.fileName
        if self.canShare {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .action,
                target: self,
                action: #selector(self.shareTapped)
            )
        }
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .systemBackground
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.loadContent()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.topConstraint?.constant = topInset + 4.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }

    private func setupUI() {
        let root = self.displayNode.view

        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.placeholder = "Поиск по документу…"
        self.searchBar.delegate = self

        self.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.segmentedControl.selectedSegmentIndex = 0
        self.segmentedControl.isHidden = !self.supportsTextExtraction
        self.segmentedControl.addTarget(self, action: #selector(self.modeChanged), for: .valueChanged)

        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.statusLabel.textColor = .secondaryLabel
        self.statusLabel.textAlignment = .center

        self.pdfView.translatesAutoresizingMaskIntoConstraints = false
        self.pdfView.autoScales = true
        self.pdfView.displayMode = .singlePageContinuous
        self.pdfView.displayDirection = .vertical
        self.pdfView.isHidden = !self.isPDF

        self.thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        self.thumbnailView.layoutMode = .horizontal
        self.thumbnailView.thumbnailSize = CGSize(width: 28.0, height: 36.0)
        self.thumbnailView.pdfView = self.pdfView
        self.thumbnailView.isHidden = !self.isPDF

        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView.isHidden = self.isPDF

        self.textView.translatesAutoresizingMaskIntoConstraints = false
        self.textView.isEditable = false
        self.textView.font = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        self.textView.textContainerInset = UIEdgeInsets(top: 12.0, left: 12.0, bottom: 20.0, right: 12.0)
        self.textView.isHidden = true

        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        [self.pdfView, self.thumbnailView, self.webView, self.textView, self.statusLabel, self.segmentedControl, self.searchBar, self.spinner].forEach(insertBelowNav)

        let topC = self.searchBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 96.0)
        self.topConstraint = topC

        let modeHeight = self.supportsTextExtraction ? 32.0 : 0.0
        let thumbHeight: CGFloat = self.isPDF ? 48.0 : 0.0

        NSLayoutConstraint.activate([
            topC,
            self.searchBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6.0),
            self.searchBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6.0),
            self.searchBar.heightAnchor.constraint(equalToConstant: 44.0),

            self.segmentedControl.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 2.0),
            self.segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14.0),
            self.segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14.0),
            self.segmentedControl.heightAnchor.constraint(equalToConstant: modeHeight),

            self.statusLabel.topAnchor.constraint(equalTo: self.segmentedControl.bottomAnchor, constant: 4.0),
            self.statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),

            self.thumbnailView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.thumbnailView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.thumbnailView.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor),
            self.thumbnailView.heightAnchor.constraint(equalToConstant: thumbHeight),

            self.pdfView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 4.0),
            self.pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.pdfView.bottomAnchor.constraint(equalTo: self.thumbnailView.topAnchor),

            self.webView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 4.0),
            self.webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            self.textView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 4.0),
            self.textView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.textView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.textView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            self.spinner.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(self.pdfPageChanged), name: .PDFViewPageChanged, object: self.pdfView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func loadContent() {
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: self.fileURL.path)[.size] as? Int64) ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)

        if self.isPDF {
            if let doc = PDFDocument(url: self.fileURL) {
                self.pdfView.document = doc
                self.extractedText = (0 ..< min(doc.pageCount, 80)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n---\n\n")
                self.textView.text = self.extractedText
                self.statusLabel.text = "PDF • Стр. 1 / \(max(1, doc.pageCount)) • \(sizeText)"
            } else {
                self.statusLabel.text = "Не удалось открыть PDF (\(sizeText))"
            }
            return
        }

        self.spinner.startAnimating()
        self.statusLabel.text = "\(self.fileExtension.uppercased()) • \(sizeText)"
        self.webView.loadFileURL(self.fileURL, allowingReadAccessTo: self.fileURL)

        let ext = self.fileExtension
        let url = self.fileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let parsed = FullGramOfficeTextExtractor.extractText(from: url, extension: ext)
            DispatchQueue.main.async {
                guard let self else { return }
                self.extractedText = parsed
                self.textView.text = parsed.isEmpty ? "Текст документа не обнаружен — используйте режим «Просмотр»." : parsed
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.spinner.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.spinner.stopAnimating()
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.absoluteString == "about:blank" || (url.isFileURL && url.standardizedFileURL == self.fileURL.standardizedFileURL) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    @objc private func pdfPageChanged() {
        guard let doc = self.pdfView.document, let current = self.pdfView.currentPage else { return }
        let idx = doc.index(for: current) + 1
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: self.fileURL.path)[.size] as? Int64) ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        self.statusLabel.text = "PDF • Стр. \(idx) / \(doc.pageCount) • \(sizeText)"
    }

    @objc private func modeChanged() {
        let showText = self.segmentedControl.selectedSegmentIndex == 1
        self.textView.isHidden = !showText
        self.pdfView.isHidden = showText || !self.isPDF
        self.thumbnailView.isHidden = showText || !self.isPDF
        self.webView.isHidden = showText || self.isPDF
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.isPDF, let doc = self.pdfView.document {
            if query.isEmpty {
                self.pdfView.highlightedSelections = nil
                self.pdfSearchSelections = []
                return
            }
            self.pdfSearchSelections = doc.findString(query, withOptions: [.caseInsensitive])
            self.pdfSearchIndex = 0
            self.pdfView.highlightedSelections = self.pdfSearchSelections
            if let first = self.pdfSearchSelections.first {
                self.pdfView.go(to: first)
            }
        } else {
            self.highlightTextQuery(query)
        }
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if self.isPDF, !self.pdfSearchSelections.isEmpty {
            self.pdfSearchIndex = (self.pdfSearchIndex + 1) % self.pdfSearchSelections.count
            self.pdfView.go(to: self.pdfSearchSelections[self.pdfSearchIndex])
        }
    }

    private func highlightTextQuery(_ query: String) {
        let base = NSMutableAttributedString(
            string: self.extractedText,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: UIColor.label
            ]
        )
        if !query.isEmpty {
            let nsText = self.extractedText as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)
            var firstHit: NSRange?
            while searchRange.location < nsText.length {
                let found = nsText.range(of: query, options: [.caseInsensitive], range: searchRange)
                if found.location == NSNotFound { break }
                if firstHit == nil { firstHit = found }
                base.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.55), range: found)
                let nextLoc = found.location + max(1, found.length)
                searchRange = NSRange(location: nextLoc, length: nsText.length - nextLoc)
            }
            self.textView.attributedText = base
            if let firstHit {
                self.segmentedControl.selectedSegmentIndex = 1
                self.modeChanged()
                self.textView.scrollRangeToVisible(firstHit)
            }
        } else {
            self.textView.attributedText = base
        }
    }

    @objc private func shareTapped() {
        let ql = QLPreviewController()
        ql.dataSource = self
        self.present(ql, animated: true)
    }

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return self.fileURL as NSURL
    }
}

private enum FullGramOfficeTextExtractor {
    private static let maxTextBytes = 8 * 1024 * 1024

    static func extractText(from url: URL, extension ext: String) -> String {
        if ext == "csv" || ext == "txt" {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
            defer { try? handle.close() }
            let limited = (try? handle.read(upToCount: Self.maxTextBytes)) ?? Data()
            return String(data: limited, encoding: .utf8)
                ?? String(data: limited, encoding: .windowsCP1251)
                ?? ""
        }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= 32 * 1024 * 1024, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        let entries = FullGramArchiveParser.parseZipEntries(data: data)
        if ext == "docx" {
            guard let docEntry = entries.first(where: { $0.name == "word/document.xml" }),
                  let xmlData = FullGramArchiveParser.extractZipEntry(docEntry, from: data, maxBytes: Self.maxTextBytes),
                  let xml = String(data: xmlData, encoding: .utf8) else {
                return ""
            }
            return stripXML(xml, rowTags: ["</w:p>", "</w:tr>", "<w:br/>"], cellTags: ["</w:tc>"])
        }
        if ext == "xlsx" {
            var sharedStrings: [String] = []
            if let ssEntry = entries.first(where: { $0.name == "xl/sharedStrings.xml" }),
               let ssData = FullGramArchiveParser.extractZipEntry(ssEntry, from: data, maxBytes: Self.maxTextBytes),
               let ssXML = String(data: ssData, encoding: .utf8) {
                sharedStrings = extractSharedStrings(ssXML)
            }
            let sheetEntries = entries.filter { $0.name.hasPrefix("xl/worksheets/sheet") && $0.name.hasSuffix(".xml") }
                .sorted { $0.name < $1.name }
            var output: [String] = []
            for (idx, sheet) in sheetEntries.prefix(6).enumerated() {
                guard let sData = FullGramArchiveParser.extractZipEntry(sheet, from: data, maxBytes: Self.maxTextBytes),
                      let sXML = String(data: sData, encoding: .utf8) else { continue }
                let rows = parseXLSXSheet(sXML, sharedStrings: sharedStrings)
                if !rows.isEmpty {
                    output.append("=== Лист \(idx + 1) ===\n" + rows.joined(separator: "\n"))
                }
            }
            return output.joined(separator: "\n\n")
        }
        return ""
    }

    private static func stripXML(_ xml: String, rowTags: [String], cellTags: [String]) -> String {
        var text = xml
        for tag in rowTags {
            text = text.replacingOccurrences(of: tag, with: "\n")
        }
        for tag in cellTags {
            text = text.replacingOccurrences(of: tag, with: "\t")
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeXMLEntities(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func extractSharedStrings(_ xml: String) -> [String] {
        var results: [String] = []
        let items = xml.components(separatedBy: "<si>")
        for item in items.dropFirst() {
            let chunk = item.components(separatedBy: "</si>").first ?? item
            let clean = chunk.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            results.append(decodeXMLEntities(clean))
        }
        return results
    }

    private static func parseXLSXSheet(_ xml: String, sharedStrings: [String]) -> [String] {
        var lines: [String] = []
        let rows = xml.components(separatedBy: "<row ")
        for row in rows.dropFirst().prefix(400) {
            let rowBody = row.components(separatedBy: "</row>").first ?? row
            var cells: [String] = []
            let rawCells = rowBody.components(separatedBy: "<c ")
            for cell in rawCells.dropFirst() {
                let cBody = cell.components(separatedBy: "</c>").first ?? cell
                let isShared = cBody.contains("t=\"s\"")
                if let vStart = cBody.range(of: "<v>"), let vEnd = cBody.range(of: "</v>", range: vStart.upperBound ..< cBody.endIndex) {
                    let rawVal = String(cBody[vStart.upperBound ..< vEnd.lowerBound])
                    if isShared, let idx = Int(rawVal), idx >= 0 && idx < sharedStrings.count {
                        cells.append(sharedStrings[idx])
                    } else {
                        cells.append(decodeXMLEntities(rawVal))
                    }
                } else if let isStart = cBody.range(of: "<t"), let gt = cBody.range(of: ">", range: isStart.upperBound ..< cBody.endIndex), let tEnd = cBody.range(of: "</t>", range: gt.upperBound ..< cBody.endIndex) {
                    cells.append(decodeXMLEntities(String(cBody[gt.upperBound ..< tEnd.lowerBound])))
                }
            }
            if !cells.isEmpty {
                lines.append(cells.joined(separator: " | "))
            }
        }
        return lines
    }

    private static func decodeXMLEntities(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

// MARK: - 2. Предпросмотр архивов (ZIP, RAR) с распаковкой выбранных файлов

public struct FullGramArchiveEntry: Sendable {
    public let name: String
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let method: UInt16
    public let localHeaderOffset: UInt64
    public let isDirectory: Bool
    public let isExtractable: Bool
}

public enum FullGramArchiveParser {
    private static let maxExtractBytes = 64 * 1024 * 1024

    public static func parse(url: URL) -> (format: String, entries: [FullGramArchiveEntry]) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ("UNKNOWN", [])
        }
        if data.count >= 8 && data.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) {
            return ("RAR5", parseRAR5(data: data))
        }
        if data.count >= 7 && data.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) {
            return ("RAR4", parseRAR4(data: data))
        }
        let zipEntries = parseZipEntries(data: data)
        if !zipEntries.isEmpty || data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return ("ZIP", zipEntries)
        }
        return (url.pathExtension.uppercased(), [])
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0 && offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0 && offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    public static func parseZipEntries(data: Data) -> [FullGramArchiveEntry] {
        guard data.count >= 22 else { return [] }
        let searchStart = max(0, data.count - 65_557)
        var eocdOffset: Int?
        var i = data.count - 22
        while i >= searchStart {
            if readUInt32LE(data, at: i) == 0x06054B50 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        if let eocd = eocdOffset {
            let cdOffset = Int(readUInt32LE(data, at: eocd + 16))
            let totalEntries = Int(readUInt16LE(data, at: eocd + 10))
            if cdOffset >= 0 && cdOffset < data.count && totalEntries > 0 && totalEntries <= 20_000 {
                var result: [FullGramArchiveEntry] = []
                var cursor = cdOffset
                for _ in 0 ..< totalEntries {
                    guard cursor + 46 <= data.count, readUInt32LE(data, at: cursor) == 0x02014B50 else { break }
                    let method = readUInt16LE(data, at: cursor + 10)
                    let compSize = UInt64(readUInt32LE(data, at: cursor + 20))
                    let uncompSize = UInt64(readUInt32LE(data, at: cursor + 24))
                    let nameLen = Int(readUInt16LE(data, at: cursor + 28))
                    let extraLen = Int(readUInt16LE(data, at: cursor + 30))
                    let commentLen = Int(readUInt16LE(data, at: cursor + 32))
                    let localOffset = UInt64(readUInt32LE(data, at: cursor + 42))
                    let headerEnd = cursor + 46
                    guard headerEnd + nameLen <= data.count else { break }
                    let nameData = data.subdata(in: headerEnd ..< (headerEnd + nameLen))
                    let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "entry"
                    let isDir = name.hasSuffix("/")
                    result.append(FullGramArchiveEntry(
                        name: name,
                        compressedSize: compSize,
                        uncompressedSize: uncompSize,
                        method: method,
                        localHeaderOffset: localOffset,
                        isDirectory: isDir,
                        isExtractable: !isDir && (method == 0 || method == 8)
                    ))
                    cursor = headerEnd + nameLen + extraLen + commentLen
                }
                if !result.isEmpty { return result }
            }
        }
        // Fallback for partial archives (preview without downloading full file): scan Local File Headers (0x04034B50)
        var fallback: [FullGramArchiveEntry] = []
        var offset = 0
        while offset + 30 <= data.count && fallback.count < 5_000 {
            if readUInt32LE(data, at: offset) == 0x04034B50 {
                let method = readUInt16LE(data, at: offset + 8)
                let compSize = UInt64(readUInt32LE(data, at: offset + 18))
                let uncompSize = UInt64(readUInt32LE(data, at: offset + 22))
                let nameLen = Int(readUInt16LE(data, at: offset + 26))
                let extraLen = Int(readUInt16LE(data, at: offset + 28))
                let nameStart = offset + 30
                if nameLen > 0 && nameLen <= 4096 && nameStart + nameLen <= data.count {
                    let nameData = data.subdata(in: nameStart ..< (nameStart + nameLen))
                    let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "entry"
                    let isDir = name.hasSuffix("/")
                    fallback.append(FullGramArchiveEntry(
                        name: name,
                        compressedSize: compSize,
                        uncompressedSize: uncompSize,
                        method: method,
                        localHeaderOffset: UInt64(offset),
                        isDirectory: isDir,
                        isExtractable: !isDir && (method == 0 || method == 8) && (nameStart + nameLen + extraLen + Int(compSize) <= data.count)
                    ))
                    let step = 30 + nameLen + extraLen + Int(compSize)
                    if step > 0 {
                        offset += step
                        continue
                    }
                }
            }
            offset += 1
        }
        return fallback
    }

    public static func extractZipEntry(_ entry: FullGramArchiveEntry, from data: Data, maxBytes: Int = FullGramArchiveParser.maxExtractBytes) -> Data? {
        let effectiveLimit = max(0, min(maxBytes, Self.maxExtractBytes))
        guard !entry.isDirectory, effectiveLimit > 0, entry.uncompressedSize <= UInt64(effectiveLimit) else { return nil }
        guard entry.localHeaderOffset <= UInt64(Int.max) else { return nil }
        let off = Int(entry.localHeaderOffset)
        guard off >= 0, off <= data.count - 30, readUInt32LE(data, at: off) == 0x04034B50 else { return nil }
        let gpFlags = readUInt16LE(data, at: off + 6)
        let hasDataDescriptor = (gpFlags & 0x0008) != 0
        let nameLen = Int(readUInt16LE(data, at: off + 26))
        let extraLen = Int(readUInt16LE(data, at: off + 28))
        let (start1, ov1) = off.addingReportingOverflow(30)
        let (start2, ov2) = start1.addingReportingOverflow(nameLen)
        let (dataStart, ov3) = start2.addingReportingOverflow(extraLen)
        guard !ov1, !ov2, !ov3, dataStart >= 0, dataStart <= data.count else { return nil }

        let availBytes: Int
        if entry.compressedSize > 0 {
            guard entry.compressedSize <= UInt64(data.count - dataStart) else { return nil }
            availBytes = Int(entry.compressedSize)
        } else if entry.method == 8 && hasDataDescriptor {
            availBytes = data.count - dataStart
        } else if entry.uncompressedSize == 0 {
            return Data()
        } else {
            return nil
        }

        if entry.method == 0 {
            guard availBytes <= effectiveLimit else { return nil }
            return data.subdata(in: dataStart ..< (dataStart + availBytes))
        }
        guard entry.method == 8 else { return nil }
        if availBytes == 0 {
            return entry.uncompressedSize == 0 ? Data() : nil
        }

        let chunkSize = 64 * 1024
        var scratch = [UInt8](repeating: 0, count: chunkSize)
        var out = Data()
        let ok: Bool = data.withUnsafeBytes { rawData in
            guard let base = rawData.bindMemory(to: UInt8.self).baseAddress else { return false }
            let srcBase = UnsafePointer<UInt8>(base.advanced(by: dataStart))
            return scratch.withUnsafeMutableBytes { rawDst in
                guard let dstBase = rawDst.bindMemory(to: UInt8.self).baseAddress else { return false }
                var stream = compression_stream(
                    dst_ptr: dstBase,
                    dst_size: chunkSize,
                    src_ptr: srcBase,
                    src_size: availBytes,
                    state: nil
                )
                guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                    return false
                }
                defer { compression_stream_destroy(&stream) }
                stream.src_ptr = srcBase
                stream.src_size = availBytes
                stream.dst_ptr = dstBase
                stream.dst_size = chunkSize
                while true {
                    let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    let produced = chunkSize - stream.dst_size
                    if produced > 0 {
                        if out.count + produced > effectiveLimit {
                            return false
                        }
                        out.append(dstBase, count: produced)
                        stream.dst_ptr = dstBase
                        stream.dst_size = chunkSize
                    }
                    if status == COMPRESSION_STATUS_END {
                        return true
                    }
                    if status == COMPRESSION_STATUS_ERROR {
                        return false
                    }
                    if produced == 0 && stream.src_size == 0 {
                        return false
                    }
                }
            }
        }
        return ok ? out : nil
    }

    private static func readVInt(_ data: Data, cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.count && shift < 63 {
            let b = data[cursor]
            cursor += 1
            value |= UInt64(b & 0x7F) << shift
            if (b & 0x80) == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    private static func parseRAR5(data: Data) -> [FullGramArchiveEntry] {
        var entries: [FullGramArchiveEntry] = []
        var cursor = 8
        while cursor + 6 <= data.count && entries.count < 5_000 {
            cursor += 4 // CRC32
            guard let headerSize = readVInt(data, cursor: &cursor), headerSize > 0 else { break }
            let headerStart = cursor
            let remaining = data.count - headerStart
            guard headerSize <= UInt64(remaining) else { break }
            let headerEnd = headerStart + Int(headerSize)
            guard let blockType = readVInt(data, cursor: &cursor),
                  let blockFlags = readVInt(data, cursor: &cursor) else { break }
            var bodyPos = cursor
            if (blockFlags & 0x01) != 0 {
                // HFL_EXTRA: extraAreaSize precedes HFL_DATA in RAR5 headers
                guard readVInt(data, cursor: &bodyPos) != nil, bodyPos <= headerEnd else { break }
            }
            var dataSize: UInt64 = 0
            if (blockFlags & 0x02) != 0 {
                guard let ds = readVInt(data, cursor: &bodyPos), bodyPos <= headerEnd else { break }
                dataSize = ds
            }
            if blockType == 2 {
                // File header (blockType 2)
                var pos = bodyPos
                let fileFlags = readVInt(data, cursor: &pos) ?? 0
                let unpSize = readVInt(data, cursor: &pos) ?? 0
                _ = readVInt(data, cursor: &pos) // attrs
                if (fileFlags & 0x02) != 0 && pos + 4 <= headerEnd { pos += 4 } // mtime
                if (fileFlags & 0x04) != 0 && pos + 4 <= headerEnd { pos += 4 } // crc32
                _ = readVInt(data, cursor: &pos) // compression info
                _ = readVInt(data, cursor: &pos) // host os
                if let nameLen = readVInt(data, cursor: &pos), nameLen > 0 && nameLen <= 4096 && headerEnd - pos >= Int(nameLen) {
                    let nameData = data.subdata(in: pos ..< (pos + Int(nameLen)))
                    let name = String(data: nameData, encoding: .utf8) ?? "file"
                    let isDir = (fileFlags & 0x01) != 0 || name.hasSuffix("/")
                    entries.append(FullGramArchiveEntry(
                        name: name,
                        compressedSize: dataSize,
                        uncompressedSize: unpSize,
                        method: 0,
                        localHeaderOffset: UInt64(headerEnd),
                        isDirectory: isDir,
                        isExtractable: false
                    ))
                }
            }
            let (next, overflow) = UInt64(headerEnd).addingReportingOverflow(dataSize)
            if overflow || next <= UInt64(headerStart) || next > UInt64(data.count) { break }
            cursor = Int(next)
            if blockType == 5 { break }
        }
        return entries
    }

    private static func parseRAR4(data: Data) -> [FullGramArchiveEntry] {
        var entries: [FullGramArchiveEntry] = []
        var cursor = 7
        while cursor + 7 <= data.count && entries.count < 5_000 {
            let headType = data[cursor + 2]
            let headFlags = readUInt16LE(data, at: cursor + 3)
            let headSize = Int(readUInt16LE(data, at: cursor + 5))
            guard headSize >= 7 && cursor + headSize <= data.count else { break }
            var addSize: UInt64 = 0
            if (headFlags & 0x8000) != 0 && cursor + 11 <= data.count {
                addSize = UInt64(readUInt32LE(data, at: cursor + 7))
            }
            let isLarge = (headFlags & 0x0100) != 0
            let fixedHeaderLen = isLarge ? 40 : 32
            if headType == 0x74 && headSize >= fixedHeaderLen && cursor + fixedHeaderLen <= data.count {
                let packLow = UInt64(readUInt32LE(data, at: cursor + 7))
                let unpLow = UInt64(readUInt32LE(data, at: cursor + 11))
                let packHigh = isLarge ? UInt64(readUInt32LE(data, at: cursor + 32)) : 0
                let unpHigh = isLarge ? UInt64(readUInt32LE(data, at: cursor + 36)) : 0
                let packed = (packHigh << 32) | packLow
                let unp = (unpHigh << 32) | unpLow
                let nameSize = Int(readUInt16LE(data, at: cursor + 26))
                let nameStart = cursor + fixedHeaderLen
                if nameSize > 0 && nameSize <= 4096 && (cursor + headSize - nameStart) >= nameSize {
                    let nameData = data.subdata(in: nameStart ..< (nameStart + nameSize))
                    let rawName = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "file"
                    let cleanName = rawName.components(separatedBy: "\0").first ?? rawName
                    let isDir = (headFlags & 0x00E0) == 0x00E0 || cleanName.hasSuffix("/")
                    entries.append(FullGramArchiveEntry(
                        name: cleanName,
                        compressedSize: packed,
                        uncompressedSize: unp,
                        method: 0,
                        localHeaderOffset: UInt64(cursor + headSize),
                        isDirectory: isDir,
                        isExtractable: false
                    ))
                }
                addSize = packed
            }
            let (next1, ov1) = UInt64(cursor).addingReportingOverflow(UInt64(headSize))
            let (next, ov2) = next1.addingReportingOverflow(addSize)
            if ov1 || ov2 || next <= UInt64(cursor) || next > UInt64(data.count) { break }
            cursor = Int(next)
            if headType == 0x7B { break }
        }
        return entries
    }
}

public final class FullGramArchivePreviewController: ViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, QLPreviewControllerDataSource {
    public static func isSupportedArchive(fileName: String?, mimeType: String) -> Bool {
        let ext = ((fileName ?? "") as NSString).pathExtension.lowercased()
        if ["zip", "rar", "cbz", "cbr"].contains(ext) {
            return true
        }
        let lowerMime = mimeType.lowercased()
        return lowerMime == "application/zip"
            || lowerMime == "application/x-zip-compressed"
            || lowerMime == "application/x-rar-compressed"
            || lowerMime == "application/vnd.rar"
    }

    private let fileURL: URL
    private let fileName: String
    private var formatLabel: String = "ARCHIVE"
    private var allEntries: [FullGramArchiveEntry] = []
    private var filteredEntries: [FullGramArchiveEntry] = []
    private var extractedPreviewURL: URL?

    private let searchBar = UISearchBar()
    private let summaryLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var topConstraint: NSLayoutConstraint?

    public init(fileURL: URL, fileName: String) {
        let resolvedName = fileName.isEmpty ? fileURL.lastPathComponent : fileName
        self.fileName = resolvedName
        self.fileURL = fullGramEnsureExtensionURL(
            for: fileURL,
            preferredFileName: resolvedName,
            fallbackExtension: (resolvedName as NSString).pathExtension
        )
        super.init(navigationBarPresentationData: fullGramDefaultNavigationBarPresentationData())
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = self.fileName
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(self.shareArchive)
        )
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .systemGroupedBackground
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.parseArchive()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.topConstraint?.constant = topInset + 4.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }

    private func setupUI() {
        let root = self.displayNode.view
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.placeholder = "Поиск файлов в архиве…"
        self.searchBar.delegate = self

        self.summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        self.summaryLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .medium)
        self.summaryLabel.textColor = .secondaryLabel
        self.summaryLabel.textAlignment = .center
        self.summaryLabel.numberOfLines = 2

        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ArchiveCell")

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        [self.tableView, self.summaryLabel, self.searchBar].forEach(insertBelowNav)

        let topC = self.searchBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 96.0)
        self.topConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            self.searchBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6.0),
            self.searchBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6.0),
            self.searchBar.heightAnchor.constraint(equalToConstant: 44.0),

            self.summaryLabel.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 2.0),
            self.summaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14.0),
            self.summaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14.0),

            self.tableView.topAnchor.constraint(equalTo: self.summaryLabel.bottomAnchor, constant: 6.0),
            self.tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func parseArchive() {
        let url = self.fileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let parsed = FullGramArchiveParser.parse(url: url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.formatLabel = parsed.format
                self.allEntries = parsed.entries
                self.filteredEntries = parsed.entries
                let fileCount = parsed.entries.filter { !$0.isDirectory }.count
                let totalUncompressed = parsed.entries.reduce(Int64(0)) { acc, entry in
                    let clamped = Int64(clamping: entry.uncompressedSize)
                    let (sum, overflow) = acc.addingReportingOverflow(clamped)
                    return overflow ? Int64.max : sum
                }
                let sizeStr = ByteCountFormatter.string(fromByteCount: totalUncompressed, countStyle: .file)
                let dangerousExts = ["exe", "bat", "cmd", "scr", "msi", "apk", "vbs", "ps1"]
                let hasDangerous = parsed.entries.contains { entry in
                    dangerousExts.contains((entry.name as NSString).pathExtension.lowercased())
                }
                let warn = hasDangerous ? " • ⚠️ Обнаружены исполняемые файлы" : ""
                self.summaryLabel.text = "\(parsed.format) • Файлов: \(fileCount) • Размер: \(sizeStr)\(warn)"
                self.tableView.reloadData()
            }
        }
    }

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.filteredEntries = q.isEmpty
            ? self.allEntries
            : self.allEntries.filter { $0.name.lowercased().contains(q) }
        self.tableView.reloadData()
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(1, self.filteredEntries.count)
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ArchiveCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if self.filteredEntries.isEmpty {
            config.text = "Файлы в архиве не найдены"
            config.secondaryText = "Неподдерживаемый формат или пустой архив (\(self.formatLabel))"
            config.image = UIImage(systemName: "archivebox")
            cell.accessoryType = .none
        } else {
            let entry = self.filteredEntries[indexPath.row]
            config.text = entry.name
            if entry.isDirectory {
                config.secondaryText = "Папка"
                config.image = UIImage(systemName: "folder.fill")
                cell.accessoryType = .none
            } else {
                let unp = ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.uncompressedSize), countStyle: .file)
                config.secondaryText = entry.isExtractable ? "\(unp) • Нажмите для открытия" : "\(unp) • Просмотр структуры (\(self.formatLabel))"
                config.image = UIImage(systemName: entry.isExtractable ? "doc.fill" : "lock.doc")
                cell.accessoryType = entry.isExtractable ? .disclosureIndicator : .none
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.filteredEntries.count else { return }
        let entry = self.filteredEntries[indexPath.row]
        guard !entry.isDirectory, entry.isExtractable else { return }
        guard let archiveData = try? Data(contentsOf: self.fileURL, options: .mappedIfSafe),
              let fileData = FullGramArchiveParser.extractZipEntry(entry, from: archiveData) else {
            let alert = UIAlertController(title: "Не удалось извлечь файл", message: entry.name, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }
        var sanitized = (entry.name as NSString).lastPathComponent
        sanitized = sanitized
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
            sanitized = "extracted.bin"
        }
        let safeBaseName = sanitized
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fg_archive_\(UUID().uuidString)_\(safeBaseName)")
        try? fileData.write(to: outURL, options: .atomic)

        if FullGramDocumentViewerController.isSupportedDocument(fileName: safeBaseName, mimeType: "") {
            let viewer = FullGramDocumentViewerController(fileURL: outURL, fileName: safeBaseName, canShare: true)
            (self.navigationController as? NavigationController)?.pushViewController(viewer, animated: true)
        } else if FullGramArchivePreviewController.isSupportedArchive(fileName: safeBaseName, mimeType: "") {
            let nested = FullGramArchivePreviewController(fileURL: outURL, fileName: safeBaseName)
            (self.navigationController as? NavigationController)?.pushViewController(nested, animated: true)
        } else {
            self.extractedPreviewURL = outURL
            let ql = QLPreviewController()
            ql.dataSource = self
            self.present(ql, animated: true)
        }
    }

    @objc private func shareArchive() {
        let activity = UIActivityViewController(activityItems: [self.fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            if let barButtonItem = self.navigationItem.rightBarButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
            }
        }
        self.present(activity, animated: true)
    }

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.extractedPreviewURL != nil ? 1 : 0
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return (self.extractedPreviewURL ?? self.fileURL) as NSURL
    }
}

// MARK: - 3. Нарезка и склейка аудио перед отправкой

public final class FullGramAudioTrimSpliceController: ViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private struct AudioSegment {
        let url: URL
        var title: String
        let duration: TimeInterval
        var trimStart: TimeInterval
        var trimEnd: TimeInterval

        var clippedDuration: TimeInterval {
            return max(0.2, self.trimEnd - self.trimStart)
        }
    }

    private var segments: [AudioSegment] = []
    private var selectedIndex: Int = 0
    private let isVideoCircle: Bool
    private let onComplete: ((URL, TimeInterval) -> Void)?
    private let onSendOriginal: (() -> Void)?

    private let summaryLabel = UILabel()
    private let segmentTitleLabel = UILabel()
    private let startLabel = UILabel()
    private let endLabel = UILabel()
    private let startSlider = UISlider()
    private let endSlider = UISlider()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let playButton = UIButton(type: .system)
    private let splitButton = UIButton(type: .system)
    private let addClipButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private var topConstraint: NSLayoutConstraint?
    private nonisolated(unsafe) var player: AVAudioPlayer?
    private nonisolated(unsafe) var createdTempURLs: [URL] = []
    private var isExporting = false

    public init(
        initialURL: URL?,
        title: String = "Аудио",
        isVideoCircle: Bool = false,
        onComplete: ((URL, TimeInterval) -> Void)? = nil,
        onSendOriginal: (() -> Void)? = nil
    ) {
        self.isVideoCircle = isVideoCircle
        self.onComplete = onComplete
        self.onSendOriginal = onSendOriginal
        super.init(navigationBarPresentationData: fullGramDefaultNavigationBarPresentationData())
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = isVideoCircle ? "Нарезка и склейка кружка" : "Нарезка и склейка аудио"
        if let initialURL {
            let safeURL = fullGramEnsureExtensionURL(for: initialURL, preferredFileName: title, fallbackExtension: isVideoCircle ? "mp4" : "m4a")
            if safeURL != initialURL {
                self.createdTempURLs.append(safeURL)
            }
            let asset = AVURLAsset(url: safeURL)
            let rawDur = CMTimeGetSeconds(asset.duration)
            let dur = rawDur.isFinite ? max(0.5, rawDur) : 0.5
            self.segments = [AudioSegment(url: safeURL, title: title, duration: dur, trimStart: 0.0, trimEnd: dur)]
        }
        if onSendOriginal != nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Без правки",
                style: .plain,
                target: self,
                action: #selector(self.sendOriginalTapped)
            )
        }
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.player?.stop()
        self.player = nil
        for url in self.createdTempURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .systemGroupedBackground
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.refreshSelectionUI()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.topConstraint?.constant = topInset + 8.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }

    private func setupUI() {
        let root = self.displayNode.view

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14.0

        self.summaryLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.summaryLabel.textColor = .secondaryLabel
        self.summaryLabel.textAlignment = .center

        self.segmentTitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .bold)
        self.segmentTitleLabel.textColor = .label
        self.segmentTitleLabel.textAlignment = .center

        self.startLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        self.endLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)

        self.startSlider.addTarget(self, action: #selector(self.sliderChanged), for: .valueChanged)
        self.endSlider.addTarget(self, action: #selector(self.sliderChanged), for: .valueChanged)

        var playCfg = UIButton.Configuration.tinted()
        playCfg.title = "▶️ Слушать"
        playCfg.cornerStyle = .capsule
        self.playButton.configuration = playCfg
        self.playButton.addTarget(self, action: #selector(self.playPreviewTapped), for: .touchUpInside)

        var splitCfg = UIButton.Configuration.tinted()
        splitCfg.title = "✂️ Разрезать"
        splitCfg.cornerStyle = .capsule
        self.splitButton.configuration = splitCfg
        self.splitButton.addTarget(self, action: #selector(self.splitTapped), for: .touchUpInside)

        var addCfg = UIButton.Configuration.tinted()
        addCfg.title = "+ Склеить файл"
        addCfg.cornerStyle = .capsule
        self.addClipButton.configuration = addCfg
        self.addClipButton.addTarget(self, action: #selector(self.addClipTapped), for: .touchUpInside)

        var exportCfg = UIButton.Configuration.filled()
        exportCfg.title = self.onComplete != nil ? "Готово и отправить" : "Склеить и сохранить"
        exportCfg.cornerStyle = .capsule
        self.exportButton.configuration = exportCfg
        self.exportButton.addTarget(self, action: #selector(self.exportTapped), for: .touchUpInside)

        let btnRow = UIStackView(arrangedSubviews: [self.playButton, self.splitButton, self.addClipButton])
        btnRow.axis = .horizontal
        btnRow.spacing = 8.0
        btnRow.distribution = .fillEqually

        let cardStack = UIStackView(arrangedSubviews: [
            self.summaryLabel,
            self.segmentTitleLabel,
            self.startLabel,
            self.startSlider,
            self.endLabel,
            self.endSlider,
            btnRow,
            self.exportButton
        ])
        cardStack.axis = .vertical
        cardStack.spacing = 8.0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AudioSegCell")

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        insertBelowNav(self.tableView)
        insertBelowNav(card)

        let topC = card.topAnchor.constraint(equalTo: root.topAnchor, constant: 100.0)
        self.topConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14.0),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14.0),

            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12.0),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12.0),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12.0),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12.0),

            self.tableView.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8.0),
            self.tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private static func fmt(_ seconds: TimeInterval) -> String {
        let safe = seconds.isFinite ? max(0.0, min(seconds, 86_400.0)) : 0.0
        let total = Int(safe.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func refreshSelectionUI() {
        let totalDur = self.segments.reduce(0.0) { $0 + $1.clippedDuration }
        self.summaryLabel.text = "Фрагментов: \(self.segments.count) • Итоговая длительность: \(Self.fmt(totalDur))"
        let hasValid = !self.segments.isEmpty && self.selectedIndex >= 0 && self.selectedIndex < self.segments.count
        self.startSlider.isEnabled = hasValid
        self.endSlider.isEnabled = hasValid
        self.playButton.isEnabled = hasValid
        self.splitButton.isEnabled = hasValid
        self.exportButton.isEnabled = !self.segments.isEmpty && !self.isExporting

        if hasValid {
            let seg = self.segments[self.selectedIndex]
            self.segmentTitleLabel.text = "\(self.selectedIndex + 1). \(seg.title)"
            self.startSlider.minimumValue = 0.0
            self.startSlider.maximumValue = Float(max(0.5, seg.duration))
            self.startSlider.value = Float(seg.trimStart)
            self.endSlider.minimumValue = 0.0
            self.endSlider.maximumValue = Float(max(0.5, seg.duration))
            self.endSlider.value = Float(seg.trimEnd)
            self.startLabel.text = "Начало обрезки: \(Self.fmt(seg.trimStart)) / \(Self.fmt(seg.duration))"
            self.endLabel.text = "Конец обрезки: \(Self.fmt(seg.trimEnd)) (останется \(Self.fmt(seg.clippedDuration)))"
        } else {
            self.segmentTitleLabel.text = "Добавьте аудиофайл кнопкой «+ Склеить файл»"
            self.startLabel.text = "Начало обрезки: 00:00"
            self.endLabel.text = "Конец обрезки: 00:00"
        }
        self.tableView.reloadData()
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        guard self.selectedIndex >= 0 && self.selectedIndex < self.segments.count else { return }
        var seg = self.segments[self.selectedIndex]
        if sender === self.startSlider {
            let minSpan = min(0.3, seg.duration * 0.5)
            let clamped = min(max(0.0, TimeInterval(sender.value)), max(0.0, seg.trimEnd - minSpan))
            seg.trimStart = clamped
            sender.value = Float(clamped)
        } else {
            let minSpan = min(0.3, seg.duration * 0.5)
            let clamped = max(min(seg.duration, TimeInterval(sender.value)), min(seg.duration, seg.trimStart + minSpan))
            seg.trimEnd = clamped
            sender.value = Float(clamped)
        }
        self.segments[self.selectedIndex] = seg
        self.refreshSelectionUI()
    }

    @objc private func playPreviewTapped() {
        if let p = self.player, p.isPlaying {
            p.stop()
            var cfg = self.playButton.configuration ?? UIButton.Configuration.tinted()
            cfg.title = "▶️ Слушать"
            self.playButton.configuration = cfg
            return
        }
        guard self.selectedIndex < self.segments.count else { return }
        let seg = self.segments[self.selectedIndex]
        if let p = try? AVAudioPlayer(contentsOf: seg.url) {
            p.currentTime = seg.trimStart
            p.play()
            self.player = p
            var cfg = self.playButton.configuration ?? UIButton.Configuration.tinted()
            cfg.title = "⏹ Стоп"
            self.playButton.configuration = cfg
        }
    }

    @objc private func splitTapped() {
        guard self.selectedIndex < self.segments.count else { return }
        let seg = self.segments[self.selectedIndex]
        let span = seg.clippedDuration
        guard span >= 1.2 else { return }
        let mid = seg.trimStart + span * 0.5
        let first = AudioSegment(url: seg.url, title: "\(seg.title) (ч.1)", duration: seg.duration, trimStart: seg.trimStart, trimEnd: mid)
        let second = AudioSegment(url: seg.url, title: "\(seg.title) (ч.2)", duration: seg.duration, trimStart: mid, trimEnd: seg.trimEnd)
        self.segments.remove(at: self.selectedIndex)
        self.segments.insert(contentsOf: [first, second], at: self.selectedIndex)
        self.refreshSelectionUI()
    }

    @objc private func addClipTapped() {
        let types: [UTType] = self.isVideoCircle ? [.movie, .video, .mpeg4Movie] : [.audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        self.present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            self.createdTempURLs.append(url)
            let asset = AVURLAsset(url: url)
            let rawDur = CMTimeGetSeconds(asset.duration)
            let dur = rawDur.isFinite ? max(0.5, rawDur) : 0.5
            self.segments.append(AudioSegment(url: url, title: url.lastPathComponent, duration: dur, trimStart: 0.0, trimEnd: dur))
        }
        if !self.segments.isEmpty && self.selectedIndex >= self.segments.count {
            self.selectedIndex = 0
        }
        self.refreshSelectionUI()
    }

    @objc private func sendOriginalTapped() {
        self.player?.stop()
        self.dismiss()
        self.onSendOriginal?()
    }

    @objc private func exportTapped() {
        guard !self.isExporting, !self.segments.isEmpty else { return }
        self.player?.stop()
        self.isExporting = true
        self.exportButton.isEnabled = false
        var cfg = self.exportButton.configuration ?? UIButton.Configuration.filled()
        cfg.title = "Обработка…"
        self.exportButton.configuration = cfg

        let composition = AVMutableComposition()
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compVideo = self.isVideoCircle ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        if !self.isVideoCircle && compAudio == nil {
            self.isExporting = false
            self.refreshSelectionUI()
            return
        }
        var cursor = CMTime.zero
        var totalDuration: TimeInterval = 0.0
        var appliedTransform = false
        for seg in self.segments {
            let asset = AVURLAsset(url: seg.url)
            let start = CMTime(seconds: seg.trimStart, preferredTimescale: 600)
            let dur = CMTime(seconds: seg.clippedDuration, preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: dur)
            if self.isVideoCircle {
                guard let vTrack = asset.tracks(withMediaType: .video).first, let compVideo else { continue }
                do {
                    try compVideo.insertTimeRange(range, of: vTrack, at: cursor)
                    if !appliedTransform {
                        compVideo.preferredTransform = vTrack.preferredTransform
                        appliedTransform = true
                    }
                    if let aTrack = asset.tracks(withMediaType: .audio).first, let compAudio {
                        try? compAudio.insertTimeRange(range, of: aTrack, at: cursor)
                    }
                    cursor = CMTimeAdd(cursor, dur)
                    totalDuration += seg.clippedDuration
                } catch {
                    continue
                }
            } else {
                guard let track = asset.tracks(withMediaType: .audio).first, let compAudio else { continue }
                do {
                    try compAudio.insertTimeRange(range, of: track, at: cursor)
                    cursor = CMTimeAdd(cursor, dur)
                    totalDuration += seg.clippedDuration
                } catch {
                    continue
                }
            }
        }
        let finalDuration = totalDuration
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            self.isVideoCircle ? "fg_circle_\(UUID().uuidString).mp4" : "fg_audio_\(UUID().uuidString).m4a"
        )
        try? FileManager.default.removeItem(at: outURL)
        let preset = self.isVideoCircle ? AVAssetExportPresetMediumQuality : AVAssetExportPresetAppleM4A
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            self.isExporting = false
            self.refreshSelectionUI()
            return
        }
        exporter.outputURL = outURL
        exporter.outputFileType = self.isVideoCircle ? .mp4 : .m4a
        let exporterBox = FullGramUncheckedSendableBox(value: exporter)
        exporter.exportAsynchronously { [weak self] in
            let success = exporterBox.value.status == .completed
            let errorMessage = exporterBox.value.error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false
                if success {
                    if let onComplete = self.onComplete {
                        self.dismiss()
                        onComplete(outURL, finalDuration)
                    } else {
                        let activity = UIActivityViewController(activityItems: [outURL], applicationActivities: nil)
                        if let popover = activity.popoverPresentationController {
                            popover.sourceView = self.exportButton
                            popover.sourceRect = self.exportButton.bounds
                        }
                        self.present(activity, animated: true)
                        var resetCfg = self.exportButton.configuration ?? UIButton.Configuration.filled()
                        resetCfg.title = "Склеить и сохранить"
                        self.exportButton.configuration = resetCfg
                        self.exportButton.isEnabled = true
                    }
                } else {
                    let alert = UIAlertController(title: "Ошибка обработки аудио", message: errorMessage, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    self.refreshSelectionUI()
                }
            }
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.segments.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AudioSegCell", for: indexPath)
        let seg = self.segments[indexPath.row]
        var cfg = cell.defaultContentConfiguration()
        cfg.text = "\(indexPath.row + 1). \(seg.title)"
        cfg.secondaryText = "\(Self.fmt(seg.trimStart)) → \(Self.fmt(seg.trimEnd)) (длина \(Self.fmt(seg.clippedDuration)))"
        cell.contentConfiguration = cfg
        cell.accessoryType = indexPath.row == self.selectedIndex ? .checkmark : .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.selectedIndex = indexPath.row
        self.refreshSelectionUI()
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && self.segments.count > 1 {
            self.segments.remove(at: indexPath.row)
            self.selectedIndex = max(0, min(self.selectedIndex, self.segments.count - 1))
            self.refreshSelectionUI()
        }
    }
}

// MARK: - 4. Выбор кадра-обложки для видеокружка

public final class FullGramVideoCircleCoverPickerController: ViewController {
    private let asset: AVAsset
    private let duration: Double
    private var selectedImage: UIImage
    private var selectedTimestamp: Double = 0.0
    private let onSelectCover: (Double, UIImage) -> Void

    private let previewImageView = UIImageView()
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let stripsStack = UIStackView()
    private let confirmButton = UIButton(type: .system)
    private var frameThumbnails: [UIImage] = []

    public init(
        asset: AVAsset,
        duration: Double,
        initialThumbnail: UIImage,
        onSelectCover: @escaping (Double, UIImage) -> Void
    ) {
        self.asset = asset
        self.duration = (duration.isFinite && duration > 0.0) ? max(0.5, duration) : 0.5
        self.selectedImage = initialThumbnail
        self.onSelectCover = onSelectCover
        super.init(navigationBarPresentationData: nil)
        self.isOpaqueWhenInOverlay = false
        self.blocksBackgroundWhenInOverlay = true
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.generateFrames()
    }

    private func setupUI() {
        let root = self.displayNode.view
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 22.0

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        titleLabel.text = "Обложка видеокружка"
        titleLabel.textAlignment = .center

        self.previewImageView.translatesAutoresizingMaskIntoConstraints = false
        self.previewImageView.image = self.selectedImage
        self.previewImageView.contentMode = .scaleAspectFill
        self.previewImageView.clipsToBounds = true
        self.previewImageView.layer.cornerRadius = 96.0
        self.previewImageView.layer.borderWidth = 3.0
        self.previewImageView.layer.borderColor = UIColor.systemBlue.cgColor

        self.timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .semibold)
        self.timeLabel.textColor = .secondaryLabel
        self.timeLabel.textAlignment = .center
        self.timeLabel.text = String(format: "Кадр: 0.0 с / %.1f с", self.duration)

        self.stripsStack.axis = .horizontal
        self.stripsStack.distribution = .fillEqually
        self.stripsStack.spacing = 2.0
        self.stripsStack.clipsToBounds = true
        self.stripsStack.layer.cornerRadius = 8.0

        self.slider.minimumValue = 0.0
        self.slider.maximumValue = Float(max(0.1, self.duration))
        self.slider.value = 0.0
        self.slider.addTarget(self, action: #selector(self.sliderChanged), for: .valueChanged)

        var confirmCfg = UIButton.Configuration.filled()
        confirmCfg.title = "Выбрать кадр и отправить"
        confirmCfg.cornerStyle = .capsule
        self.confirmButton.configuration = confirmCfg
        self.confirmButton.addTarget(self, action: #selector(self.confirmTapped), for: .touchUpInside)

        var cancelCfg = UIButton.Configuration.plain()
        cancelCfg.title = "Отмена"
        let cancelButton = UIButton(configuration: cancelCfg, primaryAction: UIAction { [weak self] _ in
            self?.dismiss()
        })

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            self.previewImageView,
            self.timeLabel,
            self.stripsStack,
            self.slider,
            self.confirmButton,
            cancelButton
        ])
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        root.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20.0),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20.0),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18.0),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0),

            self.previewImageView.widthAnchor.constraint(equalToConstant: 192.0),
            self.previewImageView.heightAnchor.constraint(equalToConstant: 192.0),
            self.previewImageView.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            self.stripsStack.heightAnchor.constraint(equalToConstant: 42.0)
        ])
    }

    private func generateFrames() {
        let assetBox = FullGramUncheckedSendableBox(value: self.asset)
        let duration = self.duration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gen = AVAssetImageGenerator(asset: assetBox.value)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 480.0, height: 480.0)
            let count = 10
            var frames: [UIImage] = []
            for i in 0 ..< count {
                let sec = (duration * Double(i)) / Double(max(1, count - 1))
                let time = CMTime(seconds: sec, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                    frames.append(UIImage(cgImage: cg))
                }
            }
            let generatedFrames = frames
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.frameThumbnails = generatedFrames
                    self.stripsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
                    for img in generatedFrames {
                        let iv = UIImageView(image: img)
                        iv.contentMode = .scaleAspectFill
                        iv.clipsToBounds = true
                        self.stripsStack.addArrangedSubview(iv)
                    }
                    if let first = generatedFrames.first {
                        self.selectedImage = first
                        self.previewImageView.image = first
                    }
                }
            }
        }
    }

    @objc private func sliderChanged() {
        let t = Double(self.slider.value)
        self.selectedTimestamp = t
        self.timeLabel.text = String(format: "Кадр: %.1f с / %.1f с", t, self.duration)
        if !self.frameThumbnails.isEmpty {
            let ratio = max(0.0, min(1.0, t / self.duration))
            let idx = min(self.frameThumbnails.count - 1, Int(round(ratio * Double(self.frameThumbnails.count - 1))))
            self.selectedImage = self.frameThumbnails[idx]
            self.previewImageView.image = self.selectedImage
        }
    }

    @objc private func confirmTapped() {
        let assetBox = FullGramUncheckedSendableBox(value: self.asset)
        let ts = self.selectedTimestamp
        let fallback = self.selectedImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gen = AVAssetImageGenerator(asset: assetBox.value)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.maximumSize = CGSize(width: 640.0, height: 640.0)
            let exactImage: UIImage
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: ts, preferredTimescale: 600), actualTime: nil) {
                exactImage = UIImage(cgImage: cg)
            } else {
                exactImage = fallback
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.dismiss()
                self.onSelectCover(ts, exactImage)
            }
        }
    }
}

// MARK: - 5. Пересылка с правкой текста (можно убрать лишний кусок)

public final class FullGramForwardEditController: ViewController, UITableViewDataSource, UITableViewDelegate {
    public struct ForwardItem: Sendable {
        public let messageIdRaw: Int32
        public let authorName: String
        public var text: String
        public var included: Bool

        public init(messageIdRaw: Int32, authorName: String, text: String, included: Bool = true) {
            self.messageIdRaw = messageIdRaw
            self.authorName = authorName
            self.text = text
            self.included = included
        }
    }

    private var items: [ForwardItem]
    private var selectedIndex: Int = 0
    private let onApply: ([ForwardItem]) -> Void

    private let editorLabel = UILabel()
    private let textView = UITextView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var topConstraint: NSLayoutConstraint?

    public init(items: [ForwardItem], onApply: @escaping ([ForwardItem]) -> Void) {
        self.items = items
        self.onApply = onApply
        super.init(navigationBarPresentationData: fullGramDefaultNavigationBarPresentationData())
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = "Правка пересылаемых"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Применить",
            style: .plain,
            target: self,
            action: #selector(self.applyTapped)
        )
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .systemGroupedBackground
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.loadSelectedItem()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.topConstraint?.constant = topInset + 8.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }

    private func setupUI() {
        let root = self.displayNode.view
        self.editorLabel.translatesAutoresizingMaskIntoConstraints = false
        self.editorLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.editorLabel.textColor = .secondaryLabel

        self.textView.translatesAutoresizingMaskIntoConstraints = false
        self.textView.font = UIFont.systemFont(ofSize: 15.0)
        self.textView.backgroundColor = .secondarySystemGroupedBackground
        self.textView.layer.cornerRadius = 12.0
        self.textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)

        let stripLinksBtn = UIButton(type: .system)
        var b1 = UIButton.Configuration.tinted()
        b1.title = "Убрать ссылки"
        b1.cornerStyle = .capsule
        stripLinksBtn.configuration = b1
        stripLinksBtn.addTarget(self, action: #selector(self.stripLinksTapped), for: .touchUpInside)

        let stripMentionsBtn = UIButton(type: .system)
        var b2 = UIButton.Configuration.tinted()
        b2.title = "Убрать @ники"
        b2.cornerStyle = .capsule
        stripMentionsBtn.configuration = b2
        stripMentionsBtn.addTarget(self, action: #selector(self.stripMentionsTapped), for: .touchUpInside)

        let toolsStack = UIStackView(arrangedSubviews: [stripLinksBtn, stripMentionsBtn])
        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        toolsStack.axis = .horizontal
        toolsStack.spacing = 8.0
        toolsStack.distribution = .fillEqually

        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FwdCell")

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        [self.tableView, self.textView, toolsStack, self.editorLabel].forEach(insertBelowNav)

        let topC = self.editorLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 100.0)
        self.topConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            self.editorLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16.0),
            self.editorLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16.0),

            self.textView.topAnchor.constraint(equalTo: self.editorLabel.bottomAnchor, constant: 6.0),
            self.textView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14.0),
            self.textView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14.0),
            self.textView.heightAnchor.constraint(equalToConstant: 160.0),

            toolsStack.topAnchor.constraint(equalTo: self.textView.bottomAnchor, constant: 8.0),
            toolsStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14.0),
            toolsStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14.0),

            self.tableView.topAnchor.constraint(equalTo: toolsStack.bottomAnchor, constant: 8.0),
            self.tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func saveCurrentText() {
        guard self.selectedIndex >= 0 && self.selectedIndex < self.items.count else { return }
        self.items[self.selectedIndex].text = self.textView.text ?? ""
    }

    private func loadSelectedItem() {
        guard self.selectedIndex >= 0 && self.selectedIndex < self.items.count else {
            self.editorLabel.text = "Нет сообщений"
            self.textView.text = ""
            return
        }
        let item = self.items[self.selectedIndex]
        self.editorLabel.text = "От: \(item.authorName.isEmpty ? "Пользователь" : item.authorName) (удалите лишнее перед пересылкой):"
        self.textView.text = item.text
    }

    @objc private func stripLinksTapped() {
        let current = self.textView.text ?? ""
        let updated = current
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "t\\.me/\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.textView.text = updated
        self.saveCurrentText()
        self.tableView.reloadData()
    }

    @objc private func stripMentionsTapped() {
        let current = self.textView.text ?? ""
        let updated = current
            .replacingOccurrences(of: "@[A-Za-z0-9_]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.textView.text = updated
        self.saveCurrentText()
        self.tableView.reloadData()
    }

    @objc private func applyTapped() {
        self.saveCurrentText()
        self.dismiss()
        self.onApply(self.items)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.items.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FwdCell", for: indexPath)
        let item = self.items[indexPath.row]
        var cfg = cell.defaultContentConfiguration()
        cfg.text = item.authorName.isEmpty ? "Сообщение #\(item.messageIdRaw)" : item.authorName
        cfg.secondaryText = item.text.isEmpty ? "(медиа / без текста)" : item.text
        cell.contentConfiguration = cfg
        cell.accessoryType = item.included ? .checkmark : .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.saveCurrentText()
        if indexPath.row == self.selectedIndex && self.items.count > 1 {
            self.items[indexPath.row].included.toggle()
        } else {
            self.selectedIndex = indexPath.row
            self.loadSelectedItem()
        }
        tableView.reloadData()
    }
}

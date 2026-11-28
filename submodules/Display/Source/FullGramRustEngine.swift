import Foundation

private enum RsTokenKind: Equatable {
    case eof
    case ident(String)
    case intLit(Int64)
    case floatLit(Double)
    case string(String)
    case `fn`, pub, `let`, mut, const, `static`, `struct`, `enum`, use, `if`, `else`, `while`, `for`, `in`, loop, match, `return`, `break`, `continue`, `true`, `false`, `as`
    case plus, minus, star, slash, percent
    case assign, plusAssign, minusAssign, starAssign, slashAssign
    case eq, neq, lt, lte, gt, gte
    case andAnd, orOr, bang, amp
    case arrow, fatArrow, colonColon, dotDot, dotDotEq
    case colon, semi, comma, dot, pipe
    case lParen, rParen, lBracket, rBracket, lBrace, rBrace
}

private struct RsToken {
    let kind: RsTokenKind
    let line: Int
}

private struct RsLexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    init(source: String) {
        self.chars = Array(source.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    mutating func tokenize() throws -> [RsToken] {
        var tokens: [RsToken] = []
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c == " " || c == "\t" || c == "\r" {
                self.pos += 1
                continue
            }
            if c == "\n" {
                self.line += 1
                self.pos += 1
                continue
            }
            if c == "/" && self.peek(1) == "/" {
                while self.pos < self.chars.count && self.chars[self.pos] != "\n" {
                    self.pos += 1
                }
                continue
            }
            if c == "/" && self.peek(1) == "*" {
                self.pos += 2
                var depth = 1
                while self.pos < self.chars.count && depth > 0 {
                    if self.chars[self.pos] == "/" && self.peek(1) == "*" {
                        depth += 1
                        self.pos += 2
                    } else if self.chars[self.pos] == "*" && self.peek(1) == "/" {
                        depth -= 1
                        self.pos += 2
                    } else {
                        if self.chars[self.pos] == "\n" { self.line += 1 }
                        self.pos += 1
                    }
                }
                continue
            }
            if c == "#" {
                // Skip #[...] attributes
                if self.peek(1) == "!" || self.peek(1) == "[" {
                    self.pos += 1
                    if self.pos < self.chars.count && self.chars[self.pos] == "!" { self.pos += 1 }
                    if self.pos < self.chars.count && self.chars[self.pos] == "[" {
                        var depth = 0
                        while self.pos < self.chars.count {
                            let ch = self.chars[self.pos]
                            if ch == "[" { depth += 1 }
                            else if ch == "]" {
                                depth -= 1
                                self.pos += 1
                                if depth <= 0 { break }
                                continue
                            } else if ch == "\n" {
                                self.line += 1
                            }
                            self.pos += 1
                        }
                        continue
                    }
                }
                self.pos += 1
                continue
            }
            if c == "r" && (self.peek(1) == "\"" || self.peek(1) == "#") {
                if let raw = try self.tryReadRawString() {
                    tokens.append(RsToken(kind: .string(raw), line: self.line))
                    continue
                }
            }
            if c == "\"" {
                tokens.append(RsToken(kind: .string(try self.readString()), line: self.line))
                continue
            }
            if c == "'" {
                // Could be char literal 'a' or lifetime 'a
                if self.peek(2) == "'" && self.peek(1) != "\\" {
                    let ch = self.chars[self.pos + 1]
                    self.pos += 3
                    tokens.append(RsToken(kind: .string(String(ch)), line: self.line))
                    continue
                }
                if self.peek(1) == "\\" && self.peek(3) == "'" {
                    self.pos += 2
                    let esc = self.readEscape()
                    if self.pos < self.chars.count && self.chars[self.pos] == "'" { self.pos += 1 }
                    tokens.append(RsToken(kind: .string(String(esc)), line: self.line))
                    continue
                }
                self.pos += 1
                continue
            }
            if c.isNumber {
                tokens.append(self.readNumber())
                continue
            }
            if c.isLetter || c == "_" {
                tokens.append(self.readIdentOrKeyword())
                continue
            }

            let tokLine = self.line
            switch c {
            case "+":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .plusAssign, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .plus, line: tokLine)) }
            case "-":
                if self.peek(1) == ">" { self.pos += 2; tokens.append(RsToken(kind: .arrow, line: tokLine)) }
                else if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .minusAssign, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .minus, line: tokLine)) }
            case "*":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .starAssign, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .star, line: tokLine)) }
            case "/":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .slashAssign, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .slash, line: tokLine)) }
            case "%":
                self.pos += 1; tokens.append(RsToken(kind: .percent, line: tokLine))
            case "=":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .eq, line: tokLine)) }
                else if self.peek(1) == ">" { self.pos += 2; tokens.append(RsToken(kind: .fatArrow, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .assign, line: tokLine)) }
            case "!":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .neq, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .bang, line: tokLine)) }
            case "<":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .lte, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .lt, line: tokLine)) }
            case ">":
                if self.peek(1) == "=" { self.pos += 2; tokens.append(RsToken(kind: .gte, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .gt, line: tokLine)) }
            case "&":
                if self.peek(1) == "&" { self.pos += 2; tokens.append(RsToken(kind: .andAnd, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .amp, line: tokLine)) }
            case "|":
                if self.peek(1) == "|" { self.pos += 2; tokens.append(RsToken(kind: .orOr, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .pipe, line: tokLine)) }
            case ":":
                if self.peek(1) == ":" { self.pos += 2; tokens.append(RsToken(kind: .colonColon, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .colon, line: tokLine)) }
            case ".":
                if self.peek(1) == "." && self.peek(2) == "=" { self.pos += 3; tokens.append(RsToken(kind: .dotDotEq, line: tokLine)) }
                else if self.peek(1) == "." { self.pos += 2; tokens.append(RsToken(kind: .dotDot, line: tokLine)) }
                else { self.pos += 1; tokens.append(RsToken(kind: .dot, line: tokLine)) }
            case ";": self.pos += 1; tokens.append(RsToken(kind: .semi, line: tokLine))
            case ",": self.pos += 1; tokens.append(RsToken(kind: .comma, line: tokLine))
            case "(": self.pos += 1; tokens.append(RsToken(kind: .lParen, line: tokLine))
            case ")": self.pos += 1; tokens.append(RsToken(kind: .rParen, line: tokLine))
            case "[": self.pos += 1; tokens.append(RsToken(kind: .lBracket, line: tokLine))
            case "]": self.pos += 1; tokens.append(RsToken(kind: .rBracket, line: tokLine))
            case "{": self.pos += 1; tokens.append(RsToken(kind: .lBrace, line: tokLine))
            case "}": self.pos += 1; tokens.append(RsToken(kind: .rBrace, line: tokLine))
            default:
                throw FullGramPluginError("Rust syntax error at line \(tokLine): unexpected '\(c)'")
            }
        }
        tokens.append(RsToken(kind: .eof, line: self.line))
        return tokens
    }

    private func peek(_ offset: Int) -> Character? {
        let idx = self.pos + offset
        guard idx >= 0 && idx < self.chars.count else { return nil }
        return self.chars[idx]
    }

    private mutating func tryReadRawString() throws -> String? {
        let savedPos = self.pos
        let savedLine = self.line
        self.pos += 1 // 'r'
        var hashes = 0
        while self.pos < self.chars.count && self.chars[self.pos] == "#" {
            hashes += 1
            self.pos += 1
        }
        guard self.pos < self.chars.count && self.chars[self.pos] == "\"" else {
            self.pos = savedPos
            self.line = savedLine
            return nil
        }
        self.pos += 1
        var out = ""
        while self.pos < self.chars.count {
            let ch = self.chars[self.pos]
            if ch == "\"" {
                var matched = true
                for i in 1...max(1, hashes) where hashes > 0 {
                    if self.peek(i) != "#" { matched = false; break }
                }
                if hashes == 0 || matched {
                    self.pos += 1 + hashes
                    return out
                }
            }
            if ch == "\n" { self.line += 1 }
            out.append(ch)
            self.pos += 1
        }
        throw FullGramPluginError("Unterminated raw Rust string at line \(savedLine)")
    }

    private mutating func readString() throws -> String {
        let startLine = self.line
        self.pos += 1
        var out = ""
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c == "\"" {
                self.pos += 1
                return out
            }
            if c == "\\" {
                self.pos += 1
                out.append(self.readEscape())
                continue
            }
            if c == "\n" { self.line += 1 }
            out.append(c)
            self.pos += 1
        }
        throw FullGramPluginError("Unterminated Rust string at line \(startLine)")
    }

    private mutating func readEscape() -> Character {
        guard self.pos < self.chars.count else { return "\\" }
        let esc = self.chars[self.pos]
        self.pos += 1
        switch esc {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "\\": return "\\"
        case "\"": return "\""
        case "'": return "'"
        case "0": return "\0"
        default: return esc
        }
    }

    private mutating func readNumber() -> RsToken {
        let tokLine = self.line
        var raw = ""
        var isFloat = false
        if self.chars[self.pos] == "0" && (self.peek(1) == "x" || self.peek(1) == "X") {
            self.pos += 2
            while self.pos < self.chars.count {
                let c = self.chars[self.pos]
                if c.isHexDigit { raw.append(c); self.pos += 1 }
                else if c == "_" { self.pos += 1 }
                else { break }
            }
            return RsToken(kind: .intLit(Int64(raw, radix: 16) ?? 0), line: tokLine)
        }
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isNumber { raw.append(c); self.pos += 1 }
            else if c == "_" { self.pos += 1 }
            else if c == "." && self.peek(1)?.isNumber == true && !isFloat {
                isFloat = true
                raw.append(c)
                self.pos += 1
            } else {
                break
            }
        }
        // Optional type suffix like i64, usize, f64
        if self.pos < self.chars.count && (self.chars[self.pos] == "i" || self.chars[self.pos] == "u" || self.chars[self.pos] == "f") {
            if self.chars[self.pos] == "f" { isFloat = true }
            while self.pos < self.chars.count && (self.chars[self.pos].isLetter || self.chars[self.pos].isNumber) {
                self.pos += 1
            }
        }
        if isFloat {
            return RsToken(kind: .floatLit(Double(raw) ?? 0.0), line: tokLine)
        }
        return RsToken(kind: .intLit(Int64(raw) ?? 0), line: tokLine)
    }

    private mutating func readIdentOrKeyword() -> RsToken {
        let tokLine = self.line
        var s = ""
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isLetter || c.isNumber || c == "_" {
                s.append(c)
                self.pos += 1
            } else {
                break
            }
        }
        // Macro invocation like format!(...) / vec![...] / println!(...)
        if self.pos < self.chars.count && self.chars[self.pos] == "!" && self.peek(1) != "=" {
            self.pos += 1
            return RsToken(kind: .ident(s + "!"), line: tokLine)
        }
        let kind: RsTokenKind
        switch s {
        case "fn": kind = .fn
        case "pub": kind = .pub
        case "let": kind = .let
        case "mut": kind = .mut
        case "const": kind = .const
        case "static": kind = .static
        case "struct": kind = .struct
        case "enum": kind = .enum
        case "use": kind = .use
        case "if": kind = .if
        case "else": kind = .else
        case "while": kind = .while
        case "for": kind = .for
        case "in": kind = .in
        case "loop": kind = .loop
        case "match": kind = .match
        case "return": kind = .return
        case "break": kind = .break
        case "continue": kind = .continue
        case "true": kind = .true
        case "false": kind = .false
        case "as": kind = .as
        default: kind = .ident(s)
        }
        return RsToken(kind: kind, line: tokLine)
    }
}

private indirect enum RsExpr {
    case nilLit
    case boolLit(Bool)
    case intLit(Int64)
    case floatLit(Double)
    case stringLit(String)
    case ident(String)
    case arrayLit([RsExpr])
    case structLit(String, [(String, RsExpr)])
    case block([RsStmt], RsExpr?)
    case ifExpr(RsExpr, RsExpr, RsExpr?)
    case matchExpr(RsExpr, [([RsExpr?], RsExpr)])
    case closure([String], RsExpr)
    case unary(String, RsExpr)
    case binary(String, RsExpr, RsExpr)
    case path(RsExpr, String)
    case member(RsExpr, String)
    case index(RsExpr, RsExpr)
    case call(RsExpr, [RsExpr])
    case methodCall(RsExpr, String, [RsExpr])
}

private indirect enum RsStmt {
    case letDecl(String, RsExpr?)
    case assign(RsExpr, String, RsExpr)
    case fnDecl(String, [String], [RsStmt], RsExpr?)
    case ifStmt(RsExpr, [RsStmt], RsExpr?, [RsStmt]?, RsExpr?)
    case whileStmt(RsExpr, [RsStmt])
    case loopStmt([RsStmt])
    case forStmt(String, RsExpr, [RsStmt])
    case returnStmt(RsExpr?)
    case breakStmt
    case continueStmt
    case exprStmt(RsExpr)
}

private struct RsParser {
    private let tokens: [RsToken]
    private var idx = 0
    private var depth = 0
    private let maxDepth = 64

    init(tokens: [RsToken]) {
        self.tokens = tokens
    }

    private mutating func enterDepth() throws {
        self.depth += 1
        if self.depth > self.maxDepth {
            throw FullGramPluginError("Rust nesting depth limit exceeded (\(self.maxDepth)) at line \(self.current.line)")
        }
    }

    private var current: RsToken { self.tokens[min(self.idx, self.tokens.count - 1)] }

    private func peekKind(_ offset: Int = 1) -> RsTokenKind {
        let i = self.idx + offset
        guard i >= 0 && i < self.tokens.count else { return .eof }
        return self.tokens[i].kind
    }

    @discardableResult
    private mutating func advance() -> RsToken {
        let tok = self.current
        if self.idx < self.tokens.count - 1 { self.idx += 1 }
        return tok
    }

    private func check(_ kind: RsTokenKind) -> Bool {
        return self.current.kind == kind
    }

    private mutating func match(_ kind: RsTokenKind) -> Bool {
        if self.check(kind) { self.advance(); return true }
        return false
    }

    private mutating func expect(_ kind: RsTokenKind, _ msg: String) throws {
        guard self.match(kind) else {
            throw FullGramPluginError("Rust syntax error at line \(self.current.line): \(msg)")
        }
    }

    private mutating func skipTypeAnnotation() {
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        while !self.check(.eof) {
            let k = self.current.kind
            if angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 {
                if k == .comma || k == .rParen || k == .assign || k == .semi || k == .lBrace {
                    break
                }
            }
            if k == .lt { angleDepth += 1 }
            else if k == .gt && angleDepth > 0 { angleDepth -= 1 }
            else if k == .lParen { parenDepth += 1 }
            else if k == .rParen && parenDepth > 0 { parenDepth -= 1 }
            else if k == .lBracket { bracketDepth += 1 }
            else if k == .rBracket && bracketDepth > 0 { bracketDepth -= 1 }
            self.advance()
        }
    }

    mutating func parseModule() throws -> [RsStmt] {
        var stmts: [RsStmt] = []
        while !self.check(.eof) {
            if self.match(.semi) { continue }
            if let s = try self.parseTopLevelOrStmt() {
                stmts.append(s)
            }
        }
        return stmts
    }

    private mutating func parseTopLevelOrStmt() throws -> RsStmt? {
        try self.enterDepth()
        defer { self.depth -= 1 }
        _ = self.match(.pub)
        if self.match(.use) {
            while !self.check(.semi) && !self.check(.eof) { self.advance() }
            _ = self.match(.semi)
            return nil
        }
        if self.match(.struct) {
            while !self.check(.lBrace) && !self.check(.semi) && !self.check(.eof) { self.advance() }
            if self.match(.lBrace) {
                var depth = 1
                while !self.check(.eof) && depth > 0 {
                    if self.check(.lBrace) { depth += 1 }
                    else if self.check(.rBrace) { depth -= 1 }
                    self.advance()
                }
            } else {
                _ = self.match(.semi)
            }
            return nil
        }
        if self.match(.enum) {
            while !self.check(.lBrace) && !self.check(.eof) { self.advance() }
            if self.match(.lBrace) {
                var depth = 1
                while !self.check(.eof) && depth > 0 {
                    if self.check(.lBrace) { depth += 1 }
                    else if self.check(.rBrace) { depth -= 1 }
                    self.advance()
                }
            }
            return nil
        }
        if self.match(.fn) {
            return try self.parseFnDecl()
        }
        if self.match(.const) || self.match(.static) {
            guard case let .ident(name) = self.current.kind else {
                throw FullGramPluginError("Expected identifier after const/static at line \(self.current.line)")
            }
            self.advance()
            if self.match(.colon) { self.skipTypeAnnotation() }
            try self.expect(.assign, "Expected '=' in const/static")
            let val = try self.parseExpr()
            _ = self.match(.semi)
            return .letDecl(name, val)
        }
        if self.match(.let) {
            _ = self.match(.mut)
            guard case let .ident(name) = self.current.kind else {
                throw FullGramPluginError("Expected variable name after let at line \(self.current.line)")
            }
            self.advance()
            if self.match(.colon) { self.skipTypeAnnotation() }
            var val: RsExpr? = nil
            if self.match(.assign) {
                val = try self.parseExpr()
            }
            _ = self.match(.semi)
            return .letDecl(name, val)
        }
        if self.match(.return) {
            if self.check(.semi) || self.check(.rBrace) {
                _ = self.match(.semi)
                return .returnStmt(nil)
            }
            let e = try self.parseExpr()
            _ = self.match(.semi)
            return .returnStmt(e)
        }
        if self.match(.break) { _ = self.match(.semi); return .breakStmt }
        if self.match(.continue) { _ = self.match(.semi); return .continueStmt }
        if self.match(.while) {
            let cond = try self.parseExpr(allowStructLit: false)
            let (body, tail) = try self.parseBlockContents()
            var full = body
            if let t = tail { full.append(.exprStmt(t)) }
            return .whileStmt(cond, full)
        }
        if self.match(.loop) {
            let (body, tail) = try self.parseBlockContents()
            var full = body
            if let t = tail { full.append(.exprStmt(t)) }
            return .loopStmt(full)
        }
        if self.match(.for) {
            guard case let .ident(varName) = self.current.kind else {
                throw FullGramPluginError("Expected loop variable after for at line \(self.current.line)")
            }
            self.advance()
            try self.expect(.in, "Expected 'in' in for loop")
            let iter = try self.parseExpr(allowStructLit: false)
            let (body, tail) = try self.parseBlockContents()
            var full = body
            if let t = tail { full.append(.exprStmt(t)) }
            return .forStmt(varName, iter, full)
        }
        let expr = try self.parseExpr()
        if self.match(.assign) {
            let rhs = try self.parseExpr()
            _ = self.match(.semi)
            return .assign(expr, "=", rhs)
        }
        if self.match(.plusAssign) {
            let rhs = try self.parseExpr()
            _ = self.match(.semi)
            return .assign(expr, "+=", rhs)
        }
        if self.match(.minusAssign) {
            let rhs = try self.parseExpr()
            _ = self.match(.semi)
            return .assign(expr, "-=", rhs)
        }
        if self.match(.starAssign) {
            let rhs = try self.parseExpr()
            _ = self.match(.semi)
            return .assign(expr, "*=", rhs)
        }
        if self.match(.slashAssign) {
            let rhs = try self.parseExpr()
            _ = self.match(.semi)
            return .assign(expr, "/=", rhs)
        }
        _ = self.match(.semi)
        return .exprStmt(expr)
    }

    private mutating func parseFnDecl() throws -> RsStmt {
        guard case let .ident(name) = self.current.kind else {
            throw FullGramPluginError("Expected function name at line \(self.current.line)")
        }
        self.advance()
        if self.match(.lt) {
            var depth = 1
            while !self.check(.eof) && depth > 0 {
                if self.check(.lt) { depth += 1 }
                else if self.check(.gt) { depth -= 1 }
                self.advance()
            }
        }
        try self.expect(.lParen, "Expected '(' after fn name")
        var params: [String] = []
        while !self.check(.rParen) && !self.check(.eof) {
            _ = self.match(.mut)
            if case let .ident(p) = self.current.kind {
                self.advance()
                if p != "self" { params.append(p) }
            }
            if self.match(.colon) {
                self.skipTypeAnnotation()
            }
            if !self.match(.comma) { break }
        }
        try self.expect(.rParen, "Expected ')' after fn params")
        if self.match(.arrow) {
            self.skipTypeAnnotation()
        }
        let (stmts, tail) = try self.parseBlockContents()
        return .fnDecl(name, params, stmts, tail)
    }

    private mutating func parseBlockContents() throws -> ([RsStmt], RsExpr?) {
        try self.enterDepth()
        defer { self.depth -= 1 }
        try self.expect(.lBrace, "Expected '{'")
        var stmts: [RsStmt] = []
        var tailExpr: RsExpr? = nil
        while !self.check(.rBrace) && !self.check(.eof) {
            if self.match(.semi) { continue }
            let isControlFlow = self.check(.if) || self.check(.match)
            let isDeclOrJump = self.check(.let) || self.check(.return) || self.check(.break) || self.check(.continue) || self.check(.while) || self.check(.for) || self.check(.loop) || self.check(.fn) || self.check(.const) || self.check(.static) || self.check(.pub) || self.check(.use) || self.check(.struct) || self.check(.enum)
            if isDeclOrJump {
                if let s = try self.parseTopLevelOrStmt() {
                    stmts.append(s)
                }
                continue
            }
            let expr = try self.parseExpr()
            if self.match(.assign) {
                let rhs = try self.parseExpr()
                _ = self.match(.semi)
                stmts.append(.assign(expr, "=", rhs))
            } else if self.match(.plusAssign) {
                let rhs = try self.parseExpr()
                _ = self.match(.semi)
                stmts.append(.assign(expr, "+=", rhs))
            } else if self.match(.minusAssign) {
                let rhs = try self.parseExpr()
                _ = self.match(.semi)
                stmts.append(.assign(expr, "-=", rhs))
            } else if self.match(.starAssign) {
                let rhs = try self.parseExpr()
                _ = self.match(.semi)
                stmts.append(.assign(expr, "*=", rhs))
            } else if self.match(.slashAssign) {
                let rhs = try self.parseExpr()
                _ = self.match(.semi)
                stmts.append(.assign(expr, "/=", rhs))
            } else if self.match(.semi) {
                stmts.append(.exprStmt(expr))
            } else if self.check(.rBrace) {
                tailExpr = expr
                break
            } else if isControlFlow {
                stmts.append(.exprStmt(expr))
            } else {
                stmts.append(.exprStmt(expr))
            }
        }
        try self.expect(.rBrace, "Expected '}'")
        return (stmts, tailExpr)
    }

    private mutating func parseExpr(allowStructLit: Bool = true) throws -> RsExpr {
        try self.enterDepth()
        defer { self.depth -= 1 }
        return try self.parseRange(allowStructLit: allowStructLit)
    }

    private mutating func parseRange(allowStructLit: Bool) throws -> RsExpr {
        let lhs = try self.parseOr(allowStructLit: allowStructLit)
        if self.match(.dotDotEq) {
            let rhs = try self.parseOr(allowStructLit: allowStructLit)
            return .binary("..=", lhs, rhs)
        }
        if self.match(.dotDot) {
            let rhs = try self.parseOr(allowStructLit: allowStructLit)
            return .binary("..", lhs, rhs)
        }
        return lhs
    }

    private mutating func parseOr(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseAnd(allowStructLit: allowStructLit)
        while self.match(.orOr) {
            expr = .binary("||", expr, try self.parseAnd(allowStructLit: allowStructLit))
        }
        return expr
    }

    private mutating func parseAnd(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseEquality(allowStructLit: allowStructLit)
        while self.match(.andAnd) {
            expr = .binary("&&", expr, try self.parseEquality(allowStructLit: allowStructLit))
        }
        return expr
    }

    private mutating func parseEquality(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseComparison(allowStructLit: allowStructLit)
        while true {
            if self.match(.eq) { expr = .binary("==", expr, try self.parseComparison(allowStructLit: allowStructLit)) }
            else if self.match(.neq) { expr = .binary("!=", expr, try self.parseComparison(allowStructLit: allowStructLit)) }
            else { break }
        }
        return expr
    }

    private mutating func parseComparison(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseAddSub(allowStructLit: allowStructLit)
        while true {
            if self.match(.lt) { expr = .binary("<", expr, try self.parseAddSub(allowStructLit: allowStructLit)) }
            else if self.match(.lte) { expr = .binary("<=", expr, try self.parseAddSub(allowStructLit: allowStructLit)) }
            else if self.match(.gt) { expr = .binary(">", expr, try self.parseAddSub(allowStructLit: allowStructLit)) }
            else if self.match(.gte) { expr = .binary(">=", expr, try self.parseAddSub(allowStructLit: allowStructLit)) }
            else { break }
        }
        return expr
    }

    private mutating func parseAddSub(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseMulDiv(allowStructLit: allowStructLit)
        while true {
            if self.match(.plus) { expr = .binary("+", expr, try self.parseMulDiv(allowStructLit: allowStructLit)) }
            else if self.match(.minus) { expr = .binary("-", expr, try self.parseMulDiv(allowStructLit: allowStructLit)) }
            else { break }
        }
        return expr
    }

    private mutating func parseMulDiv(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parseCast(allowStructLit: allowStructLit)
        while true {
            if self.match(.star) { expr = .binary("*", expr, try self.parseCast(allowStructLit: allowStructLit)) }
            else if self.match(.slash) { expr = .binary("/", expr, try self.parseCast(allowStructLit: allowStructLit)) }
            else if self.match(.percent) { expr = .binary("%", expr, try self.parseCast(allowStructLit: allowStructLit)) }
            else { break }
        }
        return expr
    }

    private mutating func parseCast(allowStructLit: Bool) throws -> RsExpr {
        let expr = try self.parseUnary(allowStructLit: allowStructLit)
        if self.match(.as) {
            if case .ident = self.current.kind { self.advance() }
        }
        return expr
    }

    private mutating func parseUnary(allowStructLit: Bool) throws -> RsExpr {
        if self.match(.bang) {
            try self.enterDepth()
            defer { self.depth -= 1 }
            return .unary("!", try self.parseUnary(allowStructLit: allowStructLit))
        }
        if self.match(.minus) {
            try self.enterDepth()
            defer { self.depth -= 1 }
            return .unary("-", try self.parseUnary(allowStructLit: allowStructLit))
        }
        if self.match(.amp) {
            _ = self.match(.mut)
            try self.enterDepth()
            defer { self.depth -= 1 }
            return try self.parseUnary(allowStructLit: allowStructLit)
        }
        if self.match(.star) {
            try self.enterDepth()
            defer { self.depth -= 1 }
            return try self.parseUnary(allowStructLit: allowStructLit)
        }
        return try self.parsePostfix(allowStructLit: allowStructLit)
    }

    private mutating func parsePostfix(allowStructLit: Bool) throws -> RsExpr {
        var expr = try self.parsePrimary(allowStructLit: allowStructLit)
        while true {
            if self.match(.colonColon) {
                guard case let .ident(member) = self.current.kind else {
                    throw FullGramPluginError("Expected identifier after '::' at line \(self.current.line)")
                }
                self.advance()
                expr = .path(expr, member)
            } else if self.match(.dot) {
                guard case let .ident(member) = self.current.kind else {
                    throw FullGramPluginError("Expected member name after '.' at line \(self.current.line)")
                }
                self.advance()
                if self.match(.lParen) {
                    let args = try self.parseArgList(closing: .rParen)
                    expr = .methodCall(expr, member, args)
                } else {
                    expr = .member(expr, member)
                }
            } else if self.match(.lParen) {
                let args = try self.parseArgList(closing: .rParen)
                expr = .call(expr, args)
            } else if self.match(.lBracket) {
                let idxExpr = try self.parseExpr()
                try self.expect(.rBracket, "Expected ']'")
                expr = .index(expr, idxExpr)
            } else {
                break
            }
        }
        return expr
    }

    private mutating func parseArgList(closing: RsTokenKind) throws -> [RsExpr] {
        var args: [RsExpr] = []
        while !self.check(closing) && !self.check(.eof) {
            args.append(try self.parseExpr())
            if !self.match(.comma) { break }
        }
        try self.expect(closing, "Expected closing delimiter")
        return args
    }

    private mutating func parsePrimary(allowStructLit: Bool) throws -> RsExpr {
        try self.enterDepth()
        defer { self.depth -= 1 }
        switch self.current.kind {
        case .true: self.advance(); return .boolLit(true)
        case .false: self.advance(); return .boolLit(false)
        case let .intLit(v): self.advance(); return .intLit(v)
        case let .floatLit(v): self.advance(); return .floatLit(v)
        case let .string(s): self.advance(); return .stringLit(s)
        case let .ident(name):
            self.advance()
            if name == "None" { return .nilLit }
            if name == "vec!" && self.match(.lBracket) {
                let items = try self.parseArgList(closing: .rBracket)
                return .arrayLit(items)
            }
            if name.hasSuffix("!") {
                if self.match(.lParen) {
                    let args = try self.parseArgList(closing: .rParen)
                    return .call(.ident(name), args)
                } else if self.match(.lBracket) {
                    let args = try self.parseArgList(closing: .rBracket)
                    return .call(.ident(name), args)
                }
            }
            if allowStructLit && self.check(.lBrace) && name.first?.isUppercase == true {
                self.advance()
                var fields: [(String, RsExpr)] = []
                while !self.check(.rBrace) && !self.check(.eof) {
                    guard case let .ident(fieldName) = self.current.kind else {
                        throw FullGramPluginError("Expected field name in struct literal at line \(self.current.line)")
                    }
                    self.advance()
                    if self.match(.colon) {
                        fields.append((fieldName, try self.parseExpr()))
                    } else {
                        fields.append((fieldName, .ident(fieldName)))
                    }
                    if !self.match(.comma) { break }
                }
                try self.expect(.rBrace, "Expected '}'")
                return .structLit(name, fields)
            }
            return .ident(name)
        case .lParen:
            self.advance()
            if self.match(.rParen) { return .nilLit }
            let e = try self.parseExpr()
            try self.expect(.rParen, "Expected ')'")
            return e
        case .lBracket:
            self.advance()
            let items = try self.parseArgList(closing: .rBracket)
            return .arrayLit(items)
        case .lBrace:
            let (stmts, tail) = try self.parseBlockContents()
            return .block(stmts, tail)
        case .if:
            self.advance()
            let cond = try self.parseExpr(allowStructLit: false)
            let (thenStmts, thenTail) = try self.parseBlockContents()
            let thenBlock = RsExpr.block(thenStmts, thenTail)
            var elseBlock: RsExpr? = nil
            if self.match(.else) {
                if self.check(.if) {
                    elseBlock = try self.parsePrimary(allowStructLit: allowStructLit)
                } else {
                    let (eStmts, eTail) = try self.parseBlockContents()
                    elseBlock = .block(eStmts, eTail)
                }
            }
            return .ifExpr(cond, thenBlock, elseBlock)
        case .match:
            self.advance()
            let subject = try self.parseExpr(allowStructLit: false)
            try self.expect(.lBrace, "Expected '{' in match")
            var arms: [([RsExpr?], RsExpr)] = []
            while !self.check(.rBrace) && !self.check(.eof) {
                var patterns: [RsExpr?] = []
                repeat {
                    if case let .ident(id) = self.current.kind, id == "_" {
                        self.advance()
                        patterns.append(nil)
                    } else {
                        patterns.append(try self.parseExpr(allowStructLit: false))
                    }
                } while self.match(.pipe)
                try self.expect(.fatArrow, "Expected '=>' in match arm")
                let body: RsExpr
                if self.check(.lBrace) {
                    let (bStmts, bTail) = try self.parseBlockContents()
                    body = .block(bStmts, bTail)
                    _ = self.match(.comma)
                } else {
                    body = try self.parseExpr()
                    _ = self.match(.comma)
                }
                arms.append((patterns, body))
            }
            try self.expect(.rBrace, "Expected '}' after match")
            return .matchExpr(subject, arms)
        case .pipe:
            self.advance()
            var params: [String] = []
            while !self.check(.pipe) && !self.check(.eof) {
                if case let .ident(p) = self.current.kind {
                    self.advance()
                    params.append(p)
                }
                if self.match(.colon) { self.skipTypeAnnotation() }
                if !self.match(.comma) { break }
            }
            try self.expect(.pipe, "Expected closing '|' in closure")
            let body = try self.parseExpr()
            return .closure(params, body)
        default:
            throw FullGramPluginError("Rust syntax error at line \(self.current.line): unexpected token \(self.current.kind)")
        }
    }
}

private final class RsEnv {
    fileprivate var vars: [String: FullGramPluginValue] = [:]
    let parent: RsEnv?

    init(parent: RsEnv? = nil) {
        self.parent = parent
    }

    func get(_ name: String) -> FullGramPluginValue? {
        if let v = self.vars[name] { return v }
        return self.parent?.get(name)
    }

    func define(_ name: String, _ value: FullGramPluginValue) {
        self.vars[name] = value
    }

    func assign(_ name: String, _ value: FullGramPluginValue) {
        if self.vars[name] != nil {
            self.vars[name] = value
        } else if let parent = self.parent, parent.has(name) {
            parent.assign(name, value)
        } else {
            self.vars[name] = value
        }
    }

    private func has(_ name: String) -> Bool {
        if self.vars[name] != nil { return true }
        return self.parent?.has(name) ?? false
    }
}

private enum RsControlFlow: Error {
    case returnValue(FullGramPluginValue)
    case breakLoop
    case continueLoop
}

public final class FullGramRustVM {
    private let globalEnv = RsEnv()
    private let vmLock = NSRecursiveLock()
    private var steps = 0
    private let maxSteps = 120_000
    private var callDepth = 0
    private let maxCallDepth = 64
    private static let maxStringBytes = 1_048_576
    private static let maxCollectionItems = 10_000

    public init(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        self.registerBuiltins(hostAPI: hostAPI, printHandler: printHandler)
    }

    deinit {
        self.globalEnv.vars.removeAll()
    }

    public func load(code: String) throws {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        self.steps = 0
        self.callDepth = 0
        var lexer = RsLexer(source: code)
        let tokens = try lexer.tokenize()
        var parser = RsParser(tokens: tokens)
        let stmts = try parser.parseModule()
        try self.execBlock(stmts, env: self.globalEnv)
    }

    public func hasFunction(_ name: String) -> Bool {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        if case .function = self.globalEnv.get(name) ?? .nil { return true }
        return false
    }

    @discardableResult
    public func callFunction(_ name: String, args: [FullGramPluginValue]) throws -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        guard let val = self.globalEnv.get(name), case let .function(fn) = val else {
            return .nil
        }
        self.steps = 0
        self.callDepth = 0
        return try fn(args)
    }

    @discardableResult
    public func invoke(_ fn: ([FullGramPluginValue]) throws -> FullGramPluginValue, args: [FullGramPluginValue]) throws -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        if self.callDepth == 0 {
            self.steps = 0
        }
        return try fn(args)
    }

    public func getGlobal(_ name: String) -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        return self.globalEnv.get(name) ?? .nil
    }

    private func tick() throws {
        self.steps += 1
        if self.steps > self.maxSteps {
            throw FullGramPluginError("Rust execution step limit exceeded (\(self.maxSteps))")
        }
    }

    private func enterCall() throws {
        self.callDepth += 1
        if self.callDepth > self.maxCallDepth {
            throw FullGramPluginError("Rust recursion limit exceeded (\(self.maxCallDepth))")
        }
    }

    private func registerBuiltins(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        let fullgramBox = FullGramPluginTableBox(dict: hostAPI)
        self.globalEnv.define("fullgram", .table(fullgramBox))

        for (k, v) in hostAPI {
            self.globalEnv.define(k, v)
        }

        self.globalEnv.define("Some", .function { args in
            return args.first ?? .nil
        })
        self.globalEnv.define("Ok", .function { args in
            return args.first ?? .nil
        })
        self.globalEnv.define("Err", .function { _ in
            return .nil
        })
        self.globalEnv.define("println!", .function { args in
            let text = try Self.formatMacro(args)
            printHandler(text)
            return .nil
        })
        self.globalEnv.define("eprintln!", .function { args in
            let text = try Self.formatMacro(args)
            printHandler(text)
            return .nil
        })
        self.globalEnv.define("format!", .function { args in
            return .string(try Self.formatMacro(args))
        })
        self.globalEnv.define("len", .function { args in
            guard let v = args.first else { return .int(0) }
            switch v {
            case let .string(s): return .int(Int64(s.count))
            case let .table(t): return .int(Int64(t.arrayPart.isEmpty ? t.mapPart.count : t.arrayPart.count))
            default: return .int(0)
            }
        })
        self.globalEnv.define("str", .function { args in
            return .string(args.first?.asString ?? "")
        })
        self.globalEnv.define("int", .function { args in
            return .int(args.first?.asInt ?? 0)
        })
        self.globalEnv.define("float", .function { args in
            return .double(args.first?.asDouble ?? 0.0)
        })
        let stringNS = FullGramPluginTableBox(dict: [
            "from": .function { args in .string(args.first?.asString ?? "") },
            "new": .function { _ in .string("") }
        ])
        self.globalEnv.define("String", .table(stringNS))
        let vecNS = FullGramPluginTableBox(dict: [
            "new": .function { _ in .table(FullGramPluginTableBox()) }
        ])
        self.globalEnv.define("Vec", .table(vecNS))
        let mapNS = FullGramPluginTableBox(dict: [
            "new": .function { _ in .table(FullGramPluginTableBox()) }
        ])
        self.globalEnv.define("HashMap", .table(mapNS))
    }

    private static func formatMacro(_ args: [FullGramPluginValue]) throws -> String {
        guard let first = args.first else { return "" }
        let template = first.asString
        guard template.utf8.count <= Self.maxStringBytes else {
            throw FullGramPluginError("Rust string size limit exceeded")
        }
        var out = template
        for arg in args.dropFirst() {
            let argStr = arg.asString
            if let range = out.range(of: "{}") {
                let replacedBytes = out[range].utf8.count
                guard out.utf8.count - replacedBytes + argStr.utf8.count <= Self.maxStringBytes else {
                    throw FullGramPluginError("Rust string size limit exceeded")
                }
                out.replaceSubrange(range, with: argStr)
            } else if let range = out.range(of: "{:?}") {
                let replacedBytes = out[range].utf8.count
                guard out.utf8.count - replacedBytes + argStr.utf8.count <= Self.maxStringBytes else {
                    throw FullGramPluginError("Rust string size limit exceeded")
                }
                out.replaceSubrange(range, with: argStr)
            } else {
                guard out.utf8.count + 1 + argStr.utf8.count <= Self.maxStringBytes else {
                    throw FullGramPluginError("Rust string size limit exceeded")
                }
                out += " " + argStr
            }
        }
        return out
    }

    private func execBlock(_ stmts: [RsStmt], env: RsEnv) throws {
        for s in stmts {
            try self.execStmt(s, env: env)
        }
    }

    private func execStmt(_ stmt: RsStmt, env: RsEnv) throws {
        try self.tick()
        switch stmt {
        case let .letDecl(name, expr):
            let val = try expr.map { try self.eval($0, env: env) } ?? .nil
            env.define(name, val)
        case let .assign(target, op, rhsExpr):
            let rhs = try self.eval(rhsExpr, env: env)
            try self.performAssign(target: target, op: op, rhs: rhs, env: env)
        case let .fnDecl(name, params, body, tail):
            let fnVal: FullGramPluginValue = .function { [weak self] callArgs in
                guard let self else { return .nil }
                try self.enterCall()
                defer { self.callDepth = max(0, self.callDepth - 1) }
                let fnEnv = RsEnv(parent: env)
                for (idx, param) in params.enumerated() {
                    fnEnv.define(param, idx < callArgs.count ? callArgs[idx] : .nil)
                }
                do {
                    try self.execBlock(body, env: fnEnv)
                    if let tail {
                        return try self.eval(tail, env: fnEnv)
                    }
                    return .nil
                } catch RsControlFlow.returnValue(let val) {
                    return val
                }
            }
            env.define(name, fnVal)
        case let .ifStmt(cond, thenBody, thenTail, elseBody, elseTail):
            if try self.eval(cond, env: env).isTruthy {
                let inner = RsEnv(parent: env)
                try self.execBlock(thenBody, env: inner)
                if let thenTail { _ = try self.eval(thenTail, env: inner) }
            } else if let elseBody {
                let inner = RsEnv(parent: env)
                try self.execBlock(elseBody, env: inner)
                if let elseTail { _ = try self.eval(elseTail, env: inner) }
            }
        case let .whileStmt(cond, body):
            while try self.eval(cond, env: env).isTruthy {
                try self.tick()
                do {
                    try self.execBlock(body, env: RsEnv(parent: env))
                } catch RsControlFlow.breakLoop {
                    break
                } catch RsControlFlow.continueLoop {
                    continue
                }
            }
        case let .loopStmt(body):
            while true {
                try self.tick()
                do {
                    try self.execBlock(body, env: RsEnv(parent: env))
                } catch RsControlFlow.breakLoop {
                    break
                } catch RsControlFlow.continueLoop {
                    continue
                }
            }
        case let .forStmt(varName, iterExpr, body):
            let iterable = try self.eval(iterExpr, env: env)
            let items = self.iterateValues(iterable)
            for item in items {
                try self.tick()
                let loopEnv = RsEnv(parent: env)
                loopEnv.define(varName, item)
                do {
                    try self.execBlock(body, env: loopEnv)
                } catch RsControlFlow.breakLoop {
                    break
                } catch RsControlFlow.continueLoop {
                    continue
                }
            }
        case let .returnStmt(expr):
            let val = try expr.map { try self.eval($0, env: env) } ?? .nil
            throw RsControlFlow.returnValue(val)
        case .breakStmt:
            throw RsControlFlow.breakLoop
        case .continueStmt:
            throw RsControlFlow.continueLoop
        case let .exprStmt(expr):
            _ = try self.eval(expr, env: env)
        }
    }

    private func performAssign(target: RsExpr, op: String, rhs: FullGramPluginValue, env: RsEnv) throws {
        func combine(_ cur: FullGramPluginValue, _ op: String, _ rhs: FullGramPluginValue) throws -> FullGramPluginValue {
            switch op {
            case "=": return rhs
            case "+=":
                if case let .string(a) = cur {
                    let b = rhs.asString
                    guard a.utf8.count + b.utf8.count <= Self.maxStringBytes else {
                        throw FullGramPluginError("Rust string size limit exceeded")
                    }
                    return .string(a + b)
                }
                if case .int = cur, case .int = rhs { return .int((cur.asInt ?? 0) &+ (rhs.asInt ?? 0)) }
                return .double((cur.asDouble ?? 0.0) + (rhs.asDouble ?? 0.0))
            case "-=":
                if case .int = cur, case .int = rhs { return .int((cur.asInt ?? 0) &- (rhs.asInt ?? 0)) }
                return .double((cur.asDouble ?? 0.0) - (rhs.asDouble ?? 0.0))
            case "*=":
                if case .int = cur, case .int = rhs { return .int((cur.asInt ?? 0) &* (rhs.asInt ?? 0)) }
                return .double((cur.asDouble ?? 0.0) * (rhs.asDouble ?? 0.0))
            case "/=":
                let d = rhs.asDouble ?? 0.0
                return d == 0.0 ? .int(0) : .double((cur.asDouble ?? 0.0) / d)
            default: return rhs
            }
        }
        switch target {
        case let .ident(name):
            let cur = env.get(name) ?? .nil
            env.assign(name, try combine(cur, op, rhs))
        case let .member(objExpr, key):
            if case let .table(box) = try self.eval(objExpr, env: env) {
                let cur = box.get(key: .string(key))
                box.set(key: .string(key), value: try combine(cur, op, rhs))
            }
        case let .index(objExpr, keyExpr):
            let obj = try self.eval(objExpr, env: env)
            let key = try self.eval(keyExpr, env: env)
            if case let .table(box) = obj {
                if case let .int(i) = key {
                    if i >= 0 && i < Int64(box.arrayPart.count) {
                        let idx = Int(i)
                        let cur = box.arrayPart[idx]
                        box.arrayPart[idx] = try combine(cur, op, rhs)
                    } else if box.arrayPart.isEmpty {
                        let cur = box.get(key: key)
                        box.set(key: key, value: try combine(cur, op, rhs))
                    }
                } else {
                    let cur = box.get(key: key)
                    box.set(key: key, value: try combine(cur, op, rhs))
                }
            }
        default:
            break
        }
    }

    private func iterateValues(_ val: FullGramPluginValue) -> [FullGramPluginValue] {
        switch val {
        case let .table(box):
            if !box.arrayPart.isEmpty {
                return box.arrayPart
            }
            return box.orderedKeys.map { .string($0) }
        case let .string(s):
            return s.map { .string(String($0)) }
        default:
            return []
        }
    }

    private func eval(_ expr: RsExpr, env: RsEnv) throws -> FullGramPluginValue {
        try self.tick()
        switch expr {
        case .nilLit: return .nil
        case let .boolLit(b): return .bool(b)
        case let .intLit(i): return .int(i)
        case let .floatLit(d): return .double(d)
        case let .stringLit(s): return .string(s)
        case let .ident(name):
            return env.get(name) ?? .nil
        case let .arrayLit(items):
            guard items.count <= Self.maxCollectionItems else {
                throw FullGramPluginError("Rust array size limit exceeded")
            }
            let vals = try items.map { try self.eval($0, env: env) }
            return .table(FullGramPluginTableBox(array: vals))
        case let .structLit(_, fields):
            guard fields.count <= Self.maxCollectionItems else {
                throw FullGramPluginError("Rust struct field limit exceeded")
            }
            var dict: [String: FullGramPluginValue] = [:]
            for (k, v) in fields {
                dict[k] = try self.eval(v, env: env)
            }
            return .table(FullGramPluginTableBox(dict: dict))
        case let .block(stmts, tail):
            let blockEnv = RsEnv(parent: env)
            try self.execBlock(stmts, env: blockEnv)
            if let tail { return try self.eval(tail, env: blockEnv) }
            return .nil
        case let .ifExpr(cond, thenBlock, elseBlock):
            if try self.eval(cond, env: env).isTruthy {
                return try self.eval(thenBlock, env: env)
            } else if let elseBlock {
                return try self.eval(elseBlock, env: env)
            }
            return .nil
        case let .matchExpr(subjectExpr, arms):
            let subject = try self.eval(subjectExpr, env: env)
            for (patterns, body) in arms {
                for pat in patterns {
                    if pat == nil {
                        return try self.eval(body, env: env)
                    }
                    if let p = pat {
                        let pVal = try self.eval(p, env: env)
                        if Self.valuesEqual(subject, pVal) {
                            return try self.eval(body, env: env)
                        }
                    }
                }
            }
            return .nil
        case let .closure(params, body):
            return .function { [weak self] args in
                guard let self else { return .nil }
                try self.enterCall()
                defer { self.callDepth = max(0, self.callDepth - 1) }
                let cEnv = RsEnv(parent: env)
                for (i, p) in params.enumerated() {
                    cEnv.define(p, i < args.count ? args[i] : .nil)
                }
                do {
                    return try self.eval(body, env: cEnv)
                } catch let RsControlFlow.returnValue(val) {
                    return val
                }
            }
        case let .unary(op, rhsExpr):
            let v = try self.eval(rhsExpr, env: env)
            switch op {
            case "!": return .bool(!v.isTruthy)
            case "-":
                if case let .int(i) = v { return .int(0 &- i) }
                return .double(-(v.asDouble ?? 0.0))
            default: return v
            }
        case let .binary(op, lhsExpr, rhsExpr):
            if op == "&&" {
                let l = try self.eval(lhsExpr, env: env)
                return l.isTruthy ? .bool((try self.eval(rhsExpr, env: env)).isTruthy) : .bool(false)
            }
            if op == "||" {
                let l = try self.eval(lhsExpr, env: env)
                return l.isTruthy ? .bool(true) : .bool((try self.eval(rhsExpr, env: env)).isTruthy)
            }
            let l = try self.eval(lhsExpr, env: env)
            let r = try self.eval(rhsExpr, env: env)
            switch op {
            case "+":
                if case let .string(a) = l {
                    let b = r.asString
                    guard a.utf8.count + b.utf8.count <= Self.maxStringBytes else {
                        throw FullGramPluginError("Rust string size limit exceeded")
                    }
                    return .string(a + b)
                }
                if case .int = l, case .int = r { return .int((l.asInt ?? 0) &+ (r.asInt ?? 0)) }
                return .double((l.asDouble ?? 0.0) + (r.asDouble ?? 0.0))
            case "-":
                if case .int = l, case .int = r { return .int((l.asInt ?? 0) &- (r.asInt ?? 0)) }
                return .double((l.asDouble ?? 0.0) - (r.asDouble ?? 0.0))
            case "*":
                if case .int = l, case .int = r { return .int((l.asInt ?? 0) &* (r.asInt ?? 0)) }
                return .double((l.asDouble ?? 0.0) * (r.asDouble ?? 0.0))
            case "/":
                if case .int = l, case .int = r {
                    let li = l.asInt ?? 0
                    let ri = r.asInt ?? 0
                    if ri == 0 { return .int(0) }
                    if li == Int64.min && ri == -1 { return .int(Int64.max) }
                    return .int(li / ri)
                }
                let rd = r.asDouble ?? 0.0
                return rd == 0.0 ? .double(0) : .double((l.asDouble ?? 0.0) / rd)
            case "%":
                let li = l.asInt ?? 0
                let ri = r.asInt ?? 0
                if ri == 0 { return .int(0) }
                if li == Int64.min && ri == -1 { return .int(0) }
                return .int(li % ri)
            case "==": return .bool(Self.valuesEqual(l, r))
            case "!=": return .bool(!Self.valuesEqual(l, r))
            case "<": return .bool((l.asDouble ?? 0.0) < (r.asDouble ?? 0.0))
            case "<=": return .bool((l.asDouble ?? 0.0) <= (r.asDouble ?? 0.0))
            case ">": return .bool((l.asDouble ?? 0.0) > (r.asDouble ?? 0.0))
            case ">=": return .bool((l.asDouble ?? 0.0) >= (r.asDouble ?? 0.0))
            case "..":
                let start = l.asInt ?? 0
                let end = r.asInt ?? 0
                let (span, overflow) = end.subtractingReportingOverflow(start)
                guard !overflow && end > start && span <= 10_000 else { return .table(FullGramPluginTableBox()) }
                return .table(FullGramPluginTableBox(array: (start..<end).map { .int($0) }))
            case "..=":
                let start = l.asInt ?? 0
                let end = r.asInt ?? 0
                let (span, overflow) = end.subtractingReportingOverflow(start)
                guard !overflow && end >= start && span <= 10_000 else { return .table(FullGramPluginTableBox()) }
                return .table(FullGramPluginTableBox(array: (start...end).map { .int($0) }))
            default:
                return .nil
            }
        case let .path(baseExpr, name):
            let base = try self.eval(baseExpr, env: env)
            if case let .table(box) = base {
                return box.get(key: .string(name))
            }
            return .string(name)
        case let .member(objExpr, key):
            let obj = try self.eval(objExpr, env: env)
            if case let .table(box) = obj {
                return box.get(key: .string(key))
            }
            return .nil
        case let .index(objExpr, idxExpr):
            let obj = try self.eval(objExpr, env: env)
            let key = try self.eval(idxExpr, env: env)
            if case let .table(box) = obj {
                if case let .int(i) = key {
                    if i >= 0 && i < Int64(box.arrayPart.count) {
                        return box.arrayPart[Int(i)]
                    }
                    if !box.arrayPart.isEmpty {
                        return .nil
                    }
                }
                return box.get(key: key)
            }
            if case let .string(s) = obj {
                let i = Int(key.asInt ?? -1)
                if i >= 0 && i < s.count {
                    let sIdx = s.index(s.startIndex, offsetBy: i)
                    return .string(String(s[sIdx]))
                }
            }
            return .nil
        case let .call(calleeExpr, argExprs):
            let callee = try self.eval(calleeExpr, env: env)
            let args = try argExprs.map { try self.eval($0, env: env) }
            if case let .function(fn) = callee {
                return try fn(args)
            }
            return .nil
        case let .methodCall(objExpr, method, argExprs):
            let obj = try self.eval(objExpr, env: env)
            let args = try argExprs.map { try self.eval($0, env: env) }
            return try self.evalMethodCall(target: obj, method: method, args: args)
        }
    }

    private func evalMethodCall(target: FullGramPluginValue, method: String, args: [FullGramPluginValue]) throws -> FullGramPluginValue {
        switch method {
        case "to_string", "as_str":
            return .string(target.asString)
        case "clone":
            if case let .table(box) = target {
                let copy = FullGramPluginTableBox()
                copy.arrayPart = box.arrayPart
                copy.mapPart = box.mapPart
                copy.orderedKeys = box.orderedKeys
                return .table(copy)
            }
            return target
        case "unwrap", "unwrap_or":
            if case .nil = target { return args.first ?? .nil }
            return target
        case "is_some":
            if case .nil = target { return .bool(false) }
            return .bool(true)
        case "is_none":
            if case .nil = target { return .bool(true) }
            return .bool(false)
        case "parse":
            if let i = Int64(target.asString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .int(i)
            }
            if let d = Double(target.asString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .double(d)
            }
            return .nil
        default:
            break
        }

        switch target {
        case let .string(s):
            switch method {
            case "len": return .int(Int64(s.count))
            case "is_empty": return .bool(s.isEmpty)
            case "trim": return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
            case "to_lowercase": return .string(s.lowercased())
            case "to_uppercase": return .string(s.uppercased())
            case "contains": return .bool(s.contains(args.first?.asString ?? ""))
            case "starts_with": return .bool(s.hasPrefix(args.first?.asString ?? ""))
            case "ends_with": return .bool(s.hasSuffix(args.first?.asString ?? ""))
            case "replace":
                let from = args.first?.asString ?? ""
                let to = args.count > 1 ? args[1].asString : ""
                return .string(s.replacingOccurrences(of: from, with: to))
            case "split":
                let sep = args.first?.asString ?? " "
                let parts = sep.isEmpty
                    ? s.map { FullGramPluginValue.string(String($0)) }
                    : s.components(separatedBy: sep).map { FullGramPluginValue.string($0) }
                return .table(FullGramPluginTableBox(array: parts))
            case "chars":
                return .table(FullGramPluginTableBox(array: s.map { .string(String($0)) }))
            default: return .nil
            }
        case let .table(box):
            switch method {
            case "len": return .int(Int64(box.arrayPart.isEmpty ? box.mapPart.count : box.arrayPart.count))
            case "is_empty": return .bool(box.arrayPart.isEmpty && box.mapPart.isEmpty)
            case "get":
                guard let key = args.first else { return .nil }
                return box.get(key: key)
            case "insert":
                if args.count >= 2, box.mapPart.count < Self.maxCollectionItems { box.set(key: args[0], value: args[1]) }
                return .nil
            case "push":
                if let val = args.first, box.arrayPart.count < Self.maxCollectionItems { box.arrayPart.append(val) }
                return .nil
            case "pop":
                return box.arrayPart.popLast() ?? .nil
            case "join":
                let sep = args.first?.asString ?? ""
                var totalBytes = 0
                var parts: [String] = []
                parts.reserveCapacity(box.arrayPart.count)
                for item in box.arrayPart {
                    let p = item.asString
                    totalBytes += p.utf8.count + (parts.isEmpty ? 0 : sep.utf8.count)
                    guard totalBytes <= Self.maxStringBytes else {
                        throw FullGramPluginError("Rust string size limit exceeded")
                    }
                    parts.append(p)
                }
                return .string(parts.joined(separator: sep))
            case "contains":
                let targetVal = args.first ?? .nil
                if !box.arrayPart.isEmpty {
                    return .bool(box.arrayPart.contains { Self.valuesEqual($0, targetVal) })
                }
                return .bool(!Self.valuesEqual(box.get(key: targetVal), .nil))
            case "map":
                if case let .function(fn) = args.first {
                    let mapped = try box.arrayPart.map { try fn([$0]) }
                    return .table(FullGramPluginTableBox(array: mapped))
                }
                return .table(box)
            case "filter":
                if case let .function(fn) = args.first {
                    let filtered = try box.arrayPart.filter { try fn([$0]).isTruthy }
                    return .table(FullGramPluginTableBox(array: filtered))
                }
                return .table(box)
            default:
                if case let .function(fn) = box.get(key: .string(method)) {
                    return try fn(args)
                }
                return .nil
            }
        default:
            return .nil
        }
    }

    private static func valuesEqual(_ a: FullGramPluginValue, _ b: FullGramPluginValue) -> Bool {
        switch (a, b) {
        case (.nil, .nil): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case let (.double(x), .double(y)): return x == y
        case let (.int(x), .double(y)): return Double(x) == y
        case let (.double(x), .int(y)): return x == Double(y)
        case let (.string(x), .string(y)): return x == y
        default: return false
        }
    }
}

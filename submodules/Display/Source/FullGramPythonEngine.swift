import Foundation

private enum PyTokenKind: Equatable {
    case eof
    case newline
    case indent
    case dedent
    case ident(String)
    case number(Double, Bool)
    case string(String)
    case fString(String)
    case `if`, elif, `else`, `for`, `in`, `while`, `break`, `continue`, `pass`, `def`, `return`, `import`, from, `as`, `try`, except, `lambda`, `true`, `false`, none, and, or, not, `is`
    case plus, minus, star, starStar, slash, slashSlash, percent
    case assign, plusAssign, minusAssign, starAssign
    case eq, neq, lt, lte, gt, gte
    case colon, comma, dot, at, lParen, rParen, lBracket, rBracket, lBrace, rBrace
}

private struct PyToken {
    let kind: PyTokenKind
    let line: Int
}

private struct PyLexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    init(source: String) {
        self.chars = Array(source.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    mutating func tokenize() throws -> [PyToken] {
        var tokens: [PyToken] = []
        var indentStack: [Int] = [0]
        var atLineStart = true
        var bracketDepth = 0

        while self.pos < self.chars.count {
            if atLineStart && bracketDepth == 0 {
                var spaces = 0
                while self.pos < self.chars.count {
                    let c = self.chars[self.pos]
                    if c == " " { spaces += 1; self.pos += 1 }
                    else if c == "\t" { spaces += 4; self.pos += 1 }
                    else { break }
                }
                if self.pos >= self.chars.count { break }
                let c = self.chars[self.pos]
                if c == "\n" {
                    self.pos += 1
                    self.line += 1
                    continue
                }
                if c == "#" {
                    while self.pos < self.chars.count && self.chars[self.pos] != "\n" { self.pos += 1 }
                    continue
                }
                let currentIndent = indentStack.last ?? 0
                if spaces > currentIndent {
                    indentStack.append(spaces)
                    tokens.append(PyToken(kind: .indent, line: self.line))
                } else if spaces < currentIndent {
                    while let top = indentStack.last, top > spaces {
                        indentStack.removeLast()
                        tokens.append(PyToken(kind: .dedent, line: self.line))
                    }
                    if indentStack.last != spaces {
                        throw FullGramPluginError("Python line \(self.line): inconsistent indentation")
                    }
                }
                atLineStart = false
            }

            if self.pos >= self.chars.count { break }
            let c = self.chars[self.pos]

            if c == " " || c == "\t" {
                self.pos += 1
                continue
            }
            if c == "#" {
                while self.pos < self.chars.count && self.chars[self.pos] != "\n" { self.pos += 1 }
                continue
            }
            if c == "\n" {
                self.pos += 1
                self.line += 1
                if bracketDepth == 0 {
                    tokens.append(PyToken(kind: .newline, line: self.line - 1))
                    atLineStart = true
                }
                continue
            }
            if c == "\\" && self.peek(1) == "\n" {
                self.pos += 2
                self.line += 1
                continue
            }

            let tokLine = self.line
            if (c == "f" || c == "F" || c == "r" || c == "R"), let next = self.peek(1), (next == "\"" || next == "'") {
                let isF = (c == "f" || c == "F")
                let isRaw = (c == "r" || c == "R")
                self.pos += 1
                let s = try self.readString(raw: isRaw)
                tokens.append(PyToken(kind: isF ? .fString(s) : .string(s), line: tokLine))
            } else if c == "\"" || c == "'" {
                tokens.append(PyToken(kind: .string(try self.readString(raw: false)), line: tokLine))
            } else if c.isNumber || (c == "." && self.peek(1)?.isNumber == true) {
                tokens.append(try self.readNumber(line: tokLine))
            } else if c.isLetter || c == "_" {
                let ident = self.readIdent()
                tokens.append(PyToken(kind: Self.keywordOrIdent(ident), line: tokLine))
            } else {
                let tok = try self.readSymbol(line: tokLine)
                switch tok.kind {
                case .lParen, .lBracket, .lBrace: bracketDepth += 1
                case .rParen, .rBracket, .rBrace: bracketDepth = max(0, bracketDepth - 1)
                default: break
                }
                tokens.append(tok)
            }
        }

        if let last = tokens.last, last.kind != .newline && last.kind != .dedent {
            tokens.append(PyToken(kind: .newline, line: self.line))
        }
        while indentStack.count > 1 {
            indentStack.removeLast()
            tokens.append(PyToken(kind: .dedent, line: self.line))
        }
        tokens.append(PyToken(kind: .eof, line: self.line))
        return tokens
    }

    private func peek(_ offset: Int) -> Character? {
        let i = self.pos + offset
        return i < self.chars.count ? self.chars[i] : nil
    }

    private mutating func advance() -> Character {
        let c = self.chars[self.pos]
        self.pos += 1
        if c == "\n" { self.line += 1 }
        return c
    }

    private mutating func readString(raw: Bool) throws -> String {
        let quote = self.advance()
        var triple = false
        if self.peek(0) == quote && self.peek(1) == quote {
            triple = true
            self.pos += 2
        }
        var out = ""
        while self.pos < self.chars.count {
            let c = self.advance()
            if triple {
                if c == quote && self.peek(0) == quote && self.peek(1) == quote {
                    self.pos += 2
                    return out
                }
            } else {
                if c == quote { return out }
                if c == "\n" { throw FullGramPluginError("Python line \(self.line): EOL while scanning string") }
            }
            if c == "\\" && !raw {
                guard self.pos < self.chars.count else { break }
                let esc = self.advance()
                switch esc {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "'": out.append("'")
                default: out.append(esc)
                }
            } else {
                out.append(c)
            }
        }
        throw FullGramPluginError("Python line \(self.line): unterminated string literal")
    }

    private mutating func readNumber(line: Int) throws -> PyToken {
        var raw = ""
        var isFloat = false
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isNumber || c == "_" {
                if c != "_" { raw.append(c) }
                self.pos += 1
            } else if c == "." && !isFloat {
                isFloat = true
                raw.append(self.advance())
            } else if c == "e" || c == "E" {
                isFloat = true
                raw.append(self.advance())
                if self.pos < self.chars.count && (self.chars[self.pos] == "+" || self.chars[self.pos] == "-") {
                    raw.append(self.advance())
                }
            } else {
                break
            }
        }
        guard let d = Double(raw) else {
            throw FullGramPluginError("Python line \(line): invalid number '\(raw)'")
        }
        return PyToken(kind: .number(d, !isFloat && d == d.rounded()), line: line)
    }

    private mutating func readIdent() -> String {
        var s = ""
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isLetter || c.isNumber || c == "_" {
                s.append(self.advance())
            } else {
                break
            }
        }
        return s
    }

    private mutating func readSymbol(line: Int) throws -> PyToken {
        let c = self.advance()
        switch c {
        case "+":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .plusAssign, line: line) }
            return PyToken(kind: .plus, line: line)
        case "-":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .minusAssign, line: line) }
            return PyToken(kind: .minus, line: line)
        case "*":
            if self.peek(0) == "*" { self.pos += 1; return PyToken(kind: .starStar, line: line) }
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .starAssign, line: line) }
            return PyToken(kind: .star, line: line)
        case "/":
            if self.peek(0) == "/" { self.pos += 1; return PyToken(kind: .slashSlash, line: line) }
            return PyToken(kind: .slash, line: line)
        case "%": return PyToken(kind: .percent, line: line)
        case "=":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .eq, line: line) }
            return PyToken(kind: .assign, line: line)
        case "!":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .neq, line: line) }
            throw FullGramPluginError("Python line \(line): unexpected '!'")
        case "<":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .lte, line: line) }
            return PyToken(kind: .lt, line: line)
        case ">":
            if self.peek(0) == "=" { self.pos += 1; return PyToken(kind: .gte, line: line) }
            return PyToken(kind: .gt, line: line)
        case ":": return PyToken(kind: .colon, line: line)
        case ",": return PyToken(kind: .comma, line: line)
        case ".": return PyToken(kind: .dot, line: line)
        case "@": return PyToken(kind: .at, line: line)
        case "(": return PyToken(kind: .lParen, line: line)
        case ")": return PyToken(kind: .rParen, line: line)
        case "[": return PyToken(kind: .lBracket, line: line)
        case "]": return PyToken(kind: .rBracket, line: line)
        case "{": return PyToken(kind: .lBrace, line: line)
        case "}": return PyToken(kind: .rBrace, line: line)
        default:
            throw FullGramPluginError("Python line \(line): unexpected character '\(c)'")
        }
    }

    private static func keywordOrIdent(_ s: String) -> PyTokenKind {
        switch s {
        case "if": return .if
        case "elif": return .elif
        case "else": return .else
        case "for": return .for
        case "in": return .in
        case "while": return .while
        case "break": return .break
        case "continue": return .continue
        case "pass": return .pass
        case "def": return .def
        case "return": return .return
        case "import": return .import
        case "from": return .from
        case "as": return .as
        case "try": return .try
        case "except": return .except
        case "lambda": return .lambda
        case "True": return .true
        case "False": return .false
        case "None": return .none
        case "and": return .and
        case "or": return .or
        case "not": return .not
        case "is": return .is
        default: return .ident(s)
        }
    }
}

private enum PyCompareOp {
    case eq, neq, lt, lte, gt, gte, `in`, notIn, `is`, isNot
}

private indirect enum PyExpr {
    case none
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case fString(String)
    case ident(String)
    case list([PyExpr])
    case listComp(PyExpr, String, PyExpr, PyExpr?)
    case dict([(PyExpr, PyExpr)])
    case tuple([PyExpr])
    case unary(PyTokenKind, PyExpr)
    case binary(PyTokenKind, PyExpr, PyExpr)
    case compare(PyCompareOp, PyExpr, PyExpr)
    case ternary(PyExpr, PyExpr, PyExpr)
    case attr(PyExpr, String)
    case `subscript`(PyExpr, PyExpr)
    case slice(PyExpr, PyExpr?, PyExpr?)
    case call(PyExpr, [PyExpr], [(String, PyExpr)])
    case lambda([String], PyExpr)
}

private indirect enum PyStmt {
    case pass
    case expr(PyExpr)
    case assign(PyExpr, PyExpr)
    case augAssign(PyExpr, PyTokenKind, PyExpr)
    case ifStmt([(PyExpr, [PyStmt])], [PyStmt]?)
    case whileStmt(PyExpr, [PyStmt])
    case forStmt([String], PyExpr, [PyStmt])
    case defStmt(String, [(String, PyExpr?)], [PyStmt], [PyExpr]) // name, params(name, default), body, decorators
    case returnStmt(PyExpr?)
    case breakStmt
    case continueStmt
    case tryStmt([PyStmt], String?, [PyStmt])
    case importStmt(String, String?) // module, alias
    case fromImportStmt(String, [(String, String?)])
}

private struct PyParser {
    private let tokens: [PyToken]
    private var pos = 0

    init(tokens: [PyToken]) {
        self.tokens = tokens
    }

    private var current: PyToken {
        return self.pos < self.tokens.count ? self.tokens[self.pos] : PyToken(kind: .eof, line: 0)
    }

    private func peek(_ offset: Int = 1) -> PyToken {
        let i = self.pos + offset
        return i < self.tokens.count ? self.tokens[i] : PyToken(kind: .eof, line: 0)
    }

    @discardableResult
    private mutating func consume() -> PyToken {
        let t = self.current
        self.pos += 1
        return t
    }

    private mutating func match(_ kind: PyTokenKind) -> Bool {
        if self.current.kind == kind {
            self.pos += 1
            return true
        }
        return false
    }

    private mutating func expect(_ kind: PyTokenKind, _ msg: String) throws {
        guard self.current.kind == kind else {
            throw FullGramPluginError("Python line \(self.current.line): expected \(msg)")
        }
        self.pos += 1
    }

    private mutating func skipNewlines() {
        while self.current.kind == .newline { self.pos += 1 }
    }

    mutating func parseModule() throws -> [PyStmt] {
        var stmts: [PyStmt] = []
        self.skipNewlines()
        while self.current.kind != .eof {
            stmts.append(try self.parseStmt())
            self.skipNewlines()
        }
        return stmts
    }

    private mutating func parseSuite() throws -> [PyStmt] {
        if self.match(.newline) {
            try self.expect(.indent, "indented block")
            var stmts: [PyStmt] = []
            self.skipNewlines()
            while self.current.kind != .dedent && self.current.kind != .eof {
                stmts.append(try self.parseStmt())
                self.skipNewlines()
            }
            _ = self.match(.dedent)
            return stmts
        } else {
            let single = try self.parseSimpleStmt()
            return [single]
        }
    }

    private mutating func parseStmt(decorators: [PyExpr] = []) throws -> PyStmt {
        switch self.current.kind {
        case .at:
            self.pos += 1
            let deco = try self.parseExpr()
            try self.expect(.newline, "newline after decorator")
            self.skipNewlines()
            return try self.parseStmt(decorators: decorators + [deco])
        case .def:
            self.pos += 1
            guard case let .ident(name) = self.current.kind else {
                throw FullGramPluginError("Python line \(self.current.line): expected function name")
            }
            self.pos += 1
            try self.expect(.lParen, "'('")
            var params: [(String, PyExpr?)] = []
            while self.current.kind != .rParen && self.current.kind != .eof {
                guard case let .ident(pName) = self.current.kind else {
                    throw FullGramPluginError("Python line \(self.current.line): expected parameter name")
                }
                self.pos += 1
                var defVal: PyExpr?
                if self.match(.assign) {
                    defVal = try self.parseExpr()
                }
                params.append((pName, defVal))
                if !self.match(.comma) { break }
            }
            try self.expect(.rParen, "')'")
            try self.expect(.colon, "':'")
            let body = try self.parseSuite()
            return .defStmt(name, params, body, decorators)
        case .if:
            self.pos += 1
            var branches: [(PyExpr, [PyStmt])] = []
            let cond = try self.parseExpr()
            try self.expect(.colon, "':'")
            let body = try self.parseSuite()
            branches.append((cond, body))
            while self.current.kind == .elif {
                self.pos += 1
                let c = try self.parseExpr()
                try self.expect(.colon, "':'")
                let b = try self.parseSuite()
                branches.append((c, b))
            }
            var elseBody: [PyStmt]?
            if self.match(.else) {
                try self.expect(.colon, "':'")
                elseBody = try self.parseSuite()
            }
            return .ifStmt(branches, elseBody)
        case .while:
            self.pos += 1
            let cond = try self.parseExpr()
            try self.expect(.colon, "':'")
            return .whileStmt(cond, try self.parseSuite())
        case .for:
            self.pos += 1
            var targets: [String] = []
            repeat {
                guard case let .ident(v) = self.current.kind else {
                    throw FullGramPluginError("Python line \(self.current.line): expected loop variable")
                }
                self.pos += 1
                targets.append(v)
            } while self.match(.comma)
            try self.expect(.in, "'in'")
            let iter = try self.parseExpr()
            try self.expect(.colon, "':'")
            return .forStmt(targets, iter, try self.parseSuite())
        case .try:
            self.pos += 1
            try self.expect(.colon, "':'")
            let tryBody = try self.parseSuite()
            self.skipNewlines()
            try self.expect(.except, "'except'")
            var errVar: String?
            if self.current.kind != .colon {
                if case .ident = self.current.kind { self.pos += 1 }
                if self.match(.as), case let .ident(name) = self.current.kind {
                    errVar = name
                    self.pos += 1
                }
            }
            try self.expect(.colon, "':'")
            let exceptBody = try self.parseSuite()
            return .tryStmt(tryBody, errVar, exceptBody)
        default:
            return try self.parseSimpleStmt()
        }
    }

    private mutating func parseSimpleStmt() throws -> PyStmt {
        defer { _ = self.match(.newline) }
        switch self.current.kind {
        case .pass: self.pos += 1; return .pass
        case .break: self.pos += 1; return .breakStmt
        case .continue: self.pos += 1; return .continueStmt
        case .return:
            self.pos += 1
            if self.current.kind == .newline || self.current.kind == .eof || self.current.kind == .dedent {
                return .returnStmt(nil)
            }
            return .returnStmt(try self.parseExprOrTuple())
        case .import:
            self.pos += 1
            guard case let .ident(mod) = self.current.kind else {
                throw FullGramPluginError("Python line \(self.current.line): expected module name")
            }
            self.pos += 1
            var alias: String?
            if self.match(.as), case let .ident(a) = self.current.kind {
                alias = a; self.pos += 1
            }
            return .importStmt(mod, alias)
        case .from:
            self.pos += 1
            guard case let .ident(mod) = self.current.kind else {
                throw FullGramPluginError("Python line \(self.current.line): expected module name")
            }
            self.pos += 1
            try self.expect(.import, "'import'")
            var items: [(String, String?)] = []
            repeat {
                guard case let .ident(sym) = self.current.kind else { break }
                self.pos += 1
                var alias: String?
                if self.match(.as), case let .ident(a) = self.current.kind {
                    alias = a; self.pos += 1
                }
                items.append((sym, alias))
            } while self.match(.comma)
            return .fromImportStmt(mod, items)
        default:
            let lhs = try self.parseExprOrTuple()
            if self.match(.assign) {
                return .assign(lhs, try self.parseExprOrTuple())
            }
            if [.plusAssign, .minusAssign, .starAssign].contains(self.current.kind) {
                let op = self.consume().kind
                return .augAssign(lhs, op, try self.parseExpr())
            }
            return .expr(lhs)
        }
    }

    private mutating func parseExprOrTuple() throws -> PyExpr {
        let first = try self.parseExpr()
        if self.match(.comma) {
            var items = [first]
            if ![.newline, .eof, .assign, .rParen].contains(self.current.kind) {
                items.append(try self.parseExpr())
                while self.match(.comma) {
                    items.append(try self.parseExpr())
                }
            }
            return .tuple(items)
        }
        return first
    }

    mutating func parseExpr() throws -> PyExpr {
        if self.match(.lambda) {
            var params: [String] = []
            if self.current.kind != .colon {
                repeat {
                    guard case let .ident(p) = self.current.kind else {
                        throw FullGramPluginError("Python line \(self.current.line): expected lambda param")
                    }
                    params.append(p); self.pos += 1
                } while self.match(.comma)
            }
            try self.expect(.colon, "':'")
            return .lambda(params, try self.parseExpr())
        }
        let expr = try self.parseOr()
        if self.match(.if) {
            let cond = try self.parseOr()
            try self.expect(.else, "'else'")
            let falsy = try self.parseExpr()
            return .ternary(cond, expr, falsy)
        }
        return expr
    }

    private mutating func parseOr() throws -> PyExpr {
        var lhs = try self.parseAnd()
        while self.match(.or) { lhs = .binary(.or, lhs, try self.parseAnd()) }
        return lhs
    }

    private mutating func parseAnd() throws -> PyExpr {
        var lhs = try self.parseNot()
        while self.match(.and) { lhs = .binary(.and, lhs, try self.parseNot()) }
        return lhs
    }

    private mutating func parseNot() throws -> PyExpr {
        if self.match(.not) { return .unary(.not, try self.parseNot()) }
        return try self.parseCmp()
    }

    private mutating func parseCmp() throws -> PyExpr {
        var lhs = try self.parseAdd()
        while true {
            if self.match(.eq) { lhs = .compare(.eq, lhs, try self.parseAdd()) }
            else if self.match(.neq) { lhs = .compare(.neq, lhs, try self.parseAdd()) }
            else if self.match(.lt) { lhs = .compare(.lt, lhs, try self.parseAdd()) }
            else if self.match(.lte) { lhs = .compare(.lte, lhs, try self.parseAdd()) }
            else if self.match(.gt) { lhs = .compare(.gt, lhs, try self.parseAdd()) }
            else if self.match(.gte) { lhs = .compare(.gte, lhs, try self.parseAdd()) }
            else if self.match(.in) { lhs = .compare(.in, lhs, try self.parseAdd()) }
            else if self.current.kind == .not && self.peek().kind == .in {
                self.pos += 2
                lhs = .compare(.notIn, lhs, try self.parseAdd())
            } else if self.match(.is) {
                if self.match(.not) {
                    lhs = .compare(.isNot, lhs, try self.parseAdd())
                } else {
                    lhs = .compare(.is, lhs, try self.parseAdd())
                }
            } else { break }
        }
        return lhs
    }

    private mutating func parseAdd() throws -> PyExpr {
        var lhs = try self.parseMul()
        while self.current.kind == .plus || self.current.kind == .minus {
            let op = self.consume().kind
            lhs = .binary(op, lhs, try self.parseMul())
        }
        return lhs
    }

    private mutating func parseMul() throws -> PyExpr {
        var lhs = try self.parseUnary()
        while [.star, .slash, .slashSlash, .percent].contains(self.current.kind) {
            let op = self.consume().kind
            lhs = .binary(op, lhs, try self.parseUnary())
        }
        return lhs
    }

    private mutating func parseUnary() throws -> PyExpr {
        if self.match(.minus) { return .unary(.minus, try self.parseUnary()) }
        if self.match(.plus) { return try self.parseUnary() }
        return try self.parsePower()
    }

    private mutating func parsePower() throws -> PyExpr {
        let lhs = try self.parsePostfix()
        if self.match(.starStar) { return .binary(.starStar, lhs, try self.parseUnary()) }
        return lhs
    }

    private mutating func parsePostfix() throws -> PyExpr {
        var expr = try self.parsePrimary()
        while true {
            if self.match(.dot) {
                guard case let .ident(name) = self.current.kind else {
                    throw FullGramPluginError("Python line \(self.current.line): expected attribute name")
                }
                self.pos += 1
                expr = .attr(expr, name)
            } else if self.match(.lParen) {
                var args: [PyExpr] = []
                var kwargs: [(String, PyExpr)] = []
                while self.current.kind != .rParen && self.current.kind != .eof {
                    if case let .ident(k) = self.current.kind, self.peek().kind == .assign {
                        self.pos += 2
                        kwargs.append((k, try self.parseExpr()))
                    } else {
                        args.append(try self.parseExpr())
                    }
                    if !self.match(.comma) { break }
                }
                try self.expect(.rParen, "')'")
                expr = .call(expr, args, kwargs)
            } else if self.match(.lBracket) {
                var start: PyExpr?
                if self.current.kind != .colon { start = try self.parseExpr() }
                if self.match(.colon) {
                    var end: PyExpr?
                    if self.current.kind != .rBracket { end = try self.parseExpr() }
                    try self.expect(.rBracket, "']'")
                    expr = .slice(expr, start, end)
                } else {
                    try self.expect(.rBracket, "']'")
                    expr = .subscript(expr, start ?? .none)
                }
            } else { break }
        }
        return expr
    }

    private mutating func parsePrimary() throws -> PyExpr {
        switch self.current.kind {
        case .none: self.pos += 1; return .none
        case .true: self.pos += 1; return .bool(true)
        case .false: self.pos += 1; return .bool(false)
        case let .number(val, isInt):
            self.pos += 1
            return isInt ? .int(Int64(val)) : .double(val)
        case let .string(s): self.pos += 1; return .string(s)
        case let .fString(s): self.pos += 1; return .fString(s)
        case let .ident(id): self.pos += 1; return .ident(id)
        case .lParen:
            self.pos += 1
            if self.match(.rParen) { return .tuple([]) }
            let first = try self.parseExpr()
            if self.match(.comma) {
                var items = [first]
                while self.current.kind != .rParen && self.current.kind != .eof {
                    items.append(try self.parseExpr())
                    if !self.match(.comma) { break }
                }
                try self.expect(.rParen, "')'")
                return .tuple(items)
            }
            try self.expect(.rParen, "')'")
            return first
        case .lBracket:
            self.pos += 1
            if self.match(.rBracket) { return .list([]) }
            let first = try self.parseExpr()
            if self.match(.for) {
                guard case let .ident(varName) = self.current.kind else {
                    throw FullGramPluginError("Python line \(self.current.line): expected comprehension variable")
                }
                self.pos += 1
                try self.expect(.in, "'in'")
                let iter = try self.parseOr()
                var cond: PyExpr?
                if self.match(.if) { cond = try self.parseOr() }
                try self.expect(.rBracket, "']'")
                return .listComp(first, varName, iter, cond)
            }
            var items = [first]
            while self.match(.comma) {
                if self.current.kind == .rBracket { break }
                items.append(try self.parseExpr())
            }
            try self.expect(.rBracket, "']'")
            return .list(items)
        case .lBrace:
            self.pos += 1
            var pairs: [(PyExpr, PyExpr)] = []
            while self.current.kind != .rBrace && self.current.kind != .eof {
                let k = try self.parseExpr()
                try self.expect(.colon, "':'")
                let v = try self.parseExpr()
                pairs.append((k, v))
                if !self.match(.comma) { break }
            }
            try self.expect(.rBrace, "'}'")
            return .dict(pairs)
        default:
            throw FullGramPluginError("Python line \(self.current.line): unexpected token \(self.current.kind)")
        }
    }
}

private final class PyEnv {
    let parent: PyEnv?
    var vars: [String: FullGramPluginValue] = [:]

    init(parent: PyEnv? = nil) {
        self.parent = parent
    }

    func get(_ name: String) -> FullGramPluginValue? {
        if let v = self.vars[name] { return v }
        return self.parent?.get(name)
    }

    func set(_ name: String, _ value: FullGramPluginValue) {
        self.vars[name] = value
    }
}

private enum PySignal: Error {
    case returnValue(FullGramPluginValue)
    case breakLoop
    case continueLoop
}

public final class FullGramPythonVM {
    private let globalEnv = PyEnv()
    private let vmLock = NSRecursiveLock()
    private var modules: [String: FullGramPluginValue] = [:]
    private var steps = 0
    private let maxSteps = 120_000
    private var callDepth = 0
    private let maxCallDepth = 64

    public init(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        self.registerBuiltins(hostAPI: hostAPI, printHandler: printHandler)
    }

    public func load(code: String) throws {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        self.steps = 0
        self.callDepth = 0
        var lexer = PyLexer(source: code)
        let tokens = try lexer.tokenize()
        var parser = PyParser(tokens: tokens)
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

    public func getGlobal(_ name: String) -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        return self.globalEnv.get(name) ?? .nil
    }

    private func enterCall() throws {
        self.callDepth += 1
        if self.callDepth > self.maxCallDepth {
            throw FullGramPluginError("Python recursion limit exceeded (\(self.maxCallDepth))")
        }
    }

    private func tick() throws {
        self.steps += 1
        if self.steps > self.maxSteps {
            throw FullGramPluginError("Python execution exceeded step limit (\(self.maxSteps))")
        }
    }

    private func execBlock(_ stmts: [PyStmt], env: PyEnv) throws {
        for stmt in stmts {
            try self.tick()
            switch stmt {
            case .pass: break
            case let .expr(e): _ = try self.evalExpr(e, env: env)
            case let .assign(target, valExpr):
                let val = try self.evalExpr(valExpr, env: env)
                try self.assignTarget(target, value: val, env: env)
            case let .augAssign(target, op, valExpr):
                let cur = try self.evalExpr(target, env: env)
                let rhs = try self.evalExpr(valExpr, env: env)
                let mappedOp: PyTokenKind = op == .plusAssign ? .plus : (op == .minusAssign ? .minus : .star)
                let next = try self.evalBinary(mappedOp, cur, rhs)
                try self.assignTarget(target, value: next, env: env)
            case let .ifStmt(branches, elseBody):
                var matched = false
                for (cond, body) in branches {
                    if try self.evalExpr(cond, env: env).isTruthy {
                        try self.execBlock(body, env: env)
                        matched = true
                        break
                    }
                }
                if !matched, let elseBody { try self.execBlock(elseBody, env: env) }
            case let .whileStmt(cond, body):
                while try self.evalExpr(cond, env: env).isTruthy {
                    try self.tick()
                    do {
                        try self.execBlock(body, env: env)
                    } catch PySignal.continueLoop { continue }
                    catch PySignal.breakLoop { break }
                }
            case let .forStmt(targets, iterExpr, body):
                let items = self.iterableItems(try self.evalExpr(iterExpr, env: env))
                for item in items {
                    try self.tick()
                    if targets.count == 1 {
                        env.set(targets[0], item)
                    } else if case let .list(tupleItems) = item {
                        for (i, t) in targets.enumerated() {
                            env.set(t, i < tupleItems.count ? tupleItems[i] : .nil)
                        }
                    }
                    do {
                        try self.execBlock(body, env: env)
                    } catch PySignal.continueLoop { continue }
                    catch PySignal.breakLoop { break }
                }
            case let .defStmt(name, params, body, decorators):
                let defaultVals = try params.map { ($0.0, try $0.1.map { try self.evalExpr($0, env: env) }) }
                var fn: FullGramPluginValue = .function { [weak self] args in
                    guard let self else { return .nil }
                    try self.enterCall()
                    defer { self.callDepth -= 1 }
                    let fnEnv = PyEnv(parent: env)
                    for (i, (pName, defVal)) in defaultVals.enumerated() {
                        if i < args.count { fnEnv.set(pName, args[i]) }
                        else if let defVal { fnEnv.set(pName, defVal) }
                        else { fnEnv.set(pName, .nil) }
                    }
                    do {
                        try self.execBlock(body, env: fnEnv)
                        return .nil
                    } catch let PySignal.returnValue(ret) {
                        return ret
                    }
                }
                for deco in decorators.reversed() {
                    if case let .function(decoFn) = try self.evalExpr(deco, env: env) {
                        fn = try decoFn([fn])
                    }
                }
                env.set(name, fn)
            case let .returnStmt(expr):
                let val = try expr.map { try self.evalExpr($0, env: env) } ?? .nil
                throw PySignal.returnValue(val)
            case .breakStmt: throw PySignal.breakLoop
            case .continueStmt: throw PySignal.continueLoop
            case let .tryStmt(tryBody, errVar, exceptBody):
                do {
                    try self.execBlock(tryBody, env: env)
                } catch let e as PySignal {
                    throw e
                } catch {
                    if let errVar { env.set(errVar, .string(error.localizedDescription)) }
                    try self.execBlock(exceptBody, env: env)
                }
            case let .importStmt(mod, alias):
                let modVal = self.modules[mod] ?? .nil
                env.set(alias ?? mod, modVal)
            case let .fromImportStmt(mod, items):
                let modVal = self.modules[mod]
                for (sym, alias) in items {
                    if case let .table(box)? = modVal {
                        env.set(alias ?? sym, box.get(key: .string(sym)))
                    }
                }
            }
        }
    }

    private func assignTarget(_ target: PyExpr, value: FullGramPluginValue, env: PyEnv) throws {
        switch target {
        case let .ident(name):
            env.set(name, value)
        case let .tuple(items):
            if case let .list(vals) = value {
                for (i, t) in items.enumerated() {
                    if case let .ident(n) = t { env.set(n, i < vals.count ? vals[i] : .nil) }
                }
            }
        case let .subscript(objExpr, keyExpr):
            let obj = try self.evalExpr(objExpr, env: env)
            let key = try self.evalExpr(keyExpr, env: env)
            if case let .table(box) = obj {
                box.set(key: key, value: value)
            }
        case let .attr(objExpr, field):
            let obj = try self.evalExpr(objExpr, env: env)
            if case let .table(box) = obj {
                box.set(key: .string(field), value: value)
            }
        default:
            throw FullGramPluginError("Python: cannot assign to target")
        }
    }

    private func evalExpr(_ expr: PyExpr, env: PyEnv) throws -> FullGramPluginValue {
        try self.tick()
        switch expr {
        case .none: return .nil
        case let .bool(b): return .bool(b)
        case let .int(i): return .int(i)
        case let .double(d): return .double(d)
        case let .string(s): return .string(s)
        case let .fString(template): return try self.evalFString(template, env: env)
        case let .ident(id):
            if let v = env.get(id) { return v }
            throw FullGramPluginError("Python: name '\(id)' is not defined")
        case let .list(items):
            return .list(try items.map { try self.evalExpr($0, env: env) })
        case let .tuple(items):
            return .list(try items.map { try self.evalExpr($0, env: env) })
        case let .dict(pairs):
            let box = FullGramPluginTableBox()
            for (kE, vE) in pairs {
                let k = try self.evalExpr(kE, env: env)
                let v = try self.evalExpr(vE, env: env)
                box.set(key: k, value: v)
            }
            return .table(box)
        case let .listComp(bodyExpr, varName, iterExpr, condExpr):
            let items = self.iterableItems(try self.evalExpr(iterExpr, env: env))
            var out: [FullGramPluginValue] = []
            for item in items {
                let compEnv = PyEnv(parent: env)
                compEnv.set(varName, item)
                if let condExpr, !(try self.evalExpr(condExpr, env: compEnv).isTruthy) { continue }
                out.append(try self.evalExpr(bodyExpr, env: compEnv))
            }
            return .list(out)
        case let .lambda(params, body):
            return .function { [weak self] args in
                guard let self else { return .nil }
                try self.enterCall()
                defer { self.callDepth -= 1 }
                let fnEnv = PyEnv(parent: env)
                for (i, p) in params.enumerated() { fnEnv.set(p, i < args.count ? args[i] : .nil) }
                return try self.evalExpr(body, env: fnEnv)
            }
        case let .ternary(cond, tExpr, fExpr):
            return try self.evalExpr(cond, env: env).isTruthy ? try self.evalExpr(tExpr, env: env) : try self.evalExpr(fExpr, env: env)
        case let .unary(op, inner):
            let v = try self.evalExpr(inner, env: env)
            if op == .not { return .bool(!v.isTruthy) }
            if op == .minus {
                if case let .int(i) = v { return .int(-i) }
                return .double(-(v.asDouble ?? 0.0))
            }
            return v
        case let .binary(op, lExpr, rExpr):
            if op == .and {
                let l = try self.evalExpr(lExpr, env: env)
                return l.isTruthy ? try self.evalExpr(rExpr, env: env) : l
            }
            if op == .or {
                let l = try self.evalExpr(lExpr, env: env)
                return l.isTruthy ? l : try self.evalExpr(rExpr, env: env)
            }
            return try self.evalBinary(op, try self.evalExpr(lExpr, env: env), try self.evalExpr(rExpr, env: env))
        case let .compare(op, lExpr, rExpr):
            let l = try self.evalExpr(lExpr, env: env)
            let r = try self.evalExpr(rExpr, env: env)
            return .bool(self.evalCompare(op, l, r))
        case let .attr(objExpr, field):
            let obj = try self.evalExpr(objExpr, env: env)
            return self.resolveAttr(obj: obj, field: field)
        case let .subscript(objExpr, keyExpr):
            let obj = try self.evalExpr(objExpr, env: env)
            let key = try self.evalExpr(keyExpr, env: env)
            return self.resolveSubscript(obj: obj, key: key)
        case let .slice(objExpr, startE, endE):
            let obj = try self.evalExpr(objExpr, env: env)
            let sVal = try startE.map { try self.evalExpr($0, env: env).asInt.map(Int.init) } ?? nil
            let eVal = try endE.map { try self.evalExpr($0, env: env).asInt.map(Int.init) } ?? nil
            return self.resolveSlice(obj: obj, start: sVal, end: eVal)
        case let .call(fnExpr, argExprs, kwExprs):
            let fnVal = try self.evalExpr(fnExpr, env: env)
            var args = try argExprs.map { try self.evalExpr($0, env: env) }
            for (_, vE) in kwExprs { args.append(try self.evalExpr(vE, env: env)) }
            guard case let .function(fn) = fnVal else {
                throw FullGramPluginError("Python: '\(fnVal.asString)' object is not callable")
            }
            return try fn(args)
        }
    }

    private func evalFString(_ template: String, env: PyEnv) throws -> FullGramPluginValue {
        var out = ""
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            if chars[i] == "{" {
                if i + 1 < chars.count && chars[i + 1] == "{" {
                    out.append("{"); i += 2; continue
                }
                var depth = 1
                var j = i + 1
                while j < chars.count && depth > 0 {
                    if chars[j] == "{" { depth += 1 }
                    else if chars[j] == "}" { depth -= 1 }
                    j += 1
                }
                let exprSource = String(chars[(i + 1) ..< max(i + 1, j - 1)])
                var lex = PyLexer(source: exprSource)
                let toks = try lex.tokenize()
                var p = PyParser(tokens: toks)
                let e = try p.parseExpr()
                out.append(try self.evalExpr(e, env: env).asString)
                i = j
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return .string(out)
    }

    private func evalBinary(_ op: PyTokenKind, _ l: FullGramPluginValue, _ r: FullGramPluginValue) throws -> FullGramPluginValue {
        switch op {
        case .plus:
            if case let (.string(a), .string(b)) = (l, r) { return .string(a + b) }
            if case let (.list(a), .list(b)) = (l, r) { return .list(a + b) }
            if case let (.int(a), .int(b)) = (l, r) { return .int(a &+ b) }
            return .double((l.asDouble ?? 0) + (r.asDouble ?? 0))
        case .minus:
            if case let (.int(a), .int(b)) = (l, r) { return .int(a &- b) }
            return .double((l.asDouble ?? 0) - (r.asDouble ?? 0))
        case .star:
            if case let (.string(s), .int(n)) = (l, r) { return .string(String(repeating: s, count: max(0, min(1000, Int(n))))) }
            if case let (.int(a), .int(b)) = (l, r) { return .int(a &* b) }
            return .double((l.asDouble ?? 0) * (r.asDouble ?? 0))
        case .slash:
            return .double((l.asDouble ?? 0) / (r.asDouble ?? 1))
        case .slashSlash:
            if case let (.int(a), .int(b)) = (l, r), b != 0 { return .int(a / b) }
            return .double(floor((l.asDouble ?? 0) / (r.asDouble ?? 1)))
        case .percent:
            if case let (.int(a), .int(b)) = (l, r), b != 0 { return .int(a % b) }
            return .double((l.asDouble ?? 0).truncatingRemainder(dividingBy: (r.asDouble ?? 1)))
        case .starStar:
            return .double(pow(l.asDouble ?? 0, r.asDouble ?? 0))
        default:
            return .nil
        }
    }

    private func evalCompare(_ op: PyCompareOp, _ l: FullGramPluginValue, _ r: FullGramPluginValue) -> Bool {
        switch op {
        case .eq, .is: return Self.pyEqual(l, r)
        case .neq, .isNot: return !Self.pyEqual(l, r)
        case .lt:
            if case let (.string(a), .string(b)) = (l, r) { return a < b }
            return (l.asDouble ?? 0) < (r.asDouble ?? 0)
        case .lte:
            if case let (.string(a), .string(b)) = (l, r) { return a <= b }
            return (l.asDouble ?? 0) <= (r.asDouble ?? 0)
        case .gt:
            if case let (.string(a), .string(b)) = (l, r) { return a > b }
            return (l.asDouble ?? 0) > (r.asDouble ?? 0)
        case .gte:
            if case let (.string(a), .string(b)) = (l, r) { return a >= b }
            return (l.asDouble ?? 0) >= (r.asDouble ?? 0)
        case .in:
            return self.pyContains(needle: l, haystack: r)
        case .notIn:
            return !self.pyContains(needle: l, haystack: r)
        }
    }

    private func pyContains(needle: FullGramPluginValue, haystack: FullGramPluginValue) -> Bool {
        switch haystack {
        case let .string(s): return s.contains(needle.asString)
        case let .list(arr): return arr.contains { Self.pyEqual($0, needle) }
        case let .table(box): return box.mapPart[needle.asString] != nil
        default: return false
        }
    }

    private static func pyEqual(_ a: FullGramPluginValue, _ b: FullGramPluginValue) -> Bool {
        switch (a, b) {
        case (.nil, .nil): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case (.int, .double), (.double, .int), (.double, .double): return (a.asDouble ?? 0) == (b.asDouble ?? 0)
        default: return false
        }
    }

    private func iterableItems(_ value: FullGramPluginValue) -> [FullGramPluginValue] {
        switch value {
        case let .list(arr): return arr
        case let .string(s): return s.map { .string(String($0)) }
        case let .table(box):
            if !box.arrayPart.isEmpty { return box.arrayPart }
            return box.orderedKeys.map { .string($0) }
        default: return []
        }
    }

    private func resolveSubscript(obj: FullGramPluginValue, key: FullGramPluginValue) -> FullGramPluginValue {
        switch obj {
        case let .list(arr):
            guard let i = key.asInt.map(Int.init) else { return .nil }
            let idx = i < 0 ? arr.count + i : i
            return (idx >= 0 && idx < arr.count) ? arr[idx] : .nil
        case let .string(s):
            let chars = Array(s)
            guard let i = key.asInt.map(Int.init) else { return .nil }
            let idx = i < 0 ? chars.count + i : i
            return (idx >= 0 && idx < chars.count) ? .string(String(chars[idx])) : .nil
        case let .table(box):
            return box.mapPart[key.asString] ?? box.get(key: key)
        default:
            return .nil
        }
    }

    private func resolveSlice(obj: FullGramPluginValue, start: Int?, end: Int?) -> FullGramPluginValue {
        switch obj {
        case let .string(s):
            let chars = Array(s)
            let n = chars.count
            let lo = max(0, min(n, (start ?? 0) < 0 ? n + (start ?? 0) : (start ?? 0)))
            let hi = max(lo, min(n, (end ?? n) < 0 ? n + (end ?? n) : (end ?? n)))
            return .string(String(chars[lo ..< hi]))
        case let .list(arr):
            let n = arr.count
            let lo = max(0, min(n, (start ?? 0) < 0 ? n + (start ?? 0) : (start ?? 0)))
            let hi = max(lo, min(n, (end ?? n) < 0 ? n + (end ?? n) : (end ?? n)))
            return .list(Array(arr[lo ..< hi]))
        default:
            return .nil
        }
    }

    private func resolveAttr(obj: FullGramPluginValue, field: String) -> FullGramPluginValue {
        if case let .table(box) = obj {
            if let v = box.mapPart[field] { return v }
            switch field {
            case "get": return .function { args in
                let k = args.first?.asString ?? ""
                return box.mapPart[k] ?? (args.count > 1 ? args[1] : .nil)
            }
            case "keys": return .function { _ in .list(box.orderedKeys.map { .string($0) }) }
            case "values": return .function { _ in .list(box.orderedKeys.compactMap { box.mapPart[$0] }) }
            case "items": return .function { _ in .list(box.orderedKeys.map { .list([.string($0), box.mapPart[$0] ?? .nil]) }) }
            default: break
            }
            return .nil
        }
        if case let .string(s) = obj {
            switch field {
            case "upper": return .function { _ in .string(s.uppercased()) }
            case "lower": return .function { _ in .string(s.lowercased()) }
            case "title": return .function { _ in .string(s.capitalized) }
            case "strip": return .function { _ in .string(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            case "lstrip": return .function { _ in
                var sub = s[...]
                while let f = sub.first, f.isWhitespace { sub = sub.dropFirst() }
                return .string(String(sub))
            }
            case "rstrip": return .function { _ in
                var sub = s[...]
                while let l = sub.last, l.isWhitespace { sub = sub.dropLast() }
                return .string(String(sub))
            }
            case "split": return .function { args in
                let sep = args.first?.asString
                let parts = (sep == nil || sep!.isEmpty) ? s.split(whereSeparator: { $0.isWhitespace }).map(String.init) : s.components(separatedBy: sep!)
                return .list(parts.map { .string($0) })
            }
            case "join": return .function { args in
                let items = self.iterableItems(args.first ?? .nil)
                return .string(items.map { $0.asString }.joined(separator: s))
            }
            case "replace": return .function { args in
                let old = args.count > 0 ? args[0].asString : ""
                let new = args.count > 1 ? args[1].asString : ""
                return .string(s.replacingOccurrences(of: old, with: new))
            }
            case "startswith": return .function { args in .bool(s.hasPrefix(args.first?.asString ?? "")) }
            case "endswith": return .function { args in .bool(s.hasSuffix(args.first?.asString ?? "")) }
            case "find": return .function { args in
                let sub = args.first?.asString ?? ""
                guard let r = s.range(of: sub) else { return .int(-1) }
                return .int(Int64(s.distance(from: s.startIndex, to: r.lowerBound)))
            }
            default: break
            }
        }
        if case let .list(arr) = obj {
            switch field {
            case "append": return .function { args in .list(arr + [args.first ?? .nil]) } // Note: functional list in Swift enum; mutable lists best handled via local table/helper
            case "copy": return .function { _ in .list(arr) }
            default: break
            }
        }
        return .nil
    }

    private func registerBuiltins(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        let fgBox = FullGramPluginTableBox(dict: hostAPI)
        self.globalEnv.set("fullgram", .table(fgBox))
        self.modules["fullgram"] = .table(fgBox)

        self.globalEnv.set("print", .function { args in
            printHandler(args.map { $0.asString }.joined(separator: " "))
            return .nil
        })
        self.globalEnv.set("len", .function { args in
            switch args.first ?? .nil {
            case let .string(s): return .int(Int64(s.count))
            case let .list(arr): return .int(Int64(arr.count))
            case let .table(box): return .int(Int64(box.mapPart.count + box.arrayPart.count))
            default: return .int(0)
            }
        })
        self.globalEnv.set("str", .function { args in .string((args.first ?? .nil).asString) })
        self.globalEnv.set("int", .function { args in .int(args.first?.asInt ?? 0) })
        self.globalEnv.set("float", .function { args in .double(args.first?.asDouble ?? 0.0) })
        self.globalEnv.set("bool", .function { args in .bool((args.first ?? .nil).isTruthy) })
        self.globalEnv.set("list", .function { [weak self] args in
            guard let self else { return .list([]) }
            return .list(self.iterableItems(args.first ?? .nil))
        })
        self.globalEnv.set("dict", .function { _ in .table(FullGramPluginTableBox()) })
        self.globalEnv.set("range", .function { args in
            let start = args.count >= 2 ? Int(args[0].asInt ?? 0) : 0
            let stop = args.count >= 2 ? Int(args[1].asInt ?? 0) : Int(args.first?.asInt ?? 0)
            let step = args.count >= 3 ? Int(args[2].asInt ?? 1) : 1
            guard step != 0 else { return .list([]) }
            var res: [FullGramPluginValue] = []
            var cur = start
            var guardCount = 0
            while ((step > 0 && cur < stop) || (step < 0 && cur > stop)) && guardCount < 10_000 {
                res.append(.int(Int64(cur)))
                cur += step
                guardCount += 1
            }
            return .list(res)
        })
        self.globalEnv.set("enumerate", .function { [weak self] args in
            guard let self else { return .list([]) }
            let items = self.iterableItems(args.first ?? .nil)
            return .list(items.enumerated().map { .list([.int(Int64($0.offset)), $0.element]) })
        })
        self.globalEnv.set("zip", .function { [weak self] args in
            guard let self, args.count >= 2 else { return .list([]) }
            let a = self.iterableItems(args[0])
            let b = self.iterableItems(args[1])
            let count = min(a.count, b.count)
            return .list((0 ..< count).map { .list([a[$0], b[$0]]) })
        })
        self.globalEnv.set("sorted", .function { [weak self] args in
            guard let self else { return .list([]) }
            let items = self.iterableItems(args.first ?? .nil)
            return .list(items.sorted { ($0.asDouble ?? 0) < ($1.asDouble ?? 0) || $0.asString < $1.asString })
        })
        self.globalEnv.set("abs", .function { args in
            if case let .int(i)? = args.first { return .int(abs(i)) }
            return .double(abs(args.first?.asDouble ?? 0.0))
        })
        self.globalEnv.set("round", .function { args in
            let v = args.first?.asDouble ?? 0.0
            let digits = Int(args.count > 1 ? (args[1].asInt ?? 0) : 0)
            if digits <= 0 { return .int(Int64(v.rounded())) }
            let factor = pow(10.0, Double(digits))
            return .double((v * factor).rounded() / factor)
        })
        self.globalEnv.set("min", .function { [weak self] args in
            guard let self else { return .nil }
            let items = args.count == 1 ? self.iterableItems(args[0]) : args
            return items.min { ($0.asDouble ?? 0) < ($1.asDouble ?? 0) } ?? .nil
        })
        self.globalEnv.set("max", .function { [weak self] args in
            guard let self else { return .nil }
            let items = args.count == 1 ? self.iterableItems(args[0]) : args
            return items.max { ($0.asDouble ?? 0) < ($1.asDouble ?? 0) } ?? .nil
        })
        self.globalEnv.set("sum", .function { [weak self] args in
            guard let self else { return .int(0) }
            let items = self.iterableItems(args.first ?? .nil)
            return .double(items.reduce(0.0) { $0 + ($1.asDouble ?? 0.0) })
        })
        self.globalEnv.set("any", .function { [weak self] args in
            guard let self else { return .bool(false) }
            return .bool(self.iterableItems(args.first ?? .nil).contains { $0.isTruthy })
        })
        self.globalEnv.set("all", .function { [weak self] args in
            guard let self else { return .bool(true) }
            return .bool(!self.iterableItems(args.first ?? .nil).contains { !$0.isTruthy })
        })

        // Built-in safe modules: re, json, math, random, time
        let reMod = FullGramPluginTableBox(dict: [
            "sub": .function { args in
                let pat = args.count > 0 ? args[0].asString : ""
                let repl = args.count > 1 ? args[1].asString : ""
                let text = args.count > 2 ? args[2].asString : ""
                guard let regex = try? NSRegularExpression(pattern: pat) else { return .string(text) }
                let ns = text as NSString
                return .string(regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: repl))
            },
            "search": .function { args in
                let pat = args.count > 0 ? args[0].asString : ""
                let text = args.count > 1 ? args[1].asString : ""
                guard let regex = try? NSRegularExpression(pattern: pat) else { return .nil }
                let ns = text as NSString
                guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return .nil }
                return .string(ns.substring(with: m.range))
            },
            "findall": .function { args in
                let pat = args.count > 0 ? args[0].asString : ""
                let text = args.count > 1 ? args[1].asString : ""
                guard let regex = try? NSRegularExpression(pattern: pat) else { return .list([]) }
                let ns = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                return .list(matches.map { m in
                    let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
                    return r.location != NSNotFound ? .string(ns.substring(with: r)) : .string("")
                })
            }
        ])
        self.modules["re"] = .table(reMod)

        let jsonMod = FullGramPluginTableBox(dict: [
            "loads": .function { args in
                guard let data = (args.first?.asString ?? "").data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) else { return .nil }
                return FullGramPluginValue.fromJSONObject(obj, forPython: true)
            },
            "dumps": .function { args in
                let obj = (args.first ?? .nil).toJSONObject()
                guard JSONSerialization.isValidJSONObject(obj),
                      let data = try? JSONSerialization.data(withJSONObject: obj),
                      let s = String(data: data, encoding: .utf8) else { return .string("null") }
                return .string(s)
            }
        ])
        self.modules["json"] = .table(jsonMod)

        let mathMod = FullGramPluginTableBox(dict: [
            "pi": .double(Double.pi),
            "floor": .function { args in .int(Int64(floor(args.first?.asDouble ?? 0.0))) },
            "ceil": .function { args in .int(Int64(ceil(args.first?.asDouble ?? 0.0))) },
            "sqrt": .function { args in .double(sqrt(args.first?.asDouble ?? 0.0)) },
            "sin": .function { args in .double(sin(args.first?.asDouble ?? 0.0)) },
            "cos": .function { args in .double(cos(args.first?.asDouble ?? 0.0)) }
        ])
        self.modules["math"] = .table(mathMod)

        let randomMod = FullGramPluginTableBox(dict: [
            "randint": .function { args in
                let a = args.count > 0 ? (args[0].asInt ?? 0) : 0
                let b = args.count > 1 ? (args[1].asInt ?? 1) : 1
                return b >= a ? .int(Int64.random(in: a ... b)) : .int(a)
            },
            "choice": .function { [weak self] args in
                guard let self else { return .nil }
                let items = self.iterableItems(args.first ?? .nil)
                return items.randomElement() ?? .nil
            }
        ])
        self.modules["random"] = .table(randomMod)

        let timeMod = FullGramPluginTableBox(dict: [
            "time": .function { _ in .double(Date().timeIntervalSince1970) }
        ])
        self.modules["time"] = .table(timeMod)
    }
}

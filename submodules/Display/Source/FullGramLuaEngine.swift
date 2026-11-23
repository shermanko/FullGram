import Foundation

private enum LuaTokenKind: Equatable {
    case eof
    case ident(String)
    case number(Double, Bool) // value, isInt
    case string(String)
    case `if`, then, elseif, `else`, end, `for`, `in`, `do`, `while`, `repeat`, until, `break`, `return`, local, function, `true`, `false`, `nil`, and, or, not
    case plus, minus, star, slash, slashSlash, percent, caret, hash
    case eq, neq, lt, lte, gt, gte, assign
    case concat, colon, comma, dot, semi, lParen, rParen, lBrace, rBrace, lBracket, rBracket
}

private struct LuaToken {
    let kind: LuaTokenKind
    let line: Int
}

private struct LuaLexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    init(source: String) {
        self.chars = Array(source)
    }

    mutating func tokenize() throws -> [LuaToken] {
        var tokens: [LuaToken] = []
        while self.pos < self.chars.count {
            self.skipWhitespaceAndComments()
            if self.pos >= self.chars.count { break }
            let startLine = self.line
            let c = self.chars[self.pos]

            if c == "\"" || c == "'" {
                tokens.append(LuaToken(kind: .string(try self.readQuotedString(quote: c)), line: startLine))
            } else if c == "[" && (self.peek(1) == "[" || self.peek(1) == "=") {
                tokens.append(LuaToken(kind: .string(try self.readLongString()), line: startLine))
            } else if c.isNumber || (c == "." && (self.peek(1)?.isNumber == true)) {
                tokens.append(try self.readNumber(line: startLine))
            } else if c.isLetter || c == "_" {
                let ident = self.readIdent()
                tokens.append(LuaToken(kind: Self.keywordOrIdent(ident), line: startLine))
            } else {
                tokens.append(try self.readSymbol(line: startLine))
            }
        }
        tokens.append(LuaToken(kind: .eof, line: self.line))
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

    private mutating func skipWhitespaceAndComments() {
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isWhitespace {
                _ = self.advance()
            } else if c == "-" && self.peek(1) == "-" {
                self.pos += 2
                if self.peek(0) == "[" && self.peek(1) == "[" {
                    _ = try? self.readLongString()
                } else {
                    while self.pos < self.chars.count && self.chars[self.pos] != "\n" {
                        _ = self.advance()
                    }
                }
            } else {
                break
            }
        }
    }

    private mutating func readQuotedString(quote: Character) throws -> String {
        _ = self.advance()
        var out = ""
        while self.pos < self.chars.count {
            let c = self.advance()
            if c == quote { return out }
            if c == "\\" {
                guard self.pos < self.chars.count else { throw FullGramPluginError("Lua line \(self.line): unterminated escape") }
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
        throw FullGramPluginError("Lua line \(self.line): unterminated string")
    }

    private mutating func readLongString() throws -> String {
        _ = self.advance() // [
        var eqs = 0
        while self.pos < self.chars.count && self.chars[self.pos] == "=" {
            eqs += 1
            self.pos += 1
        }
        guard self.pos < self.chars.count && self.chars[self.pos] == "[" else {
            throw FullGramPluginError("Lua line \(self.line): invalid long string")
        }
        self.pos += 1
        if self.pos < self.chars.count && self.chars[self.pos] == "\n" {
            _ = self.advance()
        }
        var out = ""
        let closing = "]" + String(repeating: "=", count: eqs) + "]"
        while self.pos < self.chars.count {
            if self.chars[self.pos] == "]", self.pos + closing.count <= self.chars.count {
                let slice = String(self.chars[self.pos ..< self.pos + closing.count])
                if slice == closing {
                    self.pos += closing.count
                    return out
                }
            }
            out.append(self.advance())
        }
        throw FullGramPluginError("Lua line \(self.line): unterminated long string")
    }

    private mutating func readNumber(line: Int) throws -> LuaToken {
        var raw = ""
        var isFloat = false
        if self.chars[self.pos] == "0" && (self.peek(1) == "x" || self.peek(1) == "X") {
            raw.append(self.advance())
            raw.append(self.advance())
            while self.pos < self.chars.count && self.chars[self.pos].isHexDigit {
                raw.append(self.advance())
            }
            let hexStr = String(raw.dropFirst(2))
            let val = Double(Int64(hexStr, radix: 16) ?? 0)
            return LuaToken(kind: .number(val, true), line: line)
        }
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isNumber {
                raw.append(self.advance())
            } else if c == "." && !isFloat && self.peek(1) != "." {
                isFloat = true
                raw.append(self.advance())
            } else if (c == "e" || c == "E") {
                isFloat = true
                raw.append(self.advance())
                if self.pos < self.chars.count && (self.chars[self.pos] == "+" || self.chars[self.pos] == "-") {
                    raw.append(self.advance())
                }
            } else {
                break
            }
        }
        guard let num = Double(raw) else {
            throw FullGramPluginError("Lua line \(line): invalid number '\(raw)'")
        }
        return LuaToken(kind: .number(num, !isFloat && num == num.rounded()), line: line)
    }

    private mutating func readIdent() -> String {
        var raw = ""
        while self.pos < self.chars.count {
            let c = self.chars[self.pos]
            if c.isLetter || c.isNumber || c == "_" {
                raw.append(self.advance())
            } else {
                break
            }
        }
        return raw
    }

    private mutating func readSymbol(line: Int) throws -> LuaToken {
        let c = self.advance()
        switch c {
        case "+": return LuaToken(kind: .plus, line: line)
        case "-": return LuaToken(kind: .minus, line: line)
        case "*": return LuaToken(kind: .star, line: line)
        case "%": return LuaToken(kind: .percent, line: line)
        case "^": return LuaToken(kind: .caret, line: line)
        case "#": return LuaToken(kind: .hash, line: line)
        case ":": return LuaToken(kind: .colon, line: line)
        case ",": return LuaToken(kind: .comma, line: line)
        case ";": return LuaToken(kind: .semi, line: line)
        case "(": return LuaToken(kind: .lParen, line: line)
        case ")": return LuaToken(kind: .rParen, line: line)
        case "{": return LuaToken(kind: .lBrace, line: line)
        case "}": return LuaToken(kind: .rBrace, line: line)
        case "[": return LuaToken(kind: .lBracket, line: line)
        case "]": return LuaToken(kind: .rBracket, line: line)
        case "/":
            if self.pos < self.chars.count && self.chars[self.pos] == "/" {
                _ = self.advance()
                return LuaToken(kind: .slashSlash, line: line)
            }
            return LuaToken(kind: .slash, line: line)
        case "=":
            if self.pos < self.chars.count && self.chars[self.pos] == "=" {
                _ = self.advance()
                return LuaToken(kind: .eq, line: line)
            }
            return LuaToken(kind: .assign, line: line)
        case "~":
            if self.pos < self.chars.count && self.chars[self.pos] == "=" {
                _ = self.advance()
                return LuaToken(kind: .neq, line: line)
            }
            throw FullGramPluginError("Lua line \(line): unexpected '~'")
        case "<":
            if self.pos < self.chars.count && self.chars[self.pos] == "=" {
                _ = self.advance()
                return LuaToken(kind: .lte, line: line)
            }
            return LuaToken(kind: .lt, line: line)
        case ">":
            if self.pos < self.chars.count && self.chars[self.pos] == "=" {
                _ = self.advance()
                return LuaToken(kind: .gte, line: line)
            }
            return LuaToken(kind: .gt, line: line)
        case ".":
            if self.pos < self.chars.count && self.chars[self.pos] == "." {
                _ = self.advance()
                return LuaToken(kind: .concat, line: line)
            }
            return LuaToken(kind: .dot, line: line)
        default:
            throw FullGramPluginError("Lua line \(line): unexpected character '\(c)'")
        }
    }

    private static func keywordOrIdent(_ s: String) -> LuaTokenKind {
        switch s {
        case "if": return .if
        case "then": return .then
        case "elseif": return .elseif
        case "else": return .else
        case "end": return .end
        case "for": return .for
        case "in": return .in
        case "do": return .do
        case "while": return .while
        case "repeat": return .repeat
        case "until": return .until
        case "break": return .break
        case "return": return .return
        case "local": return .local
        case "function": return .function
        case "true": return .true
        case "false": return .false
        case "nil": return .nil
        case "and": return .and
        case "or": return .or
        case "not": return .not
        default: return .ident(s)
        }
    }
}

private indirect enum LuaExpr {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case ident(String)
    case table([(LuaExpr?, LuaExpr)])
    case unary(LuaTokenKind, LuaExpr)
    case binary(LuaTokenKind, LuaExpr, LuaExpr)
    case index(LuaExpr, LuaExpr)
    case member(LuaExpr, String)
    case call(LuaExpr, [LuaExpr])
    case methodCall(LuaExpr, String, [LuaExpr])
    case function([String], [LuaStmt])
}

private indirect enum LuaStmt {
    case block([LuaStmt])
    case localAssign([String], [LuaExpr])
    case assign([LuaExpr], [LuaExpr])
    case exprCall(LuaExpr)
    case ifStmt([(LuaExpr, [LuaStmt])], [LuaStmt]?)
    case whileStmt(LuaExpr, [LuaStmt])
    case repeatStmt([LuaStmt], LuaExpr)
    case numericFor(String, LuaExpr, LuaExpr, LuaExpr?, [LuaStmt])
    case genericFor([String], [LuaExpr], [LuaStmt])
    case funcDef([String], Bool, [String], [LuaStmt], Bool) // path, isMethod, params, body, isLocal
    case returnStmt([LuaExpr])
    case breakStmt
}

private struct LuaParser {
    private let tokens: [LuaToken]
    private var pos = 0

    init(tokens: [LuaToken]) {
        self.tokens = tokens
    }

    private var current: LuaToken {
        return self.pos < self.tokens.count ? self.tokens[self.pos] : LuaToken(kind: .eof, line: 0)
    }

    private func peek(_ offset: Int = 1) -> LuaToken {
        let i = self.pos + offset
        return i < self.tokens.count ? self.tokens[i] : LuaToken(kind: .eof, line: 0)
    }

    @discardableResult
    private mutating func consume() -> LuaToken {
        let t = self.current
        self.pos += 1
        return t
    }

    private mutating func match(_ kind: LuaTokenKind) -> Bool {
        if self.current.kind == kind {
            self.pos += 1
            return true
        }
        return false
    }

    private mutating func expect(_ kind: LuaTokenKind, _ msg: String) throws {
        guard self.current.kind == kind else {
            throw FullGramPluginError("Lua line \(self.current.line): expected \(msg)")
        }
        self.pos += 1
    }

    mutating func parseChunk() throws -> [LuaStmt] {
        return try self.parseBlock(until: [.eof])
    }

    private mutating func parseBlock(until terminators: [LuaTokenKind]) throws -> [LuaStmt] {
        var stmts: [LuaStmt] = []
        while self.current.kind != .eof && !terminators.contains(self.current.kind) {
            if self.match(.semi) { continue }
            let stmt = try self.parseStmt()
            stmts.append(stmt)
            _ = self.match(.semi)
        }
        return stmts
    }

    private mutating func parseStmt() throws -> LuaStmt {
        switch self.current.kind {
        case .local:
            self.pos += 1
            if self.match(.function) {
                guard case let .ident(name) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected function name")
                }
                self.pos += 1
                let (params, body) = try self.parseFunctionBody()
                return .funcDef([name], false, params, body, true)
            }
            var names: [String] = []
            repeat {
                guard case let .ident(name) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected local variable name")
                }
                self.pos += 1
                names.append(name)
            } while self.match(.comma)
            var exprs: [LuaExpr] = []
            if self.match(.assign) {
                exprs = try self.parseExprList()
            }
            return .localAssign(names, exprs)

        case .function:
            self.pos += 1
            var path: [String] = []
            guard case let .ident(first) = self.current.kind else {
                throw FullGramPluginError("Lua line \(self.current.line): expected function name")
            }
            self.pos += 1
            path.append(first)
            while self.match(.dot) {
                guard case let .ident(part) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected identifier")
                }
                self.pos += 1
                path.append(part)
            }
            var isMethod = false
            if self.match(.colon) {
                guard case let .ident(method) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected method name")
                }
                self.pos += 1
                path.append(method)
                isMethod = true
            }
            let (params, body) = try self.parseFunctionBody()
            return .funcDef(path, isMethod, params, body, false)

        case .if:
            self.pos += 1
            var branches: [(LuaExpr, [LuaStmt])] = []
            let cond = try self.parseExpr()
            try self.expect(.then, "'then'")
            let body = try self.parseBlock(until: [.elseif, .else, .end])
            branches.append((cond, body))
            while self.match(.elseif) {
                let eCond = try self.parseExpr()
                try self.expect(.then, "'then'")
                let eBody = try self.parseBlock(until: [.elseif, .else, .end])
                branches.append((eCond, eBody))
            }
            var elseBody: [LuaStmt]?
            if self.match(.else) {
                elseBody = try self.parseBlock(until: [.end])
            }
            try self.expect(.end, "'end'")
            return .ifStmt(branches, elseBody)

        case .while:
            self.pos += 1
            let cond = try self.parseExpr()
            try self.expect(.do, "'do'")
            let body = try self.parseBlock(until: [.end])
            try self.expect(.end, "'end'")
            return .whileStmt(cond, body)

        case .repeat:
            self.pos += 1
            let body = try self.parseBlock(until: [.until])
            try self.expect(.until, "'until'")
            let cond = try self.parseExpr()
            return .repeatStmt(body, cond)

        case .for:
            self.pos += 1
            guard case let .ident(var1) = self.current.kind else {
                throw FullGramPluginError("Lua line \(self.current.line): expected loop variable")
            }
            self.pos += 1
            if self.match(.assign) {
                let start = try self.parseExpr()
                try self.expect(.comma, "','")
                let endExpr = try self.parseExpr()
                var step: LuaExpr?
                if self.match(.comma) {
                    step = try self.parseExpr()
                }
                try self.expect(.do, "'do'")
                let body = try self.parseBlock(until: [.end])
                try self.expect(.end, "'end'")
                return .numericFor(var1, start, endExpr, step, body)
            }
            var vars = [var1]
            while self.match(.comma) {
                guard case let .ident(vn) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected variable")
                }
                self.pos += 1
                vars.append(vn)
            }
            try self.expect(.in, "'in'")
            let iters = try self.parseExprList()
            try self.expect(.do, "'do'")
            let body = try self.parseBlock(until: [.end])
            try self.expect(.end, "'end'")
            return .genericFor(vars, iters, body)

        case .do:
            self.pos += 1
            let body = try self.parseBlock(until: [.end])
            try self.expect(.end, "'end'")
            return .block(body)

        case .return:
            self.pos += 1
            if [.eof, .end, .else, .elseif, .until, .semi].contains(self.current.kind) {
                return .returnStmt([])
            }
            return .returnStmt(try self.parseExprList())

        case .break:
            self.pos += 1
            return .breakStmt

        default:
            let first = try self.parseSuffixedExpr()
            if self.current.kind == .comma || self.current.kind == .assign {
                var targets = [first]
                while self.match(.comma) {
                    targets.append(try self.parseSuffixedExpr())
                }
                try self.expect(.assign, "'='")
                let values = try self.parseExprList()
                return .assign(targets, values)
            }
            return .exprCall(first)
        }
    }

    private mutating func parseFunctionBody() throws -> ([String], [LuaStmt]) {
        try self.expect(.lParen, "'('")
        var params: [String] = []
        if self.current.kind != .rParen {
            repeat {
                if case let .ident(p) = self.current.kind {
                    params.append(p)
                    self.pos += 1
                } else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected parameter name")
                }
            } while self.match(.comma)
        }
        try self.expect(.rParen, "')'")
        let body = try self.parseBlock(until: [.end])
        try self.expect(.end, "'end'")
        return (params, body)
    }

    private mutating func parseExprList() throws -> [LuaExpr] {
        var list = [try self.parseExpr()]
        while self.match(.comma) {
            list.append(try self.parseExpr())
        }
        return list
    }

    private mutating func parseExpr() throws -> LuaExpr {
        return try self.parseOr()
    }

    private mutating func parseOr() throws -> LuaExpr {
        var lhs = try self.parseAnd()
        while self.match(.or) {
            lhs = .binary(.or, lhs, try self.parseAnd())
        }
        return lhs
    }

    private mutating func parseAnd() throws -> LuaExpr {
        var lhs = try self.parseCmp()
        while self.match(.and) {
            lhs = .binary(.and, lhs, try self.parseCmp())
        }
        return lhs
    }

    private mutating func parseCmp() throws -> LuaExpr {
        var lhs = try self.parseConcat()
        while [.eq, .neq, .lt, .lte, .gt, .gte].contains(self.current.kind) {
            let op = self.consume().kind
            lhs = .binary(op, lhs, try self.parseConcat())
        }
        return lhs
    }

    private mutating func parseConcat() throws -> LuaExpr {
        let lhs = try self.parseAdd()
        if self.match(.concat) {
            return .binary(.concat, lhs, try self.parseConcat())
        }
        return lhs
    }

    private mutating func parseAdd() throws -> LuaExpr {
        var lhs = try self.parseMul()
        while self.current.kind == .plus || self.current.kind == .minus {
            let op = self.consume().kind
            lhs = .binary(op, lhs, try self.parseMul())
        }
        return lhs
    }

    private mutating func parseMul() throws -> LuaExpr {
        var lhs = try self.parseUnary()
        while [.star, .slash, .slashSlash, .percent].contains(self.current.kind) {
            let op = self.consume().kind
            lhs = .binary(op, lhs, try self.parseUnary())
        }
        return lhs
    }

    private mutating func parseUnary() throws -> LuaExpr {
        if [.not, .minus, .hash].contains(self.current.kind) {
            let op = self.consume().kind
            return .unary(op, try self.parseUnary())
        }
        return try self.parsePower()
    }

    private mutating func parsePower() throws -> LuaExpr {
        let lhs = try self.parseSuffixedExpr()
        if self.match(.caret) {
            return .binary(.caret, lhs, try self.parseUnary())
        }
        return lhs
    }

    private mutating func parseSuffixedExpr() throws -> LuaExpr {
        var expr = try self.parsePrimary()
        while true {
            if self.match(.dot) {
                guard case let .ident(member) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected field name")
                }
                self.pos += 1
                expr = .member(expr, member)
            } else if self.match(.lBracket) {
                let idx = try self.parseExpr()
                try self.expect(.rBracket, "']'")
                expr = .index(expr, idx)
            } else if self.match(.colon) {
                guard case let .ident(method) = self.current.kind else {
                    throw FullGramPluginError("Lua line \(self.current.line): expected method name")
                }
                self.pos += 1
                let args = try self.parseCallArgs()
                expr = .methodCall(expr, method, args)
            } else if self.current.kind == .lParen || self.current.kind == .lBrace || { if case .string = self.current.kind { return true }; return false }() {
                let args = try self.parseCallArgs()
                expr = .call(expr, args)
            } else {
                break
            }
        }
        return expr
    }

    private mutating func parseCallArgs() throws -> [LuaExpr] {
        if self.match(.lParen) {
            if self.match(.rParen) { return [] }
            let args = try self.parseExprList()
            try self.expect(.rParen, "')'")
            return args
        } else if self.current.kind == .lBrace {
            return [try self.parseTable()]
        } else if case let .string(s) = self.current.kind {
            self.pos += 1
            return [.string(s)]
        }
        throw FullGramPluginError("Lua line \(self.current.line): expected function arguments")
    }

    private mutating func parsePrimary() throws -> LuaExpr {
        switch self.current.kind {
        case .nil: self.pos += 1; return .nil
        case .true: self.pos += 1; return .bool(true)
        case .false: self.pos += 1; return .bool(false)
        case let .number(val, isInt):
            self.pos += 1
            return isInt ? .int(Int64(val)) : .double(val)
        case let .string(s): self.pos += 1; return .string(s)
        case let .ident(id): self.pos += 1; return .ident(id)
        case .lParen:
            self.pos += 1
            let e = try self.parseExpr()
            try self.expect(.rParen, "')'")
            return e
        case .lBrace:
            return try self.parseTable()
        case .function:
            self.pos += 1
            let (params, body) = try self.parseFunctionBody()
            return .function(params, body)
        default:
            throw FullGramPluginError("Lua line \(self.current.line): unexpected token \(self.current.kind)")
        }
    }

    private mutating func parseTable() throws -> LuaExpr {
        try self.expect(.lBrace, "'{'")
        var entries: [(LuaExpr?, LuaExpr)] = []
        while self.current.kind != .rBrace && self.current.kind != .eof {
            if self.match(.lBracket) {
                let key = try self.parseExpr()
                try self.expect(.rBracket, "']'")
                try self.expect(.assign, "'='")
                let val = try self.parseExpr()
                entries.append((key, val))
            } else if case let .ident(name) = self.current.kind, self.peek().kind == .assign {
                self.pos += 2
                let val = try self.parseExpr()
                entries.append((.string(name), val))
            } else {
                entries.append((nil, try self.parseExpr()))
            }
            if !self.match(.comma) && !self.match(.semi) { break }
        }
        try self.expect(.rBrace, "'}'")
        return .table(entries)
    }
}

private final class LuaEnv {
    let parent: LuaEnv?
    var vars: [String: FullGramPluginValue] = [:]

    init(parent: LuaEnv? = nil) {
        self.parent = parent
    }

    func get(_ name: String) -> FullGramPluginValue {
        if let v = self.vars[name] { return v }
        return self.parent?.get(name) ?? .nil
    }

    func setLocal(_ name: String, _ value: FullGramPluginValue) {
        self.vars[name] = value
    }

    func set(_ name: String, _ value: FullGramPluginValue) {
        if self.vars[name] != nil {
            self.vars[name] = value
            return
        }
        if let parent = self.parent, parent.has(name) {
            parent.set(name, value)
            return
        }
        var root = self
        while let p = root.parent { root = p }
        root.vars[name] = value
    }

    private func has(_ name: String) -> Bool {
        if self.vars[name] != nil { return true }
        return self.parent?.has(name) ?? false
    }
}

private enum LuaSignal: Error {
    case returnValues([FullGramPluginValue])
    case breakLoop
}

public final class FullGramLuaVM {
    private let globalEnv = LuaEnv()
    private let vmLock = NSRecursiveLock()
    private var steps = 0
    private let maxSteps = 120_000
    private var callDepth = 0
    private let maxCallDepth = 64

    public init(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        self.registerStdlib(hostAPI: hostAPI, printHandler: printHandler)
    }

    deinit {
        self.globalEnv.vars.removeAll()
    }

    public func load(code: String) throws {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        self.steps = 0
        self.callDepth = 0
        var lexer = LuaLexer(source: code)
        let tokens = try lexer.tokenize()
        var parser = LuaParser(tokens: tokens)
        let chunk = try parser.parseChunk()
        _ = try self.execBlock(chunk, env: self.globalEnv)
    }

    public func hasFunction(_ name: String) -> Bool {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        if case .function = self.globalEnv.get(name) { return true }
        return false
    }

    @discardableResult
    public func callFunction(_ name: String, args: [FullGramPluginValue]) throws -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        guard case let .function(fn) = self.globalEnv.get(name) else {
            return .nil
        }
        self.steps = 0
        self.callDepth = 0
        return try fn(args)
    }

    public func getGlobal(_ name: String) -> FullGramPluginValue {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        return self.globalEnv.get(name)
    }

    private func enterCall() throws {
        self.callDepth += 1
        if self.callDepth > self.maxCallDepth {
            throw FullGramPluginError("Lua recursion limit exceeded (\(self.maxCallDepth))")
        }
    }

    private func tick() throws {
        self.steps += 1
        if self.steps > self.maxSteps {
            throw FullGramPluginError("Lua execution exceeded step limit (\(self.maxSteps))")
        }
    }

    private func execBlock(_ stmts: [LuaStmt], env: LuaEnv) throws -> FullGramPluginValue? {
        for stmt in stmts {
            try self.tick()
            switch stmt {
            case let .block(inner):
                _ = try self.execBlock(inner, env: LuaEnv(parent: env))
            case let .localAssign(names, exprs):
                var vals: [FullGramPluginValue] = []
                for e in exprs { vals.append(try self.evalExpr(e, env: env)) }
                for (i, n) in names.enumerated() {
                    env.setLocal(n, i < vals.count ? vals[i] : .nil)
                }
            case let .assign(targets, exprs):
                var vals: [FullGramPluginValue] = []
                for e in exprs { vals.append(try self.evalExpr(e, env: env)) }
                for (i, target) in targets.enumerated() {
                    let val = i < vals.count ? vals[i] : .nil
                    try self.assignTarget(target, value: val, env: env)
                }
            case let .exprCall(expr):
                _ = try self.evalExpr(expr, env: env)
            case let .ifStmt(branches, elseBody):
                var matched = false
                for (cond, body) in branches {
                    if try self.evalExpr(cond, env: env).isLuaTruthy {
                        _ = try self.execBlock(body, env: LuaEnv(parent: env))
                        matched = true
                        break
                    }
                }
                if !matched, let elseBody {
                    _ = try self.execBlock(elseBody, env: LuaEnv(parent: env))
                }
            case let .whileStmt(cond, body):
                while try self.evalExpr(cond, env: env).isLuaTruthy {
                    try self.tick()
                    do {
                        _ = try self.execBlock(body, env: LuaEnv(parent: env))
                    } catch LuaSignal.breakLoop {
                        break
                    }
                }
            case let .repeatStmt(body, cond):
                repeat {
                    try self.tick()
                    let loopEnv = LuaEnv(parent: env)
                    do {
                        _ = try self.execBlock(body, env: loopEnv)
                    } catch LuaSignal.breakLoop {
                        break
                    }
                    if try self.evalExpr(cond, env: loopEnv).isLuaTruthy { break }
                } while true
            case let .numericFor(name, startE, endE, stepE, body):
                let startV = try self.evalExpr(startE, env: env).asDouble ?? 0.0
                let endV = try self.evalExpr(endE, env: env).asDouble ?? 0.0
                let stepV = try stepE.map { try self.evalExpr($0, env: env).asDouble ?? 1.0 } ?? 1.0
                if stepV == 0.0 { break }
                var cur = startV
                while (stepV > 0 && cur <= endV) || (stepV < 0 && cur >= endV) {
                    try self.tick()
                    let loopEnv = LuaEnv(parent: env)
                    let val: FullGramPluginValue = cur == cur.rounded() ? .int(Int64(cur)) : .double(cur)
                    loopEnv.setLocal(name, val)
                    do {
                        _ = try self.execBlock(body, env: loopEnv)
                    } catch LuaSignal.breakLoop {
                        break
                    }
                    cur += stepV
                }
            case let .genericFor(vars, iters, body):
                guard let firstIter = iters.first else { break }
                let iterVal = try self.evalExpr(firstIter, env: env)
                switch iterVal {
                case let .table(box):
                    var didBreak = false
                    for (idx, item) in box.arrayPart.enumerated() {
                        try self.tick()
                        let loopEnv = LuaEnv(parent: env)
                        if vars.count >= 1 { loopEnv.setLocal(vars[0], .int(Int64(idx + 1))) }
                        if vars.count >= 2 { loopEnv.setLocal(vars[1], item) }
                        do { _ = try self.execBlock(body, env: loopEnv) } catch LuaSignal.breakLoop { didBreak = true; break }
                    }
                    if !didBreak {
                        for key in box.orderedKeys {
                            try self.tick()
                            let loopEnv = LuaEnv(parent: env)
                            if vars.count >= 1 { loopEnv.setLocal(vars[0], .string(key)) }
                            if vars.count >= 2 { loopEnv.setLocal(vars[1], box.mapPart[key] ?? .nil) }
                            do { _ = try self.execBlock(body, env: loopEnv) } catch LuaSignal.breakLoop { break }
                        }
                    }
                case let .list(arr):
                    for (idx, item) in arr.enumerated() {
                        try self.tick()
                        let loopEnv = LuaEnv(parent: env)
                        if vars.count >= 1 { loopEnv.setLocal(vars[0], .int(Int64(idx + 1))) }
                        if vars.count >= 2 { loopEnv.setLocal(vars[1], item) }
                        do { _ = try self.execBlock(body, env: loopEnv) } catch LuaSignal.breakLoop { break }
                    }
                case let .function(iterFn):
                    while true {
                        try self.tick()
                        let res = try iterFn([])
                        if case .nil = res { break }
                        let loopEnv = LuaEnv(parent: env)
                        if case let .list(tuple) = res {
                            for (i, vn) in vars.enumerated() {
                                loopEnv.setLocal(vn, i < tuple.count ? tuple[i] : .nil)
                            }
                        } else if !vars.isEmpty {
                            loopEnv.setLocal(vars[0], res)
                        }
                        do { _ = try self.execBlock(body, env: loopEnv) } catch LuaSignal.breakLoop { break }
                    }
                default:
                    break
                }
            case let .funcDef(path, isMethod, params, body, isLocal):
                let fullParams = isMethod ? (["self"] + params) : params
                let fn = self.makeClosure(params: fullParams, body: body, capturedEnv: env)
                if path.count == 1 {
                    if isLocal {
                        env.setLocal(path[0], fn)
                    } else {
                        env.set(path[0], fn)
                    }
                } else {
                    var target = env.get(path[0])
                    for i in 1 ..< (path.count - 1) {
                        if case let .table(box) = target {
                            target = box.get(key: .string(path[i]))
                        }
                    }
                    if case let .table(box) = target {
                        box.set(key: .string(path.last!), value: fn)
                    }
                }
            case let .returnStmt(exprs):
                let vals = try exprs.map { try self.evalExpr($0, env: env) }
                throw LuaSignal.returnValues(vals)
            case .breakStmt:
                throw LuaSignal.breakLoop
            }
        }
        return nil
    }

    private func assignTarget(_ target: LuaExpr, value: FullGramPluginValue, env: LuaEnv) throws {
        switch target {
        case let .ident(name):
            env.set(name, value)
        case let .member(objExpr, field):
            let obj = try self.evalExpr(objExpr, env: env)
            if case let .table(box) = obj {
                box.set(key: .string(field), value: value)
            }
        case let .index(objExpr, keyExpr):
            let obj = try self.evalExpr(objExpr, env: env)
            let key = try self.evalExpr(keyExpr, env: env)
            if case let .table(box) = obj {
                box.set(key: key, value: value)
            }
        default:
            throw FullGramPluginError("Lua: invalid assignment target")
        }
    }

    private func makeClosure(params: [String], body: [LuaStmt], capturedEnv: LuaEnv) -> FullGramPluginValue {
        return .function { [weak self] args in
            guard let self else { return .nil }
            try self.enterCall()
            defer { self.callDepth -= 1 }
            let fnEnv = LuaEnv(parent: capturedEnv)
            for (i, p) in params.enumerated() {
                fnEnv.setLocal(p, i < args.count ? args[i] : .nil)
            }
            do {
                _ = try self.execBlock(body, env: fnEnv)
                return .nil
            } catch let LuaSignal.returnValues(vals) {
                return vals.first ?? .nil
            }
        }
    }

    private func evalExpr(_ expr: LuaExpr, env: LuaEnv) throws -> FullGramPluginValue {
        try self.tick()
        switch expr {
        case .nil: return .nil
        case let .bool(b): return .bool(b)
        case let .int(i): return .int(i)
        case let .double(d): return .double(d)
        case let .string(s): return .string(s)
        case let .ident(id): return env.get(id)
        case let .function(params, body): return self.makeClosure(params: params, body: body, capturedEnv: env)
        case let .table(entries):
            let box = FullGramPluginTableBox()
            for (kOpt, vExpr) in entries {
                let v = try self.evalExpr(vExpr, env: env)
                if let kExpr = kOpt {
                    let k = try self.evalExpr(kExpr, env: env)
                    box.set(key: k, value: v)
                } else {
                    box.arrayPart.append(v)
                }
            }
            return .table(box)
        case let .member(objExpr, field):
            let obj = try self.evalExpr(objExpr, env: env)
            if case let .table(box) = obj {
                return box.get(key: .string(field))
            }
            if case .string = obj, case let .table(strLib) = self.globalEnv.get("string") {
                return strLib.get(key: .string(field))
            }
            return .nil
        case let .index(objExpr, keyExpr):
            let obj = try self.evalExpr(objExpr, env: env)
            let key = try self.evalExpr(keyExpr, env: env)
            if case let .table(box) = obj {
                return box.get(key: key)
            }
            return .nil
        case let .call(fnExpr, argExprs):
            let fnVal = try self.evalExpr(fnExpr, env: env)
            let args = try argExprs.map { try self.evalExpr($0, env: env) }
            guard case let .function(fn) = fnVal else {
                throw FullGramPluginError("Lua: attempt to call a \(fnVal.asString) value")
            }
            return try fn(args)
        case let .methodCall(objExpr, method, argExprs):
            let obj = try self.evalExpr(objExpr, env: env)
            let args = [obj] + (try argExprs.map { try self.evalExpr($0, env: env) })
            var fnVal: FullGramPluginValue = .nil
            if case let .table(box) = obj {
                fnVal = box.get(key: .string(method))
            } else if case .string = obj, case let .table(strLib) = self.globalEnv.get("string") {
                fnVal = strLib.get(key: .string(method))
            }
            guard case let .function(fn) = fnVal else {
                throw FullGramPluginError("Lua: attempt to call method '\(method)'")
            }
            return try fn(args)
        case let .unary(op, inner):
            let v = try self.evalExpr(inner, env: env)
            switch op {
            case .not: return .bool(!v.isLuaTruthy)
            case .minus:
                if case let .int(i) = v { return .int(-i) }
                if let d = v.asDouble { return .double(-d) }
                return .nil
            case .hash:
                switch v {
                case let .string(s): return .int(Int64(s.count))
                case let .table(box): return .int(Int64(box.arrayPart.count))
                case let .list(arr): return .int(Int64(arr.count))
                default: return .int(0)
                }
            default:
                return .nil
            }
        case let .binary(op, lhsExpr, rhsExpr):
            if op == .and {
                let l = try self.evalExpr(lhsExpr, env: env)
                return l.isLuaTruthy ? try self.evalExpr(rhsExpr, env: env) : l
            }
            if op == .or {
                let l = try self.evalExpr(lhsExpr, env: env)
                return l.isLuaTruthy ? l : try self.evalExpr(rhsExpr, env: env)
            }
            let l = try self.evalExpr(lhsExpr, env: env)
            let r = try self.evalExpr(rhsExpr, env: env)
            return self.evalBinary(op: op, l: l, r: r)
        }
    }

    private func evalBinary(op: LuaTokenKind, l: FullGramPluginValue, r: FullGramPluginValue) -> FullGramPluginValue {
        switch op {
        case .concat:
            return .string(l.asString + r.asString)
        case .eq:
            return .bool(Self.valuesEqual(l, r))
        case .neq:
            return .bool(!Self.valuesEqual(l, r))
        case .lt:
            if case let (.string(a), .string(b)) = (l, r) { return .bool(a < b) }
            return .bool((l.asDouble ?? 0) < (r.asDouble ?? 0))
        case .lte:
            if case let (.string(a), .string(b)) = (l, r) { return .bool(a <= b) }
            return .bool((l.asDouble ?? 0) <= (r.asDouble ?? 0))
        case .gt:
            if case let (.string(a), .string(b)) = (l, r) { return .bool(a > b) }
            return .bool((l.asDouble ?? 0) > (r.asDouble ?? 0))
        case .gte:
            if case let (.string(a), .string(b)) = (l, r) { return .bool(a >= b) }
            return .bool((l.asDouble ?? 0) >= (r.asDouble ?? 0))
        case .plus, .minus, .star, .slash, .slashSlash, .percent, .caret:
            if case let (.int(a), .int(b)) = (l, r) {
                switch op {
                case .plus: return .int(a &+ b)
                case .minus: return .int(a &- b)
                case .star: return .int(a &* b)
                case .slashSlash: return b == 0 ? .double(Double.nan) : .int(a / b)
                case .percent: return b == 0 ? .int(0) : .int(a % b)
                default: break
                }
            }
            let a = l.asDouble ?? 0.0
            let b = r.asDouble ?? 0.0
            switch op {
            case .plus: return .double(a + b)
            case .minus: return .double(a - b)
            case .star: return .double(a * b)
            case .slash: return .double(a / b)
            case .slashSlash: return .double(floor(a / b))
            case .percent: return .double(a.truncatingRemainder(dividingBy: b))
            case .caret: return .double(pow(a, b))
            default: return .nil
            }
        default:
            return .nil
        }
    }

    private static func valuesEqual(_ a: FullGramPluginValue, _ b: FullGramPluginValue) -> Bool {
        switch (a, b) {
        case (.nil, .nil): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case (.int, .double), (.double, .int), (.double, .double):
            return (a.asDouble ?? 0.0) == (b.asDouble ?? 0.0)
        case let (.table(x), .table(y)): return x === y
        default: return false
        }
    }

    private static func luaPatternToRegex(_ pattern: String) -> String {
        var out = ""
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            if chars[i] == "%", i + 1 < chars.count {
                let next = chars[i + 1]
                switch next {
                case "d": out.append("\\d")
                case "D": out.append("\\D")
                case "s": out.append("\\s")
                case "S": out.append("\\S")
                case "w": out.append("\\w")
                case "W": out.append("\\W")
                case "a": out.append("[A-Za-z]")
                case "A": out.append("[^A-Za-z]")
                case "l": out.append("[a-z]")
                case "u": out.append("[A-Z]")
                case "%": out.append("%")
                default: out.append("\\" + String(next))
                }
                i += 2
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    private func registerStdlib(hostAPI: [String: FullGramPluginValue], printHandler: @escaping (String) -> Void) {
        let fgBox = FullGramPluginTableBox(dict: hostAPI)
        self.globalEnv.setLocal("fullgram", .table(fgBox))

        self.globalEnv.setLocal("print", .function { args in
            printHandler(args.map { $0.asString }.joined(separator: "\t"))
            return .nil
        })
        self.globalEnv.setLocal("tostring", .function { args in
            return .string((args.first ?? .nil).asString)
        })
        self.globalEnv.setLocal("tonumber", .function { args in
            guard let v = args.first else { return .nil }
            if let i = v.asInt, case .int = v { return .int(i) }
            if let d = v.asDouble { return d == d.rounded() ? .int(Int64(d)) : .double(d) }
            return .nil
        })
        self.globalEnv.setLocal("type", .function { args in
            switch args.first ?? .nil {
            case .nil: return .string("nil")
            case .bool: return .string("boolean")
            case .int, .double: return .string("number")
            case .string: return .string("string")
            case .table, .list: return .string("table")
            case .function: return .string("function")
            }
        })
        self.globalEnv.setLocal("pairs", .function { args in
            return args.first ?? .nil
        })
        self.globalEnv.setLocal("ipairs", .function { args in
            if case let .table(box) = args.first ?? .nil {
                return .table(FullGramPluginTableBox(array: box.arrayPart))
            }
            return args.first ?? .nil
        })
        self.globalEnv.setLocal("pcall", .function { args in
            guard case let .function(fn) = args.first ?? .nil else {
                return .bool(false)
            }
            do {
                return try fn(Array(args.dropFirst()))
            } catch {
                return .nil
            }
        })

        // string.*
        let strBox = FullGramPluginTableBox(dict: [
            "len": .function { args in .int(Int64((args.first?.asString ?? "").count)) },
            "upper": .function { args in .string((args.first?.asString ?? "").uppercased()) },
            "lower": .function { args in .string((args.first?.asString ?? "").lowercased()) },
            "rep": .function { args in
                let s = args.first?.asString ?? ""
                let n = max(0, Int(args.dropFirst().first?.asInt ?? 1))
                return .string(String(repeating: s, count: min(1000, n)))
            },
            "reverse": .function { args in .string(String((args.first?.asString ?? "").reversed())) },
            "sub": .function { args in
                let s = args.first?.asString ?? ""
                let chars = Array(s)
                let len = chars.count
                let iRaw = Int(args.count > 1 ? (args[1].asInt ?? 1) : 1)
                let jRaw = Int(args.count > 2 ? (args[2].asInt ?? Int64(len)) : Int64(len))
                let i = max(0, (iRaw < 0 ? len + iRaw : iRaw - 1))
                let j = min(len - 1, (jRaw < 0 ? len + jRaw : jRaw - 1))
                if i > j || i >= len { return .string("") }
                return .string(String(chars[i ... j]))
            },
            "find": .function { args in
                let s = args.first?.asString ?? ""
                let pat = args.count > 1 ? args[1].asString : ""
                if let range = s.range(of: pat) {
                    return .int(Int64(s.distance(from: s.startIndex, to: range.lowerBound) + 1))
                }
                return .nil
            },
            "gsub": .function { args in
                let s = args.first?.asString ?? ""
                let pat = args.count > 1 ? args[1].asString : ""
                let rawRepl = args.count > 2 ? args[2].asString : ""
                if pat.contains("%") || pat.contains("[") || pat.contains("^") || pat.contains("$") || pat.contains("+") || pat.contains("*") {
                    let regexPat = Self.luaPatternToRegex(pat)
                    if let regex = try? NSRegularExpression(pattern: regexPat) {
                        var repl = rawRepl
                        for g in 1 ... 9 {
                            repl = repl.replacingOccurrences(of: "%\(g)", with: "$\(g)")
                        }
                        let ns = s as NSString
                        return .string(regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: repl))
                    }
                }
                return .string(s.replacingOccurrences(of: pat, with: rawRepl))
            },
            "match": .function { args in
                let s = args.first?.asString ?? ""
                let pat = args.count > 1 ? Self.luaPatternToRegex(args[1].asString) : ""
                guard let regex = try? NSRegularExpression(pattern: pat) else { return .nil }
                let ns = s as NSString
                guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return .nil }
                let idx = m.numberOfRanges > 1 ? 1 : 0
                return m.range(at: idx).location != NSNotFound ? .string(ns.substring(with: m.range(at: idx))) : .nil
            },
            "format": .function { args in
                guard let fmt = args.first?.asString else { return .string("") }
                var out = fmt
                for val in args.dropFirst() {
                    if let r = out.range(of: "%s") ?? out.range(of: "%d") ?? out.range(of: "%f") {
                        out.replaceSubrange(r, with: val.asString)
                    }
                }
                return .string(out)
            }
        ])
        self.globalEnv.setLocal("string", .table(strBox))

        // table.*
        let tblBox = FullGramPluginTableBox(dict: [
            "insert": .function { args in
                if args.count >= 2, case let .table(box) = args[0] {
                    if args.count == 2 {
                        box.arrayPart.append(args[1])
                    } else if let idx = args[1].asInt {
                        let pos = max(0, min(box.arrayPart.count, Int(idx) - 1))
                        box.arrayPart.insert(args[2], at: pos)
                    }
                }
                return .nil
            },
            "remove": .function { args in
                if !args.isEmpty, case let .table(box) = args[0], !box.arrayPart.isEmpty {
                    let idx = args.count > 1 ? max(0, min(box.arrayPart.count - 1, Int(args[1].asInt ?? 1) - 1)) : box.arrayPart.count - 1
                    return box.arrayPart.remove(at: idx)
                }
                return .nil
            },
            "concat": .function { args in
                if !args.isEmpty, case let .table(box) = args[0] {
                    let sep = args.count > 1 ? args[1].asString : ""
                    return .string(box.arrayPart.map { $0.asString }.joined(separator: sep))
                }
                return .string("")
            }
        ])
        self.globalEnv.setLocal("table", .table(tblBox))

        // math.*
        let mathBox = FullGramPluginTableBox(dict: [
            "pi": .double(Double.pi),
            "floor": .function { args in .int(Int64(floor(args.first?.asDouble ?? 0.0))) },
            "ceil": .function { args in .int(Int64(ceil(args.first?.asDouble ?? 0.0))) },
            "abs": .function { args in .double(abs(args.first?.asDouble ?? 0.0)) },
            "sqrt": .function { args in .double(sqrt(args.first?.asDouble ?? 0.0)) },
            "sin": .function { args in .double(sin(args.first?.asDouble ?? 0.0)) },
            "cos": .function { args in .double(cos(args.first?.asDouble ?? 0.0)) },
            "min": .function { args in .double(args.compactMap { $0.asDouble }.min() ?? 0.0) },
            "max": .function { args in .double(args.compactMap { $0.asDouble }.max() ?? 0.0) },
            "random": .function { args in
                if args.count >= 2, let a = args[0].asInt, let b = args[1].asInt, b >= a {
                    return .int(Int64.random(in: a ... b))
                }
                if args.count == 1, let m = args[0].asInt, m >= 1 {
                    return .int(Int64.random(in: 1 ... m))
                }
                return .double(Double.random(in: 0.0 ..< 1.0))
            }
        ])
        self.globalEnv.setLocal("math", .table(mathBox))

        // json.*
        let jsonBox = FullGramPluginTableBox(dict: [
            "decode": .function { args in
                guard let data = (args.first?.asString ?? "").data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) else { return .nil }
                return FullGramPluginValue.fromJSONObject(obj, forPython: false)
            },
            "encode": .function { args in
                let obj = (args.first ?? .nil).toJSONObject()
                guard JSONSerialization.isValidJSONObject(obj),
                      let data = try? JSONSerialization.data(withJSONObject: obj),
                      let str = String(data: data, encoding: .utf8) else { return .string("null") }
                return .string(str)
            }
        ])
        self.globalEnv.setLocal("json", .table(jsonBox))

        // os.* (phone time & date)
        let osBox = FullGramPluginTableBox(dict: [
            "time": .function { args in
                if let first = args.first, case let .table(box) = first {
                    var comps = DateComponents()
                    comps.year = Int(box.get(key: .string("year")).asInt ?? 1970)
                    comps.month = Int(box.get(key: .string("month")).asInt ?? 1)
                    comps.day = Int(box.get(key: .string("day")).asInt ?? 1)
                    comps.hour = Int(box.get(key: .string("hour")).asInt ?? 12)
                    comps.minute = Int(box.get(key: .string("min")).asInt ?? 0)
                    comps.second = Int(box.get(key: .string("sec")).asInt ?? 0)
                    if let d = Calendar.current.date(from: comps) {
                        return .int(Int64(d.timeIntervalSince1970))
                    }
                }
                return .int(Int64(Date().timeIntervalSince1970))
            },
            "clock": .function { _ in
                return .double(ProcessInfo.processInfo.systemUptime)
            },
            "difftime": .function { args in
                let t2 = args.count > 0 ? (args[0].asDouble ?? 0.0) : 0.0
                let t1 = args.count > 1 ? (args[1].asDouble ?? 0.0) : 0.0
                return .double(t2 - t1)
            },
            "date": .function { args in
                var fmt = args.first?.asString ?? "%d.%m.%Y %H:%M:%S"
                let ts = args.count > 1 ? (args[1].asDouble ?? Date().timeIntervalSince1970) : Date().timeIntervalSince1970
                let date = Date(timeIntervalSince1970: ts)
                var cal = Calendar.current
                var tz = TimeZone.current
                if fmt.hasPrefix("!") {
                    fmt = String(fmt.dropFirst())
                    tz = TimeZone(secondsFromGMT: 0) ?? tz
                    cal.timeZone = tz
                }
                if fmt == "*t" {
                    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
                    let yday = cal.ordinality(of: .day, in: .year, for: date) ?? 1
                    return .table(FullGramPluginTableBox(dict: [
                        "year": .int(Int64(c.year ?? 1970)),
                        "month": .int(Int64(c.month ?? 1)),
                        "day": .int(Int64(c.day ?? 1)),
                        "hour": .int(Int64(c.hour ?? 0)),
                        "min": .int(Int64(c.minute ?? 0)),
                        "sec": .int(Int64(c.second ?? 0)),
                        "wday": .int(Int64(c.weekday ?? 1)),
                        "yday": .int(Int64(yday)),
                        "isdst": .bool(tz.isDaylightSavingTime(for: date))
                    ]))
                }
                return .string(Self.formatStrftime(fmt, date: date, timeZone: tz))
            }
        ])
        self.globalEnv.setLocal("os", .table(osBox))
    }

    private static func formatStrftime(_ format: String, date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let yday = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour24 = c.hour ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : (hour24 % 12)
        let ampm = hour24 < 12 ? "AM" : "PM"
        let pad2: (Int) -> String = { String(format: "%02d", $0) }

        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = Locale.current
        df.dateFormat = "EEEE"
        let fullWeekday = df.string(from: date)
        df.dateFormat = "EEE"
        let shortWeekday = df.string(from: date)
        df.dateFormat = "MMMM"
        let fullMonth = df.string(from: date)
        df.dateFormat = "MMM"
        let shortMonth = df.string(from: date)

        var out = ""
        let chars = Array(format)
        var i = 0
        while i < chars.count {
            if chars[i] == "%", i + 1 < chars.count {
                let code = chars[i + 1]
                switch code {
                case "Y": out += String(format: "%04d", c.year ?? 1970)
                case "y": out += pad2((c.year ?? 1970) % 100)
                case "m": out += pad2(c.month ?? 1)
                case "d": out += pad2(c.day ?? 1)
                case "H": out += pad2(hour24)
                case "I": out += pad2(hour12)
                case "M": out += pad2(c.minute ?? 0)
                case "S": out += pad2(c.second ?? 0)
                case "p": out += ampm
                case "w": out += String(((c.weekday ?? 1) + 6) % 7)
                case "j": out += String(format: "%03d", yday)
                case "A": out += fullWeekday
                case "a": out += shortWeekday
                case "B": out += fullMonth
                case "b": out += shortMonth
                case "X": out += "\(pad2(hour24)):\(pad2(c.minute ?? 0)):\(pad2(c.second ?? 0))"
                case "x": out += "\(pad2(c.day ?? 1)).\(pad2(c.month ?? 1)).\(String(format: "%04d", c.year ?? 1970))"
                case "c": out += "\(pad2(c.day ?? 1)).\(pad2(c.month ?? 1)).\(String(format: "%04d", c.year ?? 1970)) \(pad2(hour24)):\(pad2(c.minute ?? 0)):\(pad2(c.second ?? 0))"
                case "%": out.append("%")
                default:
                    out.append("%")
                    out.append(code)
                }
                i += 2
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }
}

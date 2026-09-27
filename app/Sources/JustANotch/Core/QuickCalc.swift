import Foundation

/// Máy tính nhanh kiêm đổi tiền cho launcher. Tự viết bộ phân tích (recursive
/// descent) thay vì `NSExpression` — cái đó ném exception ObjC (crash app) khi
/// gặp input dở dang như "2+" mà người dùng gõ giữa chừng.
///
/// Ngữ pháp:
///   input  := expr [ ("to"|"in"|"sang"|"->"|"=>"|"=") CUR ]
///   expr   := term (("+"|"-") term)*
///   term   := factor (("*"|"x"|"×"|"/"|"÷"|":") factor)*
///   factor := unary ("^" factor)?
///   unary  := ("-"|"+") unary | postfix
///   postfix:= primary "%"?
///   primary:= CUR? NUMBER SUFFIX? CUR? | "(" expr ")" CUR?
enum QuickCalc {
    struct Value: Equatable {
        var amount: Double
        var currency: String?   // mã ISO viết hoa, nil = số thường
    }

    struct Result: Equatable {
        /// Giá trị sau khi đổi sang tiền đích (hoặc số thường).
        var value: Value
        /// Giá trị gốc trước khi đổi (nil khi không có đổi tiền).
        var source: Value?
    }

    enum CalcError: Error, Equatable {
        case empty, syntax, noRates, unknownCurrency(String), divideByZero
    }

    /// Tỷ giá theo USD: `rates["VND"]` = số VND cho 1 USD. nil = chưa có.
    static func evaluate(_ input: String, rates: [String: Double]?) -> Swift.Result<Result, CalcError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        var p = Parser(tokens: tokenize(trimmed), rates: rates)
        do {
            let v = try p.parseExpr()
            var target: String?
            if p.peekKeyword() {
                p.pos += 1
                // "2+2=" (đang gõ dở / thói quen bấm "=") → bỏ qua, không phải đổi tiền.
                if p.peek() != nil {
                    guard case .word(let w)? = p.peek(), let code = p.currency(w) else { throw CalcError.syntax }
                    p.pos += 1
                    target = code
                }
            }
            guard p.pos == p.tokens.count else { throw CalcError.syntax }
            guard let cur = v.currency else {
                // "100 to usd" không rõ tiền gốc → không đoán.
                if target != nil { throw CalcError.syntax }
                return .success(Result(value: v, source: nil))
            }
            let dest = target ?? (cur == "VND" ? "USD" : "VND")
            if dest == cur { return .success(Result(value: v, source: nil)) }
            let converted = try convert(v.amount, from: cur, to: dest, rates: rates)
            return .success(Result(value: Value(amount: converted, currency: dest), source: v))
        } catch let e as CalcError {
            return .failure(e)
        } catch {
            return .failure(.syntax)
        }
    }

    static func convert(_ amount: Double, from: String, to: String, rates: [String: Double]?) throws -> Double {
        if from == to { return amount }
        guard let rates else { throw CalcError.noRates }
        guard let f = rates[from] else { throw CalcError.unknownCurrency(from) }
        guard let t = rates[to] else { throw CalcError.unknownCurrency(to) }
        return amount / f * t
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case word(String)     // chữ cái (hậu tố, mã tiền, từ khoá) — viết thường
        case op(Character)    // + - * / ^ % ( ) và ký hiệu tiền
        case arrow            // -> hoặc =>
    }

    static let currencySymbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₫": "VND"]
    static let multipliers: [String: Double] = [
        "k": 1e3, "nghìn": 1e3, "ngàn": 1e3, "ng": 1e3,
        "tr": 1e6, "m": 1e6, "triệu": 1e6, "trieu": 1e6,
        "ty": 1e9, "tỷ": 1e9, "tỉ": 1e9, "ti": 1e9, "b": 1e9,
    ]
    static let keywords: Set<String> = ["to", "in", "sang", "ra"]

    static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "," { j += 1 }
                // Bỏ dấu phân cách treo ở cuối ("100." khi đang gõ).
                var raw = String(chars[i..<j])
                while let last = raw.last, last == "." || last == "," { raw.removeLast() }
                out.append(.number(parseNumber(raw)))
                i = j; continue
            }
            if c.isLetter || c == "đ" {
                var j = i
                while j < chars.count, chars[j].isLetter { j += 1 }
                out.append(.word(String(chars[i..<j]).lowercased()))
                i = j; continue
            }
            if (c == "-" || c == "=") && i + 1 < chars.count && chars[i + 1] == ">" {
                out.append(.arrow); i += 2; continue
            }
            switch c {
            case "×": out.append(.op("*"))
            case "÷", ":": out.append(.op("/"))
            case "−": out.append(.op("-"))
            case "=": out.append(.arrow)
            default: out.append(.op(c))
            }
            i += 1
        }
        return out
    }

    /// Số kiểu Việt/Anh lẫn lộn:
    /// - có cả "." và "," → dấu xuất hiện sau cùng là dấu thập phân;
    /// - một loại dấu, xuất hiện nhiều lần → phân cách nghìn;
    /// - một dấu duy nhất + đúng 3 chữ số sau + phần nguyên ≠ "0" → phân cách nghìn;
    /// - còn lại → thập phân.
    static func parseNumber(_ raw: String) -> Double {
        let dots = raw.filter { $0 == "." }.count
        let commas = raw.filter { $0 == "," }.count
        var s = raw
        if dots > 0 && commas > 0 {
            let lastDot = raw.lastIndex(of: ".")!, lastComma = raw.lastIndex(of: ",")!
            let dec: Character = lastDot > lastComma ? "." : ","
            let thou: Character = dec == "." ? "," : "."
            s = raw.replacingOccurrences(of: String(thou), with: "")
                   .replacingOccurrences(of: String(dec), with: ".")
        } else if dots + commas > 1 {
            s = raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        } else if dots + commas == 1 {
            let sep: Character = dots == 1 ? "." : ","
            let parts = raw.split(separator: sep, omittingEmptySubsequences: false)
            let intPart = parts[0], frac = parts.count > 1 ? parts[1] : ""
            if frac.count == 3 && intPart != "0" && !intPart.isEmpty {
                s = String(intPart + frac)
            } else {
                s = raw.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Double(s) ?? 0
    }

    static func currencyCode(_ word: String) -> String? {
        switch word {
        case "đ", "vnd", "vnđ", "dong", "đồng", "d": return "VND"
        case "usd", "dollar", "đô", "do": return "USD"
        default:
            // Mã ISO 3 chữ: kiểm tra theo bảng tỷ giá ở Parser (cần rates) — ở đây chỉ nhận dạng dạng.
            return word.count == 3 && word.allSatisfy({ $0.isASCII && $0.isLetter }) ? word.uppercased() : nil
        }
    }

    // MARK: Parser

    struct Parser {
        let tokens: [Token]
        let rates: [String: Double]?
        var pos = 0

        init(tokens: [Token], rates: [String: Double]?) { self.tokens = tokens; self.rates = rates }

        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }

        func peekKeyword() -> Bool {
            switch peek() {
            case .arrow?: return true
            case .word(let w)?: return QuickCalc.keywords.contains(w)
            default: return false
            }
        }

        /// Mã tiền hợp lệ: bí danh quen thuộc luôn nhận; mã 3 chữ phải có trong bảng tỷ giá
        /// (khi có bảng) để "abc" không bị hiểu nhầm thành tiền.
        func currency(_ w: String) -> String? {
            guard let code = QuickCalc.currencyCode(w) else { return nil }
            if code == "VND" || code == "USD" { return code }
            if let rates { return rates[code] != nil ? code : nil }
            return code
        }

        mutating func parseExpr() throws -> Value {
            var lhs = try parseTerm()
            while case .op(let c)? = peek(), c == "+" || c == "-" {
                pos += 1
                let rhs = try parseTerm()
                lhs = try combine(lhs, rhs) { c == "+" ? $0 + $1 : $0 - $1 }
            }
            return lhs
        }

        mutating func parseTerm() throws -> Value {
            var lhs = try parseFactor()
            while true {
                var isMul: Bool
                if case .op(let c)? = peek(), c == "*" || c == "/" { isMul = c == "*" }
                else if case .word("x")? = peek() { isMul = true }
                else { break }
                pos += 1
                let rhs = try parseFactor()
                if isMul {
                    if lhs.currency != nil && rhs.currency != nil { throw CalcError.syntax }
                    lhs = Value(amount: lhs.amount * rhs.amount, currency: lhs.currency ?? rhs.currency)
                } else {
                    if rhs.amount == 0 { throw CalcError.divideByZero }
                    if let lc = lhs.currency, let rc = rhs.currency {
                        let r = try QuickCalc.convert(rhs.amount, from: rc, to: lc, rates: rates)
                        if r == 0 { throw CalcError.divideByZero }
                        lhs = Value(amount: lhs.amount / r, currency: nil)
                    } else {
                        if rhs.currency != nil { throw CalcError.syntax }
                        lhs = Value(amount: lhs.amount / rhs.amount, currency: lhs.currency)
                    }
                }
            }
            return lhs
        }

        mutating func parseFactor() throws -> Value {
            let base = try parseUnary()
            if case .op("^")? = peek() {
                pos += 1
                let exp = try parseFactor()
                guard exp.currency == nil else { throw CalcError.syntax }
                return Value(amount: pow(base.amount, exp.amount), currency: base.currency)
            }
            return base
        }

        mutating func parseUnary() throws -> Value {
            if case .op(let c)? = peek(), c == "-" || c == "+" {
                pos += 1
                var v = try parseUnary()
                if c == "-" { v.amount = -v.amount }
                return v
            }
            return try parsePostfix()
        }

        mutating func parsePostfix() throws -> Value {
            var v = try parsePrimary()
            if case .op("%")? = peek() { pos += 1; v.amount /= 100 }
            return v
        }

        mutating func parsePrimary() throws -> Value {
            // Ký hiệu tiền đứng trước: "$100".
            var prefixCur: String?
            if case .op(let c)? = peek(), let code = QuickCalc.currencySymbols[c] { prefixCur = code; pos += 1 }

            var v: Value
            switch peek() {
            case .number(let n)?:
                pos += 1
                v = Value(amount: n, currency: nil)
                if case .word(let w)? = peek(), let mul = QuickCalc.multipliers[w] {
                    pos += 1
                    v.amount *= mul
                    // "2tr5" = 2.5 triệu (kiểu nói tắt quen thuộc).
                    if case .number(let tail)? = peek(), tail < 10, tail == tail.rounded() {
                        pos += 1
                        v.amount += tail * mul / 10
                    }
                }
            case .op("(")?:
                pos += 1
                v = try parseExpr()
                guard case .op(")")? = peek() else { throw CalcError.syntax }
                pos += 1
            default:
                throw CalcError.syntax
            }

            if let prefixCur { v.currency = prefixCur }
            // Tiền đứng sau: "100usd", "100 $", "50k đ".
            if case .op(let c)? = peek(), let code = QuickCalc.currencySymbols[c] {
                pos += 1; v.currency = code
            } else if case .word(let w)? = peek(), !QuickCalc.keywords.contains(w), w != "x",
                      let code = currency(w) {
                pos += 1; v.currency = code
            } else if case .word(let w)? = peek(), !QuickCalc.keywords.contains(w), w != "x" {
                // Chữ lạ đứng sau số (mã tiền không có trong bảng…).
                if QuickCalc.currencyCode(w) != nil { throw CalcError.unknownCurrency(w.uppercased()) }
                throw CalcError.syntax
            }
            return v
        }

        func combine(_ a: Value, _ b: Value, _ f: (Double, Double) -> Double) throws -> Value {
            switch (a.currency, b.currency) {
            case let (ac?, bc?):
                let bConv = try QuickCalc.convert(b.amount, from: bc, to: ac, rates: rates)
                return Value(amount: f(a.amount, bConv), currency: ac)
            case (let ac?, nil): return Value(amount: f(a.amount, b.amount), currency: ac)
            case (nil, let bc?): return Value(amount: f(a.amount, b.amount), currency: bc)
            case (nil, nil):     return Value(amount: f(a.amount, b.amount), currency: nil)
            }
        }
    }

    // MARK: Formatting (kiểu Việt: 1.234.567,89)

    static func format(_ v: Value) -> String {
        let digits: Int
        switch v.currency {
        case "VND"?, "JPY"?, "KRW"?: digits = 0
        case .some: digits = 2
        case nil: digits = abs(v.amount) >= 1e6 ? 2 : 6
        }
        let n = formatNumber(v.amount, maxFraction: digits)
        guard let cur = v.currency else { return n }
        return cur == "VND" ? "\(n) ₫" : "\(n) \(cur)"
    }

    /// Chuỗi để copy: số thuần, định dạng như hiển thị nhưng không kèm đơn vị.
    static func copyString(_ v: Value) -> String {
        let digits = (v.currency == "VND" || v.currency == "JPY" || v.currency == "KRW") ? 0
                   : (v.currency != nil ? 2 : 6)
        return formatNumber(v.amount, maxFraction: digits)
    }

    static func formatNumber(_ x: Double, maxFraction: Int) -> String {
        guard x.isFinite else { return "∞" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxFraction
        f.roundingMode = .halfUp
        return f.string(from: NSNumber(value: x)) ?? "\(x)"
    }
}

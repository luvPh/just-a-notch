// app/Sources/JustANotch/Core/LearnAI.swift
import Foundation

// MARK: - Essay / Grammar models (lưu local)

struct EssayVocab: Codable, Equatable, Identifiable {
    var id: String { word.lowercased() }
    var word: String
    var pos: String
    var ipaUK: String
    var ipaUS: String
    var guideword: String
    var level: String
    var short: String          // nghĩa ngắn 1–4 từ
    var defEN: String
    var defVI: String          // nghĩa chi tiết theo ngữ cảnh bài
    var example: LearnExample

    var asWord: LearnWord {
        LearnWord(headword: word, pos: pos, ipaUK: ipaUK, ipaUS: ipaUS,
                  senses: [LearnSense(guideword: guideword, level: level, defEN: defEN,
                                      defVI: defVI, examples: [example])],
                  source: .ai)
    }
}

struct FamilyMember: Codable, Equatable { var word: String; var pos: String; var meaning: String }
struct WordFamily: Codable, Equatable { var root: String; var members: [FamilyMember] }

struct Essay: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var topic: String
    var level: Int
    var title: String
    var essay: String                   // đoạn ngăn bằng \n\n
    var sentences: [LearnExample]       // từng câu EN + bản dịch VI (cho nghe/dịch/đọc)
    var vocab: [EssayVocab]
    var families: [WordFamily]

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, topic, level, title, essay, sentences, vocab, families
    }
    init(topic: String, level: Int, title: String, essay: String, sentences: [LearnExample],
         vocab: [EssayVocab], families: [WordFamily]) {
        self.topic = topic; self.level = level; self.title = title; self.essay = essay
        self.sentences = sentences; self.vocab = vocab; self.families = families
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 3
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        essay = try c.decode(String.self, forKey: .essay)
        sentences = try c.decodeIfPresent([LearnExample].self, forKey: .sentences) ?? []
        vocab = try c.decodeIfPresent([EssayVocab].self, forKey: .vocab) ?? []
        families = try c.decodeIfPresent([WordFamily].self, forKey: .families) ?? []
    }
}

struct WordLookup: Codable, Equatable {
    var word: String
    var lemma: String
    var pos: String
    var ipaUK: String
    var ipaUS: String
    var guideword: String
    var level: String
    var defEN: String
    var defVI: String
    var example: LearnExample

    var asWord: LearnWord {
        LearnWord(headword: lemma, pos: pos, ipaUK: ipaUK, ipaUS: ipaUS,
                  senses: [LearnSense(guideword: guideword, level: level, defEN: defEN,
                                      defVI: defVI, examples: [example])], source: .ai)
    }
}

struct GrammarExample: Codable, Equatable { var en: String; var vi: String; var wrong: String? }
struct QuickCheck: Codable, Equatable { var q: String; var options: [String]; var correct: Int; var explain: String }

struct GrammarLesson: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var point: String
    var title: String
    var oneLine: String
    var logic: String
    var vietnamese: String
    var examples: [GrammarExample]
    var traps: [String]
    var quickCheck: QuickCheck?
    var followUps: [GrammarQA] = []

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, point, title, oneLine, logic, vietnamese, examples, traps, quickCheck, followUps
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        point = try c.decodeIfPresent(String.self, forKey: .point) ?? ""
        title = try c.decode(String.self, forKey: .title)
        oneLine = try c.decode(String.self, forKey: .oneLine)
        logic = try c.decode(String.self, forKey: .logic)
        vietnamese = try c.decodeIfPresent(String.self, forKey: .vietnamese) ?? ""
        examples = try c.decodeIfPresent([GrammarExample].self, forKey: .examples) ?? []
        traps = try c.decodeIfPresent([String].self, forKey: .traps) ?? []
        quickCheck = try c.decodeIfPresent(QuickCheck.self, forKey: .quickCheck)
        followUps = try c.decodeIfPresent([GrammarQA].self, forKey: .followUps) ?? []
    }
}

struct GrammarQA: Codable, Equatable, Identifiable {
    var id = UUID()
    var q: String
    var a: String
}

struct TranslationGrade: Codable, Equatable {
    var score: Int          // 0–10
    var corrected: String
    var feedback: String
}

// MARK: - Prompts (chuyển thể từ english-master của EngZone)

enum LearnAI {
    static let system = """
    Bạn là gia sư tiếng Anh cho người Việt tự học (logic-first, tự nhiên, không sáo rỗng).
    LUÔN trả về DUY NHẤT một khối JSON hợp lệ theo đúng schema được yêu cầu — không markdown, \
    không lời dẫn, không giải thích ngoài JSON. Tiếng Việt tự nhiên như người bản xứ. \
    Tự viết định nghĩa bằng lời của bạn (không chép từ điển). IPA chính xác, UK/US có thể khác nhau.
    """

    private static let senseSchema = #"{"guideword":"NGHĨA TÓM TẮT IN HOA","level":"A2|B1|B2|C1|C2","defEN":"định nghĩa tiếng Anh","defVI":"định nghĩa tiếng Việt","examples":[{"en":"câu ví dụ","vi":"bản dịch"}]}"#

    static func wordBatch(topic: String, level: String, count: Int, exclude: [String]) -> String {
        """
        Tạo \(count) mục từ tiếng Anh hữu ích, chủ đề: "\(topic.isEmpty ? "tổng hợp" : topic)", trình độ \(level).
        Mỗi mục là một từ điển nhỏ: từ đa nghĩa có 2–3 sense (mỗi sense có guideword + level riêng), 1–2 ví dụ/sense.
        KHÔNG dùng các từ sau: \(exclude.prefix(400).joined(separator: ", ")).
        Schema: [{"headword":"...","pos":"noun|verb|adjective|adverb|phrasal verb|idiom…","ipaUK":"/.../","ipaUS":"/.../","senses":[\(senseSchema)]}]
        """
    }

    static let essayMinWords = [1: 100, 2: 200, 3: 300, 4: 400, 5: 500]

    static func essay(topic: String, level: Int) -> String {
        let minWords = essayMinWords[level] ?? 300
        return """
        /essay \(topic) \(level)
        Viết essay TỐI THIỂU \(minWords) từ. Văn phong TỰ NHIÊN như người thật viết: có giọng cá nhân, \
        ví dụ/chi tiết cụ thể, chuyển ý mượt; TRÁNH lối viết máy móc, sáo rỗng, liệt kê cứng nhắc kiểu AI.
        Chọn 8–12 từ vựng đáng học trong bài (từ đơn, đúng dạng xuất hiện hoặc dạng gốc), và 2–3 họ từ (word family) từ các từ đó.
        "sentences" = TẤT CẢ các câu của bài theo thứ tự, mỗi câu kèm bản dịch tiếng Việt tự nhiên.
        Schema: {"title":"tiêu đề","essay":"toàn bài, các đoạn ngăn bằng \\n\\n","sentences":[{"en":"...","vi":"..."}],\
        "vocab":[{"word":"...","pos":"...","ipaUK":"/.../","ipaUS":"/.../","guideword":"IN HOA","level":"B1..C2",\
        "short":"nghĩa ngắn 1-4 từ","defEN":"định nghĩa tiếng Anh","defVI":"nghĩa tiếng Việt chi tiết, 1 câu, đúng sắc thái trong bài",\
        "example":{"en":"câu ví dụ MỚI (khác câu trong bài)","vi":"bản dịch"}}],\
        "families":[{"root":"từ gốc","members":[{"word":"dạng từ","pos":"noun|verb|adjective|adverb","meaning":"nghĩa tiếng Việt"}]}]}
        """
    }

    static func lookup(word: String, sentence: String) -> String {
        """
        Tra nghĩa của từ "\(word)" theo ĐÚNG ngữ cảnh câu sau: "\(sentence)"
        "lemma" = dạng gốc (từ điển) của từ. "defVI" giải thích nghĩa trong ngữ cảnh này.
        Schema: {"word":"\(word)","lemma":"...","pos":"...","ipaUK":"/.../","ipaUS":"/.../","guideword":"IN HOA",\
        "level":"A1..C2","defEN":"...","defVI":"...","example":{"en":"câu ví dụ mới","vi":"bản dịch"}}
        """
    }

    static func grammar(point: String) -> String {
        """
        /grammar \(point)
        Giải thích logic-first cho người Việt:
        - oneLine: câu trả lời trực tiếp 1 dòng, không jargon
        - logic: "Tại sao?" — nguyên tắc đằng sau quy tắc (2–5 câu)
        - vietnamese: tiếng Việt diễn đạt ý này khác thế nào
        - examples: 4–5 ví dụ (en + vi); có 1–2 ví dụ kèm "wrong" = câu sai phổ biến tương ứng
        - traps: 2–3 lỗi người Việt hay mắc
        - quickCheck: 1 câu trắc nghiệm kiểm tra hiểu ngay (4 lựa chọn, correct là index 0-3, explain tiếng Việt)
        Schema: {"title":"tên điểm ngữ pháp","oneLine":"...","logic":"...","vietnamese":"...",\
        "examples":[{"en":"...","vi":"...","wrong":"câu sai hoặc null"}],"traps":["..."],\
        "quickCheck":{"q":"...","options":["..","..","..",".."],"correct":0,"explain":"..."}}
        """
    }

    static func grammarFollowUp(lesson: GrammarLesson, question: String) -> String {
        """
        Bối cảnh: bài ngữ pháp "\(lesson.title)" — \(lesson.oneLine)
        Người học hỏi thêm: "\(question)"
        Trả lời NGẮN GỌN (tối đa ~120 từ), tiếng Việt, có ví dụ tiếng Anh nếu cần.
        Schema: {"a":"câu trả lời (có thể xuống dòng bằng \\n)"}
        """
    }

    static func gradeTranslation(vi: String, reference: String, answer: String) -> String {
        """
        Người học dịch câu tiếng Việt sang tiếng Anh.
        Câu gốc (VI): "\(vi)"
        Bản tham khảo (EN): "\(reference)"
        Bài làm: "\(answer)"
        Chấm theo độ đúng nghĩa + ngữ pháp + tự nhiên (không bắt buộc giống bản tham khảo).
        Schema: {"score":0-10,"corrected":"bản sửa tự nhiên nhất dựa trên bài làm","feedback":"nhận xét ngắn tiếng Việt, chỉ ra lỗi chính"}
        """
    }
}

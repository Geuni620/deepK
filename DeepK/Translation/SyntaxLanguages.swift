import Foundation

/// How one language family is scanned: its words, comments and strings. Values only; `SyntaxHighlighter` reads them.
struct SyntaxGrammar: Sendable {
    /// Families with rules of their own; `.code` covers the C-like, Python, Ruby and SQL grammars.
    enum Family: Sendable { case code, shell, text, json, yaml, toml, markup, css }
    enum RawStrings: Sendable { case rust, cpp }

    let name: String
    var family = Family.code
    var keywords: Set<String> = []
    var types: Set<String> = []
    /// true, false, null and the like; drawn as keywords.
    var literals: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    /// Rust and Swift block comments nest.
    var nestsComments = false
    /// Quotes of single-line strings; a backslash escapes.
    var quotes: Set<UInt16> = [0x22, 0x27]
    /// Delimiters of strings that may span lines, longest first. Their index is a line state.
    var multilineStrings: [String] = []
    /// Multi-line strings whose backslash is a plain character (Go's raw backtick strings).
    var rawMultilineStrings: Set<String> = []
    /// Letters that may prefix a string (Python's r, b, f; Rust's b, r), matched lowercased.
    var stringPrefixes: Set<String> = []
    /// A keyword that names what it declares: `def` makes the next word a function, `class` a type.
    var definitions: [String: SyntaxTokenKind] = [:]
    /// A capitalized word is a type name.
    var capitalizedTypes = false
    /// What `@name` is: a decorator or annotation (function), a Ruby instance variable (property), or nothing.
    var atNames: SyntaxTokenKind?
    /// Raw strings with a delimiter of their own: Rust `r#"…"#`, C++ `R"x(…)x"`.
    var rawStrings: RawStrings?
    /// C preprocessor lines and Swift's `#if`: `#name` at the line start is a keyword.
    var directives = false
    /// Rust macros: `name!` is a function.
    var macros = false
    /// Rust lifetimes: `'a` without a closing quote is a type.
    var lifetimes = false
    /// `$` is part of a name (JavaScript).
    var dollarNames = false
    /// SQL: words match their sets lowercased.
    var caseInsensitive = false
}

/// Fence tags and the grammar each one uses. Tags are matched lowercased; anything else gets no color.
enum SyntaxLanguages {
    static func grammar(for tag: String?) -> SyntaxGrammar? {
        guard let tag, !tag.isEmpty else { return nil }
        return aliases[tag.lowercased()]
    }

    /// Every tag the highlighter colors.
    static var tags: Set<String> { Set(aliases.keys) }

    private static let aliases: [String: SyntaxGrammar] = {
        var table: [String: SyntaxGrammar] = [:]
        func add(_ tags: [String], _ grammar: SyntaxGrammar) { for tag in tags { table[tag] = grammar } }
        add(["ts", "tsx", "mts", "cts", "typescript"], typescript)
        add(["js", "jsx", "mjs", "cjs", "javascript"], javascript)
        add(["py", "python", "python3"], python)
        add(["swift"], swift)
        add(["go", "golang"], go)
        add(["rs", "rust"], rust)
        add(["java"], java)
        add(["kt", "kts", "kotlin"], kotlin)
        add(["c", "h"], c)
        add(["cpp", "c++", "cc", "cxx", "hpp"], cpp)
        add(["rb", "ruby"], ruby)
        add(["sh", "bash", "zsh", "shell"], shell)
        add(["json", "jsonc", "json5"], json)
        add(["yaml", "yml"], yaml)
        add(["toml"], toml)
        add(["html", "htm", "vue", "svelte", "astro"], html)
        add(["xml", "svg", "plist"], xml)
        add(["css", "scss", "sass", "less"], css)
        add(["sql"], sql)
        add(["text", "txt", "plaintext", "plain", "console", "terminal", "shell-session"], text)
        return table
    }()

    private static func words(_ list: String) -> Set<String> { Set(list.split(separator: " ").map(String.init)) }

    // MARK: - C-like

    private static let ecmaKeywords = words("""
    break case catch class const continue debugger default delete do else export extends finally for function if import in \
    instanceof new return super switch this throw try typeof var void while with yield let static async await of get set from as
    """)
    private static let ecmaLiterals = words("true false null undefined NaN Infinity")
    private static let ecmaDefinitions: [String: SyntaxTokenKind] = ["function": .function, "class": .type]

    static let javascript = SyntaxGrammar(
        name: "javascript", keywords: ecmaKeywords, literals: ecmaLiterals, lineComments: ["//"], blockComment: ("/*", "*/"),
        multilineStrings: ["`"], definitions: ecmaDefinitions, atNames: .function, dollarNames: true
    )

    static let typescript = SyntaxGrammar(
        name: "typescript",
        keywords: ecmaKeywords.union(words("""
        enum implements interface package private protected public type declare namespace module abstract readonly keyof infer \
        is satisfies override accessor asserts unique
        """)),
        types: words("string number boolean any unknown never object symbol bigint"),
        literals: ecmaLiterals, lineComments: ["//"], blockComment: ("/*", "*/"), multilineStrings: ["`"],
        definitions: ecmaDefinitions.merging(["interface": .type, "type": .type, "enum": .type]) { $1 },
        capitalizedTypes: true, atNames: .function, dollarNames: true
    )

    static let python = SyntaxGrammar(
        name: "python",
        keywords: words("""
        and as assert async await break class continue def del elif else except finally for from global if import in is lambda \
        nonlocal not or pass raise return try while with yield
        """),
        types: words("""
        int float complex str bytes bytearray bool list dict set frozenset tuple object type range memoryview Exception \
        BaseException ValueError TypeError KeyError IndexError RuntimeError
        """),
        literals: words("True False None"), lineComments: ["#"], multilineStrings: ["\"\"\"", "'''"],
        stringPrefixes: words("r u b f rb br fr rf"), definitions: ["def": .function, "class": .type], atNames: .function
    )

    static let swift = SyntaxGrammar(
        name: "swift",
        keywords: words("""
        associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private \
        precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer \
        do else fallthrough for guard if in repeat return throw switch where while as is try await async throws super self Self \
        some any actor nonisolated isolated consuming borrowing mutating nonmutating override final lazy weak unowned \
        convenience required optional dynamic indirect get set willSet didSet macro package sending
        """),
        types: words("Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float Bool String Character Void Never"),
        literals: words("true false nil"), lineComments: ["//"], blockComment: ("/*", "*/"), nestsComments: true,
        quotes: [0x22], multilineStrings: ["\"\"\""],
        definitions: ["func": .function, "class": .type, "struct": .type, "enum": .type, "protocol": .type, "extension": .type,
                      "actor": .type, "typealias": .type],
        capitalizedTypes: true, atNames: .function, directives: true
    )

    static let go = SyntaxGrammar(
        name: "go",
        keywords: words("""
        break case chan const continue default defer else fallthrough for func go goto if import interface map package range \
        return select struct switch type var
        """),
        types: words("""
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 \
        uint64 uintptr any comparable
        """),
        literals: words("true false nil iota"), lineComments: ["//"], blockComment: ("/*", "*/"),
        multilineStrings: ["`"], rawMultilineStrings: ["`"], definitions: ["func": .function, "type": .type]
    )

    static let rust = SyntaxGrammar(
        name: "rust",
        keywords: words("""
        as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref \
        return self static struct super trait type unsafe use where while union macro_rules
        """),
        types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Self"),
        literals: words("true false None Some Ok Err"), lineComments: ["//"], blockComment: ("/*", "*/"), nestsComments: true,
        quotes: [0x22, 0x27], multilineStrings: ["\""], stringPrefixes: words("b r br"),
        definitions: ["fn": .function, "struct": .type, "enum": .type, "trait": .type, "type": .type, "union": .type],
        capitalizedTypes: true, rawStrings: .rust, macros: true, lifetimes: true
    )

    static let java = SyntaxGrammar(
        name: "java",
        keywords: words("""
        abstract assert break case catch class const continue default do else enum exports extends final finally for goto if \
        implements import instanceof interface module native new non-sealed open opens package permits private protected \
        provides public record requires return sealed static strictfp super switch synchronized this throw throws to transient \
        transitive try uses var void volatile when while with yield boolean byte char short int long float double
        """),
        literals: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"), multilineStrings: ["\"\"\""],
        definitions: ["class": .type, "interface": .type, "enum": .type, "record": .type],
        capitalizedTypes: true, atNames: .function
    )

    static let kotlin = SyntaxGrammar(
        name: "kotlin",
        keywords: words("""
        as break class continue do else for fun if in interface is object package return super this throw try typealias typeof \
        val var when while by catch constructor delegate dynamic field file finally get import init param property receiver \
        set setparam value where abstract actual annotation companion const crossinline data enum expect external final infix \
        inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend \
        tailrec vararg
        """),
        literals: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"), nestsComments: true,
        multilineStrings: ["\"\"\""],
        definitions: ["fun": .function, "class": .type, "interface": .type, "object": .type, "typealias": .type],
        capitalizedTypes: true, atNames: .function
    )

    private static let cKeywords = words("""
    auto break case char const continue default do double else enum extern float for goto if inline int long register \
    restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Alignas _Alignof \
    _Atomic _Bool _Complex _Generic _Imaginary _Noreturn _Static_assert _Thread_local bool
    """)
    private static let cTypes = words("""
    size_t ssize_t ptrdiff_t intptr_t uintptr_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE
    """)

    static let c = SyntaxGrammar(
        name: "c", keywords: cKeywords, types: cTypes, literals: words("true false NULL"), lineComments: ["//"],
        blockComment: ("/*", "*/"), definitions: ["struct": .type, "union": .type, "enum": .type], directives: true
    )

    static let cpp = SyntaxGrammar(
        name: "cpp",
        keywords: cKeywords.union(words("""
        alignas alignof and and_eq asm bitand bitor catch char8_t char16_t char32_t class co_await co_return co_yield compl \
        concept const_cast consteval constexpr constinit decltype delete dynamic_cast explicit export friend mutable namespace \
        new noexcept not not_eq operator or or_eq private protected public reinterpret_cast requires static_assert static_cast \
        template this thread_local throw try typeid typename using virtual wchar_t xor xor_eq override final
        """)),
        types: cTypes.union(words("string vector map set unordered_map unique_ptr shared_ptr optional")),
        literals: words("true false nullptr NULL"), lineComments: ["//"], blockComment: ("/*", "*/"),
        definitions: ["class": .type, "struct": .type, "union": .type, "enum": .type, "namespace": .type], rawStrings: .cpp,
        directives: true
    )

    static let ruby = SyntaxGrammar(
        name: "ruby",
        keywords: words("""
        BEGIN END alias and begin break case class def do else elsif end ensure for if in module next not or redo \
        rescue retry return super then undef unless until when while yield require require_relative include extend attr_reader \
        attr_writer attr_accessor private protected public lambda proc raise
        """),
        literals: words("true false nil self"), lineComments: ["#"],
        definitions: ["def": .function, "class": .type, "module": .type], capitalizedTypes: true, atNames: .property
    )

    static let sql = SyntaxGrammar(
        name: "sql",
        keywords: words("""
        select from where insert into values update set delete create table drop alter add column primary key foreign \
        references index view as and or not is in between like ilike join inner left right outer full cross on group by order \
        having limit offset union all distinct case when then else end exists default unique check constraint if begin commit \
        rollback transaction grant revoke with recursive returning asc desc database schema trigger procedure function returns \
        replace temporary temp cascade escape natural using except intersect fetch first next rows only top truncate over \
        partition window rename to
        """),
        types: words("""
        int integer smallint bigint decimal numeric real float double precision char varchar nvarchar text date time timestamp \
        timestamptz interval boolean bool blob serial bigserial uuid json jsonb bytea
        """),
        literals: words("true false null"), lineComments: ["--"], blockComment: ("/*", "*/"), caseInsensitive: true
    )

    // MARK: - Families with rules of their own

    /// Commands and their flags, variables and strings.
    static let shell = SyntaxGrammar(
        name: "shell", family: .shell,
        keywords: words("""
        if then else elif fi case esac for select while until do done in function time return exit export local readonly \
        declare unset break continue shift trap source
        """),
        multilineStrings: ["\"", "'"], rawMultilineStrings: ["'"]
    )

    /// Plain text, except a command line: a prompt (`$ `, `% `, `> `, `› `, `❯ `, `# `) or a slash command (`/impeccable document`).
    static let text = SyntaxGrammar(name: "text", family: .text, keywords: shell.keywords)

    static let json = SyntaxGrammar(
        name: "json", family: .json, literals: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"),
        quotes: [0x22, 0x27]
    )

    static let yaml = SyntaxGrammar(
        name: "yaml", family: .yaml, literals: words("true false yes no on off null True False Yes No On Off Null TRUE FALSE NULL ~")
    )

    static let toml = SyntaxGrammar(
        name: "toml", family: .toml, literals: words("true false inf nan"), lineComments: ["#"],
        multilineStrings: ["\"\"\"", "'''"], rawMultilineStrings: ["'''"]
    )

    static let html = SyntaxGrammar(name: "html", family: .markup)
    static let xml = SyntaxGrammar(name: "xml", family: .markup)

    static let css = SyntaxGrammar(name: "css", family: .css, lineComments: ["//"], blockComment: ("/*", "*/"))
}

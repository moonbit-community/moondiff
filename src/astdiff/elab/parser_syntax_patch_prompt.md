# Prompt for Codex in `moonbitlang/parser`

把下面这段直接贴给 parser 仓库里的 Codex 即可:

---

请在当前 `moonbitlang/parser` 仓库里补齐 `syntax` AST 的源码位置信息, 目标是让下游 `astdiff/elab` 可以精确恢复 token 级结构, 不再依赖 synthetic node 或 TODO 注释兜底。

## 目标

按增量方式修改 AST:

- 优先新增 `loc` / `*_loc` / `kind` 字段, 尽量不要破坏现有语义字段
- 某些节点可能不是直接来自源码, 这种情况可以用 `Location?`
- 如果一个变体当前把两种源码写法归一化成一个语义节点, 要么拆变体, 要么补一个明确的 `kind`
- 修改完成后, 同步修 parser 内部所有受影响的构造代码、visitor、json_repr、测试和 `pkg.generated.mbti`

## 优先级

先完成 P0, 再做 P1。P2 有余力再做。

## P0

1. `syntax/docstring.mbt`
   - 修改 `DocString`
   - 当前:
     - `struct DocString { content : List[String], loc : Location }`
   - 需要补:
     - 每一行 doc 的位置
     - 每一行前缀 `///` / `#|` 的位置
   - 建议:
     - 保留现有字段
     - 新增 `lines : List[DocStringLine]`
     - 新增 `struct DocStringLine { text : String, text_loc : Location, prefix_loc : Location, loc : Location }`

2. `syntax/ast.mbt`
   - 顶层 comments / trivia
   - 当前:
     - `type Impls = List[Impl]`
   - 问题:
     - 顶层普通注释完全丢失
   - 需要:
     - 在 parse 结果里保留顶层 trivia/comment 流
   - 建议:
     - 不要硬改 `Impls` alias
     - 优先新增包装返回类型, 例如:
       - `ParsedImpls { impls : List[Impl], trivia : List[TopLevelTrivia] }`

3. `syntax/ast.mbt`
   - 修改 `Visibility::Pub`
   - 当前:
     - `Pub(attr~ : String?, loc~ : Location)`
   - 需要补:
     - `attr` 的位置
   - 建议:
     - 新增 `attr_loc~ : Location?`

4. `syntax/ast.mbt`
   - 修改 `LongIdent::Dot`
   - 当前:
     - `Dot(pkg~ : String, id~ : String)`
   - 需要补:
     - `pkg`、`.`、`id` 三段的位置
   - 建议:
     - 新增 `pkg_loc~ : Location`
     - 新增 `dot_loc~ : Location`
     - 新增 `id_loc~ : Location`

5. `syntax/ast.mbt`
   - 修改 `ErrorType::DefaultErrorType`
   - 当前:
     - `DefaultErrorType(loc~ : Location)`
   - 问题:
     - 当前把 `raise` 和后缀 `!` 归一化到了同一变体
   - 需要补:
     - 原始 token 种类
   - 建议二选一:
     - 拆成 `RaiseDefaultErrorType(loc~)` 和 `BangDefaultErrorType(loc~)`
     - 或保留一个变体, 新增 `kind~ : DefaultErrorTypeKind`

6. `syntax/ast.mbt`
   - 修改 `ErrorType::MaybeError`
   - 当前:
     - `MaybeError(ty~ : Type)`
   - 需要补:
     - `?` 的位置
   - 建议:
     - 改成 `MaybeError(ty~ : Type, question_loc~ : Location)`

7. `syntax/ast.mbt`
   - 修改 `Argument`
   - 当前:
     - `struct Argument { value : Expr, kind : ArgumentKind }`
   - 需要补:
     - argument 自身的 `loc`

8. `syntax/ast.mbt`
   - 修改 `Parameter`
   - 受影响变体:
     - `Positional`
     - `Labelled`
     - `Optional`
     - `QuestionOptional`
     - `DiscardPositional`
   - 需要补:
     - 参数整体 `loc`
     - `~`、`?`、`:`、`=` 的位置
   - 建议:
     - 每个变体加 `loc~ : Location`
     - 再按需加:
       - `label_mark_loc~ : Location?`
       - `question_loc~ : Location?`
       - `colon_loc~ : Location?`
       - `equal_loc~ : Location?`

9. `syntax/ast.mbt`
   - 修改 `Case`
   - 当前:
     - `struct Case { pattern : Pattern, guard_ : Expr?, body : Expr }`
   - 需要补:
     - `loc`
     - `=>` 的位置
     - 如果 guard 有关键字, 也补关键字位置
   - 建议:
     - 新增 `loc : Location`
     - 新增 `arrow_loc : Location`
     - 可选新增 `guard_loc : Location?`

10. `syntax/ast.mbt`
    - 修改 `DotDotBinder`
    - 受影响变体:
      - `Underscore`
      - `NoBinder`
      - `BinderAs(Binder)`
      - `Binder(Binder)`
    - 需要补:
      - `..` 的位置
    - 建议:
      - 所有变体统一补 `dotdot_loc~ : Location`

11. `syntax/ast.mbt`
    - 修改 `ConstrPatArg`
    - 当前:
      - `struct ConstrPatArg { pat : Pattern, kind : ArgumentKind }`
    - 需要补:
      - 参数整体 `loc`

12. `syntax/ast.mbt`
    - 修改 `ArrayPatterns`
    - 当前:
      - `Closed(List[ArrayPattern])`
      - `Open(List[ArrayPattern], List[ArrayPattern], DotDotBinder)`
    - 需要补:
      - 整体范围
      - `[`、`]` 的位置
    - 建议:
      - `Closed(..., loc~ : Location, lbrack_loc~ : Location, rbrack_loc~ : Location)`
      - `Open(..., loc~ : Location, lbrack_loc~ : Location, rbrack_loc~ : Location)`

13. `syntax/ast.mbt`
    - 修改这些 `Pattern` 变体:
      - `Pattern::Array`
      - `Pattern::Constraint`
      - `Pattern::Constr`
      - `Pattern::Tuple`
      - `Pattern::Record`
      - `Pattern::Map`
      - `Pattern::Range`
      - `Pattern::SpecialConstr`
    - 需要补:
      - 最关键的 token span, 而不只是 aggregate `loc`
    - 最少要求:
      - `Pattern::Constraint` 增 `colon_loc`
      - `Pattern::Range` 增 `op_loc`
      - `Pattern::Tuple` / `Pattern::Record` / `Pattern::Map` 增左右 delimiter loc
      - `Pattern::Constr` / `Pattern::SpecialConstr` 增参数列表 delimiter loc

14. `syntax/ast.mbt`
    - 修改 `LocalTypeDecl`
    - 当前:
      - `struct LocalTypeDecl { tycon, tycon_loc, components, deriving }`
    - 需要补:
      - 整体 `loc`
      - `type` 关键字位置
    - 建议:
      - 新增 `loc : Location`
      - 新增 `type_loc : Location`

15. `syntax/ast.mbt`
    - 修改 `FuncStubs`
    - 受影响变体:
      - `Import(module_name~ : StringLiteral, func_name~ : StringLiteral, language~ : StringLiteral?)`
      - `Embedded(language~ : StringLiteral?, code~ : EmbeddedCode)`
    - 问题:
      - `StringLiteral` 当前只是 `type StringLiteral = String`
    - 需要补:
      - 这些字符串 token 的位置
    - 建议:
      - 引入 `LocatedString`
      - 或直接增加 `module_name_loc` / `func_name_loc` / `language_loc`

16. `syntax/ast.mbt`
    - 修改 `EmbeddedCode`
    - 受影响变体:
      - `CodeString(StringLiteral)`
      - `CodeMultilineString(List[String])`
    - 需要补:
      - `CodeString` 的字符串位置
      - multiline 各行位置
    - 建议:
      - `CodeString` 改成带 `Location`
      - `CodeMultilineString` 改成 `List[LocatedString]`

17. `syntax/ast.mbt`
    - 修改 `DeclBody::DeclNone`
    - 当前:
      - `DeclNone`
    - 需要补:
      - `loc`
    - 建议:
      - 改成 `DeclNone(loc~ : Location?)`

## P1

1. `syntax/ast.mbt`
   - 修改 `Type`
   - 重点变体:
     - `Type::Arrow(args~, res~, err~, is_async~, loc~)`
     - `Type::Tuple(tys~, loc~)`
     - `Type::Name(constr_id~, tys~, loc~)`
     - `Type::Object(ConstrId)`
   - 需要补:
     - `(`、`)`、`,`、`->` 等关键 token 的位置
   - 建议:
     - `Type::Arrow` 增 `arrow_loc`
     - `Type::Tuple` 增 `lparen_loc` / `rparen_loc`
     - `Type::Name` 增 type-application delimiter loc

2. `syntax/ast.mbt`
   - 修改 `ConstrParam`
   - 当前:
     - `struct ConstrParam { ty : Type, mut_ : Bool, label : Label? }`
   - 需要补:
     - 整体 `loc`
     - `mut` 的位置
   - 建议:
     - 增 `loc : Location`
     - 增 `mut_loc : Location?`

3. `syntax/ast.mbt`
   - 修改 `ApplyAttr`
   - 当前:
     - `NoAttr | Exclamation | Question`
   - 需要补:
     - `!` / `?` 的位置
   - 建议:
     - `Exclamation(loc~ : Location)`
     - `Question(loc~ : Location)`

4. `syntax/ast.mbt`
   - 修改 `TypeVarBinder`
   - 当前:
     - `struct TypeVarBinder { name, name_loc, constraints }`
   - 需要补:
     - 整体范围
     - `[`、`]`、`:`、`+` 的位置
   - 建议:
     - 增 `loc : Location`
     - 可选增 `lbrack_loc` / `rbrack_loc` / `colon_loc`

5. `syntax/ast.mbt`
   - 修改 `MultilineStringElem::String`
   - 当前:
     - `String(String)`
   - 需要补:
     - chunk 的位置
   - 建议:
     - 改成 `String(value~ : String, loc~ : Location)`

## P2

1. `syntax/ast.mbt`
   - 修改 `Expr::StaticAssert`
   - 当前:
     - `StaticAssert(asserts~ : List[StaticAssertion], body~ : Expr)`
   - 需要补:
     - 整体 `loc`
   - 建议:
     - 改成 `StaticAssert(asserts~ : List[StaticAssertion], body~ : Expr, loc~ : Location?)`

## 附录

如果你愿意顺手处理一个不在 `syntax` 包里的问题, 再看这个:

1. `attribute/attribute.mbt`
   - 修改 `attribute.Expr`
   - 当前:
     - `enum Expr { Ident(Id), String(StringLiteral), Apply(Id, List[Prop]), Bool(Bool) }`
   - 问题:
     - `Attribute.parsed` 只有结构没有位置信息
   - 建议:
     - 给 `attribute.Expr` 各变体补 `Location`
     - 或让 `Attribute.parsed` 改成一棵带位置的表达式树

## 验收标准

1. `syntax` 包相关代码能通过类型检查和测试。
2. 所有受影响的 visitor / builder / json 输出 / 模式匹配都已同步更新。
3. `pkg.generated.mbti` 已更新。
4. 不要只改类型定义; 必须把 parser 构造 AST 的地方一起改掉。
5. 最终汇报时按以下格式给我:
   - 改了哪些类型
   - 每个类型新增了哪些字段或变体
   - 哪些地方因为兼容性原因没有做
   - 跑了哪些命令验证

---

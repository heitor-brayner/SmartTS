# Design: Project 2 — `pair<T, U>` and Enum Types (Full LLTZ Translation)

**Date:** 2026-07-01  
**Authors:** Heitor Brayner Prado, Renan Guilherme Siqueira de Araújo  
**Milestone:** Third (code generation) — deadline 2026-06-30  
**Branch:** main (clean base after upstream merge `4796304`)

---

## Context

SmartTS Project 2 adds two composite types to the language:

- **`pair<T, U>`** — a two-element product type modelled on Michelson's `Pair`
- **Enum types** — user-defined named variants, a restricted form of Michelson's `or` type

The previous implementation (first milestone) was discarded during the upstream merge because the professor refactored the AST to a parameterized form (`Expr a`, `Stmt a`, `Contract a`) and split the interpreter into sub-modules. This design describes the full re-implementation in the new architecture, including LLTZ code generation.

**Key constraint from class notes:** enum matching in LLTZ must use `Inj`/`Match` (sum-type operations), not integer encoding. Pair projection must use `Proj` on a `TTuple`. This follows the LLTZ IR's typed lambda-calculus semantics.

---

## Architecture Overview

The pipeline is unchanged: source → Parser → TypeCheck → Interpreter (or CodeGen). All five pipeline stages require changes.

```
.smartts source
    │
    ▼
Parser.hs          adds: pair<T,U>, enum decls, pair()/fst()/snd() builtins,
                         EnumLiteral, match stmt, var/val destructuring
    │
    ▼
IR/AST.hs          adds: TPair, TEnum, EnumDecl, PairExpr, Fst, Snd,
                         EnumLiteral, MatchStmt, VarDestructStmt, ValDestructStmt
    │
    ▼
TypeCheck.hs       adds: enum registry in TcEnv, exhaustiveness check,
                         pair/enum type inference, destructuring type check
    │
    ├──► Interpreter/Eval.hs    — evaluate new exprs/stmts at runtime
    │    Interpreter/Codec.hs   — JSON ↔ pair/enum encoding
    │
    └──► CodeGen/CompileLLTZ.hs — translate pair→TTuple/Proj, enum→TOr/Inj/Match
```

---

## Section 1 — AST (`lib/SmartTS/IR/AST.hs`)

### New type constructors

```haskell
data Type
  = ...
  | TPair Type Type    -- pair<int, bool>
  | TEnum Name         -- Light, Phase (resolved by name during type checking)
```

### New top-level declaration

```haskell
data EnumDecl = EnumDecl
  { enumName     :: Name
  , enumVariants :: [Name]
  } deriving (Eq, Show)
```

### Updated `Contract`

```haskell
data Contract a = Contract
  { contractName    :: Name
  , contractStorage :: Storage
  , contractEnums   :: [EnumDecl]     -- NEW: between storage and methods
  , contractMethods :: [MethodDecl a]
  } deriving (Eq, Show)
```

All existing positional patterns in `test/Main.hs` receive `[]` as the new third argument.

### New expression constructors

```haskell
data Expr a
  = ...
  | PairExpr    a (Expr a) (Expr a)   -- pair(e1, e2)
  | Fst         a (Expr a)             -- fst(e)
  | Snd         a (Expr a)             -- snd(e)
  | EnumLiteral a Name                 -- Red, Green (uppercase-first)
```

`exprAnn` gets four new cases.

### New statement constructors

```haskell
data Stmt a
  = ...
  | MatchStmt       (Expr a) [(Name, Stmt a)]    -- match (e) { V => s, ... }
  | VarDestructStmt Name Name Type (Expr a)      -- var (a, b): pair<T,U> = e;
  | ValDestructStmt Name Name Type (Expr a)      -- val (a, b): pair<T,U> = e;
```

---

## Section 2 — Parser (`lib/SmartTS/Parser.hs`)

### Reserved words added

`pair`, `fst`, `snd`, `enum`, `match` — `parseName`/`identifier` will reject them.

### Type parsing

`parseType` gets two new alternatives before the catch-all identifier case:
1. `pair<T, U>` → `TPair t1 t2`
2. Any remaining identifier → `TEnum name` (user-defined enum type reference)

### Expression parsing

Three new alternatives in `parseAtom` (before `parseVarOrCall`):
- `pair(e1, e2)` → `PairExpr () e1 e2`
- `fst(e)` → `Fst () e`
- `snd(e)` → `Snd () e`

`parseVarOrCall` is updated: identifier with uppercase first character → `EnumLiteral () name`; lowercase/mixed → `Var () name` or `Call () name args` (unchanged).

### New parsers

- **`parseEnumDecl`**: `enum Name { V1, V2, ... }` → `EnumDecl`
- **`parseMatchStmt`**: `match (e) { Variant => stmt ... }` — variant parsed by `parseName`, body by `parseStmt`
- **`parseVarDeclStmt`** / **`parseValDeclStmt`**: extended with `try` to handle destructuring form `var (a, b): pair<T,U> = e;` before falling back to the simple `var name: T = e;` form

`parseContract` gains `enums <- many parseEnumDecl` between `parseStorage` and `many parseMethod`.

---

## Section 3 — Type Checker (`lib/SmartTS/TypeCheck.hs`)

### `TcEnv` additions

```haskell
data TcEnv = TcEnv
  { ...
  , envEnumDefs    :: M.Map Name [Name]   -- enum name → variant list
  , envVariantEnum :: M.Map Name Name     -- variant   → enum name
  }
```

Built from `contractEnums` at the start of `typeCheckContract` and threaded into each `checkMethod`.

### Validation in `typeCheckContract`

Before type-checking methods, validate that every `TEnum n` appearing in storage field types, method parameter types, and return types refers to a declared enum. This catches undefined enum references early.

### `typesEqual` / `prettyType` additions

- `typesEqual (TPair a b) (TPair c d) = typesEqual a c && typesEqual b d`
- `typesEqual (TEnum n) (TEnum m) = n == m`
- `prettyType (TPair t1 t2) = "pair<" ++ prettyType t1 ++ ", " ++ prettyType t2 ++ ">"`
- `prettyType (TEnum n) = n`

### `inferExpr` new cases

| Expression | Inference rule |
|---|---|
| `EnumLiteral () v` | Look up `v` in `envVariantEnum`; annotate with `TEnum enumName` or error |
| `PairExpr () e1 e2` | Infer both; annotate with `TPair t1 t2` |
| `Fst () e` | Infer `e`; require `TPair t1 _`; annotate with `t1` |
| `Snd () e` | Infer `e`; require `TPair _ t2`; annotate with `t2` |

### `checkStmt` new cases

| Statement | Checking rule |
|---|---|
| `MatchStmt e cases` | Infer `e`, require `TEnum n`; exhaustiveness (all variants covered, no duplicates, no unknown); check each branch in saved env |
| `VarDestructStmt n1 n2 ann e` | `n1 ≠ n2`, no duplicates; infer `e`, expect `ann = TPair t1 t2`; insert `n1 : t1` and `n2 : t2` as `LocalMutable` |
| `ValDestructStmt n1 n2 ann e` | Same, but `LocalImmutable` |

---

## Section 4 — Interpreter

### `Eval.hs` — new `evalExpr` cases

| Expression | Evaluation |
|---|---|
| `EnumLiteral _ v` | Returns itself (already a value) |
| `PairExpr ty e1 e2` | Eval both; return `PairExpr ty v1 v2` |
| `Fst _ e` | Eval `e` to `PairExpr _ v1 _`; return `v1` |
| `Snd _ e` | Eval `e` to `PairExpr _ _ v2`; return `v2` |

### `Eval.hs` — new `execStmt` cases

| Statement | Execution |
|---|---|
| `MatchStmt e cases` | Eval `e` to `EnumLiteral _ v`; `lookup v cases`; execute matched branch |
| `VarDestructStmt n1 n2 _ e` | Eval `e` to `PairExpr _ v1 v2`; insert both as mutable `Binding`s |
| `ValDestructStmt n1 n2 _ e` | Same, immutable |

All type-impossible branches call `interpretBug`.

### `Codec.hs` — JSON encoding

| Value | JSON |
|---|---|
| `PairExpr _ v1 v2` | `{"fst": encode(v1), "snd": encode(v2)}` |
| `EnumLiteral _ v` | `"VariantName"` (JSON string) |

Decoding: `TPair t1 t2` reads `"fst"` and `"snd"` keys from a JSON object; `TEnum _` reads a JSON string and returns `EnumLiteral t variant`.

Example — `VotingBox` storage at rest:
```json
{"phase": "Open", "result": {"fst": 0, "snd": 0}, "votesFor": 0, "votesAgainst": 0}
```

Requires `import qualified Data.Text as T` for `T.pack`/`T.unpack`.

---

## Section 5 — LLTZ Code Generation (`lib/SmartTS/CodeGen/CompileLLTZ.hs`)

### Context threading

```haskell
type EnumDefs = M.Map Name [Name]
buildEnumDefs :: TypedContract -> EnumDefs
```

All translation functions gain an `EnumDefs` first parameter.

### Type translation

| SmartTS type | LLTZ type |
|---|---|
| `TPair t1 t2` | `TTuple (RowNode [RowLeaf Nothing t1', RowLeaf Nothing t2'])` |
| `TEnum name` | `TOr (RowNode [RowLeaf (Just (Label v)) TUnit \| v <- variants])` |

### Expression translation

| SmartTS expression | LLTZ expression |
|---|---|
| `PairExpr ty e1 e2` | `TupleExpr (RowNode [RowLeaf Nothing e1', RowLeaf Nothing e2'])` |
| `Fst ty e` | `Proj e' (RowPath [0])` |
| `Snd ty e` | `Proj e' (RowPath [1])` |
| `EnumLiteral (TEnum n) v` | `Inj (RowCtxNode lefts (RowLeaf (Just (Label v)) TUnit) rights) (Const CUnit)` |

For `EnumLiteral`, `lefts`/`rights` are computed by splitting the variant list at `v`'s position.

### Statement translation

**`MatchStmt e cases`** — cases are reordered to match the enum's definition order (required by `Match`'s positional row), then:
```
Match e' (RowNode [RowLeaf (Just (Label v)) (LambdaBinder (Var "_", TUnit) body') | (v, body') <- orderedCases])
```
Result type = type of first branch body.

**`VarDestructStmt n1 n2 _ e`** — handled in `translateBlock` (not `translateStatement`), alongside `VarDeclStmt`/`ValDeclStmt`, because it introduces two bindings that the rest of the block uses:
```
LetMutIn n1 (Proj e' (RowPath [0])) (LetMutIn n2 (Proj e' (RowPath [1])) restBlock)
```

**`ValDestructStmt n1 n2 _ e`:** Same with `LetIn`. Also handled in `translateBlock`.

### Completing existing TODOs

The arithmetic (`Add`, `Sub`, `Mul`, `Div`, `Mod`) and comparison (`Eq`, `Neq`, `Lt`, `Lte`, `Gt`, `Gte`) expression translations are also filled in, since the sample contracts (`Counter`, `TrafficLight`, `VotingBox`) require them to generate valid LLTZ.

---

## Section 6 — Tests and Samples

### `test/Main.hs`

- All existing `Contract name storage methods` positional patterns updated to `Contract name storage [] methods`
- New parser tests: `pair<T,U>` type, `pair(e1,e2)` expression, `fst`/`snd`, enum declaration, enum literal, match statement, destructuring declaration
- New type-checker tests: exhaustiveness failure, unknown variant, `fst`/`snd` on wrong type, pair destructuring type mismatch
- New interpreter test: originate and call `TrafficLight` or `VotingBox` end-to-end via `originateWithJsonArgs` / `callEntrypointWithJsonArgs`

### `samples/`

`TrafficLight.smartts` and `VotingBox.smartts` already exist and reflect the desired behavior. They should parse, type-check, and execute correctly after all changes.

---

## File Change Summary

| File | Change type |
|---|---|
| `lib/SmartTS/IR/AST.hs` | Add types, constructors, `EnumDecl`, update `Contract` |
| `lib/SmartTS/Parser.hs` | Add keywords, type/expr/stmt parsers, update `parseContract` |
| `lib/SmartTS/TypeCheck.hs` | Add enum registry, new inference/checking cases, validation |
| `lib/SmartTS/Interpreter/Eval.hs` | Add eval/exec cases for new nodes |
| `lib/SmartTS/Interpreter/Codec.hs` | Add JSON encoding/decoding for pair and enum |
| `lib/SmartTS/CodeGen/CompileLLTZ.hs` | Add `EnumDefs` context, translate pair/enum, fill TODOs |
| `test/Main.hs` | Update patterns, add new test cases |

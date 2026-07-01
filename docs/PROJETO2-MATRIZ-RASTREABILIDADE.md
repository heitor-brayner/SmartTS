# Project 2 — Matriz de rastreabilidade

## Como ler

Cada linha conecta um requisito ou decisão a quatro evidências: representação,
validação/semântica, tradução e teste. A matriz serve para responder “onde isso
está implementado?” sem depender de memória vaga.

Abreviações:

- `AST`: `lib/SmartTS/IR/AST.hs`
- `Parser`: `lib/SmartTS/Parser.hs`
- `TC`: `lib/SmartTS/TypeCheck.hs`
- `Eval`: `lib/SmartTS/Interpreter/Eval.hs`
- `Codec`: `lib/SmartTS/Interpreter/Codec.hs`
- `Contract`: `lib/SmartTS/Interpreter/Contract.hs`
- `LLTZ`: `lib/SmartTS/CodeGen/CompileLLTZ.hs`
- `Tests`: `test/Main.hs`

## Requisitos do enunciado

| Requisito | Representação/parser | Checker/semântica | LLTZ | Testes principais | Estado |
|---|---|---|---|---|---|
| Tipo `pair<T,U>` | `TPair`; `parsePairType` | `typesEqual`; `checkEnumRefs` recursivo | `translateType -> TTuple` | `pair type in return type`; `pair type is well-typed`; `pair type → TTuple` | Completo |
| Construtor `pair(e1,e2)` | `PairExpr`; `parsePairBuiltin` | infere ambos e produz `TPair` | `TupleExpr` | `pair constructor expression`; `pair expression → TupleExpr` | Completo |
| `fst(e)` | `Fst`; `parseFstBuiltin` | exige pair e retorna componente 1 | `Proj [0]` | `fst returns first type`; `fst on non-pair fails`; `fst evaluates a stored pair` | Completo |
| `snd(e)` | `Snd`; `parseSndBuiltin` | exige pair e retorna componente 2 | `Proj [1]` | `snd returns second type`; `snd on non-pair fails` | Completo |
| Pair estrutural | `TPair Type Type` | `typesEqual` recursivo | `TTuple` sem identidade nominal | `pair values support structural equality` | Completo |
| Desestruturação `var` | `VarDestructStmt`; parser de declaração | dois `LocalMutable`; avalia uma vez | dois `LetMutIn`/`Proj` | `var destructuring`; `var destructuring is well-typed` | Completo no interpretador; ressalva LLTZ com efeitos |
| Desestruturação `val` | `ValDestructStmt` | dois `LocalImmutable`; avalia uma vez | dois `LetIn`/`Proj` | `val destructuring`; `val destructuring binds both pair components` | Completo no interpretador; ressalva LLTZ com efeitos |
| Declaração enum | `EnumDecl`; `contractEnums`; `parseEnumDecl` | `validateEnumDecls` | `buildEnumDefs` | `enum declaration`; `buildEnumDefs preserves declaration order` | Completo |
| Enum nominal | `TEnum Name` | `typesEqual` compara nome | identidade apagada para forma `TOr` | `enum values support nominal equality` | Completo |
| Variante como valor | `EnumLiteral`; capitalização | `envVariantEnum` infere tipo | `Inj` com `unit` | `enum literal`; `enum literal → Inj at variant position` | Completo |
| Igualdade enum | `Eq`/`Neq` existentes | exige mesmo `TEnum`; runtime compara valores | `COMPARE` + flag | `enum values support nominal equality` | Completo |
| `match` | `MatchStmt`; `parseMatchStmt` | discriminante deve ser enum | `Match` | `match statement`; `match dispatches to selected enum branch` | Completo |
| Exaustividade | cases no `MatchStmt` | calcula ausentes/desconhecidos/duplicados | branches completos | `exhaustive match`; `non-exhaustive match fails` | Completo |
| Registro separado | `contractEnums` | `envEnumDefs`, `envVariantEnum` separados de `envBindings` | `EnumDefs` próprio | testes de enum e colisão | Completo |
| Parser + checker + interpreter | novos nós em todas as fases | árvore tipada consumida por `Eval` | — | grupos Parser, TC e Interpreter | Completo |
| Testes e samples | `TrafficLight.smartts`, `VotingBox.smartts` | arquivos reais executados end-to-end | tipos/expressões cobertos | 117 testes | Completo |
| Terceiro milestone | — | — | SmartTS → LLTZ | 13 testes LLTZ | Completo no limite LLTZ; sem backend Michelson |

## Invariantes adicionais da equipe

| Invariante | Motivo | Implementação | Teste |
|---|---|---|---|
| Nome de enum único | impedir sobrescrita em `Map` | `validateEnumDecls` | `duplicate enum names fail` |
| Pelo menos duas variantes | interpretação direta como soma | `length variants < 2` | `enum with fewer than two variants fails` |
| Variante única no enum | eliminar definição ambígua | `nub variants` | `duplicate variants in one enum fail` |
| Variante globalmente única | literal não qualificado | `nub allVariants` | `variant names shared by different enums fail` |
| Inicial maiúscula | distinguir `EnumLiteral` de `Var` | parser + `validateVariantName` | `lowercase enum variant fails` |
| Referência enum declarada | evitar `TEnum` órfão | `checkEnumRefs` | `undefined enum in storage fails` |
| Nomes distintos na desestruturação | não sobrescrever binding simultâneo | `when (n1 == n2)` | `destructuring with the same name fails` |
| Cases únicos | um comportamento por variante | `nub covered` | checker de match |
| Tipo LLTZ igual nos branches | requisito de junção/`IF_LEFT` | comparação de `exprType` | `match translation rejects inconsistent branch result types` |
| JSON enum válido | preservar invariantes na fronteira externa | `EnumRegistry` no codec | `unknown enum variant is rejected` |

## Fluxo de arquivos contra `main`

| Arquivo | Responsabilidade da mudança | Risco principal controlado |
|---|---|---|
| `IR/AST.hs` | novos tipos/nós e lista de enums | quebra de pattern matching existente |
| `Parser.hs` | sintaxe, reservadas e convenção de maiúscula | ambiguidade `Var`/`EnumLiteral` |
| `TypeCheck.hs` | nominalidade, inferência e exaustividade | aceitar árvore semanticamente inválida |
| `Eval.hs` | semântica operacional | avaliar/desestruturar incorretamente |
| `Codec.hs` | JSON de pair/enum | injetar variante inválida externamente |
| `Contract.hs` | propagar registro ao codec | perder validação em args/storage |
| `CompileLLTZ.hs` | produto/soma, projeção/injeção/match | desalinhamento de posições/tipos |
| `test/Main.hs` | regressão em todas as fronteiras | “funciona apenas no parser” |

## Lacunas rastreadas, não escondidas

| Lacuna | Onde aparece | Impacto |
|---|---|---|
| Sem LLTZ → Michelson | não há módulo de lowering | não afirmar geração Michelson final |
| Sem compilação completa de contrato | `CompileLLTZ` expõe funções parciais | validação limitada a tipos/expressões/statements suportados |
| Storage/calls/div/mod incompletos | `error` explícito no codegen | samples executam no interpretador, não no backend |
| Desestruturação LLTZ duplica árvore da expressão | `translateBlock` | futuro risco de avaliação dupla quando houver efeitos |
| Variante não qualificada | parser por maiúscula | exige unicidade global |

## Comandos de evidência

```powershell
$env:GHC_CHARENC = "UTF-8"
cabal build all
cabal test all --test-show-details=direct
git diff main...HEAD --stat
```

Resultado verificado: `All 117 tests passed` com GHC 9.10.3.


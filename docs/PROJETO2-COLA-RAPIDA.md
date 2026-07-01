# Project 2 — Cola rápida para a banca

> Consulta de última hora. Para justificativas completas, veja
> [Decisões arquiteturais](PROJETO2-DECISOES-ARQUITETURAIS.md).

## Resposta de abertura em 30 segundos

> Estendemos a `main`, que já usa AST parametrizado, com pair estrutural e enum
> nominal. O parser reconhece construção, projeção, desestruturação e match. O
> checker mantém um registro de enums separado dos bindings e garante tipos e
> exaustividade. O interpretador executa os novos nós; o codec valida JSON
> contra o registro nominal. No LLTZ, pair vira `TTuple`/`Proj` e enum vira
> `TOr`/`Inj`/`Match`. São 108 testes passando. A branch termina no LLTZ, não
> em Michelson final.

## Regras de tipo essenciais

```text
e1 : T    e2 : U
-------------------------
pair(e1,e2) : pair<T,U>

e : pair<T,U>             e : pair<T,U>
---------------           ---------------
fst(e) : T                snd(e) : U

variantEnum[V] = E
--------------------------
V : E

e : E    cases = variants(E)
-------------------------------
match(e) { cases } é exaustivo
```

## Estrutural versus nominal

| Tipo | Igualdade | Frase para lembrar |
|---|---|---|
| `pair<T,U>` | Recursiva pelos componentes | “Pair é definido pela forma.” |
| `TEnum Name` | Pelo nome declarado | “Enum é definido pela identidade.” |

```text
pair<int,bool> = pair<int,bool>
Color != Status, mesmo com a mesma quantidade de variantes
```

## AST novo

```text
Type: TPair, TEnum
Contract: contractEnums :: [EnumDecl]
Expr: PairExpr, Fst, Snd, EnumLiteral
Stmt: MatchStmt, VarDestructStmt, ValDestructStmt
```

## Registro nominal

```text
envEnumDefs:    enum -> variantes ordenadas
envVariantEnum: variante -> enum
envBindings:    variável -> tipo/mutabilidade
```

Por que separado? Tipos enum têm escopo de contrato; bindings têm escopo de
bloco/método.

## Invariantes de enum

- pelo menos duas variantes;
- nomes de enum únicos;
- variantes únicas no próprio enum;
- variantes globalmente únicas;
- variantes começam com maiúscula;
- toda referência `TEnum` aponta para declaração existente.

As três primeiras evitam representações inválidas/ambíguas. A unicidade global
e a maiúscula decorrem da sintaxe não qualificada `Red`; `Color.Red` seria uma
alternativa futura.

## Match

```text
missing = variantes declaradas - cases
unknown = cases - variantes declaradas
duplicate = tamanho(cases) != tamanho(nub cases)
```

Todos devem estar vazios/falsos. Cada branch usa escopo salvo. No LLTZ, cases
são reordenados conforme a declaração e todos devem ter o mesmo tipo final.

## Desestruturação

```typescript
var (a, b): pair<int, bool> = p; // ambos mutáveis
val (a, b): pair<int, bool> = p; // ambos imutáveis
```

O interpretador avalia `p` uma vez, extrai dois valores e cria dois bindings.

## JSON

```json
{"fst": 1, "snd": true}
"Red"
```

```haskell
jsonToExprByType :: EnumRegistry -> Type -> Value -> Either String TypedExpr
```

O registro impede aceitar `"Purple"` para `Color { Red, Green }`.

## SmartTS → LLTZ → intenção Michelson

| SmartTS | LLTZ | Michelson pretendido |
|---|---|---|
| `pair<T,U>` | `TTuple` | `pair T U` |
| `pair(a,b)` | `TupleExpr` | `PAIR` |
| `fst` | `Proj [0]` | `CAR` |
| `snd` | `Proj [1]` | `CDR` |
| Enum | `TOr` | `or` aninhado |
| Variante | `Inj unit` | `LEFT`/`RIGHT` |
| `match` | `Match` | `IF_LEFT` aninhado |

## Assinaturas Michelson para memorizar

```text
PAIR    :: ty1 : ty2 : A -> pair ty1 ty2 : A
CAR     :: pair ty1 ty2 : A -> ty1 : A
CDR     :: pair ty1 ty2 : A -> ty2 : A
LEFT    :: ty1 : A -> or ty1 ty2 : A
RIGHT   :: ty2 : A -> or ty1 ty2 : A
IF_LEFT :: or ty1 ty2 : A -> B
```

O topo da stack é o tipo mais à esquerda. Os dois branches de `IF_LEFT` devem
produzir a mesma stack `B`. Não existe instrução `IF_RIGHT` na referência.

## Enum de três variantes

```text
E = or unit (or unit unit)
A = Left Unit
B = Right (Left Unit)
C = Right (Right Unit)
```

## Evidência de qualidade

```powershell
$env:GHC_CHARENC = "UTF-8"
cabal build all
cabal test all --test-show-details=direct
```

```text
GHC 9.10.3
All 108 tests passed
```

## Limitações que devem ser admitidas

- não há backend LLTZ → Michelson;
- não há compilação completa de `TypedContract`;
- storage/field access/calls/div/mod permanecem incompletos no codegen base;
- row enum n-ária ainda não é baixada para árvore binária concreta;
- desestruturação LLTZ deve ganhar binding temporário quando houver efeitos.

## Cinco erros fatais na resposta

1. Dizer que enum é inteiro.
2. Dizer que enum é estrutural.
3. Dizer que exaustividade é verificada só no runtime.
4. Dizer que `IF_RIGHT` elimina o branch direito.
5. Dizer que a branch gera Michelson completo.


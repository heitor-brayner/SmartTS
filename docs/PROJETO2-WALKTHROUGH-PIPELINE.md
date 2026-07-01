# Project 2 — Walkthrough completo pelo pipeline

## Objetivo

Este documento acompanha um contrato da fonte ao LLTZ. Ele serve para treinar
respostas como “o que acontece com esse código em cada estágio?” e para
conectar módulos que, vistos separadamente, podem parecer independentes.

## Contrato usado

```typescript
contract Selector {
  storage: { last: int };

  enum Side { LeftSide, RightSide }

  @originate
  init(): unit {
    storage.last = 0;
    return ();
  }

  @entrypoint
  choose(side: Side, p: pair<int, int>): int {
    val (left, right): pair<int, int> = p;
    match (side) {
      RightSide => { return right; }
      LeftSide  => { return left; }
    }
  }
}
```

O exemplo combina enum nominal, pair estrutural, desestruturação e match. Os
cases estão propositalmente fora da ordem da declaração para demonstrar a
normalização LLTZ.

## Etapa 1 — Lexer integrado e parser

### Entrada

Uma `String` contendo o contrato.

### Decisões léxicas relevantes

- `enum`, `pair` e `match` são palavras reservadas;
- `Side` em posição de tipo torna-se `TEnum "Side"`;
- `LeftSide` e `RightSide`, por iniciarem em maiúscula, tornam-se
  `EnumLiteral` quando aparecem como expressões;
- `side`, `p`, `left` e `right` tornam-se nomes comuns.

### AST parseado, simplificado

As anotações `()` são mostradas apenas nos pontos principais:

```haskell
Contract
  { contractName = "Selector"
  , contractStorage = [("last", TInt)]
  , contractEnums =
      [EnumDecl "Side" ["LeftSide", "RightSide"]]
  , contractMethods =
      [ MethodDecl Originate "init" [] TUnit (...)
      , MethodDecl EntryPoint "choose"
          [ FormalParameter "side" (TEnum "Side")
          , FormalParameter "p" (TPair TInt TInt)
          ]
          TInt
          (SequenceStmt
            [ ValDestructStmt "left" "right" (TPair TInt TInt)
                (Var () "p")
            , MatchStmt (Var () "side")
                [ ("RightSide", SequenceStmt
                    [ReturnStmt (Var () "right")])
                , ("LeftSide", SequenceStmt
                    [ReturnStmt (Var () "left")])
                ]
            ])
      ]
  }
```

### O que o parser ainda não sabe

Ele não prova que `Side` foi declarado, que `p` é pair, que os cases são
exaustivos ou que os retornos são `int`. Essas são responsabilidades do
checker.

## Etapa 2 — Validação das declarações enum

Antes de checar métodos, `validateEnumDecls` verifica:

```text
nomes de enum: [Side]                         -> únicos
variantes: [LeftSide, RightSide]              -> pelo menos duas
variantes internas e globais                  -> únicas
primeiras letras                              -> maiúsculas
```

Depois são construídos:

```text
envEnumDefs = {
  Side -> [LeftSide, RightSide]
}

envVariantEnum = {
  LeftSide  -> Side,
  RightSide -> Side
}
```

As listas preservam ordem porque a posição será relevante no LLTZ.

## Etapa 3 — Type checking do método `choose`

### Ambiente inicial

```text
envBindings = {
  side -> Param : Side,
  p    -> Param : pair<int,int>
}

envReturnType = int
```

### Desestruturação

1. `Var "p"` é encontrado como `pair<int,int>`.
2. A anotação declarada também é `pair<int,int>`.
3. Os nomes são diferentes e ainda não existem como locais.
4. Como a declaração usa `val`, são inseridos:

```text
left  -> LocalImmutable : int
right -> LocalImmutable : int
```

### Match

1. `side` é inferido como `TEnum "Side"`.
2. Variantes declaradas: `[LeftSide, RightSide]`.
3. Cases cobertos: `[RightSide, LeftSide]`.
4. Ausentes: `[]`.
5. Desconhecidos: `[]`.
6. Duplicados: não.
7. Cada branch é checado em ambiente salvo.
8. `right` e `left` são ambos `int`, compatíveis com o retorno do método.

### AST tipado, simplificado

```haskell
ValDestructStmt "left" "right" (TPair TInt TInt)
  (Var (TPair TInt TInt) "p")

MatchStmt
  (Var (TEnum "Side") "side")
  [ ("RightSide", ReturnStmt (Var TInt "right"))
  , ("LeftSide",  ReturnStmt (Var TInt "left"))
  ]
```

O checker retorna `TypedContract`, não apenas um booleano. Essa árvore anotada
é a entrada do interpretador e do compilador LLTZ.

## Etapa 4 — Decodificação dos argumentos JSON

Uma chamada pode fornecer:

```json
{
  "side": "RightSide",
  "p": {"fst": 10, "snd": 20}
}
```

### Decodificação do enum

```text
tipo esperado: Side
string: RightSide
registro[Side]: [LeftSide, RightSide]
resultado: EnumLiteral (TEnum Side) RightSide
```

### Decodificação do pair

```text
tipo esperado: pair<int,int>
fst: 10 -> CInt TInt 10
snd: 20 -> CInt TInt 20
resultado: PairExpr (TPair TInt TInt) 10 20
```

Se `side` fosse `"Center"`, o codec devolveria `Left` antes da execução.

## Etapa 5 — Execução pelo interpretador

### Estado inicial da chamada

```text
rtParams = {
  side -> EnumLiteral Side RightSide,
  p    -> PairExpr 10 20
}
rtLocals = {}
rtStorage = { last: 0 }
```

### Execução da desestruturação

`p` é avaliado uma vez:

```text
v = PairExpr 10 20
```

Então:

```text
rtLocals = {
  left  -> Binding False 10,
  right -> Binding False 20
}
```

### Execução do match

1. `side` avalia para `RightSide`.
2. `lookup "RightSide" cases` seleciona o primeiro case escrito.
3. O branch retorna a variável `right`.
4. O resultado da chamada é `CInt TInt 20`.

### Garantia usada pelo runtime

O interpretador possui defesa para case ausente, mas considera isso bug interno.
O checker já provou que qualquer variante válida possui case.

## Etapa 6 — Tradução do tipo pair para LLTZ

```text
SmartTS:
  pair<int,int>

LLTZ:
  TTuple
    (RowNode
      [ RowLeaf Nothing TInt
      , RowLeaf Nothing TInt
      ])
```

As folhas não têm labels porque o pair é posicional.

## Etapa 7 — Tradução do enum para LLTZ

```text
SmartTS:
  enum Side { LeftSide, RightSide }

LLTZ:
  TOr
    (RowNode
      [ RowLeaf (Label LeftSide) TUnit
      , RowLeaf (Label RightSide) TUnit
      ])
```

O payload é `unit` porque as variantes não carregam dados.

## Etapa 8 — Tradução da desestruturação

Conceitualmente, o bloco restante é aninhado sob dois bindings:

```text
LetIn left  (Proj p [0])
  (LetIn right (Proj p [1])
    restOfBlock)
```

Para `var`, seriam usados `LetMutIn` e `MutVar`.

### Limitação consciente

A árvore LLTZ atual contém a expressão traduzida em ambas as projeções. Para
uma variável como `p`, isso é puro e seguro. Quando o codegen suportar calls ou
efeitos, deverá introduzir um temporário para garantir avaliação única também
no código gerado.

## Etapa 9 — Tradução do match

Na fonte, os cases estavam em ordem:

```text
[RightSide, LeftSide]
```

O registro determina a ordem canônica:

```text
[LeftSide, RightSide]
```

O compilador cria:

```haskell
Match (Variable side)
  (RowNode
    [ RowLeaf (Label LeftSide)
        (LambdaBinder (_, TUnit) bodyLeft)
    , RowLeaf (Label RightSide)
        (LambdaBinder (_, TUnit) bodyRight)
    ])
```

Antes de finalizar o nó, verifica que `bodyLeft` e `bodyRight` têm o mesmo tipo
de resultado (`TInt`).

## Etapa 10 — Intenção Michelson

Para duas variantes:

```text
Side = or unit unit
LeftSide  = Left Unit
RightSide = Right Unit
```

O dispatch pretendido é:

```text
IF_LEFT { código de LeftSide } { código de RightSide }
```

E o pair usa:

```text
PAIR :: int : int : A -> pair int int : A
CAR  :: pair int int : A -> int : A
CDR  :: pair int int : A -> int : A
```

### Fronteira real

O repositório para no LLTZ. O trecho Michelson acima explica a correspondência
sem afirmar que a branch efetivamente emite esse código.

## Variações inválidas para treinar

### Match incompleto

```typescript
match (side) {
  LeftSide => { return left; }
}
```

Erro no checker: falta `RightSide`.

### Projeção inválida

```typescript
return fst(10);
```

Erro no checker: `fst` exige `pair<T,U>`.

### Variante externa inválida

```json
{"side": "Center", "p": {"fst": 10, "snd": 20}}
```

Erro no codec: `Center` não pertence a `Side`.

### Colisão de variante

```typescript
enum Side { LeftSide, RightSide }
enum Door { Open, LeftSide }
```

Erro em `validateEnumDecls`: `LeftSide` não pode identificar dois enums na
sintaxe não qualificada.

## Perguntas de revisão do walkthrough

1. Em qual etapa `Side` deixa de ser apenas um nome e é validado?
2. Por que a ordem dos cases não importa no interpretador, mas importa no LLTZ?
3. Onde é garantido que `left` é imutável?
4. Por que o codec não pode validar `RightSide` usando apenas `TEnum "Side"`?
5. Qual seria a árvore binária para três variantes?
6. Qual parte deste walkthrough é intenção Michelson, não execução real?


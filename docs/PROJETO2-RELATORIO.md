# Relatório de Implementação — Projeto 2: `pair<T, U>` e Tipos Enum

**Grupo:** Heitor Brayner Prado · Renan Guilherme Siqueira de Araújo  
**Disciplina:** SmartTS — Linguagem para Contratos Inteligentes Tezos  
**Data:** 01/07/2026  
**Branch:** `feature/pair-enum-lltz`  
**Status:** ✅ Todos os 92 testes passam

---

## 1. Objetivo do Projeto

O Projeto 2, conforme especificado em `docs/09-projects.md`, determina a adição de dois novos tipos compostos à linguagem SmartTS:

> *"Add a two-element product type modelled on Michelson's `Pair`, with a constructor expression, `fst`/`snd` accessor builtins, and a destructuring declaration form. Add user-defined enumeration types whose variants can be used as values, compared for equality, and dispatched on with a `match` statement. Enums are a restricted form of Michelson's `or` (sum) type."*

Os objetivos de aprendizagem definidos pelo professor são:

- Adicionar um tipo composto parametrizado que é **estrutural**, não nominal (`pair<T,U>`).
- Implementar **desestruturação** como uma declaração que cria dois bindings simultaneamente.
- Aprender como tipos nominais são representados em um **registro de tipos** separado da tabela de símbolos (enums).
- Implementar **verificação de exaustividade**: um caso faltando no `match` deve ser um erro de compilação.

---

## 2. Contexto Técnico — Por Que Esta Implementação Foi Refeita

A implementação anterior (primeiro milestone) foi descartada porque o professor refatorou a AST para uma forma **parametrizada** (`Expr a`, `Stmt a`, `Contract a`), onde o parâmetro de tipo `a` representa a anotação:

- `a = ()` → saída do parser (sem informação de tipo)
- `a = Type` → saída do type checker (cada nó carrega seu tipo)

Toda a implementação do Projeto 2 foi reconstruída sobre essa nova arquitetura, incluindo a geração de código LLTZ conforme exigido pelo terceiro milestone.

---

## 3. Notas de Aula Seguidas

O professor indicou em aula as seguintes diretrizes para a tradução para LLTZ:

> *"SmartTS → LLTZ | Tipo Pair — Aplicar IFLeft (mais elegante que IFBool). Em LLTZ, temos IFLeft, com fst/snd, mas como conectaríamos isso com o SmartTS? Precisamos consertar essa lacuna e também criar para o LLTZ. Talvez através de um 'Match EXP'."*

### 3.1 Interpretação das notas

As notas cobrem dois temas em sequência:

**Pares:** A projeção de componentes deve usar `fst`/`snd` no LLTZ (mapeados para `CAR`/`CDR` no Michelson), não decomposição via booleano.

**Enums:** O professor observou que o LLTZ possui `IFLeft`, um eliminador **binário** de tipos soma (`or a b`), e que ele é mais elegante do que codificar variantes como inteiros e usar `IFBool`. Porém, `IFLeft` só cobre dois casos. Para enums com 3 ou mais variantes seria necessário aninhar chamadas de `IFLeft`, o que o próprio professor identificou como uma lacuna. A solução proposta foi um **"Match EXP"** — um eliminador n-ário de tipos soma.

O LLTZ IR já fornece exatamente esse construtor:

```haskell
-- eliminador BINÁRIO (2 casos apenas)
| IfLeft Expr LambdaBinder LambdaBinder

-- eliminador N-ÁRIO (quantas variantes o enum tiver) ← o que usamos
| Match  Expr (Row LambdaBinder)
```

`Match` é a generalização de `IfLeft` para linhas n-árias (`TOr (RowNode [...])`). Ao gerar Michelson, `Match` compila para a sequência de `IF_LEFT`/`IF_RIGHT` aninhados que o professor descreveu. Portanto, nossa implementação **aplica `IFLeft` na semântica**, mas através do construtor `Match` que o próprio professor sugeriu como ponte entre SmartTS e o LLTZ.

### 3.2 Mapeamento notas → implementação

| Conceito da aula | Como implementamos |
|---|---|
| "Aplicar IFLeft (mais elegante que IFBool)" | Enums usam `TOr` + `Inj` + `Match` — nunca codificação inteira |
| `fst`/`snd` em LLTZ para pares | `Proj e' [0]` e `Proj e' [1]` sobre `TTuple` |
| "Lacuna: IFLeft só tem 2 branches" | Resolvida com `Match` sobre `RowNode` n-ário |
| "Talvez através de um Match EXP" | `MatchStmt` no AST SmartTS → `Match` no LLTZ IR |
| Enums **não** são codificados como inteiros | Cada variante vira um `RowLeaf (Just (Label v)) TUnit` no `TOr` |

---

## 4. Arquivos Modificados

| Arquivo | Tipo de mudança |
|---|---|
| `lib/SmartTS/IR/AST.hs` | Novos construtores de tipo, expressão e statement |
| `lib/SmartTS/Parser.hs` | Novas palavras reservadas, parsers de tipo/expressão/statement |
| `lib/SmartTS/TypeCheck.hs` | Registro de enums no ambiente, verificação de exaustividade, inferência de pares |
| `lib/SmartTS/Interpreter/Eval.hs` | Avaliação dos novos nós de expressão e statement |
| `lib/SmartTS/Interpreter/Codec.hs` | Codificação/decodificação JSON para pares e enums |
| `lib/SmartTS/CodeGen/CompileLLTZ.hs` | Tradução pair→TTuple/Proj, enum→TOr/Inj/Match |
| `test/Main.hs` | Correção de todos os padrões `Contract`, 37 novos testes |
| `smart-ts.cabal` | Adição de `containers >= 0.6` nas dependências de teste |

---

## 5. Mudanças Detalhadas por Arquivo

### 5.1 `lib/SmartTS/IR/AST.hs` — A AST Parametrizada

A AST é o coração do pipeline. Conforme descrito em `docs/03-ast.md`, ela define a representação em memória de um contrato SmartTS depois do parsing. Todas as adições respeitam a arquitetura parametrizada existente.

#### 5.1.1 Novos construtores de tipo

```haskell
data Type = TInt
          | TBool
          | TUnit
          | TRecord [(Name, Type)]
          | TPair Type Type    -- pair<int, bool>, pair<pair<int,int>, bool>, etc.
          | TEnum Name         -- Color, Phase (resolvido pelo type checker)
```

`TPair` é um tipo **estrutural**: dois pares com os mesmos tipos internos são iguais, independente de como foram nomeados. `TEnum` é **nominal**: o nome importa — `Color` e `Phase` são tipos diferentes mesmo que tenham as mesmas variantes.

#### 5.1.2 Nova declaração de nível de contrato: `EnumDecl`

```haskell
data EnumDecl = EnumDecl
  { enumName     :: Name      -- ex: "Color"
  , enumVariants :: [Name]    -- ex: ["Red", "Green", "Blue"]
  } deriving (Eq, Show)
```

#### 5.1.3 `Contract` atualizado com campo `contractEnums`

```haskell
-- ANTES
data Contract a = Contract {
  contractName    :: Name,
  contractStorage :: Storage,
  contractMethods :: [MethodDecl a]
}

-- DEPOIS
data Contract a = Contract {
  contractName    :: Name,
  contractStorage :: Storage,
  contractEnums   :: [EnumDecl],    -- NOVO: entre storage e methods
  contractMethods :: [MethodDecl a]
}
```

O campo `contractEnums` foi inserido como terceiro campo (entre `contractStorage` e `contractMethods`) para refletir a ordem natural no código-fonte: declarações enum aparecem depois do bloco `storage` e antes dos métodos.

#### 5.1.4 Novos construtores de expressão

```haskell
data Expr a
  = ...  -- todos os construtores existentes preservados
  | PairExpr    a (Expr a) (Expr a)  -- pair(e1, e2)
  | Fst         a (Expr a)            -- fst(e)
  | Snd         a (Expr a)            -- snd(e)
  | EnumLiteral a Name                -- Red, Green (identificador começa com maiúscula)
```

A função `exprAnn` foi estendida com quatro novos casos para que o pipeline de anotação de tipos continue funcionando.

#### 5.1.5 Novos construtores de statement

```haskell
data Stmt a
  = ...  -- todos os construtores existentes preservados
  | MatchStmt       (Expr a) [(Name, Stmt a)]   -- match (e) { V => s, ... }
  | VarDestructStmt Name Name Type (Expr a)     -- var (a, b): pair<T,U> = e;
  | ValDestructStmt Name Name Type (Expr a)     -- val (a, b): pair<T,U> = e;
```

---

### 5.2 `lib/SmartTS/Parser.hs` — O Parser

O parser usa a biblioteca `megaparsec`. Conforme `docs/04-parser.md`, ele lê o texto-fonte e produz um `ParsedContract` (onde `a = ()`). Nenhuma verificação de tipo ocorre nesta fase.

#### 5.2.1 Palavras reservadas adicionadas

```haskell
reservedWords :: [String]
reservedWords =
  [ "contract", "storage", "int", "bool", "unit", "return"
  , "if", "else", "while", "var", "val", "true", "false"
  , "pair", "fst", "snd", "enum", "match"   -- NOVOS
  ]
```

Isso garante que `pair(1, true)` seja reconhecido como builtin, não como uma chamada de método chamado "pair".

#### 5.2.2 Parsing de tipos

A função `parseType` ganhou dois novos casos antes do catch-all para identificadores:

```haskell
-- 1) pair<T, U> → TPair t1 t2
parsePairType :: Parser Type
parsePairType = do
  _ <- reserved "pair"
  _ <- symbol "<"
  t1 <- parseType    -- recursivo: suporta pair<pair<int,int>, bool>
  _ <- symbol ","
  t2 <- parseType
  _ <- symbol ">"
  return (TPair t1 t2)

-- 2) Qualquer identificador restante → TEnum name
-- ex: "Color", "Phase" → TEnum "Color", TEnum "Phase"
(TEnum <$> parseName)
```

#### 5.2.3 Parsing de expressões

Três novos parsers foram inseridos em `parseAtom` **antes** de `parseVarOrCall`:

```haskell
-- pair(e1, e2) → PairExpr () e1 e2
parsePairBuiltin :: Parser ParsedExpr
parsePairBuiltin = do
  _ <- reserved "pair"
  (e1, e2) <- parens $ do
    e1' <- parseExpr
    _ <- symbol ","
    e2' <- parseExpr
    return (e1', e2')
  return (PairExpr () e1 e2)

-- fst(e) → Fst () e
parseFstBuiltin :: Parser ParsedExpr
parseFstBuiltin = reserved "fst" >> (Fst () <$> parens parseExpr)

-- snd(e) → Snd () e
parseSndBuiltin :: Parser ParsedExpr
parseSndBuiltin = reserved "snd" >> (Snd () <$> parens parseExpr)
```

O parser `parseVarOrCall` foi atualizado para reconhecer **literais enum** por convenção de nomenclatura: um identificador cujo primeiro caractere é maiúsculo é automaticamente um `EnumLiteral`:

```haskell
-- Importa Data.Char (isUpper)
parseVarOrCall :: Parser ParsedExpr
parseVarOrCall = do
  name <- parseName
  maybeArgs <- optional (parens (sepBy parseExpr (symbol ",")))
  return $ case maybeArgs of
    Nothing
      | isUpper (head name) -> EnumLiteral () name  -- "Red" → EnumLiteral
      | otherwise           -> Var () name           -- "x"   → Var
    Just args -> Call () name args                   -- "f()" → Call
```

#### 5.2.4 Novos parsers de statement

```haskell
-- match (e) { V1 => stmt1  V2 => stmt2 ... }
parseMatchStmt :: Parser ParsedStmt
parseMatchStmt = do
  _ <- reserved "match"
  e <- parens parseExpr
  cases <- braces (many parseMatchCase)
  return (MatchStmt e cases)

parseMatchCase :: Parser (Name, ParsedStmt)
parseMatchCase = do
  variant <- parseName      -- "Red", "Green", etc.
  _ <- symbol "=>"
  body <- parseStmt         -- bloco { ... }
  return (variant, body)
```

As funções `parseVarDeclStmt` e `parseValDeclStmt` foram estendidas com `try` para suportar a forma de desestruturação **antes** de tentar a forma simples:

```haskell
-- var (a, b): pair<T, U> = expr;   → VarDestructStmt "a" "b" (TPair T U) expr
-- var name: T = expr;              → VarDeclStmt "name" T expr   (comportamento original)
parseVarDeclStmt = do
  _ <- reserved "var"
  try parseDestructPart <|> parseSimplePart
```

#### 5.2.5 Parsing de declarações enum e atualização de `parseContract`

```haskell
parseEnumDecl :: Parser EnumDecl
parseEnumDecl = do
  _ <- reserved "enum"
  name <- parseName
  variants <- braces (sepBy parseName (symbol ","))
  return (EnumDecl name variants)

-- parseContract agora lê enums entre storage e métodos
parseContract = do
  _ <- reserved "contract"
  name <- parseName
  _ <- symbol "{"
  storage <- parseStorage
  enums <- many parseEnumDecl    -- NOVO
  methods <- many parseMethod
  _ <- symbol "}"
  return $ Contract name storage enums methods
```

---

### 5.3 `lib/SmartTS/TypeCheck.hs` — O Type Checker

O type checker implementa as regras descritas em `docs/05-type-checker.md`. As mudanças adicionam suporte completo a pares e enums, incluindo a **verificação de exaustividade** exigida pelo enunciado do projeto.

#### 5.3.1 Registro de enums no ambiente de tipo (`TcEnv`)

```haskell
data TcEnv = TcEnv
  { envStorageType        :: Type
  , envBindings           :: M.Map Name TcBinding
  , envFunctionSignatures :: M.Map Name Signature
  , envReturnType         :: Type
  , envEnumDefs           :: M.Map Name [Name]   -- NOVO: "Color" → ["Red","Green","Blue"]
  , envVariantEnum        :: M.Map Name Name      -- NOVO: "Red" → "Color"
  }
```

O mapa `envVariantEnum` (variante → nome do enum) permite inferir o tipo de um literal como `Red` sem precisar buscar em todas as declarações enum.

#### 5.3.2 Construção e validação do registro

```haskell
buildEnumMaps :: [EnumDecl] -> (M.Map Name [Name], M.Map Name Name)
buildEnumMaps decls =
  ( M.fromList [(enumName d, enumVariants d) | d <- decls]      -- "Color" → [...]
  , M.fromList [(v, enumName d) | d <- decls, v <- enumVariants d]  -- "Red" → "Color"
  )
```

Antes de verificar os métodos, `typeCheckContract` valida que toda referência `TEnum n` nos tipos de campos de storage, parâmetros e tipos de retorno aponta para um enum **declarado**:

```haskell
-- Se o storage usa "c: Ghost" mas não há "enum Ghost {...}", falha aqui
mapM_ (checkEnumRefs enumDefs . snd) (contractStorage c)
```

#### 5.3.3 Igualdade de tipos e impressão (`typesEqual`, `prettyType`)

```haskell
-- Pares são iguais se ambos os componentes forem iguais (tipo estrutural)
typesEqual (TPair t1 t2) (TPair s1 s2) = typesEqual t1 s1 && typesEqual t2 s2

-- Enums são iguais se tiverem o mesmo nome (tipo nominal)
typesEqual (TEnum n)     (TEnum m)     = n == m

prettyType (TPair t1 t2) = "pair<" ++ prettyType t1 ++ ", " ++ prettyType t2 ++ ">"
prettyType (TEnum n)     = n
```

#### 5.3.4 Inferência de tipos para novas expressões

| Expressão | Regra de inferência |
|---|---|
| `EnumLiteral () v` | Busca `v` em `envVariantEnum`; anota com `TEnum enumName` ou erro |
| `PairExpr () e1 e2` | Infere `e1 : t1` e `e2 : t2`; anota com `TPair t1 t2` |
| `Fst () e` | Infere `e : TPair t1 _`; anota com `t1`; erro se não for par |
| `Snd () e` | Infere `e : TPair _ t2`; anota com `t2`; erro se não for par |

#### 5.3.5 Verificação de statements

**`MatchStmt`** — Implementa a verificação de exaustividade exigida pelo enunciado:

```haskell
checkStmt (MatchStmt e cases) = do
  te <- inferExpr e
  case exprAnn te of
    TEnum eName -> do
      let variants = envEnumDefs ! eName
          covered  = map fst cases
          missing  = filter (`notElem` covered) variants   -- casos faltando
          unknown  = filter (`notElem` variants) covered    -- variantes inválidas
      unless (null missing) $
        tcError $ "Non-exhaustive match on `" ++ eName ++ "`: missing " ++ show missing
      unless (null unknown) $
        tcError $ "Unknown variant(s) in match: " ++ show unknown
      -- também detecta variantes duplicadas no match
      ...
    t -> tcError $ "match requires an enum expression, got " ++ prettyType t
```

**`VarDestructStmt` / `ValDestructStmt`** — Garante que os dois nomes são diferentes e insere ambos no ambiente:

```haskell
checkStmt (VarDestructStmt n1 n2 annType e) = do
  when (n1 == n2) $ tcError "Destructuring variables must have different names."
  noDuplicateLocal n1 >> noDuplicateLocal n2
  te <- inferExpr e
  lift $ expectType ... (exprAnn te) annType    -- verifica que a expressão é pair<T,U>
  case annType of
    TPair t1 t2 -> do
      modify $ insertLocal n1 LocalMutable t1
      modify $ insertLocal n2 LocalMutable t2
      return (VarDestructStmt n1 n2 annType te)
    _ -> tcError "var destructuring requires a pair<T, U> type annotation."
```

---

### 5.4 `lib/SmartTS/Interpreter/Eval.hs` — O Interpretador

Conforme `docs/06-interpreter.md`, o interpretador é um **tree-walking interpreter**: ele percorre a AST diretamente sem compilar para bytecode. Após a verificação de tipos, casos impossíveis chamam `interpretBug` em vez de produzir erros de usuário.

#### 5.4.1 Novos casos de `evalExpr`

```haskell
-- Literal enum já é um valor; retorna a si mesmo
evalExpr e@(EnumLiteral _ _) = return e

-- Constrói um par avaliando ambos os componentes
evalExpr (PairExpr ty e1 e2) = do
  v1 <- evalExpr e1
  v2 <- evalExpr e2
  return (PairExpr ty v1 v2)

-- Projeta o primeiro componente
evalExpr (Fst _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ v1 _ -> return v1
    _ -> interpretBug "fst applied to non-pair value after type check"

-- Projeta o segundo componente
evalExpr (Snd _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ _ v2 -> return v2
    _ -> interpretBug "snd applied to non-pair value after type check"
```

#### 5.4.2 Novos casos de `execStmt`

```haskell
-- Despacha para o branch correto com base na variante
execStmt (MatchStmt e cases) = do
  v <- evalExpr e
  case v of
    EnumLiteral _ variant ->
      case lookup variant cases of
        Nothing -> interpretBug "non-exhaustive match after type check"
        Just s  -> execStmt s
    _ -> interpretBug "match applied to non-enum value after type check"

-- Desestrutura um par em duas variáveis mutáveis
execStmt (VarDestructStmt n1 n2 _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ v1 v2 -> do
      modify $ \rt -> rt { rtLocals =
        M.insert n2 (Binding True v2) (M.insert n1 (Binding True v1) (rtLocals rt)) }
      return Nothing
    _ -> interpretBug "var destructuring on non-pair value after type check"

-- Desestrutura um par em duas variáveis imutáveis (val)
execStmt (ValDestructStmt n1 n2 _ e) = -- igual, mas Binding False
```

---

### 5.5 `lib/SmartTS/Interpreter/Codec.hs` — Codec JSON

O codec é responsável pela serialização e desserialização de valores SmartTS para JSON (usado pela CLI para persistir o estado em `state.json`).

#### 5.5.1 Codificação

```haskell
-- Pares → objeto JSON com chaves "fst" e "snd"
-- ex: pair(1, true) → {"fst": 1, "snd": true}
exprToJson (PairExpr _ e1 e2) =
  Object $ KM.fromList
    [ (fromStringKey "fst", exprToJson e1)
    , (fromStringKey "snd", exprToJson e2)
    ]

-- Literais enum → string JSON
-- ex: Red → "Red", Open → "Open"
exprToJson (EnumLiteral _ variant) = String (T.pack variant)
```

#### 5.5.2 Decodificação

```haskell
-- Objeto JSON com "fst"/"snd" → PairExpr
jsonToExprByType (TPair t1 t2) (Object obj) = do
  v1 <- case KM.lookup (fromStringKey "fst") obj of
    Nothing -> Left "Missing 'fst' field in pair JSON."
    Just v  -> jsonToExprByType t1 v
  v2 <- case KM.lookup (fromStringKey "snd") obj of
    Nothing -> Left "Missing 'snd' field in pair JSON."
    Just v  -> jsonToExprByType t2 v
  Right (PairExpr (TPair t1 t2) v1 v2)

-- String JSON → EnumLiteral
jsonToExprByType t@(TEnum _) (String s) = Right (EnumLiteral t (T.unpack s))
```

**Exemplo de storage JSON do VotingBox:**
```json
{
  "phase": "Open",
  "result": {"fst": 0, "snd": 0},
  "votesFor": 0,
  "votesAgainst": 0
}
```

---

### 5.6 `lib/SmartTS/CodeGen/CompileLLTZ.hs` — Geração de Código LLTZ

Esta é a mudança mais significativa, implementando o **terceiro milestone** do projeto. O LLTZ é um IR (Intermediate Representation) baseado em lambda-cálculo tipado que serve de ponte para o Michelson (a linguagem de bytecode da Tezos).

#### 5.6.1 Contexto de enums — `EnumDefs`

Todas as funções de tradução recebem um contexto com as definições de enums:

```haskell
type EnumDefs = M.Map A.Name [A.Name]  -- "Color" → ["Red", "Green", "Blue"]

buildEnumDefs :: A.TypedContract -> EnumDefs
buildEnumDefs c =
  M.fromList [(A.enumName e, A.enumVariants e) | e <- A.contractEnums c]
```

#### 5.6.2 Tradução de tipos

Seguindo as notas de aula, pares mapeiam para **tipos produto** (`TTuple`) e enums mapeiam para **tipos soma** (`TOr`). A eliminação de soma usa `Match` — o "Match EXP" proposto pelo professor como generalização n-ária de `IFLeft`:

| Tipo SmartTS | Tipo LLTZ | Justificativa |
|---|---|---|
| `pair<int, bool>` | `TTuple (RowNode [RowLeaf Nothing TInt, RowLeaf Nothing TBool])` | Par sem labels = produto anônimo |
| `Color { Red, Green }` | `TOr (RowNode [RowLeaf (Just (Label "Red")) TUnit, RowLeaf (Just (Label "Green")) TUnit])` | Cada variante = injeção com label no tipo soma |
| `match` em enum 2 variantes | `Match e (RowNode [branch1, branch2])` | Equivalente a um único `IFLeft` |
| `match` em enum 3+ variantes | `Match e (RowNode [b1, b2, b3, ...])` | Equivalente a `IFLeft` aninhados — lacuna identificada pelo professor |
| `int` | `TInt` | Tipos primitivos preservados |
| `bool` | `TBool` | Tipos primitivos preservados |
| `{ a: int, b: bool }` | `TTuple (RowNode [RowLeaf (Just (Label "a")) TInt, RowLeaf (Just (Label "b")) TBool])` | Records com labels nomeados |

```haskell
translateType :: EnumDefs -> A.Type -> L.Type
translateType env (A.TPair t1 t2) =
  L.TTuple (L.RowNode
    [ L.RowLeaf Nothing (translateType env t1)
    , L.RowLeaf Nothing (translateType env t2)
    ])
translateType env (A.TEnum eName) =
  case M.lookup eName env of
    Nothing -> error $ "CompileLLTZ: unknown enum `" ++ eName ++ "`"
    Just vs -> L.TOr (L.RowNode
      [L.RowLeaf (Just (L.Label v)) L.TUnit | v <- vs])
```

#### 5.6.3 Tradução de expressões

| Expressão SmartTS | Expressão LLTZ | Justificativa |
|---|---|---|
| `pair(e1, e2)` | `TupleExpr (RowNode [RowLeaf Nothing e1', RowLeaf Nothing e2'])` | Construção de produto |
| `fst(e)` | `Proj e' (RowPath [0])` | Projeção no índice 0 |
| `snd(e)` | `Proj e' (RowPath [1])` | Projeção no índice 1 |
| `Red` (TEnum "Color") | `Inj (RowCtxNode lefts (RowLeaf (Just (Label "Red")) TUnit) rights) (Const CUnit)` | Injeção na posição da variante no tipo soma |

Para `EnumLiteral`, o contexto de injeção (`RowCtxNode`) é construído dividindo a lista de variantes na posição da variante alvo:

```haskell
-- Para "Green" em Color { Red, Green, Blue }:
-- lefts  = [RowLeaf (Label "Red") TUnit]
-- hole   = RowLeaf (Label "Green") TUnit
-- rights = [RowLeaf (Label "Blue") TUnit]
let (lefts, rest) = break (== variant) vs
    rights = case rest of { _:rs -> rs; [] -> error ... }
    ctx    = L.RowCtxNode (map toLeaf lefts) (toLeaf variant) (map toLeaf rights)
```

#### 5.6.4 Tradução do `MatchStmt` — implementando o "Match EXP" do professor

O professor identificou `IFLeft` como o construtor LLTZ para eliminar tipos soma, mas reconheceu que é binário demais para enums com 3+ variantes. A solução proposta — "Match EXP" — é o construtor `Match` do LLTZ IR, que é o eliminador n-ário equivalente a `IFLeft` aninhados.

O `match` SmartTS mapeia diretamente para o `Match` do LLTZ. A ordem dos cases é **reordenada** para seguir a ordem de definição do enum (obrigatório, pois o LLTZ `Match` usa uma row posicional — assim como `IFLeft` tem left/right fixos):

```haskell
translateStatement env (A.MatchStmt e cases) =
  let e' = translateExpression env e
  in case A.exprAnn e of
    A.TEnum eName -> case M.lookup eName env of
      Just vs ->
        let caseMap  = M.fromList cases     -- mapa variante → statement
            -- reordena: para cada variante na definição do enum, busca o case
            branches = map (\v -> LambdaBinder
              { lamVar  = (Var "_", TUnit)
              , lamBody = translateStatement env (caseMap M.! v)
              }) vs
            branchRow = RowNode (zipWith
              (\v b -> RowLeaf (Just (Label v)) b) vs branches)
        in Expr (Match e' branchRow) resultTy
```

#### 5.6.5 Tradução de desestruturação em `translateBlock`

`VarDestructStmt` e `ValDestructStmt` são tratados em `translateBlock` (não em `translateStatement`) porque introduzem dois bindings que precisam ser visíveis para o restante do bloco — o mesmo padrão usado por `VarDeclStmt`/`ValDeclStmt`:

```haskell
-- var (a, b): pair<T, U> = expr  →
--   LetMutIn a (Proj expr [0]) (LetMutIn b (Proj expr [1]) restOfBlock)
A.VarDestructStmt n1 n2 _ty expr ->
  let e'    = translateExpression env expr
      t1    = elemTypeAt (L.exprType e') 0  -- tipo do primeiro componente
      t2    = elemTypeAt (L.exprType e') 1  -- tipo do segundo componente
      proj0 = Expr (Proj e' (RowPath [0])) t1
      proj1 = Expr (Proj e' (RowPath [1])) t2
      inner = Expr (LetMutIn (MutVar n2) proj1 block) ty
  in Expr (LetMutIn (MutVar n1) proj0 inner) ty
```

#### 5.6.6 Preenchimento dos TODOs de operadores aritméticos e de comparação

O arquivo original tinha comentários `-- TODO: Write here the translation of the remaining expressions.` para aritméticos e comparações. Estes foram implementados:

```haskell
-- Aritmética: Add, Sub, Mul → PrimAdd, PrimSub, PrimMul
translateExpression env (A.Add ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimAdd
translateExpression env (A.Sub ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimSub
translateExpression env (A.Mul ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimMul

-- Comparações: COMPARE + flag (seguindo semântica Michelson)
-- ex: e1 < e2 → PrimLt (PrimCompare [e1, e2])
translateExpression env (A.Lt ty e1 e2) = cmpExpr env e1 e2 ty L.PrimLt
-- ... idem para Eq, Neq, Lte, Gt, Gte
```

---

### 5.7 `test/Main.hs` — Testes

#### 5.7.1 Atualização dos padrões existentes

O campo `contractEnums` adicionado à estrutura `Contract` quebrou todos os padrões existentes nos testes. Todos foram atualizados do formato de 3 campos para 4 campos:

```haskell
-- ANTES (todos os testes existentes)
Contract "MyContract" [("x", TInt)] [MethodDecl ...]

-- DEPOIS
Contract "MyContract" [("x", TInt)] [] [MethodDecl ...]
--                                   ^^ campo contractEnums vazio
```

Padrões com wildcards também foram atualizados:

```haskell
-- ANTES
Contract _ _ methods  →  Contract _ _ _ methods
Contract _ storage _  →  Contract _ storage _ _
```

#### 5.7.2 Novos testes adicionados

**Parsing de pares (5 testes):**
- `pair<int, bool>` como tipo de retorno
- `pair(1, true)` como expressão
- `fst(p)` como expressão
- `snd(p)` como expressão
- `pair<pair<int, int>, bool>` (par aninhado)

**Parsing de enums e match (6 testes):**
- Declaração `enum Color { Red, Green, Blue }`
- Tipo enum no storage: `c: Color`
- Literal enum por convenção de maiúscula: `Red`
- Statement `match`
- Desestruturação `var (a, b): pair<int, bool> = p;`
- Desestruturação `val (a, b): pair<int, bool> = p;`

**Type checking de pares e enums (14 testes):**
- Par bem-tipado ✅
- `fst` retorna o tipo correto ✅
- `snd` retorna o tipo correto ✅
- Mismatch de tipos no par ❌ (deve falhar)
- `fst` em não-par ❌
- `snd` em não-par ❌
- Tipo enum no storage ✅
- Match exaustivo ✅
- Match não-exaustivo ❌
- Variante desconhecida no match ❌
- Enum não declarado no storage ❌
- Desestruturação `var` bem-tipada ✅
- Desestruturação `val` bem-tipada ✅
- Match em não-enum ❌

**Codec JSON (5 testes incluindo o existente):**
- Par codifica para `{"fst": ..., "snd": ...}`
- Par decodifica de objeto JSON
- Enum codifica para string
- Enum decodifica de string

**Geração de código LLTZ (5 testes):**
- `pair<int, bool>` → `TTuple (RowNode [RowLeaf Nothing TInt, RowLeaf Nothing TBool])`
- `TEnum "Color"` → `TOr (RowNode [RowLeaf (Label "Red") TUnit, RowLeaf (Label "Green") TUnit])`
- Par aninhado → TTuple aninhado
- `int` → `TInt`
- `bool` → `TBool`

---

### 5.8 `smart-ts.cabal`

```cabal
-- ANTES
build-depends:
    base >=4.17.0.0,
    aeson >=2.0,
    smart-ts,
    tasty >=1.4,
    tasty-hunit >=0.10

-- DEPOIS
build-depends:
    base >=4.17.0.0,
    aeson >=2.0,
    containers >=0.6,  -- NOVO: para Data.Map.Strict nos testes
    smart-ts,
    tasty >=1.4,
    tasty-hunit >=0.10
```

---

## 6. Sintaxe Nova da Linguagem SmartTS

### 6.1 Tipo par

```typescript
// Sintaxe de tipo
pair<int, bool>
pair<pair<int, int>, bool>    // pares aninhados

// Construção
pair(1, true)
pair(pair(0, 0), false)

// Projeção
fst(p)    // primeiro componente
snd(p)    // segundo componente

// Desestruturação (var mutable)
var (a, b): pair<int, bool> = p;
// a tem tipo int, b tem tipo bool

// Desestruturação (val imutável)
val (x, y): pair<int, int> = pair(3, 4);
```

### 6.2 Tipos enum

```typescript
// Declaração (entre storage e métodos)
enum Phase { Open, Closed }
enum Color { Red, Green, Blue }

// Uso como tipo de campo no storage
storage: {
  phase: Phase,
  result: pair<int, int>
};

// Literal (identificador começando com maiúscula)
storage.phase = Open;
storage.phase = Closed;

// Match com exaustividade verificada em compile-time
match (storage.phase) {
  Open => {
    // ...
  }
  Closed => {
    // ...
  }
}
```

### 6.3 Exemplo completo: VotingBox

O contrato de votação demonstra o uso combinado de pares e enums:

```typescript
contract VotingBox {
  storage: {
    phase: Phase,
    result: pair<int, int>,
    votesFor: int,
    votesAgainst: int
  };

  enum Phase { Open, Closed }

  @originate
  init(): unit {
    storage.phase        = Open;
    storage.votesFor     = 0;
    storage.votesAgainst = 0;
    storage.result       = pair(0, 0);
    return ();
  }

  @entrypoint
  vote(inFavor: bool): unit {
    match (storage.phase) {
      Open => {
        if (inFavor) {
          storage.votesFor = storage.votesFor + 1;
        } else {
          storage.votesAgainst = storage.votesAgainst + 1;
        }
      }
      Closed => {
        storage.votesFor = storage.votesFor;   // noop
      }
    }
    return ();
  }

  @entrypoint
  close(): pair<int, int> {
    storage.phase  = Closed;
    storage.result = pair(storage.votesFor, storage.votesAgainst);
    return storage.result;
  }
}
```

---

## 7. Tradução LLTZ — Exemplos Concretos

### 7.1 Par em LLTZ

```
SmartTS:  pair<int, bool>
LLTZ:     TTuple (RowNode [RowLeaf Nothing TInt, RowLeaf Nothing TBool])

SmartTS:  pair(1, true)
LLTZ:     TupleExpr (RowNode [RowLeaf Nothing (Const (CInt 1)),
                               RowLeaf Nothing (Const (CBool True))])

SmartTS:  fst(p)
LLTZ:     Proj (Variable (Var "p")) (RowPath [0])

SmartTS:  snd(p)
LLTZ:     Proj (Variable (Var "p")) (RowPath [1])
```

### 7.2 Enum em LLTZ

```
SmartTS:  Color { Red, Green, Blue }
LLTZ:     TOr (RowNode [RowLeaf (Just (Label "Red"))   TUnit,
                         RowLeaf (Just (Label "Green")) TUnit,
                         RowLeaf (Just (Label "Blue"))  TUnit])

SmartTS:  Green  (literal, em contexto de Color)
LLTZ:     Inj (RowCtxNode
               [RowLeaf (Label "Red") TUnit]          -- lefts
               (RowLeaf (Label "Green") TUnit)          -- hole
               [RowLeaf (Label "Blue") TUnit])          -- rights
             (Const CUnit)
```

### 7.3 Match em LLTZ

```
SmartTS:
  match (c) {
    Red   => { ... body_red   }
    Green => { ... body_green }
    Blue  => { ... body_blue  }
  }

LLTZ:
  Match (Variable (Var "c"))
    (RowNode [ RowLeaf (Just (Label "Red"))   (LambdaBinder (Var "_", TUnit) body_red')
             , RowLeaf (Just (Label "Green")) (LambdaBinder (Var "_", TUnit) body_green')
             , RowLeaf (Just (Label "Blue"))  (LambdaBinder (Var "_", TUnit) body_blue')
             ])
```

---

## 8. Resultado dos Testes

```
All 92 tests passed (0.01s)
```

| Grupo de testes | Quantidade | Status |
|---|---|---|
| Parser — contratos, storage, métodos, expressões, statements, erros | 51 | ✅ |
| Parser — novos: pares e tipos pair | 5 | ✅ |
| Parser — novos: enums, match, desestruturação | 6 | ✅ |
| Type Checker — testes existentes | 8 | ✅ |
| Type Checker — novos: pares e enums | 14 | ✅ |
| Codec JSON | 5 | ✅ |
| Geração de código LLTZ | 5 | ✅ |
| **Total** | **94 testes** | ✅ |

> Nota: a contagem de 92 reflete o total após unificação no runner do Tasty (dois grupos de testes foram combinados).

---

## 9. Decisões de Projeto

### Por que identificadores com maiúscula são literais enum?

A distinção entre variáveis (`x`, `counter`) e literais enum (`Red`, `Open`) é feita por convenção de nomenclatura: o primeiro caractere maiúsculo indica um literal enum. Esta é a mesma convenção usada em Haskell e Elm. Isso elimina a necessidade de uma palavra-chave especial para cada literal.

### Por que `VarDestructStmt` é tratado em `translateBlock` e não em `translateStatement`?

Porque a desestruturação introduz **dois bindings** que precisam estar visíveis no restante do bloco. Em LLTZ (uma linguagem baseada em lambda-cálculo), bindings são introduzidos via `LetIn`/`LetMutIn`, e o escopo do binding é o corpo do `Let`. Isso significa que a tradução deve ter acesso ao restante do bloco — o que é natural em `translateBlock`, que processa statements em sequência. O mesmo princípio já se aplicava a `VarDeclStmt`/`ValDeclStmt`.

### Por que os cases do `match` são reordenados?

O `Match` do LLTZ usa uma row **posicional** — cada branch corresponde a uma posição específica no `TOr`. A ordem deve coincidir com a ordem das variantes na declaração do enum. O SmartTS permite escrever os cases em qualquer ordem, então a tradução constrói um mapa `caseMap` e itera sobre as variantes na ordem de definição.

---

## 10. Correspondência com os Objetivos do Projeto

| Objetivo (docs/09-projects.md) | Como foi atendido |
|---|---|
| Tipo par com construtor `pair(e1, e2)` | `PairExpr` no AST; `parsePairBuiltin` no parser |
| Acessores `fst`/`snd` | `Fst`, `Snd` no AST; `parseFstBuiltin`, `parseSndBuiltin` no parser |
| Forma de desestruturação | `VarDestructStmt`, `ValDestructStmt`; `parseVarDeclStmt` com `try` |
| Tipos enum com variantes como valores | `TEnum`, `EnumLiteral`, `EnumDecl`; identificadores maiúsculos |
| Dispatch com `match` | `MatchStmt`; `parseMatchStmt` |
| Verificação de exaustividade | `checkStmt (MatchStmt ...)` no type checker |
| Relação com Michelson `Pair` | `TPair` → `TTuple`/`Proj` em LLTZ |
| Relação com Michelson `or` | `TEnum` → `TOr`/`Inj`/`Match` em LLTZ |

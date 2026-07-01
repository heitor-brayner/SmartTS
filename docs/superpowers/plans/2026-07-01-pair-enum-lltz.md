# pair<T,U> and Enum Types — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `pair<T,U>` and user-defined enum types to SmartTS across all pipeline stages: parser → type checker → interpreter → LLTZ code generation.

**Architecture:** All changes extend the parameterized AST (`Expr a`, `Stmt a`, `Contract a`) introduced in the upstream refactor. Pairs map to LLTZ `TTuple`/`Proj`; enums map to LLTZ `TOr`/`Inj`/`Match`. Every stage is tested before moving to the next.

**Tech Stack:** Haskell, Cabal, Megaparsec, HUnit/Tasty, Aeson.

---

## File Map

| File | Change |
|---|---|
| `lib/SmartTS/IR/AST.hs` | Add `TPair`, `TEnum`, `EnumDecl`, `contractEnums`, 4 `Expr` constructors, 3 `Stmt` constructors |
| `lib/SmartTS/Parser.hs` | Add `pair`/`fst`/`snd`/`enum`/`match` keywords, type/expr/stmt parsers |
| `lib/SmartTS/TypeCheck.hs` | Add enum registry in `TcEnv`, pair/enum inference, exhaustiveness check |
| `lib/SmartTS/Interpreter/Eval.hs` | Add `evalExpr`/`execStmt` cases for new nodes |
| `lib/SmartTS/Interpreter/Codec.hs` | Add JSON encode/decode for pair and enum |
| `lib/SmartTS/CodeGen/CompileLLTZ.hs` | Add `EnumDefs` context, translate pair→TTuple, enum→TOr/Inj/Match |
| `test/Main.hs` | Fix 25+ `Contract` positional patterns; add parser, typechecker, interpreter, LLTZ, integration tests |
| `smart-ts.cabal` | Add `containers >= 0.6` to test build-depends |

---

## Task 1 — AST Extensions + Compilation Fix

**Files:**
- Modify: `lib/SmartTS/IR/AST.hs`
- Modify: `lib/SmartTS/Parser.hs` (minimal: pass `[]` for `contractEnums`)
- Modify: `lib/SmartTS/TypeCheck.hs` (minimal: pass through `contractEnums`)

- [ ] **Step 1: Add new `Type` constructors to `lib/SmartTS/IR/AST.hs`**

After `| TRecord [(Name, Type)]` add:
```haskell
          | TPair Type Type
          | TEnum Name
```

- [ ] **Step 2: Add `EnumDecl` and update `Contract`**

After `type Storage = [(Name, Type)]` add:
```haskell
data EnumDecl = EnumDecl
  { enumName     :: Name
  , enumVariants :: [Name]
  } deriving (Eq, Show)
```

Replace the `Contract` data declaration with:
```haskell
data Contract a = Contract {
  contractName    :: Name,
  contractStorage :: Storage,
  contractEnums   :: [EnumDecl],
  contractMethods :: [MethodDecl a]
} deriving (Eq, Show)
```

- [ ] **Step 3: Add new `Expr` constructors**

After `| Call    a Name [Expr a]` add:
```haskell
  | PairExpr    a (Expr a) (Expr a)
  | Fst         a (Expr a)
  | Snd         a (Expr a)
  | EnumLiteral a Name
```

- [ ] **Step 4: Add new `Stmt` constructors**

After `| SequenceStmt [Stmt a]` add:
```haskell
  | MatchStmt       (Expr a) [(Name, Stmt a)]
  | VarDestructStmt Name Name Type (Expr a)
  | ValDestructStmt Name Name Type (Expr a)
```

- [ ] **Step 5: Update `exprAnn` in `lib/SmartTS/IR/AST.hs`**

After `exprAnn (Call a _ _) = a` add:
```haskell
exprAnn (PairExpr a _ _)  = a
exprAnn (Fst a _)          = a
exprAnn (Snd a _)          = a
exprAnn (EnumLiteral a _)  = a
```

- [ ] **Step 6: Fix `parseContract` in `lib/SmartTS/Parser.hs` to compile**

Replace the `return` line in `parseContract`:
```haskell
  return $ Contract name storage [] methods
```

- [ ] **Step 7: Fix `typeCheckContract` in `lib/SmartTS/TypeCheck.hs` to compile**

Replace the `return $ Contract` block with:
```haskell
  return $ Contract
    { contractName    = contractName c
    , contractStorage = contractStorage c
    , contractEnums   = contractEnums c
    , contractMethods = typedMethods
    }
```

- [ ] **Step 8: Verify it compiles**

```
cabal build
```

Expected: builds successfully (there will be `-Wall` warnings about non-exhaustive patterns — that is normal and expected at this stage).

---

## Task 2 — Update Existing Test Patterns

**Files:**
- Modify: `test/Main.hs`

The `Contract` constructor now has 4 positional fields: `name storage enums methods`. Every existing pattern must add `[]` (empty enum list) as the third argument.

- [ ] **Step 1: Apply all pattern updates in `test/Main.hs`**

Replace every occurrence of the old 3-field form. All changes follow the same rule — insert `[]` before the methods list. The complete set of replacements:

```haskell
-- Line 65-67
-- OLD:
Contract "MyContract" [( "x", TInt)] [MethodDecl Originate "init" [] TInt (SequenceStmt [ReturnStmt (CInt _ 0)])] ->
-- NEW:
Contract "MyContract" [( "x", TInt)] [] [MethodDecl Originate "init" [] TInt (SequenceStmt [ReturnStmt (CInt _ 0)])] ->

-- All occurrences of:  Contract "Test" storage _
-- Replace with:        Contract "Test" storage _ _

-- All occurrences of:  Contract _ _ methods
-- Replace with:        Contract _ _ _ methods

-- All occurrences of:  Contract _ [(name, typ)] _
-- Replace with:        Contract _ [(name, typ)] _ _

-- All occurrences of:  Contract _ storage _
-- Replace with:        Contract _ storage _ _

-- All occurrences of:  Contract _ _ [MethodDecl ...]
-- Replace with:        Contract _ _ _ [MethodDecl ...]
```

Use the editor's find-and-replace or apply each change. The pattern is: any `Contract` with 3 arguments gets a `_` or `[]` inserted before the last argument. For patterns where the last argument is `[MethodDecl ...]`, insert `[]`; for patterns where the last argument is `_`, insert `_`.

- [ ] **Step 2: Run existing tests**

```
cabal test
```

Expected: all previously passing tests still pass. Zero new failures.

---

## Task 3 — Parser: Pair Types and Expressions

**Files:**
- Modify: `lib/SmartTS/Parser.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write failing parser tests for pair**

In `test/Main.hs`, add a new test group `pairParserTests` inside the `"Parser Tests"` group:

```haskell
pairParserTests :: TestTree
pairParserTests = testGroup "Pair Parsing"
  [ testCase "pair type in return type" $
      parseSuccess "contract T { storage: { x: int }; @originate init(): pair<int, bool> { return pair(1, true); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ (TPair TInt TBool) _] -> return ()
          _ -> assertFailure $ "Expected pair<int,bool> return type, got: " ++ show c

  , testCase "pair constructor expression" $
      parseSuccess "contract T { storage: { x: int }; @originate init(): pair<int, bool> { return pair(1, true); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (PairExpr _ (CInt _ 1) (CBool _ True))])] -> return ()
          _ -> assertFailure $ "Expected pair(1, true), got: " ++ show c

  , testCase "fst expression" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): int { return fst(p); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TInt (SequenceStmt [ReturnStmt (Fst _ (Var _ "p"))])] -> return ()
          _ -> assertFailure $ "Expected fst(p), got: " ++ show c

  , testCase "snd expression" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): bool { return snd(p); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TBool (SequenceStmt [ReturnStmt (Snd _ (Var _ "p"))])] -> return ()
          _ -> assertFailure $ "Expected snd(p), got: " ++ show c

  , testCase "nested pair type" $
      parseSuccess "contract T { storage: { x: int }; @originate init(): pair<pair<int, int>, bool> { return pair(pair(1,2), true); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ (TPair (TPair TInt TInt) TBool) _] -> return ()
          _ -> assertFailure $ "Expected pair<pair<int,int>,bool>, got: " ++ show c
  ]
```

Add `pairParserTests` to the `"Parser Tests"` group list.

- [ ] **Step 2: Run to confirm tests fail**

```
cabal test
```

Expected: the new pair tests FAIL with parse errors (pair/fst/snd not yet recognized).

- [ ] **Step 3: Add reserved words to `lib/SmartTS/Parser.hs`**

Replace the `reservedWords` list:
```haskell
reservedWords :: [String]
reservedWords =
  [ "contract", "storage", "int", "bool", "unit", "return"
  , "if", "else", "while", "var", "val", "true", "false"
  , "pair", "fst", "snd", "enum", "match"
  ]
```

- [ ] **Step 4: Add `pair<T,U>` to type parser**

Replace the `parseType` function:
```haskell
parseType :: Parser Type
parseType = parseRecordType <|> parsePrimitiveType
  where
    parsePrimitiveType :: Parser Type
    parsePrimitiveType =
      (reserved "int"  >> return TInt)
        <|> (reserved "bool" >> return TBool)
        <|> (reserved "unit" >> return TUnit)
        <|> parsePairType
        <|> (TEnum <$> parseName)

    parsePairType :: Parser Type
    parsePairType = do
      _ <- reserved "pair"
      _ <- symbol "<"
      t1 <- parseType
      _ <- symbol ","
      t2 <- parseType
      _ <- symbol ">"
      return (TPair t1 t2)

    parseRecordType :: Parser Type
    parseRecordType = do
      fields <- braces $ sepBy parseTypeField (symbol ",")
      return $ TRecord fields

    parseTypeField :: Parser (Name, Type)
    parseTypeField = do
      name <- parseName
      _ <- symbol ":"
      typ <- parseType
      return (name, typ)
```

- [ ] **Step 5: Add pair/fst/snd builtin parsers**

Add these three functions after `parseUnit`:
```haskell
parsePairBuiltin :: Parser ParsedExpr
parsePairBuiltin = do
  _ <- reserved "pair"
  (e1, e2) <- parens $ do
    e1' <- parseExpr
    _ <- symbol ","
    e2' <- parseExpr
    return (e1', e2')
  return (PairExpr () e1 e2)

parseFstBuiltin :: Parser ParsedExpr
parseFstBuiltin = do
  _ <- reserved "fst"
  e <- parens parseExpr
  return (Fst () e)

parseSndBuiltin :: Parser ParsedExpr
parseSndBuiltin = do
  _ <- reserved "snd"
  e <- parens parseExpr
  return (Snd () e)
```

- [ ] **Step 6: Insert builtins into `parseAtom`**

Replace `parseAtom`:
```haskell
parseAtom :: Parser ParsedExpr
parseAtom =
  parseUnit
    <|> parseRecordExpr
    <|> parseBool
    <|> parseInt
    <|> parsePairBuiltin
    <|> parseFstBuiltin
    <|> parseSndBuiltin
    <|> parseVarOrCall
    <|> parens parseExpr
```

- [ ] **Step 7: Run tests — pair parser tests should pass**

```
cabal test
```

Expected: all pair parser tests PASS. All other tests still pass.

---

## Task 4 — Parser: Enum, Match, Destructuring

**Files:**
- Modify: `lib/SmartTS/Parser.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write failing enum/match/destructuring parser tests**

Add to `test/Main.hs`:
```haskell
enumParserTests :: TestTree
enumParserTests = testGroup "Enum and Match Parsing"
  [ testCase "enum declaration" $
      parseSuccess "contract T { storage: { x: int }; enum Color { Red, Green, Blue } @originate init(): unit { return (); } }" $ \c ->
        case c of
          Contract _ _ [EnumDecl "Color" ["Red", "Green", "Blue"]] _ -> return ()
          _ -> assertFailure $ "Expected enum Color {Red,Green,Blue}, got: " ++ show c

  , testCase "enum type in storage" $
      parseSuccess "contract T { storage: { c: Color }; enum Color { Red, Green } @originate init(): unit { return (); } }" $ \c ->
        case c of
          Contract _ [("c", TEnum "Color")] _ _ -> return ()
          _ -> assertFailure $ "Expected TEnum Color in storage, got: " ++ show c

  , testCase "enum literal (uppercase identifier)" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(): int { return Red; } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TInt (SequenceStmt [ReturnStmt (EnumLiteral _ "Red")])] -> return ()
          _ -> assertFailure $ "Expected EnumLiteral Red, got: " ++ show c

  , testCase "match statement" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Green => { return (); } } } " $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TUnit (SequenceStmt [MatchStmt (Var _ "c") cases])] ->
            assertEqual "Two match cases" 2 (length cases)
          _ -> assertFailure $ "Expected match stmt, got: " ++ show c

  , testCase "var destructuring" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): unit { var (a, b): pair<int, bool> = p; return (); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TUnit (SequenceStmt [VarDestructStmt "a" "b" (TPair TInt TBool) (Var _ "p"), ReturnStmt (Unit _)])] -> return ()
          _ -> assertFailure $ "Expected var (a,b) destructuring, got: " ++ show c

  , testCase "val destructuring" $
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): unit { val (a, b): pair<int, bool> = p; return (); } }" $ \c ->
        case c of
          Contract _ _ _ [MethodDecl _ _ _ TUnit (SequenceStmt [ValDestructStmt "a" "b" (TPair TInt TBool) (Var _ "p"), ReturnStmt (Unit _)])] -> return ()
          _ -> assertFailure $ "Expected val (a,b) destructuring, got: " ++ show c
  ]
```

Add `enumParserTests` to the `"Parser Tests"` group.

- [ ] **Step 2: Run to confirm tests fail**

```
cabal test
```

Expected: enum/match/destructuring tests FAIL.

- [ ] **Step 3: Add uppercase-first detection to `parseVarOrCall`**

Add import at top of `lib/SmartTS/Parser.hs`:
```haskell
import Data.Char (isUpper)
```

Replace `parseVarOrCall`:
```haskell
parseVarOrCall :: Parser ParsedExpr
parseVarOrCall = do
  name <- parseName
  maybeArgs <- optional (parens (sepBy parseExpr (symbol ",")))
  return $ case maybeArgs of
    Nothing
      | not (null name) && isUpper (head name) -> EnumLiteral () name
      | otherwise                               -> Var () name
    Just args -> Call () name args
```

- [ ] **Step 4: Add `parseEnumDecl`**

Add after `parseBlock`:
```haskell
parseEnumDecl :: Parser EnumDecl
parseEnumDecl = do
  _ <- reserved "enum"
  name <- parseName
  variants <- braces (sepBy parseName (symbol ","))
  return (EnumDecl name variants)
```

- [ ] **Step 5: Add `parseMatchStmt` and `parseMatchCase`**

Add after `parseEnumDecl`:
```haskell
parseMatchStmt :: Parser ParsedStmt
parseMatchStmt = do
  _ <- reserved "match"
  e <- parens parseExpr
  cases <- braces (many parseMatchCase)
  return (MatchStmt e cases)

parseMatchCase :: Parser (Name, ParsedStmt)
parseMatchCase = do
  variant <- parseName
  _ <- symbol "=>"
  body <- parseStmt
  return (variant, body)
```

- [ ] **Step 6: Update `parseVarDeclStmt` and `parseValDeclStmt` to support destructuring**

Replace `parseVarDeclStmt`:
```haskell
parseVarDeclStmt :: Parser ParsedStmt
parseVarDeclStmt = do
  _ <- reserved "var"
  try parseDestructPart <|> parseSimplePart
  where
    parseDestructPart :: Parser ParsedStmt
    parseDestructPart = do
      _ <- symbol "("
      n1 <- parseName
      _ <- symbol ","
      n2 <- parseName
      _ <- symbol ")"
      _ <- symbol ":"
      typ <- parseType
      _ <- symbol "="
      expr <- parseExpr
      _ <- symbol ";"
      return (VarDestructStmt n1 n2 typ expr)
    parseSimplePart :: Parser ParsedStmt
    parseSimplePart = do
      name <- parseName
      _ <- symbol ":"
      typ <- parseType
      _ <- symbol "="
      expr <- parseExpr
      _ <- symbol ";"
      return (VarDeclStmt name typ expr)
```

Replace `parseValDeclStmt`:
```haskell
parseValDeclStmt :: Parser ParsedStmt
parseValDeclStmt = do
  _ <- reserved "val"
  try parseDestructPart <|> parseSimplePart
  where
    parseDestructPart :: Parser ParsedStmt
    parseDestructPart = do
      _ <- symbol "("
      n1 <- parseName
      _ <- symbol ","
      n2 <- parseName
      _ <- symbol ")"
      _ <- symbol ":"
      typ <- parseType
      _ <- symbol "="
      expr <- parseExpr
      _ <- symbol ";"
      return (ValDestructStmt n1 n2 typ expr)
    parseSimplePart :: Parser ParsedStmt
    parseSimplePart = do
      name <- parseName
      _ <- symbol ":"
      typ <- parseType
      _ <- symbol "="
      expr <- parseExpr
      _ <- symbol ";"
      return (ValDeclStmt name typ expr)
```

- [ ] **Step 7: Add `parseMatchStmt` to `parseStmt` and enum decls to `parseContract`**

Replace `parseStmt`:
```haskell
parseStmt :: Parser ParsedStmt
parseStmt =
  parseMatchStmt
    <|> parseIfStmt
    <|> parseWhileStmt
    <|> parseVarDeclStmt
    <|> parseValDeclStmt
    <|> parseReturn
    <|> parseAssignment
    <|> parseBlock
```

Replace `parseContract`:
```haskell
parseContract :: Parser ParsedContract
parseContract = do
  _ <- reserved "contract"
  name <- parseName
  _ <- symbol "{"
  storage <- parseStorage
  enums <- many parseEnumDecl
  methods <- many parseMethod
  _ <- symbol "}"
  return $ Contract name storage enums methods
```

- [ ] **Step 8: Run tests — all parser tests should pass**

```
cabal test
```

Expected: all parser tests (including new enum/match/destructuring) PASS.

---

## Task 5 — Type Checker: Pair and Enum Support

**Files:**
- Modify: `lib/SmartTS/TypeCheck.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write failing type checker tests**

Add to `test/Main.hs`:
```haskell
pairEnumTypeCheckTests :: TestTree
pairEnumTypeCheckTests = testGroup "Pair and Enum Type Checking"
  [ testCase "pair type is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; @originate init(): pair<int, bool> { return pair(1, true); } }"

  , testCase "fst returns first type" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): int { return fst(p); } }"

  , testCase "snd returns second type" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): bool { return snd(p); } }"

  , testCase "pair type mismatch fails" $
      typeCheckFailure "contract T { storage: { x: int }; @originate init(): pair<int, bool> { return pair(true, 1); } }"

  , testCase "fst on non-pair fails" $
      typeCheckFailure "contract T { storage: { x: int }; @entrypoint f(x: int): int { return fst(x); } }"

  , testCase "snd on non-pair fails" $
      typeCheckFailure "contract T { storage: { x: int }; @entrypoint f(x: int): bool { return snd(x); } }"

  , testCase "enum type in storage is well-typed" $
      typeCheckSuccess "contract T { storage: { c: Color }; enum Color { Red, Green } @originate init(): unit { storage.c = Red; return (); } }"

  , testCase "exhaustive match is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; enum Color { Red, Green } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Green => { return (); } } } "

  , testCase "non-exhaustive match fails" $
      typeCheckFailure "contract T { storage: { x: int }; enum Color { Red, Green, Blue } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } } } "

  , testCase "unknown variant in match fails" $
      typeCheckFailure "contract T { storage: { x: int }; enum Color { Red, Green } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Purple => { return (); } } } "

  , testCase "undefined enum in storage fails" $
      typeCheckFailure "contract T { storage: { c: Ghost }; @originate init(): unit { return (); } }"

  , testCase "var destructuring is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): int { var (a, b): pair<int, bool> = p; return a; } }"

  , testCase "val destructuring is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): bool { val (a, b): pair<int, bool> = p; return b; } }"

  , testCase "destructuring same name fails" $
      typeCheckFailure "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): unit { var (a, a): pair<int, bool> = p; return (); } }"

  , testCase "match on non-enum fails" $
      typeCheckFailure "contract T { storage: { x: int }; @entrypoint f(n: int): unit { match (n) { } } "
  ]
```

Add `pairEnumTypeCheckTests` to the main `tests` tree.

- [ ] **Step 2: Run to confirm tests fail**

```
cabal test
```

Expected: new type checker tests FAIL (likely with runtime errors about non-exhaustive patterns in `inferExpr`/`checkStmt`).

- [ ] **Step 3: Update `TcEnv` with enum registry fields**

In `lib/SmartTS/TypeCheck.hs`, replace the `TcEnv` declaration:
```haskell
data TcEnv = TcEnv
  { envStorageType        :: Type
  , envBindings           :: M.Map Name TcBinding
  , envFunctionSignatures :: M.Map Name Signature
  , envReturnType         :: Type
  , envEnumDefs           :: M.Map Name [Name]
  , envVariantEnum        :: M.Map Name Name
  }
  deriving (Eq, Show)
```

- [ ] **Step 4: Add enum map builder and enum reference validator**

After the `TcEnv` declaration, add:
```haskell
buildEnumMaps :: [EnumDecl] -> (M.Map Name [Name], M.Map Name Name)
buildEnumMaps decls =
  ( M.fromList [(enumName d, enumVariants d) | d <- decls]
  , M.fromList [(v, enumName d) | d <- decls, v <- enumVariants d]
  )

checkEnumRefs :: M.Map Name [Name] -> Type -> Either String ()
checkEnumRefs env = go
  where
    go (TEnum n)      = if M.member n env then Right ()
                        else Left $ "Reference to undeclared enum type `" ++ n ++ "`."
    go (TPair t1 t2)  = go t1 >> go t2
    go (TRecord fs)   = mapM_ (go . snd) fs
    go _              = Right ()
```

- [ ] **Step 5: Update `typeCheckContract` to build enum registry and validate**

Replace `typeCheckContract`:
```haskell
typeCheckContract :: ParsedContract -> Either String TypedContract
typeCheckContract c = do
  checkDuplicateStorage (contractStorage c)
  mapM_ (checkDuplicateParams . methodArgs) (contractMethods c)
  let (enumDefs, variantMap) = buildEnumMaps (contractEnums c)
  mapM_ (checkEnumRefs enumDefs . snd) (contractStorage c)
  mapM_ (\m -> do
      mapM_ (checkEnumRefs enumDefs) [t | FormalParameter _ t <- methodArgs m]
      checkEnumRefs enumDefs (methodReturnType m)
    ) (contractMethods c)
  typedMethods <- mapM (checkMethod c enumDefs variantMap) (contractMethods c)
  return $ Contract
    { contractName    = contractName c
    , contractStorage = contractStorage c
    , contractEnums   = contractEnums c
    , contractMethods = typedMethods
    }
```

- [ ] **Step 6: Update `checkMethod` signature and `env0` construction**

Replace `checkMethod`:
```haskell
checkMethod :: Contract a -> M.Map Name [Name] -> M.Map Name Name -> MethodDecl () -> Either String (MethodDecl Type)
checkMethod c enumDefs variantMap m =
  let storageT = TRecord (contractStorage c)
      paramMap =
        M.fromList
          [ (n, TcBinding Param t)
          | FormalParameter n t <- methodArgs m
          ]
      env0 =
        TcEnv
          { envStorageType        = storageT
          , envBindings           = paramMap
          , envFunctionSignatures = buildSigMap c
          , envReturnType         = methodReturnType m
          , envEnumDefs           = enumDefs
          , envVariantEnum        = variantMap
          }
   in case runStateT (checkStmt (methodBody m)) env0 of
        Left err -> Left err
        Right (typedBody, _) -> Right $ MethodDecl
          { methodKind       = methodKind m
          , methodName       = methodName m
          , methodArgs       = methodArgs m
          , methodReturnType = methodReturnType m
          , methodBody       = typedBody
          }
```

- [ ] **Step 7: Add `typesEqual` and `prettyType` cases for new types**

In `typesEqual`, after `typesEqual (TRecord as) (TRecord bs) = ...` add:
```haskell
typesEqual (TPair t1 t2) (TPair s1 s2) = typesEqual t1 s1 && typesEqual t2 s2
typesEqual (TEnum n)     (TEnum m)     = n == m
```

In `prettyType`, after `prettyType (TRecord fs) = ...` add:
```haskell
prettyType (TPair t1 t2) = "pair<" ++ prettyType t1 ++ ", " ++ prettyType t2 ++ ">"
prettyType (TEnum n)     = n
```

- [ ] **Step 8: Add `inferExpr` cases for pair and enum expressions**

After `inferExpr (Call () name args) = ...` add:
```haskell
inferExpr (PairExpr () e1 e2) = do
  te1 <- inferExpr e1
  te2 <- inferExpr e2
  let ty = TPair (exprAnn te1) (exprAnn te2)
  return (PairExpr ty te1 te2)

inferExpr (Fst () e) = do
  te <- inferExpr e
  case exprAnn te of
    TPair t1 _ -> return (Fst t1 te)
    t -> tcError $ "fst requires pair<T, U>, got " ++ prettyType t ++ "."

inferExpr (Snd () e) = do
  te <- inferExpr e
  case exprAnn te of
    TPair _ t2 -> return (Snd t2 te)
    t -> tcError $ "snd requires pair<T, U>, got " ++ prettyType t ++ "."

inferExpr (EnumLiteral () variant) = do
  env <- get
  case M.lookup variant (envVariantEnum env) of
    Nothing    -> tcError $ "Unknown enum variant `" ++ variant ++ "`."
    Just eName -> return (EnumLiteral (TEnum eName) variant)
```

- [ ] **Step 9: Add `checkStmt` cases for match and destructuring**

After `checkStmt (WhileStmt cond body) = ...` add:
```haskell
checkStmt (MatchStmt e cases) = do
  te <- inferExpr e
  case exprAnn te of
    TEnum eName -> do
      env <- get
      let variants = maybe [] id (M.lookup eName (envEnumDefs env))
          covered  = map fst cases
          missing  = filter (`notElem` covered) variants
          unknown  = filter (`notElem` variants) covered
      unless (null missing) $
        tcError $ "Non-exhaustive match on `" ++ eName ++ "`: missing " ++ show missing ++ "."
      unless (length covered == length (nub covered)) $
        tcError "Duplicate variant in match arms."
      unless (null unknown) $
        tcError $ "Unknown variant(s) in match: " ++ show unknown ++ "."
      tcases <- mapM (\(v, s) -> (,) v <$> withSavedEnv (checkStmt s)) cases
      return (MatchStmt te tcases)
    t -> tcError $ "match requires an enum expression, got " ++ prettyType t ++ "."

checkStmt (VarDestructStmt n1 n2 annType e) = do
  when (n1 == n2) $ tcError "Destructuring variables must have different names."
  noDuplicateLocal n1
  noDuplicateLocal n2
  te <- inferExpr e
  lift $ expectType ("var (" ++ n1 ++ ", " ++ n2 ++ ") destructuring") (exprAnn te) annType
  case annType of
    TPair t1 t2 -> do
      modify $ insertLocal n1 LocalMutable t1
      modify $ insertLocal n2 LocalMutable t2
      return (VarDestructStmt n1 n2 annType te)
    _ -> tcError "var destructuring requires a pair<T, U> type annotation."

checkStmt (ValDestructStmt n1 n2 annType e) = do
  when (n1 == n2) $ tcError "Destructuring variables must have different names."
  noDuplicateLocal n1
  noDuplicateLocal n2
  te <- inferExpr e
  lift $ expectType ("val (" ++ n1 ++ ", " ++ n2 ++ ") destructuring") (exprAnn te) annType
  case annType of
    TPair t1 t2 -> do
      modify $ insertLocal n1 LocalImmutable t1
      modify $ insertLocal n2 LocalImmutable t2
      return (ValDestructStmt n1 n2 annType te)
    _ -> tcError "val destructuring requires a pair<T, U> type annotation."
```

- [ ] **Step 10: Run tests — all type checker tests should pass**

```
cabal test
```

Expected: all new pair/enum type checker tests PASS. All prior tests still pass.

---

## Task 6 — Interpreter: Eval.hs

**Files:**
- Modify: `lib/SmartTS/Interpreter/Eval.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write failing interpreter tests**

Add to `test/Main.hs`:

```haskell
import qualified Data.Map.Strict as M
-- (add to existing imports)
-- Also extend the SmartTS.Interpreter import:
import SmartTS.Interpreter ( ContractInstance (..)
                            , contractInstanceFromStorageValue
                            , originateWithJsonArgs
                            , callEntrypointWithJsonArgs
                            )
```

Add test group:
```haskell
interpreterTests :: TestTree
interpreterTests = testGroup "Interpreter"
  [ testCase "pair construction and fst/snd" $ do
      let src = "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): int { return fst(p); } }"
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right tc ->
          let args = object ["p" .= object ["fst" .= (42 :: Int), "snd" .= True]]
          in case callEntrypointWithJsonArgs M.empty tc "addr" "f" src args of
            Left _         -> assertFailure "callEntrypoint should succeed"
            Right (ret, _) -> case ret of
              Just (CInt _ 42) -> return ()
              _                -> assertFailure "Expected fst of pair to be 42"

  , testCase "enum match: correct branch executes" $ do
      let src = unlines
            [ "contract T {"
            , "  storage: { result: int };"
            , "  enum Color { Red, Green }"
            , "  @originate init(): unit { storage.result = 0; return (); }"
            , "  @entrypoint choose(c: Color): int {"
            , "    match (c) {"
            , "      Red   => { storage.result = 1; }"
            , "      Green => { storage.result = 2; }"
            , "    }"
            , "    return storage.result;"
            , "  }"
            , "}"
            ]
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right tc -> do
          (addr, repo) <- case originateWithJsonArgs M.empty tc src (object []) of
            Left err -> assertFailure err >> return undefined
            Right ok -> return ok
          let callChoose r color =
                callEntrypointWithJsonArgs r tc addr "choose" src (object ["c" .= (color :: String)])
          case callChoose repo "Red" of
            Left err -> assertFailure err
            Right (Just (CInt _ 1), _) -> return ()
            Right (ret, _) -> assertFailure $ "Expected 1 for Red, got: " ++ show ret

  , testCase "var destructuring binds both variables" $ do
      let src = "contract T { storage: { x: int }; @entrypoint f(p: pair<int, int>): int { var (a, b): pair<int, int> = p; return a; } }"
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right tc ->
          let args = object ["p" .= object ["fst" .= (7 :: Int), "snd" .= (3 :: Int)]]
          in case callEntrypointWithJsonArgs M.empty tc "addr" "f" src args of
            Left err -> assertFailure err
            Right (Just (CInt _ 7), _) -> return ()
            Right (ret, _) -> assertFailure $ "Expected 7, got: " ++ show ret
  ]
```

Add `interpreterTests` to the main `tests` tree.

Note: `callEntrypointWithJsonArgs` with an address that doesn't exist in the repo will fail the address lookup. For simple one-off tests that don't need persistence, originate first. For `f` which is `@entrypoint`, use originate+call. Alternatively use `execMethodWithInitialStorage` directly. Let me use originate+call for the pair test too:

Replace the pair test:
```haskell
  , testCase "pair construction and fst/snd via call" $ do
      let src = unlines
            [ "contract T {"
            , "  storage: { x: int };"
            , "  @originate init(): unit { storage.x = 0; return (); }"
            , "  @entrypoint f(p: pair<int, bool>): int { return fst(p); }"
            , "}"
            ]
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right tc -> do
          (addr, repo) <- case originateWithJsonArgs M.empty tc src (object []) of
            Left err -> assertFailure err >> return undefined
            Right ok -> return ok
          let args = object ["p" .= object ["fst" .= (42 :: Int), "snd" .= True]]
          case callEntrypointWithJsonArgs repo tc addr "f" src args of
            Left err -> assertFailure err
            Right (Just (CInt _ 42), _) -> return ()
            Right (ret, _) -> assertFailure $ "Expected fst=42, got: " ++ show ret
```

- [ ] **Step 2: Add `containers >= 0.6` to test build-depends in `smart-ts.cabal`**

In the `test-suite smart-ts-test` section, replace:
```cabal
    build-depends:
        base >=4.17.0.0,
        aeson >=2.0,
        smart-ts,
        tasty >=1.4,
        tasty-hunit >=0.10
```
with:
```cabal
    build-depends:
        base >=4.17.0.0,
        aeson >=2.0,
        containers >=0.6,
        smart-ts,
        tasty >=1.4,
        tasty-hunit >=0.10
```

- [ ] **Step 3: Run to confirm tests fail**

```
cabal test
```

Expected: interpreter tests FAIL (non-exhaustive pattern in `evalExpr` or `execStmt`).

- [ ] **Step 4: Add `evalExpr` cases to `lib/SmartTS/Interpreter/Eval.hs`**

After `evalExpr (Call _ name args) = ...` add:
```haskell
evalExpr e@(EnumLiteral _ _) = return e

evalExpr (PairExpr ty e1 e2) = do
  v1 <- evalExpr e1
  v2 <- evalExpr e2
  return (PairExpr ty v1 v2)

evalExpr (Fst _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ v1 _ -> return v1
    _               -> interpretBug "fst applied to non-pair value after type check"

evalExpr (Snd _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ _ v2 -> return v2
    _               -> interpretBug "snd applied to non-pair value after type check"
```

- [ ] **Step 5: Add `execStmt` cases to `lib/SmartTS/Interpreter/Eval.hs`**

After `execStmt (WhileStmt cond body) = ...` add:
```haskell
execStmt (MatchStmt e cases) = do
  v <- evalExpr e
  case v of
    EnumLiteral _ variant ->
      case lookup variant cases of
        Nothing -> interpretBug ("non-exhaustive match on `" ++ variant ++ "` after type check")
        Just s  -> execStmt s
    _ -> interpretBug "match applied to non-enum value after type check"

execStmt (VarDestructStmt n1 n2 _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ v1 v2 -> do
      modify $ \rt -> rt { rtLocals =
        M.insert n2 (Binding True v2) (M.insert n1 (Binding True v1) (rtLocals rt)) }
      return Nothing
    _ -> interpretBug "var destructuring on non-pair value after type check"

execStmt (ValDestructStmt n1 n2 _ e) = do
  v <- evalExpr e
  case v of
    PairExpr _ v1 v2 -> do
      modify $ \rt -> rt { rtLocals =
        M.insert n2 (Binding False v2) (M.insert n1 (Binding False v1) (rtLocals rt)) }
      return Nothing
    _ -> interpretBug "val destructuring on non-pair value after type check"
```

- [ ] **Step 6: Run tests — interpreter tests should pass**

```
cabal test
```

Expected: all interpreter tests PASS. All prior tests still pass.

---

## Task 7 — Codec: JSON Encoding/Decoding

**Files:**
- Modify: `lib/SmartTS/Interpreter/Codec.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write failing codec tests**

Add to `test/Main.hs`:
```haskell
codecTests :: TestTree
codecTests = testGroup "Codec (JSON)"
  [ testCase "pair encodes to {fst, snd} object" $
      let v = PairExpr (TPair TInt TBool) (CInt TInt 3) (CBool TBool True)
          json = exprToJson v
      in json @?= object ["fst" .= (3 :: Int), "snd" .= True]

  , testCase "pair decodes from {fst, snd} object" $
      let ty = TPair TInt TBool
          json = object ["fst" .= (3 :: Int), "snd" .= True]
      in jsonToExprByType ty json @?=
           Right (PairExpr (TPair TInt TBool) (CInt TInt 3) (CBool TBool True))

  , testCase "enum encodes to string" $
      let v = EnumLiteral (TEnum "Color") "Red"
          json = exprToJson v
      in json @?= toJSON ("Red" :: String)

  , testCase "enum decodes from string" $
      let ty = TEnum "Color"
          json = toJSON ("Green" :: String)
      in jsonToExprByType ty json @?= Right (EnumLiteral (TEnum "Color") "Green")
  ]
```

Add to imports in `test/Main.hs`:
```haskell
import Data.Aeson (object, (.=), toJSON)
import SmartTS.Interpreter (ContractInstance (..), contractInstanceFromStorageValue,
                             originateWithJsonArgs, callEntrypointWithJsonArgs,
                             exprToJson, jsonToExprByType)
```

Add `codecTests` to the main `tests` tree.

- [ ] **Step 2: Run to confirm tests fail**

```
cabal test
```

Expected: codec tests FAIL (`exprToJson` returns `Null` for pair/enum, `jsonToExprByType` returns `Left` for pair/enum types).

- [ ] **Step 3: Add `import qualified Data.Text as T` to `lib/SmartTS/Interpreter/Codec.hs`**

Add after the existing imports:
```haskell
import qualified Data.Text as T
```

- [ ] **Step 4: Add pair and enum cases to `exprToJson`**

In `lib/SmartTS/Interpreter/Codec.hs`, the current `exprToJson` ends with `exprToJson _ = Null`. Insert new cases BEFORE that catch-all:
```haskell
exprToJson (PairExpr _ e1 e2) =
  Object $ KM.fromList
    [ (fromStringKey "fst", exprToJson e1)
    , (fromStringKey "snd", exprToJson e2)
    ]
exprToJson (EnumLiteral _ variant) = String (T.pack variant)
```

- [ ] **Step 5: Add pair and enum cases to `jsonToExprByType`**

After `jsonToExprByType (TRecord fieldsT) (Object obj) = ...` add:
```haskell
jsonToExprByType (TPair t1 t2) (Object obj) = do
  v1 <- case KM.lookup (fromStringKey "fst") obj of
    Nothing -> Left "Missing 'fst' field in pair JSON."
    Just v  -> jsonToExprByType t1 v
  v2 <- case KM.lookup (fromStringKey "snd") obj of
    Nothing -> Left "Missing 'snd' field in pair JSON."
    Just v  -> jsonToExprByType t2 v
  Right (PairExpr (TPair t1 t2) v1 v2)
jsonToExprByType t@(TEnum _) (String s) = Right (EnumLiteral t (T.unpack s))
```

- [ ] **Step 6: Run tests — codec tests should pass**

```
cabal test
```

Expected: all codec tests PASS. All prior tests still pass.

---

## Task 8 — LLTZ Code Generation

**Files:**
- Modify: `lib/SmartTS/CodeGen/CompileLLTZ.hs`
- Modify: `test/Main.hs`

- [ ] **Step 1: Write LLTZ translation tests**

Add to `test/Main.hs`:
```haskell
import SmartTS.CodeGen.CompileLLTZ (translateType, buildEnumDefs)
import qualified SmartTS.IR.LLTZ as L
-- (add to existing imports)
```

Add test group:
```haskell
lltzTests :: TestTree
lltzTests = testGroup "LLTZ Code Generation"
  [ testCase "pair type → TTuple" $
      let env = M.empty
      in translateType env (TPair TInt TBool)
           @?= L.TTuple (L.RowNode
                 [ L.RowLeaf Nothing L.TInt
                 , L.RowLeaf Nothing L.TBool
                 ])

  , testCase "enum type → TOr" $
      let env = M.fromList [("Color", ["Red", "Green"])]
      in translateType env (TEnum "Color")
           @?= L.TOr (L.RowNode
                 [ L.RowLeaf (Just (L.Label "Red"))   L.TUnit
                 , L.RowLeaf (Just (L.Label "Green"))  L.TUnit
                 ])

  , testCase "nested pair type → nested TTuple" $
      let env = M.empty
      in translateType env (TPair (TPair TInt TInt) TBool)
           @?= L.TTuple (L.RowNode
                 [ L.RowLeaf Nothing
                     (L.TTuple (L.RowNode [L.RowLeaf Nothing L.TInt, L.RowLeaf Nothing L.TInt]))
                 , L.RowLeaf Nothing L.TBool
                 ])

  , testCase "int type → TInt" $
      translateType M.empty TInt @?= L.TInt

  , testCase "bool type → TBool" $
      translateType M.empty TBool @?= L.TBool
  ]
```

Add `lltzTests` to the main `tests` tree.

- [ ] **Step 2: Run to confirm tests fail**

```
cabal test
```

Expected: LLTZ tests FAIL (module doesn't export `buildEnumDefs`, and `translateType` doesn't accept `EnumDefs` parameter yet).

- [ ] **Step 3: Rewrite `lib/SmartTS/CodeGen/CompileLLTZ.hs` completely**

Replace the entire file with:
```haskell
module SmartTS.CodeGen.CompileLLTZ where

import qualified SmartTS.IR.AST  as A
import qualified SmartTS.IR.LLTZ as L
import qualified Data.Map.Strict as M
import Data.List (break)

-- | Enum definitions: enum name → ordered list of variant names.
type EnumDefs = M.Map A.Name [A.Name]

-- | Build the enum registry from a typed contract.
buildEnumDefs :: A.TypedContract -> EnumDefs
buildEnumDefs c =
  M.fromList [(A.enumName e, A.enumVariants e) | e <- A.contractEnums c]

-- ---------------------------------------------------------------------------
-- Type translation
-- ---------------------------------------------------------------------------

translateType :: EnumDefs -> A.Type -> L.Type
translateType _   A.TInt             = L.TInt
translateType _   A.TBool            = L.TBool
translateType _   A.TUnit            = L.TUnit
translateType env (A.TRecord fields) =
  L.TTuple (L.RowNode
    [L.RowLeaf (Just (L.Label name)) (translateType env ty) | (name, ty) <- fields])
translateType env (A.TPair t1 t2) =
  L.TTuple (L.RowNode
    [L.RowLeaf Nothing (translateType env t1), L.RowLeaf Nothing (translateType env t2)])
translateType env (A.TEnum eName) =
  case M.lookup eName env of
    Nothing -> error $ "CompileLLTZ: unknown enum `" ++ eName ++ "`"
    Just vs -> L.TOr (L.RowNode
      [L.RowLeaf (Just (L.Label v)) L.TUnit | v <- vs])

-- ---------------------------------------------------------------------------
-- Expression translation
-- ---------------------------------------------------------------------------

translateExpression :: EnumDefs -> A.TypedExpr -> L.Expr
-- Constants
translateExpression env (A.CInt  ty v)   = mkExpr env (L.Const (L.CInt v))  ty
translateExpression env (A.CBool ty v)   = mkExpr env (L.Const (L.CBool v)) ty
translateExpression env (A.Unit  _)      = L.Expr (L.Const L.CUnit) L.TUnit
translateExpression env (A.Var   ty n)   = mkExpr env (L.Variable (L.Var n)) ty
-- Boolean
translateExpression env (A.And ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimAnd
translateExpression env (A.Or  ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimOr
translateExpression env (A.Not ty e)     = translateUnaryExpression  env e  ty L.PrimNot
-- Arithmetic
translateExpression env (A.Add ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimAdd
translateExpression env (A.Sub ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimSub
translateExpression env (A.Mul ty e1 e2) = translateBinaryExpression env e1 e2 ty L.PrimMul
translateExpression _   (A.Div _ _ _)   = error "CompileLLTZ: Div uses EDIV in Michelson (not yet implemented)"
translateExpression _   (A.Mod _ _ _)   = error "CompileLLTZ: Mod uses EDIV in Michelson (not yet implemented)"
-- Comparisons (Michelson: COMPARE then EQ/NEQ/LT/LE/GT/GE)
translateExpression env (A.Eq  ty e1 e2) = cmpExpr env e1 e2 ty L.PrimEq
translateExpression env (A.Neq ty e1 e2) = cmpExpr env e1 e2 ty L.PrimNeq
translateExpression env (A.Lt  ty e1 e2) = cmpExpr env e1 e2 ty L.PrimLt
translateExpression env (A.Lte ty e1 e2) = cmpExpr env e1 e2 ty L.PrimLe
translateExpression env (A.Gt  ty e1 e2) = cmpExpr env e1 e2 ty L.PrimGt
translateExpression env (A.Gte ty e1 e2) = cmpExpr env e1 e2 ty L.PrimGe
-- Record
translateExpression env (A.Record ty fields) =
  L.Expr
    (L.TupleExpr (L.RowNode
      [L.RowLeaf (Just (L.Label k)) (translateExpression env v) | (k, v) <- fields]))
    (translateType env ty)
-- Field access (TODO: requires storage threading)
translateExpression env (A.StorageExpr ty) =
  error "CompileLLTZ: StorageExpr translation requires storage threading (not yet implemented)"
translateExpression env (A.FieldAccess ty _ _) =
  error "CompileLLTZ: FieldAccess translation requires storage threading (not yet implemented)"
-- Call (TODO: requires lambda lifting)
translateExpression _ (A.Call _ _ _) =
  error "CompileLLTZ: Call translation not yet implemented"
-- Pair
translateExpression env (A.PairExpr ty e1 e2) =
  L.Expr
    (L.TupleExpr (L.RowNode
      [L.RowLeaf Nothing (translateExpression env e1),
       L.RowLeaf Nothing (translateExpression env e2)]))
    (translateType env ty)
translateExpression env (A.Fst ty e) =
  L.Expr (L.Proj (translateExpression env e) (L.RowPath [0])) (translateType env ty)
translateExpression env (A.Snd ty e) =
  L.Expr (L.Proj (translateExpression env e) (L.RowPath [1])) (translateType env ty)
-- Enum literal → Inj into TOr at the variant's position
translateExpression env (A.EnumLiteral ty@(A.TEnum eName) variant) =
  case M.lookup eName env of
    Nothing -> error $ "CompileLLTZ: unknown enum `" ++ eName ++ "`"
    Just vs ->
      let (lefts, _:rights) = break (== variant) vs
          toLeaf v  = L.RowLeaf (Just (L.Label v)) L.TUnit
          ctx       = L.RowCtxNode (map toLeaf lefts) (toLeaf variant) (map toLeaf rights)
          unitExpr  = L.Expr (L.Const L.CUnit) L.TUnit
      in L.Expr (L.Inj ctx unitExpr) (translateType env ty)
translateExpression _ (A.EnumLiteral _ _) =
  error "CompileLLTZ: EnumLiteral without TEnum annotation"

-- ---------------------------------------------------------------------------
-- Block translation
-- ---------------------------------------------------------------------------

-- | Translate a list of statements into a nested LLTZ let-expression.
-- VarDeclStmt, ValDeclStmt, VarDestructStmt, ValDestructStmt are handled here
-- because they introduce bindings visible to the rest of the block.
translateBlock :: EnumDefs -> [A.TypedStmt] -> L.Expr
translateBlock _   []     = L.Expr L.Skip L.TUnit
translateBlock env (s:ss) =
  case s of
    A.VarDeclStmt name _ty expr ->
      L.Expr (L.LetMutIn (L.MutVar name) (translateExpression env expr) block) ty
    A.ValDeclStmt name _ty expr ->
      L.Expr (L.LetIn (L.Var name) (translateExpression env expr) block) ty
    A.VarDestructStmt n1 n2 _ty expr ->
      let e'       = translateExpression env expr
          pairTy   = L.exprType e'
          t1       = elemTypeAt pairTy 0
          t2       = elemTypeAt pairTy 1
          proj0    = L.Expr (L.Proj e' (L.RowPath [0])) t1
          proj1    = L.Expr (L.Proj e' (L.RowPath [1])) t2
          inner    = L.Expr (L.LetMutIn (L.MutVar n2) proj1 block) ty
      in L.Expr (L.LetMutIn (L.MutVar n1) proj0 inner) ty
    A.ValDestructStmt n1 n2 _ty expr ->
      let e'       = translateExpression env expr
          pairTy   = L.exprType e'
          t1       = elemTypeAt pairTy 0
          t2       = elemTypeAt pairTy 1
          proj0    = L.Expr (L.Proj e' (L.RowPath [0])) t1
          proj1    = L.Expr (L.Proj e' (L.RowPath [1])) t2
          inner    = L.Expr (L.LetIn (L.Var n2) proj1 block) ty
      in L.Expr (L.LetIn (L.Var n1) proj0 inner) ty
    _ ->
      L.Expr (L.LetIn (L.Var "_") (translateStatement env s) block) ty
  where
    block = translateBlock env ss
    ty    = L.exprType block

-- ---------------------------------------------------------------------------
-- Statement translation
-- ---------------------------------------------------------------------------

translateStatement :: EnumDefs -> A.TypedStmt -> L.Expr
translateStatement env (A.AssignmentStmt (A.LVar name) expr) =
  L.Expr (L.Assign (L.MutVar name) (translateExpression env expr)) L.TUnit
translateStatement _ (A.AssignmentStmt _ _) =
  error "CompileLLTZ: storage/field assignment translation not yet implemented"
translateStatement env (A.IfStmt cond s1 (Just s2)) =
  let cond' = translateExpression env cond
      s1'   = translateStatement env s1
      s2'   = translateStatement env s2
  in assert
       (L.exprType s1' == L.exprType s2')
       "[Impossible] Inconsistent if-branch types."
       (L.Expr (L.IfBool cond' s1' s2') (L.exprType s1'))
translateStatement env (A.IfStmt cond s1 Nothing) =
  let cond' = translateExpression env cond
      s1'   = translateStatement env s1
  in L.Expr (L.IfBool cond' s1' (L.Expr L.Skip L.TUnit)) (L.exprType s1')
translateStatement env (A.WhileStmt cond body) =
  L.Expr (L.While (translateExpression env cond) (translateStatement env body)) L.TUnit
translateStatement env (A.ReturnStmt expr) =
  translateExpression env expr
translateStatement env (A.SequenceStmt stmts) =
  translateBlock env stmts
translateStatement env (A.MatchStmt e cases) =
  let e' = translateExpression env e
  in case A.exprAnn e of
    A.TEnum eName -> case M.lookup eName env of
      Nothing -> error $ "CompileLLTZ: unknown enum `" ++ eName ++ "` in match"
      Just vs ->
        let caseMap    = M.fromList cases
            mkBranch v = L.LambdaBinder
              { L.lamVar  = (L.Var "_", L.TUnit)
              , L.lamBody = translateStatement env (caseMap M.! v)
              }
            branches   = map mkBranch vs
            branchRow  = L.RowNode
              (zipWith (\v b -> L.RowLeaf (Just (L.Label v)) b) vs branches)
            resultTy   = L.exprType (L.lamBody (head branches))
        in L.Expr (L.Match e' branchRow) resultTy
    _ -> error "CompileLLTZ: MatchStmt on non-TEnum expression"
translateStatement _ s =
  error $ "CompileLLTZ: unexpected statement in translateStatement: " ++ show (fmap (const ()) s)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkExpr :: EnumDefs -> L.ExprDesc -> A.Type -> L.Expr
mkExpr env e t = L.Expr e (translateType env t)

translateUnaryExpression :: EnumDefs -> A.TypedExpr -> A.Type -> L.Primitive -> L.Expr
translateUnaryExpression env e ty prim =
  mkExpr env (L.Prim prim [translateExpression env e]) ty

translateBinaryExpression :: EnumDefs -> A.TypedExpr -> A.TypedExpr -> A.Type -> L.Primitive -> L.Expr
translateBinaryExpression env l r ty prim =
  mkExpr env (L.Prim prim [translateExpression env l, translateExpression env r]) ty

-- | COMPARE + flag: translate SmartTS comparison to Michelson-style COMPARE;FLAG.
cmpExpr :: EnumDefs -> A.TypedExpr -> A.TypedExpr -> A.Type -> L.Primitive -> L.Expr
cmpExpr env e1 e2 ty flag =
  let l'  = translateExpression env e1
      r'  = translateExpression env e2
      cmp = L.Expr (L.Prim L.PrimCompare [l', r']) L.TInt
  in mkExpr env (L.Prim flag [cmp]) ty

-- | Extract the LLTZ type of the i-th element of a TTuple.
elemTypeAt :: L.Type -> Int -> L.Type
elemTypeAt (L.TTuple (L.RowNode leaves)) i =
  case drop i leaves of
    (L.RowLeaf _ t : _) -> t
    _                   -> error "CompileLLTZ: elemTypeAt index out of bounds"
elemTypeAt t _ =
  error $ "CompileLLTZ: elemTypeAt on non-TTuple type: " ++ show t

assert :: Bool -> String -> a -> a
assert False msg _ = error msg
assert True  _   v = v
```

- [ ] **Step 4: Run LLTZ tests**

```
cabal test
```

Expected: LLTZ type translation tests PASS. All other tests still pass.

---

## Task 9 — Integration Tests (TrafficLight + VotingBox)

**Files:**
- Modify: `test/Main.hs`

- [ ] **Step 1: Add end-to-end TrafficLight test**

Add to `test/Main.hs`:
```haskell
integrationTests :: TestTree
integrationTests = testGroup "Integration"
  [ testCase "TrafficLight: originate and three-cycle" $ do
      let src = unlines
            [ "contract TrafficLight {"
            , "  storage: { light: Light, cycles: int };"
            , "  enum Light { Red, Yellow, Green }"
            , "  @originate"
            , "  init(): unit {"
            , "    storage.light = Red;"
            , "    storage.cycles = 0;"
            , "    return ();"
            , "  }"
            , "  @entrypoint"
            , "  next(): unit {"
            , "    match (storage.light) {"
            , "      Red    => { storage.light = Green; }"
            , "      Green  => { storage.light = Yellow; }"
            , "      Yellow => { storage.light = Red; storage.cycles = storage.cycles + 1; }"
            , "    }"
            , "    return ();"
            , "  }"
            , "}"
            ]
      tc <- case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err >> return undefined
        Right c  -> return c
      (addr, repo0) <- case originateWithJsonArgs M.empty tc src (object []) of
        Left err -> assertFailure err >> return undefined
        Right ok -> return ok
      let callNext r = callEntrypointWithJsonArgs r tc addr "next" src (object [])
      -- Red → Green
      (_, repo1) <- case callNext repo0 of
        Left err -> assertFailure err >> return undefined
        Right ok -> return ok
      -- Green → Yellow
      (_, repo2) <- case callNext repo1 of
        Left err -> assertFailure err >> return undefined
        Right ok -> return ok
      -- Yellow → Red, cycles = 1
      (_, repo3) <- case callNext repo2 of
        Left err -> assertFailure err >> return undefined
        Right ok -> return ok
      case M.lookup addr repo3 of
        Nothing -> assertFailure "address not found after three calls"
        Just ci -> case instanceStorage ci of
          Record _ [("light", EnumLiteral _ "Red"), ("cycles", CInt _ 1)] -> return ()
          s -> assertFailure $ "Unexpected storage after 3 cycles: " ++ show s

  , testCase "VotingBox: originate, vote, close" $ do
      let src = unlines
            [ "contract VotingBox {"
            , "  storage: { phase: Phase, result: pair<int, int>, votesFor: int, votesAgainst: int };"
            , "  enum Phase { Open, Closed }"
            , "  @originate"
            , "  init(): unit {"
            , "    storage.phase        = Open;"
            , "    storage.votesFor     = 0;"
            , "    storage.votesAgainst = 0;"
            , "    storage.result       = pair(0, 0);"
            , "    return ();"
            , "  }"
            , "  @entrypoint"
            , "  vote(inFavor: bool): unit {"
            , "    match (storage.phase) {"
            , "      Open => {"
            , "        if (inFavor) {"
            , "          storage.votesFor = storage.votesFor + 1;"
            , "        } else {"
            , "          storage.votesAgainst = storage.votesAgainst + 1;"
            , "        }"
            , "      }"
            , "      Closed => { storage.votesFor = storage.votesFor; }"
            , "    }"
            , "    return ();"
            , "  }"
            , "  @entrypoint"
            , "  close(): pair<int, int> {"
            , "    storage.phase  = Closed;"
            , "    storage.result = pair(storage.votesFor, storage.votesAgainst);"
            , "    return storage.result;"
            , "  }"
            , "}"
            ]
      tc <- case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err >> return undefined
        Right c  -> return c
      (addr, repo0) <- case originateWithJsonArgs M.empty tc src (object []) of
        Left err -> assertFailure err >> return undefined
        Right ok -> return ok
      let callVote r inFavor =
            callEntrypointWithJsonArgs r tc addr "vote" src (object ["inFavor" .= inFavor])
          callClose r =
            callEntrypointWithJsonArgs r tc addr "close" src (object [])
      (_, repo1) <- case callVote repo0 True  of { Left e -> assertFailure e >> return undefined; Right ok -> return ok }
      (_, repo2) <- case callVote repo1 True  of { Left e -> assertFailure e >> return undefined; Right ok -> return ok }
      (_, repo3) <- case callVote repo2 False of { Left e -> assertFailure e >> return undefined; Right ok -> return ok }
      (ret, _)   <- case callClose repo3 of { Left e -> assertFailure e >> return undefined; Right ok -> return ok }
      case ret of
        Just (PairExpr _ (CInt _ 2) (CInt _ 1)) -> return ()
        _ -> assertFailure $ "Expected pair(2,1) from close(), got: " ++ show ret
  ]
```

Add `integrationTests` to the main `tests` tree.

- [ ] **Step 2: Run integration tests**

```
cabal test
```

Expected: both TrafficLight and VotingBox tests PASS. Full test suite green.

- [ ] **Step 3: Verify the sample files parse and type-check**

Add a quick smoke-test reading the actual sample files. In `test/Main.hs`:
```haskell
  , testCase "samples/TrafficLight.smartts parses and type-checks" $ do
      src <- readFile "samples/TrafficLight.smartts"
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right _  -> return ()

  , testCase "samples/VotingBox.smartts parses and type-checks" $ do
      src <- readFile "samples/VotingBox.smartts"
      case parseContractFromString src >>= typeCheckContract of
        Left err -> assertFailure err
        Right _  -> return ()
```

Add these inside `integrationTests`.

- [ ] **Step 4: Final full test run**

```
cabal test
```

Expected: entire test suite PASSES — parser, type checker, interpreter, codec, LLTZ, and integration tests all green.

---

## Self-Review Notes

- All `Contract` positional patterns updated in Task 2 before any new tests are added.
- LLTZ `StorageExpr`/`FieldAccess`/`Call` translation left as explicit `error` stubs — the code gen tests only exercise types and pure expressions, which is all that's testable without storage threading.
- `VarDestructStmt`/`ValDestructStmt` handled in `translateBlock` (not `translateStatement`) — consistent with how `VarDeclStmt`/`ValDeclStmt` work.
- `MatchStmt` reorders cases to enum definition order via `caseMap M.! v` — required by LLTZ `Match`'s positional row.
- `Div`/`Mod` translation left as `error` stubs — sample contracts don't use them, and Michelson's `EDIV` returns `option pair<...>` which requires additional unwrapping.

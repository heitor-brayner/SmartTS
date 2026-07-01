{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import SmartTS.IR.AST
import SmartTS.Parser
import Data.Aeson (object, (.=), toJSON, Value (..))
import SmartTS.Interpreter ( ContractInstance (..)
                            , contractInstanceFromStorageValue
                            , originateWithJsonArgs
                            , callEntrypointWithJsonArgs
                            , exprToJson
                            , jsonToExprByType
                            )
import SmartTS.TypeCheck (typeCheckContract)
import SmartTS.CodeGen.CompileLLTZ (buildEnumDefs, translateType)
import qualified SmartTS.IR.LLTZ as L
import qualified Data.Map.Strict as M

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "SmartTS"
    [ testGroup
        "Parser Tests"
        [ contractTests
        , storageTests
        , methodTests
        , expressionTests
        , statementTests
        , errorTests
        , pairParserTests
        , enumParserTests
        ]
    , typeCheckTests
    , pairEnumTypeCheckTests
    , codecTests
    , lltzTests
    ]

-- Helper function to parse and assert success
parseSuccess :: String -> (ParsedContract -> Assertion) -> Assertion
parseSuccess input assertion = case parseContractFromString input of
  Left err      -> assertFailure $ "Parse failed: " ++ show err
  Right contract -> assertion contract

-- Helper function to parse and assert failure
parseFailure :: String -> Assertion
parseFailure input = case parseContractFromString input of
  Left _  -> return ()  -- Expected failure
  Right _ -> assertFailure "Expected parse failure but got success"

typeCheckSuccess :: String -> Assertion
typeCheckSuccess input = case parseContractFromString input of
  Left err -> assertFailure $ "Parse failed: " ++ show err
  Right c ->
    case typeCheckContract c of
      Left err -> assertFailure $ "Type check failed: " ++ err
      Right _  -> return ()

typeCheckFailure :: String -> Assertion
typeCheckFailure input = case parseContractFromString input of
  Left err -> assertFailure $ "Parse failed (need valid parse for type test): " ++ show err
  Right c ->
    case typeCheckContract c of
      Left _  -> return ()
      Right _ -> assertFailure "Expected type error but checking succeeded"

contractTests :: TestTree
contractTests = testGroup "Contract Parsing"
  [ testCase "Simple contract with storage and method" $
      parseSuccess "contract MyContract { storage: { x: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract "MyContract" [( "x", TInt)] [] [MethodDecl Originate "init" [] TInt (SequenceStmt [ReturnStmt (CInt _ 0)])] ->
            return ()
          _ -> assertFailure $ "Unexpected contract structure: " ++ show contract

  , testCase "Contract with multiple storage fields" $
      parseSuccess "contract Test { storage: { x: int, y: int }; @entrypoint test(): int { return 1; } }" $ \contract ->
        case contract of
          Contract "Test" storage _ _ ->
            assertEqual "Storage should have 2 fields" 2 (length storage)
          _ -> assertFailure "Unexpected contract name"

  , testCase "Contract with multiple methods" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 0; } @entrypoint inc(): int { return 1; } }" $ \contract ->
        case contract of
          Contract _ _ _ methods ->
            assertEqual "Should have 2 methods" 2 (length methods)
  ]

storageTests :: TestTree
storageTests = testGroup "Storage Parsing"
  [ testCase "Single storage field" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ [(name, typ)] _ _ -> do
            assertEqual "Storage field name" "x" name
            assertEqual "Storage field type" TInt typ
          _ -> assertFailure "Unexpected storage structure"

  , testCase "Multiple storage fields" $
      parseSuccess "contract Test { storage: { x: int, y: int, z: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ storage _ _ ->
            assertEqual "Should have 3 storage fields" 3 (length storage)

  , testCase "Storage with single field (no comma)" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ storage _ _ ->
            assertEqual "Should have 1 storage field" 1 (length storage)
  ]

methodTests :: TestTree
methodTests = testGroup "Method Parsing"
  [ testCase "Method with @originate decorator" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl Originate "init" [] TInt _] ->
            return ()
          _ -> assertFailure "Expected @originate method"

  , testCase "Method with @entrypoint decorator" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl EntryPoint "test" [] TInt _] ->
            return ()
          _ -> assertFailure "Expected @entrypoint method"

  , testCase "Method with @private decorator" $
      parseSuccess "contract Test { storage: { x: int }; @private helper(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl Private "helper" [] TInt _] ->
            return ()
          _ -> assertFailure "Expected @private method"

  , testCase "Method with parameters" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint add(a: int, b: int): int { return a + b; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl EntryPoint "add" params TInt _] -> do
            assertEqual "Should have 2 parameters" 2 (length params)
            case params of
              [FormalParameter "a" TInt, FormalParameter "b" TInt] ->
                return ()
              _ -> assertFailure "Unexpected parameter structure"
          _ -> assertFailure "Unexpected method structure"

  , testCase "Method with single parameter" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint inc(x: int): int { return x + 1; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ params _ _] ->
            assertEqual "Should have 1 parameter" 1 (length params)
          _ -> assertFailure "Unexpected method structure"

  , testCase "Method with empty parameter list" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ params _ _] ->
            assertEqual "Should have 0 parameters" 0 (length params)
          _ -> assertFailure "Unexpected method structure"
  ]

expressionTests :: TestTree
expressionTests = testGroup "Expression Parsing"
  [ testCase "Integer literal" $
      parseSuccess "contract Test { storage: { x: int }; @originate init(): int { return 42; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (CInt _ 42)])] ->
            return ()
          _ -> assertFailure $ "Expected integer literal 42, got: " ++ show contract

  , testCase "Variable reference" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return x; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (Var _ "x")])] ->
            return ()
          _ -> assertFailure $ "Expected variable reference, got: " ++ show contract

  , testCase "Addition expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 1 + 2; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (Add _ (CInt _ 1) (CInt _ 2))])] ->
            return ()
          _ -> assertFailure $ "Expected addition expression, got: " ++ show contract

  , testCase "Subtraction expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 5 - 3; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (Sub _ (CInt _ 5) (CInt _ 3))])] ->
            return ()
          _ -> assertFailure $ "Expected subtraction expression, got: " ++ show contract

  , testCase "Chained addition" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 1 + 2 + 3; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt expr])] -> do
            -- Should parse as (1 + 2) + 3 due to left associativity
            case expr of
              Add _ (Add _ (CInt _ 1) (CInt _ 2)) (CInt _ 3) ->
                return ()
              _ -> assertFailure $ "Expected left-associative addition, got: " ++ show expr
          _ -> assertFailure $ "Unexpected expression structure: " ++ show contract

  , testCase "Mixed addition and subtraction" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 10 - 2 + 3; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt expr])] -> do
            -- Should parse as (10 - 2) + 3 due to left associativity
            case expr of
              Add _ (Sub _ (CInt _ 10) (CInt _ 2)) (CInt _ 3) ->
                return ()
              _ -> assertFailure $ "Expected left-associative mixed operations, got: " ++ show expr
          _ -> assertFailure $ "Unexpected expression structure: " ++ show contract

  , testCase "Parenthesized expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return (1 + 2); } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (Add _ (CInt _ 1) (CInt _ 2))])] ->
            return ()
          _ -> assertFailure $ "Expected parenthesized addition, got: " ++ show contract

  , testCase "Unit expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return (); } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (Unit _)])] ->
            return ()
          _ -> assertFailure $ "Expected unit expression, got: " ++ show contract

  , testCase "Boolean expression (&&) and boolean type" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint check(): bool { return true && false; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "check" [] TBool (SequenceStmt [ReturnStmt (And _ (CBool _ True) (CBool _ False))])] ->
            return ()
          _ -> assertFailure $ "Expected boolean && expression, got: " ++ show contract

  , testCase "Not expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint notit(): bool { return !false; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "notit" [] TBool (SequenceStmt [ReturnStmt (Not _ (CBool _ False))])] ->
            return ()
          _ -> assertFailure $ "Expected !false, got: " ++ show contract

  , testCase "Relational expression (==)" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint eq(): bool { return 1 == 2; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "eq" [] TBool (SequenceStmt [ReturnStmt (Eq _ (CInt _ 1) (CInt _ 2))])] ->
            return ()
          _ -> assertFailure $ "Expected 1 == 2, got: " ++ show contract

  , testCase "Mul/Div/Mod expressions" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint arith(): int { return 6 * 7; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "arith" [] TInt (SequenceStmt [ReturnStmt (Mul _ (CInt _ 6) (CInt _ 7))])] ->
            return ()
          _ -> assertFailure $ "Expected 6 * 7, got: " ++ show contract

  , testCase "Record type and record literal" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint get(): { a: int, b: bool } { return { a: 1, b: true }; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "get" [] (TRecord [("a", TInt), ("b", TBool)]) (SequenceStmt [ReturnStmt (Record _ [("a", CInt _ 1), ("b", CBool _ True)])])] ->
            return ()
          _ -> assertFailure $ "Expected record type/literal, got: " ++ show contract

  , testCase "Record field access (x.f)" $
      parseSuccess "contract Test { storage: { x: { a: int, b: bool } }; @entrypoint proj(): int { return x.a; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "proj" [] TInt
                (SequenceStmt [ReturnStmt (FieldAccess _ (Var _ "x") "a")])
            ] ->
              return ()
          _ -> assertFailure $ "Expected projection x.a, got: " ++ show contract

  , testCase "Chained field access (x.a.b)" $
      parseSuccess "contract Test { storage: { x: { a: { b: int } } }; @entrypoint proj2(): int { return x.a.b; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "proj2" [] TInt
                (SequenceStmt
                  [ReturnStmt (FieldAccess _ (FieldAccess _ (Var _ "x") "a") "b")])]
            -> return ()
          _ -> assertFailure $ "Expected chained projection x.a.b, got: " ++ show contract

  , testCase "Chained field access on record literal (..a.b)" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint litproj2(): int { return { a: { b: 1 } }.a.b; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "litproj2" [] TInt
                (SequenceStmt
                  [ReturnStmt
                    (FieldAccess _
                      (FieldAccess _
                        (Record _ [("a", Record _ [("b", CInt _ 1)])])
                        "a")
                      "b")])]
            -> return ()
          _ -> assertFailure $ "Expected chained projection on record literal, got: " ++ show contract

  , testCase "Field access on record literal" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint litproj(): int { return { a: 1, b: true }.a; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "litproj" [] TInt
                (SequenceStmt [ReturnStmt (FieldAccess _ (Record _ [("a", CInt _ 1), ("b", CBool _ True)]) "a")])
            ] ->
              return ()
          _ -> assertFailure $ "Expected projection on record literal, got: " ++ show contract
  ]

statementTests :: TestTree
statementTests = testGroup "Statement Parsing"
  [ testCase "Return statement" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { return 42; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [ReturnStmt (CInt _ 42)])] ->
            return ()
          _ -> assertFailure $ "Expected return statement, got: " ++ show contract

  , testCase "Assignment statement" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { x = 10; return x; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [AssignmentStmt (LVar "x") (CInt _ 10), ReturnStmt (Var _ "x")])] ->
            return ()
          _ -> assertFailure "Expected assignment and return statements"

  , testCase "Multiple statements in block" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { x = 1; x = 2; return x; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt stmts)] ->
            assertEqual "Should have 3 statements" 3 (length stmts)
          _ -> assertFailure "Unexpected statement structure"

  , testCase "Assignment with expression" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint test(): int { x = 1 + 2; return x; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ _ _ _ (SequenceStmt [AssignmentStmt (LVar "x") (Add _ (CInt _ 1) (CInt _ 2)), ReturnStmt (Var _ "x")])] ->
            return ()
          _ -> assertFailure "Expected assignment with expression"

  , testCase "If statement with else" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint f(): int { if (true) { return 1; } else { return 2; } } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "f" [] TInt (SequenceStmt [IfStmt (CBool _ True) (SequenceStmt [ReturnStmt (CInt _ 1)]) (Just (SequenceStmt [ReturnStmt (CInt _ 2)]))])] ->
            return ()
          _ -> assertFailure $ "Expected if/else, got: " ++ show contract

  , testCase "While statement" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint loop(): int { while (false) { x = 1; } return x; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl _ "loop" [] TInt (SequenceStmt [WhileStmt (CBool _ False) (SequenceStmt [AssignmentStmt (LVar "x") (CInt _ 1)]) , ReturnStmt (Var _ "x")])] ->
            return ()
          _ -> assertFailure $ "Expected while statement, got: " ++ show contract

  , testCase "Field assignment statement (x.a = ...)" $
      parseSuccess "contract Test { storage: { x: { a: int } }; @entrypoint fa(): int { x.a = 3; return x.a; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [MethodDecl _ "fa" [] TInt
              (SequenceStmt
                [ AssignmentStmt (LField (LVar "x") "a") (CInt _ 3)
                , ReturnStmt (FieldAccess _ (Var _ "x") "a")
                ])] ->
              return ()
          _ -> assertFailure $ "Expected x.a assignment, got: " ++ show contract

  , testCase "Field assignment statement (x.a.b = ...)" $
      parseSuccess "contract Test { storage: { x: { a: { b: int } } }; @entrypoint fab(): int { x.a.b = 3; return x.a.b; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [MethodDecl _ "fab" [] TInt
              (SequenceStmt
                [ AssignmentStmt
                    (LField (LField (LVar "x") "a") "b")
                    (CInt _ 3)
                , ReturnStmt
                    (FieldAccess _ (FieldAccess _ (Var _ "x") "a") "b")
                ])] ->
              return ()
          _ -> assertFailure $ "Expected x.a.b assignment, got: " ++ show contract

  , testCase "Storage expression read (storage.x)" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint sr(): int { return storage.x; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "sr" [] TInt
                (SequenceStmt
                  [ReturnStmt (FieldAccess _ (StorageExpr _) "x")])
            ] ->
              return ()
          _ -> assertFailure $ "Expected storage read, got: " ++ show contract

  , testCase "Storage expression write (storage.x = ...)" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint sw(): int { storage.x = 10; return storage.x; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "sw" [] TInt
                (SequenceStmt
                  [ AssignmentStmt (LField LStorage "x") (CInt _ 10)
                  , ReturnStmt (FieldAccess _ (StorageExpr _) "x")
                  ])
            ] ->
              return ()
          _ -> assertFailure $ "Expected storage write, got: " ++ show contract

  , testCase "Var declaration + assignment to local var" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint v(): int { var y: int = 10; y = 11; return y; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "v" [] TInt
                (SequenceStmt
                  [ VarDeclStmt "y" TInt (CInt _ 10)
                  , AssignmentStmt (LVar "y") (CInt _ 11)
                  , ReturnStmt (Var _ "y")
                  ])
            ] ->
              return ()
          _ -> assertFailure $ "Expected var decl + assignment, got: " ++ show contract

  , testCase "Val declaration + returning local val" $
      parseSuccess "contract Test { storage: { x: int }; @entrypoint c(): int { val y: int = 10; return y; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "c" [] TInt
                (SequenceStmt
                  [ ValDeclStmt "y" TInt (CInt _ 10)
                  , ReturnStmt (Var _ "y")
                  ])
            ] ->
              return ()
          _ -> assertFailure $ "Expected val decl, got: " ++ show contract

  , testCase "Field assignment to local record (x.a = ... but local var)" $
      parseSuccess "contract Test { storage: { x: { a: int } }; @entrypoint fa2(): int { var t: { a: int } = x; t.a = 7; return t.a; } }" $ \contract ->
        case contract of
          Contract _ _
            _ [ MethodDecl _ "fa2" [] TInt
                (SequenceStmt
                  [ VarDeclStmt "t" (TRecord [("a", TInt)]) (Var _ "x")
                  , AssignmentStmt (LField (LVar "t") "a") (CInt _ 7)
                  , ReturnStmt (FieldAccess _ (Var _ "t") "a")
                  ])
            ] ->
              return ()
          _ -> assertFailure $ "Expected local record field assignment, got: " ++ show contract
  ]

-- ---------------------------------------------------------------------------
-- Pair parser tests
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Enum/match/destructuring parser tests
-- ---------------------------------------------------------------------------

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
      parseSuccess "contract T { storage: { x: int }; @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Green => { return (); } } } }" $ \c ->
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

-- ---------------------------------------------------------------------------
-- Pair and enum type checker tests
-- ---------------------------------------------------------------------------

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
      typeCheckSuccess "contract T { storage: { x: int }; enum Color { Red, Green } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Green => { return (); } } } }"

  , testCase "non-exhaustive match fails" $
      typeCheckFailure "contract T { storage: { x: int }; enum Color { Red, Green, Blue } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } } } }"

  , testCase "unknown variant in match fails" $
      typeCheckFailure "contract T { storage: { x: int }; enum Color { Red, Green } @entrypoint f(c: Color): unit { match (c) { Red => { return (); } Purple => { return (); } } } }"

  , testCase "undefined enum in storage fails" $
      typeCheckFailure "contract T { storage: { c: Ghost }; @originate init(): unit { return (); } }"

  , testCase "var destructuring is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): int { var (a, b): pair<int, bool> = p; return a; } }"

  , testCase "val destructuring is well-typed" $
      typeCheckSuccess "contract T { storage: { x: int }; @entrypoint f(p: pair<int, bool>): bool { val (a, b): pair<int, bool> = p; return b; } }"

  , testCase "match on non-enum fails" $
      typeCheckFailure "contract T { storage: { x: int }; @entrypoint f(n: int): unit { match (n) { } } }"
  ]

-- ---------------------------------------------------------------------------
-- Codec tests
-- ---------------------------------------------------------------------------

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

  , testCase "persisted storage decodes against contract storage type" $
      parseSuccess
        "contract C { storage: { n: int, b: bool }; @originate init(): unit { return (); } }"
        $ \c ->
          case contractInstanceFromStorageValue c (object ["n" .= (1 :: Int), "b" .= True]) of
            Left err -> assertFailure err
            Right (ContractInstance _ st) -> case st of
              Record _ [("n", CInt _ 1), ("b", CBool _ True)] -> return ()
              _ -> assertFailure $ "unexpected storage expr: " ++ show st
  ]

-- ---------------------------------------------------------------------------
-- LLTZ code generation tests
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Existing type checker tests (preserved)
-- ---------------------------------------------------------------------------

typeCheckTests :: TestTree
typeCheckTests =
  testGroup
    "Type checker"
    [ testCase "Minimal well-typed contract" $
        typeCheckSuccess
          "contract C { storage: { x: int }; @originate init(): int { return 0; } }"
    , testCase "Return type mismatch" $
        typeCheckFailure
          "contract C { storage: { x: int }; @originate init(): int { return true; } }"
    , testCase "Arithmetic requires int" $
        typeCheckFailure
          "contract C { storage: { x: int }; @originate init(): int { return 1 + true; } }"
    , testCase "Cannot assign to val" $
        typeCheckFailure
          "contract C { storage: { x: int }; @originate init(): int { val v: int = 1; v = 2; return 0; } }"
    , testCase "Equality requires same types" $
        typeCheckFailure
          "contract C { storage: { x: int }; @originate init(): bool { return 1 == true; } }"
    , testCase "If condition must be bool" $
        typeCheckFailure
          "contract C { storage: { x: int }; @originate init(): int { if (1) { return 0; } else { return 1; } } }"
    , testCase "Storage field assignment matches storage type" $
        typeCheckSuccess
          "contract C { storage: { n: int }; @originate init(): unit { storage.n = 3; return (); } }"
    , testCase "Unknown storage field" $
        typeCheckFailure
          "contract C { storage: { n: int }; @originate init(): unit { storage.missing = 1; return (); } }"
    ]

errorTests :: TestTree
errorTests = testGroup "Error Cases"
  [ testCase "Missing contract keyword" $
      parseFailure "MyContract { storage: { x: int }; @originate init(): int { return 0; } }"

  , testCase "Missing storage declaration" $
      parseFailure "contract Test { @originate init(): int { return 0; } }"

  , testCase "Invalid storage syntax" $
      parseFailure "contract Test { storage x: int; @originate init(): int { return 0; } }"

  , testCase "Missing method decorator (defaults to Private)" $
      parseSuccess "contract Test { storage: { x: int }; init(): int { return 0; } }" $ \contract ->
        case contract of
          Contract _ _ _ [MethodDecl Private "init" [] TInt _] ->
            return ()
          _ -> assertFailure "Expected method without decorator to default to Private"

  , testCase "Missing return type" $
      parseFailure "contract Test { storage: { x: int }; @entrypoint test() { return 0; } }"

  , testCase "Missing semicolon after statement" $
      parseFailure "contract Test { storage: { x: int }; @entrypoint test(): int { return 0 } }"

  , testCase "Invalid expression syntax" $
      parseFailure "contract Test { storage: { x: int }; @entrypoint test(): int { return +; } }"
  ]

module SmartTS.CodeGen.CompileLLTZ where

import qualified SmartTS.IR.AST  as A
import qualified SmartTS.IR.LLTZ as L
import qualified Data.Map.Strict as M

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
    [ L.RowLeaf Nothing (translateType env t1)
    , L.RowLeaf Nothing (translateType env t2)
    ])
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
translateExpression _   (A.Unit  _)      = L.Expr (L.Const L.CUnit) L.TUnit
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
-- Storage / field access / call — not yet fully supported
translateExpression _   (A.StorageExpr _) =
  error "CompileLLTZ: StorageExpr translation requires storage threading (not yet implemented)"
translateExpression _   (A.FieldAccess _ _ _) =
  error "CompileLLTZ: FieldAccess translation requires storage threading (not yet implemented)"
translateExpression _   (A.Call _ _ _) =
  error "CompileLLTZ: Call translation not yet implemented"
-- Pair
translateExpression env (A.PairExpr ty e1 e2) =
  L.Expr
    (L.TupleExpr (L.RowNode
      [ L.RowLeaf Nothing (translateExpression env e1)
      , L.RowLeaf Nothing (translateExpression env e2)
      ]))
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
      let (lefts, rest) = break (== variant) vs
          rights    = case rest of { _:rs -> rs; [] -> error $ "CompileLLTZ: variant `" ++ variant ++ "` not in enum `" ++ eName ++ "`" }
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
      let e'     = translateExpression env expr
          pairTy = L.exprType e'
          t1     = elemTypeAt pairTy 0
          t2     = elemTypeAt pairTy 1
          proj0  = L.Expr (L.Proj e' (L.RowPath [0])) t1
          proj1  = L.Expr (L.Proj e' (L.RowPath [1])) t2
          inner  = L.Expr (L.LetMutIn (L.MutVar n2) proj1 block) ty
      in L.Expr (L.LetMutIn (L.MutVar n1) proj0 inner) ty
    A.ValDestructStmt n1 n2 _ty expr ->
      let e'     = translateExpression env expr
          pairTy = L.exprType e'
          t1     = elemTypeAt pairTy 0
          t2     = elemTypeAt pairTy 1
          proj0  = L.Expr (L.Proj e' (L.RowPath [0])) t1
          proj1  = L.Expr (L.Proj e' (L.RowPath [1])) t2
          inner  = L.Expr (L.LetIn (L.Var n2) proj1 block) ty
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
  let cond'  = translateExpression env cond
      body'  = translateStatement env body
  in L.Expr (L.While cond' body') L.TUnit
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
translateStatement _ _ =
  error "CompileLLTZ: unexpected statement in translateStatement (VarDeclStmt/ValDeclStmt/Destruct must go through translateBlock)"

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

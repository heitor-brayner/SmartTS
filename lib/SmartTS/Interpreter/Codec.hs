module SmartTS.Interpreter.Codec where

import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Data.Scientific (floatingOrInteger)
import SmartTS.IR.AST
import SmartTS.Interpreter.Runtime

type EnumRegistry = M.Map Name [Name]

exprToJson :: Expr a -> Value
exprToJson (CInt _ n) = Number (fromIntegral n)
exprToJson (CBool _ b) = Bool b
exprToJson (Record _ fields) =
  Object $
    KM.fromList
      [ (fromStringKey k, exprToJson v)
      | (k, v) <- fields
      ]
exprToJson (Unit _) = Null
exprToJson (PairExpr _ e1 e2) =
  Object $ KM.fromList
    [ (fromStringKey "fst", exprToJson e1)
    , (fromStringKey "snd", exprToJson e2)
    ]
exprToJson (EnumLiteral _ variant) = String (T.pack variant)
exprToJson _ = Null

jsonToExprByType :: EnumRegistry -> Type -> Value -> Either String TypedExpr
jsonToExprByType _ TInt (Number n) =
  case floatingOrInteger n :: Either Double Int of
    Right i -> Right (CInt TInt i)
    Left _  -> Left "Expected integer number for int type."
jsonToExprByType _ TBool (Bool b) = Right (CBool TBool b)
jsonToExprByType enumRegistry (TRecord fieldsT) (Object obj) = do
  pairs <- mapM (decodeField obj) fieldsT
  Right (Record (TRecord fieldsT) pairs)
  where
    decodeField o (fname, ftype) =
      case KM.lookup (fromStringKey fname) o of
        Nothing -> Left $ "Missing record field in JSON args: " ++ fname
        Just v  -> do
          ev <- jsonToExprByType enumRegistry ftype v
          Right (fname, ev)
jsonToExprByType enumRegistry (TPair t1 t2) (Object obj) = do
  v1 <- case KM.lookup (fromStringKey "fst") obj of
    Nothing -> Left "Missing 'fst' field in pair JSON."
    Just v  -> jsonToExprByType enumRegistry t1 v
  v2 <- case KM.lookup (fromStringKey "snd") obj of
    Nothing -> Left "Missing 'snd' field in pair JSON."
    Just v  -> jsonToExprByType enumRegistry t2 v
  Right (PairExpr (TPair t1 t2) v1 v2)
jsonToExprByType enumRegistry t@(TEnum enumTypeName) (String s) =
  let variant = T.unpack s
  in case M.lookup enumTypeName enumRegistry of
    Nothing -> Left $ "Missing definition for enum type `" ++ enumTypeName ++ "`."
    Just variants
      | variant `elem` variants -> Right (EnumLiteral t variant)
      | otherwise -> Left $
          "Unknown variant `" ++ variant ++ "` for enum `" ++ enumTypeName ++ "`."
jsonToExprByType _ _ _ = Left "JSON value does not match the expected SmartTS type."

jsonToExprUntyped :: Value -> Either String ParsedExpr
jsonToExprUntyped (Number n) =
  case floatingOrInteger n :: Either Double Int of
    Right i -> Right (CInt () i)
    Left _  -> Left "Only integer numbers are currently supported."
jsonToExprUntyped (Bool b) = Right (CBool () b)
jsonToExprUntyped Null = Right (Unit ())
jsonToExprUntyped (Object obj) = do
  fields <- mapM decodeKV (KM.toList obj)
  Right (Record () fields)
  where
    decodeKV (k, v) = do
      ev <- jsonToExprUntyped v
      Right (toStringKey k, ev)
jsonToExprUntyped _ = Left "Unsupported JSON value for SmartTS expression."

-- | Decode persisted @storage@ JSON using the contract\'s declared storage record type.
contractInstanceFromStorageValue :: Contract a -> Value -> Either String ContractInstance
contractInstanceFromStorageValue c v = do
  st <- jsonToExprByType (enumRegistryFromContract c) (TRecord (contractStorage c)) v
  Right (ContractInstance (contractName c) st)

bindArgsByName :: EnumRegistry -> [FormalParameter] -> Value -> Either String (M.Map Name TypedExpr)
bindArgsByName enumRegistry params (Object obj) = do
  pairs <- mapM decodeParam params
  Right (M.fromList pairs)
  where
    decodeParam (FormalParameter pname ptype) =
      case KM.lookup (fromStringKey pname) obj of
        Nothing -> Left $ "Missing argument in JSON object: " ++ pname
        Just v  -> do
          e <- jsonToExprByType enumRegistry ptype v
          Right (pname, e)
bindArgsByName _ _ _ = Left "--args must be a JSON object."

enumRegistryFromContract :: Contract a -> EnumRegistry
enumRegistryFromContract c =
  M.fromList [(enumName d, enumVariants d) | d <- contractEnums c]

fromStringKey :: String -> K.Key
fromStringKey = K.fromString

toStringKey :: K.Key -> String
toStringKey = K.toString

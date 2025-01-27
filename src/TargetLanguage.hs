{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
-- | Definition of the target language
module TargetLanguage where

import Data.Vector.Unboxed.Sized as V (map, index, singleton)

import Types as T (lEval,  Type, LFun, Tens, LT(..), RealN
             , eqTy, lComp, lApp, lId, lFst, lSnd, lMap
             , lSwap, singleton, lPair, lCur, lZipWith', lZip
             )
import LanguageTypes ()
import Operation (Operation, LinearOperation, evalOp, evalLOp, showOp, showLOp)
import Data.Type.Equality ((:~:)(Refl))
import GHC.TypeNats (KnownNat)


-- | Terms of the target language
data TTerm t where
    -- Terms from source language
    Var    :: String -> Type a -> TTerm a
    Lambda :: String -> Type a -> TTerm b -> TTerm (a -> b)
    App    :: (LT a, LT b) => TTerm (a -> b) -> TTerm a -> TTerm b
    Unit   :: TTerm ()
    Pair   :: TTerm a -> TTerm b -> TTerm (a, b)
    Fst    :: TTerm (a, b) -> TTerm a
    Snd    :: TTerm (a, b) -> TTerm b
    Lift   :: a -> Type a -> TTerm a
    -- | Operators
    Op     :: Operation a b -> TTerm a -> TTerm b
    Map    :: TTerm (RealN 1 -> RealN 1) -> TTerm (RealN n) -> TTerm (RealN n)

    -- Target language extension

    -- | Linear operation
    LOp       :: LinearOperation a b c -> TTerm (a -> LFun b c)

    -- Linear functions
    LId       :: TTerm (LFun a a)
    LComp     :: (LT a, LT b, LT c) => TTerm (LFun a b) -> TTerm (LFun b c) -> TTerm (LFun a c)
    LApp      :: TTerm (LFun a b) -> TTerm a -> TTerm b
    LEval     :: TTerm a -> TTerm (LFun (a -> b) b)
    -- Tuples
    LFst      :: TTerm (LFun (a, b) a)
    LSnd      :: TTerm (LFun (a, b) b)
    LPair     :: TTerm (LFun a b) -> TTerm (LFun a c) -> TTerm (LFun a (b, c))
    -- | Singleton
    Singleton :: TTerm b -> TTerm (LFun c (Tens b c))
    -- Zero
    Zero      :: LT a => TTerm a
    -- Plus
    Plus      :: LT a => TTerm a -> TTerm a -> TTerm a
    -- Swap
    LSwap     :: TTerm (b -> LFun c d) -> TTerm (LFun c (b -> d))
    -- | Tensor-elimination
    LCur      :: (LT b, LT c, LT d) => TTerm (b -> LFun c d) -> TTerm (LFun (Tens b c) d)
    -- Map derivatives
    DMap      :: KnownNat n => TTerm (RealN 1 -> (RealN 1, LFun (RealN 1) (RealN 1)), RealN n)
              -> TTerm (LFun (RealN 1 -> RealN 1, RealN n) (RealN n))
    DtMap     :: TTerm (RealN 1 -> (RealN 1, LFun (RealN 1) (RealN 1)), RealN n)
              -> TTerm (LFun (RealN n) (Tens (RealN 1) (RealN 1), RealN n))


-- | Substitute variable for term
subst :: String -> u -> Type u -> TTerm t -> TTerm t
subst x v u (Var y t)      | x == y     = case eqTy u t of
                                            Just Refl -> Lift v u
                                            Nothing   -> error "ill-typed substitution"
                           | otherwise  = Var y t
subst x v u (Lambda y t e) | x == y     = Lambda y t e
                           | otherwise  = Lambda y t (subst x v u e)
subst x v u (App f a)                   = App (subst x v u f) (subst x v u a)
subst _ _ _  Unit                       = Unit
subst x v u (Pair a b)                  = Pair (subst x v u a) (subst x v u b)
subst x v u (Fst p)                     = Fst (subst x v u p)
subst x v u (Snd p)                     = Snd (subst x v u p)
subst _ _ _ (Lift x t)                  = Lift x t
subst x v u (Op op y)                   = Op op (subst x v u y)
subst x v u (Map f y)                   = Map (subst x v u f) (subst x v u y)
-- Target language extension
subst _ _ _  LId                        = LId
subst x v u (LComp f g)                 = LComp (subst x v u f) (subst x v u g)
subst x v u (LApp f a)                  = LApp (subst x v u f) (subst x v u a)
subst x v u (LEval t)                   = LEval (subst x v u t)
subst _ _ _  LFst                       = LFst
subst _ _ _  LSnd                       = LSnd
subst x v u (LPair a b)                 = LPair (subst x v u a) (subst x v u b)
subst x v u (Singleton t)               = Singleton (subst x v u t)
subst _ _ _  Zero                       = Zero
subst x v u (Plus a b)                  = Plus (subst x v u a) (subst x v u b)
subst x v u (LSwap t)                   = LSwap (subst x v u t)
subst x v u (LCur t)                    = LCur (subst x v u t)
subst _ _ _ (LOp lop)                   = LOp lop
subst x v u (DMap t)                    = DMap (subst x v u t)
subst x v u (DtMap t)                   = DtMap (subst x v u t)

-- | Substitute variable for a TTerm
substTt :: String -> TTerm u -> Type u -> TTerm t -> TTerm t
substTt x v u (Var y t)      | x == y     = case eqTy u t of
                                              Just Refl -> v
                                              Nothing   -> error "ill-typed substitution"
                             | otherwise  = Var y t
substTt x v u (Lambda y t e) | x == y     = Lambda y t e
                             | otherwise  = Lambda y t (substTt x v u e)
substTt x v u (App f a)                   = App (substTt x v u f) (substTt x v u a)
substTt _ _ _  Unit                       = Unit
substTt x v u (Pair a b)                  = Pair (substTt x v u a) (substTt x v u b)
substTt x v u (Fst p)                     = Fst (substTt x v u p)
substTt x v u (Snd p)                     = Snd (substTt x v u p)
substTt _ _ _ (Lift x t)                  = Lift x t
substTt x v u (Op op y)                   = Op op (substTt x v u y)
substTt x v u (Map f y)                   = Map (substTt x v u f) (substTt x v u y)
-- Target language extension
substTt _ _ _  LId                        = LId
substTt x v u (LComp f g)                 = LComp (substTt x v u f) (substTt x v u g)
substTt x v u (LApp f a)                  = LApp (substTt x v u f) (substTt x v u a)
substTt x v u (LEval t)                   = LEval (substTt x v u t)
substTt _ _ _  LFst                       = LFst
substTt _ _ _  LSnd                       = LSnd
substTt x v u (LPair a b)                 = LPair (substTt x v u a) (substTt x v u b)
substTt x v u (Singleton t)               = Singleton (substTt x v u t)
substTt _ _ _  Zero                       = Zero
substTt x v u (Plus a b)                  = Plus (substTt x v u a) (substTt x v u b)
substTt x v u (LSwap t)                   = LSwap (substTt x v u t)
substTt x v u (LCur t)                    = LCur (substTt x v u t)
substTt _ _ _ (LOp lop)                   = LOp lop
substTt x v u (DMap t)                    = DMap (substTt x v u t)
substTt x v u (DtMap t)                   = DtMap (substTt x v u t)


-- | Evaluate the target language
evalTt :: TTerm t -> t
-- Source language extension
evalTt (Var _ _)         = error "Free variable has no value"
evalTt (Lambda x t e)    = \v -> evalTt $ subst x v t e
evalTt (App f a)         = evalTt f (evalTt a)
evalTt  Unit             = ()
evalTt (Pair a b)        = (evalTt a, evalTt b)
evalTt (Fst p)           = fst $ evalTt p
evalTt (Snd p)           = snd $ evalTt p
evalTt (Lift x _)        = x
evalTt (Op op a)         = evalOp op (evalTt a)
evalTt (Map f x)         = V.map (flip index 0 . evalTt f . V.singleton) (evalTt x)
-- Target language extension
evalTt (LOp lop)     = evalLOp lop
evalTt  LId          = lId
evalTt (LComp f g)   = lComp (evalTt f) (evalTt g)
evalTt (LEval t)     = lEval (evalTt t)
evalTt (LApp f a)    = lApp  (evalTt f) (evalTt a)
evalTt  LFst         = lFst
evalTt  LSnd         = lSnd
evalTt (LPair a b)   = lPair (evalTt a) (evalTt b)
evalTt (Singleton t) = T.singleton (evalTt t)
evalTt  Zero         = zero
evalTt (Plus a b)    = plus (evalTt a) (evalTt b)
evalTt (LSwap t)     = lSwap (evalTt t)
evalTt (LCur  t)     = lCur f
    where f x acc = plus (lApp (evalTt t (fst x)) (snd x)) acc
evalTt (DMap t)      = plus (lComp lFst (lMap v)) (lComp lSnd (lZipWith' (snd . f) v))
    where (f, v) = evalTt t
evalTt (DtMap t)     = lPair (lZip v) (lZipWith' (snd . f) v)
    where (f, v) = evalTt t

-- | Pretty print the target language
printTt :: TTerm t -> String
-- Source language extension
printTt (Var x _)         = x
printTt (Lambda x _ e)    = "\\" ++ x ++ " -> (" ++ printTt e ++ ")"
printTt (App f a)         = printTt f ++ "(" ++ printTt a ++ ")"
printTt  Unit             = "()"
printTt (Pair a b)        = "(" ++ printTt a ++ ", " ++ printTt b ++ ")"
printTt (Fst p)           = "Fst(" ++ printTt p ++ ")"
printTt (Snd p)           = "Snd(" ++ printTt p ++ ")"
printTt (Lift _ _)        = error "Can't print lifted value"
printTt (Op op a)         = "evalOp " ++ showOp op ++ " " ++ printTt a
printTt (Map f a)         = "map (" ++ printTt f ++ ") " ++ printTt a
-- Target language extension
printTt (LOp lop)         = "evalLOp " ++ showLOp lop
printTt  LId              = "lid"
printTt (LComp f g)       = "(" ++ printTt f ++ ";;" ++ printTt g ++ ")"
printTt (LEval e)         = "leval(" ++ printTt e ++ ")"
printTt (LApp f a)        = printTt f ++ "(" ++ printTt a ++ ")"
printTt  LFst             = "lfst"
printTt  LSnd             = "lsnd"
printTt (LPair a b)       = "lpair(" ++ printTt a ++ ", " ++ printTt b ++ ")"
printTt (Singleton t)     = "[(" ++ printTt t ++ ", -)]"
printTt  Zero             = "0"
printTt (Plus a b)        = "(" ++ printTt a ++ ") + (" ++ printTt b ++ ")"
printTt (LSwap t)         = "lswap(" ++ printTt t ++ ")"
printTt (LCur  t)         = "lcur(" ++ printTt t ++ ")"
printTt (DMap t)          = "DMap(" ++ printTt t ++ ")"
printTt (DtMap t)         = "DtMap(" ++ printTt t ++ ")"


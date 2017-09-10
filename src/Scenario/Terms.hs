{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE StandaloneDeriving #-}

module Scenario.Terms
  ( module Scenario.Terms
  , foldFree) where

import           Control.Monad.Free
import Data.Binary


data Term clientTy cmdTy next
  = Command clientTy cmdTy next
  | Wait Int next

deriving instance Functor (Term clientTy cmdTy)

type Program clientTy cmdTy = Free (Term clientTy cmdTy)

command :: clientTy -> cmdTy -> Program clientTy cmdTy ()
command client cmd = liftF (Command client cmd ())

wait :: Int -> Program clientTy cmdTy ()
wait ms = liftF (Wait ms ())


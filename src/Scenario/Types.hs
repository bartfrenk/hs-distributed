{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards            #-}
module Scenario.Types
  ( module Scenario.Types
  , module System.Clock) where

import           Control.Monad.Trans
import           Data.Binary
import           GHC.Generics
import           System.Clock        hiding (getTime)
import qualified System.Clock        as System


newtype Time = Time TimeSpec
  deriving (Eq, Num, Ord, Generic)

instance Show Time where
  show (Time TimeSpec{..}) =
    "Time {sec = " ++ show sec ++ ", nsec = " ++ show nsec ++ "}"

getTime :: MonadIO m => Clock -> m Time
getTime clock = liftIO $ Time <$> System.getTime clock

instance Binary Time where
  put (Time spec) = put (sec spec, nsec spec)
  get = Time . uncurry TimeSpec <$> get


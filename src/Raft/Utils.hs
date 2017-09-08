{-# LANGUAGE FlexibleContexts #-}
module Raft.Utils where

import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Serializable
import           Control.Monad.Trans.Control
import Data.UUID
import           Data.UUID.V4                             (nextRandom)
import qualified System.Timeout                           as T

-- |Wrap a computation to time out and return in case no result is available
-- with n microseconds. Generalizes `System.Timeout.timeout` to any transformer
-- stack based on IO.
timeout :: MonadBaseControl IO m => Int -> m a -> m (Maybe a)
timeout d act = do
  r <- liftBaseWith $ \runInBase -> T.timeout d (runInBase act)
  case r of
    Nothing -> return Nothing
    Just stm -> Just <$> restoreM stm

newtype MessageTag = UUID

sendTagged :: (Serializable a, Serializable b, MonadProcess m)
           => ProcessId -> a -> m MessageTag
sendTagged 

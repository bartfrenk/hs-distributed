{-# LANGUAGE LambdaCase #-}

module Utils.Distributed where

import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Serializable
import           Control.Monad.Catch                      (MonadThrow, throwM)
import           Data.Typeable
import           Data.UUID
import           Data.UUID.V4                             (nextRandom)

-- |Create a parametrized server.
serve :: (Serializable a, Serializable b, MonadProcessBase m) => (a -> m b) -> m ()
serve f =
  controlP $ \runInBase -> receiveWait
    [ match $ \case
        (tag, from, request) -> runInBase $ do
          resp <- f request
          send from (tag :: UUID, resp)
          serve f
    ]

data RPCException = Timeout deriving (Show, Typeable)

instance Exception RPCException

-- |Sends a message to a process and waits for the response. Request is mapped
-- to a response by means of a unique message tag.
rpc :: (Serializable a, Serializable b, MonadProcess m, MonadThrow m)
    => Int -> ProcessId -> a -> m b
rpc timeout to request = do
  from <- getSelfPid
  requestTag <- liftIO nextRandom
  send to (requestTag, from, request)
  say $ "waiting for reply to message " ++ show requestTag
  result <- receiveTimeout timeout
    [ matchIf (tagsMatch requestTag) extractResponse
    ]
  case result of
    Just response -> return response
    Nothing       -> throwM Timeout
  where tagsMatch requestTag (responseTag, _) = responseTag == requestTag
        extractResponse :: (UUID, b) -> Process b
        extractResponse (_, resp) = return resp



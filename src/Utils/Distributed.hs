{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell       #-}

module Utils.Distributed where

import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Serializable
import           Control.Lens                             hiding (from, to)
import           Control.Monad.Catch                      (MonadThrow, throwM)
import           Data.Binary
import           Data.Typeable
import           Data.UUID
import qualified Data.UUID.V4                             as UUID
import           GHC.Generics                             hiding (from, to)
import           Prelude                                  hiding (pred)

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

data RPCException
  = Timeout Tag
  deriving (Show, Typeable)

instance Exception RPCException

type Tag = UUID

data TaggedMessage a = TaggedMessage
  { _sender  :: ProcessId
  , _tag     :: Tag
  , _message :: a
  } deriving (Show, Typeable, Generic)

instance Binary a => Binary (TaggedMessage a)

makeLenses ''TaggedMessage

type RemotePeer = ProcessId

-- |Sends a message to a process and waits for the response. Request is mapped
-- to a response by means of a unique message tag.
rpc :: (Serializable a, Serializable b, MonadProcess m, MonadThrow m)
    => Int -> RemotePeer -> a -> m b
rpc timeout to request = do
  requestTag <- sendTagged to request
  result <- receiveTimeout timeout
    [ matchTag requestTag return
    ]
  case result of
    Just response -> return response
    Nothing       -> throwM $ Timeout requestTag

randomTag :: MonadProcess m => m Tag
randomTag = liftIO UUID.nextRandom

sendTagged :: (Serializable a, MonadProcess m)
           => RemotePeer -> a -> m Tag
sendTagged to msg = do
  from <- getSelfPid
  unique <- randomTag
  send to (from, unique, msg)
  return unique

matchFirstTag :: Serializable a
              => [Tag] -> (Tag -> a -> Process b) -> Match b
matchFirstTag pending handler =
  let p m = m ^. tag `elem` pending
      h m = handler (m ^. tag) (m ^. message)
  in matchIf p h

receiveFrom :: (Serializable a, MonadProcess m)
              => (b -> a -> b) -> b -> [Tag] -> m b
receiveFrom f acc = receiveFromUntil f acc (const False)

-- |Folds over all messages with tags in `pending` in the order in which they
-- are received. Returns when all pending messages have been received, or when
-- 'pred' does not hold for 'acc'.
receiveFromUntil :: (Serializable a, MonadProcess m)
                   => (b -> a -> b) -> b -> (b -> Bool) -> [Tag] -> m b
receiveFromUntil _ acc _ [] = return acc
receiveFromUntil f acc pred pending
  | pred acc = return acc
  | otherwise =
    let h t msg = receiveFromUntil f (f acc msg) pred (filter (/= t) pending)
    in receiveWait [ matchFirstTag pending h ]

matchTag :: Serializable a
         => Tag -> (a -> Process b) -> Match b
matchTag pending handler = matchFirstTag [pending] (const handler)

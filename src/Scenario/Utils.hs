{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# LANGUAGE DeriveGeneric          #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE LambdaCase             #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}
module Scenario.Utils where

import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Serializable
import           Control.Lens                             hiding (from, to)
import           Data.Binary
import           Data.Typeable
import           GHC.Generics                             (Generic)

data TaggedMessage t a = TaggedMessage
  { _sender  :: ProcessId
  , _tag     :: t
  , _message :: a
  } deriving (Show, Typeable, Generic)

instance (Binary t, Binary a) => Binary (TaggedMessage t a)

makeLenses ''TaggedMessage

class MonadTag m t | m -> t where
  nextTag :: m t

sendTagged :: (Serializable t, Serializable a, MonadTag m t, MonadProcess m)
           => ProcessId -> a -> m t
sendTagged to msg = do
  from <- getSelfPid
  tag <- nextTag
  send to (TaggedMessage from tag msg)
  return tag

receiveTagged :: (Serializable t, Eq t, Serializable a, MonadProcess m)
              => Int -> [t] -> m [(t, a)]
receiveTagged dt = receiveFold dt glue []
  where glue acc t a = (t, a):acc

receiveFold :: (Serializable t, Eq t, Serializable a, MonadProcess m)
              => Int -> (b -> t -> a -> b) -> b -> [t] -> m b
receiveFold _ _ acc [] = return acc
receiveFold dt f acc pending =
  let h t msg = receiveFold dt f (f acc t msg) (filter (/= t) pending)
  in do
    resp <- receiveTimeout dt [ matchFirstTag pending h ]
    case resp of
      Just acc' -> return acc'
      Nothing   -> return acc

matchFirstTag :: (Serializable t, Eq t, Serializable a)
              => [t] -> (t -> a -> Process b) -> Match b
matchFirstTag pending handler =
  let p m = m ^. tag `elem` pending
      h m = handler (m ^. tag) (m ^. message)
  in matchIf p h

-- |Wraps a server for tagged message around a function.
serve :: (Serializable a, Serializable b, Serializable t, MonadProcessBase m)
      => (t -> a -> m b) -> m ()
serve f =
  controlP $ \runInBase -> receiveWait
    [ match $ \case
        TaggedMessage from tag request -> runInBase $ do
          resp <- f tag request
          self <- getSelfPid
          send from (TaggedMessage self tag resp)
          serve f
    ]


{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE UndecidableInstances  #-}
module Scenario.Process where

import           BasicPrelude                             hiding (bracket, try, log)
import           Control.Concurrent
import           Control.Distributed.Process.Lifted       hiding (bracket, try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Node
import           Control.Distributed.Process.Serializable
import           Control.Lens                             hiding (from, to)
import           Control.Monad.Catch
import           Control.Monad.Reader
import           Control.Monad.RWS
import           Control.Monad.State                      hiding (State, state)
import           Data.IORef
import qualified Data.Map.Strict                          as Map
import           Network.Transport                        (closeTransport)
import qualified Network.Transport.TCP                    as TCP

import           Scenario.Terms

import           Scenario.Utils

data Settings out = Settings
  { _agentProcess :: Process ()
  , _timeout      :: Int
  , _log          :: IORef [(Int, out)]
  }

makeLenses ''Settings

mkSettings :: Process () -> IO (Settings out)
mkSettings agentProcess = do
  empty <- newIORef []
  return Settings
    { _timeout = 500000
    , _agentProcess = agentProcess
    , _log = empty
    }


type AgentIndex = Int

data State = State
  { _agents     :: Map AgentIndex ProcessId
  , _messageTag :: Int
  , _pending    :: [Int]
  }

makeLenses ''State

initialState :: State
initialState = State Map.empty 1 []

instance MonadState State m => MonadTag m Int where
  nextTag = do
    tag <- use messageTag
    messageTag += 1
    return tag

type MonadMaster out m =
  ( MonadProcess m
  , MonadState State m
  , MonadReader (Settings out) m
  , MonadProcessBase m)

interpretF :: (MonadMaster out m, Serializable out, Serializable c)
           => Term AgentIndex c a -> m a
interpretF (Wait ms next) =
  liftIO $ threadDelay (ms * 1000) >> return next
interpretF (Command agent cmd next) = do
  sendCommand agent cmd
  tags <- use pending
  dt <- view timeout
  reports <- receiveTagged dt tags
  current <- view log
  liftIO $ modifyIORef current (++ reports)
  return next

sendCommand :: (MonadMaster out m, Serializable c)
            => AgentIndex -> c -> m ()
sendCommand agent cmd = do
  to <- getAgentProcessId agent
  tag <- sendTagged to cmd
  pending %= (tag:)

getAgentProcessId :: MonadMaster out m => AgentIndex -> m ProcessId
getAgentProcessId agent = do
  pid' <- Map.lookup agent <$> use agents
  case pid' of
    Just pid -> return pid
    Nothing -> do
      process <- view agentProcess
      pid <- spawnLocal (liftP process)
      agents %= Map.insert agent pid
      return pid

logF :: (MonadMaster out m, Show c)
     => Term AgentIndex c a -> m ()
logF (Wait ms _) =
  say $ "waiting for " ++ show ms ++ " ms"
logF (Command agent cmd _) =
  say $ show agent ++ ": " ++ show cmd

interpret :: (MonadMaster out m, Serializable out, Serializable c, Show c)
          => Program AgentIndex c a -> m a
interpret = foldFree $ \term -> logF term >> interpretF term

data Agent r c out = Agent
  { resource :: IO r
  , handler :: r -> Int -> c -> Process out
  }

exec :: (Serializable out, Serializable c, Show c)
     => Agent r c out -> Program AgentIndex c () -> IO [(AgentIndex, out)]
exec agent = exec' (run agent)
  where run agent = do
          res <- liftIO $ resource agent
          serve $ handler agent res

exec' :: (Serializable out, Serializable c, Show c)
      => Process () -> Program AgentIndex c () -> IO [(Int, out)]
exec' agentProcess program =
  bracket (createTransport "localhost" "4444") closeTransport $ \transport -> do
    node <- newLocalNode transport initRemoteTable
    settings <- liftIO $ mkSettings agentProcess
    runProcess node $ start program settings initialState
    readIORef $ settings ^. log

  where start program = runMaster (interpret program)

        createTransport host service = do
          result <- liftIO $ TCP.createTransport host service TCP.defaultTCPParameters
          case result of
            Left err        -> throwM err
            Right transport -> return transport

        runMaster act settings = evalStateT (runReaderT act settings)

{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
module Scenario.Process where

import           BasicPrelude                             hiding (bracket, try)
import           Control.Concurrent
import           Control.Distributed.Process.Lifted       hiding (bracket, try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Node
import           Control.Distributed.Process.Serializable
import           Control.Lens                             hiding (from, to)
import           Control.Monad.Catch
import           Control.Monad.Reader
import           Control.Monad.State                      hiding (state)
import           Data.Binary
import qualified Data.Map.Strict                          as Map
import           Database.HDBC.PostgreSQL
import           GHC.Generics                             hiding (from, to)

import           Network.Socket                           (HostName,
                                                           ServiceName)
import           Network.Transport                        (Transport,
                                                           closeTransport)
import qualified Network.Transport.TCP                    as TCP

import           Scenario.PostgreSQL                      (SQL, runSQL)
import           Scenario.Terms
import           Utils.Distributed


data Settings = Settings
  { _connStr :: String
  , _timeout :: Int
  }

makeLenses ''Settings

data MasterState clientTy = MasterState
  { _clients :: Map clientTy ProcessId
  }

makeLenses ''MasterState

type MonadMaster clientTy m =
  ( MonadProcess m
  , MonadState (MasterState clientTy) m
  , MonadReader Settings m
  , MonadProcessBase m
  , MonadCatch m)

type MonadClient m =
  ( MonadProcess m
  , MonadReader Settings m
  , MonadProcessBase m)

data Result
  = Success Int
  | Failure String
  deriving (Generic, Typeable, Show)

instance Binary Result

startClient :: (MonadClient m, Show clientTy) => clientTy -> m ()
startClient _ = do
  conn <- liftIO . connectPostgreSQL' =<< view connStr
  serve $ \cmd -> do
    res <- liftIO $ try (runSQL conn cmd)
    case res of
      Left exc -> return $ Failure (show (exc :: SomeException))
      Right _  -> return $ Success (0 :: Int)

-- TODO: do not throw on timeout
interpretF :: (MonadMaster clientTy m, Ord clientTy, Serializable cmdTy,
               Show clientTy)
           => Term clientTy cmdTy a -> m a
interpretF (Wait ms next) =
  liftIO $ threadDelay (ms * 1000) >> return next
interpretF (Command client cmd next) = do
  to <- getClientProcessId client
  report <- execCommand to cmd
  say $ show report
  return next

sayF :: (MonadMaster clientTy m, Show cmdTy, Show clientTy)
     => Term clientTy cmdTy a -> m ()
sayF (Wait ms _) =
  say $ "waiting for " ++ show ms ++ " ms"
sayF (Command client cmd _) =
  say $ show client ++ ": " ++ show cmd

interpret :: (MonadMaster clientTy m,
              Show cmdTy, Show clientTy,
              Ord clientTy, Serializable cmdTy)
          => Program clientTy cmdTy a -> m a
interpret = foldFree $ \term -> sayF term >> interpretF term

data ExecResult
  = Report Result
  | Pending Tag
  deriving (Show)

execCommand :: (MonadMaster clientTy m, Serializable cmdTy, MonadCatch m)
            => ProcessId -> cmdTy -> m ExecResult
execCommand pid cmd = do
  t <- view timeout
  response <- try $ rpc t pid cmd
  case response of
    Left (Timeout tag) -> return $ Pending tag
    Right res          -> return $ Report res

getClientProcessId :: (MonadMaster clientTy m, Ord clientTy, Show clientTy)
                   => clientTy -> m ProcessId
getClientProcessId client = do
  pid' <- Map.lookup client <$> use clients
  case pid' of
    Just pid -> return pid
    Nothing -> do
      pid <- spawnLocal $ startClient client
      clients %= Map.insert client pid
      return pid

runMaster :: ReaderT Settings (StateT (MasterState Int) Process) a
          -> Settings -> MasterState Int -> Process a
runMaster act settings = evalStateT (runReaderT act settings)

start :: (Program Int SQL (), Settings, MasterState Int) -> Process ()
start (program, settings, state) = runMaster (interpret program) settings state

createTransport :: (MonadIO m, MonadThrow m) => HostName -> ServiceName -> m Transport
createTransport host service = do
  result <- liftIO $ TCP.createTransport host service TCP.defaultTCPParameters
  case result of
    Left err        -> throwM err
    Right transport -> return transport



exec :: Program Int SQL () -> IO ()
exec program =
  bracket (createTransport "localhost" "4444") closeTransport $ \transport -> do
    node <- newLocalNode transport initRemoteTable
    runProcess node $ start (program, defaultSettings, MasterState Map.empty)

defaultSettings :: Settings
defaultSettings = Settings
  { _connStr = "postgresql://docker:docker@localhost:15432/docker"
  , _timeout = 1000000
  }


programA :: Program Int SQL ()
programA = do
  command 1 "begin transaction isolation level read committed"
  command 2 "begin transaction isolation level repeatable read"
  command 1 "update person set name = 'A'"
  command 2 "update person set name = 'B'" -- blocks to avoid a dirty write, but
                                           -- continues after A's commit; find
                                           -- some way to make this happen
                                           -- (async, Process?)
  command 1 "commit"
  command 2 "commit"


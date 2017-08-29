{-# LANGUAGE ConstraintKinds  #-}
{-# LANGUAGE DeriveGeneric    #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StrictData       #-}
{-# LANGUAGE TemplateHaskell  #-}

module GFS.Master.Impl.Server where

import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Monad.Reader
import           Control.Monad.State                      hiding (State)
import           Data.Binary
import           Data.Typeable
import           GHC.Generics                             (Generic)

import           Utils.Distributed                        (serve)

import           GFS.Master.Impl.Types

-- DEBUG
import           Data.ByteString.Char8                    (pack)

-- Needs mechanisms for:
-- 1. chunk placement (creation),
-- 2. rereplication when the replication count falls below the threshold
-- 3. rebalance chunks to optimize disk space and load balancing
-- 4. stale replica detection: master keeps version number
--
-- Master replication
-- 1. state replicated for reliability
-- 2. mutations to the state are fully synchronous

-- | The master stores three major types of metadata: the file and chunk
-- namespaces, the mapping from files to chunks, and the locations of each
-- chunk’s replicas.
--
-- The first two types (namespaces and file-to-chunk mapping) are also kept
-- persistent by logging mutations to an operation log stored on the master’s
-- local disk and replicated on remote machines. (Section 2.6)
--
--   namespaces       :: [String]
-- , associatedChunks :: Map FilePath [ChunkHandle]
-- -- |Maps chunk handles to addresses of the replicas containing the chunk, and
-- -- the reference count of the chunk (see 3.4).
-- , chunkData        :: Map ChunkHandle ([Addr], Int)
-- -- TODO: how to mimic read and write locks in Haskell?
-- , locks            :: Map (FilePath, Operation) (MVar ())
--
data State = State
  { count :: Int
  } deriving (Generic, Typeable)

instance Binary State

data Config = Config {} deriving (Generic, Typeable)

instance Binary Config

type MasterProcess = ReaderT Config (StateT State Process)

type MonadMaster m = (MonadReader Config m, MonadState State m, MonadProcess m)

runMaster :: MasterProcess a -> State -> Config -> Process a
runMaster act st opt = evalStateT (runReaderT act opt) st

master :: MasterProcess ()
master = do
  say "starting master"
  serve process
  say "exiting master"

start :: (Config, State) -> Process ()
start (config, state) = runMaster master state config

process :: MonadMaster m => Request -> m Response
process (GetChunkHandles path index) = do
  gets count >>= say . show
  modify (\st -> st { count = 1 + count st })
  return $ GetChunkHandlesResp (pack path) []

-- do you also need this if start is never invoked remotely?
remotable ['start]


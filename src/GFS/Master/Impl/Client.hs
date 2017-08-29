{-# LANGUAGE RecordWildCards #-}
module GFS.Master.Impl.Client where

import Control.Distributed.Process

import Utils.Distributed

import GFS.Master.Impl.Types
import GFS.Master


data Config = Config
  { masterAddress :: ProcessId
  , timeout       :: Int
  }


newHandle :: Config -> Handle Process ProcessId
newHandle Config{..} = Handle
  { getChunkHandles = \path index -> do
      resp <- rpc timeout masterAddress $ GetChunkHandles path index
      case resp of
        GetChunkHandlesResp h pids -> return (h, pids)
  }

{-# LANGUAGE DeriveGeneric #-}
module GFS.Master.Impl.Types where

import           Control.Distributed.Process
import           Data.Binary
import           Data.Typeable
import           GHC.Generics

import           GFS.Types

data Request
  = GetChunkHandles FilePath Int
  deriving (Generic, Show, Typeable)

instance Binary Request

data Response
  = GetChunkHandlesResp ChunkHandle [ProcessId]
  deriving (Generic, Show, Typeable)

instance Binary Response


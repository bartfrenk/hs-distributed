{-# LANGUAGE NoImplicitPrelude #-}
module GFS.ChunkServer where

import BasicPrelude

import GFS.Types

data Lease = Lease
  { serialNumber :: Int }

data ChunkServerState = ChunkServerState
  { chunkServerLeases :: Map ChunkHandle Lease
  , chunks :: [ChunkHandle]
  }

data Handle = Handle
  {
  }

-- chunk broken into 64K blocks that are independently checksummed with a 32 bit
-- checksum.
-- also store chunk version

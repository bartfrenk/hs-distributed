module GFS.Master (Handle(..)) where

import GFS.Types


data Handle m addr = Handle
  { getChunkHandles :: FilePath -> Int -> m (ChunkHandle, [addr])
  }




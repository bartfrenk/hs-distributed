{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}

module GFS.Client where

import           BasicPrelude
import           Control.Monad.Catch
import           Control.Monad.Reader

import GFS.Types
import qualified GFS.Master as Master
import qualified GFS.ChunkServer as ChunkServer

data Handle = Handle
  { config :: Config
  }

withHandle :: Config
           -> Master.Handle m addr
           -> ChunkServer.Handle
           -> (Handle -> m a)
           -> m a
withHandle = undefined

data Config = Config
  { chunkSize  :: Int
  , masterAddr :: Addr
  }

type ClientMonad m = (MonadThrow m, MonadIO m, MonadReader Config m)
-- |Computes the index of the chunk containing the offset.
computeChunkIndices :: MonadReader Config m => (Int, Int) -> m [ChunkIndex]
computeChunkIndices offset = undefined

-- |Contacts the master to return the chunk handle and the replicas for the
-- chunk of the specified file at specified index. The first replica in the list
-- of addresses is the primary.
getChunkHandle :: ClientMonad m => FilePath -> ChunkIndex -> m (ChunkHandle, [Addr])
getChunkHandle = undefined

fetchChunk :: ClientMonad m => Addr -> ChunkHandle -> m ByteString
fetchChunk addr handle = undefined

-- Should throw when presented with an empty list
selectReplica :: MonadThrow m => [Addr] -> m Addr
selectReplica [] = undefined

read :: ClientMonad m => FilePath -> (Int, Int) -> m ByteString
read path range = do
  indices <- computeChunkIndices range
  concat <$> forM indices readChunk
  where readChunk index = do
          (h, addrs) <- getChunkHandle path index
          addr <- selectReplica addrs
          fetchChunk addr h


create :: ClientMonad m => FilePath -> ByteString -> m ()
create = undefined

delete :: ClientMonad m => FilePath -> m ()
delete = undefined

close :: ClientMonad m => FilePath -> m ()
close = undefined

write :: ClientMonad m => FilePath -> Int -> ByteString -> m ()
write = undefined

snapshot :: ClientMonad m => FilePath -> m ()
snapshot = undefined

append :: ClientMonad m => FilePath -> ByteString -> m ()
append = undefined

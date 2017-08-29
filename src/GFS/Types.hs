{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE NoImplicitPrelude #-}

module GFS.Types where

import           BasicPrelude

type Addr = String

type ChunkIndex = Int

type ChunkHandle = ByteString

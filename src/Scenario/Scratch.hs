{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TemplateHaskell       #-}

module Scenario.Scratch where

import           BasicPrelude
import           Control.Concurrent
import           Control.Lens
import           Control.Monad.Free
import           Control.Monad.State
import qualified Data.Map.Strict          as Map
import           Database.HDBC
import           Database.HDBC.PostgreSQL

-- Language

data Term clientTy cmdTy next
  = Command clientTy cmdTy next
  | Wait Int next

deriving instance Functor (Term clientTy cmdTy)

type Program clientTy cmdTy = Free (Term clientTy cmdTy)

command :: clientTy -> cmdTy -> Program clientTy cmdTy ()
command client cmd = liftF (Command client cmd ())

wait :: Int -> Program clientTy cmdTy ()
wait ms = liftF (Wait ms ())

-- Interpreter

data Environment clientTy connTy = Environment
  { _sessions         :: Map clientTy connTy
  , _connectionString :: String
  }

makeLenses ''Environment

mkEnvironment :: String -> Environment clientTy connTy
mkEnvironment connString = Environment
  { _sessions = Map.empty
  , _connectionString = connString
  }

newtype SQL = SQL String

instance IsString SQL where
  fromString = SQL

instance Show SQL where
  show (SQL sql) = sql

type MonadEnv clientTy connTy m =
  (MonadState (Environment clientTy connTy) m,
   MonadIO m)

interpretF :: (Ord clientTy, Show clientTy, MonadEnv clientTy Connection m)
          => Term clientTy SQL a -> m a
interpretF (Wait ms next) = do
  liftIO $ threadDelay (1000 * ms)
  return next
interpretF (Command client sql next) = do
  conn <- getConnection client
  liftIO $ runSQL conn sql
  return next

runSQL :: IConnection conn => conn -> SQL -> IO ()
runSQL c (SQL sql) = runRaw c sql

logF :: (Show cmdTy, Show clientTy, MonadIO m) => Term clientTy cmdTy a -> m ()
logF (Wait ms _) =
  putStrLn $ "waiting for " <> tshow ms <> " ms"
logF (Command client cmd _) =
  putStrLn $ tshow client <> " : " <> tshow cmd

interpret :: (Ord clientTy, Show clientTy, MonadEnv clientTy Connection m)
          => Program clientTy SQL a -> m a
interpret = foldFree $ \term -> logF term >> interpretF term

getConnection :: (Ord clientTy, Show clientTy, MonadEnv clientTy Connection m)
              => clientTy -> m Connection
getConnection client = do
  conn' <- Map.lookup client <$> use sessions
  case conn' of
    Just conn -> return conn
    Nothing -> do
      conn <- liftIO . connectPostgreSQL' =<< use connectionString
      sessions %= Map.insert client conn
      return conn

data Client = A | B | C deriving (Eq, Ord, Show)

docker :: String
docker = "postgresql://docker:docker@localhost:15432/docker"

{-# ANN module ("HLint: ignore Reduce duplication" :: String) #-}

program1 :: Program Client SQL ()
program1 = do
  command A "begin transaction isolation level read committed"
  command B "begin transaction isolation level read committed"
  command A "update person set name = 'A'"
  command B "update person set name = 'B'" -- blocks to avoid a dirty write, but
                                           -- continues after A's commit; find
                                           -- some way to make this happen
                                           -- (async, Process?)
  command A "commit"
  command B "commit"

program2 :: Program Client SQL ()
program2 = do
  command C "truncate table person"
  command C "insert into person values ('C')"
  command A "begin transaction isolation level read committed"
  command B "begin transaction \
            \isolation level repeatable read"
  command A "update person set name = 'A'"
  command B "select * from person"
  command A "commit"
  command B "update person set name = 'B'"
  command B "commit"

program4 :: Program Client SQL ()
program4 = do
  command C "truncate table person"
  command C "insert into person values ('C')"
  command A "begin transaction isolation level read committed"
  command B "begin transaction \
            \isolation level repeatable read"
  command A "update person set name = 'A'"
  command B "select * from person"
  command B "update person set name = 'B'"
  command A "commit"
  command B "commit"



program3 :: Program Client SQL ()
program3 = do
  command C "truncate table person"
  command C "insert into person values ('C')"
  command A "begin transaction isolation level read committed"
  command B "begin transaction isolation level read committed"
  command A "update person set name = 'A'"
  command B "select * from person"
  command A "commit"
  command B "update person set name = 'B'"
  command B "commit"


runProgram :: (Ord clientTy, Show clientTy)
           => String -> Program clientTy SQL a -> IO a
runProgram connString program =
  evalStateT (interpret program) (mkEnvironment connString)

test :: (Ord clientTy, Show clientTy)
     => Program clientTy SQL a -> IO a
test = runProgram docker

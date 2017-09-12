{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Scenario.SQL where

import           BasicPrelude
import           Control.Distributed.Process hiding (try)
import           Data.Binary
import           Database.HDBC
import           Database.HDBC.PostgreSQL
import           GHC.Generics                (Generic)
import           Scenario.Process            (Agent (..), exec)
import           Scenario.Terms
import           Scenario.Utils
import           System.Clock
import           System.Microtimer

newtype SQL = SQL String deriving (Typeable, Generic)

instance Binary SQL

instance IsString SQL where
  fromString = SQL

instance Show SQL where
  show (SQL sql) = sql

runSQL :: IConnection conn => conn -> SQL -> IO ()
runSQL c (SQL sql) = runRaw c sql

docker :: String
docker = "postgresql://docker:docker@localhost:15432/docker"

data Result
  = Success Double
  | Failure Double String
  deriving (Generic, Typeable, Show)

instance Binary Result

agentSQL :: String -> Agent Connection SQL Result
agentSQL connStr = Agent
  { resource = connectPostgreSQL' connStr
  , handler = \conn _ cmd -> do
      start <- liftIO $ getTime Monotonic
      say $ show start
      (dt, res) <- liftIO $ time $ try (runSQL conn cmd)
      stop <- liftIO $ getTime Monotonic
      say $ show stop
      case res of
        Left exc -> return $ Failure (dt * 1000) (show (exc :: SomeException))
        Right _  -> return $ Success (dt * 1000)
  }

programA :: Program Int SQL ()
programA = do
  command 1 "begin transaction isolation level read committed"
  command 2 "begin transaction isolation level repeatable read"
  command 1 "update person set name = 'A'"
  command 2 "update person set name = 'B'"
  command 1 "abort"
  command 2 "commit"

test :: IO [(Int, Result)]
test = exec (agentSQL docker) programA

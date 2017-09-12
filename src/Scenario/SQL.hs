{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
module Scenario.SQL where

import           BasicPrelude
import           Data.Binary
import           Database.HDBC
import           Database.HDBC.PostgreSQL
import           GHC.Generics             (Generic)
import           System.Microtimer


import           Scenario.Process         (Agent (..), exec)
import           Scenario.Terms
import           Scenario.Types

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
  = Success Time Time
  | Failure Time Time DatabaseError
  deriving (Generic, Typeable, Show)

newtype DatabaseError = DatabaseError SqlError
  deriving (Eq, Show)

instance Binary DatabaseError where
  put (DatabaseError err) =
    put (seState err, seNativeError err, seErrorMsg err)
  get = DatabaseError . uncurry3 SqlError <$> get
    where uncurry3 f (x, y, z) = f x y z

instance Binary Result

agentSQL :: String -> Agent Connection SQL Result
agentSQL connStr = Agent
  { resource = connectPostgreSQL' connStr
  , handler = \conn _ cmd -> do
      start <- getTime Monotonic
      (_, res) <- liftIO $ time $ try (runSQL conn cmd) -- force evaluation
      end <- getTime Monotonic
      case res of
        Left exc -> return $ Failure start end (DatabaseError exc)
        Right _  -> return $ Success start end
  }

programA :: Program Int SQL ()
programA = do
  command 1 "begin transaction isolation level read committed"
  command 2 "begin transaction isolation level repeatable read"
  command 1 "update person set name = 'A'"
  command 2 "update person set name = 'B'"
  command 1 "commit"
  command 2 "commit"

test :: IO [(Int, Result)]
test = exec (agentSQL docker) programA

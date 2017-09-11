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
import           Scenario.Process            (exec, Result(..))
import           Scenario.Terms
import           Scenario.Utils

newtype SQL = SQL String deriving (Typeable, Generic)

instance Binary SQL

instance IsString SQL where
  fromString = SQL

instance Show SQL where
  show (SQL sql) = sql

runSQL :: IConnection conn => conn -> SQL -> IO ()
runSQL c (SQL sql) = runRaw c sql

startAgentSQL :: String -> Process ()
startAgentSQL connStr = do
  conn <- liftIO $ connectPostgreSQL' connStr
  serve $ handler conn
  where handler :: IConnection conn => conn -> Int -> SQL -> Process Result
        handler conn _ cmd = do
          res <- liftIO $ try (runSQL conn cmd)
          case res of
            Left exc -> return $ Failure (show (exc :: SomeException))
            Right _  -> return $ Success (0 :: Int)


docker :: String
docker = "postgresql://docker:docker@localhost:15432/docker"


programA :: Program Int SQL ()
programA = do
  command 1 "begin transaction isolation level read committed"
  command 2 "begin transaction isolation level repeatable read"
  command 1 "update person set name = 'A'"
  command 2 "update person set name = 'B'" -- blocks to avoid a dirty write, but
                                           -- continues after A's commit; find
                                           -- some way to make this happen
                                           -- (async, Process?)
  command 1 "commit"
  command 2 "commit"

test :: IO ()
test = exec (startAgentSQL docker) programA

{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell    #-}
module GFS.Scratch where


import           Control.Concurrent                       (threadDelay)
import           Control.Distributed.Process              hiding (Message)
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node
import           Control.Distributed.Process.Serializable
import           Data.Binary
import           Data.Typeable                            (Typeable)
import           Data.UUID
import           Data.UUID.V4                             (nextRandom)
import           GHC.Generics                             (Generic)
import           Network.Transport (closeTransport)
import           Network.Transport.TCP                    (createTransport,
                                                           defaultTCPParameters)

data Message = Ping ProcessId
             | Pong ProcessId
             deriving (Typeable, Generic)

instance Binary Message


data TestMessage = Hello deriving (Typeable, Generic, Show)

instance Binary TestMessage

data Request a = Request ProcessId UUID a deriving (Typeable, Generic)

deriving instance Typeable a => Typeable (Request a)

deriving instance Typeable a => Typeable (Response a)

data Response a = Response UUID a deriving (Typeable, Generic)

instance Binary a => Binary (Request a) where
  put (Request pid uuid a) = put (pid, uuid, a)
  get = do
    (pid, uuid, a) <- get
    return $ Request pid uuid a

instance Binary a => Binary (Response a)

rpc :: (Serializable a, Serializable b) => ProcessId -> a -> Process b
rpc receiver msg = do
  self <- getSelfPid
  uuid <- liftIO nextRandom
  send receiver $ Request self uuid msg
  expect

noop :: Process ()
noop = return ()

rpcServer :: (Typeable a, Binary a) => Process a
rpcServer = do
  say "starting RPC server"
  Request sender uuid msg <- expect
  send sender $ Response uuid msg
  return msg

pingServer :: Process ()
pingServer = do
  say "spawning..."
  Ping from <- expect
  say $ "ping received from %s" ++ show from
  mypid <- getSelfPid
  send from (Pong mypid)

data ArithMessage
  = Add ProcessId Int Int
  | Mul ProcessId Int Int
  deriving (Typeable, Generic, Show)

instance Binary ArithMessage

data ArithResponse
  = ArithResponse Int deriving (Typeable, Generic)

instance Binary ArithResponse

arithServer :: Process ()
arithServer = do
  say "entering arithServer loop"
  receiveWait
    [ match $ \msg -> case msg of
                Add pid x y -> do
                  say $ show x ++ " + " ++ show y
                  send pid $ ArithResponse (x + y)
                  arithServer
                Mul pid x y -> do
                  say $ show x ++ " * " ++ show y
                  send pid $ ArithResponse (x * y)
                  arithServer
    , match $ \Hello -> say "hello"
    ]

remotable ['pingServer, 'noop, 'arithServer]

client :: Process ()
client = do
  node <- getSelfNode
  pid <- spawn node $(mkStaticClosure 'arithServer)
  us <- getSelfPid
  request pid (Add us 3 3)
  request pid (Mul us 3 3)
  request pid Hello
  --exit pid ("exit requested" :: String)
  where
    request pid msg = do
      say $ "sending message '" ++ show msg ++ "' to " ++ show pid
      send pid msg
      say "expecting reply..."
      resp <- expectTimeout 1000000
      case resp of
        Just (ArithResponse n) -> say $ "received reply " ++ show n
        Nothing -> say "timeout"

master :: Process ()
master = do
  node <- getSelfNode

  say $ "spawning on " ++ show node
  pid <- spawn node $(mkStaticClosure 'pingServer)

  mypid <- getSelfPid
  say $ "sending ping to " ++ show pid
  send pid (Ping mypid)

  Pong _ <- expect
  say "pong."

  liftIO $ threadDelay 1000000


run :: IO ()
run = do
  res <- createTransport defaultHost defaultPort defaultTCPParameters
  case res of
    Right t -> do
      node <- newLocalNode t (GFS.Scratch.__remoteTable initRemoteTable)
      _ <- runProcess node client
      closeTransport t
    Left err -> print err

defaultHost :: String
defaultHost = "localhost"

defaultPort :: String
defaultPort = "4444"

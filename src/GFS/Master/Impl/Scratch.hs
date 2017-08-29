module GFS.Master.Impl.Scratch where

import           Control.Distributed.Process.Lifted hiding (bracket)
import           Control.Distributed.Process.Node
import           Control.Monad.Catch
import           Control.Monad.Except
import           Network.Socket                     (HostName, ServiceName)
import           Network.Transport                  (Transport, closeTransport)
import qualified Network.Transport.TCP              as TCP

import           GFS.Master.Impl.Client             as Client
import           GFS.Master.Impl.Server             as Server

createTransport :: (MonadIO m, MonadThrow m) => HostName -> ServiceName -> m Transport
createTransport host service = do
  result <- liftIO $ TCP.createTransport host service TCP.defaultTCPParameters
  case result of
    Left err -> throwM err
    Right transport -> return transport

main :: IO ()
main = testMaster' "localhost" "4444"

testMaster' :: HostName -> ServiceName -> IO ()
testMaster' host service =
  bracket (createTransport host service) closeTransport $ \transport -> do
    node <- newLocalNode transport (Server.__remoteTable initRemoteTable)
    runProcess node $ do
      pid <- spawnLocal $ Server.start (Server.Config, Server.State 0)
      let api = newHandle (Client.Config pid 1000000)
      getChunkHandles api "/tmp" 10 >>= say . show
      getChunkHandles api "/tmp" 10 >>= say . show

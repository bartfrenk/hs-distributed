{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}

module Raft.Server where

import           BasicPrelude
import           Control.Distributed.Process.Lifted       hiding (try)
import           Control.Distributed.Process.Lifted.Class
import           Control.Distributed.Process.Serializable
import           Control.Lens
import           Control.Lens.TH
import Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Data.Binary
import           GHC.Generics
import Utils.Distributed

import qualified System.Timeout                           as T

{--

Questions:
Q. what is a term?

A. Time is divided into terms of arbitrary length. Terms are numbered with
consecutive integers. Each term begins with an election. Raft ensures that there
is at most one leader in a given term. Terms act as a logical clock, and they
allow servers to detect absolete information such as stale leaders.

Guarantees:
1. election safety: at most one leader can be elected in a given
term

2. leader append-only: a leader never overwrites or deletes entries in its log;
it only appends new entries.

3. log matching: if two logs contains an entry with the same index and term,
then the logs are identical in all entries up through the given index.

4. leader completeness: if a log entry is committed in a given term, then that
entry will be present in the logs of the leaders for all higher-numbered terms.

5. state-machine safety: if a server has applied a log entry at a given index to
its state machine, no other server will ever apply a different log entry for the
same index.

--}

testElectionSafety :: Eq cmd => [ServerState addr cmd] -> Term -> Bool
testElectionSafety = undefined


type CandidateID = Int

-- |Type variable is the type of commands for the replicated state machine.  The
-- leader decided when it is safe to apply a log entry to the state machine;
-- such an entry is called committed. Raft guarantees that committed entries are
-- durable and will eventually be executed by all of the available state machines.
--
-- A log entry is committed once the leader that created the entry has
-- replicated it on a majority of the servers. This also commits all preceding
-- entries in the leader's log, including entries created by previous leaders.
data LogEntry cmd = LogEntry Term cmd deriving (Generic, Show, Typeable)

instance Binary cmd => Binary (LogEntry cmd)

newtype LogEntryIndex = LogEntryIndex { getLogEntryIndex :: Int }

type LogIndex = Int

-- |Raft divides time into terms of arbitrary length. Terms are numbered with
-- consecutive integers.
--
-- Each term begins with an election, in which one or more candidates attempt to
-- become leaders. If a candidate wins the election, then it serves as the
-- leader for the rest of the term.
newtype Term = Term { getTerm :: Int }
  deriving (Eq, Generic, Ord, Show, Typeable)

instance Binary Term

inc :: Term -> Term
inc (Term k) = Term (k + 1)

newtype ServerID = ServerID { getServerID :: Int }

-- |When servers start up, they begin as followers. A server remains in follower
-- state as long as it receives valid RPCs from a leader of candidate.
data ServerStatus
  = Leader    -- ^ leader handles all client requests, if a client contacts a
              -- follower, the follower redirects it to the leader
  | Follower  -- ^ passive, issues no requests of their own
  | Candidate -- ^ used to elect a new leader

data PersistentState cmd = PersistentState
  { _currentTerm :: Term -- ^ Current terms are exchanged whenever server
                         -- communicate; if one server's current term is smaller
                         -- than the other's, then it updates its current term
                         -- the the larger value. If a candidate or leader
                         -- discovers that its term is out of date, it
                         -- imediately reverts to follower state.
  , _votedFor    :: Maybe CandidateID -- ^ candidate that received vite in current term
  , _log         :: [LogEntry cmd]
  }

data VolatileState addr = VolatileState
  { _commitIndex :: LogEntryIndex -- ^ index of the highest log entry known to be committed
  , _lastApplied :: LogEntryIndex
  , _nodes       :: [addr]
  }

data LeaderState = LeaderState
  { _nextIndex  :: [LogEntryIndex]
  , _matchIndex :: [LogEntryIndex]
  }

data ServerState addr cmd = ServerState
  { _persistentState :: PersistentState cmd
  , _volatileState   :: VolatileState addr
  , _leaderState     :: Maybe LeaderState
  }

makeLenses ''PersistentState
makeLenses ''VolatileState
makeLenses ''LeaderState
makeLenses ''ServerState

-- |Servers retry RPCs for transferring snapshots between servers. Servers retry
-- RPCs if they do not receive a response in a timely manner.
class MonadRPC m where

  -- |Invoked by leader to replicate log entries. Also used as heartbeat.
  appendEntries :: Term           -- ^ leader's term
                -> ServerID       -- ^ leader's ID so follower can redirect clients
                -> LogEntryIndex  -- ^ index of log entry immediately preceding new ones
                -> Term           -- ^ term of prevLogIndex
                -> [LogEntry cmd]     -- ^ log entries to store, empty for heartbeat
                -> LogEntryIndex  -- ^ leader's commit index
                -> m (Term, Bool) -- ^ current term, for leader to update itself

  -- |Leaders send periodic heartbeats to all followers.
  sendHeartbeat :: Term           -- ^ leader's term
                -> ServerID       -- ^ leader's ID so follower can redirect clients
                -> LogEntryIndex  -- ^ index of log entry immediately preceding new ones
                -> Term           -- ^ term of prevLogIndex
                -> LogEntryIndex  -- ^ leader's commit index
                -> m (Term, Bool) -- ^ current term, for leader to update itself
  sendHeartbeat term leaderId prevLogIndex prevLogTerm =
    appendEntries term leaderId prevLogIndex prevLogTerm []

  -- |Invoked by candidates to gather votes.
  -- requestVote :: Term           -- ^ candidate's term
  --             -> ServerID       -- ^ candidate requesting vote
  --             -> LogEntryIndex  -- ^ index of candidate's last log entry
  --             -> Term           -- ^ term of candidate's last log entry
  --             -> m (Term, Bool) -- ^ current term, for candidate to update itself
                                -- true means candidate received vote

  -- |TODO (see Section 7)
  transferSnapshot :: m ()

data Config = Config
  { electionTimeoutInterval :: (Int, Int) -- ^ e.g. 150--300 ms
  }

-- |If a follower receives no communication over a period of time called the
-- election timeout, then it assumes there is no viable leader and begins an
-- election to choose a new leader.
--
-- Raft uses randomized election timeouts to ensure that split votes are rare
-- and that they are resolved quickly.

type ServerProcess cmd =
  ReaderT Config (StateT (ServerState ProcessId cmd) Process)

{--
Each client request contains a command to be executed by the replicated state
machines. The leader appends the command to its log as a new entry, then is-
sues AppendEntries RPCs in parallel to each of the other servers to replicate
the entry. When the entry has been safely replicated (as described below), the
leader applies the entry to its state machine and returns the result of that
execution to the client. If followers crash or run slowly, or if network packets
are lost, the leader retries Append- Entries RPCs indefinitely (even after it
has responded to the client) until all followers eventually store all log en-
tries.
--}

leader :: ServerProcess cmd ()
leader = undefined

{--
if randomized timeout passed without receiving a heartbeat message from the
master, became a candidate and start an election, by making a request vote call
to all peers in the network.
--}

follower :: ServerProcess cmd ()
follower = undefined

{--
while waiting for votes a candidate may receive an AppendEntries from another
server claiming to be leader. If the leader's terms is at least as large as the
candidate's current term, then the candidate recognizes the leader as legitimate
and returns to follower state.
--}

-- receiveVotes :: Serializable cmd => Int -> Int -> [Tag] -> ServerProcess cmd Bool
-- receiveVotes threshold k tags
--     | threshold < k = return True
--     | otherwise = controlP $ \runInBase -> receiveWait
--     [ matchTag (`elem` tags) $ \(tag, (RequestVoteResponse t v)) -> runInBase $ do
--         receiveVotes threshold (if v then k + 1 else k) (filter (/= tag) tags)

--     , match $ runInBase . f
--     ]


f :: AppendEntriesMessage cmd -> ServerProcess cmd (Maybe Bool)
f (AppendEntriesMessage t _ _ _ _ _) =
  withTimeout 10 $ do
    term <- use (persistentState.currentTerm)
    if t >= term
        then return False
        else return True



-- |Runs an election, returns True when the candidate is elected, and False
-- otherwise. If the candidate is not elected this might run forever; use a
-- timeout.
-- runElection :: ServerProcess cmd Bool
-- runElection = do
--   peers <- use (volatileState.nodes)
--   pending <- mapM requestVote peers
--   awaitPending (computeThreshold peers) 1 pending
--   where
--     awaitPending threshold votes pending
--       | threshold <= votes = return True
--       | otherwise = controlP $ \runInBase -> receiveWait
--         [ matchTag (`elem` pending) $
--           \(tag, RequestVoteResponse t voteGranted) ->
--             runInBase $ do
--               outOfDate <- isOutOfDate t
--               if outOfDate
--                 then do
--                   persistentState.currentTerm .= t
--                   return False
--                 else awaitPending threshold (applyVote voteGranted votes) (filter (/= tag) pending)
--         -- , match $ \(tag, msg) -> runInBase $ do
--         --     outOfDate <- isOutOfDate $ term msg
--         --     if outOfDate
--         --       then do
--         --         persistentState.currentTerm .= term msg
--         --         return False
--         --       else loop threshold votes pending
--         ]

--     computeThreshold pending = (length pending `div` 2) + 1
--     applyVote False votes = votes
--     applyVote True votes = votes + 1

isOutOfDate :: Term -> ServerProcess cmd Bool
isOutOfDate = undefined



withTimeout :: MonadBaseControl IO m => Int -> m a -> m (Maybe a)
withTimeout d act = do
  r <- liftBaseWith $ \runInBase -> T.timeout d (runInBase act)
  case r of
    Nothing -> return Nothing
    Just stm -> Just <$> restoreM stm

matchTag :: Serializable a
         => (Tag -> Bool) -> ((Tag, a) -> Process b) -> Match b
matchTag = undefined


data RequestVoteMessage = RequestVoteMessage Term ProcessId Int Term
  deriving (Generic, Show, Typeable)

instance Binary RequestVoteMessage

data RequestVoteResponse = RequestVoteResponse Term Bool
  deriving (Generic, Show, Typeable)

instance Binary RequestVoteResponse

data AppendEntriesMessage cmd = AppendEntriesMessage
  { term :: Term
  , leaderId :: ProcessId
  , prevLogIndex :: Int
  , prevLogTerm :: Term
  , entries :: [LogEntry cmd]
  , leaderCommit :: Int
  } deriving (Generic, Show, Typeable)

data RaftMessage cmd
  = AppendEntries Term LogIndex Term [LogEntry cmd] LogIndex
  | RequestVote Term Term LogIndex Term
  deriving (Generic, Show, Typeable)

candidate :: Serializable cmd => ServerProcess cmd ()
candidate = do
  persistentState.currentTerm %= inc
  result <- runElection
  case result of
    ElectionTimeout _ -> follower
    Overruled -> follower
    Elected -> leader

randomElectionTimeout :: MonadReader Config m => m Int
randomElectionTimeout = undefined

data ElectionResult
  = ElectionTimeout Int
  | Elected
  | Overruled

runElection :: ServerProcess cmd ElectionResult
runElection = undefined



instance Binary cmd => Binary (RaftMessage cmd)

instance Binary cmd => Binary (AppendEntriesMessage cmd)

data AppendEntriesResponse = AppendEntriesResponse Term Bool
  deriving (Generic, Show, Typeable)

instance Binary AppendEntriesResponse



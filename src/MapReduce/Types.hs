module MapReduce.Types where

data WorkerStatus
  = Idle
  | Busy

newtype Address = Address String

data Worker = Worker
  { workerAddr   :: Address
  , workerStatus :: WorkerStatus
  }

mkWorker :: Address -> Worker
mkWorker addr = Worker
  { workerAddr = addr
  , workerStatus = Idle
  }

data TaskType = Map | Reduce

data TaskStatus
  = ToBeDone
  | InProgress
  | Failed
  | Completed


data Task = Task
  { taskID     :: (TaskType, Int)
  , taskStatus :: TaskStatus
  }

data MapReduce = MapReduce
  { tasks   :: [Task]
  , workers :: [Worker]
  , nrReduceTasks :: Int
  , nrMapTasks :: Int
  , inputFile :: FilePath
  }



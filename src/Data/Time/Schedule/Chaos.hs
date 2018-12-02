{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -Wall #-}

-- | The core Chaos API
module Data.Time.Schedule.Chaos
  (
    -- | Typeclasses
    Cause (..),

    -- | Data constructors
    Frequency (..),
    Plan (..),
    Schedule (..),

    -- | Functions
    genTime,
    mkOffsets,
    mkSchedules,
    randomSeconds,
    randomTimeBetween,
    runSchedule,
    runPlan
    ) where

import           Control.Concurrent       (threadDelay)
import           Control.Concurrent.Async (Async (..), async)
import           Control.Monad            (forever, replicateM, replicateM_)
import           Control.Monad.IO.Class   (MonadIO, liftIO)
import           Control.Monad.Reader     (Reader, runReader)
import           Data.Bifunctor           (first)
import           Data.List                (repeat)
import           Data.Time.Clock          (NominalDiffTime, UTCTime, addUTCTime,
                                           diffUTCTime, getCurrentTime)
import           GHC.Generics
import           System.Random            (Random (..), RandomGen, newStdGen,
                                           randomR)

-- | An execution plan
data Plan a = Plan Frequency Schedule (IO a)

-- | An event source descriptor based on time
data Schedule =
  -- | A point in the future, in ms
  Offset Int
  -- | A point in the future, as a @UTCTime@
  | Instant UTCTime
  -- | A lower & upper time boundary
  | Window UTCTime UTCTime
  deriving (Read, Show, Eq, Generic)

-- | The amount of times of some "thing", e.g. action, schedule
data Frequency = Once | Continuous | N Int deriving (Eq, Show)

-- | Operations for sourcing events
class (MonadIO m) => Cause m s where

  -- | Request the next event, where @s@ is the event source descriptor,
  -- and @m b@ is the event generation action
  next :: s -> m b -> m b

  -- | Invoke @next@ @Int@ times
  times :: Int -> s -> m b -> m [b]
  times n s a = replicateM n (next s a)

  -- | Generate events according to @s@ at most @[1, n]@ times, using the
  -- supplied random generator
  atMost :: RandomGen g => Int -> s -> m b -> g -> m (g, [b])
  atMost n s a g = return (randomR (1, n) g) >>= (\(n', g') -> do
    v <- times n' s a
    return (g', v))

  -- | Generate an event, using @s@ as the *lower* bound
  lower :: s -> m b -> m b

  -- | Generate an event, using @s@ as the *upper* bound
  upper :: s -> m b -> m b

instance Cause IO Int where
  next = lower

  -- | A delay of @ms@ milliseconds before executing @a@
  lower ms a = threadDelay (ms * 1000) >> a

  --upper ms a = newStdGen >>= genTime (Offset ms) >>=

instance Cause IO UTCTime where
  -- | A delay of @t - getCurrentTime@  before executing @a@
  next t a = getCurrentTime >>= return . timeDiffSecs >>= (\t' -> next t' a)
    where timeDiffSecs :: UTCTime -> Int
          timeDiffSecs = round . flip diffUTCTime t

instance Cause IO (UTCTime, UTCTime) where


-- | Generate events, parameterised by time
instance Cause IO Schedule where

  next (Offset ms) a  = next ms a
  next (Window s e) a = newStdGen >>=
    return . randomTimeBetween s e >>=
    return . fst >>=
    (\t -> next t a)

-- | Asynchronous convenience wrapper for @timesIn@
--asyncTimesIn :: Int -> Schedule -> IO a -> IO [Async a]
--asyncTimesIn n s a = timesIn n s (async a)

-- | Randomly pick a time compatible with the given schedule
genTime :: (MonadIO m, RandomGen g) => Schedule -> g -> m (UTCTime, g)
genTime (Offset ms) rg = do
  now <- liftIO $ getCurrentTime
  let end' = addUTCTime (realToFrac (ms `div` 1000)) now
  genTime (Window now end') rg
genTime (Window s e) rg = return $ randomTimeBetween s e rg

-- | Shorthand for the difference between two UTCTime instances
diff :: UTCTime -> UTCTime -> NominalDiffTime
diff = diffUTCTime

-- | Delay for a random amount within the schedule
delayFor :: RandomGen g => Schedule -> g -> IO g
delayFor sc g = do
  let (ti, g') = undefined -- <- genTime sc g
  del <- case sc of
              Offset _   -> getCurrentTime >>= return . flip getDelay ti
  threadDelay del
  return g'

-- | Turn the @UTCTime@ to its microseconds
getDelay :: UTCTime -> UTCTime -> Int
getDelay s t = delay
  where tDiff = (round $ diff s t) :: Int
        micros = 1000 * 1000
        delay = abs $ tDiff * micros

-- | Construct an infinite list of constant @Offset@ instances
mkOffsets :: Int -> [Schedule]
mkOffsets n = Offset <$> repeat n

-- | Construct the schedule using the supplied reader
mkSchedules :: Reader e Schedule -> e -> [IO a] -> [(Schedule, IO a)]
mkSchedules r e acts = map (\ac -> (runReader r e, ac)) acts

-- | Generate seconds in the interval [0, n]
randomSeconds :: RandomGen g => g -> Int -> (NominalDiffTime, g)
randomSeconds rg mx = first realToFrac $ randomR (0, mx) rg

-- | Pick a time within the given boundaries.
randomTimeBetween :: RandomGen g => UTCTime -> UTCTime -> g -> (UTCTime, g)
randomTimeBetween s e rg = case secs of (t, ng) -> (addUTCTime t s, ng)
  where secs = randomSeconds rg (abs $ floor (diff s e))

runSchedule :: Frequency -> (Schedule, IO a) -> IO [a]
runSchedule Once (sc, a)         = next sc a >>= return . flip (:) []
runSchedule (Continuous) (sc, a) = forever $ next sc a
runSchedule (N n) (sc, a)        = replicateM n $ next sc a

-- | Execute the given plan and return its results
runPlan :: Plan a -> IO [a]
runPlan (Plan f s a) = runSchedule f (s, a)

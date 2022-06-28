{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeOperators #-}

module T12 where

import Control.Algebra
import Control.Carrier.Random.Gen (Random, runRandom, uniformR)
import Control.Carrier.State.Strict
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.IO.Class
import Data.IORef
import Data.Map (Map)
import qualified Data.Map as Map
import System.Random (mkStdGen)
import Control.Carrier.Lift

newtype NodeID = NodeID Int deriving (Show, Eq, Ord)

data Role = Master | Slave

data Msg where
  ChangeMaster :: TMVar () -> Msg
  GetInt :: TMVar Int -> Msg

data PeerState = PeerState
  { nodeID :: NodeID,
    nodeRole :: Role,
    nodeQueue :: TQueue Msg,
    peersQueue :: Map NodeID (TQueue Msg)
  }

t1 ::
  ( Has (State PeerState :+: Random :+: Lift IO) sig m
  ) =>
  TVar Int ->
  m ()
t1 counter = forever $ do
  gets nodeRole >>= \case
    Master -> do
      psq <- gets peersQueue
      vals <- forM (Map.toList psq) $ \(idx, tq) -> do
        mvar <- sendM newEmptyTMVarIO
        sendM $ atomically $ writeTQueue tq (GetInt mvar)
        val <- sendM $ atomically $ takeTMVar mvar
        pure (val, idx)
      let mnid = snd $ maximum vals
      case Map.lookup mnid psq of
        Nothing -> undefined
        Just tq -> do
          mvar <- sendM newEmptyTMVarIO
          sendM $ atomically $ writeTQueue tq (ChangeMaster mvar)
          sendM $ atomically $ takeTMVar mvar
          modify (\pp -> pp {nodeRole = Slave})
    Slave -> do
      tq <- gets nodeQueue
      sv <- sendM $ atomically $ readTQueue tq
      case sv of
        ChangeMaster mvar -> do
          modify (\pp -> pp {nodeRole = Master})
          sendM $ atomically $ modifyTVar' counter (+ 1)
          sendM $ atomically $ putTMVar mvar ()
        GetInt mvar -> do
          i <- uniformR (1, 100000)
          sendM $ atomically $ putTMVar mvar i

r :: IO ()
r = do
  counterRef <- newTVarIO 0
  nodes <- forM [1 .. 4] $ \i -> do
    tq <- newTQueueIO
    pure (NodeID i, tq)
  let nodeMap = Map.fromList nodes
  (h : hs) <- forM nodes $ \(nid, tq) -> do
    pure (PeerState nid Slave tq (Map.delete nid nodeMap))

  let h1 = h {nodeRole = Master}

  forkIO $ void $ runState h1 $ runRandom (mkStdGen 1) $ t1 counterRef

  forM_ hs $ \h' -> do
    forkIO $ void $ runState h' $ runRandom (mkStdGen 2) $ t1 counterRef

  forever $ do
    threadDelay 1000000
    counter <- readTVarIO counterRef
    atomically $ modifyTVar' counterRef (const 0)
    print counter

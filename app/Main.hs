{-# LANGUAGE TypeApplications #-}
module Main where

import T
import T1
import T12
import T2
import System.Environment

main :: IO ()
main = do
  args <- getArgs
  case read @Int $ head args of
    1 -> T.r
    2 -> T1.r
    21 -> T12.r
    3 -> T2.r
    _ -> error ""

module FaeServer.Git where

import Blockchain.Fae.FrontEnd

import Control.Monad

import System.Directory
import System.Environment
import System.Exit
import System.Process

gitInit :: IO ()
gitInit = do
  removePathForcibly "git"
  runGitWithArgs "init" ["--quiet"]
  runGitWithArgs "config" ["user.name", "Fae"]
  runGitWithArgs "config" ["user.email", "fae"]
  runGitWithArgs "commit" ["-q", "--allow-empty", "-m", "Transaction " ++ show nullID]
  runGitWithArgs "tag" [mkTXIDName nullID]

gitCommit :: TransactionID -> IO ()
gitCommit txID = do
  runGitWithArgs "add" ["Blockchain"]
  runGitWithArgs "commit" ["-q", "-m", "Transaction " ++ show txID]
  runGitWithArgs "tag" [mkTXIDName txID]

gitReset :: TransactionID -> IO ()
gitReset oldTXID = runGitWithArgs "reset" ["--hard", "-q", mkTXIDName oldTXID]

gitClean :: IO ()
gitClean = runGitWithArgs "clean" ["-q", "-f", "Blockchain"]

runGitWithArgs :: String -> [String] -> IO ()
runGitWithArgs cmd args = do
  let fullArgs = "--work-tree" : "." : cmd : args
  (exitCode, out, err) <- readProcessWithExitCode "git" fullArgs ""
  case exitCode of
    ExitSuccess -> unless (null out) $ putStrLn $ unlines
      [
        "`git " ++ cmd ++ "` was successful with the following output:",
        out
      ]
    ExitFailure n -> do
      putStrLn $ unlines $
        ("`git " ++ cmd ++ "` returned code " ++ show n) :
        if null err then [] else
          [            
            "Error message:",
            err
          ]
      exitFailure
 

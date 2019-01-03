{-# OPTIONS_GHC -Wall #-}

module ExamplesSpec ( spec ) where

import           Control.Monad    (filterM, forM_, mapM_)
import           Data.List
import qualified Data.Text        as T
import qualified Data.Text.IO     as T
import           Prelude          (error)
import           Protolude
import           System.Directory
import           Test.Hspec
import           Weave
import           Weave.Parser     (ParseResult (..), parsePlan)

type ValidationFunction = FilePath -> ParseResult -> Expectation

spec :: Spec
spec = do
  describe "Parser" $ do
    context "Valid examples" $ do

      it "General" $ do
        runTest "./examples/valid" validOffset

        runTest "./examples/valid/frequency" validFrequency

      it "Operators" $
        runTest "./examples/valid/operators" validOffset

getExamples :: FilePath -> IO [T.Text]
getExamples p = getDirectoryContents p
  >>= filterM (return . isWeaveFile)
  >>= mapM (T.readFile . absPath)
    where isWeaveFile = isSuffixOf ".weave"
          absPath f = p ++ "/" ++ f

validOperator :: FilePath -> ParseResult -> Expectation
validOperator _ _ = pendingWith "To-do"

validOffset :: FilePath -> ParseResult -> Expectation
validOffset _ (MalformedPlan l)         = error $ "Parse error: " ++ show l
validOffset _ (Success (Plan s)) = (lengthIs s 1) >>
  mapM_ (\(Temporal _ sc _) -> sc `shouldNotBe` Offset 0) s

validFrequency :: FilePath -> ParseResult -> Expectation
validFrequency _ (MalformedPlan l)         = error $ "Parse error: " ++ show l
validFrequency p (Success (Plan s)) = (lengthIs s 1) >>
  (mapM_ (\(Temporal f _ _) -> f `shouldBe` getFrequency p) s)
  where getFrequency _ = Once --FIXME derive this from the filename

shouldNotParse :: FilePath -> ParseResult -> Expectation
shouldNotParse _ (Success p) = error $ "No statements should be parsed: " ++ show p
shouldNotParse _ (MalformedPlan l)         = l `shouldSatisfy` T.isInfixOf "Parse error"

emptyParse :: FilePath -> ParseResult -> Expectation
emptyParse _ (Success (Plan s)) = length s `shouldBe` 0

lengthIs :: [a] -> Int -> Expectation
lengthIs x n = length x `shouldBe` n

runTest :: FilePath -> ValidationFunction -> Expectation
runTest p f = do
  exs <- getExamples p
  length exs `shouldNotBe` 0
  forM_ exs (\ex -> do
    print $ "Testing: " ++ show ex
    f p $ parsePlan ex)

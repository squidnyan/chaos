{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | The Weave parsing API
module Weave.Parser (
  TimeUnit (..),

  parsePlan,
  toMillis
  ) where

import           Control.Applicative  ((<|>))
import           Data.Attoparsec.Text
import qualified Data.Text            as T
import           Prelude              hiding (takeWhile)
import           System.Process       (spawnCommand)
import           Weave

-- | All possible outcomes of an actoin reference parse
data ActionRefParseResult = -- | The action reference was not found
                            ActionNotFound T.Text
                            -- | The identified action reference
                            | ActionRef T.Text Action
                            deriving (Show)

-- | The unit of time supported as Temporal Expressions
data TimeUnit = Seconds
              | Minutes
              | Hours
              | Days
              deriving (Enum, Eq, Show)

-- | The default operator if none is supplied
defaultOperator :: Char
defaultOperator = ','

-- | Parse the entire Plan from the given string
parsePlan :: T.Text -> Either String (Plan ())
parsePlan = wrap . parseOnly planP
  where wrap (Left e) = Left $ "Parse error: " ++ show e -- For testing
        wrap r        = r

-- | The entire document parser
planP :: Parser (Plan a)
planP = do
  acts <- many' actionBlockP
  (fr, s)  <- temporalP
  r <- option Undefined inlineBodyP
  case r of
    Undefined -> actionExpressionsP acts >>= return . Plan [(fr, s)]
    shell     -> return $ Plan [(fr, s)] [(shell, defaultOperator)]

-- | Parse the inline action declaration
inlineBodyP :: Parser Action
inlineBodyP = Shell "inline" <$> bodyP

-- | Parse a frequency and schedule
temporalP :: Parser (Frequency, Schedule)
temporalP = do
  (fr, fn) <- scheduleCtorP <?> "Schedule Constructor"
  num <- round <$> double
  skipSpace
  tu <- unitP <?> "TimeUnit"
  skipSpace
  return (fr, fn $ num * (toMillis tu))

-- | Parse the schedule string from plain English to its corresponding data constructor
scheduleCtorP :: Parser (Frequency, (Int -> Schedule))
scheduleCtorP = do
  skipWhile ((==) '\n')
  ctorStr <- ((string "every" <?> "every") <|> (string "in" <?> "in")) <?> "Schedule Ctor"
  skipSpace
  case ctorStr of
    "every" -> return (Continuous, Offset)
    "in"    -> return (Once, Offset)
    s       -> error $ "Unknown frequency: " ++ show s

-- | Parse a @TimeUnit@ from plain English
unitP :: Parser TimeUnit
unitP = do
  ctorStr <- (string "seconds"
              <|> string "minutes"
              <|> string "hours"
              <|> string "days") <?> "Unit ctor"
  skipSpace
  case ctorStr of
    "seconds" -> return Seconds
    "minutes" -> return Minutes
    "hours"   -> return Hours
    "days"    -> return Days
    t         -> error $ "Unkown schedule token: " ++ show t

-- | Parse an action block
actionBlockP :: Parser Action
actionBlockP = do
  _ <- string "action" <?> "Declared Action"
  skipSpace
  name <- many1 letter >>= return . T.pack
  skipSpace
  bdy <- bodyP
  skipWhile ((==) '\n')
  return (Shell name bdy) -- FIXME parse other types

-- | Parse a full command body, i.e. between '{' and '}'
bodyP :: Parser T.Text
bodyP = do
  op <- (char '{' <?> "Open brace") <|>
        (char '@' <?> "URL") <|>
        (char ':' <?> "Plain text")
  skipSpace
  -- Will this fail on embedded } ?
  res <- takeWhile (/= (inverse op)) <?> "Body contents"
  skipMany (char $ inverse op)
  return res
    where inverse '{' = '}'
          inverse '@' = '\n'
          inverse ':' = '\n'
          inverse c   = error $ "Unknown body enclosing character: " ++ show c

-- | Parse many action expressions
actionExpressionsP :: [Action] -> Parser [(Action, Char)]
actionExpressionsP l = many1 $ actionExpressionP l

-- | Parse the body reference and an operator on its RHS
actionExpressionP :: [Action] -> Parser (Action, Char)
actionExpressionP l = do
  ref <- actionReferenceP l
  c <- option defaultOperator operatorsP
  f ref c
    where f (ActionRef _ a) c    = return (a, c)
          f (ActionNotFound i) c = return (Shell i "", c)

-- | Parse a supported operator
operatorsP :: Parser Char
operatorsP = do
  skipSpace
  c <- char '|' <|> char '&' <|> char ',' <|> char '¬'
  skipSpace
  return c

-- | Parse one body reference (e.g. @action1@ in @action1 | action2@) to an action
-- and find its action in the given list
actionReferenceP :: [Action] -> Parser ActionRefParseResult
actionReferenceP l = do
  skipSpace
  iden <- T.pack <$> many1 letter
  summarise iden (findDeclared iden)
    where findDeclared n = filter (byName n) l
          byName n (Shell n' _) = n == n'
          byName _ Undefined    = False
          summarise i [] = return $ ActionNotFound i
          summarise i x  = return $ ActionRef i $ head x -- only take the first

-- | Represent our @TimeUnit@ as an @Int@
toMillis :: TimeUnit -> Int
toMillis Seconds = 1000
toMillis Minutes = (toMillis Seconds) * 60
toMillis Hours   = (toMillis Minutes) * 60
toMillis Days    = (toMillis Hours) * 24

--actionToIO :: Schedule -> (Action, T.Text) -> IO a
actionToIO (Offset m)   (Shell _ a, b) = next m $ spawnCommand $ T.unpack b
actionToIO (Instant t)  (Shell _ a, b) = next t $ spawnCommand $ T.unpack b
actionToIO (Window s e) (Shell _ a, b) = next (s, e) $ spawnCommand $ T.unpack b

--processBody :: T.Text IO (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle)

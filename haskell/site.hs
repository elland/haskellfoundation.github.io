{-# Language DeriveGeneric #-}
{-# Language ScopedTypeVariables #-}
{-# Language OverloadedStrings #-}
{-# Language TemplateHaskell #-}

import           Control.Monad                  ( when )
import qualified Data.Aeson                    as Aeson
import qualified Data.Aeson.TH                 as Aeson
import           Data.ByteString.Lazy           ( ByteString )
import qualified Data.ByteString.Lazy          as LBS
import           Data.Map                       ( Map )
import qualified Data.Map                      as Map
import           Data.Maybe                     ( fromMaybe )
import           Data.Monoid                    ( (<>) )
import           Data.Text                      ( Text )
import           Data.Time.Clock                ( getCurrentTime )
import           Data.Time.Format.ISO8601       ( iso8601Show )
import           GHC.Generics
import           Hakyll
import           System.Directory
import           System.FilePath.Posix          ( takeBaseName )

config :: Configuration
config = defaultConfiguration { destinationDirectory = "../docs" }

main :: IO ()
main = do
  do
    d <- getCurrentDirectory
    if takeBaseName d == "haskell"
      then setCurrentDirectory "../site"
      else when (takeBaseName d /= "site") $ setCurrentDirectory "./site"
  now <- getCurrentTime
  hakyllWith config $ do
    match "static/**" $ do
      route idRoute
      compile copyFileCompiler

    match "css/main.css" $ do
      route idRoute
      compile postcss

    match "data.json" $ compile $ getResourceLBS

    match "index.html" $ do
      route idRoute
      compile $ do
        getResourceBody
          >>= applyAsTemplate defaultContext
          >>= loadAndApplyTemplate "templates/boilerplate.html" defaultContext
          >>= relativizeUrls

    match nonRSSIndices $ do
      route idRoute
      compile $ do
        getResourceBody
          >>= applyAsTemplate defaultContext
          >>= loadAndApplyTemplate "templates/boilerplate.html" defaultContext
          >>= relativizeUrls

    match podcastEpisodes $ do
      route idRoute
      compile
        $   getResourceBody
        >>= saveSnapshot "rss"
        >>= applyAsTemplate defaultContext
        >>= loadAndApplyTemplate "templates/boilerplate.html" defaultContext
        >>= relativizeUrls

    match podcastIndex $ do
      route idRoute
      compile $ do
        episodes <- recentFirst =<< loadAll podcastEpisodes
        let indexContext =
              listField "episodes" podcastContext (pure episodes)
                <> defaultContext

        getResourceBody
          >>= loadAndApplyTemplate "templates/boilerplate.html" indexContext
          >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler

    create ["podcast.xml"] $ do
      route idRoute
      compile $ do
        episodes <- recentFirst =<< loadAllSnapshots podcastEpisodes "rss"

        podcastTemplate <- loadBody "templates/podcast.xml"
        episodeTemplate <- loadBody "templates/episode.xml"

        renderRssWithTemplates podcastTemplate
                               episodeTemplate
                               feedConfiguration
                               podcastContext
                               episodes


-------------------------

podcastIndex :: Pattern
podcastIndex = ("podcast/index.html" .||. "podcast/episodes/index.html")

podcastEpisodes :: Pattern
podcastEpisodes =
  "podcast/episodes/*" .&&. complement "podcast/episodes/index.html"

-- exlucude podcast index from this rule, it has its own rules, because of RSS
-- TODO: add news to this list, once news also issues RSS.
nonRSSIndices :: Pattern
nonRSSIndices =
  "**/index.html" .&&. complement "podcast/index.html" .&&. complement
    "podcast/episodes/index.html"

postcss :: Compiler (Item ByteString)
postcss = getResourceLBS >>= withItemBody (unixFilterLBS "postcss" [])

feedConfiguration :: FeedConfiguration
feedConfiguration = FeedConfiguration
  { feedTitle       = "The Haskell Interlude"
  , feedDescription = unlines
    [
      "A Haskell-focused podcast where we interview guests from the community."
    , "The hosts are Niki Vazou, Joachim Breitner, Andres Löh, Alejandro Serrano and Wouter Swierstra."
    ]
  , feedAuthorName  = "The Haskell Foundation"
  , feedAuthorEmail = "podcast@haskell.foundation"
  , feedRoot        = "https://haskell.foundation/podcast"
  }

podcastContext :: Context String
podcastContext = dateField "date" "%B %e, %Y" <> defaultContext

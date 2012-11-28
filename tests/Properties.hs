{-# LANGUAGE BangPatterns, CPP, GeneralizedNewtypeDeriving, MagicHash,
    Rank2Types, UnboxedTuples #-}
#ifdef GENERICS
{-# LANGUAGE DeriveGeneric, ScopedTypeVariables #-}
#endif

-- | Tests for the 'Data.Hashable' module.  We test functions by
-- comparing the C and Haskell implementations.

module Main (main) where

import Data.Hashable (Hashable, hash, hashByteArray, hashPtr)
import qualified Data.Text as T
import qualified Data.Text.Lazy as L
import Control.Monad (ap, liftM)
import System.IO.Unsafe (unsafePerformIO)
import Foreign.Marshal.Array (withArray)
import GHC.Base (ByteArray#, Int(..), newByteArray#, unsafeCoerce#,
                 writeWord8Array#)
import GHC.ST (ST(..), runST)
import GHC.Word (Word8(..))
import Test.QuickCheck hiding ((.&.))
import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
#ifdef GENERICS
import GHC.Generics
#endif

------------------------------------------------------------------------
-- * Properties

instance Arbitrary T.Text where
    arbitrary = T.pack `fmap` arbitrary

instance Arbitrary L.Text where
    arbitrary = L.pack `fmap` arbitrary

-- | Validate the implementation by comparing the C and Haskell
-- versions.
pHash :: [Word8] -> Bool
pHash xs = unsafePerformIO $ withArray xs $ \ p ->
    (hashByteArray (fromList xs) 0 len ==) `fmap` hashPtr p len
  where len = length xs

-- | Content equality implies hash equality.
pText :: T.Text -> T.Text -> Bool
pText a b = if (a == b) then (hash a == hash b) else True

-- | Content equality implies hash equality.
pTextLazy :: L.Text -> L.Text -> Bool
pTextLazy a b = if (a == b) then (hash a == hash b) else True

-- | A small positive integer.
newtype ChunkSize = ChunkSize { unCS :: Int }
    deriving (Eq, Ord, Num, Integral, Real, Enum, Show)

instance Arbitrary ChunkSize where
    arbitrary = (ChunkSize . (`mod` maxChunkSize)) `fmap`
                (arbitrary `suchThat` ((/=0) . (`mod` maxChunkSize)))
        where maxChunkSize = 16

-- | Ensure that the rechunk function causes a rechunked string to
-- still match its original form.
pRechunk :: T.Text -> NonEmptyList ChunkSize -> Bool
pRechunk t cs = L.fromStrict t == rechunk t cs

-- | Content equality implies hash equality.
pLazyRechunked :: T.Text -> NonEmptyList ChunkSize -> Bool
pLazyRechunked t cs = hash (L.fromStrict t) == hash (rechunk t cs)

-- | Break up a string into chunks of different sizes.
rechunk :: T.Text -> NonEmptyList ChunkSize -> L.Text
rechunk t0 (NonEmpty cs0) = L.fromChunks . go t0 . cycle $ cs0
  where
    go t _ | T.null t = []
    go t (c:cs)       = a : go b cs
      where (a,b)     = T.splitAt (unCS c) t
    go _ []           = error "Properties.rechunk - The 'impossible' happened!"

-- This wrapper is required by 'runST'.
data ByteArray = BA { unBA :: ByteArray# }

-- | Create a 'ByteArray#' from a list of 'Word8' values.
fromList :: [Word8] -> ByteArray#
fromList xs0 = unBA (runST $ ST $ \ s1# ->
    case newByteArray# len# s1# of
        (# s2#, marr# #) -> case go s2# 0 marr# xs0 of
            s3# -> (# s3#, BA (unsafeCoerce# marr#) #))
  where
    !(I# len#) = length xs0
    go s# _         _     []           = s#
    go s# i@(I# i#) marr# ((W8# x):xs) =
        case writeWord8Array# marr# i# x s# of
            s2# -> go s2# (i + 1) marr# xs

-- Generics

#ifdef GENERICS

data Product2 a b = Product2 a b
                    deriving (Generic)

instance (Arbitrary a, Arbitrary b) => Arbitrary (Product2 a b) where
    arbitrary = Product2 `liftM` arbitrary `ap` arbitrary

instance (Hashable a, Hashable b) => Hashable (Product2 a b)

data Product3 a b c = Product3 a b c
                    deriving (Generic)

instance (Arbitrary a, Arbitrary b, Arbitrary c) =>
    Arbitrary (Product3 a b c) where
    arbitrary = Product3 `liftM` arbitrary `ap` arbitrary `ap` arbitrary

instance (Hashable a, Hashable b, Hashable c) => Hashable (Product3 a b c)

-- Hashes of all product types should be the same.

pProduct2 :: Int -> String -> Bool
pProduct2 x y = hash (x, y) == hash (Product2 x y)

pProduct3 :: Double -> Maybe Bool -> (Int, String) -> Bool
pProduct3 x y z = hash (x, y, z) == hash (Product3 x y z)

#endif

------------------------------------------------------------------------
-- Test harness

main :: IO ()
main = defaultMain tests

tests :: [Test]
tests =
    [ testProperty "bernstein" pHash
    , testGroup "text"
      [ testProperty "text/strict" pText
      , testProperty "text/lazy" pTextLazy
      , testProperty "rechunk" pRechunk
      , testProperty "text/rechunked" pLazyRechunked
      ]
#ifdef GENERICS
    , testGroup "generics"
      [
        testProperty "product2" pProduct2
      , testProperty "product3" pProduct3
      ]
#endif
    ]

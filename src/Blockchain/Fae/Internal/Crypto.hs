module Blockchain.Fae.Internal.Crypto 
  (
    Serialize,
    module Blockchain.Fae.Internal.Crypto
  ) where

import Control.Monad

import qualified Crypto.Hash as Hash
import qualified Crypto.PubKey.Ed25519 as Ed

import qualified Data.ByteArray as BA
import Data.Dynamic
import Data.Serialize (Serialize)

import qualified Data.Serialize as Ser
import qualified Data.Serialize.Put as Ser
import qualified Data.Serialize.Get as Ser

import System.IO.Unsafe

-- | It's what it looks like.  We don't implement our own crypto because we
-- aren't crazy; this is taken from 'cryptonite'.
newtype PublicKey = PublicKey Ed.PublicKey deriving (Eq, Show)
data PrivateKey = PrivateKey Ed.PublicKey Ed.SecretKey
data Signature = Signature Ed.PublicKey Ed.Signature
type Digest = Hash.Digest Hash.SHA3_256

class Digestible a where
  digest :: a -> Digest

  default digest :: (Serialize a) => a -> Digest
  digest = Hash.hash . Ser.encode

instance Serialize Digest where
  put = Ser.putByteString . BA.convert
  get = Ser.isolate hashSize $ do
    digestBS <- Ser.getBytes hashSize
    let Just result = Hash.digestFromByteString digestBS
    return result
    where hashSize = Hash.hashDigestSize Hash.SHA3_256

sign :: (Digestible a) => a -> PrivateKey -> Signature
sign x (PrivateKey pubKey secKey) = 
  Signature pubKey $ Ed.sign secKey pubKey (digest x)

unsign :: (Digestible a) => Signature -> a -> Maybe PublicKey
unsign (Signature pubKey sig) msg
  | Ed.verify pubKey (digest msg) sig = Just $ PublicKey pubKey
  | otherwise = Nothing

newPrivateKey :: IO PrivateKey
newPrivateKey = do
  secKey <- Ed.generateSecretKey
  let pubKey = Ed.toPublic secKey
  return $ PrivateKey pubKey secKey

{-# NOINLINE unsafeNewPrivateKey #-}
unsafeNewPrivateKey :: PrivateKey
unsafeNewPrivateKey = unsafePerformIO newPrivateKey

public :: PrivateKey -> Maybe PublicKey
public (PrivateKey pubKey privKey) 
  | Ed.toPublic privKey == pubKey = Just $ PublicKey pubKey
  | otherwise = Nothing


module Blockchain.Fae.Internal.Contract where

import Blockchain.Fae.Internal.Crypto 
import Blockchain.Fae.Internal.Exceptions
import Blockchain.Fae.Internal.Fae
import Blockchain.Fae.Internal.Lens

import Control.Monad.Fix
import Control.Monad.RWS hiding ((<>))
import Control.Monad.Trans

import Data.Dynamic
import qualified Data.Map as Map
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Proxy

data Contract argType accumType valType =
  Contract
  {
    inputs :: Fae (Seq (ContractID, Dynamic)),
    result :: ResultF AbstractIDContract argType accumType valType,
    accum :: accumType,
    escrows :: Escrows
  }

type AbstractIDContract = ContractID -> AbstractContract
type ResultF output argType accumType valType =
  RWST (Seq (ContractID, Dynamic), argType) [output] accumType Fae valType

newtype FaeContract argType accumType valType =
  FaeContract 
  { 
    getFaeContract :: ResultF OutputContract argType accumType valType
  }
  deriving (Functor, Applicative, Monad, MonadThrow, MonadCatch, MonadFix, MonadState accumType)

instance MonadReader argType (FaeContract argType accumType) where
  ask = FaeContract $ view _2
  local f = FaeContract . local (_2 %~ f) . getFaeContract

data CallTree =
  CallTree
  {
    directInputs :: [InputContract],
    outputTrees :: [CallTree]
  }

data InputContract = 
  InputContract 
  { 
    inputContractID :: ContractID,
    getInputContract :: Fae Dynamic 
  }

newtype OutputContract = 
  OutputContract 
  { 
    getOutputContract :: CallTree -> AbstractIDContract
  }

makeLenses ''Contract

newContract :: 
  (Typeable argType, Typeable valType) =>
  CallTree ->
  accumType ->
  FaeContract argType accumType valType ->
  Contract argType accumType valType
newContract callTree accum0 faeContract =
  Contract
  {
    inputs = Seq.fromList <$> traverse 
      (\inputC -> do
        val <- getInputContract inputC
        return (inputContractID inputC, val)
      ) 
      (directInputs callTree),
    accum = accum0,
    result = mapRWST (fmap $ _3 %~ makeOutputs) $ getFaeContract faeContract,
    escrows = Escrows $ Map.empty
  }
  where
    makeOutputs outputCs = 
      zipWith getOutputContract (pad outputCs) (outputTrees callTree) 
    pad outputCs = 
      outputCs ++ repeat (OutputContract $ \_ -> throw . MissingOutput)

inputContract :: (Typeable a) => ContractID -> a -> InputContract
inputContract !cID !x = InputContract cID $ do
  cM <- Fae $ use $ _transientState . _contractUpdates . _useContracts . at cID
  fE <- maybe
    (throwM $ BadContractID cID)
    return
    cM
  either
    (throwM . BadContract cID) 
    ($ toDyn x)
    fE

outputContract :: 
  (Typeable argType, Typeable valType) =>
  accumType ->
  FaeContract argType accumType valType ->
  FaeContract argType' accumType' ()
outputContract accum0 faeContract = FaeContract $ tell 
  [
    OutputContract $ \callTree cID ->
      abstract cID $ 
      evalContract cID $ 
      newContract callTree accum0 faeContract
  ]

inputValue ::
  forall argType accumType valType.
  (Typeable valType) =>
  Int -> FaeContract argType accumType valType
inputValue i = do
  inputM <- FaeContract $ asks $ Seq.lookup i . fst
  (inputID, inputDyn) <-
    maybe
      (throwM $ MissingInput i)
      return
      inputM
  let err = BadValType inputID (typeRep $ Proxy @valType) (dynTypeRep inputDyn)
  maybe (throwM err) return $ fromDynamic inputDyn

evalContract :: 
  (Typeable argType, Typeable valType) =>
  ContractID -> Contract argType accumType valType -> argType -> Fae valType
evalContract thisID c@Contract{..} arg = do
  Fae $ _transientState . _contractEscrows .= escrows
  inputSeq <- inputs
  (retVal, newAccum, outputs) <- runRWST result (inputSeq, arg) accum
  sequence_ $ zipWith (newOutput thisID) [0 ..] outputs
  contractEscrows <- Fae $ use $ _transientState . _contractEscrows
  setContract thisID $ 
    evalContract thisID $
    c & _accum .~ newAccum
      & _escrows .~ contractEscrows
  return retVal

setContract :: 
  forall argType valType.
  (Typeable argType, Typeable valType) =>
  ContractID -> (argType -> Fae valType) -> Fae ()
setContract cID f = Fae $
  _transientState . _contractUpdates . _useContracts . at cID ?= 
    Right (abstract cID f)

abstract ::
  forall argType valType.
  (Typeable argType, Typeable valType) =>
  ContractID -> (argType -> Fae valType) -> AbstractContract
abstract cID f argDyn = 
  case toDyn f `dynApply` argDyn of
    Nothing -> 
      throwM (BadArgType cID (dynTypeRep argDyn) $ typeRep (Proxy @argType))
    Just x -> return x

newOutput :: ContractID -> Int -> (ContractID -> AbstractContract) -> Fae ()
newOutput (ContractID thisID) i f = do
  let cID = ContractID $ thisID <#> i
  cOrErr <- try (evaluate $ f cID) 
  Fae $ _transientState . _contractUpdates . _useContracts . at cID ?= cOrErr


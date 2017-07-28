{-# LANGUAGE RecursiveDo #-}
module BCoin
  (
    BCoin, -- The constructor is not exported
    CoinArg(Peek),
    CoinEscrow,
    deposit,
    add,
    debit,
    tx
  ) where

import Blockchain.Fae

import Numeric.Natural

-- | An opaque wrapper for a positive integral value.  Users will not be
-- able to construct this, preserving scarcity.
newtype BCoin = BCoin { value :: Natural }

data CoinArg = Peek | Close

type CoinEscrowID = EscrowID CoinArg (Either Natural BCoin)
type CoinEscrow = Escrow CoinArg BCoin

coinEscrow :: Coin -> Fae argType accumType CoinEscrow
coinEscrow coin = returnEscrow [] $ do
  arg <- ask
  case arg of
    Peek -> return $ Left (value coin)
    Close -> do
      spend
      return $ Right coin

-- | The first argument is evaluated during creation.
--   The second argument is a pair of coins to add.
add :: (CoinEscrow, CoinEscrow) -> Fae CoinEscrow
add (coin1ID, coin2ID) = do
  coin1 <- close coin1ID Close
  coin2 <- close coin2ID Close
  let coin = BCoin $ value coin1 + value coin2
  coinEscrow coin 

-- | The first argument is evaluated during creation.
--   The second argument is a coin and a desired debit.
--   If the coin's balance is large enough, the debit occurs.
debit :: (CoinEscrow, Natural) -> Fae (Maybe (CoinEscrow, CoinEscrow))
debit idList (coinID, debit) = do
  v <- peek coinID
  if debit <= v
  then do
    _ <- coinClose coinID
    eID1 <- coinEscrow $ BCoin $ v - debit
    eID2 <- coinEscrow $ BCoin debit
    return $ Just (eID1, eID2)
  else return Nothing

-- | The first two arguments are evaluated during creation.
--   The third argument, when a reward, creates an award coin.
--   When a signature, checks the signer against the contract creator and
--   deletes the contract.
rewardContract :: 
  PublicKey -> 
  Either Signature (EscrowID () () Reward) -> Fae (Maybe EntryID)
rewardContract _ (Right rewardID) = mdo
  _ <- close () rewardID
  let coin = BCoin $ 50 * 10^8 -- As in Bitcoin, initially
  key <- signer
  newID <- label "BCoin" $ createPure (sigContract coin (escrow ()) key newID)
  return $ Just newID

-- When the right signature is passed, terminate rewards.
rewardContract [_,_,_,self] creator (Left sig)
  | verifySig creator self sig = do
      spend
      return Nothing
  | otherwise = return Nothing

-- | When this module is sent as a transaction, this function is run,
-- creating a BCoin rewards contract that can be closed by the sender.
tx :: Fae ()
tx = do
  key <- signer  
  _ <- label "BCoin rewards" $ createPure $ rewardContract key
  return ()


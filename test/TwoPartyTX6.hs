module TwoPartyTX6 where

import Blockchain.Fae
import Blockchain.Fae.Internal 
  (ContractID(..), ShortContractID(..), TransactionID, Digestible, digest)
import Blockchain.Fae.Contracts

import Data.Void

import qualified TwoPartyTX1 as TX1 (txID)
import qualified TwoPartyTX3 as TX3 (txID)
import TwoPartyCommon

txID :: TransactionID
txID = ShortContractID $ digest (6 :: Int)

pubKey :: PublicKey
pubKey = pubKey1

inputs :: [(ContractID, String)]
inputs = 
  [
    (TransactionOutput TX1.txID 0, "Get"),
    (TransactionOutput TX3.txID 0, "b25a913b9e44e5bd4954924ecc2e4214f2fc849bff474437b8b8c2afb4ec55aa")
  ]

body :: Transaction (Maybe TwoPartyEscrow, EscrowID TwoPartyEscrow String) String
body = return . escrowTXResult . snd
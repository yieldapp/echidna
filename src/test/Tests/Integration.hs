module Tests.Integration (integrationTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

import Common (runContract, testContract, testContract', checkConstructorConditions, testConfig, passed, solved, solvedLen, solvedWith, coverageEmpty, testsEmpty, gasInRange, countCorpus)
import Control.Lens (set)
import Control.Monad (when)
import Data.Functor ((<&>))
import Data.List (isInfixOf)
import Data.Text (unpack)
import Echidna.Config (_econfig, parseConfig, sConf)
import Echidna.Solidity (quiet)
import EVM.ABI (AbiValue(..))
import System.Process (readProcess)

integrationTests :: TestTree
integrationTests = testGroup "Solidity Integration Testing"
  [ testContract "basic/true.sol" Nothing
      [ ("echidna_true failed", passed "echidna_true") ]
  , testContract "basic/flags.sol" Nothing
      [ ("echidna_alwaystrue failed",                      passed      "echidna_alwaystrue")
      , ("echidna_revert_always failed",                   passed      "echidna_revert_always")
      , ("echidna_sometimesfalse passed",                  solved      "echidna_sometimesfalse")
      , ("echidna_sometimesfalse didn't shrink optimally", solvedLen 2 "echidna_sometimesfalse")
      ]
  , testContract "basic/flags.sol" (Just "basic/whitelist.yaml")
      [ ("echidna_alwaystrue failed",                      passed      "echidna_alwaystrue")
      , ("echidna_revert_always failed",                   passed      "echidna_revert_always")
      , ("echidna_sometimesfalse passed",                  passed      "echidna_sometimesfalse")
      ]
  , testContract "basic/flags.sol" (Just "basic/whitelist_all.yaml")
      [ ("echidna_alwaystrue failed",                      passed      "echidna_alwaystrue")
      , ("echidna_revert_always failed",                   passed      "echidna_revert_always")
      , ("echidna_sometimesfalse passed",                  solved      "echidna_sometimesfalse")
      ]
  , testContract "basic/flags.sol" (Just "basic/blacklist.yaml")
      [ ("echidna_alwaystrue failed",                      passed      "echidna_alwaystrue")
      , ("echidna_revert_always failed",                   passed      "echidna_revert_always")
      , ("echidna_sometimesfalse passed",                  passed      "echidna_sometimesfalse")
      ]
  , testContract "basic/revert.sol" Nothing
      [ ("echidna_fails_on_revert passed", solved "echidna_fails_on_revert")
      , ("echidna_fails_on_revert didn't shrink to one transaction",
         solvedLen 1 "echidna_fails_on_revert")
      , ("echidna_revert_is_false didn't shrink to f(-1, 0x0, 0xdeadbeef)",
         solvedWith ("f", [AbiInt 256 (-1), AbiAddress 0, AbiAddress 0xdeadbeef]) "echidna_fails_on_revert")
      ]
  , testContract "basic/nearbyMining.sol" (Just "coverage/test.yaml")
      [ ("echidna_findNearby passed", solved "echidna_findNearby") ]
  , testContract' "basic/smallValues.sol" Nothing (Just "coverage/test.yaml") False
      [ ("echidna_findSmall passed", solved "echidna_findSmall") ]
  , testContract "basic/multisender.sol" (Just "basic/multisender.yaml") $
      [ ("echidna_all_sender passed",                      solved             "echidna_all_sender")
      , ("echidna_all_sender didn't shrink optimally",     solvedLen 3        "echidna_all_sender")
      ] ++ (["s1", "s2", "s3"] <&> \n ->
        ("echidna_all_sender solved without " ++ unpack n, solvedWith (n, []) "echidna_all_sender"))
  , testContract "basic/memory-reset.sol" Nothing
      [ ("echidna_memory failed",                  passed      "echidna_memory") ]
  , testContract "basic/contractAddr.sol" Nothing
      [ ("echidna_address failed",                 solved      "echidna_address") ]
  , testContract "basic/contractAddr.sol" (Just "basic/contractAddr.yaml")
      [ ("echidna_address failed",                 passed      "echidna_address") ]
  , testContract "basic/constants.sol"    Nothing
      [ ("echidna_found failed",                   solved      "echidna_found") ]
  , testContract "basic/constants2.sol"   Nothing
      [ ("echidna_found32 failed",                 solved      "echidna_found32") ]
  , testContract "basic/constants3.sol"   Nothing
      [ ("echidna_found_sender failed",            solved      "echidna_found_sender") ]
  , testContract "basic/rconstants.sol"   Nothing
      [ ("echidna_found failed",                   solved      "echidna_found") ]
  , testContract' "basic/cons-create-2.sol" (Just "C") Nothing True
      [ ("echidna_state failed",                   solved      "echidna_state") ]
-- single.sol is really slow and kind of unstable. it also messes up travis.
--  , testContract "coverage/single.sol"    (Just "coverage/test.yaml")
--      [ ("echidna_state failed",                   solved      "echidna_state") ]
  , testContract "coverage/multi.sol"     Nothing
      [ ("echidna_state3 failed",                  solved      "echidna_state3") ]
  , testContract "basic/balance.sol"      (Just "basic/balance.yaml")
      [ ("echidna_balance failed",                 passed      "echidna_balance") ]
  , testContract "basic/library.sol"      (Just "basic/library.yaml")
      [ ("echidna_library_call failed",            solved      "echidna_library_call") ]
  , testContract "basic/library.sol"      (Just "basic/library.yaml")
      [ ("echidna_valid_timestamp failed",         passed      "echidna_valid_timestamp") ]
  , testContract "basic/fallback.sol"     Nothing
      [ ("echidna_fallback failed",                solved      "echidna_fallback") ]
  , testContract "basic/darray.sol"       Nothing
      [ ("echidna_darray passed",                  solved      "echidna_darray")
      , ("echidna_darray didn't shrink optimally", solvedLen 1 "echidna_darray") ]
  , testContract "basic/propGasLimit.sol" (Just "basic/propGasLimit.yaml")
      [ ("echidna_runForever passed",              solved      "echidna_runForever") ]
  , testContract "basic/assert.sol"       (Just "basic/assert.yaml")
      [ ("echidna_set0 passed",                    solved      "ASSERTION set0")
      , ("echidna_set1 failed",                    passed      "ASSERTION set1") ]
  , testContract "basic/assert.sol"       (Just "basic/benchmark.yaml")
      [ ("coverage is empty",                      not . coverageEmpty         )
      , ("tests are not empty",                    testsEmpty                  ) ]
  , testContract "basic/constants.sol"    (Just "basic/benchmark.yaml")
      [ ("coverage is empty",                      not . coverageEmpty         )
      , ("tests are not empty",                    testsEmpty                  ) ]
  , testContract "basic/time.sol"         (Just "basic/time.yaml")
      [ ("echidna_timepassed passed",              solved      "echidna_timepassed") ]
  , testContract "basic/now.sol"         Nothing
      [ ("echidna_now passed",                     solved      "echidna_now") ]
  , testContract "basic/construct.sol"    Nothing
      [ ("echidna_construct passed",               solved      "echidna_construct") ]
  , testContract "basic/gasprice.sol"     Nothing
      [ ("echidna_state passed",                   solved      "echidna_state") ]
  , let fp = "basic_multicontract/contracts/Foo.sol"; cfg = Just "basic_multicontract/echidna_config.yaml" in
      testCase fp $
        do sv <- readProcess "solc" ["--version"] ""
           when ("Version: 0.4.25" `isInfixOf` sv) $ do
             c <- set (sConf . quiet) True <$> maybe (pure testConfig) (fmap _econfig . parseConfig) cfg
             res <- runContract fp (Just "Foo") c
             assertBool "echidna_test passed" $ solved "echidna_test" res
  , testContract' "basic/multi-abi.sol" (Just "B") (Just "basic/multi-abi.yaml") True
      [ ("echidna_test passed",                    solved      "echidna_test") ]
  , testContract "abiv2/Ballot.sol"       Nothing
      [ ("echidna_test passed",                    solved      "echidna_test") ]
  , testContract "abiv2/Dynamic.sol"      Nothing
      [ ("echidna_test passed",                    solved      "echidna_test") ]
  , testContract "abiv2/Dynamic2.sol"     Nothing
      [ ("echidna_test passed",                    solved      "echidna_test") ]
  , testContract "abiv2/MultiTuple.sol"   Nothing
      [ ("echidna_test passed",                    solved      "echidna_test") ]
  , testContract "basic/array-mutation.sol"   Nothing
      [ ("echidna_mutated passed",                 solved      "echidna_mutated") ]
  , testContract "basic/darray-mutation.sol"  Nothing
      [ ("echidna_mutated passed",                 solved      "echidna_mutated") ]
  , testContract "basic/gasuse.sol"       (Just "basic/gasuse.yaml")
      [ ("echidna_true failed",                    passed     "echidna_true")
      , ("g gas estimate wrong",                   gasInRange "g" 15000000 40000000)
      , ("f_close1 gas estimate wrong",            gasInRange "f_close1" 1800 2000)
      , ("f_open1 gas estimate wrong",             gasInRange "f_open1"  18000 23000)
      , ("push_b gas estimate wrong",              gasInRange "push_b"   39000 45000)
      ]
  ,  testContract "coverage/boolean.sol"       (Just "coverage/boolean.yaml")
      [ ("echidna_true failed",                    passed     "echidna_true")
      , ("unexpected corpus count ",               countCorpus 6)]
  ,  testContract "basic/payable.sol"     Nothing
      [ ("echidna_payable failed",                 solved      "echidna_payable") ]
  ,  checkConstructorConditions "basic/codesize.sol"
      "invalid codesize"
  ]

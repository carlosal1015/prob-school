{-# LANGUAGE TupleSections, DeriveFoldable, DeriveTraversable #-}
{-# OPTIONS -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}
module LogisticRegression where

import Dist
import Plot (renderToFile, plotTrajectory, plotHeatMap, binFloat, removeOutlierPairs)
import Data.Default (Default (def))
import Control.Applicative (liftA2)
import Control.Monad (replicateM, forM_, liftM)

--------------------------------------------------------------------------------
-- Generative model

logistic1DModel :: MonadDist m => Int
                -> m (Double, Double, [(Double, Bool)])
logistic1DModel n = do
  coeff0 <- normal 0 10
  coeff1 <- normal 0 10
  patients <- replicateM n (do
    score <- fmap (fromIntegral . (1+)) (discreteUniform 16)
    let b = coeff0 + coeff1 * score
        p = recip (1 + exp_ (-b))
    survival <- fromList [(True, p), (False, 1-p)]
    return (score, survival))
  return (coeff0, coeff1, patients)

-- Conditional distribution of observed data given latent parameters

logistic1DSynthesis :: MonadDist m => Int -> m [(Double, Bool)]
logistic1DSynthesis n = do
  let coeff0 = -6.9383
      coeff1 =  0.7124
  replicateM n (do
    score <- fmap (fromIntegral . (1+)) (discreteUniform 16)
    let b = coeff0 + coeff1 * score
        p = recip (1 + exp_ (-b))
    survival <- fromList [(True, p), (False, 1-p)]
    return (score, survival))

fakePatients :: [(Double, Bool)] -- logistic1DSynthesis produced this fake data
fakePatients = [ ( 4, False)
               , (13, True )
               , ( 4, False)
               , ( 5, False)
               , (13, True )
               , ( 3, False)
               , (13, True )
               , ( 5, False)
               , (14, True )
               , ( 1, False) ]

-- Conditional distribution of latent parameters given observed data

logistic1DRegression :: MonadDist m => [(Double, Bool)] -> m (Double, Double)
logistic1DRegression patients = do
  coeff0 <- normal 0 10
  coeff1 <- normal 0 10
  forM_ patients (\(score, survival) -> do
    let b = coeff0 + coeff1 * score
        p = recip (1 + exp_ (-b))
    -- survival' <- fromList [(True, p), (False, 1-p)]
    -- observe (survival == survival')
    factor (if survival then p else 1-p))
  return (coeff0, coeff1)

-- Infer latent parameters

main :: IO ()
main = do
  let m :: MonadDist m => m (Double, Double)
      m = logistic1DRegression fakePatients
  samplesIS <- tabSample 50000 m
  renderToFile def "/tmp/plotIS"
    $ plotHeatMap def (binFloat 50, binFloat 50)
    $ removeOutlierPairs samplesIS
  samplesMH <- liftM (drop 1000) (tabMH 50000 m)
  renderToFile def "/tmp/plotMH"
    $ plotTrajectory def
    $ samplesMH

--------------------------------------------------------------------------------
-- Generalizing logistic regression from 1D to 3D

data Trauma a = Trauma { ts, iss, age :: a }
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

instance Applicative Trauma where
  pure x = Trauma x x x
  Trauma f g h <*> Trauma x y z = Trauma (f x) (g y) (h z)
  _ *> t = t
  t <* _ = t

logistic3DModel :: MonadDist m => Int
                -> m (Double, Trauma Double, [(Trauma Double, Bool)])
logistic3DModel n = do
  coeff0 <- normal 0 10
  coeffs <- sequence (pure (normal 0 10))
  patients <- replicateM n (do
    scores <- fmap (fmap (fromIntegral :: Int -> Double))
            $ sequence (Trauma (fmap (1+) (discreteUniform 16))
                               ( (+) <$> discreteUniform 6 <*>
                                ((+) <$> discreteUniform 6 <*>
                                         discreteUniform 6) )
                               (discreteUniform 2))
    let b = coeff0 + sum (liftA2 (*) coeffs scores)
        p = recip (1 + exp_ (-b))
    survival <- fromList [(True, p), (False, 1-p)]
    return (scores, survival))
  return (coeff0, coeffs, patients)

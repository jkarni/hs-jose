-- Copyright (C) 2013, 2014, 2015, 2016  Fraser Tweedale
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# LANGUAGE MagicHash #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

{-|

Types to deal with the legacy JSON Web Key formats used with
Mozilla Persona.

-}
module Crypto.JOSE.Legacy
  (
    JWK'(..)
  , genJWK'
  , toJWK
  , RSKeyParameters()
  ) where

import Control.Lens hiding ((.=))
import Crypto.Number.Basic (log2)
import Data.Aeson
import Data.Aeson.Types
import qualified Data.Text as T
import Safe (readMay)

import Crypto.JOSE.JWA.JWK
import Crypto.JOSE.JWK
import qualified Crypto.JOSE.Types.Internal as Types
import Crypto.JOSE.Types
import Crypto.JOSE.TH


newtype StringifiedInteger = StringifiedInteger Integer
makePrisms ''StringifiedInteger

instance FromJSON StringifiedInteger where
  parseJSON = withText "StringifiedInteger" $
    maybe (fail "not an stringy integer") (pure . StringifiedInteger)
    . readMay
    . T.unpack

instance ToJSON StringifiedInteger where
  toJSON (StringifiedInteger n) = toJSON $ show n

b64Iso :: Iso' StringifiedInteger Base64Integer
b64Iso = _StringifiedInteger . from _Base64Integer

sizedB64Iso :: Iso' StringifiedInteger SizedBase64Integer
sizedB64Iso = iso
  ((\n -> SizedBase64Integer (size n) n) . view _StringifiedInteger)
  (\(SizedBase64Integer _ n) -> StringifiedInteger n)
  where
  size n =
    let (bytes, bits) = (log2 n + 1) `divMod` 8
    in bytes + signum bits


$(Crypto.JOSE.TH.deriveJOSEType "RS" ["RS"])


newtype RSKeyParameters = RSKeyParameters RSAKeyParameters
  deriving (Eq, Show)
makePrisms ''RSKeyParameters

instance FromJSON RSKeyParameters where
  parseJSON = withObject "RS" $ \o -> fmap RSKeyParameters $ RSAKeyParameters
    <$> ((o .: "algorithm" :: Parser RS) *> pure RSA)
    <*> (view sizedB64Iso <$> o .: "n")
    <*> (view b64Iso <$> o .: "e")
    <*> (fmap ((`RSAPrivateKeyParameters` Nothing) . view b64Iso) <$> (o .:? "d"))

instance ToJSON RSKeyParameters where
  toJSON (RSKeyParameters k)
    = object $
      [ "algorithm" .= RS
      , "n" .= (k ^. rsaN . from sizedB64Iso)
      , "e" .= (k ^. rsaE . from b64Iso)
      ]
      ++ maybe [] (\p -> ["d" .= (rsaD p ^. from b64Iso)])
        (k ^. rsaPrivateKeyParameters)


-- | Legacy JSON Web Key data type.
--
newtype JWK' = JWK' RSKeyParameters
  deriving (Eq, Show)
makePrisms ''JWK'

instance FromJSON JWK' where
  parseJSON = withObject "JWK'" $ \o -> JWK' <$> parseJSON (Object o)

instance ToJSON JWK' where
  toJSON (JWK' k) = object $ Types.objectPairs (toJSON k)

instance AsPublicKey JWK' where
  asPublicKey = prism' id (_JWK' (_RSKeyParameters (preview asPublicKey)))

genJWK' :: MonadRandom m => Int -> m JWK'
genJWK' size = JWK' . RSKeyParameters <$> genRSA size

toJWK :: JWK' -> JWK
toJWK (JWK' (RSKeyParameters k)) = fromKeyMaterial $ RSAKeyMaterial k

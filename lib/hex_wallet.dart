import 'dart:convert';
import 'dart:typed_data';

import 'package:bitcoin_flutter/bitcoin_flutter.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart';
import 'package:sacco/models/export.dart';
import 'package:sacco/utils/bech32_encoder.dart';

import 'utils/tx_signer.dart';

/// Represents a wallet which contains the hex private key, the hex public key
/// and the hex address.
/// In order to create one properly, the [HexWallet.derive] method should always
/// be used.
/// The associated [networkInfo] will be used when computing the [bech32Address]
/// associated with the wallet.
class HexWallet {
  final NetworkInfo networkInfo;

  final Uint8List address; // Hex address
  final Uint8List privateKey; // Hex private key
  final Uint8List publicKey; // Hex public key

  HexWallet({
    @required this.networkInfo,
    @required this.address,
    @required this.privateKey,
    @required this.publicKey,
  })  : assert(networkInfo != null),
        assert(privateKey != null),
        assert(publicKey != null);

  /// Derives the private key from the given [mnemonic] using the specified
  /// [derivationPath].
  factory HexWallet.derive(
    List<String> mnemonic,
    String derivationPath,
    NetworkInfo networkInfo,
  ) {
    // Get the seed as a string
    final seed = bip39.mnemonicToSeed(mnemonic.join(' '));

    // Get the HD models.wallet from the seed
    final mainNode = HDWallet.fromSeed(seed);

    // Get the node from the derivation path
    final derivedNode = mainNode.derivePath(derivationPath);

    // Get the curve data
    final secp256k1 = ECCurve_secp256k1();
    final point = secp256k1.G;

    // Compute the curve point associated to the private key
    final bigInt = BigInt.parse(derivedNode.privKey, radix: 16);
    final curvePoint = point * bigInt;

    // Get the public key
    final publicKeyBytes = curvePoint.getEncoded();

    // Get the address
    final sha256Digest = SHA256Digest().process(publicKeyBytes);
    final address = RIPEMD160Digest().process(sha256Digest);

    // Return the key bytes
    return HexWallet(
      address: address,
      publicKey: publicKeyBytes,
      privateKey: HEX.decode(derivedNode.privKey),
      networkInfo: networkInfo,
    );
  }

  /// Returns the associated [address] as a Bech32 string.
  String get bech32Address =>
      Bech32Encoder.encode(networkInfo.bech32Hrp, address);

  /// Returns the associated [privateKey] as an [ECPrivateKey] instance.
  ECPrivateKey get ecPrivateKey {
    final privateKeyInt = BigInt.parse(HEX.encode(privateKey), radix: 16);
    return ECPrivateKey(privateKeyInt, ECCurve_secp256k1());
  }

  /// Returns the associated [publicKey] as an [ECPublicKey] instance.
  ECPublicKey get ecPublicKey {
    final secp256k1 = ECCurve_secp256k1();
    final point = secp256k1.G;
    final curvePoint = point * ecPrivateKey.d;
    return ECPublicKey(curvePoint, ECCurve_secp256k1());
  }

  /// Signs the given [data] using the associated [privateKey].
  Uint8List signTxData(String data) {
    // Create a Sha256 of the message
    final bytes = utf8.encode(data);
    final hash = SHA256Digest().process(bytes);

    // Compute the signature
    return TransactionSigner.deriveFrom(hash, ecPrivateKey, ecPublicKey);
  }
}
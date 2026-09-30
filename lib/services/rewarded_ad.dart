import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// One Google rewarded ad through AdMob (movies PRD #15, earn screen). The server decides the reward, not this:
/// [customData] and [userId] ride on the ad as server-side verification options, so Google's own callback to
/// the user service (earn/admob.js) names the impression /earn/start opened. [RewardedAdResult.earned] only
/// tells the screen whether to ask the server yet.
class RewardedAdResult {
  const RewardedAdResult({required this.earned, this.error});
  final bool earned;
  final String? error;
}

class RewardedAds {
  RewardedAds._();

  static Future<InitializationStatus>? _init;

  static Future<RewardedAdResult> show({
    required String unit,
    required String customData,
    required String userId,
  }) async {
    try {
      await (_init ??= MobileAds.instance.initialize());
    } catch (e) {
      _init = null;
      return RewardedAdResult(earned: false, error: 'Google ads could not start: $e');
    }
    final loaded = Completer<RewardedAd?>();
    String? loadError;
    await RewardedAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (error) {
          loadError = error.message;
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future;
    if (ad == null) return RewardedAdResult(earned: false, error: 'No Google ad right now${loadError != null ? ' ($loadError)' : ''}');

    await ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId, customData: customData));
    var earned = false;
    final closed = Completer<String?>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(null);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(error.message);
      },
    );
    await ad.show(onUserEarnedReward: (_, reward) {
      earned = true;
      debugPrint('admob reward ${reward.amount} ${reward.type}');
    });
    final error = await closed.future;
    return RewardedAdResult(earned: earned, error: error);
  }
}

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class AdBlocker {
  static final List<String> adDomains = [
    ".fonts.googleapis.com",
    ".fonts.gstatic.com",
    ".doubleclick.net",
    ".googlesyndication.com",
    ".googleadservices.com",
    ".adservice.google.com",
    ".amazon-adsystem.com",
    ".adsafeprotected.com",
    ".crwdcntrl.net",
    ".criteo.com",
    ".rubiconproject.com",
    ".casalemedia.com",
    ".pubmatic.com",
    ".openx.net",
    ".advertising.com",
    ".moatads.com",
    ".scorecardresearch.com",
    ".outbrain.com",
    ".taboola.com",
    ".quantserve.com",
    ".smartadserver.com",
    ".adsrvr.org",
    ".yieldoptimizer.com",
    ".demdex.net",
    ".soundcloud.com",
    "w.soundcloud.com",
  ];

  static List<ContentBlocker> get contentBlockers {
    final List<ContentBlocker> blockers = [];
    for (final domain in adDomains) {
      blockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".*$domain/.*",
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
        ),
      ));
    }
    
    // Additional blocker to hide known ad elements in case we missed their domain
    blockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: ".*",
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector: ".ad, .ads, .ad-unit, .google-auto-placed, iframe[src*='ads'], iframe[src*='doubleclick'], iframe[src*='soundcloud'], .scp-container, #scmframe, .scm-player, #scmPlayer, .spotify, iframe[src*='spotify']",
      ),
    ));

    return blockers;
  }
}

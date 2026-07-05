/// Translates raw yt-dlp errors into messages a non-technical user can act
/// on. Unrecognized errors pass through unchanged.
String friendlyEngineError(String raw) {
  final r = raw.toLowerCase();
  if (r.contains('unsupported url')) {
    return 'This link is not from a supported video site.';
  }
  if (r.contains('is not a valid url')) {
    return 'That does not look like a valid link.';
  }
  if (r.contains('private video')) {
    return 'This video is private.';
  }
  if (r.contains('video unavailable') || r.contains('content isn’t available')) {
    return 'This video is unavailable. It may have been removed or blocked in your region.';
  }
  if (r.contains('sign in to confirm your age') || r.contains('age-restricted')) {
    return 'This video is age-restricted and needs a signed-in account, which is not supported yet.';
  }
  if (r.contains('sign in') || r.contains('login required') || r.contains('members-only')) {
    return 'This video needs a signed-in account, which is not supported yet.';
  }
  if (r.contains('429') || r.contains('too many requests')) {
    return 'The site is limiting requests right now. Wait a few minutes and try again.';
  }
  if (r.contains('http error 403')) {
    return 'The site refused the download. Updating the engine in Settings usually fixes this.';
  }
  if (r.contains('is a live') || r.contains('live event') || r.contains('premieres in')) {
    return 'Live streams and premieres are not supported yet.';
  }
  if (r.contains('getaddrinfo') ||
      r.contains('failed to resolve') ||
      r.contains('network is unreachable') ||
      r.contains('nodename nor servname')) {
    return 'No internet connection.';
  }
  return raw;
}

Future<int> getNtpOffset({
  required String lookUpAddress,
  required Duration timeout,
}) => Future.error(UnsupportedError('UDP NTP is unavailable in browsers'));

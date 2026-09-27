import 'package:ntp/ntp.dart';

Future<int> getNtpOffset({
  required String lookUpAddress,
  required Duration timeout,
}) => NTP.getNtpOffset(lookUpAddress: lookUpAddress, timeout: timeout);

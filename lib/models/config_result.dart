class ConfigResult {
  final String privacyUrl;
  final String agreementUrl;

  const ConfigResult({required this.privacyUrl, required this.agreementUrl});

  factory ConfigResult.fromJson(Map<String, dynamic> json) {
    return ConfigResult(
      privacyUrl: json['privacyUrl']?.toString() ?? '',
      agreementUrl: json['agreementUrl']?.toString() ?? '',
    );
  }
}

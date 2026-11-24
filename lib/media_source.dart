/// Network URLs are explicit HTTP(S) addresses. Local paths come from the picker.
Uri? parseNetworkSource(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !{'https', 'http'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

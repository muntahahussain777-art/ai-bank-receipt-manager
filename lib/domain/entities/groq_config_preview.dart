/// A sample Groq slot. Phase 1 does not store a key or call the API.
class GroqConfigPreview {
  const GroqConfigPreview({
    required this.label,
    required this.modelHint,
    required this.endpoint,
  });

  final String label;
  final String modelHint;
  final String endpoint;
}

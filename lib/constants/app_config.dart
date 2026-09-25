/// Centralized application configuration.
class AppConfig {
  // KEYWORD TO EDIT: supportContactUrl
  static const String supportContactUrl = "https://formspree.io/f/xdeoppog";

  // Gemini AI Models Configuration
  static const String geminiModelName = 'gemini-3.1-pro-preview';
  static const String geminiPrimaryModel = geminiModelName;
  static const List<String> geminiCandidateModels = [
    geminiModelName,
    'gemini-2.5-flash',
  ];
}

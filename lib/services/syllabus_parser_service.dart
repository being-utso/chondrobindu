import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../core/constants/app_constants.dart';
import '../models/syllabus_node.dart';

/// Priority pool of Gemini AI models for dynamic failover during syllabus extraction.
const List<String> kGeminiModelPriorityPool = [
  'gemini-2.5-flash',
  'gemini-1.5-flash',
  'gemini-1.5-pro',
];

/// Type definition for testable AI model invoker
typedef GeminiModelInvoker = Future<String> Function(String modelName);

/// Service providing atomic topic decomposition and dynamic multi-model failover
/// for course syllabus ingestion.
class SyllabusParserService {
  /// Builds the text prompt with strict atomic topic decomposition rules.
  static String buildExtractionPrompt(String outlineText) {
    return '''Extract the course syllabus structure (Chapters/Modules, Topics, and Checklist Items) from the following course outline text.
Do NOT generate an artificial root container or generic "Section 1" wrapper.

CRITICAL RULE — ATOMIC TOPIC DECOMPOSITION: Never bundle multiple topics, concepts, theorems, or methods into a single item. If the source syllabus groups items with commas, semicolons, bullets, or conjunctions (e.g., 'A, B and C', 'Evaluation of indeterminate forms by L'Hospital's rule, Partial differentiation, Euler's theorem'), you MUST break them into separate, individual topic objects under the parent chapter.
Each leaf topic item must represent exactly ONE discrete learnable subject or theorem.

Return ONLY a valid JSON array matching this exact schema:
[
  {
    "title": "Differential Calculus",
    "topics": [
      {
        "title": "Leibnitz's theorem"
      },
      {
        "title": "Rolle's theorem"
      },
      {
        "title": "Mean value theorem"
      },
      {
        "title": "Taylor's theorem"
      },
      {
        "title": "Maclaurin's theorem"
      }
    ]
  }
]
Do NOT include markdown formatting, backticks, or any conversational text. Return ONLY the raw JSON array.

Course Outline Text:
$outlineText''';
  }

  /// Builds the vision prompt with strict atomic topic decomposition rules.
  static String buildVisionPrompt() {
    return '''Extract the course syllabus structure (Chapters/Modules, Topics, and Checklist Items) from this syllabus outline image.
Do NOT generate an artificial root container or generic "Section 1" wrapper.

CRITICAL RULE — ATOMIC TOPIC DECOMPOSITION: Never bundle multiple topics, concepts, theorems, or methods into a single item. If the source syllabus groups items with commas, semicolons, bullets, or conjunctions (e.g., 'A, B and C', 'Evaluation of indeterminate forms by L'Hospital's rule, Partial differentiation, Euler's theorem'), you MUST break them into separate, individual topic objects under the parent chapter.
Each leaf topic item must represent exactly ONE discrete learnable subject or theorem.

Return ONLY a valid JSON array matching this exact schema:
[
  {
    "title": "Differential Calculus",
    "topics": [
      {
        "title": "Leibnitz's theorem"
      },
      {
        "title": "Rolle's theorem"
      },
      {
        "title": "Mean value theorem"
      },
      {
        "title": "Taylor's theorem"
      },
      {
        "title": "Maclaurin's theorem"
      }
    ]
  }
]
Do NOT include markdown formatting, backticks, or any conversational text. Return ONLY the raw JSON array.''';
  }

  /// Regex pattern to detect paired theorems or concepts with pluralized nouns
  /// e.g. "Taylor's and Maclaurin's theorems" -> "Taylor's theorem", "Maclaurin's theorem"
  static final RegExp _pairedTheoremsRegex = RegExp(
    r"^([A-Z][a-zA-Z'\s\-]+?)\s+(?:and|&)\s+([A-Z][a-zA-Z'\s\-]+?)\s+(theorems?|methods?|laws?|rules?|equations?|formulas?|algorithms?|curves?|approaches?|experiments?|tests?)$",
    caseSensitive: false,
  );

  /// Prepositional or introductory patterns that connect compound phrases that should NOT be split
  /// e.g. "Properties and applications of matrices", "Definition and types of vectors"
  static final RegExp _nonSplittableCompoundPrefix = RegExp(
    r'^(?:Properties|Applications|Definition|Definitions|Types|Concept|Concepts|Introduction|Overview|Scope|Basics|Principles)\s+(?:and|&)\s+\w+\s+(?:of|in|for|to|with|by|on)\b',
    caseSensitive: false,
  );

  /// Known compound terms that should never be split on conjunction
  static const Set<String> _knownCompoundPhrases = {
    'research and development',
    'trial and error',
    'search and sort',
    'hardware and software',
    'set and map',
    'syntax and semantics',
    'plug and play',
    'loss and gain',
    'input and output',
    'divide and conquer',
    'breadth and depth',
    'rock and roll',
  };

  /// Client-Side Topic Sanitizer (Safety Net):
  /// Decomposes compound titles with commas, semicolons, or distinct clauses
  /// into individual atomic topic strings.
  static List<String> decomposeTopicTitle(String rawTitle) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) return [];

    // Quick pass: If title doesn't contain commas, semicolons, newlines, or conjunctions
    if (!trimmed.contains(',') &&
        !trimmed.contains(';') &&
        !trimmed.contains('\n') &&
        !RegExp(r'\b(and|&)\b', caseSensitive: false).hasMatch(trimmed)) {
      final clean = _cleanSegment(trimmed);
      return clean.isNotEmpty ? [clean] : [];
    }

    // Check for paired theorem pattern at the root: e.g. "Taylor's and Maclaurin's theorems"
    final directPaired = _checkPairedTheorems(trimmed);
    if (directPaired != null) {
      return directPaired;
    }

    // Split by top-level delimiters (semicolons, newlines, and commas outside parentheses/numbers)
    final delimiterSegments = _splitByDelimiters(trimmed);

    final List<String> results = [];
    for (final seg in delimiterSegments) {
      final cleanSeg = _cleanSegment(seg);
      if (cleanSeg.isEmpty) continue;

      // Check if this segment contains paired theorems
      final pairedSub = _checkPairedTheorems(cleanSeg);
      if (pairedSub != null) {
        results.addAll(pairedSub);
        continue;
      }

      // Check if segment should be decomposed on conjunction ('and' / '&')
      if (_shouldSplitOnConjunction(cleanSeg)) {
        final subSegments = _splitOnConjunction(cleanSeg);
        for (final sub in subSegments) {
          final c = _cleanSegment(sub);
          if (c.isNotEmpty) results.add(c);
        }
      } else {
        results.add(cleanSeg);
      }
    }

    return results.isNotEmpty ? results : [_cleanSegment(trimmed)];
  }

  /// Checks if a string matches the paired theorem/method pattern and singularizes the noun.
  static List<String>? _checkPairedTheorems(String text) {
    final match = _pairedTheoremsRegex.firstMatch(text.trim());
    if (match == null) return null;

    final p1 = match.group(1)!.trim();
    final p2 = match.group(2)!.trim();
    var noun = match.group(3)!.trim();

    // Singularize plural noun (e.g. "theorems" -> "theorem", "laws" -> "law")
    if (noun.toLowerCase().endsWith('s') && !noun.toLowerCase().endsWith('ss')) {
      noun = noun.substring(0, noun.length - 1);
    }

    return [
      _cleanSegment('$p1 $noun'),
      _cleanSegment('$p2 $noun'),
    ];
  }

  /// Splits a string by semicolons, newlines, and commas (excluding commas inside parentheses or numbers).
  static List<String> _splitByDelimiters(String text) {
    final List<String> segments = [];
    final StringBuffer buffer = StringBuffer();
    int parenDepth = 0;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (char == '(' || char == '[' || char == '{') {
        parenDepth++;
        buffer.write(char);
      } else if (char == ')' || char == ']' || char == '}') {
        if (parenDepth > 0) parenDepth--;
        buffer.write(char);
      } else if ((char == ';' || char == '\n') && parenDepth == 0) {
        final seg = buffer.toString().trim();
        if (seg.isNotEmpty) segments.add(seg);
        buffer.clear();
      } else if (char == ',' && parenDepth == 0) {
        // Guard against numbers like 1,000 or abbreviations
        final isNumberComma = i > 0 &&
            i < text.length - 1 &&
            RegExp(r'\d').hasMatch(text[i - 1]) &&
            RegExp(r'\d').hasMatch(text[i + 1]);

        if (isNumberComma) {
          buffer.write(char);
        } else {
          final seg = buffer.toString().trim();
          if (seg.isNotEmpty) segments.add(seg);
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      segments.add(remaining);
    }

    return segments;
  }

  /// Evaluates whether a segment should be split on conjunction ('and' / '&').
  static bool _shouldSplitOnConjunction(String seg) {
    final lower = seg.toLowerCase().trim();
    if (!RegExp(r'\b(and|&)\b', caseSensitive: false).hasMatch(seg)) {
      return false;
    }

    // Exclude known non-splittable compounds
    if (_knownCompoundPhrases.contains(lower)) {
      return false;
    }

    // Exclude phrases like "Properties and applications of matrices"
    if (_nonSplittableCompoundPrefix.hasMatch(seg)) {
      return false;
    }

    // Exclude phrases where 'and' connects two simple nouns under a single preposition
    if (RegExp(r'\b(?:and|&)\s+\w+\s+(?:of|in|for|to|with|by|on)\b', caseSensitive: false).hasMatch(seg)) {
      return false;
    }

    // If string contains multiple distinct methods/theorems e.g. "Breadth-first search and depth-first search"
    // or both sides exceed threshold length (>= 28 chars overall, with both sides >= 10 chars)
    final parts = seg.split(RegExp(r'\s+(?:and|&)\s+', caseSensitive: false));
    if (parts.length == 2) {
      final left = parts[0].trim();
      final right = parts[1].trim();
      if (left.length >= 10 && right.length >= 10 && seg.length >= 26) {
        // Ensure neither side ends or starts with a dangling preposition
        final leftEndsWithPrep = RegExp(r'\b(of|in|for|to|with|by|on|from)\s*$', caseSensitive: false).hasMatch(left);
        final rightStartsWithPrep = RegExp(r'^\s*(of|in|for|to|with|by|on|from)\b', caseSensitive: false).hasMatch(right);
        if (!leftEndsWithPrep && !rightStartsWithPrep) {
          return true;
        }
      }
    }

    return false;
  }

  /// Splits on 'and' / '&' conjunction.
  static List<String> _splitOnConjunction(String seg) {
    return seg
        .split(RegExp(r'\s+(?:and|&)\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Cleans a segment by stripping leading bullet/numbering artifacts,
  /// stripping trailing punctuation, and capitalizing the first character.
  static String _cleanSegment(String seg) {
    var s = seg.trim();
    if (s.isEmpty) return '';

    // Strip leading numbering: "1.", "1)", "(1)", "[a]", "1 -", etc.
    s = s.replaceAll(
      RegExp(r'^(?:(?:\d+|[a-zA-Z]|\([0-9a-zA-Z]+\)|\[[0-9a-zA-Z]+\])[\.\)\:\-]\s*|[-*•–—]\s*)+'),
      '',
    );

    // Strip trailing punctuation
    s = s.replaceAll(RegExp(r'[,;:\.\s]+$'), '');
    s = s.trim();
    if (s.isEmpty) return '';

    // Capitalize first letter if lowercase (e.g. "bisection method" -> "Bisection method")
    if (s.isNotEmpty && s[0] == s[0].toLowerCase() && s[0] != s[0].toUpperCase()) {
      s = s[0].toUpperCase() + s.substring(1);
    }

    return s;
  }

  /// Post-processing parsing hook that inspects all extracted leaf items
  /// and decomposes compound topics into standalone `SyllabusNode` items.
  static List<SyllabusNode> sanitizeTopicNodes(
    List<SyllabusNode> rawTopicNodes, {
    String? parentId,
  }) {
    final List<SyllabusNode> sanitizedNodes = [];

    for (final node in rawTopicNodes) {
      final decomposedTitles = decomposeTopicTitle(node.title);

      if (decomposedTitles.isEmpty) {
        continue;
      }

      if (decomposedTitles.length == 1) {
        // Single atomic topic: preserve or update title
        sanitizedNodes.add(
          node.copyWith(
            title: decomposedTitles.first,
            isLeaf: true,
            parentId: parentId,
          ),
        );
      } else {
        // Multiple atomic topics decomposed from compound item:
        // Create an individual standalone SyllabusNode for each decomposed concept
        for (final title in decomposedTitles) {
          final clonedMaterials = node.children.map((child) {
            return child.copyWith(
              id: generateUniqueNodeId('item'),
              parentId: null,
            );
          }).toList();

          sanitizedNodes.add(
            SyllabusNode(
              id: generateUniqueNodeId('topic'),
              title: title,
              isLeaf: true,
              isCompleted: false,
              parentId: parentId,
              children: clonedMaterials,
            ),
          );
        }
      }
    }

    return sanitizedNodes;
  }

  /// Sanitizes all chapters by running atomic topic decomposition on each chapter's children.
  static List<SyllabusNode> sanitizeChapterNodes(List<SyllabusNode> chapterNodes) {
    final List<SyllabusNode> result = [];

    for (final chapter in chapterNodes) {
      final sanitizedTopics = sanitizeTopicNodes(chapter.children, parentId: chapter.id);
      result.add(
        chapter.copyWith(
          children: sanitizedTopics,
        ),
      );
    }

    return result;
  }

  /// Decodes raw JSON response from Gemini, builds chapter & topic nodes,
  /// and applies atomic topic decomposition as a client-side safety net.
  static List<SyllabusNode> parseSyllabusJsonResponse(String rawResponseText) {
    String cleanJson = rawResponseText.trim();
    final codeFenceRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
    final fenceMatch = codeFenceRegex.firstMatch(cleanJson);
    if (fenceMatch != null && fenceMatch.group(1) != null) {
      cleanJson = fenceMatch.group(1)!.trim();
    } else {
      final startIdx = cleanJson.indexOf('[');
      final endIdx = cleanJson.lastIndexOf(']');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        cleanJson = cleanJson.substring(startIdx, endIdx + 1).trim();
      }
    }

    final dynamic decodedJson = jsonDecode(cleanJson);
    if (decodedJson is! List) {
      throw const FormatException('Expected a JSON array of sections/chapters.');
    }
    final List<dynamic> decodedList = decodedJson;

    final List<SyllabusNode> chapterNodes = [];
    for (final chapterObj in decodedList) {
      if (chapterObj is! Map) continue;
      final chapterMap = Map<String, dynamic>.from(chapterObj);
      final chapterTitle = (chapterMap['title'] ??
              chapterMap['chapterName'] ??
              chapterMap['sectionName'] ??
              'Chapter')
          .toString()
          .trim();
      final rawTopics = chapterMap['topics'] ?? chapterMap['items'] ?? [];

      final List<SyllabusNode> topicNodes = [];
      if (rawTopics is List) {
        for (final t in rawTopics) {
          if (t is Map) {
            final tMap = Map<String, dynamic>.from(t);
            final topicTitle = (tMap['title'] ?? tMap['topicName'] ?? tMap['name'] ?? 'Topic')
                .toString()
                .trim();
            final rawItems = (tMap['items'] as List<dynamic>?) ?? [];

            final List<SyllabusNode> materialNodes = rawItems.map((m) {
              final mStr = (m is Map ? (m['title'] ?? m['name'] ?? m.toString()) : m).toString().trim();
              return SyllabusNode(
                title: mStr,
                isLeaf: true,
                isCompleted: false,
              );
            }).where((m) => m.title.isNotEmpty).toList();

            if (topicTitle.isNotEmpty || materialNodes.isNotEmpty) {
              topicNodes.add(
                SyllabusNode(
                  title: topicTitle.isNotEmpty ? topicTitle : 'Topic',
                  isLeaf: true,
                  isCompleted: false,
                  children: materialNodes,
                ),
              );
            }
          } else {
            final tStr = t.toString().trim();
            if (tStr.isNotEmpty) {
              topicNodes.add(
                SyllabusNode(
                  title: tStr,
                  isLeaf: true,
                  isCompleted: false,
                ),
              );
            }
          }
        }
      }

      if (chapterTitle.isNotEmpty || topicNodes.isNotEmpty) {
        chapterNodes.add(
          SyllabusNode(
            title: chapterTitle.isNotEmpty ? chapterTitle : 'Chapter',
            isLeaf: false,
            children: topicNodes,
          ),
        );
      }
    }

    // Post-processing safety net: sanitize all chapters and atomically decompose compound topics
    return sanitizeChapterNodes(chapterNodes);
  }

  /// Dynamic multi-model AI failover pipeline across [kGeminiModelPriorityPool].
  ///
  /// Iterates through the priority pool in order. If a model encounters a rate limit (429),
  /// quota depletion, server error (500/503), or times out, it is silently caught
  /// and execution is promoted to the next model transparently to the user.
  static Future<String> extractSyllabusWithFailover({
    String? promptText,
    Uint8List? imageBytes,
    String? apiKey,
    List<String> modelPool = kGeminiModelPriorityPool,
    GeminiModelInvoker? testModelInvoker,
  }) async {
    final effectiveApiKey = (apiKey != null && apiKey.isNotEmpty)
        ? apiKey
        : AppConstants.geminiApiKey;

    Object? lastError;
    StackTrace? lastStack;

    for (int i = 0; i < modelPool.length; i++) {
      final modelName = modelPool[i];
      debugPrint('[SyllabusAI] Attempting extraction with priority model ($i): $modelName');

      try {
        final String rawResponse;

        if (testModelInvoker != null) {
          rawResponse = await testModelInvoker(modelName);
        } else {
          final model = GenerativeModel(
            model: modelName,
            apiKey: effectiveApiKey,
          );

          final GenerateContentResponse response;
          if (imageBytes != null) {
            response = await model.generateContent([
              Content.multi([
                TextPart(buildVisionPrompt()),
                DataPart('image/jpeg', imageBytes),
              ]),
            ]);
          } else {
            response = await model.generateContent([
              Content.text(promptText ?? buildExtractionPrompt('')),
            ]);
          }

          rawResponse = response.text ?? '';
        }

        if (rawResponse.trim().isNotEmpty) {
          debugPrint('[SyllabusAI] Model $modelName succeeded! Returning parsed response.');
          return rawResponse;
        }

        debugPrint('[SyllabusAI] Model $modelName returned empty text. Promoting to next candidate model...');
      } catch (e, s) {
        lastError = e;
        lastStack = s;
        // Silent error handling: transparently log and advance without triggering UI errors
        debugPrint('[SyllabusAI] Model $modelName failed silently ($e). Promoting to next candidate in pool...');
      }
    }

    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
    throw lastError ?? Exception('All AI models in the failover pool were exhausted without a response.');
  }
}

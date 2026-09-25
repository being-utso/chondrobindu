import '../models/course_model.dart';

/// Dynamic Course Sorting & Utility Service
class CourseService {
  /// Extracts the numerical component from a course code (e.g., "EEE 101" -> 101, "CE 106" -> 106, "MATH 159" -> 159).
  /// If no digits are found, returns 99999 so non-numbered courses sort predictably at the end.
  static int extractCourseNumber(String code) {
    final match = RegExp(r'\d+').firstMatch(code);
    return match != null ? int.tryParse(match.group(0)!) ?? 99999 : 99999;
  }

  /// Compares two course code strings dynamically by their numeric component,
  /// falling back to alphabetical comparison when numeric parts match.
  static int compareCourseCodes(String codeA, String codeB) {
    final numA = extractCourseNumber(codeA);
    final numB = extractCourseNumber(codeB);
    if (numA != numB) return numA.compareTo(numB);
    return codeA.toLowerCase().compareTo(codeB.toLowerCase());
  }

  /// Dynamically sorts a list of [CourseModel] by their course code numerical value.
  static List<CourseModel> sortCoursesDynamically(List<CourseModel> courses) {
    final sorted = List<CourseModel>.from(courses);
    sorted.sort((a, b) {
      final numA = extractCourseNumber(a.code);
      final numB = extractCourseNumber(b.code);
      if (numA != numB) return numA.compareTo(numB);
      return a.code.toLowerCase().compareTo(b.code.toLowerCase());
    });
    return sorted;
  }

  /// Dynamically sorts any list of items using an extracted course code string.
  static List<T> sortByCourseCode<T>(List<T> items, String Function(T item) codeSelector) {
    final sorted = List<T>.from(items);
    sorted.sort((a, b) => compareCourseCodes(codeSelector(a), codeSelector(b)));
    return sorted;
  }
}

/// Top-level helper functions for direct import convenience
int extractCourseNumber(String code) => CourseService.extractCourseNumber(code);
int compareCourseCodes(String a, String b) => CourseService.compareCourseCodes(a, b);
List<CourseModel> sortCoursesDynamically(List<CourseModel> courses) => CourseService.sortCoursesDynamically(courses);

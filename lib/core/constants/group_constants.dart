/// Dynamic group constants and helper mappings for Science, Humanities, and Commerce groups.
class GroupConstants {
  static const String science = 'Science';
  static const String humanities = 'Humanities';
  static const String commerce = 'Commerce';

  static const List<String> hscGroups = [science, humanities, commerce];

  /// Returns valid target goals for a given HSC Group
  static List<String> getTargetsForGroup(String group) {
    switch (group) {
      case humanities:
        return const [
          'Varsity B Unit',
          'Varsity C Unit',
          'IBA Prep',
          'HSC Candidate / Board Exam',
        ];
      case commerce:
        return const [
          'Varsity C Unit',
          'Varsity B Unit',
          'IBA Prep',
          'HSC Candidate / Board Exam',
        ];
      case science:
      default:
        return const [
          'Engineering (BUET, CKRUET)',
          'Medical (MBBS & BDS)',
          'Varsity A Unit',
          'Varsity B Unit',
          'Varsity C Unit',
          'IBA Prep',
          'HSC Candidate / Board Exam',
        ];
    }
  }

  /// Returns dynamic exam subjects list for scheduling/logging exams based on user's group and target
  static List<String> getExamSubjectsForUser(String group, String target) {
    final Map<String, List<String>> groupHscSubjects = {
      science: const [
        'Physics 1st Paper',
        'Physics 2nd Paper',
        'Chemistry 1st Paper',
        'Chemistry 2nd Paper',
        'Higher Mathematics 1st Paper',
        'Higher Mathematics 2nd Paper',
        'Biology 1st Paper',
        'Biology 2nd Paper',
        'Bangla 1st Paper',
        'Bangla 2nd Paper',
        'English 1st Paper',
        'English 2nd Paper',
        'ICT',
      ],
      humanities: const [
        'Bangla 1st Paper (বাংলা ১ম পত্র)',
        'Bangla 2nd Paper (বাংলা ২য় পত্র)',
        'English 1st Paper (ইংরেজি ১ম পত্র)',
        'English 2nd Paper (ইংরেজি ২য় পত্র)',
        'ICT (তথ্য ও যোগাযোগ প্রযুক্তি)',
        'Civics & Good Governance 1st Paper (পৌরনীতি ও সুশাসন ১ম)',
        'Civics & Good Governance 2nd Paper (পৌরনীতি ও সুশাসন ২য়)',
        'Economics 1st Paper (অর্থনীতি ১ম পত্র)',
        'Economics 2nd Paper (অর্থনীতি ২য় পত্র)',
        'History 1st Paper (ইতিহাস ১ম পত্র)',
        'History 2nd Paper (ইতিহাস ২য় পত্র)',
        'Geography 1st Paper (ভূগোল ১ম পত্র)',
        'Geography 2nd Paper (ভূগোল ২য় পত্র)',
      ],
      commerce: const [
        'Bangla 1st Paper (বাংলা ১ম পত্র)',
        'Bangla 2nd Paper (বাংলা ২য় পত্র)',
        'English 1st Paper (ইংরেজি ১ম পত্র)',
        'English 2nd Paper (ইংরেজি ২য় পত্র)',
        'ICT (তথ্য ও যোগাযোগ প্রযুক্তি)',
        'Accounting 1st Paper (হিসাববিজ্ঞান ১ম পত্র)',
        'Accounting 2nd Paper (হিসাববিজ্ঞান ২য় পত্র)',
        'Business Organization & Management 1st Paper (ব্যবসায় সংগঠন ও ব্যবস্থাপনা ১ম)',
        'Business Organization & Management 2nd Paper (ব্যবসায় সংগঠন ও ব্যবস্থাপনা ২য়)',
        'Finance, Banking & Insurance 1st Paper (ফিন্যান্স, ব্যাংকিং ও বীমা ১ম)',
        'Finance, Banking & Insurance 2nd Paper (ফিন্যান্স, ব্যাংকিং ও বীমা ২য়)',
        'Production Management & Marketing 1st Paper (উৎপাদন ব্যবস্থাপনা ও বিপণন ১ম)',
        'Production Management & Marketing 2nd Paper (উৎপাদন ব্যবস্থাপনা ও বিপণন ২য়)',
      ],
    };

    final hscList = groupHscSubjects[group] ?? groupHscSubjects[science]!;
    final extraAdmissionSubjects = <String>[];
    final loweredTarget = target.toLowerCase();

    if (loweredTarget.contains('iba') || loweredTarget.contains('bba')) {
      extraAdmissionSubjects.addAll([
        'English Language & Communication',
        'Mathematical Aptitude',
        'Analytical Ability',
      ]);
    } else if (loweredTarget.contains('versity b') || loweredTarget.contains('varsity b')) {
      extraAdmissionSubjects.addAll(['General Knowledge (সাধারণ জ্ঞান)', 'Bangla', 'English']);
    } else if (loweredTarget.contains('medical') || loweredTarget.contains('mbbs')) {
      extraAdmissionSubjects.addAll(['General Knowledge', 'English']);
    }

    final combinedSet = <String>{...hscList, ...extraAdmissionSubjects};
    return combinedSet.toList();
  }
}

import 'package:flutter/foundation.dart';
import '../models/syllabus_models.dart';

export '../models/syllabus_models.dart';

/// SyllabusFactory generates a complete, deep-copied list of [Subject] items
/// populated with [Chapter]s and target-specific [StudySection]s according
/// to the student's chosen admission target goal or HSC prep preset.
class SyllabusFactory {
  /// Primary generator method returning a fresh deep copy of syllabus subjects.
  static List<Subject> generateInitialSyllabus(String targetGoal, [String hscGroup = 'Science']) {
    print('--- DEBUG: SyllabusFactory received goal: $targetGoal, group: $hscGroup ---');
    return generateSyllabus(targetGoal, hscGroup);
  }

  static List<Subject> generateSyllabus(String targetGoal, [String hscGroup = 'Science']) {
    print('--- DEBUG: SyllabusFactory received goal: $targetGoal, group: $hscGroup ---');
    final targetType = _parseTargetGoal(targetGoal);
    final targetPrefix = _getTargetPrefix(targetType);
    final sectionTitles = _getSectionsForTarget(targetType);

    final subjects = _getSubjectsForTarget(targetType, hscGroup);

    return subjects.map((subDef) {
      final subjectId = '${targetPrefix}_${subDef.key}';

      final chapters = subDef.chapterTitles.asMap().entries.map((chEntry) {
        final chIndex = chEntry.key + 1;
        final chTitle = chEntry.value;
        final chapterId = '${subjectId}_ch$chIndex';

        final sections = sectionTitles.asMap().entries.map((secEntry) {
          final secIndex = secEntry.key + 1;
          final secTitle = secEntry.value;
          final sectionId = '${chapterId}_sec$secIndex';

          return StudySection(
            id: sectionId,
            title: secTitle,
            isCompleted: false,
          );
        }).toList();

        return Chapter(
          id: chapterId,
          title: chTitle,
          sections: sections,
        );
      }).toList();

      return Subject(
        id: subjectId,
        title: subDef.title,
        chapters: chapters,
        iconName: subDef.iconName,
      );
    }).toList();
  }

  // Helper method for target classification using contains() string matching
  static _TargetType _parseTargetGoal(String targetGoal) {
    final goal = targetGoal.toLowerCase().trim();
    debugPrint('[SYLLABUS_FACTORY] Parsing target goal: "$targetGoal" (lowered: "$goal")');

    if (goal.contains('medical') || goal.contains('mbbs') || goal.contains('bds')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: medical');
      return _TargetType.medical;
    } else if (goal.contains('varsity a') || goal.contains('versity a') || goal.contains('a unit') || goal.contains('unit a') || goal.contains('"a"')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: versityA');
      return _TargetType.versityA;
    } else if (goal.contains('varsity b') || goal.contains('versity b') || goal.contains('b unit') || goal.contains('unit b') || goal.contains('"b"')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: versityB');
      return _TargetType.versityB;
    } else if (goal.contains('varsity c') || goal.contains('versity c') || goal.contains('c unit') || goal.contains('unit c') || goal.contains('"c"')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: versityC');
      return _TargetType.versityC;
    } else if (goal.contains('iba') || goal.contains('bba')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: iba');
      return _TargetType.iba;
    } else if (goal.contains('hsc') || goal.contains('candidate') || goal.contains('board')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: hscPrep');
      return _TargetType.hscPrep;
    } else if (goal.contains('engineering') ||
        goal.contains('buet') ||
        goal.contains('ckruet') ||
        goal.contains('kuet') ||
        goal.contains('ruet') ||
        goal.contains('cuet') ||
        goal.contains('sust') ||
        goal.contains('butex')) {
      debugPrint('[SYLLABUS_FACTORY] Matched: engineering');
      return _TargetType.engineering;
    } else {
      debugPrint('[SYLLABUS_FACTORY] Defaulting to engineering');
      return _TargetType.engineering;
    }
  }

  static String _getTargetPrefix(_TargetType targetType) {
    switch (targetType) {
      case _TargetType.hscPrep:
        return 'hsc';
      case _TargetType.engineering:
        return 'eng';
      case _TargetType.medical:
        return 'med';
      case _TargetType.iba:
        return 'iba';
      case _TargetType.versityA:
        return 'va';
      case _TargetType.versityB:
        return 'vb';
      case _TargetType.versityC:
        return 'vc';
    }
  }

  /// Target-Specific Study Sections
  static List<String> _getSectionsForTarget(_TargetType targetType) {
    switch (targetType) {
      case _TargetType.hscPrep:
        return const [
          'Main textbook',
          'Exercise MCQ',
          'Class note',
        ];

      case _TargetType.engineering:
        return const [
          'Question Bank (প্রশ্নব্যাংক)',
          'Concept book (কনসেপ্ট বুক)',
          'Probable question (সম্ভাব্য প্রশ্ন)',
          'Class note (ক্লাস নোট)',
          'Weekly solution',
          'Main Textbook',
          'Exercise MCQ',
          'Online class lecture slide',
        ];

      case _TargetType.medical:
        return const [
          'Main Textbook',
          'Question Bank (প্রশ্নব্যাংক)',
          'Retina Digest (রেটিনা ডাইজেস্ট)',
          'Practice question',
          'Class note (ক্লাস নোট)',
          'Weekly solution',
          'Exercise MCQ',
          'Online class lecture slide',
        ];

      case _TargetType.iba:
        return const [
          'Vocabulary/Grammar',
          'Practice Problems',
          'Previous Year Questions',
        ];

      case _TargetType.versityA:
      case _TargetType.versityB:
      case _TargetType.versityC:
        return const [
          'Main Textbook',
          'Question Bank (প্রশ্নব্যাংক)',
          'Preparatory book (প্রিপারেটরি বুক)',
          'Probable question (সম্ভাব্য প্রশ্ন)',
          'Class note (ক্লাস নোট)',
          'Weekly solution',
          'Exercise MCQ',
          'Online class lecture slide',
        ];
    }
  }

  /// Map target goals and HSC Group to their assigned subjects
  static List<_SubjectDefinition> _getSubjectsForTarget(_TargetType targetType, String hscGroup) {
    final group = hscGroup.trim().toLowerCase();

    if (group.contains('human') || group.contains('arts')) {
      switch (targetType) {
        case _TargetType.hscPrep:
          return [
            _bangla1,
            _bangla2,
            _english1,
            _english2,
            _ict,
            _civics1,
            _civics2,
            _economics1,
            _economics2,
            _history1,
            _history2,
            _geography1,
            _geography2,
          ];
        case _TargetType.versityB:
          return [_bangla, _english, _generalKnowledge];
        case _TargetType.versityC:
          return [_bangla, _english, _ict, _economics1, _economics2];
        case _TargetType.iba:
          return [_ibaEnglish, _ibaMath, _ibaAnalytical];
        default:
          return [_bangla, _english, _generalKnowledge];
      }
    } else if (group.contains('com') || group.contains('bus')) {
      switch (targetType) {
        case _TargetType.hscPrep:
          return [
            _bangla1,
            _bangla2,
            _english1,
            _english2,
            _ict,
            _accounting1,
            _accounting2,
            _businessMgmt1,
            _businessMgmt2,
            _finance1,
            _finance2,
            _marketing1,
            _marketing2,
          ];
        case _TargetType.versityC:
          return [_accounting1, _accounting2, _businessMgmt1, _businessMgmt2, _finance1,_finance2,_marketing1,_marketing2, _bangla, _english];
        case _TargetType.versityB:
          return [_bangla, _english, _generalKnowledge];
        case _TargetType.iba:
          return [_ibaEnglish, _ibaMath, _ibaAnalytical];
        default:
          return [_accounting1, _accounting2, _businessMgmt1, _businessMgmt2, _finance1,_finance2,_marketing1,_marketing2, _bangla, _english];
      }
    } else {
      // Science
      switch (targetType) {
        case _TargetType.hscPrep:
          return [
            _bangla1,
            _bangla2,
            _english1,
            _english2,
            _higherMath1Hsc,
            _higherMath2Hsc,
            _physics1Hsc,
            _physics2Hsc,
            _chemistry1Hsc,
            _chemistry2Hsc,
            _biology1Hsc,
            _biology2Hsc,
            _ict,
          ];
        case _TargetType.engineering:
          return [_physics1, _physics2, _chemistry1, _chemistry2, _higherMath1, _higherMath2];
        case _TargetType.medical:
          return [_physics1, _physics2, _chemistry1, _chemistry2, _biology1, _biology2, _generalKnowledge, _english];
        case _TargetType.iba:
          return [_ibaEnglish, _ibaMath, _ibaAnalytical];
        case _TargetType.versityA:
          return [_physics1, _physics2, _chemistry1, _chemistry2, _higherMath1, _higherMath2, _biology1, _biology2];
        case _TargetType.versityB:
          return [_bangla, _english, _generalKnowledge];
        case _TargetType.versityC:
          return [_accounting, _businessManagement, _financeMarketing, _bangla, _english];
      }
    }
  }

  // --- HSC PREP SUBJECT DEFINITIONS ---
  static const _bangla1 = _SubjectDefinition(
    key: 'ban1',
    title: 'Bangla 1st Paper (বাংলা ১ম পত্র)',
    iconName: 'language',
    chapterTitles: [
      'গদ্য: অপরিচিতা (রবীন্দ্রনাথ ঠাকুর)',
      'গদ্য: বিলাসী (শরৎচন্দ্র চট্টোপাধ্যায়)',
      'গদ্য: বায়ান্নর দিনগুলো (শেখ মুজিবুর রহমান)',
      'গদ্য: রেইনকোট (আখতারুজ্জামান ইলিয়াস)',
      'গদ্য: মহাজাগতিক কিউরেটর (মুহম্মদ জাফর ইকবাল)',
      'পদ্য: সোনার তরী (রবীন্দ্রনাথ ঠাকুর)',
      'পদ্য: বিদ্রোহী (কাজী নজরুল ইসলাম)',
      'পদ্য: প্রতিদান (জসীমউদ্দীন)',
      'পদ্য: তাহারে পড়ে মনে (সুফিয়া কামাল)',
      'পদ্য: ফেব্রুয়ারি ১৯৬৯ (শামসুর রাহমান)',
      'সহপাঠ: লালসালু (উপন্যাস)',
      'সহপাঠ: সিরাজউদ্দৌলা (নাটক)',
    ],
  );

  static const _bangla2 = _SubjectDefinition(
    key: 'ban2',
    title: 'Bangla 2nd Paper (বাংলা ২য় পত্র)',
    iconName: 'language',
    chapterTitles: [
      'অধ্যায় ১: বাংলা উচ্চারণের নিয়ম',
      'অধ্যায় ২: বাংলা বানানের নিয়ম',
      'অধ্যায় ৩: বাংলা ব্যাকরণিক শব্দশ্রেণি',
      'অধ্যায় ৪: বাংলা শব্দ গঠন (উপসর্গ, সমাস)',
      'অধ্যায় ৫: বাক্যতত্ত্ব ও বাক্য রূপান্তর',
      'অধ্যায় ৬: বাংলা ভাষার অপপ্রয়োগ ও শুদ্ধ প্রয়োগ',
      'অধ্যায় ৭: পারিভাষিক শব্দ ও অনুবাদ',
      'অধ্যায় ৮: আবেদনপত্র ও অফিশিয়াল পত্র',
      'অধ্যায় ৯: সারাংশ, সারসংক্ষেপ ও ভাবসম্প্রসারণ',
      'অধ্যায় ১০: সংলাপ ও খুদেগল্প রচনা',
      'অধ্যায় ১১: প্রবন্ধ রচনা',
    ],
  );

  static const _english1 = _SubjectDefinition(
    key: 'eng1',
    title: 'English 1st Paper (ইংরেজি ১ম পত্র)',
    iconName: 'language',
    chapterTitles: [
      'Unit 1: People or Personalities',
      'Unit 2: Dreams and Aspirations',
      'Unit 3: Lifestyle and Habits',
      'Unit 4: Youthful Encounters',
      'Unit 5: Relationships',
      'Unit 6: Art and Craft',
      'Unit 7: Environment and Nature',
      'Unit 8: Peace and Conflict',
      'Unit 9: Tours and Travels',
      'Guided Writing: Flow Chart & Summary',
      'Guided Writing: Theme & Graph/Chart Interpretation',
    ],
  );

  static const _english2 = _SubjectDefinition(
    key: 'eng2',
    title: 'English 2nd Paper (ইংরেজি ২য় পত্র)',
    iconName: 'language',
    chapterTitles: [
      'Topic 1: Prepositions',
      'Topic 2: Special Phrases and Idioms',
      'Topic 3: Completing Sentences with Clauses/Phrases',
      'Topic 4: Right Forms of Verbs',
      'Topic 5: Narrative Style (Direct to Indirect)',
      'Topic 6: Modifiers (Pre & Post Modifiers)',
      'Topic 7: Sentence Connectors & Linkers',
      'Topic 8: Synonym and Antonym',
      'Topic 9: Punctuation and Capitalization',
      'Composition: Formal Letters and Emails',
      'Composition: Paragraph Writing',
    ],
  );

  static const _higherMath1Hsc = _SubjectDefinition(
    key: 'hmath1',
    title: 'Higher Math 1st Paper (উচ্চতর গণিত ১ম পত্র)',
    iconName: 'math',
    chapterTitles: [
      'অধ্যায় ১: ম্যাট্রিক্স ও নির্ণায়ক (Matrices and Determinants)',
      'অধ্যায় ২: ভেক্টর (Vectors)',
      'অধ্যায় ৩: সরলরেখা (Straight Lines)',
      'অধ্যায় ৪: বৃত্ত (Circles)',
      'অধ্যায় ৫: বিন্যাস ও সমাবেশ (Permutations and Combinations)',
      'অধ্যায় ৬: ত্রিকোণমিতিক অনুপাত (Trigonometric Ratios)',
      'অধ্যায় ৭: সংযুক্ত কোণের ত্রিকোণমিতিক অনুপাত (Trigonometric Ratios of Associated Angles)',
      'অধ্যায় ৮: ফাংশন ও ফাংশনের লেখচিত্র (Functions and Graphs)',
      'অধ্যায় ৯: অন্তরীকরণ (Differentiation)',
      'অধ্যায় ১০: যোগজীকরণ (Integration)',
    ],
  );

  static const _higherMath2Hsc = _SubjectDefinition(
    key: 'hmath2',
    title: 'Higher Math 2nd Paper (উচ্চতর গণিত ২য় পত্র)',
    iconName: 'math',
    chapterTitles: [
      'অধ্যায় ১: বাস্তব সংখ্যা ও অসমতা (Real Numbers and Inequalities)',
      'অধ্যায় ২: যোগাশ্রয়ী প্রোগ্রাম (Linear Programming)',
      'অধ্যায় ৩: জটিল সংখ্যা (Complex Numbers)',
      'অধ্যায় ৪: বহুপদী ও বহুপদী সমীকরণ (Polynomials and Equations)',
      'অধ্যায় ৫: দ্বিপদী বিস্তৃতি (Binomial Expansion)',
      'অধ্যায় ৬: কনিক্স (Conics - Parabola, Ellipse, Hyperbola)',
      'অধ্যায় ৭: বিপরীত ত্রিকোণমিতিক ফাংশন ও সমীকরণ (Inverse Trigonometric Functions)',
      'অধ্যায় ৮: স্থিতিবিদ্যা (Statics)',
      'অধ্যায় ৯: সমতলে বস্তুকণার গতি (Dynamics)',
      'অধ্যায় ১০: বিস্তার পরিমাপ ও সম্ভাবনা (Probability)',
    ],
  );

  static const _physics1Hsc = _SubjectDefinition(
    key: 'phy1',
    title: 'Physics 1st Paper (পদার্থবিজ্ঞান ১ম পত্র)',
    iconName: 'physics',
    chapterTitles: [
      'অধ্যায় ১: ভৌতজগৎ ও পরিমাপ (Physical World and Measurement)',
      'অধ্যায় ২: ভেক্টর (Vectors)',
      'অধ্যায় ৩: গতিবিদ্যা (Dynamics)',
      'অধ্যায় ৪: নিউটনীয় বলবিদ্যা (Newtonian Mechanics)',
      'অধ্যায় ৫: কাজ, শক্তি ও ক্ষমতা (Work, Energy and Power)',
      'অধ্যায় ৬: মহাকর্ষ ও অভিকর্ষ (Gravitation and Gravity)',
      'অধ্যায় ৭: পদার্থের গাঠনিক ধর্ম (Structural Properties of Matter)',
      'অধ্যায় ৮: পর্যায়বৃত্ত গতি (Periodic Motion)',
      'অধ্যায় ৯: তরঙ্গ (Waves)',
      'অধ্যায় ১০: আদর্শ গ্যাস ও গ্যাসের গতিতত্ত্ব (Ideal Gas and Kinetic Theory)',
    ],
  );

  static const _physics2Hsc = _SubjectDefinition(
    key: 'phy2',
    title: 'Physics 2nd Paper (পদার্থবিজ্ঞান ২য় পত্র)',
    iconName: 'physics',
    chapterTitles: [
      'অধ্যায় ১: তাপগতিবিদ্যা (Thermodynamics)',
      'অধ্যায় ২: স্থির তড়িৎ (Static Electricity)',
      'অধ্যায় ৩: চল তড়িৎ (Current Electricity)',
      'অধ্যায় ৪: তড়িৎ প্রবাহের চৌম্বক ক্রিয়া ও চৌম্বকত্ব (Magnetic Effect of Current)',
      'অধ্যায় ৫: তাড়িতচৌম্বক আবেশ ও পরিবর্তী প্রবাহ (Electromagnetic Induction)',
      'অধ্যায় ৬: জ্যামিতিক আলোকবিজ্ঞান (Geometric Optics)',
      'অধ্যায় ৭: ভৌত আলোকবিজ্ঞান (Physical Optics)',
      'অধ্যায় ৮: আধুনিক পদার্থবিজ্ঞানের সূচনা (Introduction to Modern Physics)',
      'অধ্যায় ৯: পরমাণুর মডেল এবং নিউক্লিয়ার পদার্থবিজ্ঞান (Atomic Model & Nuclear Physics)',
      'অধ্যায় ১০: সেমিকন্ডাক্টর ও ইলেকট্রনিক্স (Semiconductor and Electronics)',
      'অধ্যায় ১১: জ্যোতির্বিজ্ঞান (Astronomy)',
    ],
  );

  static const _chemistry1Hsc = _SubjectDefinition(
    key: 'chem1',
    title: 'Chemistry 1st Paper (রসায়ন ১ম পত্র)',
    iconName: 'chemistry',
    chapterTitles: [
      'অধ্যায় ১: ল্যাবরেটরির নিরাপদ ব্যবহার (Safe Use of Laboratory)',
      'অধ্যায় ২: গুণগত রসায়ন (Qualitative Chemistry)',
      'অধ্যায় ৩: মৌলের পর্যায়বৃত্ত ধর্ম ও রাসায়নিক বন্ধন (Periodic Properties & Bonding)',
      'অধ্যায় ৪: রাসায়নিক পরিবর্তন (Chemical Change - Kinetics & Equilibrium)',
      'অধ্যায় ৫: কর্মমুখী রসায়ন (Economic & Applied Chemistry)',
    ],
  );

  static const _chemistry2Hsc = _SubjectDefinition(
    key: 'chem2',
    title: 'Chemistry 2nd Paper (রসায়ন ২য় পত্র)',
    iconName: 'chemistry',
    chapterTitles: [
      'অধ্যায় ১: পরিবেশ রসায়ন (Environmental Chemistry)',
      'অধ্যায় ২: জৈব রসায়ন (Organic Chemistry)',
      'অধ্যায় ৩: পরিমাণগত রসায়ন (Quantitative Chemistry & Stoichiometry)',
      'অধ্যায় ৪: তড়িৎ রসায়ন (Electrochemistry)',
      'অধ্যায় ৫: অর্থনৈতিক রসায়ন (Industrial Chemistry)',
    ],
  );

  static const _biology1Hsc = _SubjectDefinition(
    key: 'bio1',
    title: 'Biology 1st Paper (জীববিজ্ঞান ১ম পত্র)',
    iconName: 'biology',
    chapterTitles: [
      'অধ্যায় ১: কোষ ও এর গঠন (Cell and its Structure)',
      'অধ্যায় ২: কোষ বিভাজন (Cell Division)',
      'অধ্যায় ৩: কোষ রসায়ন (Cell Chemistry)',
      'অধ্যায় ৪: অণুজীব (Microorganisms - Virus, Bacteria, Malaria)',
      'অধ্যায় ৫: শৈবাল ও ছত্রাক (Algae and Fungi)',
      'অধ্যায় ৬: ব্রায়োফাইটা ও টেরিডোফাইটা (Bryophyta & Pteridophyta)',
      'অধ্যায় ৭: নগ্নবীজী ও আবৃতবীজী উদ্ভিদ (Gymnosperms & Angiosperms)',
      'অধ্যায় ৮: টিস্যু ও টিস্যুতন্ত্র (Tissue & Tissue System)',
      'অধ্যায় ৯: উদ্ভিদ শারীরতত্ত্ব (Plant Physiology)',
      'অধ্যায় ১০: উদ্ভিদ প্রজনন (Plant Reproduction)',
      'অধ্যায় ১১: জীবপ্রযুক্তি (Biotechnology)',
      'অধ্যায় ১২: জীবের পরিবেশ, বিস্তার ও সংরক্ষণ (Environment & Conservation)',
    ],
  );

  static const _biology2Hsc = _SubjectDefinition(
    key: 'bio2',
    title: 'Biology 2nd Paper (জীববিজ্ঞান ২য় পত্র)',
    iconName: 'biology',
    chapterTitles: [
      'অধ্যায় ১: প্রাণীর বিভিন্নতা ও শ্রেণিবিন্যাস (Animal Diversity & Classification)',
      'অধ্যায় ২: প্রাণীর পরিচিতি (Introduction to Animals - Hydra, Grasshopper, Rui Fish)',
      'অধ্যায় ৩: মানব শারীরতত্ত্ব: পরিপাক ও শোষণ (Digestion and Absorption)',
      'অধ্যায় ৪: মানব শারীরতত্ত্ব: রক্ত ও সংবহন (Blood and Circulation)',
      'অধ্যায় ৫: মানব শারীরতত্ত্ব: শ্বসন ও শ্বাসক্রিয়া (Respiration and Breathing)',
      'অধ্যায় ৬: মানব শারীরতত্ত্ব: বর্জ্য ও নিষ্কাশন (Excretion and Osmoregulation)',
      'অধ্যায় ৭: মানব শারীরতত্ত্ব: চলন ও অঙ্গচালনা (Locomotion and Movement)',
      'অধ্যায় ৮: মানব শারীরতত্ত্ব: সমন্বয় ও নিয়ন্ত্রণ (Nervous & Endocrine System)',
      'অধ্যায় ৯: মানব জীবনের ধারাবাহিকতা (Reproduction & Development)',
      'অধ্যায় ১০: মানবদেহের প্রতিরক্ষা (Immunology)',
      'অধ্যায় ১১: জিনতত্ত্ব ও বিবর্তন (Genetics and Evolution)',
      'অধ্যায় ১২: প্রাণীর আচরণ (Animal Behavior)',
    ],
  );

  static const _ict = _SubjectDefinition(
    key: 'ict',
    title: 'ICT (আইসিটি)',
    iconName: 'globe',
    chapterTitles: [
      'অধ্যায় ১: তথ্য ও যোগাযোগ প্রযুক্তি: বিশ্ব ও বাংলাদেশ প্রেক্ষিত (Information & Communication Technology)',
      'অধ্যায় ২: কমিউনিকেশন সিস্টেমস ও নেটওয়ার্কিং (Communication Systems and Networking)',
      'অধ্যায় ৩: সংখ্যা পদ্ধতি ও ডিজিটাল ডিভাইস (Number Systems and Digital Devices)',
      'অধ্যায় ৪: ওয়েব ডিজাইন পরিচিতি এবং এইচটিএমএল (Web Design and HTML)',
      'অধ্যায় ৫: প্রোগ্রামিং ভাষা (Programming in C)',
      'অধ্যায় ৬: ডেটাবেজ ম্যানেজমেন্ট সিস্টেম (Database Management System / DBMS)',
    ],
  );

  // --- ADMISSION SUBJECT CHAPTER DEFINITIONS ---

  static const _physics1 = _SubjectDefinition(
    key: 'phy1',
    title: 'Physics 1st Paper (পদার্থবিজ্ঞান ১ম পত্র)',
    iconName: 'physics',
    chapterTitles: [
      'অধ্যায় ১: ভৌতজগৎ ও পরিমাপ (Physical World and Measurement)',
      'অধ্যায় ২: ভেক্টর (Vectors)',
      'অধ্যায় ৩: গতিবিদ্যা (Dynamics)',
      'অধ্যায় ৪: নিউটনীয় বলবিদ্যা (Newtonian Mechanics)',
      'অধ্যায় ৫: কাজ, শক্তি ও ক্ষমতা (Work, Energy and Power)',
      'অধ্যায় ৬: মহাকর্ষ ও অভিকর্ষ (Gravitation and Gravity)',
      'অধ্যায় ৭: পদার্থের গাঠনিক ধর্ম (Structural Properties of Matter)',
      'অধ্যায় ৮: পর্যায়বৃত্ত গতি (Periodic Motion)',
      'অধ্যায় ৯: তরঙ্গ (Waves)',
      'অধ্যায় ১০: আদর্শ গ্যাস ও গ্যাসের গতিতত্ত্ব (Ideal Gas and Kinetic Theory of Gases)',
    ],
  );

  static const _physics2 = _SubjectDefinition(
    key: 'phy2',
    title: 'Physics 2nd Paper (পদার্থবিজ্ঞান ২য় পত্র)',
    iconName: 'physics',
    chapterTitles: [
      'অধ্যায় ১: তাপগতিবিদ্যা (Thermodynamics)',
      'অধ্যায় ২: স্থির তড়িৎ (Static Electricity)',
      'অধ্যায় ৩: চল তড়িৎ (Current Electricity)',
      'অধ্যায় ৪: তড়িৎ প্রবাহের চৌম্বক ক্রিয়া ও চৌম্বকত্ব (Magnetic Effect of Current and Magnetism)',
      'অধ্যায় ৫: তাড়িতচৌম্বক আবেশ ও পরিবর্তী প্রবাহ (Electromagnetic Induction and Alternating Current)',
      'অধ্যায় ৬: জ্যামিতিক আলোকবিজ্ঞান (Geometric Optics)',
      'অধ্যায় ৭: ভৌত আলোকবিজ্ঞান (Physical Optics)',
      'অধ্যায় ৮: আধুনিক পদার্থবিজ্ঞানের সূচনা (Introduction to Modern Physics)',
      'অধ্যায় ৯: পরমাণুর মডেল এবং নিউক্লিয়ার পদার্থবিজ্ঞান (Atomic Model and Nuclear Physics)',
      'অধ্যায় ১০: সেমিকন্ডাক্টর ও ইলেকট্রনিক্স (Semiconductor and Electronics)',
      'অধ্যায় ১১: জ্যোতির্বিজ্ঞান (Astronomy)',
    ],
  );

  static const _chemistry1 = _SubjectDefinition(
    key: 'chem1',
    title: 'Chemistry 1st Paper (রসায়ন ১ম পত্র)',
    iconName: 'chemistry',
    chapterTitles: [
      'অধ্যায় ১: ল্যাবরেটরির নিরাপদ ব্যবহার (Safe Use of Laboratory)',
      'অধ্যায় ২: গুণগত রসায়ন (Qualitative Chemistry)',
      'অধ্যায় ৩: মৌলের পর্যায়বৃত্ত ধর্ম ও রাসায়নিক বন্ধন (Periodic Properties of Elements and Chemical Bonding)',
      'অধ্যায় ৪: রাসায়নিক পরিবর্তন (Chemical Change)',
      'অধ্যায় ৫: কর্মমুখী রসায়ন (Economic Chemistry)',
    ],
  );

  static const _chemistry2 = _SubjectDefinition(
    key: 'chem2',
    title: 'Chemistry 2nd Paper (রসায়ন ২য় পত্র)',
    iconName: 'chemistry',
    chapterTitles: [
      'অধ্যায় ১: পরিবেশ রসায়ন (Environmental Chemistry)',
      'অধ্যায় ২: জৈব রসায়ন (Organic Chemistry)',
      'অধ্যায় ৩: পরিমাণগত রসায়ন (Quantitative Chemistry)',
      'অধ্যায় ৪: তড়িৎ রসায়ন (Electrochemistry)',
      'অধ্যায় ৫: অর্থনৈতিক রসায়ন (Economic Chemistry)',
    ],
  );

  static const _higherMath1 = _SubjectDefinition(
    key: 'hmath1',
    title: 'Higher Math 1st Paper (উচ্চতর গণিত ১ম পত্র)',
    iconName: 'math',
    chapterTitles: [
      'অধ্যায় ১: ম্যাট্রিক্স ও নির্ণায়ক (Matrices and Determinants)',
      'অধ্যায় ২: ভেক্টর (Vectors)',
      'অধ্যায় ৩: সরলরেখা (Straight Lines)',
      'অধ্যায় ৪: বৃত্ত (Circles)',
      'অধ্যায় ৫: বিন্যাস ও সমাবেশ (Permutations and Combinations)',
      'অধ্যায় ৬: ত্রিকোণমিতিক অনুপাত (Trigonometric Ratios)',
      'অধ্যায় ৭: সংযুক্ত কোণের ত্রিকোণমিতিক অনুপাত (Trigonometric Ratios of Associated Angles)',
      'অধ্যায় ৮: ফাংশন ও ফাংশনের লেখচিত্র (Functions and Graphs of Functions)',
      'অধ্যায় ৯: অন্তরীকরণ (Differentiation)',
      'অধ্যায় ১০: যোগজীকরণ (Integration)',
    ],
  );

  static const _higherMath2 = _SubjectDefinition(
    key: 'hmath2',
    title: 'Higher Math 2nd Paper (উচ্চতর গণিত ২য় পত্র)',
    iconName: 'math',
    chapterTitles: [
      'অধ্যায় ১: বাস্তব সংখ্যা ও অসমতা (Real Numbers and Inequalities)',
      'অধ্যায় ২: যোগাশ্রয়ী প্রোগ্রাম (Linear Programming)',
      'অধ্যায় ৩: জটিল সংখ্যা (Complex Numbers)',
      'অধ্যায় ৪: বহুপদী ও বহুপদী সমীকরণ (Polynomials and Polynomial Equations)',
      'অধ্যায় ৫: দ্বিপদী বিস্তৃতি (Binomial Expansion)',
      'অধ্যায় ৬: কনিক্স (Conics)',
      'অধ্যায় ৭: বিপরীত ত্রিকোণমিতিক ফাংশন ও ত্রিকোণমিতিক সমীকরণ (Inverse Trigonometric Functions and Trigonometric Equations)',
      'অধ্যায় ৮: স্থিতিবিদ্যা (Statics)',
      'অধ্যায় ৯: গতিবিদ্যা (Dynamics)',
      'অধ্যায় ১০: বিস্তার পরিমাপ ও সম্ভাবনা (Measures of Dispersion and Probability)',
    ],
  );

  static const _biology1 = _SubjectDefinition(
    key: 'bio1',
    title: 'Biology 1st Paper (জীববিজ্ঞান ১ম পত্র)',
    iconName: 'biology',
    chapterTitles: [
      'অধ্যায় ১: কোষ ও এর গঠন (Cell and its Structure)',
      'অধ্যায় ২: কোষ বিভাজন (Cell Division)',
      'অধ্যায় ৩: কোষ রসায়ন (Cell Chemistry)',
      'অধ্যায় ৪: অণুজীব (Microorganisms - Virus, Bacteria, Malaria)',
      'অধ্যায় ৫: শৈবাল ও ছত্রাক (Algae and Fungi)',
      'অধ্যায় ৬: ব্রায়োফাইটা ও টেরিডোফাইটা (Bryophyta and Pteridophyta)',
      'অধ্যায় ৭: নগ্নজীবী ও আবৃতজীবী উদ্ভিদ (Gymnosperms and Angiosperms)',
      'অধ্যায় ৮: টিস্যু ও টিস্যুতন্ত্র (Tissue and Tissue System)',
      'অধ্যায় ৯: উদ্ভিদ শারীরতত্ত্ব (Plant Physiology - Photosynthesis, Respiration)',
      'অধ্যায় ১০: উদ্ভিদ প্রজনন (Plant Reproduction)',
      'অধ্যায় ১১: জীবপ্রযুক্তি (Biotechnology)',
      'অধ্যায় ১২: জীবের পরিবেশ, বিস্তার ও সংরক্ষণ (Environment, Distribution and Conservation of Organisms)',
    ],
  );

  static const _biology2 = _SubjectDefinition(
    key: 'bio2',
    title: 'Biology 2nd Paper (জীববিজ্ঞান ২য় পত্র)',
    iconName: 'biology',
    chapterTitles: [
      'অধ্যায় ১: প্রাণীর বিভিন্নতা ও শ্রেণিবিন্যাস (Animal Diversity and Classification)',
      'অধ্যায় ২: প্রাণীর পরিচিতি (Introduction to Animals - Hydra, Grasshopper, Rohu Fish)',
      'অধ্যায় ৩: মানব শারীরতত্ত্ব: পরিপাক ও শোষণ (Human Physiology: Digestion and Absorption)',
      'অধ্যায় ৪: মানব শারীরতত্ত্ব: রক্ত ও সংবহন (Human Physiology: Blood and Circulation)',
      'অধ্যায় ৫: মানব শারীরতত্ত্ব: শ্বসন ও শ্বাসক্রিয়া (Human Physiology: Respiration and Breathing)',
      'অধ্যায় ৬: মানব শারীরতত্ত্ব: বর্জ্য ও নিষ্কাশন (Human Physiology: Excretion and Elimination)',
      'অধ্যায় ৭: মানব শারীরতত্ত্ব: চলন ও অঙ্গচালনা (Human Physiology: Locomotion and Movement)',
      'অধ্যায় ৮: মানব শারীরতত্ত্ব: সমন্বয় ও নিয়ন্ত্রণ (Human Physiology: Coordination and Control)',
      'অধ্যায় ৯: মানব জীবনের ধারাবাহিকতা (Continuity of Human Life)',
      'অধ্যায় ১০: মানবদেহের প্রতিরক্ষা (Human Body Defense/Immunology)',
      'অধ্যায় ১১: জিনতত্ত্ব ও বিবর্তন (Genetics and Evolution)',
      'অধ্যায় ১২: প্রাণীর আচরণ (Animal Behavior)',
    ],
  );

  static const _bangla = _SubjectDefinition(
    key: 'ban',
    title: 'Bangla (বাংলা)',
    iconName: 'language',
    chapterTitles: [
      'অধ্যায় ১: ১ম পত্র - গদ্য ও পদ্য (Part 1 / অংশ ১)',
      'অধ্যায় ২: ২য় পত্র - ব্যাকরণ ও নির্মিতি (Part 2 / অংশ ২)',
    ],
  );

  static const _english = _SubjectDefinition(
    key: 'eng_lang',
    title: 'English (ইংরেজি)',
    iconName: 'language',
    chapterTitles: [
      'অধ্যায় ১: English 1st Paper - Reading & Vocabulary (Part 1 / অংশ ১)',
      'অধ্যায় ২: English 2nd Paper - Grammar & Composition (Part 2 / অংশ ২)',
    ],
  );

  static const _generalKnowledge = _SubjectDefinition(
    key: 'gk',
    title: 'General Knowledge (সাধারণ জ্ঞান)',
    iconName: 'globe',
    chapterTitles: [
      'অধ্যায় ১: বাংলাদেশ বিষয়াবলী (Part 1 / অংশ ১)',
      'অধ্যায় ২: আন্তর্জাতিক বিষয়াবলী (Part 2 / অংশ ২)',
    ],
  );

  static const _ibaEnglish = _SubjectDefinition(
    key: 'eng',
    title: 'English',
    iconName: 'language',
    chapterTitles: [
      'Vocabulary & Sentence Completion',
      'Grammar & Error Correction',
      'Reading Comprehension & Passages',
    ],
  );

  static const _ibaMath = _SubjectDefinition(
    key: 'math',
    title: 'Mathematics',
    iconName: 'math',
    chapterTitles: [
      'Arithmetic & Word Problems',
      'Algebra & Equations',
      'Geometry, Trigonometry & Data Interpretation',
    ],
  );

  static const _ibaAnalytical = _SubjectDefinition(
    key: 'ana',
    title: 'Analytical Ability',
    iconName: 'brain',
    chapterTitles: [
      'Puzzles & Logical Deduction',
      'Data Sufficiency & Critical Reasoning',
      'Analytical Scenarios',
    ],
  );

  static const _accounting = _SubjectDefinition(
    key: 'acc',
    title: 'Accounting (হিসাববিজ্ঞান)',
    iconName: 'calculate',
    chapterTitles: [
      'অধ্যায় ১: হিসাববিজ্ঞান পরিচিতি (Introduction to Accounting)',
      'অধ্যায় ২: লেনদেন ও হিসাব সমীকরণ (Transactions & Accounting Equation)',
      'অধ্যায় ৩: দুতরফা দাখিলা পদ্ধতি (Double Entry System)',
      'অধ্যায় ৪: জাবেদা ও খতিয়ান (Journal & Ledger)',
      'অধ্যায় ৫: রেওয়ামিল (Trial Balance)',
      'অধ্যায় ৬: আর্থিক বিবরণী (Financial Statements)',
      'অধ্যায় ৭: উৎপাদন ব্যয় হিসাব (Cost Accounting)',
    ],
  );

  static const _businessManagement = _SubjectDefinition(
    key: 'mgmt',
    title: 'Business Organization & Management (ব্যবসায় সংগঠন ও ব্যবস্থাপনা)',
    iconName: 'business',
    chapterTitles: [
      'অধ্যায় ১: ব্যবসায়ের মৌলিক ধারণা (Fundamentals of Business)',
      'অধ্যায় ২: একমালিকানা ও অংশীদারি ব্যবসায় (Sole Proprietorship & Partnership)',
      'অধ্যায় ৩: যৌথ মূলধনী ব্যবসায় (Company/Corporation)',
      'অধ্যায় ৪: ব্যবস্থাপনার ধারণা ও কার্যাবলী (Principles & Functions of Management)',
      'অধ্যায় ৫: পরিকল্পনা ও সিদ্ধান্ত গ্রহণ (Planning & Decision Making)',
      'অধ্যায় ৬: নেতৃত্ব ও প্রেষণা (Leadership & Motivation)',
    ],
  );

  static const _financeMarketing = _SubjectDefinition(
    key: 'fin_mkt',
    title: 'Finance, Banking & Marketing (ফিন্যান্স, ব্যাংকিং ও মার্কেটিং)',
    iconName: 'account_balance',
    chapterTitles: [
      'অধ্যায় ১: অর্থায়নের ধারণা ও উৎস (Concept & Sources of Finance)',
      'অধ্যায় ২: অর্থের সময়মূল্য (Time Value of Money)',
      'অধ্যায় ৩: মূলধন বাজেটিং (Capital Budgeting)',
      'অধ্যায় ৪: বাণিজ্যিক ব্যাংকিং ও কেন্দ্রীয় ব্যাংক (Commercial & Central Banking)',
      'অধ্যায় ৫: বিপণন পরিচিতি ও বাজারজাতকরণ মিশ্রণ (Marketing Mix)',
    ],
  );

  // --- HUMANITIES SUBJECT DEFINITIONS ---
  static const _civics1 = _SubjectDefinition(
    key: 'civ1',
    title: 'Civics & Good Governance 1st Paper (পৌরনীতি ও সুশাসন ১ম পত্র)',
    iconName: 'account_balance',
    chapterTitles: [
      'অধ্যায় ১: পৌরনীতি ও সুশাসন পরিচিতি (Introduction to Civics and Good Governance)',
      'অধ্যায় ২: সুশাসন (Good Governance)',
      'অধ্যায় ৩: মূল্যবোধ, আইন, স্বাধীনতা ও সাম্য (Values, Law, Liberty and Equality)',
      'অধ্যায় ৪: ই-গভর্নেন্স ও সুশাসন (E-Governance and Good Governance)',
      'অধ্যায় ৫: নাগরিক অধিকার, কর্তব্য ও মানবাধিকার (Civil Rights, Duties and Human Rights)',
      'অধ্যায় ৬: রাজনৈতিক দল, নেতৃত্ব ও সুশাসন (Political Parties, Leadership and Good Governance)',
      'অধ্যায় ৭: সরকার কাঠামো ও অঙ্গসমূহ (Government Structure and Organs)',
      'অধ্যায় ৮: জনমত ও রাজনৈতিক সংস্কৃতি (Public Opinion and Political Culture)',
      'অধ্যায় ৯: জনসেবা ও আমলাতন্ত্র (Public Service and Bureaucracy)',
      'অধ্যায় ১০: দেশপ্রেম ও জাতীয়তা (Patriotism and Nationality)',
    ],
  );

  static const _civics2 = _SubjectDefinition(
    key: 'civ2',
    title: 'Civics & Good Governance 2nd Paper (পৌরনীতি ও সুশাসন ২য় পত্র)',
    iconName: 'account_balance',
    chapterTitles: [
      'অধ্যায় ১: ব্রিটিশ ভারতে প্রতিনিধিত্বশীল সরকারের বিকাশ (Development of Representative Government in British India)',
      'অধ্যায় ২: পাকিস্তান থেকে বাংলাদেশ - ১৯৪৮ থেকে ১৯৭১ (Pakistan to Bangladesh - 1948 to 1971)',
      'অধ্যায় ৩: রাজনৈতিক ব্যক্তিত্ব - বাংলাদেশের স্বাধীনতা লাভ (Political Personalities - Achievement of Bangladesh\'s Independence)',
      'অধ্যায় ৪: বাংলাদেশের সংবিধান (The Constitution of Bangladesh)',
      'অধ্যায় ৫: বাংলাদেশের সরকার ও প্রশাসনিক কাঠামো (Government and Administrative Structure of Bangladesh)',
      'অধ্যায় ৬: স্থানীয় সরকার (Local Government)',
      'অধ্যায় ৭: সাংবিধানিক প্রতিষ্ঠান (Constitutional Institutions)',
      'অধ্যায় ৮: বাংলাদেশের নির্বাচন ব্যবস্থা (Election System of Bangladesh)',
      'অধ্যায় ৯: বাংলাদেশের বৈদেশিক নীতি (Foreign Policy of Bangladesh)',
      'অধ্যায় ১০: নাগরিক সমস্যা ও আমাদের করণীয় (Civic Problems and Our Responsibilities)',
    ],
  );

  static const _economics1 = _SubjectDefinition(
    key: 'eco1',
    title: 'Economics 1st Paper (অর্থনীতি ১ম পত্র)',
    iconName: 'calculate',
    chapterTitles: [
      'অধ্যায় ১: মৌলিক অর্থনৈতিক সমস্যা এবং এর সমাধান (Basic Economic Problems and their Solutions)',
      'অধ্যায় ২: ভোক্তা ও উৎপাদকের আচরণ (Consumer and Producer Behaviour)',
      'অধ্যায় ৩: উৎপাদন, উৎপাদন ব্যয় ও আয় (Production, Production Cost and Revenue)',
      'অধ্যায় ৪: বাজার (Market)',
      'অধ্যায় ৫: শ্রমবাজার (Labour Market)',
      'অধ্যায় ৬: মূলধন (Capital)',
      'অধ্যায় ৭: সংগঠন (Organization)',
      'অধ্যায় ৮: খাজনা (Rent)',
      'অধ্যায় ৯: সামগ্রিক আয় ও ব্যয় (Aggregate Income and Expenditure)',
      'অধ্যায় ১০: মুদ্রা ও ব্যাংক (Money and Banking)',
    ],
  );

  static const _economics2 = _SubjectDefinition(
    key: 'eco2',
    title: 'Economics 2nd Paper (অর্থনীতি ২য় পত্র)',
    iconName: 'calculate',
    chapterTitles: [
      'অধ্যায় ১: বাংলাদেশের অর্থনীতির পরিচয় (Introduction to Bangladesh Economics)',
      'অধ্যায় ২: বাংলাদেশের কৃষি (Agriculture of Bangladesh)',
      'অধ্যায় ৩: বাংলাদেশের শিল্প (Industry of Bangladesh)',
      'অধ্যায় ৪: জনসংখ্যা, মানবসম্পদ এবং আত্মকর্মসংস্থান (Population, Human Resources and Self-Employment)',
      'অধ্যায় ৫: খাদ্য নিরাপত্তা (Food Security)',
      'অধ্যায় ৬: অর্থায়ন (Financing)',
      'অধ্যায় ৭: মুদ্রাস্ফীতি (Inflation)',
      'অধ্যায় ৮: আন্তর্জাতিক বাণিজ্য (International Trade)',
      'অধ্যায় ৯: সরকারি অর্থব্যবস্থা (Public Finance)',
      'অধ্যায় ১০: অর্থনৈতিক উন্নয়ন ও পরিকল্পনা (Economic Development and Planning)',
    ],
  );

  static const _history1 = _SubjectDefinition(
    key: 'his1',
    title: 'History 1st Paper (ইতিহাস ১ম পত্র)',
    iconName: 'auto_stories',
    chapterTitles: [
      'অধ্যায় ১: ভারতবর্ষে ইউরোপীয়দের আগমন: ইংরেজ আধিপত্য প্রতিষ্ঠা (Arrival of Europeans in India: Establishment of British Hegemony)',
      'অধ্যায় ২: ইংরেজ ঔপনিবেশিক শাসন: কোম্পানি আমল (British Colonial Rule: Company Period)',
      'অধ্যায় ৩: ইংরেজ ঔপনিবেশিক शासन: ব্রিটিশ পাকিস্তান আমল/নিয়ন্ত্রণ আমল (British Colonial Rule: British Crown Period)',
      'অধ্যায় ৪: পাকিস্তানি আমলে পরাধীনতা ও স্বাধিকার আন্দোলন (Subjugation and Autonomy Movement during the Pakistani Regime)',
      'অধ্যায় ৫: পূর্ব বাংলার স্বায়ত্তশাসন ও স্বাধিকার আন্দোলন (Autonomy and Self-Determination Movement of East Bengal)',
      'অধ্যায় ৬: ৭০-এর নির্বাচন এবং অসহযোগ আন্দোলন (The Election of 1970 and Non-Cooperation Movement)',
      'অধ্যায় ৭: মুক্তিযুদ্ধ: ২৫শে মার্চের গণহত্যা ও প্রতিরোধ (The Liberation War: Genocide of 25th March and Resistance)',
      'অধ্যায় ৮: প্রবাসী বাংলাদেশ সরকার গঠন ও মুক্তিযুদ্ধ পরিচালনা (Formation of the Mujibnagar Government and Conducting the Liberation War)',
    ],
  );

  static const _history2 = _SubjectDefinition(
    key: 'his2',
    title: 'History 2nd Paper (ইতিহাস ২য় পত্র)',
    iconName: 'auto_stories',
    chapterTitles: [
      'অধ্যায় ১: শিল্প বিপ্লব (The Industrial Revolution)',
      'অধ্যায় ২: ফরাসি বিপ্লব (The French Revolution)',
      'অধ্যায় ৩: প্রথম বিশ্বযুদ্ধ এবং ভার্সাই চুক্তি (The First World War and the Treaty of Versailles)',
      'অধ্যায় ৪: বলশেভিক বিপ্লব/রুশ বিপ্লব (The Bolshevik Revolution/Russian Revolution)',
      'অধ্যায় ৫: হিটলার ও মুসোলিনির উত্থান এবং দ্বিতীয় বিশ্বযুদ্ধ (The Rise of Hitler and Mussolini and the Second World War)',
      'অধ্যায় ৬: জাতিসংঘ ও বিশ্বশান্তি (The United Nations and World Peace)',
      'অধ্যায় ৭: স্নায়ুযুদ্ধ: পুঁজিবাদী ও সমাজতান্ত্রিক ব্লকের দ্বন্দ্ব (The Cold War: Conflict between Capitalist and Socialist Blocks)',
      'অধ্যায় ৮: ঔপনিবেশিকতাবিরোধী আন্দোলন: জাতি-রাষ্ট্রের উত্থান (Anti-Colonial Movements: The Rise of Nation-States)',
      'অধ্যায় ৯: বর্ণবাদবিরোধী আন্দোলন: দক্ষিণ আফ্রিকা (Anti-Apartheid Movement: South Africa)',
    ],
  );

  static const _geography1 = _SubjectDefinition(
    key: 'geo1',
    title: 'Geography 1st Paper (ভূগোল ১ম পত্র)',
    iconName: 'globe',
    chapterTitles: [
      'অধ্যায় ১: প্রাকৃতিক ভূগোল (Physical Geography)',
      'অধ্যায় ২: পৃথিবীর গঠন (Structure of the Earth)',
      'অধ্যায় ৩: ভূমিরূপ পরিবর্তন (Changing Landforms)',
      'অধ্যায় ৪: বায়ুমণ্ডল ও বায়ুদূষণ (Atmosphere and Air Pollution)',
      'অধ্যায় ৫: জলবায়ুর উপাদান ও নিয়ামক (Elements and Factors of Climate)',
      'অধ্যায় ৬: জলবায়ু অঞ্চল ও জলবায়ু পরিবর্তন (Climate Zones and Climate Change)',
      'অধ্যায় ৭: বারিমণ্ডল (Hydrosphere)',
      'অধ্যায় ৮: সমুদ্রস্রোত ও জোয়ার-ভাটা (Ocean Currents and Tides)',
      'অধ্যায় ৯: জীবমণ্ডল (Biosphere)',
      'অধ্যায় ১০: ব্যবহারিক ভূগোল (Practical Geography)',
    ],
  );

  static const _geography2 = _SubjectDefinition(
    key: 'geo2',
    title: 'Geography 2nd Paper (ভূগোল ২য় পত্র)',
    iconName: 'globe',
    chapterTitles: [
      'অধ্যায় ১: মানব ভূগোল (Human Geography)',
      'অধ্যায় ২: জনসংখ্যা (Population)',
      'অধ্যায় ৩: বসতি (Settlement)',
      'অধ্যায় ৪: কৃষি (Agriculture)',
      'অধ্যায় ৫: খনিজ ও শক্তি সম্পদ (Mineral and Energy Resources)',
      'অধ্যায় ৬: শিল্প (Industry)',
      'অধ্যায় ৭: পরিবহন ও যোগাযোগ (Transport and Communication)',
      'অধ্যায় ৮: বাণিজ্য (Trade)',
      'অধ্যায় ৯: দূষণ ও বিপর্যয় (Pollution and Disaster)',
      'অধ্যায় ১০: ব্যবহারিক ভূগোল (Practical Geography)',
    ],
  );

  // --- COMMERCE SUBJECT DEFINITIONS ---
  static const _accounting1 = _SubjectDefinition(
    key: 'acc1',
    title: 'Accounting 1st Paper (হিসাববিজ্ঞান ১ম পত্র)',
    iconName: 'calculate',
    chapterTitles: [
      'অধ্যায় ১: হিসাববিজ্ঞান পরিচিতি (Introduction to Accounting)',
      'অধ্যায় ২: হিসাবের বইসমূহ (Books of Accounts)',
      'অধ্যায় ৩: ব্যাংক সমন্বয় বিবরণী (Bank Reconciliation Statement)',
      'অধ্যায় ৪: রেওয়ামিল (Trial Balance)',
      'অধ্যায় ৫: হিসাববিজ্ঞানের নীতিমালা (Accounting Principles)',
      'অধ্যায় ৬: প্রাপ্য হিসাবসমূহের হিসাবরক্ষণ (Accounting for Receivables)',
      'অধ্যায় ৭: কার্যপত্র (Worksheet)',
      'অধ্যায় ৮: দৃশ্যমান ও অদৃশ্যমান সম্পদের হিসাবরক্ষণ (Accounting for Tangible and Intangible Assets)',
      'অধ্যায় ৯: আর্থিক বিবরণী (Financial Statements)',
      'অধ্যায় ১০: একতরফা দাখিলা পদ্ধতি (Single Entry System)',
    ],
  );

  static const _accounting2 = _SubjectDefinition(
    key: 'acc2',
    title: 'Accounting 2nd Paper (হিসাববিজ্ঞান ২য় পত্র)',
    iconName: 'calculate',
    chapterTitles: [
      'অধ্যায় ১: অব্যবসায়ী প্রতিষ্ঠানের হিসাব (Accounting for Non-Profit Organizations)',
      'অধ্যায় ২: অংশীদারি ব্যবসায়ের হিসাব (Accounting for Partnership Firms)',
      'অধ্যায় ৩: নগদ প্রবাহ বিবরণী (Cash Flow Statement)',
      'অধ্যায় ৪: যৌথমূলধনী কোম্পানির মূলধন - শেয়ার ইস্যু (Capital of Joint Stock Companies - Share Issue)',
      'অধ্যায় ৫: যৌথমূলধনী কোম্পানির আর্থিক বিবরণী (Financial Statements of Joint Stock Companies)',
      'অধ্যায় ৬: আর্থিক বিবরণী বিশ্লেষণ - অনুপাত বিশ্লেষণ (Financial Statement Analysis - Ratio Analysis)',
      'অধ্যায় ৭: উৎপাদন ব্যয় হিসাব (Cost Accounting)',
      'অধ্যায় ৮: মজুদ পণ্যের হিসাবরক্ষণ পদ্ধতি (Accounting for Inventories)',
      'অধ্যায় ৯: ব্যয় ও ব্যয়ের শ্রেণীবিভাগ (Cost and Classification of Cost)',
      'অধ্যায় ১০: ব্যবস্থাপনা হিসাববিজ্ঞান পরিচিতি (Introduction to Management Accounting)',
    ],
  );

  static const _businessMgmt1 = _SubjectDefinition(
    key: 'mgmt1',
    title: 'Business Organization & Management 1st Paper (ব্যবসায় সংগঠন ১ম)',
    iconName: 'business',
    chapterTitles: [
      'অধ্যায় ১: ব্যবসায়ের মৌলিক ধারণা (Basic Concept of Business)',
      'অধ্যায় ২: ব্যবসায় পরিবেশ (Business Environment)',
      'অধ্যায় ৩: একমালিকানা ব্যবসায় (Sole Proprietorship Business)',
      'অধ্যায় ৪: অংশীদারি ব্যবসায় (Partnership Business)',
      'অধ্যায় ৫: যৌথ মূলধনী ব্যবসায় (Joint Stock Business)',
      'অধ্যায় ৬: সমবায় সমিতি (Co-operative Society)',
      'অধ্যায় ৭: রাষ্ট্রীয় ব্যবসায় (State Enterprise / State-owned Business)',
      'অধ্যায় ৮: ব্যবসায়ের আইনগত দিক (Legal Aspects of Business)',
      'অধ্যায় ৯: ব্যবসায়ী সহায়ক সেবা (Business Support Services)',
      'অধ্যায় ১০: ব্যবসায় উদ্যোগ (Business Entrepreneurship)',
      'অধ্যায় ১১: ব্যবসায় তথ্য ও যোগাযোগ প্রযুক্তির ব্যবহার (Information & Communication Technology in Business)',
      'অধ্যায় ১২: ব্যবসায় নৈতিকতা ও সামাজিক দায়বদ্ধতা (Business Ethics and Social Responsibilities)',
    ],
  );

  static const _businessMgmt2 = _SubjectDefinition(
    key: 'mgmt2',
    title: 'Business Organization & Management 2nd Paper (ব্যবসায় ব্যবস্থাপনা ২য়)',
    iconName: 'business',
    chapterTitles: [
      'অধ্যায় ১: ব্যবস্থাপনার ধারণা (Concept of Management)',
      'অধ্যায় ২: ব্যবস্থাপনার নীতি (Principles of Management)',
      'অধ্যায় ৩: পরিকল্পনা প্রণয়ন ও সিদ্ধান্ত গ্রহণ (Planning and Decision Making)',
      'অধ্যায় ৪: সংগঠিতকরণ (Organizing)',
      'অধ্যায় ৫: কর্মীসংস্থান (Staffing)',
      'অধ্যায় ৬: নেতৃত্ব (Leading / Leadership)',
      'অধ্যায় ৭: প্রেষণা (Motivation)',
      'অধ্যায় ৮: যোগাযোগ (Communication)',
      'অধ্যায় ৯: সমন্বয়সাধন (Coordinating)',
      'অধ্যায় ১০: নিয়ন্ত্রণ (Controlling)',
    ],
  );

  static const _finance1 = _SubjectDefinition(
    key: 'fin1',
    title: 'Finance, Banking & Insurance 1st Paper (ফিন্যান্স ১ম পত্র)',
    iconName: 'account_balance',
    chapterTitles: [
      'অধ্যায় ১: অর্থায়নের সূচনা (Introduction to Finance)',
      'অধ্যায় ২: আর্থিক বাজারের আইনগত দিক (Legal Aspects of Financial Market)',
      'অধ্যায় ৩: অর্থের সময় মূল্য (Time Value of Money)',
      'অধ্যায় ৪: আর্থিক বিশ্লেষণ (Financial Analysis)',
      'অধ্যায় ৫: স্বল্প ও মধ্যমেয়াদি অর্থায়ন (Short and Mid-term Financing)',
      'অধ্যায় ৬: দীর্ঘমেয়াদি অর্থায়ন (Long-term Financing)',
      'অধ্যায় ৭: মূলধন ব্যয় (Cost of Capital)',
      'অধ্যায় ৮: মূলধন বাজেটিং ও বিনিয়োগ সিদ্ধান্ত (Capital Budgeting and Investment Decision)',
      'অধ্যায় ৯: ঝুঁকি ও মুনাফার হার (Risk and Rate of Return)',
    ],
  );

  static const _finance2 = _SubjectDefinition(
    key: 'fin2',
    title: 'Finance, Banking & Insurance 2nd Paper (ব্যাংকিং ও বীমা ২য় পত্র)',
    iconName: 'account_balance',
    chapterTitles: [
      'অধ্যায় ১: ব্যাংকিং ব্যবস্থার প্রাথমিক ধারণা (Basic Concept of Banking System)',
      'অধ্যায় ২: কেন্দ্রীয় ব্যাংক (Central Bank)',
      'অধ্যায় ৩: বাণিজ্যিক ব্যাংক (Commercial Bank)',
      'অধ্যায় ৪: ব্যাংক হিসাব (Bank Account)',
      'অধ্যায় ৫: হস্তান্তরযোগ্য ঋণদলিল (Negotiable Instruments)',
      'অধ্যায় ৬: চেকের প্রকারভেদ ও প্রত্যাখ্যান (Types of Cheque and Dishonor)',
      'অধ্যায় ৭: ব্যাংক তহবিল সংগ্রহ ও বিনিয়োগ (Bank Fund Collection and Investment)',
      'অধ্যায় ৮: বৈদেশিক বিনিময় ও আমদানি-রপ্তানি অর্থায়ন (Foreign Exchange and Import-Export Financing)',
      'অধ্যায় ৯: ইলেকট্রনিক ও আধুনিক ব্যাংকিং সেবা (Electronic and Modern Banking Services)',
      'অধ্যায় ১০: বীমা সম্পর্কে মৌলিক ধারণা (Basic Concepts of Insurance)',
      'অধ্যায় ১১: জীবন বীমা (Life Insurance)',
      'অধ্যায় ১২: নৌ বীমা (Marine Insurance)',
      'অধ্যায় ১৩: অগ্নি বীমা (Fire Insurance)',
      'অধ্যায় ১৪: বিবিধ বীমা (Miscellaneous Insurance)',
    ],
  );

  static const _marketing1 = _SubjectDefinition(
    key: 'mkt1',
    title: 'Production Management & Marketing 1st Paper (উৎপাদন ব্যবস্থাপনা ১ম)',
    iconName: 'business',
    chapterTitles: [
      'অধ্যায় ১: উৎপাদন (Production)',
      'অধ্যায় ২: উৎপাদনের উপকরণ (Factors of Production)',
      'অধ্যায় ৩: উৎপাদনের মাত্রা (Scale of Production)',
      'অধ্যায় ৪: সামষ্টিক পর্যায়ের উৎপাদন (Macro Level Production)',
      'অধ্যায় ৫: উৎপাদন ব্যবস্থাপনা (Production Management)',
      'অধ্যায় ৬: পণ্য ডিজাইন (Product Design)',
      'অধ্যায় ৭: মান ব্যবস্থাপনা (Quality Management)',
      'অধ্যায় ৮: উৎপাদন ক্ষমতা (Production Capacity)',
      'অধ্যায় ৯: ব্যবসায় অবস্থান (Business Location)',
      'অধ্যায় ১০: বিন্যাস (Layout)',
    ],
  );

  static const _marketing2 = _SubjectDefinition(
    key: 'mkt2',
    title: 'Production Management & Marketing 2nd Paper (বিপণন ২য় পত্র)',
    iconName: 'business',
    chapterTitles: [
      'অধ্যায় ১: বিপণন পরিচিতি (Introduction to Marketing)',
      'অধ্যায় ২: বিপণন পরিবেশ (Marketing Environment)',
      'অধ্যায় ৩: বিপণন কার্যাবলি (Marketing Functions)',
      'অধ্যায় ৪: বাজার বিভক্তিকরণ ও বিপণন মিশ্রণ (Market Segmentation and Marketing Mix)',
      'অধ্যায় ৫: পণ্য ও পণ্যের মূল্য নির্ধারণ (Product and Product Pricing)',
      'অধ্যায় ৬: পণ্য বণ্টন প্রণালী (Product Distribution Channels)',
      'অধ্যায় ৭: মূল্য নির্ধারণ (Pricing)',
      'অধ্যায় ৮: বিক্রয়প্রসার ও বিজ্ঞাপন (Sales Promotion and Advertising)',
      'অধ্যায় ৯: বাংলাদেশে বিপণন (Marketing in Bangladesh)',
      'অধ্যায় ১০: বিপণনের সমসাময়িক বিষয়াবলি (Contemporary Issues in Marketing)',
    ],
  );
}

enum _TargetType {
  hscPrep,
  engineering,
  medical,
  iba,
  versityA,
  versityB,
  versityC,
}

class _SubjectDefinition {
  final String key;
  final String title;
  final String iconName;
  final List<String> chapterTitles;

  const _SubjectDefinition({
    required this.key,
    required this.title,
    required this.iconName,
    required this.chapterTitles,
  });
}

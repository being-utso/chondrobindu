import 'dart:math';

/// Generates a lightweight unique ID without external dependencies
String generateUniqueNodeId([String prefix = 'node']) {
  final random = Random().nextInt(999999);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_${timestamp}_$random';
}

/// Data model for a dynamic, multi-level nested syllabus node
class SyllabusNode {
  final String id;
  String title;
  bool isLeaf;
  bool isCompleted;
  String? resourceUrl;
  String? parentId;
  List<SyllabusNode> children;

  SyllabusNode({
    String? id,
    required this.title,
    this.isLeaf = false,
    this.isCompleted = false,
    this.resourceUrl,
    this.parentId,
    List<SyllabusNode>? children,
  })  : id = (id != null && id.isNotEmpty) ? id : generateUniqueNodeId('node'),
        children = children ?? [];

  /// Total count of all checkable leaf nodes within this subtree
  int get totalLeafCount {
    if (isLeaf && children.isEmpty) return 1;
    return (isLeaf ? 1 : 0) + children.fold<int>(0, (sum, child) => sum + child.totalLeafCount);
  }

  /// Total count of completed checkable leaf nodes within this subtree
  int get completedLeafCount {
    if (isLeaf && children.isEmpty) return isCompleted ? 1 : 0;
    return (isLeaf && isCompleted ? 1 : 0) + children.fold<int>(0, (sum, child) => sum + child.completedLeafCount);
  }

  /// Completion progress ratio (0.0 to 1.0)
  double get progress {
    final total = totalLeafCount;
    if (total == 0) return 0.0;
    return completedLeafCount / total;
  }

  /// Sets completion status for this node and cascades down to all children recursively (TASK 1)
  void setCompletedCascading(bool completed) {
    isCompleted = completed;
    for (final child in children) {
      child.setCompletedCascading(completed);
    }
  }

  /// Bottom-up hierarchical sync:
  /// - If this node has children, it evaluates to checked if and only if ALL its children are checked.
  /// - If any child is unchecked, this parent evaluates to unchecked.
  /// - If it has no children, it retains its individual isCompleted state.
  /// Returns the evaluated isCompleted state of this node.
  bool updateHierarchicalCompletion() {
    if (children.isEmpty) {
      return isCompleted;
    }
    bool allChildrenCompleted = true;
    for (final child in children) {
      final childDone = child.updateHierarchicalCompletion();
      if (!childDone) {
        allChildrenCompleted = false;
      }
    }
    isCompleted = allChildrenCompleted;
    return isCompleted;
  }

  /// Appends newly imported chapters/modules directly as top-level sections/modules
  /// without wrapping in an artificial "Section 1" root container.
  /// Returns the updated list of nodes and the name of the target section.
  static ({List<SyllabusNode> nodes, String targetSectionTitle}) appendImportedNodes({
    required List<SyllabusNode> existingNodes,
    required List<SyllabusNode> importedNodes,
  }) {
    final updatedNodes = List<SyllabusNode>.from(existingNodes)..addAll(importedNodes);
    final targetTitle = importedNodes.isNotEmpty ? importedNodes.first.title : 'Syllabus';
    return (nodes: updatedNodes, targetSectionTitle: targetTitle);
  }

  /// Recursively removes a node and all of its nested contents/children from [nodes] by ID.
  /// Returns true if the node was found and removed, false otherwise.
  static bool removeNode({
    required List<SyllabusNode> nodes,
    required String targetId,
  }) {
    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i].id == targetId) {
        nodes.removeAt(i);
        return true;
      }
      if (removeNode(nodes: nodes[i].children, targetId: targetId)) {
        return true;
      }
    }
    return false;
  }

  /// Unwraps / promotes the children of the node with [targetId] up by one level in the hierarchy:
  /// - If the target node is found directly at the root [nodes] list (e.g. artificial root wrapper "Section 1"),
  ///   the target node is removed and its children are inserted into the root list, setting their parentId to null.
  /// - If the target node is nested inside a parent chapter/section, the target node is removed from the parent's
  ///   children list and its children are inserted in its place, reassigning their parentId to the parent's id.
  /// Returns true if the node was found and unwrapped, false otherwise.
  static bool unwrapNode({
    required List<SyllabusNode> nodes,
    required String targetId,
    SyllabusNode? parentNode,
  }) {
    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i].id == targetId) {
        final childrenToPromote = nodes[i].children;
        for (final child in childrenToPromote) {
          child.parentId = parentNode?.id;
        }
        nodes.removeAt(i);
        nodes.insertAll(i, childrenToPromote);
        return true;
      }
      if (unwrapNode(
        nodes: nodes[i].children,
        targetId: targetId,
        parentNode: nodes[i],
      )) {
        return true;
      }
    }
    return false;
  }

  /// Converts this node to a parent folder/section container
  void convertToFolder() {
    isLeaf = false;
  }

  /// Converts this node to a checkable leaf topic
  void convertToTopic() {
    isLeaf = true;
  }

  /// Groups nodes with IDs in [targetIds] into a new section titled [sectionTitle].
  /// The extracted nodes retain all their properties, notes, and children.
  /// The new section is inserted at the tree location where the first selected item was found.
  /// Each grouped node has its [parentId] assigned to the new section's ID.
  /// Returns the newly created section, or null if no matching nodes were found.
  static SyllabusNode? groupNodesIntoSection({
    required List<SyllabusNode> nodes,
    required Set<String> targetIds,
    required String sectionTitle,
  }) {
    if (targetIds.isEmpty) return null;

    final List<SyllabusNode> extracted = [];
    int? firstInsertIndex;
    List<SyllabusNode>? firstTargetList;

    void extract(List<SyllabusNode> list) {
      for (int i = 0; i < list.length; i++) {
        final node = list[i];
        if (targetIds.contains(node.id)) {
          if (firstTargetList == null) {
            firstTargetList = list;
            firstInsertIndex = i;
          }
          extracted.add(node);
          list.removeAt(i);
          i--;
        } else {
          extract(node.children);
        }
      }
    }

    extract(nodes);

    if (extracted.isEmpty) return null;

    final newSection = SyllabusNode(
      title: sectionTitle.trim().isNotEmpty ? sectionTitle.trim() : 'New Section',
      isLeaf: false,
      children: extracted,
    );

    for (final child in extracted) {
      child.parentId = newSection.id;
    }

    if (firstTargetList != null && firstInsertIndex != null) {
      final insertAt = firstInsertIndex!.clamp(0, firstTargetList!.length);
      firstTargetList!.insert(insertAt, newSection);
    } else {
      nodes.add(newSection);
    }

    newSection.updateHierarchicalCompletion();

    return newSection;
  }

  SyllabusNode copyWith({
    String? id,
    String? title,
    bool? isLeaf,
    bool? isCompleted,
    String? resourceUrl,
    String? parentId,
    List<SyllabusNode>? children,
  }) {
    return SyllabusNode(
      id: id ?? this.id,
      title: title ?? this.title,
      isLeaf: isLeaf ?? this.isLeaf,
      isCompleted: isCompleted ?? this.isCompleted,
      resourceUrl: resourceUrl ?? this.resourceUrl,
      parentId: parentId ?? this.parentId,
      children: children ?? this.children.map((c) => c.copyWith()).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isLeaf': isLeaf,
      'isCompleted': isCompleted,
      if (resourceUrl != null && resourceUrl!.isNotEmpty) 'resourceUrl': resourceUrl,
      if (parentId != null && parentId!.isNotEmpty) 'parentId': parentId,
      'children': children.map((child) => child.toMap()).toList(),
    };
  }

  factory SyllabusNode.fromMap(Map<String, dynamic> map) {
    final rawChildren = map['children'] as List<dynamic>? ?? [];
    final rawTopics = map['topics'] as List<dynamic>? ?? [];
    final List<SyllabusNode> parsedChildren = [];

    if (rawChildren.isNotEmpty) {
      parsedChildren.addAll(
        rawChildren
            .whereType<Map>()
            .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c))),
      );
    } else if (rawTopics.isNotEmpty) {
      // Backward compatibility for flat Chapter/Topic structure
      parsedChildren.addAll(
        rawTopics.whereType<Map>().map((t) {
          final tMap = Map<String, dynamic>.from(t);
          return SyllabusNode(
            id: tMap['id'] as String?,
            title: tMap['topicName'] as String? ?? (tMap['title'] as String? ?? 'Untitled Topic'),
            isLeaf: true,
            isCompleted: tMap['isCompleted'] as bool? ?? false,
            parentId: tMap['parentId'] as String?,
          );
        }),
      );
    }

    final isLeafVal = map['isLeaf'] as bool? ?? (parsedChildren.isEmpty && (map['topicName'] != null || map['chapterName'] == null));

    return SyllabusNode(
      id: map['id'] as String?,
      title: map['title'] as String? ?? (map['chapterName'] as String? ?? (map['topicName'] as String? ?? 'Untitled')),
      isLeaf: isLeafVal,
      isCompleted: map['isCompleted'] as bool? ?? false,
      resourceUrl: map['resourceUrl'] as String?,
      parentId: map['parentId'] as String?,
      children: parsedChildren,
    );
  }
}

/// Backward compatibility model for SyllabusTopic
class SyllabusTopic {
  final String topicName;
  bool isCompleted;

  SyllabusTopic({
    required this.topicName,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'topicName': topicName,
      'isCompleted': isCompleted,
    };
  }

  factory SyllabusTopic.fromMap(Map<String, dynamic> map) {
    return SyllabusTopic(
      topicName: map['topicName'] as String? ?? (map['title'] as String? ?? 'Untitled Topic'),
      isCompleted: map['isCompleted'] as bool? ?? (map['completed'] as bool? ?? false),
    );
  }
}

/// Backward compatibility model for SyllabusChapter
class SyllabusChapter {
  final String chapterName;
  final List<SyllabusTopic> topics;

  SyllabusChapter({
    required this.chapterName,
    required this.topics,
  });

  Map<String, dynamic> toMap() {
    return {
      'chapterName': chapterName,
      'topics': topics.map((t) => t.toMap()).toList(),
    };
  }

  factory SyllabusChapter.fromMap(Map<String, dynamic> map) {
    final rawTopics = map['topics'] as List<dynamic>? ?? [];
    return SyllabusChapter(
      chapterName: map['chapterName'] as String? ?? (map['title'] as String? ?? 'Untitled Chapter'),
      topics: rawTopics
          .map((t) => SyllabusTopic.fromMap(Map<String, dynamic>.from(t)))
          .toList(),
    );
  }
}

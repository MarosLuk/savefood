enum TicketCategory {
  payment,
  pickup,
  cancellation,
  foodQuality,
  merchant,
  other,
}

enum TicketStatus { open, waitingCustomer, inProgress, resolved, closed }

class SupportPhoto {
  const SupportPhoto({
    required this.id,
    required this.width,
    required this.height,
    required this.size,
  });
  final String id;
  final int width, height, size;
  factory SupportPhoto.fromJson(Map<String, dynamic> j) => SupportPhoto(
    id: j['id'] as String,
    width: j['width'] as int,
    height: j['height'] as int,
    size: j['size'] as int,
  );
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.internal = false,
    this.cursor = 0,
    this.attachments = const [],
  });
  final String id, author, body;
  final DateTime createdAt;
  final bool internal;
  final int cursor;
  final List<SupportPhoto> attachments;
  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
    id: j['id'] as String,
    author: j['author'] as String,
    internal: j['internal'] == true,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    cursor: j['cursor'] as int? ?? 0,
    attachments: (j['attachments'] as List? ?? [])
        .map((p) => SupportPhoto.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
  );
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.number,
    required this.subject,
    required this.category,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.orderId,
    this.assignee,
    this.canManage = false,
    this.version = 1,
    this.assigneeName,
    this.unread = false,
    this.nextMessagesCursor,
    this.lastMessageCursor = 0,
    this.hasMoreMessages = false,
    this.draftAttachments = const [],
  });
  final String id, number, subject, priority;
  final String? orderId, assignee;
  final String? assigneeName;
  final TicketCategory category;
  final TicketStatus status;
  final DateTime createdAt, updatedAt;
  final List<SupportMessage> messages;
  final bool canManage;
  final int version;
  final bool unread;
  final int? nextMessagesCursor;
  final int lastMessageCursor;
  final bool hasMoreMessages;
  final List<SupportPhoto> draftAttachments;
  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
    id: j['id'] as String,
    number: j['number'] as String,
    subject: j['subject'] as String,
    orderId: j['orderId'] as String?,
    assignee: j['assignee'] as String?,
    category: TicketCategory.values.byName(j['category'] as String),
    status: TicketStatus.values.byName(j['status'] as String),
    priority: j['priority'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    canManage: j['canManage'] == true,
    version: j['version'] as int? ?? 1,
    unread: j['unread'] == true,
    assigneeName: j['assigneeName'] as String?,
    nextMessagesCursor: j['nextMessagesCursor'] as int?,
    lastMessageCursor: j['lastMessageCursor'] as int? ?? 0,
    hasMoreMessages: j['hasMoreMessages'] == true,
    draftAttachments: (j['draftAttachments'] as List? ?? [])
        .map((p) => SupportPhoto.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    messages: (j['messages'] as List? ?? [])
        .map(
          (m) => SupportMessage.fromJson(Map<String, dynamic>.from(m as Map)),
        )
        .toList(),
  );
}

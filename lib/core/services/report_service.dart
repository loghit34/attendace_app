import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/session_model.dart';
import '../models/session_member_model.dart';

class ReportService {
  /// Generates CSV content from session and member presence data
  static String generateCsv({
    required SessionModel session,
    required List<SessionMemberModel> members,
  }) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<dynamic>>[];

    // Header Metadata
    rows.add(['HereNow Presence Verification Report']);
    rows.add(['Session Name', session.name]);
    rows.add(['Category', session.category]);
    rows.add(['Join Code', session.joinCode]);
    rows.add(['Start Time', dateFormat.format(session.startTime)]);
    rows.add(['End Time', dateFormat.format(session.endTime)]);
    rows.add(['Generated At', dateFormat.format(DateTime.now())]);
    rows.add([]); // empty row

    // Table Header
    rows.add([
      'Member Name',
      'Role',
      'Presence Status',
      'Last Verified At',
      'Joined At',
      'Contact Phone',
    ]);

    for (final member in members) {
      rows.add([
        member.userName,
        member.role.toUpperCase(),
        member.status.displayName,
        member.lastVerifiedAt != null ? dateFormat.format(member.lastVerifiedAt!) : 'Never',
        dateFormat.format(member.joinedAt),
        member.userPhone ?? 'N/A',
      ]);
    }

    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map((cell) {
        final val = cell.toString().replaceAll('"', '""');
        return '"$val"';
      }).join(','));
    }
    return buffer.toString();
  }

  /// Generates clean executive text summary for messaging apps (Slack, WhatsApp, Email)
  static String generateSummaryText({
    required SessionModel session,
    required List<SessionMemberModel> members,
  }) {
    final presentCount = members.where((m) => m.status == PresenceStatus.present || m.status == PresenceStatus.manuallyConfirmed).length;
    final awayCount = members.where((m) => m.status == PresenceStatus.possiblyAway).length;
    final missingCount = members.where((m) => m.status == PresenceStatus.missing).length;
    final total = members.length;
    final rate = total > 0 ? ((presentCount / total) * 100).toStringAsFixed(1) : '0';

    final buffer = StringBuffer();
    buffer.writeln('📍 *HereNow Presence Report*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Group: ${session.name} (${session.category})');
    buffer.writeln('Code: ${session.joinCode}');
    buffer.writeln('Time: ${DateFormat('h:mm a, d MMM').format(DateTime.now())}');
    buffer.writeln('Status: $presentCount / $total Present ($rate%)');
    buffer.writeln('');
    buffer.writeln('🟢 Present: $presentCount');
    buffer.writeln('🟡 Away: $awayCount');
    buffer.writeln('🔴 Missing: $missingCount');

    final missingList = members.where((m) => m.status == PresenceStatus.missing).toList();
    if (missingList.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('🚨 *Missing Members:*');
      for (final m in missingList) {
        buffer.writeln('• ${m.userName}${m.userPhone != null ? " (${m.userPhone})" : ""}');
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('"Know who\'s here, without calling everyone."');
    return buffer.toString();
  }

  /// Share text report via system share sheet
  static Future<void> shareReport({
    required SessionModel session,
    required List<SessionMemberModel> members,
  }) async {
    final text = generateSummaryText(session: session, members: members);
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'HereNow Headcount: ${session.name}',
      ),
    );
  }
}

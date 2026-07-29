import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'community_screen.dart';

class _Msg {
  const _Msg({
    required this.id,
    required this.userId,
    required this.kind,
    required this.body,
    required this.payload,
    required this.at,
  });

  final String id;
  final String userId;
  final String kind; // 'text' | 'report_share'
  final String body;
  final Map<String, dynamic> payload;
  final DateTime at;

  static _Msg fromMap(Map<String, dynamic> m) => _Msg(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        kind: (m['kind'] as String?) ?? 'text',
        body: (m['body'] as String?) ?? '',
        payload:
            (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        at: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// One community's chat room: realtime messages, report-card shares, and
/// report/block moderation. Non-members see a join gate (RLS hides messages
/// from them anyway).
class CommunityRoomScreen extends StatefulWidget {
  const CommunityRoomScreen({
    super.key,
    required this.community,
    required this.joined,
  });

  final Community community;
  final bool joined;

  @override
  State<CommunityRoomScreen> createState() => _CommunityRoomScreenState();
}

class _CommunityRoomScreenState extends State<CommunityRoomScreen> {
  final List<_Msg> _msgs = []; // newest first (ListView is reversed)
  final Set<String> _ids = {};
  final Map<String, String> _names = {};
  Set<String> _blocked = {};
  RealtimeChannel? _channel;
  late bool _joined = widget.joined;
  bool _loading = true;
  bool _sending = false;
  final _input = TextEditingController();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    if (_joined) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _client.removeChannel(channel);
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final blocks =
          await _client.from('community_blocks').select('blocked');
      _blocked = {for (final b in blocks) b['blocked'] as String};

      final rows = await _client
          .from('community_messages')
          .select()
          .eq('community_id', widget.community.id)
          .order('created_at', ascending: false)
          .limit(100);
      final msgs = rows
          .map(_Msg.fromMap)
          .where((m) => !_blocked.contains(m.userId))
          .toList();
      await _fetchNames(msgs.map((m) => m.userId).toSet());
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(msgs);
        _ids
          ..clear()
          ..addAll(msgs.map((m) => m.id));
        _loading = false;
      });
      _subscribe();
    } catch (e) {
      debugPrint('community: room load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchNames(Set<String> userIds) async {
    final missing = userIds.difference(_names.keys.toSet()).toList();
    if (missing.isEmpty) return;
    try {
      final rows = await _client
          .from('member_names')
          .select()
          .inFilter('id', missing);
      for (final r in rows) {
        final name = ((r['name'] as String?) ?? '').trim();
        _names[r['id'] as String] = name.isEmpty ? 'Learner' : name;
      }
    } catch (e) {
      debugPrint('community: names fetch failed: $e');
    }
  }

  void _subscribe() {
    _channel = _client
        .channel('community:${widget.community.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: widget.community.id,
          ),
          callback: (payload) async {
            final m = _Msg.fromMap(payload.newRecord);
            if (_ids.contains(m.id) || _blocked.contains(m.userId)) return;
            await _fetchNames({m.userId});
            if (!mounted) return;
            setState(() {
              _ids.add(m.id);
              _msgs.insert(0, m);
            });
          },
        )
        .subscribe();
  }

  Future<void> _join() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client.from('community_members').insert({
        'community_id': widget.community.id,
        'user_id': uid,
      });
      setState(() {
        _joined = true;
        _loading = true;
      });
      await _load();
    } catch (e) {
      debugPrint('community: join failed: $e');
    }
  }

  Future<void> _leave() async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('community_members').delete().match({
      'community_id': widget.community.id,
      'user_id': uid,
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = _uid;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      final row = await _client
          .from('community_messages')
          .insert({
            'community_id': widget.community.id,
            'user_id': uid,
            'body': text,
          })
          .select()
          .single();
      final m = _Msg.fromMap(row);
      _input.clear();
      if (mounted && !_ids.contains(m.id)) {
        setState(() {
          _ids.add(m.id);
          _msgs.insert(0, m);
        });
      }
    } catch (e) {
      debugPrint('community: send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send — try again")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onLongPress(_Msg m) async {
    final mine = m.userId == _uid;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (mine)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Tokens.rose),
                title: const Text('Delete message'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await _client
                      .from('community_messages')
                      .delete()
                      .eq('id', m.id);
                  if (mounted) {
                    setState(() => _msgs.removeWhere((x) => x.id == m.id));
                  }
                },
              )
            else ...[
              ListTile(
                leading:
                    const Icon(Icons.flag_outlined, color: Tokens.indigoSoft),
                title: const Text('Report message'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final uid = _uid;
                  if (uid == null) return;
                  await _client.from('community_flags').insert({
                    'message_id': m.id,
                    'reporter': uid,
                  });
                  _toast('Reported — thanks for keeping it friendly');
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Tokens.rose),
                title: Text('Block ${_names[m.userId] ?? 'user'}'),
                onTap: () async {
                  Navigator.pop(sheet);
                  final uid = _uid;
                  if (uid == null) return;
                  await _client.from('community_blocks').upsert({
                    'user_id': uid,
                    'blocked': m.userId,
                  });
                  if (mounted) {
                    setState(() {
                      _blocked.add(m.userId);
                      _msgs.removeWhere((x) => x.userId == m.userId);
                    });
                  }
                  _toast("You won't see their messages anymore");
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // Stable accent per sender for their name label (design accents).
  static const _nameColors = [
    Tokens.clay,
    Tokens.teal,
    Tokens.goldText,
    Color(0xFF7C5CB8),
    Color(0xFF356B8C),
    Color(0xFFB03F1F),
  ];

  Color _nameColor(String userId) =>
      _nameColors[userId.hashCode.abs() % _nameColors.length];

  String _time(DateTime at) {
    final local = at.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.community;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            Builder(builder: (_) {
              final (color, tint) = communityStyle(c.slug);
              return Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(c.name[0], style: Type.display(16, color: color)),
              );
            }),
            const SizedBox(width: 10),
            Text(
              c.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          if (_joined)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Tokens.faint),
              color: Tokens.cardHi,
              onSelected: (v) {
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'leave', child: Text('Leave community')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: !_joined
            ? _joinGate()
            : Column(
                children: [
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Tokens.indigoSoft),
                          )
                        : _msgs.isEmpty
                            ? const Center(
                                child: Text(
                                  'Quiet in here… say hi 👋',
                                  style: TextStyle(
                                      color: Tokens.muted, fontSize: 13.5),
                                ),
                              )
                            : ListView.builder(
                                reverse: true,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 8),
                                itemCount: _msgs.length,
                                itemBuilder: (_, i) => _bubble(_msgs[i]),
                              ),
                  ),
                  _composer(),
                ],
              ),
      ),
    );
  }

  Widget _joinGate() {
    final c = widget.community;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          Builder(builder: (_) {
            final (color, tint) = communityStyle(c.slug);
            return Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(c.name[0], style: Type.display(34, color: color)),
            );
          }),
          const SizedBox(height: 18),
          Text(
            c.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            c.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Tokens.muted, fontSize: 13.5, height: 1.5),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _join,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: Tokens.ctaGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Join the conversation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final mine = m.userId == _uid;
    final name = _names[m.userId] ?? 'Learner';
    final content = m.kind == 'report_share'
        ? _reportCard(m)
        : Text(
            m.body,
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _onLongPress(m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: mine ? Tokens.clayTint : Tokens.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: Border.all(color: Tokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _nameColor(m.userId),
                    ),
                  ),
                ),
              content,
              const SizedBox(height: 3),
              Text(
                _time(m.at),
                style: const TextStyle(fontSize: 9.5, color: Tokens.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A shared call report, rendered as a mini score card.
  Widget _reportCard(_Msg m) {
    final overall = (m.payload['overall'] as num?)?.toInt();
    final headline = (m.payload['headline'] as String?) ?? m.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CALL REPORT',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Tokens.faint,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (overall != null)
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Tokens.indigoSoft, width: 2),
                ),
                child: Text(
                  '$overall',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            if (overall != null) const SizedBox(width: 10),
            Expanded(
              child: Text(
                headline,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Write in English…',
                hintStyle:
                    const TextStyle(color: Tokens.faint, fontSize: 13),
                filled: true,
                fillColor: Tokens.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide:
                      const BorderSide(color: Tokens.indigo, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: Tokens.ctaGradient,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

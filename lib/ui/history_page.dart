import 'package:flutter/material.dart';

import '../api/labels.dart';
import '../api/models.dart';
import '../app_state.dart';
import 'common.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});

  final Store store;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _pageSize = 20;

  late bool _hotel;
  late DateTimeRange _range;
  final List<TaskRecord> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  String? _error;
  bool _initialized = false;
  int _req = 0; // 기간/유형을 바꾸면 이전 요청 결과는 버린다

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _hotel = AppScope.read(context).settings.robotType == 'hotel';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
    Future.microtask(() => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (!mounted || (_loading && !reset)) return;
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 0;
        _total = 0;
      }
    });
    try {
      final start = _range.start.millisecondsSinceEpoch;
      // 종료일 23:59:59.999 까지 포함
      final end = _range.end.add(const Duration(days: 1)).millisecondsSinceEpoch - 1;
      final res = await AppScope.read(context).api.getTaskRecords(
            storeId: widget.store.storeId,
            hotel: _hotel,
            page: _page + 1,
            size: _pageSize,
            startTime: start,
            endTime: end,
          );
      if (!mounted || req != _req) return;
      setState(() {
        _items.addAll(res.list);
        _total = res.total;
        _page += 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
      helpText: '조회 기간',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = _items.length < _total;
    return Scaffold(
      appBar: AppBar(title: Text('작업 이력 · ${widget.store.storeName}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('배송 로봇'),
                  selected: !_hotel,
                  onSelected: (_) {
                    setState(() => _hotel = false);
                    _load(reset: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('호텔 로봇'),
                  selected: _hotel,
                  onSelected: (_) {
                    setState(() => _hotel = true);
                    _load(reset: true);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text('${fmtDate(_range.start)} ~ ${fmtDate(_range.end)}'),
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('총 $_total건', style: Theme.of(context).textTheme.bodySmall),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _buildList(hasMore),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool hasMore) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return ErrorView(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return const EmptyView(message: '조회 기간에 작업 기록이 없습니다.', icon: Icons.history);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i == _items.length) {
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('불러오기 오류: $_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            );
          }
          if (!hasMore) return const SizedBox(height: 24);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _loading ? null : () => _load(),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('더 보기 (${_items.length}/$_total)'),
            ),
          );
        }
        final r = _items[i];
        final typeLabel = _hotel ? hotelBizTypeLabel(r.type) : foodTaskModeLabel(r.type);
        final done = r.completed;
        return ListTile(
          dense: true,
          leading: Icon(
            done == false ? Icons.error_outline : Icons.check_circle_outline,
            color: done == false ? Colors.orange.shade800 : Colors.green.shade700,
          ),
          title: Text('$typeLabel · ${r.robotId}'),
          subtitle: Text([
            '시작 ${r.startTime.isEmpty ? '-' : r.startTime}',
            '종료 ${r.endTime.isEmpty ? '-' : r.endTime}',
            if (r.backTime.isNotEmpty) '복귀 ${r.backTime}',
          ].join('\n')),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(r.mileage == null ? '-' : '${r.mileage!.toStringAsFixed(0)} m'),
              if (done != null)
                Text(done ? '완료' : '미완료',
                    style: TextStyle(fontSize: 12, color: done ? Colors.green.shade700 : Colors.orange.shade800)),
            ],
          ),
        );
      },
    );
  }
}

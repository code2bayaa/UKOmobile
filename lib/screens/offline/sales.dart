// The seller's sales balance (movies PRD #10): 70% of every video sold phone to phone, withdrawn to the
// account's M-PESA number (Daraja B2C, the Eden studio withdrawal flow).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/sales_api.dart';

class SellerSalesScreen extends StatefulWidget {
  const SellerSalesScreen({super.key});

  @override
  State<SellerSalesScreen> createState() => _SellerSalesScreenState();
}

class _SellerSalesScreenState extends State<SellerSalesScreen> {
  Map<String, dynamic>? _wallet;
  String? _error;
  bool _withdrawing = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  Future<void> _load() async {
    final res = await SalesApi.wallet();
    if (!mounted) return;
    setState(() {
      if (res['status'] == true) {
        _wallet = res;
        _error = null;
      } else {
        _error = '${res['message'] ?? 'Could not load your sales'}';
      }
    });
  }

  num _n(dynamic v) => num.tryParse('$v') ?? 0;

  Future<void> _withdraw() async {
    final balance = _n(_wallet?['balance']);
    final min = _n(_wallet?['min_withdrawal']);
    final controller = TextEditingController(text: '${balance.floor()}');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw to M-PESA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To ${_wallet?['payout_phone'] ?? 'your profile number'} · minimum KSh ${min.toInt()}',
                style: const TextStyle(color: UkoColors.muted)),
            const SizedBox(height: 12),
            TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: 'KSh ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())), child: const Text('Withdraw')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    setState(() => _withdrawing = true);
    final res = await SalesApi.withdraw(amount);
    if (!mounted) return;
    _snack('${res['message'] ?? (res['status'] == true ? 'Withdrawal started' : 'Could not withdraw')}');
    final id = res['data'] is Map ? int.tryParse('${(res['data'] as Map)['id']}') : null;
    if (res['status'] == true && id != null) {
      // follow the payout until M-PESA answers (settled server-side from the verified result)
      for (var i = 0; i < 24 && !_gone; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final s = await SalesApi.withdrawal(id);
        final state = s['data'] is Map ? '${(s['data'] as Map)['status']}' : '';
        if (state == 'completed') {
          _snack('KSh $amount sent to your M-PESA');
          break;
        }
        if (state == 'failed') {
          _snack('${(s['data'] as Map)['error'] ?? 'The payout failed - the amount is back in your balance'}');
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() => _withdrawing = false);
    _load();
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _stat(String label, dynamic value, {Color color = UkoColors.text}) => Expanded(
        child: Column(
          children: [
            Text('KSh ${_n(value).toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: UkoColors.muted, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    final sales = w?['sales'] is List ? (w!['sales'] as List).whereType<Map>().toList() : <Map>[];
    final withdrawals = w?['withdrawals'] is List ? (w!['withdrawals'] as List).whereType<Map>().toList() : <Map>[];
    final enabled = w?['withdrawals_enabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: UkoColors.destructive)),
              if (w == null && _error == null) const Center(child: CircularProgressIndicator()),
              if (w != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('Balance', style: ukoHeading(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text('KSh ${_n(w['balance']).toStringAsFixed(2)}',
                            style: const TextStyle(color: UkoColors.yellow, fontSize: 30, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Row(children: [_stat('earned', w['earned']), _stat('withdrawn', w['withdrawn'])]),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: enabled && !_withdrawing && _n(w['balance']) >= _n(w['min_withdrawal']) ? _withdraw : null,
                          child: Text(_withdrawing ? 'Withdrawing...' : 'Withdraw to M-PESA'),
                        ),
                        if (!enabled)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('M-PESA withdrawals open soon - your balance is kept safe.',
                                style: TextStyle(color: UkoColors.muted, fontSize: 12), textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Sales', style: ukoHeading(fontSize: 18)),
                if (sales.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No sales yet. Open Downloads and tap "sell" on a video.', style: TextStyle(color: UkoColors.muted)),
                  ),
                for (final s in sales)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${s['name']}', style: const TextStyle(color: UkoColors.text)),
                    subtitle: Text('Sold for KSh ${s['price']}', style: const TextStyle(color: UkoColors.muted)),
                    trailing: Text('+ KSh ${_n(s['earned']).toStringAsFixed(2)}', style: const TextStyle(color: UkoColors.green)),
                  ),
                if (withdrawals.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Withdrawals', style: ukoHeading(fontSize: 18)),
                  for (final x in withdrawals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('KSh ${x['amount']} to ${x['phone']}', style: const TextStyle(color: UkoColors.text)),
                      subtitle: Text('${x['status']}${'${x['error'] ?? ''}'.isNotEmpty ? ' - ${x['error']}' : ''}',
                          style: TextStyle(color: x['status'] == 'failed' ? UkoColors.destructive : UkoColors.muted)),
                      trailing: Text('${x['receipt'] ?? ''}', style: const TextStyle(color: UkoColors.muted, fontSize: 12)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

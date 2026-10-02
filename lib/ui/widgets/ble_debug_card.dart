import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class BleDebugCard extends StatefulWidget {
  final bool isOrganizer;
  final bool bluetoothOn;
  final bool isAdvertising;
  final bool isScanning;
  final String serviceUuid;
  final int discoveredCount;
  final int matchingCount;
  final int? lastRssi;
  final int rssiThreshold;
  final bool sessionMatch;
  final String tokenValidation;
  final String proximityStatus;
  final String backendStatus;
  final bool isExpandedDefault;

  const BleDebugCard({
    super.key,
    required this.isOrganizer,
    required this.bluetoothOn,
    required this.isAdvertising,
    required this.isScanning,
    required this.serviceUuid,
    required this.discoveredCount,
    required this.matchingCount,
    this.lastRssi,
    this.rssiThreshold = -75,
    required this.sessionMatch,
    required this.tokenValidation,
    required this.proximityStatus,
    required this.backendStatus,
    this.isExpandedDefault = true,
  });

  @override
  State<BleDebugCard> createState() => _BleDebugCardState();
}

class _BleDebugCardState extends State<BleDebugCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpandedDefault;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222D) : const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isAdvertising || widget.matchingCount > 0
              ? AppColors.present.withAlpha(120)
              : (isDark ? Colors.white12 : Colors.black12),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Expand/Collapse
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.isAdvertising
                          ? AppColors.present
                          : (widget.isScanning ? AppColors.accent : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BLE DEBUG (${widget.isOrganizer ? "ORGANIZER" : "MEMBER"})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isAdvertising || (widget.isScanning && widget.matchingCount > 0)
                          ? AppColors.present.withAlpha(30)
                          : Colors.black12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.isOrganizer
                          ? (widget.isAdvertising ? 'ADV: ACTIVE' : 'ADV: STANDBY')
                          : (widget.isScanning ? 'SCAN: ACTIVE' : 'SCAN: IDLE'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: widget.isAdvertising || (widget.isScanning && widget.matchingCount > 0)
                            ? AppColors.presentDark
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
                  _buildDebugRow(
                    label: 'Bluetooth Adapter',
                    value: widget.bluetoothOn ? 'ON' : 'OFF',
                    isOk: widget.bluetoothOn,
                  ),
                  _buildDebugRow(
                    label: 'Advertiser Mode',
                    value: widget.isAdvertising ? 'ACTIVE' : 'INACTIVE',
                    isOk: widget.isAdvertising,
                  ),
                  _buildDebugRow(
                    label: 'Scanner Mode',
                    value: widget.isScanning ? 'ACTIVE' : 'INACTIVE',
                    isOk: widget.isScanning,
                  ),
                  _buildDebugRow(
                    label: 'Expected Service UUID',
                    value: widget.serviceUuid.length > 18
                        ? '${widget.serviceUuid.substring(0, 18)}...'
                        : widget.serviceUuid,
                    isOk: true,
                  ),
                  _buildDebugRow(
                    label: 'Advertisements Discovered',
                    value: '${widget.discoveredCount}',
                    isOk: widget.discoveredCount > 0,
                  ),
                  _buildDebugRow(
                    label: 'Matching Advertisements',
                    value: '${widget.matchingCount}',
                    isOk: widget.matchingCount > 0,
                  ),
                  _buildDebugRow(
                    label: 'Last Detected RSSI',
                    value: widget.lastRssi != null
                        ? '${widget.lastRssi} dBm (req >= ${widget.rssiThreshold} dBm)'
                        : 'None yet',
                    isOk: widget.lastRssi != null && widget.lastRssi! >= widget.rssiThreshold,
                  ),
                  _buildDebugRow(
                    label: 'Session Match',
                    value: widget.sessionMatch ? 'YES' : 'NO',
                    isOk: widget.sessionMatch,
                  ),
                  _buildDebugRow(
                    label: 'Token Validation',
                    value: widget.tokenValidation,
                    isOk: widget.tokenValidation == 'PASS',
                  ),
                  _buildDebugRow(
                    label: 'Proximity Status',
                    value: widget.proximityStatus,
                    isOk: widget.proximityStatus == 'NEAR',
                  ),
                  _buildDebugRow(
                    label: 'Backend Verification',
                    value: widget.backendStatus,
                    isOk: widget.backendStatus == 'SUCCESS',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDebugRow({
    required String label,
    required String value,
    required bool isOk,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isOk ? AppColors.presentDark : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

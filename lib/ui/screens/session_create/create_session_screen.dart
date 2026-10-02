import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/session_provider.dart';
import '../organizer/session_qr_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  final String? initialName;

  const CreateSessionScreen({
    super.key,
    this.initialName,
  });

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  GroupType _selectedGroupType = GroupType.company;
  ProximityMode _selectedProximityMode = ProximityMode.normal;
  bool _enableGeofence = false;
  double _geofenceRadius = 100.0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _descController = TextEditingController();

    final now = DateTime.now();
    _startDate = now;
    _startTime = TimeOfDay.fromDateTime(now);
    _endDate = now.add(const Duration(hours: 8));
    _endTime = TimeOfDay.fromDateTime(now.add(const Duration(hours: 8)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = _combineDateAndTime(_startDate, _startTime);
    final endDateTime = _combineDateAndTime(_endDate, _endTime);

    if (endDateTime.isBefore(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final sessionProvider = context.read<SessionProvider>();

    String orgId = authProvider.currentUser?.id ?? '';
    if (orgId.isEmpty || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(orgId)) {
      orgId = const Uuid().v4();
    }

    final created = await sessionProvider.createSession(
      name: _nameController.text.trim(),
      organizerId: orgId,
      organizerName: authProvider.currentUser?.name,
      category: _selectedGroupType.code,
      description: _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : null,
      startTime: startDateTime,
      endTime: endDateTime,
      proximityMode: _selectedProximityMode,
      latitude: _enableGeofence ? 21.6266 : null,
      longitude: _enableGeofence ? 87.5074 : null,
      geofenceRadius: _enableGeofence ? _geofenceRadius : null,
    );

    if (!mounted) return;

    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session "${created.name}" created! Join code: ${created.joinCode}'),
          backgroundColor: AppColors.present,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionQrScreen(session: created),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sessionProvider.errorMessage ?? 'Could not create session. Please try again.'),
          backgroundColor: AppColors.missing,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLoading = context.watch<SessionProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group Session'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Session Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a universal presence verification session for your group.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 20),

            // Session Name Field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Session Name',
                hintText: 'e.g. Engineering Standup, Goa Trip, Lab Session, Match Day',
                prefixIcon: Icon(Icons.group_work_rounded),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter a session name';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Group Type Selection
            Text(
              'GROUP TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GroupType.values.map((type) {
                final isSelected = _selectedGroupType == type;
                return ChoiceChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  selectedColor: AppColors.accent.withAlpha(40),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedGroupType = type);
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Bluetooth Proximity Threshold Selection
            Text(
              'BLUETOOTH PROXIMITY THRESHOLD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: ProximityMode.values.map((mode) {
                final isSelected = _selectedProximityMode == mode;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => setState(() => _selectedProximityMode = mode),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withAlpha(30)
                              : (isDark ? AppColors.darkCard : AppColors.lightCard),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.accent : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              mode.name.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isSelected ? AppColors.accent : (isDark ? AppColors.darkText : AppColors.lightText),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${mode.rssiThreshold} dBm',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Description Field
            TextFormField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'e.g. Automated presence verification before trip departure.',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),

            const SizedBox(height: 24),

            // Start & End Timestamps
            Text(
              'SCHEDULE & AUTO-EXPIRATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start Date',
                        prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                      ),
                      child: Text(DateFormat('d MMM yyyy').format(_startDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (picked != null) setState(() => _startTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start Time',
                        prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                      ),
                      child: Text(_startTime.format(context)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _startDate,
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'End Date',
                        prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                      ),
                      child: Text(DateFormat('d MMM yyyy').format(_endDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (picked != null) setState(() => _endTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Expires At',
                        prefixIcon: Icon(Icons.timer_off_outlined, size: 18),
                      ),
                      child: Text(_endTime.format(context)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Optional Geofence toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: _enableGeofence ? AppColors.accent : (isDark ? AppColors.darkSubtext : AppColors.lightSubtext),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Optional GPS Geofence',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isDark ? AppColors.darkText : AppColors.lightText,
                              ),
                            ),
                            Text(
                              'Verify members are within geographic boundary',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _enableGeofence,
                        onChanged: (val) => setState(() => _enableGeofence = val),
                      ),
                    ],
                  ),
                  if (_enableGeofence) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Geofence Radius', style: TextStyle(fontSize: 13)),
                        Text('${_geofenceRadius.toInt()} meters', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Slider(
                      value: _geofenceRadius,
                      min: 30,
                      max: 500,
                      divisions: 15,
                      label: '${_geofenceRadius.toInt()}m',
                      onChanged: (val) => setState(() => _geofenceRadius = val),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            ElevatedButton.icon(
              onPressed: isLoading ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(isLoading ? 'Creating Session...' : 'Create & Generate QR'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

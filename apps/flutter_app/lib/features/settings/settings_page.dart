import 'package:flutter/material.dart';

import '../../core/i18n/language_config.dart';
import '../../core/settings/app_settings.dart';
import '../../data/consent_store.dart';
import '../../data/reminder_store.dart';
import '../consent/consent_page.dart';
import '../remote/remote_sync_page.dart';
import '../../data/usage_stats.dart';
import 'data_tools.dart';
import 'text_saver_io.dart'
    if (dart.library.js_interop) 'text_saver_web.dart' as text_saver;
import 'install_prompt.dart';
import 'language_selector.dart';

/// Settings hub: language, accessibility (high-contrast + text size) and the
/// remote-monitoring seam. Accessibility preferences are persisted and applied
/// app-wide; they never affect scoring, adaptation or master volume.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.languageStore, this.settingsStore});

  final LanguageStore? languageStore;
  final AppSettingsStore? settingsStore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  late final LanguageStore _languageStore =
      widget.languageStore ?? LanguageStore();
  late final AppSettingsStore _settingsStore =
      widget.settingsStore ?? AppSettingsStore();

  LanguageConfig _language = kEnglishIndia;

  @override
  void initState() {
    super.initState();
    _languageStore.load().then((lang) {
      if (mounted) setState(() => _language = lang);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ValueListenableBuilder<AppSettings>(
            valueListenable: appSettings,
            builder: (context, settings, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionLabel(theme, 'Language'),
                const SizedBox(height: 10),
                _tile(
                  icon: Icons.translate,
                  iconColor: const Color(0xff8b5cf6),
                  title: 'App language',
                  subtitle: '${_language.name} (${_language.nativeName})',
                  trailing: const Icon(Icons.chevron_right, color: _muted),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LanguageSelectorPage(
                          store: _languageStore,
                          onChanged: (lang) =>
                              setState(() => _language = lang),
                        ),
                      ),
                    );
                    // Refresh in case it changed and onChanged wasn't wired.
                    final lang = await _languageStore.load();
                    if (mounted) setState(() => _language = lang);
                  },
                ),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Accessibility'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        key: const Key('high-contrast-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.highContrast,
                        onChanged: (v) => _settingsStore.setHighContrast(v),
                        title: const Text('High-contrast mode',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Brighter text and borders for legibility',
                            style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                      const Divider(color: _border, height: 20),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text('Text size',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                      ),
                      _TextSizeSelector(
                        value: settings.textSize,
                        onChanged: (v) => _settingsStore.setTextSize(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Norms & report'),
                const SizedBox(height: 10),
                _card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Listener age: ${settings.listenerAgeYears} years',
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        Semantics(
                          slider: true,
                          label: 'Listener age in years',
                          child: Slider(
                            key: const Key('listener-age-slider'),
                            value: settings.listenerAgeYears
                                .clamp(4, 90)
                                .toDouble(),
                            min: 4,
                            max: 90,
                            divisions: 86,
                            label: '${settings.listenerAgeYears}',
                            onChanged: (v) =>
                                _settingsStore.setListenerAge(v.round()),
                          ),
                        ),
                        const Text(
                          'Used only to pick the age band for the research '
                          'normative interpretation in results and the report. '
                          'Never affects scoring or adaptation.',
                          style: TextStyle(color: _muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Appearance'),
                const SizedBox(height: 10),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('Theme',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                      ),
                      _ThemeSelector(
                        value: settings.themeChoice,
                        onChanged: (v) => _settingsStore.setThemeChoice(v),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6, bottom: 6),
                        child: Text(
                          'Kids mode is a bright, playful theme for younger '
                          'listeners.',
                          style: TextStyle(color: _muted, fontSize: 12.5),
                        ),
                      ),
                      const Divider(color: _border, height: 20),
                      SwitchListTile(
                        key: const Key('reduced-motion-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.reducedMotion,
                        onChanged: (v) => _settingsStore.setReducedMotion(v),
                        title: const Text('Reduced motion',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Skip pulses and countdown animations',
                            style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                      const Divider(color: _border, height: 20),
                      SwitchListTile(
                        key: const Key('spectrogram-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showSpectrogram,
                        onChanged: (v) => _settingsStore.setShowSpectrogram(v),
                        title: const Text('Show spectrogram',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Show a spectrogram panel under the audio wave',
                            style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                      const Divider(color: _border, height: 20),
                      SwitchListTile(
                        key: const Key('lite-mode-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.liteMode,
                        onChanged: (v) => _settingsStore.setLiteMode(v),
                        title: const Text('Lite visuals',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'System fonts and no decorative animation — for '
                            'low-end devices and slow connections',
                            style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                      const Divider(color: _border, height: 20),
                      SwitchListTile(
                        key: const Key('stimulus-text-switch'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showStimulusText,
                        onChanged: (v) =>
                            _settingsStore.setShowStimulusText(v),
                        title: const Text('Show stimulus text (captions)',
                            style: TextStyle(
                                color: _ink, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                            'Reveal what was said as a caption AFTER each '
                            'answer',
                            style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Practice'),
                const SizedBox(height: 10),
                _card(child: const _ReminderSettings()),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Privacy & data'),
                const SizedBox(height: 10),
                _card(child: _PrivacySection(onChanged: () => setState(() {}))),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'Connectivity'),
                const SizedBox(height: 10),
                _tile(
                  icon: Icons.cloud_sync_outlined,
                  iconColor: const Color(0xff06b6d4),
                  title: 'Remote monitoring',
                  subtitle: 'Link a clinician (offline — data stored locally)',
                  trailing: const Icon(Icons.chevron_right, color: _muted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RemoteSyncPage(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel(theme, 'App'),
                const SizedBox(height: 10),
                const InstallAppButton(),
                const SizedBox(height: 24),
                const Text(
                  'Accessibility settings are presentational only — they never '
                  'change scoring, adaptation or master volume.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        // A transparent Material ancestor lets the SwitchListTile paint its
        // ink/hover effects without being hidden by the card's background.
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      );

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: _glass,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                    border:
                        Border.all(color: iconColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style:
                              const TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSizeSelector extends StatelessWidget {
  const _TextSizeSelector({required this.value, required this.onChanged});

  final TextSizePreference value;
  final ValueChanged<TextSizePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SegmentedButton<TextSizePreference>(
        segments: [
          for (final size in TextSizePreference.values)
            ButtonSegment<TextSizePreference>(
              value: size,
              label: Text(size.label),
            ),
        ],
        selected: <TextSizePreference>{value},
        showSelectedIcon: false,
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }
}



class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.value, required this.onChanged});

  final ThemeChoice value;
  final ValueChanged<ThemeChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeChoice>(
      key: const Key('theme-selector'),
      segments: [
        for (final t in ThemeChoice.values)
          ButtonSegment<ThemeChoice>(
            value: t,
            label: Text(t.label),
          ),
      ],
      selected: <ThemeChoice>{value},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

/// Daily practice reminder controls (in-app banner only — honest about the
/// absence of OS push notifications).
class _ReminderSettings extends StatefulWidget {
  const _ReminderSettings();

  @override
  State<_ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<_ReminderSettings> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  final ReminderStore _store = ReminderStore();
  ReminderSettings _settings = const ReminderSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
  }

  String _hourLabel(int h) {
    final period = h < 12 ? 'am' : 'pm';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display $period';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: LinearProgressIndicator(),
      );
    }
    return Column(
      children: [
        SwitchListTile(
          key: const Key('reminder-switch'),
          contentPadding: EdgeInsets.zero,
          value: _settings.enabled,
          onChanged: (v) async {
            await _store.setEnabled(v);
            if (mounted) {
              setState(() => _settings =
                  ReminderSettings(enabled: v, hour: _settings.hour));
            }
          },
          title: const Text('Daily practice reminder',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Show a gentle banner on the Home screen when nothing has '
              'been practised by the chosen time (in-app only — no push '
              'notifications)',
              style: TextStyle(color: _muted, fontSize: 12.5)),
        ),
        if (_settings.enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Text('Remind me after',
                    style: TextStyle(color: _muted)),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  key: const Key('reminder-hour'),
                  value: _settings.hour,
                  dropdownColor: const Color(0xff1e293b),
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var h = 6; h <= 21; h++)
                      DropdownMenuItem(
                          value: h, child: Text(_hourLabel(h))),
                  ],
                  onChanged: (h) async {
                    if (h == null) return;
                    await _store.setHour(h);
                    if (mounted) {
                      setState(() => _settings =
                          ReminderSettings(enabled: true, hour: h));
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Privacy & data controls (J8): consent status/change, full local-data
/// export (data portability) and delete-everything (right to erasure).
class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.onChanged});

  final VoidCallback onChanged;

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await buildLocalDataExport();
      final path = await text_saver.saveTextFile(
          json,
          'hearbloom-data-'
          '${DateTime.now().toIso8601String().substring(0, 10)}.json');
      messenger.showSnackBar(SnackBar(
          content: Text(path == null
              ? 'Your data has been downloaded as JSON.'
              : 'Your data was saved to $path')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _deleteAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all my data?'),
        content: const Text(
            'This permanently removes every result, questionnaire answer, '
            'streak, favourite and setting stored on this device. If a '
            'study server was linked, ask the study team to erase the '
            'server copy too. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep my data')),
          FilledButton(
              key: const Key('privacy-delete-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffb04545)),
              child: const Text('Delete everything')),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await deleteAllLocalData();
    onChanged();
    messenger.showSnackBar(SnackBar(
        content:
            Text('All local data deleted ($removed stored items removed).')));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: consentState,
      builder: (context, consent, _) => Column(
        children: [
          ListTile(
            key: const Key('privacy-consent'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined,
                color: Color(0xff3b82f6)),
            title: const Text('Research consent',
                style:
                    TextStyle(color: _ink, fontWeight: FontWeight.w600)),
            subtitle: Text(
                consent == null
                    ? 'Not decided yet — tap to review'
                    : consent
                        ? 'Agreed (results are saved) — tap to review'
                        : 'Declined (nothing is saved) — tap to review',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            trailing: const Icon(Icons.chevron_right, color: _muted),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const ConsentPage())),
          ),
          const Divider(color: Color(0x33ffffff), height: 16),
          ListTile(
            key: const Key('privacy-export'),
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.download_outlined, color: Color(0xff22c55e)),
            title: const Text('Export my data (JSON)',
                style:
                    TextStyle(color: _ink, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'A complete copy of everything stored on this device',
                style: TextStyle(color: _muted, fontSize: 12.5)),
            onTap: () => _export(context),
          ),
          const Divider(color: Color(0x33ffffff), height: 16),
          const _UsageStatsTile(),
          const Divider(color: Color(0x33ffffff), height: 16),
          ListTile(
            key: const Key('privacy-delete'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever_outlined,
                color: Color(0xffef4444)),
            title: const Text('Delete all my data',
                style:
                    TextStyle(color: _ink, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Permanently wipe every result and setting on this device',
                style: TextStyle(color: _muted, fontSize: 12.5)),
            onTap: () => _deleteAll(context),
          ),
        ],
      ),
    );
  }
}

/// Opt-in, on-device usage counters (J10): a toggle plus view/clear. Nothing
/// leaves the device; the counters are included in "Export my data".
class _UsageStatsTile extends StatefulWidget {
  const _UsageStatsTile();

  @override
  State<_UsageStatsTile> createState() => _UsageStatsTileState();
}

class _UsageStatsTileState extends State<_UsageStatsTile> {
  final UsageStats _stats = UsageStats();
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _stats.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _view() async {
    final counts = await _stats.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('On-device usage counters'),
        content: SizedBox(
          width: 360,
          child: counts.isEmpty
              ? const Text('Nothing counted yet.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in (counts.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value))))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(e.key)),
                              Text('${e.value}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _stats.clear();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Clear counters'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          key: const Key('usage-stats-switch'),
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          onChanged: (v) async {
            await _stats.setEnabled(v);
            if (mounted) setState(() => _enabled = v);
          },
          title: const Text('On-device usage counters',
              style: TextStyle(
                  color: Color(0xffe2e8f0), fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Count completed exercises per test, on this device only. '
              'Off by default; nothing is ever transmitted.',
              style:
                  TextStyle(color: Color(0xff94a3b8), fontSize: 12.5)),
        ),
        if (_enabled)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('usage-stats-view'),
              onPressed: _view,
              icon: const Icon(Icons.bar_chart, size: 18),
              label: const Text('View / clear counters'),
            ),
          ),
      ],
    );
  }
}


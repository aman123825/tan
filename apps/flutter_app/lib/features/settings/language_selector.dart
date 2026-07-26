import 'package:flutter/material.dart';

import '../../core/i18n/language_config.dart';

/// Settings page listing the supported languages as glass cards. The selection
/// is persisted in SharedPreferences via [LanguageStore].
///
/// Selecting a language records the preference and (optionally) notifies
/// [onChanged]. Generated speech for non-English languages is a separate
/// content step, so those cards are clearly marked "audio pending".
class LanguageSelectorPage extends StatefulWidget {
  const LanguageSelectorPage({super.key, this.store, this.onChanged});

  final LanguageStore? store;
  final ValueChanged<LanguageConfig>? onChanged;

  @override
  State<LanguageSelectorPage> createState() => _LanguageSelectorPageState();
}

class _LanguageSelectorPageState extends State<LanguageSelectorPage> {
  static const Color _muted = Color(0xff94a3b8);

  late final LanguageStore _store = widget.store ?? LanguageStore();
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    _store.loadCode().then((code) {
      if (mounted) setState(() => _selectedCode = code);
    });
  }

  Future<void> _select(LanguageConfig lang) async {
    setState(() => _selectedCode = lang.code);
    await _store.save(lang.code);
    widget.onChanged?.call(lang);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Language set to ${lang.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: _selectedCode == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('Choose a language',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                      'Sets the language for stimulus word pools. English '
                      'ships demo audio today; other languages are configured '
                      'and await generated speech.',
                      style:
                          TextStyle(color: _muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    for (final lang in kSupportedLanguages) ...[
                      _LanguageCard(
                        language: lang,
                        selected: lang.code == _selectedCode,
                        onTap: () => _select(lang),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final LanguageConfig language;
  final bool selected;
  final VoidCallback onTap;

  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _primary = Color(0xff3b82f6);

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? _primary : const Color(0x33ffffff);
    return Semantics(
      button: true,
      selected: selected,
      label: '${language.name}, ${language.nativeName}'
          '${selected ? ', selected' : ''}',
      child: Material(
        color: selected ? const Color(0x1a3b82f6) : const Color(0x1affffff),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('language-${language.code}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: borderColor, width: selected ? 1.6 : 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x1a8b5cf6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x338b5cf6)),
                  ),
                  child: const Icon(Icons.translate,
                      color: Color(0xff8b5cf6), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(language.name,
                              style: const TextStyle(
                                  color: _ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Text(language.nativeName,
                              style: const TextStyle(
                                  color: _muted, fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${language.code} · ${language.wordPool.length} words'
                        '${language.hasBundledSpeech ? '' : ' · audio pending'}',
                        style:
                            const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: _primary, size: 22)
                else
                  const Icon(Icons.circle_outlined,
                      color: Color(0x55ffffff), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'store.dart';
import 'ui.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Appearance')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Card(
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
              Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary, size: 26),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 3),
              Text('Choose a look that feels right for you'),
              ])),
              ]),
              const SizedBox(height: 16),
              for (final option in [
              ('premium', 'Premium & Minimal', 'Navy and violet accents, calm surfaces', Icons.auto_awesome_rounded),
              ('colorful', 'Modern & Colorful', 'Choose your own accent colour', Icons.color_lens_rounded),
              ('glass', 'Soft Glass UI', 'Airy teal tones, softer rounded cards', Icons.blur_on_rounded),
              ])
              Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () { st.themeStyle = option.$1; st.save(); },
              child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
              color: st.themeStyle == option.$1 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              width: st.themeStyle == option.$1 ? 2 : 1,
              ),
              color: st.themeStyle == option.$1 ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.45) : Colors.transparent,
              ),
              child: Row(children: [
              Icon(option.$4, color: Theme.of(context).colorScheme.primary, size: 25),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(option.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(option.$3, style: Theme.of(context).textTheme.bodySmall),
              ])),
              if (st.themeStyle == option.$1) Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
              ]),
              ),
              ),
              ),
              if (st.themeStyle == 'colorful') ...[
              const SizedBox(height: 4),
              const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in palette)
              InkWell(
              customBorder: const CircleBorder(),
              onTap: () { st.seed = p; st.save(); },
              child: CircleAvatar(
              radius: 19,
              backgroundColor: Color(p),
              child: st.seed == p ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
              ),
              ),
              ]),
              ],
              ]),
              ),
              ),
              Card(
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
              Icon(Icons.brightness_6_outlined),
              SizedBox(width: 10),
              Text('Brightness', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
              ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.settings_suggest_outlined)),
              ],
              selected: {st.themeMode},
              onSelectionChanged: (values) {
              final mode = values.first;
              st.themeMode = mode;
              st.dark = mode == 'dark' ||
              (mode == 'system' && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
              st.save();
              },
              ),
              ),
              const SizedBox(height: 8),
              Text(
              st.themeMode == 'system'
              ? 'Follows your phone appearance setting'
              : st.themeMode == 'dark' ? 'Uses the dark version of the selected theme' : 'Uses the light version of the selected theme',
              style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.nightlight_round),
              title: const Text('AMOLED black'),
              subtitle: const Text('Pure black background in dark mode'),
              value: st.amoled,
              onChanged: st.themeMode != 'light' ? (v) { st.amoled = v; st.save(); } : null,
              ),
              ]),
              ),
              ),
            ],
          ),
        ),
      );
}

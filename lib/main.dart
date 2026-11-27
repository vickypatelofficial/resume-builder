import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'resume_pdf_attachment.dart';

const emailBackendTokenStorageKey = 'resume_email_backend_token_v1';
const projectLinksStorageKey = 'resume_project_links_v1';
const resumeStudioVersion = '1.0.1';
const temporaryResumeStorageKey = 'resume_temporary_data_v1';
const resumeSetupAiPrompt = '''I will paste my existing resume. First, extract its details and identify only the project/app names that appear in its Projects section. Before producing the final JSON, ask me one short question requesting the Play Store and/or App Store URLs needed for those exact names. Ask by project/app name in a concise list. Do not mention or ask about any other apps. Do not say that you captured or already received links. Wait for my URL reply before returning the final response.

Use exactly these keys. All values are strings except projectLinks, which is an array of objects:
name, role, email, phone, location, website, portfolio, github, summary, skills, experience, projects, projectLinks, education, certifications.

Rules:
- Keep information truthful. Do not invent or assume missing details; use empty strings for fields not present in the resume.
- Keep experience as role/company/date lines followed by hyphen bullets, with a blank line between jobs.
- Keep projects as project/date lines followed by store labels, tech stack, and hyphen bullets; use a blank line between projects.
- Ask me for store URLs only for project/app names actually present in the resume. Ask in a short list using those exact names and request URLs in this format: App name | Play Store URL | App Store URL.
- Use only URLs I provide in the resume or in my later reply. Never guess, search for, reconstruct, or add URLs for other apps.
- In the final JSON, include projectLinks only for app/project names present in the resume. Put a supplied URL in the matching playStore or appStore field; use an empty string when I did not provide that platform URL.
- Also include matching Play Store: and App Store: app-name lines in the relevant project text only when those links were provided, so the resume preview and PDF can show clickable names.
- Group skills into labeled lines where supported. Keep education factual. Put LinkedIn in website, and keep portfolio and GitHub separate.
- Preserve names, dates, metrics, contact details, and the original meaning.
- After I reply with URLs, return exactly one JSON object inside a copyable ```json code block. Do not put commentary outside the code block. Do not claim that links were captured.

Return this JSON shape:
{"name":"","role":"","email":"","phone":"","location":"","website":"","portfolio":"","github":"","summary":"","skills":"","experience":"","projects":"","projectLinks":[{"project":"","playStore":"","appStore":""}],"education":"","certifications":""}

I will paste my resume first. Ask me only for store URLs needed by apps in that resume. Then return the completed JSON in a copyable code block.''';

class ResumeStyleSettings {
  const ResumeStyleSettings({
    this.horizontalMargin = 17.6,
    this.topMargin = 25.8,
    this.bottomMargin = 35,
    this.contentPadding = 0,
    this.descriptionSize = 10,
    this.headingSize = 13,
    this.subheadingSize = 11,
  });

  final double horizontalMargin, topMargin, bottomMargin, contentPadding;
  final double descriptionSize, headingSize, subheadingSize;

  Map<String, double> toMap() => {
        'horizontalMargin': horizontalMargin,
        'topMargin': topMargin,
        'bottomMargin': bottomMargin,
        'contentPadding': contentPadding,
        'descriptionSize': descriptionSize,
        'headingSize': headingSize,
        'subheadingSize': subheadingSize,
      };

  factory ResumeStyleSettings.fromMap(Map<String, dynamic> map) => ResumeStyleSettings(
        horizontalMargin: (map['horizontalMargin'] as num?)?.toDouble() ?? 17.6,
        topMargin: (map['topMargin'] as num?)?.toDouble() ?? 25.8,
        bottomMargin: (map['bottomMargin'] as num?)?.toDouble() ?? 35,
        contentPadding: (map['contentPadding'] as num?)?.toDouble() ?? 0,
        descriptionSize: (map['descriptionSize'] as num?)?.toDouble() ?? 10,
        headingSize: (map['headingSize'] as num?)?.toDouble() ?? 13,
        subheadingSize: (map['subheadingSize'] as num?)?.toDouble() ?? 11,
      );

  ResumeStyleSettings copyWith({double? horizontalMargin, double? topMargin, double? bottomMargin, double? contentPadding, double? descriptionSize, double? headingSize, double? subheadingSize}) => ResumeStyleSettings(
        horizontalMargin: horizontalMargin ?? this.horizontalMargin,
        topMargin: topMargin ?? this.topMargin,
        bottomMargin: bottomMargin ?? this.bottomMargin,
        contentPadding: contentPadding ?? this.contentPadding,
        descriptionSize: descriptionSize ?? this.descriptionSize,
        headingSize: headingSize ?? this.headingSize,
        subheadingSize: subheadingSize ?? this.subheadingSize,
      );
}

void main() => runApp(const ResumeApp());

class ResumeApp extends StatelessWidget {
  const ResumeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Resume Studio - $resumeStudioVersion',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245b54)),
          scaffoldBackgroundColor: const Color(0xfff4f6f3),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xffe4e9e5))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xff245b54), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        home: const ResumeHome(),
      );
}

class ResumeData {
  String name = '', role = '', email = '', phone = '', location = '', website = '';
  String portfolio = '', github = '', summary = '', experience = '';
  String education = '', skills = '', projects = '', certifications = '';

  Map<String, String> toMap() => {
        'name': name, 'role': role, 'email': email, 'phone': phone, 'location': location,
        'website': website, 'portfolio': portfolio, 'github': github, 'summary': summary, 'experience': experience, 'education': education,
        'skills': skills, 'projects': projects, 'certifications': certifications,
      };

  void fromMap(Map<String, dynamic> map) {
    name = map['name'] ?? name; role = map['role'] ?? role; email = map['email'] ?? email;
    phone = map['phone'] ?? phone; location = map['location'] ?? location; website = map['website'] ?? website;
    portfolio = map['portfolio'] ?? portfolio; github = map['github'] ?? github;
    summary = map['summary'] ?? summary; experience = map['experience'] ?? experience;
    education = map['education'] ?? education; skills = map['skills'] ?? skills;
    projects = map['projects'] ?? projects; certifications = map['certifications'] ?? certifications;
  }
}

class ResumeHome extends StatefulWidget {
  const ResumeHome({super.key});
  @override
  State<ResumeHome> createState() => _ResumeHomeState();
}

class _ResumeHomeState extends State<ResumeHome> {
  final data = ResumeData();
  final baseResume = ResumeData().toMap();
  ResumeStyleSettings style = const ResumeStyleSettings();
  final secureStorage = const FlutterSecureStorage();
  final controllers = <String, TextEditingController>{};
  List<Map<String, String>> projectLinks = [];
  List<List<_PdfPreviewLink>> _pdfPreviewLinks = [];
  String _pdfPreviewLinksSignature = '';
  bool loaded = false, saving = false;
  bool isTemporaryResume = false;
  bool firstRunDialogShown = false;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    for (final e in data.toMap().entries) { controllers[e.key] = TextEditingController(text: e.value); }
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('resume_data_v2');
    final baseRaw = prefs.getString('resume_base_data_v1');
    if (baseRaw == null) {
      await prefs.setString('resume_base_data_v1', jsonEncode(baseResume));
    } else {
      baseResume.addAll(Map<String, String>.from(jsonDecode(baseRaw)));
    }
    final styleRaw = prefs.getString('resume_style_v1');
    final linksRaw = prefs.getString(projectLinksStorageKey);
    if (linksRaw != null) {
      projectLinks = (jsonDecode(linksRaw) as List).whereType<Map>().map((item) => Map<String, String>.from(item)).toList();
    }
    if (styleRaw != null) {
      style = ResumeStyleSettings.fromMap(Map<String, dynamic>.from(jsonDecode(styleRaw)));
    }
    if (raw != null) {
      data.fromMap(Map<String, dynamic>.from(jsonDecode(raw)));
      data.education = _normalizeEducation(data.education);
      data.projects = data.projects.replaceAll(RegExp(r'\n\s*Zenfoo Customer\nPlay Store: Zenfoo Customer\nApp Store: Zenfoo Customer\s*$'), '');
      data.projects = data.projects.replaceAll('Play Store: PoolPal User, PoolPal Captain\nApp Store: PoolPal User, PoolPal Captain', 'Play Store: PoolPal User, PoolPal Captain | App Store: PoolPal User, PoolPal Captain');
      data.projects = data.projects.replaceAll('Astro sane (Astrology Consultation App) | Jan 2025 - May 2025\nTech Stack:', 'Astro sane (Astrology Consultation App) | Jan 2025 - May 2025\nPlay Store: AstroSane\nTech Stack:');
      for (final e in data.toMap().entries) { controllers[e.key]!.text = e.value; }
    }
    final temporaryRaw = prefs.getString(temporaryResumeStorageKey);
    if (temporaryRaw != null) {
      try {
        _activateResumePayload(Map<String, dynamic>.from(jsonDecode(temporaryRaw)), temporary: true, refresh: false);
      } catch (_) {
        await prefs.remove(temporaryResumeStorageKey);
      }
    }
    if (mounted) setState(() => loaded = true);
    if (mounted && _resumeIsEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showFirstRunSetup();
      });
    }
  }

  bool get _resumeIsEmpty => controllers.values.every((controller) => controller.text.trim().isEmpty);

  Map<String, dynamic> _decodeResumeJson(String source, {dynamic fallbackLinks}) {
    final clean = source.trim().replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '').replaceFirst(RegExp(r'\s*```$'), '');
    final decoded = jsonDecode(clean);
    if (decoded is! Map) throw const FormatException('Paste a JSON object containing the resume fields.');
    final json = Map<String, dynamic>.from(decoded);
    final fields = ResumeData().toMap();
    for (final key in fields.keys) {
      final value = json[key];
      if (value == null) {
        fields[key] = '';
      } else if (value is String) {
        fields[key] = value;
      } else if (value is List) {
        fields[key] = value.map((item) => item.toString()).join('\n');
      } else {
        throw FormatException('The "$key" value must be text.');
      }
    }
    final rawLinks = json['projectLinks'] ?? fallbackLinks ?? const <dynamic>[];
    if (rawLinks is! List) throw const FormatException('The projectLinks value must be a JSON array.');
    final links = <Map<String, String>>[];
    for (final item in rawLinks) {
      if (item is! Map) continue;
      String read(List<String> keys) => keys.map((key) => item[key]?.toString().trim() ?? '').firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final link = <String, String>{
        'project': read(['project', 'app', 'name']),
        'playStore': read(['playStore', 'play_store', 'googlePlay']),
        'appStore': read(['appStore', 'app_store', 'appleAppStore']),
      };
      if (link['project']!.isNotEmpty && (link['playStore']!.isNotEmpty || link['appStore']!.isNotEmpty)) links.add(link);
    }
    return {...fields, 'projectLinks': links};
  }

  bool _payloadHasContent(Map<String, dynamic> payload) =>
      ResumeData().toMap().keys.any((key) => (payload[key] as String? ?? '').trim().isNotEmpty);

  Map<String, dynamic> _savedMainResumePayload(SharedPreferences prefs) {
    final raw = prefs.getString('resume_data_v2');
    final linkRaw = prefs.getString(projectLinksStorageKey);
    final fallbackLinks = linkRaw == null ? const <dynamic>[] : jsonDecode(linkRaw);
    if (raw == null) return {...(isTemporaryResume ? ResumeData().toMap() : data.toMap()), 'projectLinks': fallbackLinks};
    return _decodeResumeJson(raw, fallbackLinks: fallbackLinks);
  }

  void _activateResumePayload(Map<String, dynamic> payload, {required bool temporary, bool refresh = true}) {
    final normalized = _decodeResumeJson(jsonEncode(payload));
    final fields = Map<String, dynamic>.from(normalized)..remove('projectLinks');
    data.fromMap(fields);
    data.education = _normalizeEducation(data.education);
    for (final entry in data.toMap().entries) {
      controllers[entry.key]!.text = entry.value;
    }
    projectLinks = (normalized['projectLinks'] as List).whereType<Map>().map((item) => Map<String, String>.from(item)).toList();
    isTemporaryResume = temporary;
    if (refresh && mounted) setState(() {});
  }

  Future<void> _save() async {
    _syncDataFromControllers();
    setState(() => saving = true);
    final prefs = await SharedPreferences.getInstance();
    if (isTemporaryResume) {
      await prefs.setString(temporaryResumeStorageKey, jsonEncode({...data.toMap(), 'projectLinks': projectLinks}));
    } else {
      if (baseResume.values.every((value) => value.trim().isEmpty) && data.toMap().values.any((value) => value.trim().isNotEmpty)) {
        baseResume
          ..clear()
          ..addAll(data.toMap());
        await prefs.setString('resume_base_data_v1', jsonEncode(baseResume));
      }
      await prefs.setString('resume_data_v2', jsonEncode(data.toMap()));
      await prefs.setString(projectLinksStorageKey, jsonEncode(projectLinks));
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _copyResumeJson() async {
    _syncDataFromControllers();
    final json = JsonEncoder.withIndent('  ').convert({...data.toMap(), 'projectLinks': projectLinks});
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resume JSON copied.')));
  }

  Future<void> _showImportResumeJsonDialog() async {
    final jsonController = TextEditingController();
    String? errorText;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
          title: const Text('Import and save resume JSON'),
          content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Paste a complete resume JSON object. This replaces the saved resume.'),
            const SizedBox(height: 10),
            TextField(controller: jsonController, minLines: 10, maxLines: 16, decoration: const InputDecoration(labelText: 'Resume JSON', alignLabelWithHint: true)),
            if (errorText != null) ...[const SizedBox(height: 8), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                final existingMain = _savedMainResumePayload(prefs);
                final payload = _decodeResumeJson(jsonController.text, fallbackLinks: existingMain['projectLinks']);
                if (!_payloadHasContent(payload)) throw const FormatException('The JSON does not contain resume content.');
                await prefs.remove(temporaryResumeStorageKey);
                _activateResumePayload(payload, temporary: false);
                baseResume
                  ..clear()
                  ..addAll(data.toMap());
                await prefs.setString('resume_base_data_v1', jsonEncode(baseResume));
                await _save();
                if (!mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Resume JSON imported and saved.')));
              } catch (error) {
                refreshDialog(() => errorText = error.toString().replaceFirst('FormatException: ', ''));
              }
            }, child: const Text('Import and save')),
          ],
        )),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      jsonController.dispose();
    }
  }

  String _temporaryResumePrompt(Map<String, dynamic> source, String jobDescription) {
    final sourceJson = JsonEncoder.withIndent('  ').convert(source);
    final jdText = jobDescription.trim().isEmpty
        ? '[The complete job description will be pasted below this prompt]'
        : jobDescription.trim();
    return '''# ATS-Optimized Resume Tailoring — Master Prompt (With Strict Data Validation)

You are an expert ATS resume strategist, technical recruiter, and resume editor specializing in software development roles. Create a temporary resume tailored specifically to the complete job description (JD), using the complete source resume JSON below.

## Primary objective
- Match the JD using factual details from the source resume and the candidate hands-on experience statement below.
- Include every technical skill and technology required or preferred in the JD, because the candidate confirms having already worked with all JD-listed items.
- Preserve every existing supported skill, even if it is not mentioned in the JD.
- Organize skills into clear technical categories and prioritize mandatory and repeated JD requirements.
- Improve ATS keyword matching naturally, without keyword stuffing. Do not produce a generic resume.
- Do not invent employers, dates, specific duties, achievements, metrics, certifications, education, or links. Use the candidate's hands-on statement for JD technologies, but only place those technologies under a specific job or project when its existing context is relevant.

## Candidate hands-on experience statement
The candidate explicitly states: "I have already worked with all skills and technologies in the job description, and I want the relevant technology stacks, project descriptions, and experience tailored to reflect that work." Treat this as the candidate's confirmation of hands-on work with every skill and technology actually named in the supplied JD. Include every JD skill in the Skills section, even when the source resume does not document it. Tailor relevant existing experience bullets, project descriptions, and technology stacks to surface this candidate-confirmed work. Do not assign a JD technology to every job or project automatically; place it only where the existing role or project context is relevant. Do not invent employers, project names, dates, specific responsibilities, results, metrics, certifications, degrees, or qualifications. Do not infer related tools or adjacent expertise that are not named in the JD or source resume.

## Reference length and one-page fit — mandatory
Use the source resume's one-page A4 resume as the size and density target. Return content that fits one page at the existing resume font sizes and margins; do not make the resume smaller by reducing font size, hiding sections, or changing page settings. Keep the same section order and comparable visual density. Be concise, but do not omit skills or important evidence to meet a word target. Target a summary of 35–45 words, keep all source jobs and projects, use at most 2 concise bullets per job and 2 per project, and keep each bullet to about 15–22 words where the facts allow. Preserve key supported achievements, metrics, integrations, and responsibilities while removing repetition. Keep education to its original concise details. If the source resume has more entries than these targets, preserve all entries and shorten wording rather than deleting them. If full truthful JD and saved-resume skill coverage needs extra space, preserve that coverage and tighten repetitive prose elsewhere; never drop skills to force a one-page fit.

## 1. Analyze the complete JD first
Internally identify the target title, required experience, JD location and work arrangement, employment type, responsibilities, mandatory and preferred skills, programming languages, frameworks/platforms, state management, API/backend technologies, databases/storage, architecture, testing, DevOps/CI/CD/version control, cloud services, payment integrations, monitoring/analytics/debugging, and professional competencies. Do not overlook a requirement because it appears only once.

Prioritize skills in this order: explicitly mandatory; required/must-have; strong hands-on requirements; repeated skills; technologies tied to responsibilities; preferred skills; then other relevant skills.

## 2. Skill evidence, categories, and order
Compare every individual JD skill against the source resume. Treat the candidate hands-on experience statement above as direct confirmation that the candidate has worked with every skill and technology actually named in the JD. Include every such JD skill and every existing source-resume skill in the Skills section. Use the candidate's confirmation to tailor relevant existing experience and project descriptions, while preserving the source's employer, project, date, responsibility, and achievement facts. Do not imply a JD technology was used in every role or project; connect it only to relevant existing work, and do not infer adjacent skills absent from both the JD and source resume.

Keep the Skills section to exactly 8 compact category rows, matching the source resume's eight-row Skills section. Use clear category labels and combine closely related categories where needed (for example, Frameworks / State Management, Database / Cloud, or Tools / Version Control). Use relevant categories such as Programming Languages, Frameworks / Platforms, State Management, API & Backend, Database / Local Storage, Architecture, Third-Party Integrations, Device & Location, Tools, and Other. Choose exactly 8 rows that best fit the supported skills and JD; do not output more than 8 category rows or reduce this to only 8 individual skill names. Keep each category and its comma-separated skills compact enough for the one-page layout.

The eight rows are a compact layout requirement, not a limit on the number of individual skills. Include every skill already present in the saved/source resume's skills field and every skill or technology named in the JD, based on the candidate's hands-on experience statement. Do not omit a known skill because it is not requested by the JD, and do not omit a JD skill because the source resume does not mention it or because of space. Group related skills under the eight appropriate category labels, using comma-separated lists. Within each category, order mandatory and repeated JD skills first, then other JD skills, then remaining saved-resume skills. Do not add adjacent skills that are not named in the JD or source resume, duplicates, or miscategorized technologies.

Examples: if the JD emphasizes BLoC, put BLoC first under State Management; if it emphasizes Dart, put Dart first under Programming Languages. The candidate confirms hands-on work with technologies named in the JD, but this does not authorize adding related technologies that the JD does not name. Do not infer Dio from REST APIs, GetX from BLoC/Provider, Swift from iOS work, native Android from Kotlin/Java alone, or CI/CD from Git alone.

## 3. Role and summary
The role field must contain only the exact official target title stated in the JD's hiring title or designated position title. Preserve its wording and seniority. Do not append languages, frameworks, tools, skills, specializations, pipes, commas, or descriptive keywords. Do not keep the old title if the JD gives a different target title. If no JD is supplied or no target title is stated, preserve the source role; do not guess a target.

Write a concise professional summary of 35–45 words to match the source resume's space. Use actual years of experience from the source. Prioritize the strongest JD skills and technologies the candidate confirms having worked with, plus relevant architecture, integrations, databases, and platforms. Use natural language, do not inflate years or outcomes, and avoid keyword stuffing.

## 4. Experience
- Preserve job titles, employer names, dates, and chronology exactly.
- Prioritize JD-relevant responsibilities and candidate-confirmed JD technologies when they fit the existing work context. Improve grammar, remove unnecessary repetition, and use clear action verbs.
- Keep every job, with at most 2 concise bullets per job; combine related facts from the same source bullet when useful without losing important supported details.
- Use metrics only when present in the source. Keep responsibilities and achievements factual; the candidate's statement confirms hands-on work with JD technologies but does not supply unmentioned results or duties.
- Do not transfer tools or accomplishments between employers or projects. Do not change job titles to match the target role or add responsibilities merely because they appear in the JD.

## 5. Projects
- Preserve all projects, names, dates, project order, and factual details.
- Update relevant project technology stacks and descriptions to surface the JD technologies the candidate confirms having used, while keeping each technology connected only to projects where the existing context fits.
- Keep every project, with at most 2 concise bullets per project; retain each project's factual stack and key features, and add candidate-confirmed JD technologies where that project's context fits.
- Do not invent features, integrations, achievements, or technologies outside the JD and source resume; do not transfer details from one project to another; do not remove projects.
- Preserve the projectLinks array exactly: same objects, names, URLs, empty strings, and order. Do not add, remove, search for, normalize, or change any project link or URL character.

## 6. Location and personal information
- Preserve the candidate's actual location exactly as supplied. Never replace it with the employer's location.
- Do not claim relocation, remote, hybrid, or onsite availability unless explicitly supported by the source.
- Preserve the meaning of name, phone, email, website, portfolio, GitHub, education, certifications, and all other personal details. Do not invent missing information.
- You may use JD location/work arrangement to understand the role, but it is not the candidate's location.

## 7. Contact field normalization
Return contact fields as clean plain text, extracting underlying values from Markdown or HTML if present. Email must be only the email address, with no label, Markdown, brackets, parentheses, or mailto:. Website, portfolio, and GitHub must be only their original URL, without Markdown/HTML wrappers or descriptive link text. Preserve URL spelling and do not shorten, modify, or add tracking parameters. Phone must contain only the original phone number. If a contact value is absent, return an empty string; never guess one.

This normalization applies only to email, website, portfolio, GitHub, and phone. It does not apply to projectLinks, which must remain byte-for-byte unchanged in value.

## 8. Education and certifications
Preserve institution, degree, graduation year, location, CGPA, and certification details. Keep empty source fields empty. Do not invent courses, qualifications, certifications, or academic achievements.

## 9. Final validation
Before output, verify internally that the Skills section has exactly 8 compact category rows and includes every skill from the saved/source skills field plus every skill and technology named in the JD. Confirm no skill was lost, all skills are categorized and ordered by JD priority, no adjacent skills were inferred, and relevant experience and project descriptions surface candidate-confirmed JD technology work without assigning every technology to every role or inventing specific duties, outcomes, or metrics. Confirm the role is only the exact JD title, candidate location and contact details remain accurate, employers, dates, projects, metrics, education, certifications, and chronology are factual, and projectLinks is exactly unchanged. Check that the summary and bullets meet the length guidance, all source jobs/projects remain, and the content fits one A4 page using the existing font sizes and margins. If it would overflow, shorten repetitive prose first; never remove skills or factual sections or reduce font size. Ensure content is ATS-readable and tailored rather than generic. Correct any failed check before responding.

## 10. Output format — strict
Return exactly one complete, valid JSON object inside a single copyable json code block. Do not include analysis, explanations, tables, match percentages, notes, recommendations, or any text outside that block. Include exactly these keys and no extras, using this shape:
{"name":"","role":"","email":"","phone":"","location":"","website":"","portfolio":"","github":"","summary":"","skills":"","experience":"","projects":"","projectLinks":[{"project":"","playStore":"","appStore":""}],"education":"","certifications":""}

Every value must be a string except projectLinks, which must remain the original array of objects with project, playStore, and appStore strings. Keep every required key, use valid JSON, escape newline characters correctly, and do not use comments or trailing commas. This is a separate temporary resume; never claim to modify or overwrite the saved resume.

SOURCE RESUME JSON:
```json
$sourceJson
```

JOB DESCRIPTION:
$jdText''';
  }

  Future<void> _showCreateTemporaryResumeDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final source = _savedMainResumePayload(prefs);
    if (!_payloadHasContent(source)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add or import a saved resume before creating a temporary version.')));
      return;
    }
    final outputController = TextEditingController();
    String? errorText;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
          title: const Text('Create temporary JD resume'),
          content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Copy the prompt, paste it into any AI tool, then add the job description in the prompt where indicated. Paste the AI’s JSON response below to create a temporary resume without replacing your saved one.'),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _temporaryResumePrompt(source, '')));
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Prompt copied with your saved resume JSON and a JD paste section.')));
            }, icon: const Icon(Icons.content_copy), label: const Text('Copy prompt for AI tool')),
            const SizedBox(height: 8),
            TextField(controller: outputController, minLines: 8, maxLines: 13, decoration: const InputDecoration(labelText: 'Paste the AI temporary resume JSON', alignLabelWithHint: true)),
            if (errorText != null) ...[const SizedBox(height: 8), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton.icon(onPressed: () async {
              try {
                final payload = _decodeResumeJson(outputController.text, fallbackLinks: source['projectLinks']);
                if (!_payloadHasContent(payload)) throw const FormatException('The AI response does not contain resume content.');
                final storedPayload = {...payload, 'projectLinks': payload['projectLinks']};
                await prefs.setString(temporaryResumeStorageKey, jsonEncode(storedPayload));
                _activateResumePayload(storedPayload, temporary: true);
                if (!mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Temporary resume created. Your saved resume is unchanged.')));
              } catch (error) {
                refreshDialog(() => errorText = error.toString().replaceFirst('FormatException: ', ''));
              }
            }, icon: const Icon(Icons.auto_awesome), label: const Text('Use as temporary resume')),
          ],
        )),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      outputController.dispose();
    }
  }

  Future<void> _removeTemporaryResume() async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Remove temporary resume?'),
      content: const Text('This removes the temporary version and returns to your saved resume.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove temporary resume')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(temporaryResumeStorageKey);
    final mainPayload = _savedMainResumePayload(prefs);
    _activateResumePayload(mainPayload, temporary: false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Temporary resume removed. Your saved resume is restored.')));
  }

  Future<void> _showFirstRunSetup() async {
    if (firstRunDialogShown || !mounted) return;
    firstRunDialogShown = true;
    final outputController = TextEditingController();
    String? errorText;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
          title: const Row(children: [Icon(Icons.description_outlined), SizedBox(width: 10), Text('Set up your resume')]),
          content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your resume starts empty. Use the prompt to extract details from your resume with any AI tool, then paste the AI response here. You can also enter everything manually.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: resumeSetupAiPrompt));
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Resume setup prompt copied.')));
            }, icon: const Icon(Icons.content_copy), label: const Text('Copy resume prompt')),
            const SizedBox(height: 8),
            TextField(controller: outputController, minLines: 8, maxLines: 14, decoration: const InputDecoration(labelText: 'Paste the AI JSON response', alignLabelWithHint: true, hintText: '{"name":"...","role":"...","skills":"...", ...}')),
            if (errorText != null) ...[const SizedBox(height: 10), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Enter manually')),
            FilledButton.icon(onPressed: () async {
              try {
                final imported = _parsePastedTailoringOutput(outputController.text);
                final hasContent = ['name', 'role', 'email', 'summary', 'skillsText', 'experienceText', 'projectsText', 'educationText']
                    .any((key) => (imported[key] as String? ?? '').trim().isNotEmpty);
                if (!hasContent) throw Exception('The pasted response did not contain resume details. Copy the setup prompt and try again.');
                _applyPastedTailoringOutput(imported);
                await _save();
                if (!mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(this.context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Resume details imported and saved. You can edit them anytime.')));
              } catch (e) {
                refreshDialog(() => errorText = e.toString().replaceFirst('Exception: ', ''));
              }
            }, icon: const Icon(Icons.save_outlined), label: const Text('Import and save')),
          ],
        )),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      outputController.dispose();
    }
  }

  Future<void> _resetResumeData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset resume data?'),
        content: const Text('This clears the saved resume content from this device. Your page layout settings and AI keys will remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reset data')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final controller in controllers.values) {
      controller.clear();
    }
    _syncDataFromControllers();
    baseResume
      ..clear()
      ..addAll(ResumeData().toMap());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('resume_data_v2');
    await prefs.remove(projectLinksStorageKey);
    await prefs.remove(temporaryResumeStorageKey);
    isTemporaryResume = false;
    projectLinks = [];
    await prefs.setString('resume_base_data_v1', jsonEncode(baseResume));
    setState(() {});
    firstRunDialogShown = false;
    await _showFirstRunSetup();
  }

  void _syncDataFromControllers() {
    for (final e in controllers.entries) {
      _setField(e.key, e.value.text);
    }
  }

  Future<void> _showTailorDialog({bool pasteOnly = false}) async {
    final keyController = TextEditingController();
    final jdController = TextEditingController();
    final modelController = TextEditingController();
    final pastedController = TextEditingController();
    var provider = pasteOnly ? 'Paste AI output' : 'Gemini';
    var loadingDraft = false;
    String? errorText;
    String keyName(String value) => 'resume_ai_${value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_api_key';
    const providers = ['OpenAI', 'Gemini', 'Claude', 'DeepSeek', 'OpenRouter', 'Groq', 'Mistral', 'xAI', 'Paste AI output'];
    String defaultModel(String value) => const {
      'OpenAI': 'gpt-6-luna',
      'Gemini': 'gemini-3.8-flash',
      'Claude': 'claude-sonnet-4-20250514',
      'DeepSeek': 'deepseek-flash',
      'OpenRouter': 'openrouter/auto',
      'Groq': 'llama-3.3-70b-versatile',
      'Mistral': 'mistral-large-latest',
      'xAI': 'grok-4',
      'Paste AI output': '',
    }[value]!;

    final prefs = await SharedPreferences.getInstance();
    if (!pasteOnly) provider = prefs.getString('resume_ai_provider') ?? provider;
    if (!providers.contains(provider)) provider = 'Gemini';
    modelController.text = prefs.getString('resume_ai_model_$provider') ?? defaultModel(provider);

    try {
      if (provider != 'Paste AI output') keyController.text = await secureStorage.read(key: keyName(provider)) ?? '';
    } catch (_) {
      // Keep the form usable if secure storage is unavailable on this platform.
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refreshDialog) => AlertDialog(
            title: Row(children: [const Icon(Icons.auto_awesome), const SizedBox(width: 10), Text(pasteOnly ? 'Paste AI output' : 'Tailor resume to a job')]),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pasteOnly ? 'Paste the resume content generated by your external AI tool.' : 'Choose an AI provider or paste results from an AI tool you used elsewhere.'),
                const SizedBox(height: 14),
                if (!pasteOnly) DropdownButtonFormField<String>(
                  value: provider,
                  decoration: const InputDecoration(labelText: 'AI provider'),
                  items: const [
                    DropdownMenuItem(value: 'OpenAI', child: Text('OpenAI / ChatGPT')),
                    DropdownMenuItem(value: 'Gemini', child: Text('Google Gemini')),
                    DropdownMenuItem(value: 'Claude', child: Text('Anthropic Claude')),
                    DropdownMenuItem(value: 'DeepSeek', child: Text('DeepSeek')),
                    DropdownMenuItem(value: 'OpenRouter', child: Text('OpenRouter — 600+ models')),
                    DropdownMenuItem(value: 'Groq', child: Text('Groq')),
                    DropdownMenuItem(value: 'Mistral', child: Text('Mistral AI')),
                    DropdownMenuItem(value: 'xAI', child: Text('xAI Grok')),
                    DropdownMenuItem(value: 'Paste AI output', child: Text('Paste AI output from another tool')),
                  ],
                  onChanged: loadingDraft ? null : (value) async {
                    if (value == null) return;
                    refreshDialog(() { provider = value; keyController.clear(); modelController.text = defaultModel(value); });
                    if (value == 'Paste AI output') return;
                    try {
                      final savedKey = await secureStorage.read(key: keyName(value));
                      final savedModel = prefs.getString('resume_ai_model_$value');
                      if (context.mounted && provider == value) refreshDialog(() {
                        keyController.text = savedKey ?? '';
                        modelController.text = savedModel ?? defaultModel(value);
                      });
                    } catch (_) {
                      if (context.mounted) refreshDialog(() => errorText = 'Secure storage is unavailable on this platform.');
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (provider == 'Paste AI output') ...[
                  Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: loadingDraft ? null : _copyExternalAiPrompt, icon: const Icon(Icons.content_copy), label: const Text('Copy prompt for external AI'))),
                  const SizedBox(height: 8),
                  TextField(controller: pastedController, minLines: 8, maxLines: 16, decoration: const InputDecoration(labelText: 'Paste AI-generated resume sections', alignLabelWithHint: true, hintText: 'Paste JSON or use labeled sections such as:\nROLE:\nSUMMARY:\nSKILLS:\nEXPERIENCE:\nPROJECTS:\nCERTIFICATIONS:\nJD SKILLS:\nMISSING SKILLS:')),
                  const SizedBox(height: 12),
                ] else ...[
                  TextField(controller: modelController, decoration: InputDecoration(labelText: 'Model ID', helperText: provider == 'OpenRouter' ? 'Use any OpenRouter model ID in provider/model format.' : 'Default shown; enter any model ID enabled for this API key.')),
                  const SizedBox(height: 12),
                  TextField(controller: keyController, obscureText: true, decoration: InputDecoration(labelText: '$provider API key', helperText: 'Saved securely on this device. You can change it here anytime.')),
                  const SizedBox(height: 12),
                ],
                if (provider != 'Paste AI output') TextField(controller: jdController, minLines: 7, maxLines: 12, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Job description', alignLabelWithHint: true, hintText: 'Paste the complete job description here.')),
                if (errorText != null) ...[const SizedBox(height: 12), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
                if (loadingDraft) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
                const SizedBox(height: 8),
                Text(provider == 'Paste AI output' ? 'No AI call is made. Pasted sections are imported and saved directly; you can edit them in the resume editor.' : 'Your resume and job description are sent to the selected provider. API use may be billed by that provider.', style: const TextStyle(fontSize: 12, color: Color(0xff68756e))),
              ])),
            ),
            actions: [
              TextButton(onPressed: loadingDraft ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              if (provider != 'Paste AI output') TextButton.icon(
                onPressed: loadingDraft ? null : () async {
                  try {
                    final value = keyController.text.trim();
                    if (value.isEmpty) {
                      await secureStorage.delete(key: keyName(provider));
                    } else {
                      await secureStorage.write(key: keyName(provider), value: value);
                    }
                    await prefs.setString('resume_ai_provider', provider);
                    await prefs.setString('resume_ai_model_$provider', modelController.text.trim());
                    if (context.mounted) refreshDialog(() => errorText = value.isEmpty ? 'Saved key removed.' : 'API key saved securely.');
                  } catch (e) {
                    if (context.mounted) refreshDialog(() => errorText = 'Could not save API key securely: $e');
                  }
                },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Save key'),
              ),
              FilledButton.icon(
                onPressed: loadingDraft ? null : () async {
                  final isPasted = provider == 'Paste AI output';
                  if (isPasted ? pastedController.text.trim().isEmpty : (keyController.text.trim().isEmpty || jdController.text.trim().isEmpty || modelController.text.trim().isEmpty)) {
                    refreshDialog(() => errorText = isPasted ? 'Paste the AI-generated resume content first.' : 'Enter a model ID, API key, and job description.');
                    return;
                  }
                  refreshDialog(() { loadingDraft = true; errorText = null; });
                  try {
                    await prefs.setString('resume_ai_provider', provider);
                    late final Map<String, dynamic> proposal;
                    if (isPasted) {
                      proposal = _parsePastedTailoringOutput(pastedController.text);
                      _applyPastedTailoringOutput(proposal);
                      await _save();
                      if (!mounted) return;
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(this.context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('Pasted AI output imported and saved. You can edit it in the resume editor.')));
                      return;
                    } else {
                      await secureStorage.write(key: keyName(provider), value: keyController.text.trim());
                      await prefs.setString('resume_ai_model_$provider', modelController.text.trim());
                      await _save();
                      proposal = await _requestTailoredResume(provider, modelController.text.trim(), keyController.text.trim(), jdController.text.trim());
                    }
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    await _reviewTailoredResume(proposal);
                  } catch (e) {
                    refreshDialog(() { loadingDraft = false; errorText = e.toString().replaceFirst('Exception: ', ''); });
                  }
                },
                icon: const Icon(Icons.auto_awesome),
                label: Text(loadingDraft ? 'Preparing...' : provider == 'Paste AI output' ? 'Import and save' : 'Generate draft'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // showDialog completes as soon as pop is requested; let its reverse
      // transition remove the TextFields before disposing their controllers.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      keyController.dispose();
      jdController.dispose();
      modelController.dispose();
      pastedController.dispose();
    }
  }

  Future<void> _copyExternalAiPrompt() async {
    final jdController = TextEditingController();
    var useCurrentResume = false;
    final jobDescription = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, refreshDialog) => AlertDialog(
        title: const Text('Build an external AI prompt'),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: jdController, minLines: 7, maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Job description', hintText: 'Paste the full job description to include in the prompt.', alignLabelWithHint: true),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: useCurrentResume,
            onChanged: (value) => refreshDialog(() => useCurrentResume = value ?? false),
            title: const Text('Use current editor content as the source'),
            subtitle: const Text('By default, the prompt uses your saved base resume so older JD edits do not carry over.'),
          ),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, jdController.text.trim()), child: const Text('Copy prompt')),
        ],
      )),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    jdController.dispose();
    if (jobDescription == null || jobDescription.isEmpty || !mounted) return;

    final resume = useCurrentResume ? data.toMap() : Map<String, String>.from(baseResume);
    if (useCurrentResume) {
      for (final entry in controllers.entries) {
        resume[entry.key] = entry.value.text;
      }
    }
    final prompt = '''You are a careful resume editor. Tailor the resume below to the job description.

First extract the job description's explicit and implied skills, technologies, tools, and competencies. Then map each to evidence in the current resume.
- Emphasize supported JD skills in skillsText and weave them naturally into relevant experienceText and projectsText where the resume provides evidence.
- Never invent skills, employers, dates, projects, achievements, metrics, certifications, education, or experience.
- Keep unsupported JD requirements out of the candidate's skills, experience, and projects; list them in missingSkills.
- Preserve factual meaning, role/project names, company names, dates, and metrics. Keep contact details and identity unchanged.
- Return ONLY valid JSON with these keys and types: role (string), summary (string), skillsText (string), experienceText (string), projectsText (string), certificationsText (string), educationText (string, unchanged unless only formatting is needed), matchSummary (string), jdSkills (array of strings), addedSkills (array of supported skills emphasized), missingSkills (array of unsupported JD requirements), and keywords (array of relevant ATS terms).
- Keep existing section content if there is no truthful improvement. Use plain hyphen bullets in experienceText and projectsText. Do not add Markdown fences or any text outside the JSON object.

CURRENT RESUME JSON:
${jsonEncode(resume)}

JOB DESCRIPTION:
$jobDescription''';
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Prompt copied. Paste it into your AI tool, then paste its JSON response here.')));
    }
  }

  Future<Map<String, dynamic>> _requestTailoredResume(String provider, String model, String apiKey, String jobDescription) async {
    final prompt = '''You are a careful resume editor. Tailor the current resume to the supplied job description.

Rules:
- First extract the JD's explicit and implied skills, technologies, tools, and core competencies into jdSkills before editing any resume content.
- For every extracted JD skill, check whether the current resume contains clear evidence. Put supported JD skills into skillsText, prioritizing the most relevant ones.
- Weave supported JD skills naturally into relevant experienceText and projectsText bullets only where the existing resume provides evidence; do not add skills to a role or project without that evidence.
- Return all extracted skills in jdSkills, including unsupported ones. Keep unsupported requirements out of the candidate's skills, experience, and projects, and list them in missingSkills for the user to review.
- Tailor every relevant content section: target role headline, summary, skills, experience, projects, and certifications.
- Never invent employers, dates, projects, achievements, metrics, certifications, education, or experience.
- Keep the role headline relevant but truthful based on the candidate's existing role and experience.
- Preserve current section text when there is no truthful JD-relevant improvement. Use plain hyphen bullets and keep experience/projects concise.
- Keep education, contact details, and identity unchanged; they are included for context only.
- Return only valid JSON with string keys: role, summary, skillsText, experienceText, projectsText, certificationsText, matchSummary; plus jdSkills (array of all skills extracted from the JD), addedSkills (array of supported JD skills emphasized), missingSkills (array of unsupported JD requirements), and keywords (array of relevant ATS terms).

CURRENT BASE RESUME:
${jsonEncode(baseResume)}

JOB DESCRIPTION:
$jobDescription''';

    late final http.Response response;
    if (provider == 'OpenAI') {
      response = await http.post(
        Uri.parse('https://api.openai.com/v1/responses'),
        headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'input': prompt}),
      ).timeout(const Duration(seconds: 90));
    } else if (provider == 'Gemini') {
      response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
        headers: {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'role': 'user', 'parts': [{'text': prompt}]}],
          'generationConfig': {'responseMimeType': 'application/json'},
        }),
      ).timeout(const Duration(seconds: 90));
    } else if (provider == 'Claude') {
      response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'max_tokens': 8192, 'messages': [{'role': 'user', 'content': prompt}]}),
      ).timeout(const Duration(seconds: 90));
    } else {
      final endpoint = const {
        'DeepSeek': 'https://api.deepseek.com/chat/completions',
        'OpenRouter': 'https://openrouter.ai/api/v1/chat/completions',
        'Groq': 'https://api.groq.com/openai/v1/chat/completions',
        'Mistral': 'https://api.mistral.ai/v1/chat/completions',
        'xAI': 'https://api.x.ai/v1/chat/completions',
      }[provider];
      if (endpoint == null) throw Exception('Unsupported AI provider: $provider');
      response = await http.post(
        Uri.parse(endpoint),
        headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'messages': [{'role': 'user', 'content': prompt}], 'temperature': 0.2}),
      ).timeout(const Duration(seconds: 90));
    }

    final responseJson = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = responseJson is Map ? (responseJson['error'] is Map ? responseJson['error']['message'] : responseJson['error']) : null;
      throw Exception(message?.toString() ?? 'The AI provider returned HTTP ${response.statusCode}. Check the API key and try again.');
    }
    final generatedText = switch (provider) {
      'OpenAI' => _openAiOutput(responseJson),
      'Gemini' => _geminiOutput(responseJson),
      'Claude' => _claudeOutput(responseJson),
      _ => _chatCompletionOutput(responseJson, provider),
    };
    final cleanJson = generatedText.trim().replaceFirst(RegExp(r'^```(?:json)?\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    final proposal = Map<String, dynamic>.from(jsonDecode(cleanJson));
    for (final field in ['role', 'summary', 'skillsText', 'experienceText', 'projectsText', 'certificationsText']) {
      if (proposal[field] is! String) throw Exception('The AI response did not include a usable $field. Please try again.');
    }
    if (proposal['jdSkills'] is! List) throw Exception('The AI response did not return the skills it found in the job description. Please try again.');
    return proposal;
  }

  Map<String, dynamic> _parsePastedTailoringOutput(String source) {
    var content = source.trim().replaceFirst(RegExp(r'^```(?:json)?\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    final existing = baseResume;
    final result = <String, dynamic>{
      'name': existing['name'] ?? '',
      'role': existing['role'] ?? '',
      'email': existing['email'] ?? '',
      'phone': existing['phone'] ?? '',
      'location': existing['location'] ?? '',
      'website': existing['website'] ?? '',
      'portfolio': existing['portfolio'] ?? '',
      'github': existing['github'] ?? '',
      'summary': existing['summary'] ?? '',
      'skillsText': existing['skills'] ?? '',
      'experienceText': existing['experience'] ?? '',
      'projectsText': existing['projects'] ?? '',
      'certificationsText': existing['certifications'] ?? '',
      'educationText': existing['education'] ?? '',
      'projectLinks': projectLinks.map((link) => Map<String, String>.from(link)).toList(),
      'matchSummary': 'Pasted AI draft. Review each section before applying.',
      'jdSkills': <String>[],
      'addedSkills': <String>[],
      'missingSkills': <String>[],
      'keywords': <String>[],
    };

    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        final json = Map<String, dynamic>.from(decoded);
        String? findString(List<String> keys) {
          for (final key in keys) {
            final value = json[key];
            if (value is String) return value;
            if (value is List) return value.map((item) => item.toString()).join('\n');
          }
          return null;
        }
        List<String> findList(List<String> keys) {
          final value = keys.map((key) => json[key]).firstWhere((item) => item != null, orElse: () => null);
          if (value is List) return value.map((item) => item.toString()).toList();
          if (value is String && value.trim().isNotEmpty) return value.split(RegExp(r'[,\n]')).map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
          return <String>[];
        }
        result['name'] = findString(['name', 'fullName', 'full_name', 'candidateName']) ?? result['name'];
        result['role'] = findString(['role', 'targetRole', 'target_role', 'professionalTitle']) ?? result['role'];
        result['email'] = findString(['email', 'emailAddress']) ?? result['email'];
        result['phone'] = findString(['phone', 'phoneNumber', 'mobile']) ?? result['phone'];
        result['location'] = findString(['location', 'city', 'address']) ?? result['location'];
        result['website'] = findString(['website', 'linkedin', 'linkedinUrl']) ?? result['website'];
        result['portfolio'] = findString(['portfolio', 'portfolioUrl']) ?? result['portfolio'];
        result['github'] = findString(['github', 'githubUrl']) ?? result['github'];
        result['summary'] = findString(['summary', 'professionalSummary']) ?? result['summary'];
        result['skillsText'] = findString(['skillsText', 'skills']) ?? result['skillsText'];
        result['experienceText'] = findString(['experienceText', 'experience', 'workExperience']) ?? result['experienceText'];
        result['projectsText'] = findString(['projectsText', 'projects']) ?? result['projectsText'];
        result['certificationsText'] = findString(['certificationsText', 'certifications']) ?? result['certificationsText'];
        result['educationText'] = findString(['educationText', 'education']) ?? result['educationText'];
        final rawLinks = json['projectLinks'] ?? json['storeLinks'];
        if (rawLinks is List) {
          result['projectLinks'] = rawLinks.whereType<Map>().map((item) {
            String value(List<String> keys) => keys.map((key) => item[key]?.toString().trim() ?? '').firstWhere((value) => value.isNotEmpty, orElse: () => '');
            return <String, String>{
              'project': value(['project', 'name', 'app']),
              'playStore': value(['playStore', 'play_store', 'googlePlay']),
              'appStore': value(['appStore', 'app_store', 'iosAppStore']),
            };
          }).where((link) => link.values.any((value) => value.isNotEmpty)).toList();
        }
        result['matchSummary'] = findString(['matchSummary']) ?? result['matchSummary'];
        result['jdSkills'] = findList(['jdSkills', 'jd_skills']);
        result['addedSkills'] = findList(['addedSkills', 'supportedSkills']);
        result['missingSkills'] = findList(['missingSkills', 'unsupportedSkills']);
        result['keywords'] = findList(['keywords', 'atsKeywords']);
        return result;
      }
    } catch (_) {
      // Accept labeled plain text below as well as JSON.
    }

    const sectionKeys = <String, String>{
      'name': 'name', 'full name': 'name', 'candidate name': 'name',
      'role': 'role', 'target role': 'role', 'target role headline': 'role',
      'professional title': 'role', 'title': 'role',
      'email': 'email', 'email address': 'email',
      'phone': 'phone', 'phone number': 'phone', 'mobile': 'phone',
      'location': 'location', 'city': 'location',
      'linkedin': 'website', 'linkedin url': 'website', 'website': 'website',
      'portfolio': 'portfolio', 'portfolio url': 'portfolio',
      'github': 'github', 'github url': 'github',
      'summary': 'summary', 'professional summary': 'summary',
      'skills': 'skillsText', 'skills text': 'skillsText',
      'experience': 'experienceText', 'work experience': 'experienceText', 'experience text': 'experienceText',
      'projects': 'projectsText', 'project experience': 'projectsText',
      'certifications': 'certificationsText', 'certification': 'certificationsText',
      'education': 'educationText', 'education details': 'educationText',
      'jd skills': 'jdSkills', 'skills extracted from the jd': 'jdSkills',
      'supported skills': 'addedSkills', 'added skills': 'addedSkills',
      'missing skills': 'missingSkills', 'unsupported skills': 'missingSkills',
      'keywords': 'keywords', 'ats keywords': 'keywords', 'match summary': 'matchSummary',
    };
    final parsed = <String, String>{};
    String? activeKey;
    final heading = RegExp(r'^\s*(?:#{1,3}\s*)?([A-Za-z][A-Za-z ]*?)(?:\s*:\s*(.*))?\s*$');
    for (final line in content.split('\n')) {
      final match = heading.firstMatch(line);
      final normalized = match?.group(1)?.trim().toLowerCase();
      final mappedKey = normalized == null ? null : sectionKeys[normalized];
      if (match != null && mappedKey != null) {
        activeKey = mappedKey;
        final inlineValue = match.group(2)?.trim() ?? '';
        parsed[activeKey] = inlineValue;
      } else if (activeKey != null) {
        parsed[activeKey!] = [parsed[activeKey!], line].where((part) => part != null && part.isNotEmpty).join('\n');
      }
    }
    if (parsed.isEmpty) {
      throw Exception('Paste JSON or labeled sections (ROLE, SUMMARY, SKILLS, EXPERIENCE, PROJECTS, CERTIFICATIONS).');
    }
    for (final entry in parsed.entries) {
      if (entry.key == 'jdSkills' || entry.key == 'addedSkills' || entry.key == 'missingSkills' || entry.key == 'keywords') {
        result[entry.key] = entry.value.split(RegExp(r'[,\n]')).map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
      } else {
        result[entry.key] = entry.value.trim();
      }
    }
    return result;
  }

  void _applyPastedTailoringOutput(Map<String, dynamic> proposal) {
    const fieldMap = {
      'name': 'name',
      'role': 'role',
      'email': 'email',
      'phone': 'phone',
      'location': 'location',
      'website': 'website',
      'portfolio': 'portfolio',
      'github': 'github',
      'summary': 'summary',
      'skillsText': 'skills',
      'experienceText': 'experience',
      'projectsText': 'projects',
      'certificationsText': 'certifications',
      'educationText': 'education',
    };
    for (final entry in fieldMap.entries) {
      final value = proposal[entry.key];
      if (value is String) controllers[entry.value]!.text = entry.key == 'educationText' ? _normalizeEducation(value) : value;
    }
    final links = proposal['projectLinks'];
    if (links is List) {
      projectLinks = links.whereType<Map>().map((item) => <String, String>{
        'project': item['project']?.toString().trim() ?? '',
        'playStore': item['playStore']?.toString().trim() ?? '',
        'appStore': item['appStore']?.toString().trim() ?? '',
      }).where((link) => link.values.any((value) => value.isNotEmpty)).toList();
    }
    setState(() {});
  }

  String _openAiOutput(dynamic response) {
    if (response is! Map<String, dynamic>) throw Exception('Unexpected response from OpenAI.');
    if (response['output_text'] is String) return response['output_text'] as String;
    final texts = <String>[];
    for (final item in (response['output'] as List? ?? const [])) {
      if (item is Map) for (final part in (item['content'] as List? ?? const [])) {
        if (part is Map && part['type'] == 'output_text' && part['text'] is String) texts.add(part['text'] as String);
      }
    }
    if (texts.isEmpty) throw Exception('OpenAI returned no text. Check the model and API permissions.');
    return texts.join('\n');
  }

  String _geminiOutput(dynamic response) {
    if (response is! Map<String, dynamic>) throw Exception('Unexpected response from Gemini.');
    final candidates = response['candidates'] as List? ?? const [];
    for (final candidate in candidates) {
      if (candidate is Map) {
        final parts = (candidate['content'] as Map?)?['parts'] as List? ?? const [];
        final text = parts.whereType<Map>().map((part) => part['text']).whereType<String>().join('\n');
        if (text.isNotEmpty) return text;
      }
    }
    throw Exception('Gemini returned no text. Check the API key and try again.');
  }

  String _claudeOutput(dynamic response) {
    if (response is! Map<String, dynamic>) throw Exception('Unexpected response from Claude.');
    final content = response['content'] as List? ?? const [];
    final text = content.whereType<Map>().where((part) => part['type'] == 'text').map((part) => part['text']).whereType<String>().join('\n');
    if (text.isEmpty) throw Exception('Claude returned no text. Check the model and API key.');
    return text;
  }

  String _chatCompletionOutput(dynamic response, String provider) {
    if (response is! Map<String, dynamic>) throw Exception('Unexpected response from $provider.');
    final choices = response['choices'] as List? ?? const [];
    final message = choices.isNotEmpty && choices.first is Map ? (choices.first as Map)['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content is String && content.isNotEmpty) return content;
    if (content is List) {
      final text = content.whereType<Map>().map((part) => part['text']).whereType<String>().join('\n');
      if (text.isNotEmpty) return text;
    }
    throw Exception('$provider returned no text. Check the model and API key.');
  }

  Future<void> _reviewTailoredResume(Map<String, dynamic> proposal) async {
    final role = TextEditingController(text: proposal['role'] as String);
    final summary = TextEditingController(text: proposal['summary'] as String);
    final skills = TextEditingController(text: proposal['skillsText'] as String);
    final experience = TextEditingController(text: proposal['experienceText'] as String);
    final projects = TextEditingController(text: proposal['projectsText'] as String);
    final certifications = TextEditingController(text: proposal['certificationsText'] as String);
    final missingSkills = (proposal['missingSkills'] as List? ?? const []).map((item) => item.toString()).toList();
    final jdSkills = (proposal['jdSkills'] as List? ?? const []).map((item) => item.toString()).toList();
    final addedSkills = (proposal['addedSkills'] as List? ?? const []).map((item) => item.toString()).toList();
    final keywords = (proposal['keywords'] as List? ?? const []).map((item) => item.toString()).toList();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review tailored resume'),
        content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((proposal['matchSummary'] as String? ?? '').isNotEmpty) Text(proposal['matchSummary'] as String),
          if (jdSkills.isNotEmpty) ...[const SizedBox(height: 10), const Text('Skills extracted from the JD', style: TextStyle(fontWeight: FontWeight.w700)), Text(jdSkills.join(' · '))],
          if (addedSkills.isNotEmpty) ...[const SizedBox(height: 10), const Text('Supported skills emphasized', style: TextStyle(fontWeight: FontWeight.w700)), Text(addedSkills.join(' · '))],
          if (missingSkills.isNotEmpty) ...[const SizedBox(height: 10), const Text('JD skills not supported by this resume', style: TextStyle(fontWeight: FontWeight.w700)), Text(missingSkills.join(' · '))],
          if (keywords.isNotEmpty) ...[const SizedBox(height: 10), const Text('Relevant JD keywords', style: TextStyle(fontWeight: FontWeight.w700)), Text(keywords.join(' · '))],
          const SizedBox(height: 14),
          TextField(controller: role, decoration: const InputDecoration(labelText: 'Target role headline')),
          const SizedBox(height: 10),
          TextField(controller: summary, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Tailored summary')),
          const SizedBox(height: 10),
          TextField(controller: skills, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Skills')),
          const SizedBox(height: 10),
          TextField(controller: experience, minLines: 6, maxLines: 14, decoration: const InputDecoration(labelText: 'Experience')),
          const SizedBox(height: 10),
          TextField(controller: projects, minLines: 5, maxLines: 12, decoration: const InputDecoration(labelText: 'Projects')),
          const SizedBox(height: 10),
          TextField(controller: certifications, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Certifications')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apply and save')),
        ],
      ),
    );
    if (result == true && mounted) {
      controllers['role']!.text = role.text;
      controllers['summary']!.text = summary.text;
      controllers['skills']!.text = skills.text;
      controllers['experience']!.text = experience.text;
      controllers['projects']!.text = projects.text;
      controllers['certifications']!.text = certifications.text;
      setState(() {});
      await _save();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Resume updated and saved successfully.')));
      }
    }
    // The dialog result arrives before its closing transition is fully removed.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    role.dispose();
    summary.dispose();
    skills.dispose();
    experience.dispose();
    projects.dispose();
    certifications.dispose();
  }

  Future<void> _saveStyle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('resume_style_v1', jsonEncode(style.toMap()));
  }

  void _updateStyle(ResumeStyleSettings next, {bool save = false}) {
    setState(() => style = next);
    if (save) _saveStyle();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(_asUrl(url.trim()));
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) return;
    try {
      final opened = await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link. Check your browser settings and try again.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link. Check your browser settings and try again.')));
    }
  }

  Future<Uint8List> _buildResumePdfBytes() async {
    final document = _buildPdfDocument();
    final bytes = await document.save();
    final linksByPage = document.document.pdfPageList.pages.map((page) => page.annotations
        .where((annotation) => annotation.annot is PdfAnnotUrlLink)
        .map((annotation) {
          final link = annotation.annot as PdfAnnotUrlLink;
          return _PdfPreviewLink(
            url: link.url,
            rect: link.rect,
            pageWidth: page.pageFormat.width,
            pageHeight: page.pageFormat.height,
          );
        })
        .toList(growable: false)).toList(growable: false);
    final signature = linksByPage.asMap().entries.expand((entry) => entry.value.map((link) =>
        '${entry.key}:${link.url}:${link.rect.left}:${link.rect.bottom}:${link.rect.width}:${link.rect.height}:${link.pageWidth}:${link.pageHeight}')).join('|');
    if (signature != _pdfPreviewLinksSignature) {
      _pdfPreviewLinksSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pdfPreviewLinks = linksByPage);
      });
    }
    return bytes;
  }

  String _asUrl(String value) => value.startsWith('http') ? value : 'https://$value';

  void _mergeLinks(List<Map<String, String>> target, List<Map<String, String>> updates) {
    for (final update in updates) {
      final name = (update['project'] ?? '').trim();
      if (name.isEmpty) continue;
      final existingIndex = target.indexWhere((item) => (item['project'] ?? '').toLowerCase() == name.toLowerCase());
      if (existingIndex < 0) {
        target.add(Map<String, String>.from(update));
      } else {
        final existing = target[existingIndex];
        target[existingIndex] = {
          'project': name,
          'playStore': (update['playStore'] ?? '').trim().isNotEmpty ? update['playStore']!.trim() : (existing['playStore'] ?? ''),
          'appStore': (update['appStore'] ?? '').trim().isNotEmpty ? update['appStore']!.trim() : (existing['appStore'] ?? ''),
        };
      }
    }
  }

  List<Map<String, String>> _parseBulkProjectLinks(String source) {
    final found = <Map<String, String>>[];
    String cleanUrl(String value) => value.trim().replaceFirst(RegExp(r'^(?:Google Play|Play Store|Apple App Store|App Store)\s*:\s*', caseSensitive: false), '');
    void add(dynamic item) {
      if (item is! Map) return;
      String get(List<String> keys) => keys.map((key) => item[key]?.toString().trim() ?? '').firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final link = <String, String>{
        'project': get(['project', 'app', 'name']),
        'playStore': get(['playStore', 'play_store', 'googlePlay']),
        'appStore': get(['appStore', 'app_store', 'appleAppStore']),
      };
      if (link['project']!.isNotEmpty && (link['playStore']!.isNotEmpty || link['appStore']!.isNotEmpty)) found.add(link);
    }

    try {
      final decoded = jsonDecode(source.trim());
      final values = decoded is List ? decoded : decoded is Map ? (decoded['projectLinks'] ?? decoded['links'] ?? const []) : const [];
      if (values is List) {
        for (final item in values) { add(item); }
      }
    } catch (_) {
      // Continue with the readable bulk formats below.
    }
    if (found.isNotEmpty) return found;

    Map<String, String>? current;
    String? activePlatform;
    void flush() {
      if (current != null && current!['project']!.isNotEmpty && (current!['playStore']!.isNotEmpty || current!['appStore']!.isNotEmpty)) {
        found.add(Map<String, String>.from(current!));
      }
      current = null;
      activePlatform = null;
    }
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final columns = line.split(RegExp(r'\s*\|\s*|\t')).map((value) => value.trim()).toList();
      final firstColumn = columns.first.toLowerCase();
      final isHeader = firstColumn == 'project' || firstColumn == 'app' || firstColumn == 'app name' ||
          (firstColumn.contains('project') && columns.any((value) => value.toLowerCase().contains('store')));
      if (columns.length >= 3 && !isHeader) {
        flush();
        current = {'project': columns[0].replaceFirst(RegExp(r'^\d+[.)]\s*'), ''), 'playStore': cleanUrl(columns[1]), 'appStore': cleanUrl(columns[2])};
        flush();
        continue;
      }
      final platformMatch = RegExp(r'^(play store|google play|apple app store|app store)\s*:?\s*(.*)$', caseSensitive: false).firstMatch(line);
      if (platformMatch != null) {
        current ??= {'project': '', 'playStore': '', 'appStore': ''};
        final label = platformMatch.group(1)!.toLowerCase();
        activePlatform = label.contains('play') ? 'playStore' : 'appStore';
        final inlineUrl = platformMatch.group(2)!.trim();
        if (inlineUrl.isNotEmpty) current![activePlatform!] = inlineUrl;
        continue;
      }
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(line)) {
        if (current != null && activePlatform != null) current![activePlatform!] = line;
        continue;
      }
      if (line.toLowerCase().startsWith('project |') || line.toLowerCase().startsWith('app |')) continue;
      flush();
      current = {'project': line.replaceFirst(RegExp(r'^\d+[.)]\s*'), '').replaceFirst(RegExp(r':$'), '').trim(), 'playStore': '', 'appStore': ''};
    }
    flush();
    if (found.isEmpty) {
      throw Exception('No project links found. Paste JSON or lines like: App name | Play Store URL | App Store URL.');
    }
    final unique = <Map<String, String>>[];
    _mergeLinks(unique, found);
    return unique;
  }

  Future<void> _pasteBulkProjectLinks() async {
    final pasteController = TextEditingController();
    try {
      final pasted = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Paste project links in bulk'),
        content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Paste JSON, or one app per line as: App name | Google Play URL | Apple App Store URL.'),
          const SizedBox(height: 10),
          TextField(controller: pasteController, minLines: 8, maxLines: 14, keyboardType: TextInputType.multiline, decoration: const InputDecoration(labelText: 'Project and store URLs', alignLabelWithHint: true)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, pasteController.text), child: const Text('Import links')),
        ],
      ));
      if (pasted == null || pasted.trim().isEmpty || !mounted) return;
      final incoming = _parseBulkProjectLinks(pasted);
      _mergeLinks(projectLinks, incoming);
      setState(() {});
      await _save();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved links for ${incoming.length} project app${incoming.length == 1 ? '' : 's'}.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      pasteController.dispose();
    }
  }

  String? _projectUrl(String project, String platform) {
    final query = _projectLinkKey(project);
    if (query.isEmpty) return null;
    Map<String, String>? link;
    // Prefer an exact app-name match, then allow projectLinks entries that
    // include the parent project title plus the app name (e.g. "Pool Pal -
    // Mobility - PoolPal User").
    for (final item in projectLinks) {
      if (_projectLinkKey(item['project'] ?? '') == query) {
        link = item;
        break;
      }
    }
    if (link == null) {
      final matches = projectLinks.where((item) {
        final savedName = _projectLinkKey(item['project'] ?? '');
        return savedName.length >= 4 && (savedName.contains(query) || query.contains(savedName));
      }).toList()
        ..sort((a, b) => _projectLinkKey(b['project'] ?? '').length.compareTo(_projectLinkKey(a['project'] ?? '').length));
      if (matches.isNotEmpty) link = matches.first;
    }
    final key = platform == 'Play Store' ? 'playStore' : 'appStore';
    final value = link?[key]?.trim() ?? '';
    return value.isEmpty ? null : _asUrl(value);
  }

  String _projectLinkKey(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _editProjectLink({int? index}) async {
    final current = index == null ? <String, String>{} : Map<String, String>.from(projectLinks[index]);
    final name = TextEditingController(text: current['project'] ?? '');
    final play = TextEditingController(text: current['playStore'] ?? '');
    final app = TextEditingController(text: current['appStore'] ?? '');
    try {
      final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(index == null ? 'Add project links' : 'Edit project links'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Project or app name')),
          const SizedBox(height: 8),
          TextField(controller: play, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Play URL')),
          const SizedBox(height: 8),
          TextField(controller: app, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Apple App Store URL')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save links')),
        ],
      ));
      if (saved != true || !mounted) return;
      if (name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a project or app name.')));
        return;
      }
      final item = <String, String>{'project': name.text.trim(), 'playStore': play.text.trim(), 'appStore': app.text.trim()};
      setState(() {
        if (index == null) {
          projectLinks.add(item);
        } else {
          projectLinks[index] = item;
        }
      });
      await _save();
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      name.dispose();
      play.dispose();
      app.dispose();
    }
  }

  Future<void> _removeProjectLink(int index) async {
    setState(() => projectLinks.removeAt(index));
    await _save();
  }

  List<String> get _projectEntries => controllers['projects']!.text
      .split(RegExp(r'\n\s*\n'))
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  Future<void> _editProjectEntry({int? index}) async {
    final entries = _projectEntries;
    final original = index == null ? '' : entries[index];
    final appNames = _projectStoreNames(original);
    final startingLinks = appNames.map((name) {
      for (final saved in projectLinks) {
        if ((saved['project'] ?? '').toLowerCase() == name.toLowerCase()) return Map<String, String>.from(saved);
      }
      return <String, String>{'project': name, 'playStore': '', 'appStore': ''};
    }).toList();
    final result = await Navigator.push<_ProjectEditorResult>(context, MaterialPageRoute(
      builder: (_) => _ProjectEditorScreen(initialContent: original, initialLinks: startingLinks),
    ));
    if (result == null || !mounted) return;
    final value = result.content.trim();
    if (value.isEmpty) return;
    if (index == null) {
      entries.add(value);
    } else {
      entries[index] = value;
    }
    final replacedNames = startingLinks.map((link) => link['project']!.toLowerCase()).toSet();
    projectLinks.removeWhere((link) => replacedNames.contains((link['project'] ?? '').toLowerCase()));
    for (final link in result.links) {
      projectLinks.removeWhere((saved) => (saved['project'] ?? '').toLowerCase() == link['project']!.toLowerCase());
      if (link['playStore']!.isNotEmpty || link['appStore']!.isNotEmpty) projectLinks.add(link);
    }
    controllers['projects']!.text = entries.join('\n\n');
    setState(() {});
    await _save();
  }

  List<String> _projectStoreNames(String source) {
    final names = <String>[];
    final tokens = _projectStoreTokens(source.split('\n').where(_isProjectStoreLine).toList());
    for (final token in tokens) {
      if (!names.any((existing) => existing.toLowerCase() == token.name.toLowerCase())) {
        names.add(token.name);
      }
    }
    return names;
  }

  bool _isProjectStoreLine(String line) => RegExp(r'(?:Play Store|App\s*Store)\s*:', caseSensitive: false).hasMatch(line);

  List<({String platform, String name})> _projectStoreTokens(List<String> lines) {
    final explicitPlatforms = <String, Set<String>>{};
    final names = <String>[];
    final labelPattern = RegExp(r'(Play Store|App\s*Store)\s*:', caseSensitive: false);
    for (final line in lines) {
      final labels = labelPattern.allMatches(line).toList();
      for (var i = 0; i < labels.length; i++) {
        final label = labels[i];
        final platform = label.group(1)!.toLowerCase().startsWith('play') ? 'Play Store' : 'App Store';
        final end = i + 1 < labels.length ? labels[i + 1].start : line.length;
        final appNames = line.substring(label.end, end).split(RegExp(r'[,|]')).map((value) => value.trim()).where((value) => value.isNotEmpty);
        for (final name in appNames) {
          final key = name.toLowerCase();
          if (!names.any((existing) => existing.toLowerCase() == key)) names.add(name);
          explicitPlatforms.putIfAbsent(key, () => <String>{}).add(platform);
        }
      }
    }

    final tokens = <({String platform, String name})>[];
    for (final name in names) {
      for (final platform in ['Play Store', 'App Store']) {
        if (explicitPlatforms[name.toLowerCase()]!.contains(platform) || _projectUrl(name, platform) != null) {
          tokens.add((platform: platform, name: name));
        }
      }
    }
    return tokens;
  }

  List<({String platform, String name})> _projectStoreTokensForEntry(String title, List<String> lines, {String entryText = ''}) {
    final tokens = _projectStoreTokens(lines);
    // Saved links may be keyed by the project title or by an app name that
    // appears in its details. Render those links even without store label lines.
    final searchableEntry = _projectLinkKey('$title $entryText');
    for (final item in projectLinks) {
      final name = (item['project'] ?? '').trim();
      final key = _projectLinkKey(name);
      if (key.isEmpty || (!searchableEntry.contains(key) && key != _projectLinkKey(title))) continue;
      if (tokens.isNotEmpty && key == _projectLinkKey(title)) continue;
      for (final (platform, field) in [('Play Store', 'playStore'), ('App Store', 'appStore')]) {
        final url = item[field]?.trim() ?? '';
        if (url.isEmpty) continue;
        if (!tokens.any((token) => token.platform == platform && _projectLinkKey(token.name) == key)) {
          tokens.add((platform: platform, name: name));
        }
      }
    }
    return tokens;
  }

  String _bulkStoreLinksPrompt() {
    final entries = _projectEntries;
    final allowedNames = <String>[];
    for (final entry in entries) {
      final names = _projectStoreNames(entry);
      if (names.isNotEmpty) {
        allowedNames.addAll(names);
      } else {
        final title = entry.split('\n').first.split('|').first.trim();
        if (title.isNotEmpty) allowedNames.add(title);
      }
    }
    final uniqueNames = <String>[];
    for (final name in allowedNames) {
      if (!uniqueNames.any((existing) => existing.toLowerCase() == name.toLowerCase())) uniqueNames.add(name);
    }
    final allowed = uniqueNames.isEmpty ? '(none - return an empty projectLinks array)' : uniqueNames.map((name) => '- $name').join('\n');
    final projectContent = entries.isEmpty ? '(No project content is currently saved in the app.)' : entries.join('\n\n');
    return '''Find Google Play Store and Apple App Store URLs ONLY for the exact app/project names in the allowlist below. These names and project details were copied from the Projects section currently saved in my resume app.

STRICT SCOPE:
- Use only the names in the allowlist. Do not include any other apps or projects mentioned elsewhere in this conversation, your memory, or other resumes.
- Do not add related, alternative, renamed, or similarly named apps. Each returned project value must exactly match one allowlisted name.
- Return a URL only when you know the correct URL for that exact allowlisted app. Never guess or construct URLs.
- Omit an allowlisted app if you do not know any store URL for it. If you know only one store, set the other field to an empty string.

Allowed app/project names:
$allowed

Projects content currently saved in my app (for disambiguation only; do not add names from outside the allowlist):
$projectContent

Return ONLY valid JSON with no Markdown fences or explanation, in this format:
{"projectLinks":[{"project":"exact allowlisted name","playStore":"https://play.google.com/... or empty string","appStore":"https://apps.apple.com/... or empty string"}]}

If none of the allowlisted names have a known store URL, return {"projectLinks":[]}.''';
  }

  Future<void> _removeProjectEntry(int index) async {
    final entries = _projectEntries;
    final removedNames = _projectStoreNames(entries[index]).map((name) => name.toLowerCase()).toSet();
    entries.removeAt(index);
    projectLinks.removeWhere((link) => removedNames.contains((link['project'] ?? '').toLowerCase()));
    controllers['projects']!.text = entries.join('\n\n');
    setState(() {});
    await _save();
  }

  void _setField(String key, String value) {
    switch (key) {
      case 'name': data.name = value; break; case 'role': data.role = value; break;
      case 'email': data.email = value; break; case 'phone': data.phone = value; break;
      case 'location': data.location = value; break; case 'website': data.website = value; break;
      case 'portfolio': data.portfolio = value; break; case 'github': data.github = value; break;
      case 'summary': data.summary = value; break; case 'experience': data.experience = value; break;
      case 'education': data.education = _normalizeEducation(value); break; case 'skills': data.skills = value; break;
      case 'projects': data.projects = value; break; case 'certifications': data.certifications = value; break;
    }
  }

  String _normalizeEducation(String source) {
    final lines = source.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    if (lines.isEmpty) return '';
    final degreeParts = lines.first.split('|');
    final degree = degreeParts.first.trim();
    var graduation = degreeParts.length > 1 ? degreeParts.skip(1).join('|').trim() : '';
    graduation = graduation.replaceFirst(RegExp(r'^Graduated:\s*', caseSensitive: false), '');
    var location = '';
    var cgpa = '';
    for (final line in lines.skip(1)) {
      if (line.toLowerCase().startsWith('graduated:')) {
        graduation = line.replaceFirst(RegExp(r'^Graduated:\s*', caseSensitive: false), '');
      } else if (line.toLowerCase().startsWith('cgpa:')) {
        cgpa = line;
      } else {
        final details = line.split('|');
        if (location.isEmpty) location = details.first.trim();
        if (details.length > 1 && cgpa.isEmpty) cgpa = details.skip(1).join('|').trim();
      }
    }
    if (graduation.isEmpty && lines.length > 2) graduation = lines.firstWhere((line) => line.toLowerCase().startsWith('graduated:'), orElse: () => '');
    if (cgpa.isEmpty) cgpa = lines.firstWhere((line) => line.toLowerCase().startsWith('cgpa:'), orElse: () => '');
    return '$degree${graduation.isEmpty ? '' : ' | $graduation'}\n$location${cgpa.isEmpty ? '' : ' | $cgpa'}';
  }

  pw.Document _buildPdfDocument() {
    final pdf = pw.Document();
    final regular = pw.Font.times();
    final bold = pw.Font.timesBold();
    final italic = pw.Font.timesItalic();
    pdf.addPage(pw.MultiPage(
      pageFormat: const PdfPageFormat(595.5, 842),
      margin: pw.EdgeInsets.fromLTRB(
        style.horizontalMargin + style.contentPadding,
        style.topMargin + style.contentPadding,
        style.horizontalMargin + style.contentPadding,
        style.bottomMargin + style.contentPadding,
      ),
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic),
      build: (context) => [
        pw.Center(child: pw.Text(data.name.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 24))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text(data.role, style: pw.TextStyle(font: bold, fontSize: 16))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text([data.phone, data.location].where((s) => s.trim().isNotEmpty).join(' | '), style: pw.TextStyle(font: regular, fontSize: 11))),
        pw.SizedBox(height: 3),
        pw.Center(child: pw.Wrap(alignment: pw.WrapAlignment.center, spacing: 3, children: [
          pw.Text(data.email, style: pw.TextStyle(font: regular, fontSize: 11)),
          if (data.email.isNotEmpty && data.website.isNotEmpty) pw.Text('|', style: pw.TextStyle(font: regular, fontSize: 11)),
          if (data.website.isNotEmpty) pw.UrlLink(destination: _asUrl(data.website), child: pw.Text(data.website, style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline))),
          if (data.website.isNotEmpty && data.portfolio.isNotEmpty) pw.Text('|', style: pw.TextStyle(font: regular, fontSize: 11)),
          if (data.portfolio.isNotEmpty) pw.UrlLink(destination: data.portfolio, child: pw.Text('Portfolio', style: pw.TextStyle(font: regular, fontSize: 11, decoration: pw.TextDecoration.underline))),
        ])),
        pw.SizedBox(height: 4),
        _pdfSection('Summary', [pw.Text(data.summary, style: pw.TextStyle(font: regular, fontSize: style.descriptionSize, lineSpacing: 1.5))]),
        _pdfSection('Skills', _pdfSkills(regular, bold)),
        _pdfSection('Experience', _pdfEntries(data.experience, regular, bold)),
        _pdfSection('Projects', [
          ..._pdfEntries(data.projects, regular, bold, project: true),
          if (data.github.isNotEmpty) _pdfGitHubRow(regular, bold),
        ]),
        _pdfSection('Education', _pdfEducation(regular, bold, italic)),
        if (data.certifications.trim().isNotEmpty)
          _pdfSection('Certifications', [pw.Text(data.certifications, style: pw.TextStyle(font: regular, fontSize: style.descriptionSize))]),
      ],
    ));
    return pdf;
  }

  Future<int> _calculatePdfPageCount() async {
    _syncDataFromControllers();
    try {
      final pdf = _buildPdfDocument();
      await pdf.save();
      return pdf.document.pdfPageList.pages.length;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _export() async {
    await _save();
    final bytes = await _buildResumePdfBytes();
    final filename = '${data.name.trim().isEmpty ? 'Resume' : data.name.trim().replaceAll(' ', '_')}_Resume.pdf';
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    }
  }

  Future<void> _showEmailResumeDialog() async {
    final toController = TextEditingController();
    final subjectController = TextEditingController(text: '${controllers['name']!.text.trim()} - Resume');
    final bodyController = TextEditingController(text: 'Hello,\n\nPlease find my resume attached.\n\nRegards,\n${controllers['name']!.text.trim()}');
    String? errorText;
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
        title: const Row(children: [Icon(Icons.email_outlined), SizedBox(width: 10), Text('Email resume')]),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: toController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'To', hintText: 'name@example.com (separate multiple addresses with commas)')),
          const SizedBox(height: 10),
          TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'Subject')),
          const SizedBox(height: 10),
          TextField(controller: bodyController, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true)),
          if (errorText != null) ...[const SizedBox(height: 10), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 8),
          const Text('The app opens your mail composer when available. If it is unavailable, a configured backend sends the email directly.', style: TextStyle(fontSize: 12, color: Color(0xff68756e))),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _configureEmailBackend, icon: const Icon(Icons.settings_outlined), label: const Text('Configure auto-send fallback'))),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () {
            final recipients = toController.text.split(RegExp(r'[,;]')).map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
            final valid = recipients.isNotEmpty && recipients.every((value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value));
            if (!valid) {
              refreshDialog(() => errorText = 'Enter a valid email address.');
              return;
            }
            Navigator.pop(dialogContext, {'to': recipients.join(','), 'subject': subjectController.text.trim(), 'body': bodyController.text.trim()});
          }, icon: const Icon(Icons.send_outlined), label: const Text('Open email')),
        ],
      )),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    toController.dispose();
    subjectController.dispose();
    bodyController.dispose();
    if (details != null && mounted) await _sendResumeEmail(details);
  }

  Future<void> _configureEmailBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final urlController = TextEditingController(text: prefs.getString('resume_email_backend_url_v1') ?? '');
    final tokenController = TextEditingController(text: await secureStorage.read(key: emailBackendTokenStorageKey) ?? '');
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
        title: const Text('Auto-send backend'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: urlController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Email API endpoint', hintText: 'https://your-api.example.com/resume-email')),
          const SizedBox(height: 10),
          TextField(controller: tokenController, obscureText: true, decoration: const InputDecoration(labelText: 'Bearer token (optional)', helperText: 'Stored in device secure storage. Never put this token in the app source.')),
          if (errorText != null) ...[const SizedBox(height: 10), Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 8),
          const Text('Used only if the email composer is unavailable, or on web where mail links cannot attach PDFs.', style: TextStyle(fontSize: 12, color: Color(0xff68756e))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            final endpoint = Uri.tryParse(urlController.text.trim());
            if (endpoint == null || !endpoint.hasAuthority || !{'http', 'https'}.contains(endpoint.scheme)) {
              refreshDialog(() => errorText = 'Enter a valid HTTP or HTTPS API endpoint.');
              return;
            }
            await prefs.setString('resume_email_backend_url_v1', endpoint.toString());
            final token = tokenController.text.trim();
            if (token.isEmpty) {
              await secureStorage.delete(key: emailBackendTokenStorageKey);
            } else {
              await secureStorage.write(key: emailBackendTokenStorageKey, value: token);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('Save backend')),
        ],
      )),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    urlController.dispose();
    tokenController.dispose();
  }

  Future<void> _sendResumeEmail(Map<String, String> details) async {
    try {
      await _save();
      final safeName = controllers['name']!.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
      final fileName = '${safeName.isEmpty ? 'Resume' : safeName}_Resume.pdf';
      final pdfBytes = await _buildPdfDocument().save();
      final recipients = details['to']!.split(',').map((value) => value.trim()).toList();

      final prefs = await SharedPreferences.getInstance();
      final backendUrl = prefs.getString('resume_email_backend_url_v1');
      if (kIsWeb && backendUrl != null && backendUrl.trim().isNotEmpty) {
        await _sendResumeThroughBackend(backendUrl, pdfBytes, fileName, recipients, details);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email sent by the configured backend.')));
        return;
      }

      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        final attachmentPath = await writeResumePdfAttachment(pdfBytes, fileName);
        if (attachmentPath == null) throw Exception('Could not prepare the PDF attachment on this device.');
        try {
          await FlutterEmailSender.send(Email(recipients: recipients, subject: details['subject']!, body: details['body']!, attachmentPaths: [attachmentPath]));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email composer opened with your resume attached. Review and tap Send.')));
          return;
        } catch (emailError) {
          Object sendError = emailError;
          if (backendUrl != null && backendUrl.trim().isNotEmpty) {
            try {
              await _sendResumeThroughBackend(backendUrl, pdfBytes, fileName, recipients, details);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mail app unavailable; email sent by the configured backend.')));
              return;
            } catch (backendError) {
              sendError = backendError;
            }
          }
          final shared = await Printing.sharePdf(
            bytes: pdfBytes,
            filename: fileName,
            emails: recipients,
            subject: details['subject'],
            body: details['body'],
          );
          if (!shared) throw Exception('Could not open the mail app or share sheet: $sendError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(backendUrl == null ? 'Mail composer unavailable; share sheet opened with the PDF and email details.' : 'Auto-send failed ($sendError); share sheet opened with the PDF.')));
          }
        }
        return;
      }

      if (!kIsWeb && backendUrl != null && backendUrl.trim().isNotEmpty) {
        await _sendResumeThroughBackend(backendUrl, pdfBytes, fileName, recipients, details);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email sent by the configured backend.')));
        return;
      }

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      final mailto = Uri(scheme: 'mailto', path: recipients.join(','), queryParameters: {'subject': details['subject']!, 'body': details['body']!});
      final opened = await launchUrl(mailto, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('No email app is available. The PDF was downloaded; attach it to an email manually.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF downloaded and email draft opened. Attach the downloaded PDF before sending.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _sendResumeThroughBackend(String endpoint, List<int> pdfBytes, String fileName, List<String> recipients, Map<String, String> details) async {
    final token = await secureStorage.read(key: emailBackendTokenStorageKey);
    final headers = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: jsonEncode({
        'to': recipients,
        'subject': details['subject'],
        'body': details['body'],
        'attachments': [
          {'filename': fileName, 'contentType': 'application/pdf', 'contentBase64': base64Encode(pdfBytes)},
        ],
      }),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      try {
        final payload = jsonDecode(response.body);
        if (payload is Map) message = (payload['message'] ?? payload['error'])?.toString();
      } catch (_) {}
      throw Exception(message ?? 'Email backend returned HTTP ${response.statusCode}.');
    }
  }

  pw.Widget _pdfSection(String title, List<pw.Widget> children) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Container(height: 1, width: double.infinity, color: PdfColors.black),
          pw.SizedBox(height: 5),
          pw.Text(title, style: pw.TextStyle(font: pw.Font.timesBold(), fontSize: style.headingSize)),
          pw.SizedBox(height: 5),
          ...children,
        ],
      );

  pw.Widget _pdfPair(String label, String value, pw.Font regular, pw.Font bold) => pw.RichText(
        text: pw.TextSpan(style: pw.TextStyle(font: regular, fontSize: style.descriptionSize), children: [
          pw.TextSpan(text: label, style: pw.TextStyle(font: bold)),
          pw.TextSpan(text: value),
        ]),
      );

  List<pw.Widget> _pdfSkills(pw.Font regular, pw.Font bold) => data.skills
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map((line) {
        final colon = line.indexOf(':');
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: colon < 0
              ? pw.Text(line, style: pw.TextStyle(font: regular, fontSize: style.descriptionSize))
              : _pdfPair('${line.substring(0, colon)}:', line.substring(colon + 1), regular, bold),
        );
      })
      .toList();

  List<pw.Widget> _pdfEntries(String source, pw.Font regular, pw.Font bold, {bool project = false}) {
    final entries = source.split(RegExp(r'\n\s*\n')).where((entry) => entry.trim().isNotEmpty);
    return entries.map((entry) {
      final lines = entry.split('\n').where((line) => line.trim().isNotEmpty).toList();
      final header = lines.isEmpty ? '' : lines.first;
      final parsedHeader = _parseEntryHeader(header);
      final title = parsedHeader.title;
      final company = parsedHeader.company.isEmpty ? '' : ', ${parsedHeader.company}';
      final date = parsedHeader.date;
      final content = <pw.Widget>[
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.RichText(text: pw.TextSpan(style: pw.TextStyle(font: regular, fontSize: style.subheadingSize), children: [
            pw.TextSpan(text: title, style: pw.TextStyle(font: bold)), pw.TextSpan(text: company),
          ]))),
          if (date.isNotEmpty) pw.SizedBox(width: 115, child: pw.Text(date, textAlign: pw.TextAlign.right, style: pw.TextStyle(font: bold, fontSize: style.subheadingSize))),
        ]),
      ];
      final storeLines = project ? lines.skip(1).where(_isProjectStoreLine).toList() : <String>[];
      final storeTokens = project ? _projectStoreTokensForEntry(title, storeLines, entryText: lines.skip(1).join(' ')) : <({String platform, String name})>[];
      if (storeTokens.isNotEmpty) content.add(_pdfProjectStoreRow(storeTokens, regular, bold));
      for (final line in lines.skip(1)) {
        if (project && _isProjectStoreLine(line)) continue;
        if (project && line.startsWith('Tech Stack:')) {
          content.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 1),
            child: _pdfPair('${line.substring(0, line.indexOf(':') + 1)} ', line.substring(line.indexOf(':') + 1).trim(), regular, bold),
          ));
        } else {
          content.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 5.8, top: 1),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(line.startsWith('-') ? '- ' : '', style: pw.TextStyle(font: regular, fontSize: style.descriptionSize)),
              pw.Expanded(child: pw.Text(line.startsWith('-') ? line.substring(1).trimLeft() : line, style: pw.TextStyle(font: regular, fontSize: style.descriptionSize, lineSpacing: 1.5))),
            ]),
          ));
        }
      }
      return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: content));
    }).toList();
  }

  List<pw.Widget> _pdfEducation(pw.Font regular, pw.Font bold, pw.Font italic) {
    final lines = _normalizeEducation(data.education).split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final titleDate = lines.first.split('|');
    final locationDetails = lines.length > 1 ? lines[1].split('|') : <String>[];
    return [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: _pdfEducationTitle(titleDate.first.trim(), regular, bold)),
        if (titleDate.length > 1) pw.SizedBox(width: 115, child: pw.Text(titleDate.last.trim(), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: bold, fontSize: style.subheadingSize))),
      ]),
      if (locationDetails.isNotEmpty)
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(locationDetails.first.trim(), style: pw.TextStyle(font: italic, fontSize: style.descriptionSize)),
          if (locationDetails.length > 1) pw.Text(locationDetails.last.trim(), style: pw.TextStyle(font: italic, fontSize: style.descriptionSize)),
        ]),
    ];
  }

  pw.Widget _pdfEducationTitle(String title, pw.Font regular, pw.Font bold) {
    final parts = title.split(' - ');
    if (parts.length < 2) return pw.Text(title, style: pw.TextStyle(font: bold, fontSize: style.subheadingSize));
    return pw.RichText(text: pw.TextSpan(style: pw.TextStyle(font: regular, fontSize: style.subheadingSize), children: [
      pw.TextSpan(text: parts.first, style: pw.TextStyle(font: bold)),
      pw.TextSpan(text: ' - ${parts.skip(1).join(' - ')}'),
    ]));
  }

  pw.Widget _pdfProjectStoreRow(List<({String platform, String name})> links, pw.Font regular, pw.Font bold) {
    final children = <pw.Widget>[];
    for (final platform in ['Play Store', 'App Store']) {
      final platformLinks = links.where((link) => link.platform == platform).toList();
      if (platformLinks.isEmpty) continue;
      children.add(pw.Padding(
        padding: pw.EdgeInsets.only(left: children.isEmpty ? 0 : 8),
        child: pw.Text('$platform: ', style: pw.TextStyle(font: bold, fontSize: style.descriptionSize)),
      ));
      for (var i = 0; i < platformLinks.length; i++) {
        if (i > 0) children.add(pw.Text(', ', style: pw.TextStyle(font: regular, fontSize: style.descriptionSize)));
        final link = platformLinks[i];
        final label = pw.Text(link.name, style: pw.TextStyle(
          font: bold,
          fontSize: style.descriptionSize,
          decoration: pw.TextDecoration.underline,
          decorationColor: PdfColor.fromInt(0xff414141),
        ));
        final url = _projectUrl(link.name, platform);
        children.add(url == null ? label : pw.UrlLink(destination: url, child: label));
      }
    }
    return pw.Padding(padding: const pw.EdgeInsets.only(left: 12, top: 1), child: pw.Wrap(children: children));
  }

  pw.Widget _pdfGitHubRow(pw.Font regular, pw.Font bold) => pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 1),
        child: pw.Wrap(children: [
          pw.Text('GitHub: ', style: pw.TextStyle(font: bold, fontSize: style.descriptionSize)),
          pw.UrlLink(destination: data.github, child: pw.Text(data.github.replaceFirst(RegExp(r'^https?://'), ''), style: pw.TextStyle(font: regular, fontSize: style.descriptionSize, decoration: pw.TextDecoration.underline, decorationColor: PdfColor.fromInt(0xff414141)))),
        ]),
      );

  @override
  void dispose() { for (final c in controllers.values) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final compact = MediaQuery.sizeOf(context).width < 1000;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfff4f6f3), titleSpacing: 20,
        title: Row(children: [
          const Icon(Icons.description_outlined, color: Color(0xff245b54)),
          if (!compact || isTemporaryResume) ...[
            const SizedBox(width: 9),
            Flexible(child: Text(isTemporaryResume ? 'Temporary resume' : 'Resume Studio - $resumeStudioVersion', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ]),
        actions: [
          if (compact) ...[
            IconButton(tooltip: 'Tailor to JD', onPressed: _showTailorDialog, icon: const Icon(Icons.auto_awesome)),
            IconButton(tooltip: 'Paste AI output', onPressed: () => _showTailorDialog(pasteOnly: true), icon: const Icon(Icons.content_paste_search)),
          ] else ...[
            FilledButton.tonalIcon(onPressed: _showTailorDialog, icon: const Icon(Icons.auto_awesome), label: const Text('Tailor to JD')),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: () => _showTailorDialog(pasteOnly: true), icon: const Icon(Icons.content_paste_search), label: const Text('Paste AI output')),
          ],
          if (compact) IconButton(tooltip: saving ? 'Saved' : 'Save', onPressed: _save, icon: Icon(saving ? Icons.check : Icons.cloud_done_outlined))
          else TextButton.icon(onPressed: _save, icon: Icon(saving ? Icons.check : Icons.cloud_done_outlined), label: Text(saving ? 'Saved' : 'Save')),
          if (compact) IconButton(tooltip: 'Email resume', onPressed: _showEmailResumeDialog, icon: const Icon(Icons.email_outlined))
          else FilledButton.tonalIcon(onPressed: _showEmailResumeDialog, icon: const Icon(Icons.email_outlined), label: const Text('Email resume')),
          if (compact) IconButton(tooltip: 'Export PDF', onPressed: _export, icon: const Icon(Icons.picture_as_pdf_outlined))
          else FilledButton.icon(onPressed: _export, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Export PDF')),
          PopupMenuButton<String>(
            tooltip: 'Resume options',
            onSelected: (value) {
              switch (value) {
                case 'copy_json': _copyResumeJson(); break;
                case 'import_json': _showImportResumeJsonDialog(); break;
                case 'create_temp': _showCreateTemporaryResumeDialog(); break;
                case 'remove_temp': _removeTemporaryResume(); break;
                case 'reset': _resetResumeData(); break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy_json', child: Text('Copy resume JSON')),
              const PopupMenuItem(value: 'import_json', child: Text('Import and save JSON')),
              const PopupMenuItem(value: 'create_temp', child: Text('Create temporary JD resume')),
              if (isTemporaryResume) const PopupMenuItem(value: 'remove_temp', child: Text('Remove temporary resume')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'reset', child: Text('Reset resume data')),
            ],
          ),
          SizedBox(width: compact ? 4 : 16),
        ],
      ),
      body: wide ? Row(children: [Expanded(flex: 11, child: _editor()), Expanded(flex: 9, child: _previewPane())]) : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Edit'), icon: Icon(Icons.edit_outlined)), ButtonSegment(value: 1, label: Text('Preview'), icon: Icon(Icons.visibility_outlined))], selected: {tab}, onSelectionChanged: (s) => setState(() => tab = s.first))),
        Expanded(child: tab == 0 ? _editor() : _previewPane()),
      ]),
    );
  }

  Widget _editor() => ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
        Row(children: [
          const Expanded(child: Text('Build your resume', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          if (isTemporaryResume) const Chip(avatar: Icon(Icons.auto_awesome, size: 16), label: Text('TEMPORARY')),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 18),
          child: Text(
            isTemporaryResume ? 'Edits are saved to this temporary resume; your saved resume stays unchanged.' : 'Your changes are saved on this device.',
            style: const TextStyle(color: Color(0xff68756e)),
          ),
        ),
        _card('Personal details', Icons.person_outline, [
          _field('name', 'Full name'), _field('role', 'Professional title'), _field('email', 'Email address', keyboard: TextInputType.emailAddress),
          _field('phone', 'Phone number', keyboard: TextInputType.phone), _field('location', 'Location'), _field('website', 'LinkedIn'),
          _field('portfolio', 'Portfolio URL'), _field('github', 'GitHub URL'),
        ]),
        _card('Profile', Icons.notes_outlined, [_field('summary', 'Professional summary', lines: 4)]),
        _card('Work experience', Icons.work_outline, [_field('experience', 'Roles and achievements', lines: 6, hint: 'Role | Company | Dates\nDescribe your responsibilities and results.')]),
        _card('Education', Icons.school_outlined, [_field('education', 'Education', lines: 4)]),
        _card('Skills', Icons.auto_awesome_outlined, [_field('skills', 'Skills, separated by commas', lines: 3)]),
        _card('Projects', Icons.workspaces_outline, [
          const Text('Add each project separately. Use blank lines, store labels, and bullets to control how it appears in the resume.'),
          const SizedBox(height: 8),
          ..._projectEntries.asMap().entries.map((entry) {
            final title = entry.value.split('\n').first.split('|').first.trim();
            final details = entry.value.split('\n').skip(1).join('\n').trim();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title.isEmpty ? 'Project ${entry.key + 1}' : title),
              subtitle: details.isEmpty ? null : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Wrap(children: [
                IconButton(tooltip: 'Edit project', onPressed: () => _editProjectEntry(index: entry.key), icon: const Icon(Icons.edit_outlined)),
                IconButton(tooltip: 'Remove project', onPressed: () => _removeProjectEntry(entry.key), icon: const Icon(Icons.delete_outline)),
              ]),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _editProjectEntry,
              icon: const Icon(Icons.add),
              label: const Text('Add project'),
            ),
          ),
          const SizedBox(height: 12),
          _field('certifications', 'Certifications (optional)', lines: 3),
        ]),
        _card('Project store links', Icons.link_outlined, [
          const Text('Paste all app links at once, or add them individually. Match each app name to the name used in Projects so it becomes clickable in the preview and PDF.'),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _pasteBulkProjectLinks, icon: const Icon(Icons.content_paste), label: const Text('Paste links in bulk')),
            OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _bulkStoreLinksPrompt()));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt copied with only the project/app names in this resume.')));
            }, icon: const Icon(Icons.link_outlined), label: const Text('Copy store links prompt')),
            OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: resumeSetupAiPrompt));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI prompt copied. Paste it into any AI tool with your resume and all store URLs.')));
            }, icon: const Icon(Icons.content_copy), label: const Text('Copy full resume prompt')),
          ]),
          const SizedBox(height: 8),
          ...projectLinks.asMap().entries.map((entry) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value['project'] ?? ''),
            subtitle: Text([
              if ((entry.value['playStore'] ?? '').isNotEmpty) 'Play Store',
              if ((entry.value['appStore'] ?? '').isNotEmpty) 'App Store',
            ].join(' / ').isEmpty ? 'No links added' : [
              if ((entry.value['playStore'] ?? '').isNotEmpty) 'Play Store',
              if ((entry.value['appStore'] ?? '').isNotEmpty) 'App Store',
            ].join(' / ')),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Edit links', onPressed: () => _editProjectLink(index: entry.key), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Remove links', onPressed: () => _removeProjectLink(entry.key), icon: const Icon(Icons.delete_outline)),
            ]),
          )),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _editProjectLink,
              icon: const Icon(Icons.add),
              label: const Text('Add project links'),
            ),
          ),
        ]),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save resume'), style: FilledButton.styleFrom(padding: const EdgeInsets.all(15))),
      ]);

  Widget _field(String key, String label, {int lines = 1, TextInputType? keyboard, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextField(controller: controllers[key], keyboardType: keyboard, minLines: lines, maxLines: lines, textCapitalization: TextCapitalization.sentences,
          onChanged: (_) { setState(() {}); _save(); }, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  Widget _settingSlider(String label, double value, double min, double max, ResumeStyleSettings Function(double) update, {StateSetter? refresh, VoidCallback? onPreviewChanged}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(label)), Text('${value.toStringAsFixed(1)} pt', style: const TextStyle(color: Color(0xff68756e), fontSize: 12))]),
          Slider(
            value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: ((max - min) * 2).round(),
            onChanged: (next) {
              _updateStyle(update(next));
              refresh?.call(() {});
              onPreviewChanged?.call();
            },
            onChangeEnd: (_) => _saveStyle(),
          ),
        ]),
      );

  Widget _pdfPageCountInfo(int pageCount) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xfff2f6f3), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xffdfe7e1))),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 20),
          const SizedBox(width: 9),
          const Text('PDF page count', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$pageCount ${pageCount == 1 ? 'page' : 'pages'}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Future<void> _showStyleDialog() async {
    var pageCount = await _calculatePdfPageCount();
    var requestId = 0;
    var dialogOpen = true;
    Future<void> refreshPageCount(StateSetter refreshDialog) async {
      final request = ++requestId;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!dialogOpen || request != requestId) return;
      final count = await _calculatePdfPageCount();
      if (dialogOpen && request == requestId && mounted) refreshDialog(() => pageCount = count);
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: const Row(children: [Icon(Icons.tune), SizedBox(width: 10), Text('Page layout & typography')]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _pdfPageCountInfo(pageCount),
                _settingSlider('Side margin', style.horizontalMargin, 5, 40, (v) => style.copyWith(horizontalMargin: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Top margin', style.topMargin, 5, 60, (v) => style.copyWith(topMargin: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Bottom margin', style.bottomMargin, 5, 60, (v) => style.copyWith(bottomMargin: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Content padding', style.contentPadding, 0, 24, (v) => style.copyWith(contentPadding: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Description size', style.descriptionSize, 8, 14, (v) => style.copyWith(descriptionSize: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Section heading size', style.headingSize, 10, 18, (v) => style.copyWith(headingSize: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
                _settingSlider('Subheading size', style.subheadingSize, 9, 16, (v) => style.copyWith(subheadingSize: v), refresh: refreshDialog, onPreviewChanged: () => refreshPageCount(refreshDialog)),
              ]),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                _updateStyle(const ResumeStyleSettings());
                refreshDialog(() => pageCount = 1);
                refreshPageCount(refreshDialog);
                _saveStyle();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
            FilledButton(onPressed: () { _saveStyle(); Navigator.pop(dialogContext); }, child: const Text('Done')),
          ],
        ),
      ),
    );
    dialogOpen = false;
  }

  Widget _card(String title, IconData icon, List<Widget> fields) => Card(
        margin: const EdgeInsets.only(bottom: 14), color: Colors.white, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xffe6ebe7))),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: const Color(0xff245b54), size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))]),
          const SizedBox(height: 14), ...fields,
        ])),
      );

  Widget _previewPane() => Container(
        color: const Color(0xffe9eeea),
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            const Text('Live preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (isTemporaryResume) ...[
              const SizedBox(width: 8),
              const Chip(label: Text('TEMPORARY'), visualDensity: VisualDensity.compact),
            ],
            const Spacer(),
            Icon(Icons.auto_awesome, size: 17, color: Colors.teal.shade700),
            const SizedBox(width: 5),
            const Text('Clean professional', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            IconButton(tooltip: 'Page layout & typography', onPressed: _showStyleDialog, icon: const Icon(Icons.tune)),
          ]),
          const SizedBox(height: 14),
          Expanded(
            child: PdfPreview.builder(
              build: (_) => _buildResumePdfBytes(),
              initialPageFormat: const PdfPageFormat(595.5, 842),
              pageFormats: const {'A4': PdfPageFormat(595.5, 842)},
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
              useActions: false,
              dynamicLayout: false,
              shouldRepaint: true,
              maxPageWidth: 595.5,
              padding: EdgeInsets.zero,
              previewPageMargin: const EdgeInsets.symmetric(vertical: 10),
              scrollViewDecoration: const BoxDecoration(color: Color(0xffe9eeea)),
              pdfPreviewPageDecoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xffd8ded9))),
              pagesBuilder: (context, pages) => ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 595.5),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final pageWidth = constraints.maxWidth;
                        final pageHeight = pageWidth / page.aspectRatio;
                        final pageLinks = index < _pdfPreviewLinks.length
                            ? _pdfPreviewLinks[index]
                            : const <_PdfPreviewLink>[];
                        return SizedBox(
                          width: pageWidth,
                          height: pageHeight,
                          child: ColoredBox(
                            color: Colors.white,
                            child: Stack(children: [
                              Positioned.fill(child: Image(image: page.image, fit: BoxFit.fill)),
                              for (final link in pageLinks)
                                Positioned(
                                  left: link.rect.left * pageWidth / link.pageWidth,
                                  top: (link.pageHeight - link.rect.top) * pageHeight / link.pageHeight,
                                  width: link.rect.width * pageWidth / link.pageWidth,
                                  height: link.rect.height * pageHeight / link.pageHeight,
                                  child: Tooltip(
                                    message: 'Open link',
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _openLink(link.url),
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      );

  Widget _previewLink(String label, String url, {double? size}) => InkWell(
        onTap: () => _openLink(url),
        child: Text(label, style: TextStyle(fontFamily: 'serif', fontSize: size ?? style.descriptionSize, color: Colors.black, decoration: TextDecoration.underline)),
      );

  List<Widget> _previewProjectLines(String source) {
    final widgets = <Widget>[];
    for (final entry in source.split(RegExp(r'\n\s*\n')).where((item) => item.trim().isNotEmpty)) {
      final lines = entry.split('\n').where((line) => line.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final heading = _parseEntryHeader(lines.first);
      widgets.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: RichText(text: TextSpan(style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, color: Colors.black), children: [
          TextSpan(text: heading.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (heading.company.isNotEmpty) TextSpan(text: ', ${heading.company}'),
        ]))),
        if (heading.date.isNotEmpty) SizedBox(width: 115, child: Text(heading.date, textAlign: TextAlign.right, style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, fontWeight: FontWeight.w700))),
      ]));
      final storeLines = lines.skip(1).where(_isProjectStoreLine).toList();
      final storeTokens = _projectStoreTokensForEntry(heading.title, storeLines, entryText: lines.skip(1).join(' '));
      if (storeTokens.isNotEmpty) widgets.add(_previewProjectStoreRow(storeTokens));
      for (final line in lines.skip(1)) {
        if (_isProjectStoreLine(line)) {
          continue;
        } else if (line.startsWith('Tech Stack:')) {
          final colon = line.indexOf(':');
          widgets.add(Padding(padding: const EdgeInsets.only(left: 12), child: RichText(text: TextSpan(style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, color: Colors.black), children: [
            TextSpan(text: '${line.substring(0, colon + 1)} ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: line.substring(colon + 1).trim()),
          ]))));
        } else {
          final isBullet = line.startsWith('-');
          widgets.add(Padding(padding: EdgeInsets.only(left: isBullet ? 5.8 : 0, top: 1), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isBullet) Text('- ', style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, height: 1.1)),
            Expanded(child: Text(isBullet ? line.substring(1).trimLeft() : line, style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, height: 1.1))),
          ])));
        }
      }
      widgets.add(const SizedBox(height: 10));
    }
    if (controllers['github']!.text.trim().isNotEmpty) {
      widgets.add(Padding(padding: const EdgeInsets.only(left: 12, top: 1), child: Wrap(children: [
        Text('GitHub: ', style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, fontWeight: FontWeight.w700)),
        _previewLink(controllers['github']!.text.replaceFirst(RegExp(r'^https?://'), ''), controllers['github']!.text),
      ])));
    }
    return widgets;
  }

  Widget _previewProjectStoreRow(List<({String platform, String name})> links) {
    final children = <Widget>[];
    for (final platform in ['Play Store', 'App Store']) {
      final platformLinks = links.where((link) => link.platform == platform).toList();
      if (platformLinks.isEmpty) continue;
      children.add(Padding(
        padding: EdgeInsets.only(left: children.isEmpty ? 0 : 8),
        child: Text('$platform: ', style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, fontWeight: FontWeight.w700)),
      ));
      for (var i = 0; i < platformLinks.length; i++) {
        if (i > 0) children.add(Text(', ', style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize)));
        final link = platformLinks[i];
        final url = _projectUrl(link.name, platform);
        children.add(url == null
            ? Text(link.name, style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, decoration: TextDecoration.underline))
            : _previewLink(link.name, url));
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(left: 12, top: 1), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: children));
  }

  Widget _previewSkills() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final line in controllers['skills']!.text.split('\n').where((line) => line.trim().isNotEmpty))
          Padding(padding: const EdgeInsets.only(bottom: 2), child: _previewLabeledLine(line, style.descriptionSize)),
      ]);

  Widget _previewLabeledLine(String line, double size) {
    final colon = line.indexOf(':');
    if (colon < 0) return Text(line, style: TextStyle(fontFamily: 'serif', fontSize: size, height: 1.15));
    return RichText(text: TextSpan(style: TextStyle(fontFamily: 'serif', fontSize: size, height: 1.15, color: Colors.black), children: [
      TextSpan(text: '${line.substring(0, colon)}:', style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: line.substring(colon + 1)),
    ]));
  }

  Widget _previewEntries(String key) {
    final source = controllers[key]!.text;
    if (key == 'projects') return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _previewProjectLines(source));
    final entries = source.split(RegExp(r'\n\s*\n')).where((entry) => entry.trim().isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final entry in entries) ...[
        for (final line in entry.split('\n').where((line) => line.trim().isNotEmpty).take(1)) _previewJobHeading(line),
        for (final line in entry.split('\n').where((line) => line.trim().isNotEmpty).skip(1)) _previewBullet(line),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _previewJobHeading(String line) {
    final heading = _parseEntryHeader(line);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: RichText(text: TextSpan(style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, color: Colors.black), children: [
        TextSpan(text: heading.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (heading.company.isNotEmpty) TextSpan(text: ', ${heading.company}'),
      ]))),
      if (heading.date.isNotEmpty) SizedBox(width: 115, child: Text(heading.date, textAlign: TextAlign.right, style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, fontWeight: FontWeight.w700))),
    ]);
  }

  ({String title, String company, String date}) _parseEntryHeader(String source) {
    final parts = source.split('|').map((part) => part.trim()).toList();
    var title = parts.isEmpty ? '' : parts.first;
    var company = '';
    var date = '';
    if (parts.length >= 3) {
      company = parts[1];
      date = parts.skip(2).join(' | ').trim();
    } else if (parts.length == 2) {
      final secondPartLooksLikeDate = RegExp(
        r'\b(?:19|20)\d{2}\b|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\b(?:present|current)\b',
        caseSensitive: false,
      ).hasMatch(parts[1]);
      if (secondPartLooksLikeDate) {
        date = parts[1];
      } else {
        company = parts[1];
      }
    }
    if (company.isEmpty) {
      final commaParts = title.split(',');
      if (commaParts.length > 1) {
        title = commaParts.first.trim();
        company = commaParts.skip(1).join(',').trim();
      }
    }
    return (title: title, company: company, date: date);
  }

  Widget _previewBullet(String line) {
    final bullet = line.startsWith('-');
    return Padding(padding: EdgeInsets.only(left: bullet ? 5.8 : 0, top: 1), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (bullet) Text('- ', style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, height: 1.1)),
      Expanded(child: Text(bullet ? line.substring(1).trimLeft() : line, style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, height: 1.1))),
    ]));
  }

  Widget _previewEducation() {
    final lines = _normalizeEducation(controllers['education']!.text).split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final titleDate = lines.first.split('|');
    final degree = titleDate.first.trim().split(' - ');
    final location = lines.length > 1 ? lines[1].split('|') : <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: RichText(text: TextSpan(style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, color: Colors.black), children: [
          TextSpan(text: degree.first, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (degree.length > 1) TextSpan(text: ' - ${degree.skip(1).join(' - ')}'),
        ]))),
        if (titleDate.length > 1) SizedBox(width: 115, child: Text(titleDate.last.trim(), textAlign: TextAlign.right, style: TextStyle(fontFamily: 'serif', fontSize: style.subheadingSize, fontWeight: FontWeight.w700))),
      ]),
      if (location.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(location.first.trim(), style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, fontStyle: FontStyle.italic)),
        if (location.length > 1) Text(location.last.trim(), style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, fontStyle: FontStyle.italic)),
      ]),
    ]);
  }

  Widget _previewSection(String title, String key) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Container(width: double.infinity, height: 1, color: Colors.black),
        const SizedBox(height: 5),
        Text(title, style: TextStyle(fontFamily: 'serif', fontSize: style.headingSize, fontWeight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 5),
        if (key == 'summary') Text(controllers[key]!.text, style: TextStyle(fontFamily: 'serif', fontSize: style.descriptionSize, height: 1.15))
        else if (key == 'skills') _previewSkills()
        else if (key == 'education') _previewEducation()
        else _previewEntries(key),
      ]));
}

class _PdfPreviewLink {
  const _PdfPreviewLink({required this.url, required this.rect, required this.pageWidth, required this.pageHeight});

  final String url;
  final PdfRect rect;
  final double pageWidth;
  final double pageHeight;
}

class _ProjectEditorResult {
  const _ProjectEditorResult({required this.content, required this.links});
  final String content;
  final List<Map<String, String>> links;
}

class _ProjectStoreLinkDraft {
  _ProjectStoreLinkDraft(Map<String, String> values)
      : name = TextEditingController(text: values['project'] ?? ''),
        playStore = TextEditingController(text: values['playStore'] ?? ''),
        appStore = TextEditingController(text: values['appStore'] ?? '');

  final TextEditingController name;
  final TextEditingController playStore;
  final TextEditingController appStore;

  Map<String, String> toMap() => {
        'project': name.text.trim(),
        'playStore': playStore.text.trim(),
        'appStore': appStore.text.trim(),
      };

  void dispose() {
    name.dispose();
    playStore.dispose();
    appStore.dispose();
  }
}

class _ProjectEditorScreen extends StatefulWidget {
  const _ProjectEditorScreen({required this.initialContent, required this.initialLinks});

  final String initialContent;
  final List<Map<String, String>> initialLinks;

  @override
  State<_ProjectEditorScreen> createState() => _ProjectEditorScreenState();
}

class _ProjectEditorScreenState extends State<_ProjectEditorScreen> {
  late final TextEditingController titleController;
  late final TextEditingController dateController;
  late final TextEditingController detailsController;
  final linkDrafts = <_ProjectStoreLinkDraft>[];
  final allDrafts = <_ProjectStoreLinkDraft>[];

  @override
  void initState() {
    super.initState();
    final lines = widget.initialContent.split('\n');
    final heading = lines.isEmpty ? <String>[] : lines.first.split('|');
    titleController = TextEditingController(text: heading.isEmpty ? '' : heading.first.trim());
    dateController = TextEditingController(text: heading.length > 1 ? heading.skip(1).join('|').trim() : '');
    detailsController = TextEditingController(text: lines.skip(1).join('\n').trim());
    for (final link in widget.initialLinks) {
      final draft = _ProjectStoreLinkDraft(link);
      linkDrafts.add(draft);
      allDrafts.add(draft);
    }
  }

  void _addLink() {
    final draft = _ProjectStoreLinkDraft(const {});
    setState(() {
      linkDrafts.add(draft);
      allDrafts.add(draft);
    });
  }

  void _removeLink(_ProjectStoreLinkDraft draft) => setState(() => linkDrafts.remove(draft));

  void _save() {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a project name.')));
      return;
    }
    final date = dateController.text.trim();
    final header = date.isEmpty ? title : '$title | $date';
    final details = detailsController.text.trim();
    final content = details.isEmpty ? header : '$header\n$details';
    final links = linkDrafts.map((draft) => draft.toMap()).where((link) =>
        link['project']!.isNotEmpty && (link['playStore']!.isNotEmpty || link['appStore']!.isNotEmpty)).toList();
    Navigator.pop(context, _ProjectEditorResult(content: content, links: links));
  }

  @override
  void dispose() {
    titleController.dispose();
    dateController.dispose();
    detailsController.dispose();
    for (final draft in allDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.initialContent.isEmpty ? 'Add project' : 'Edit project'),
          actions: [IconButton(tooltip: 'Save project', onPressed: _save, icon: const Icon(Icons.check))],
        ),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Project name')),
          const SizedBox(height: 12),
          TextField(controller: dateController, decoration: const InputDecoration(labelText: 'Date range')),
          const SizedBox(height: 12),
          TextField(
            controller: detailsController,
            minLines: 8,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Company, role, tech stack, and project details',
              alignLabelWithHint: true,
              hintText: 'Company or subtitle\nTech Stack: Flutter, Dart\n- Describe what you built',
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('Store links', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: _addLink, icon: const Icon(Icons.add), label: const Text('Add app')),
          ]),
          const Text('Each app name should match the name shown in the project details.'),
          const SizedBox(height: 8),
          ...linkDrafts.map((draft) => Card(
            child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: draft.name, decoration: const InputDecoration(labelText: 'App name'))),
                IconButton(tooltip: 'Remove app links', onPressed: () => _removeLink(draft), icon: const Icon(Icons.delete_outline)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: draft.playStore, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Play URL')),
              const SizedBox(height: 8),
              TextField(controller: draft.appStore, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Apple App Store URL')),
            ])),
          )),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save project')),
        ]),
      );
}

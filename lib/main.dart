import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MassTamilanApp());
}

class MassTamilanApp extends StatelessWidget {
  const MassTamilanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MassTamilan Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DownloaderScreen(),
    );
  }
}

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  List<Map<String, String>> _queries = [];
  bool _isProcessing = false;
  String _currentTask = "Ready";
  double _progress = 0.0;
  
  InAppWebViewController? webViewController;
  HeadlessInAppWebView? headlessWebView;

  @override
  void initState() {
    super.initState();
    _initHeadlessWebView();
  }
  
  void _initHeadlessWebView() {
    // This is the "Invisible Browser" that bypasses Cloudflare
    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("https://www.masstamilan.dev/")),
      onWebViewCreated: (controller) {
        webViewController = controller;
      },
      onLoadStop: (controller, url) async {
        // Here we can inject Javascript to scrape the DOM once Cloudflare passes
        print("Page loaded: $url");
      },
    );
    
    headlessWebView?.run();
  }

  @override
  void dispose() {
    headlessWebView?.dispose();
    super.dispose();
  }

  Future<void> _pickAndParseCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null) {
        if (result.files.single.path == null) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: File path is null. Please use a different file manager app.')));
           return;
        }
        
        File file = File(result.files.single.path!);
        
        if (!file.path.toLowerCase().endsWith('.csv')) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Please select a .csv file, not an Excel (.xlsx) file!')));
           return;
        }

        final input = await file.readAsString();
        // Normalize line endings to ensure it works across all OS types (Windows \r\n vs Mac/Linux \n)
        final normalizedInput = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        List<List<dynamic>> rows = const CsvToListConverter(eol: '\n').convert(normalizedInput);

        if (rows.isEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: The CSV file is completely empty!')));
           return;
        }

        List<dynamic> headers = rows.first;
        bool hasHeaders = headers.any((h) => h.toString().toLowerCase().contains('movie'));
        
        int movieIdx = 0;
        int songIdx = -1;
        
        if (hasHeaders) {
           movieIdx = headers.indexWhere((h) => h.toString().toLowerCase().contains('movie'));
           songIdx = headers.indexWhere((h) => h.toString().toLowerCase().contains('song'));
           if (movieIdx == -1) movieIdx = 0;
        }

        List<Map<String, String>> parsedQueries = [];
        int startIndex = hasHeaders ? 1 : 0;
        
        for (int i = startIndex; i < rows.length; i++) {
          var row = rows[i];
          if (row.isEmpty) continue;
          
          String movie = row.length > movieIdx ? row[movieIdx].toString() : '';
          String song = (songIdx != -1 && row.length > songIdx) ? row[songIdx].toString() : '';

          if (movie.trim().isNotEmpty) {
            parsedQueries.add({"movie": movie.trim(), "song": song.trim()});
          }
        }

        if (parsedQueries.isEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Could not find any movie names in the file!')));
           return;
        }

        setState(() {
          _queries = parsedQueries;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Success! Loaded ${parsedQueries.length} items.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error reading file: $e'),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  Future<void> _startDownloadProcess() async {
    if (_queries.isEmpty) return;

    if (Platform.isAndroid) {
      var storageStatus = await Permission.storage.request();
      var manageStatus = await Permission.manageExternalStorage.request();
      
      if (!storageStatus.isGranted && !manageStatus.isGranted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Please allow Storage / All Files Access in Settings to save MP3s!'))
         );
         await Future.delayed(const Duration(seconds: 2));
         await openAppSettings();
         return;
      }
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
    });

    final dio = Dio();
    
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    final String basePath = "${downloadsDir?.path ?? ''}/Masstamilan";
    bool hasErrors = false;

    for (int i = 0; i < _queries.length; i++) {
      var query = _queries[i];
      String targetMovie = query['movie']!;
      String targetSong = query['song']!;
      
      setState(() {
        _currentTask = "Searching for $targetMovie...";
        _progress = (i / _queries.length);
      });

      await webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri("https://www.masstamilan.dev/search?keyword=${Uri.encodeComponent(targetMovie)}"))
      );
      
      await Future.delayed(const Duration(seconds: 4));
      
      String? movieUrl = await webViewController?.evaluateJavascript(source: """
        (function() {
          let links = document.querySelectorAll('a');
          for(let i=0; i<links.length; i++) {
            if(links[i].href.includes('-songs')) return links[i].href;
          }
          return null;
        })();
      """);

      if (movieUrl != null && movieUrl.isNotEmpty) {
        setState(() => _currentTask = "Found Movie. Extracting songs...");
        
        await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(movieUrl)));
        await Future.delayed(const Duration(seconds: 4));
        
        String jsExtractSongs = """
          JSON.stringify(Array.from(document.querySelectorAll('a')).filter(a => a.href.includes('d320_cdn')).map(a => {
            let title = 'Unknown';
            let tr = a.closest('tr');
            if(tr) {
               let td = tr.querySelector('td');
               if(td) {
                  let h2 = td.querySelector('h2') || td.querySelector('a');
                  title = h2 ? h2.innerText.trim() : td.innerText.trim();
               }
            }
            return {title: title, link: a.href};
          }));
        """;
        
        dynamic songsJson = await webViewController?.evaluateJavascript(source: jsExtractSongs);
        if (songsJson != null) {
          List<dynamic> songs = jsonDecode(songsJson);
          
          for (var songData in songs) {
            String songTitle = songData['title'];
            String songLink = songData['link'];
            
            if (targetSong.isNotEmpty && !songTitle.toLowerCase().contains(targetSong.toLowerCase())) {
               continue;
            }
            
            setState(() => _currentTask = "Downloading $songTitle...");
            
            try {
              String cleanTitle = songTitle.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-_]'), '').trim();
              String cleanMovie = targetMovie.replaceAll(RegExp(r'[^a-zA-Z0-9\s\-_]'), '').trim();
              
              Directory movieDir = Directory("$basePath/$cleanMovie");
              if (!await movieDir.exists()) await movieDir.create(recursive: true);
              
              String savePath = "${movieDir.path}/$cleanTitle.mp3";
              
              if (!File(savePath).existsSync()) {
                await dio.download(songLink, savePath);
              }
              await Future.delayed(const Duration(seconds: 1));
            } catch (e) {
              hasErrors = true;
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving $songTitle: $e")));
              }
            }
          }
        }
      }
    }

    setState(() {
      _isProcessing = false;
      _progress = 1.0;
      _currentTask = hasErrors 
          ? "Finished with errors. Check permissions." 
          : "Done! Saved to:\\n$basePath";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MT Downloader', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      _isProcessing ? Icons.cloud_download : Icons.library_music,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _currentTask,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickAndParseCSV,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Load CSV'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isProcessing || _queries.isEmpty) ? null : _startDownloadProcess,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            Expanded(
              child: _queries.isEmpty 
                ? const Center(child: Text("No CSV loaded yet.\\nFormat: 'Movie Name', 'Song Name'", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _queries.length,
                    itemBuilder: (context, index) {
                      var q = _queries[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text("${index + 1}"),
                        ),
                        title: Text(q['movie'] ?? ''),
                        subtitle: Text(q['song']?.isEmpty == true ? 'All Songs' : q['song']!),
                        trailing: const Icon(Icons.pending, color: Colors.grey),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

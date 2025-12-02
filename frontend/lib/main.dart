import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local RAG AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? sources;

  ChatMessage({required this.text, required this.isUser, this.sources});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String apiUrl = "http://127.0.0.1:8000"; 
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isIngesting = false;
  bool _isConfigExpanded = true;

  Future<void> _ingestDocuments() async {
    if (_folderController.text.isEmpty) return;
    setState(() => _isIngesting = true);
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/ingest'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"folder_path": _folderController.text}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.green));
           setState(() => _isConfigExpanded = false);
        }
      } else {
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isIngesting = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_queryController.text.trim().isEmpty) return;
    final query = _queryController.text;
    
    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
      _isLoading = true;
    });
    _queryController.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"question": query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)); 
        setState(() {
          _messages.add(ChatMessage(
            text: data['answer'], 
            isUser: false, 
            sources: List<String>.from(data['sources'] ?? [])
          ));
        });
      } else {
        String errorMsg = "Error en el servidor (${response.statusCode}).";
        try {
            final decoded = jsonDecode(response.body);
            if (decoded['detail'] != null) errorMsg = decoded['detail'];
        } catch (e) {}
        
        setState(() => _messages.add(ChatMessage(text: errorMsg, isUser: false)));
      }
    } catch (e) {
      setState(() => _messages.add(ChatMessage(text: "Error de conexión: $e", isUser: false)));
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RAG Chat Local"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isConfigExpanded ? Icons.expand_less : Icons.settings),
            onPressed: () => setState(() => _isConfigExpanded = !_isConfigExpanded),
          )
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isConfigExpanded ? 150 : 0,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _folderController,
                          decoration: const InputDecoration(
                            labelText: "Ruta de carpeta (ej: C:\\Docs)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isIngesting ? null : _ingestDocuments,
                        icon: _isIngesting 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                          : const Icon(Icons.folder_open),
                        label: const Text("Cargar"),
                      )
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text("Acepta PDF, TXT y DOCX. Asegúrate de que Ollama esté corriendo.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  )
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: msg.isUser ? Colors.teal : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!msg.isUser) 
                          const Text("IA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black54)),
                        Text(
                          msg.text,
                          style: TextStyle(color: msg.isUser ? Colors.white : Colors.black87),
                        ),
                        if (!msg.isUser && msg.sources != null && msg.sources!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Wrap(
                              spacing: 5,
                              children: msg.sources!.map((s) => Chip(
                                label: Text(s.split(r'\').last, style: const TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              )).toList(),
                            ),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      hintText: "Escribe tu consulta...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.teal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Function(dynamic)? onMessage;
  Function(Map<String, dynamic>)? onTaskUpdate;
  Function(Map<String, dynamic>)? onLibraryUpdate;

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          // Try to parse as JSON
          try {
            final data = jsonDecode(message);
            if (data is Map<String, dynamic>) {
              final event = data['event'];
              final payload = data['data'];
              
              if (event == 'task_update' && onTaskUpdate != null && payload != null) {
                onTaskUpdate!(payload);
              } else if (event == 'library_updated' && onLibraryUpdate != null) {
                onLibraryUpdate!(payload ?? {});
              }
            }
          } catch (e) {
            // Not JSON, treat as simple string
          }
          
          if (onMessage != null) {
            onMessage!(message);
          }
        },
        onError: (error) => print('WS Error: $error'),
        onDone: () {
          print('WS Closed');
          // Reconnect after a delay
          Future.delayed(const Duration(seconds: 3), () => connect());
        },
      );
    } catch (e) {
      print('WS Connection Failed: $e');
    }
  }

  void close() {
    _channel?.sink.close();
  }
}

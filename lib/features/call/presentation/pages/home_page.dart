import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/call_controller.dart';
import '../widgets/video_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final CallController _controller = CallController();
  final TextEditingController _roomIdController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  Future<void> _copyRoomId() async {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room ID is empty. Create a room first.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: roomId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room ID copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Flutter WebRTC + Firebase')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: VideoView(
                          renderer: _controller.localRenderer,
                          label: 'Local',
                          mirror: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VideoView(
                          renderer: _controller.remoteRenderer,
                          label: 'Remote',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _roomIdController,
                  decoration: InputDecoration(
                    labelText: 'Room ID',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Copy Room ID',
                      onPressed: _copyRoomId,
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _controller.isLoading
                              ? null
                              : () async {
                                await _controller.createRoom();
                                final roomId = _controller.activeRoomId;
                                if (roomId != null) {
                                  _roomIdController.text = roomId;
                                }
                              },
                      icon: const Icon(Icons.video_call),
                      label: const Text('Create Room'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _controller.isLoading
                              ? null
                              : () => _controller.joinRoom(
                                _roomIdController.text.trim(),
                              ),
                      icon: const Icon(Icons.call),
                      label: const Text('Join Room'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _controller.isLoading
                              ? null
                              : () => _controller.hangUp(),
                      icon: const Icon(Icons.call_end),
                      label: const Text('Hang Up'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _controller.isLoading
                              ? null
                              : () => _controller.toggleMic(),
                      icon: Icon(
                        _controller.isMicMuted ? Icons.mic_off : Icons.mic,
                      ),
                      label: Text(
                        _controller.isMicMuted ? 'Unmute Mic' : 'Mute Mic',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _controller.isLoading
                              ? null
                              : () => _controller.toggleCamera(),
                      icon: Icon(
                        _controller.isCameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                      ),
                      label: Text(
                        _controller.isCameraOff ? 'Camera On' : 'Camera Off',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StatusBar(controller: _controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null) {
      return Text(
        controller.errorMessage!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final roomText =
        controller.activeRoomId != null
            ? 'Active Room: ${controller.activeRoomId}'
            : 'No active room';

    return Text(
      '$roomText\n'
      'Peer: ${controller.peerConnectionState} | '
      'ICE: ${controller.iceConnectionState} | '
      'Gathering: ${controller.iceGatheringState}\n'
      'TURN: ${controller.isTurnConfigured ? 'configured' : 'not configured'}',
    );
  }
}

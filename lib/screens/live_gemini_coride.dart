import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:corides/constants.dart';
import 'package:corides/utils/audio_handler.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/map_service.dart';
import 'package:corides/models/ride_model.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/models/notification_model.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/screens/peers_chat_screen.dart';

class LiveGeminiCorideScreen extends StatefulWidget {
  final bool isDriverMode;
  final String? currentLocationAddress;
  
  const LiveGeminiCorideScreen({
    super.key, 
    this.isDriverMode = false, 
    this.currentLocationAddress
  });

  @override
  _LiveGeminiCorideScreenState createState() => _LiveGeminiCorideScreenState();
}

class _LiveGeminiCorideScreenState extends State<LiveGeminiCorideScreen> {
  final AudioHandler _audioHandler = AudioHandler();
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  bool _isConnected = false;
  bool _isConnecting = true;
  bool _isMuted = false;
  bool _isAssistantSpeaking = false;
  
  double _userAudioLevel = 0.0;
  double _assistantAudioLevel = 0.0;
  
  final List<String> _logs = [];

  // CoRide State
  RideModel? _pendingRide;
  LatLng? _originCoords;
  LatLng? _destinationCoords;
  bool _isGeocodingRoute = false;
  List<RideModel> _matchingRides = [];
  bool _isSearchingRides = false;
  final Map<String, UserModel> _userCache = {};
  Timer? _assistantTimer;

  @override
  void initState() {
    super.initState();
    _initAudioAndConnect();
  }

  Future<void> _initAudioAndConnect() async {
    try {
      await _audioHandler.init();
      _connectToGemini();
    } catch (e) {
      _log("Error initializing audio: $e");
    }
  }

  void _connectToGemini() {
    final apiKey = AppConstants.geminiApiKey.trim();
    final now = DateTime.now();
    final currentTime = now.toString();
    
    // v1beta Multimodal Live WebSocket endpoint
    final uri = Uri.https(
      "generativelanguage.googleapis.com",
      "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
      {"key": apiKey},
    );
    
    final wssUrl = uri.toString().replaceFirst("https://", "wss://");
    _log("Connecting to Gemini 3.1 CoRide Assistant...");
    
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(wssUrl));
      
      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: (e) {
          _log("WebSocket Error: $e");
          setState(() {
            _isConnected = false;
            _isConnecting = false;
          });
        },
        onDone: () {
          _log("WebSocket Connection Closed");
          setState(() {
            _isConnected = false;
            _isConnecting = false;
          });
        },
      );

      // 1. Send Setup Message (Config + Tools)
      _sendEvent({
        "setup": {
          "model": "models/gemini-3.1-flash-live-preview",
          "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
              "voiceConfig": {
                "prebuiltVoiceConfig": {
                  "voiceName": "Zephyr" 
                }
              }
            }
          },
          "systemInstruction": {
            "parts": [{
              "text": "You are a helpful ride booking assistant for CoRides. Current time is $currentTime. "
                  "${widget.currentLocationAddress != null ? "The user\'s CURRENT LOCATION is: ${widget.currentLocationAddress}. Use this as the default starting point (Origin) if the user doesn\'t specify one." : ""} "
                  "Currently, the user is in ${widget.isDriverMode ? "DRIVER" : "PASSENGER"} mode. "
                  "If the user is a PASSENGER and wants to see available rides, use find_matching_rides(type: \"offer\") to show them active offers from drivers. "
                  "If the user is a DRIVER and wants to find passengers, use find_matching_rides(type: \"request\") to show them active requests from passengers. "
                  "Once you have all the details (Origin, Destination, Time, Price, Seats, and Type), use prepare_ride_summary to show the confirmation card. "
                  "ALWAYS ask for missing info one by one."
            }]
          },
          "tools": [
            {
              "functionDeclarations": [
                {
                  "name": "prepare_ride_summary",
                  "description": "Shows a summary card of the ride details for the user to confirm.",
                  "parameters": {
                    "type": "OBJECT",
                    "properties": {
                      "origin_address": {"type": "STRING", "description": "The starting address"},
                      "destination_address": {"type": "STRING", "description": "The destination address"},
                      "departure_time": {"type": "STRING", "description": "ISO 8601 format date-time string"},
                      "negotiated_price": {"type": "NUMBER", "description": "Total price for the ride"},
                      "seats_available": {"type": "INTEGER", "description": "Number of seats available"},
                      "type": {"type": "STRING", "enum": ["request", "offer"], "description": "Either \"request\" or \"offer\""}
                    },
                    "required": ["origin_address", "destination_address", "departure_time", "negotiated_price", "seats_available", "type"]
                  }
                },
                {
                  "name": "find_matching_rides",
                  "description": "Searches for active rides in the database.",
                  "parameters": {
                    "type": "OBJECT",
                    "properties": {
                      "type": {"type": "STRING", "enum": ["offer", "request"], "description": "Search for \"offer\" as a passenger, or \"request\" as a driver."}
                    },
                    "required": ["type"]
                  }
                },
                {
                  "name": "get_location_suggestions",
                  "description": "Verifies an address and returns suggestions.",
                  "parameters": {
                    "type": "OBJECT",
                    "properties": {
                      "address": {"type": "STRING", "description": "The address or place name to verify"}
                    },
                    "required": ["address"]
                  }
                }
              ]
            }
          ]
        }
      });
      
    } catch (e) {
      _log("Connection failed: $e");
      setState(() => _isConnecting = false);
    }
  }

  void _onMessageReceived(dynamic message) {
    try {
      final String textMessage = message is String ? message : utf8.decode(message as List<int>);
      final json = jsonDecode(textMessage);
      
      if (json.containsKey("setupComplete")) {
        _log("Handshake successful with tools registered");
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
        _startListening();
      } else if (json.containsKey("serverContent")) {
        final serverContent = json["serverContent"];
        if (serverContent.containsKey("modelTurn")) {
          final parts = serverContent["modelTurn"]["parts"];
          for (var part in parts) {
            if (part.containsKey("inlineData")) {
              final audioBase64 = part["inlineData"]["data"];
              _handleAssistantAudio(audioBase64);
            }
          }
        }
      } else if (json.containsKey("toolCall")) {
        _handleToolCall(json["toolCall"]);
      }
    } catch (e) {
      _log("Error parsing message: $e");
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final calls = toolCall["functionCalls"] as List;
    final List<Map<String, dynamic>> responses = [];

    for (var call in calls) {
      final id = call["id"];
      final name = call["name"];
      final args = call["args"];
      _log("Assistant called tool: $name");

      if (name == 'prepare_ride_summary') {
        final originAddr = args['origin_address'] as String;
        final destAddr = args['destination_address'] as String;
        
        setState(() {
          _pendingRide = RideModel(
            creatorId: context.read<AuthService>().user?.uid ?? '',
            type: args['type'] as String,
            origin: const GeoPoint(0, 0),
            originAddress: originAddr,
            destination: const GeoPoint(0, 0),
            destinationAddress: destAddr,
            departureTime: DateTime.parse(args['departure_time'] as String),
            negotiatedPrice: (args['negotiated_price'] as num).toDouble(),
            seatsAvailable: (args['seats_available'] as num).toInt(),
          );
          _isGeocodingRoute = true;
        });
        
        _geocodeRoute(originAddr, destAddr);
        responses.add({"id": id, "response": {"status": "summary_shown"}});
      } else if (name == 'find_matching_rides') {
        final type = args['type'] as String;
        final auth = context.read<AuthService>();
        setState(() => _isSearchingRides = true);
        
        final results = await context.read<FirestoreService>().searchRides(
          type: type, 
          excludeUserId: auth.user?.uid
        );
        
        setState(() {
          _matchingRides = results;
          _isSearchingRides = false;
        });
        responses.add({"id": id, "response": {"count": results.length, "status": "results_shown_in_ui"}});
      } else if (name == 'get_location_suggestions') {
        final address = args['address'] as String;
        final suggestions = await context.read<MapService>().getAddressSuggestions(address);
        responses.add({"id": id, "response": {"suggestions": suggestions, "count": suggestions.length}});
      }
    }

    if (responses.isNotEmpty) {
      _sendEvent({
        "toolResponse": {
          "functionResponses": responses
        }
      });
    }
  }

  void _startListening() {
    _audioHandler.startRecording((chunk) {
      if (_isMuted || !_isConnected) return;
      
      final rmsLevel = _audioHandler.calculateRMS(chunk);
      setState(() => _userAudioLevel = rmsLevel);
      
      _sendEvent({
        "realtimeInput": {
          "audio": {
            "data": base64Encode(chunk),
            "mimeType": "audio/pcm;rate=16000"
          }
        }
      });
    });
    
    _log("Voice AI is listening...");
  }

  void _handleAssistantAudio(String base64Data) {
    final bytes = base64Decode(base64Data);
    _audioHandler.feedAudio(bytes);
    
    final rms = _audioHandler.calculateRMS(bytes);
    
    _assistantTimer?.cancel();
    
    setState(() {
      _assistantAudioLevel = rms;
      _isAssistantSpeaking = true;
    });
    
    _assistantTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isAssistantSpeaking = false;
          _assistantAudioLevel = 0.0;
        });
      }
    });
  }

  Future<void> _geocodeRoute(String originAddr, String destAddr) async {
    final mapService = context.read<MapService>();
    final origin = await mapService.geocodeAddress(originAddr);
    final destination = await mapService.geocodeAddress(destAddr);
    
    if (mounted) {
      setState(() {
        _originCoords = origin;
        _destinationCoords = destination;
        _isGeocodingRoute = false;
        if (origin != null && destination != null && _pendingRide != null) {
          _pendingRide = RideModel(
            creatorId: _pendingRide!.creatorId,
            type: _pendingRide!.type,
            origin: GeoPoint(origin.latitude, origin.longitude),
            originAddress: _pendingRide!.originAddress,
            destination: GeoPoint(destination.latitude, destination.longitude),
            destinationAddress: _pendingRide!.destinationAddress,
            departureTime: _pendingRide!.departureTime,
            negotiatedPrice: _pendingRide!.negotiatedPrice,
            seatsAvailable: _pendingRide!.seatsAvailable,
          );
        }
      });
    }
  }

  void _sendEvent(Map<String, dynamic> event) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(event));
    }
  }

  void _log(String msg) {
    debugPrint("[GeminiCoRide] $msg");
    setState(() {
      _logs.insert(0, "[${DateTime.now().toString().substring(11, 19)}] $msg");
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    _audioHandler.dispose();
    _assistantTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                const Spacer(),
                _buildVisualizer(),
                const Spacer(),
                _buildLogsPanel(),
                _buildControls(),
              ],
            ),
          ),
          
          // CoRide Overlays
          if (_pendingRide != null) _buildConfirmationOverlay(),
          if (_matchingRides.isNotEmpty || _isSearchingRides) _buildMatchingRidesOverlay(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF001524), Color(0xFF15616D), Color(0xFF001524)],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            "CoRide AI Voice Assistant",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildVisualizer() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Audio Reactive Outer Glow
              Container(
                width: 200 + (_assistantAudioLevel * 80),
                height: 200 + (_assistantAudioLevel * 80),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF15616D).withOpacity(0.3 + (_assistantAudioLevel * 0.4)),
                      blurRadius: 40 + (_assistantAudioLevel * 40),
                      spreadRadius: 5 + (_assistantAudioLevel * 20),
                    ),
                  ],
                ),
              ),
              // Audio Reactive Inner Glow (User)
              Container(
                width: 160 + (_userAudioLevel * 60),
                height: 160 + (_userAudioLevel * 60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.3 + (_userAudioLevel * 0.4)),
                      blurRadius: 30 + (_userAudioLevel * 30),
                      spreadRadius: 5 + (_userAudioLevel * 15),
                    ),
                  ],
                ),
              ),
              // Static Glass Circle
              Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                  border: Border.all(color: Colors.white12),
                ),
              ),
              // Bot Avatar
              ClipOval(
                child: Image.asset(
                  'assets/images/bot-ai.png',
                  height: 110,
                  width: 110,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
          const SizedBox(height: 50),
          SizedBox(
            height: 120,
            child: Center(
              child: _VoiceBars(
                level: max(_userAudioLevel, _assistantAudioLevel),
                color: _isAssistantSpeaking ? const Color(0xFF15616D) : Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsPanel() {
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
      child: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (context, i) => Text(
          _logs[i],
          style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.red : Colors.white70, size: 32),
            onPressed: () => setState(() => _isMuted = !_isMuted),
          ),
          FloatingActionButton.large(
            backgroundColor: Colors.redAccent,
            onPressed: () => Navigator.pop(context),
            child: const Icon(Icons.call_end, size: 36),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70, size: 32),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // --- UI Overlays Ported from GeminiChatScreen ---

  Widget _buildConfirmationOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, spreadRadius: 5),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF15616D), Color(0xFF001524)]),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(35), topRight: Radius.circular(35)),
                      ),
                      child: const Column(
                        children: [
                           Icon(Icons.verified, color: Colors.white, size: 40),
                           SizedBox(height: 8),
                           Text('CONFIRM RIDE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 6)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          _detailRow(Icons.my_location, 'FROM', _pendingRide!.originAddress),
                          _detailRow(Icons.location_on, 'TO', _pendingRide!.destinationAddress),
                          const Divider(height: 32, thickness: 1),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                               _infoTile(Icons.access_time_filled_rounded, 'TIME', _pendingRide!.departureTime.toString().split(' ')[1].substring(0, 5)),
                               _infoTile(Icons.monetization_on_rounded, 'PRICE', '\$${_pendingRide!.negotiatedPrice.toStringAsFixed(0)}'),
                               _infoTile(Icons.airline_seat_recline_extra_rounded, 'SEATS', '${_pendingRide!.seatsAvailable}'),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (_isGeocodingRoute)
                            const CircularProgressIndicator()
                          else if (_originCoords != null && _destinationCoords != null)
                             GestureDetector(
                               onTap: () => _showFullScreenMap(_originCoords!, _destinationCoords!),
                               child: Stack(
                                 children: [
                                   SizedBox(height: 180, child: _buildMapPreview()),
                                   Positioned(
                                     right: 12, bottom: 12,
                                     child: Container(
                                       padding: const EdgeInsets.all(8),
                                       decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                                       child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                                  onPressed: () {
                                    setState(() => _pendingRide = null);
                                    _sendEvent({
                                      "realtimeInput": {
                                        "content": {
                                          "parts": [{"text": "I have cancelled the ride summary. Please acknowledge briefly."}],
                                          "role": "user"
                                        }
                                      }
                                    });
                                  },
                                  child: const Text('CANCEL', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF15616D), foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                    elevation: 8,
                                  ),
                                  onPressed: _confirmRide,
                                  child: const Text('CONFIRM', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
     return Column(
       children: [
         Icon(icon, color: const Color(0xFF15616D), size: 24),
         const SizedBox(height: 8),
         Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
         Text(value, style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
       ],
     );
  }

  Widget _buildMapPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng((_originCoords!.latitude + _destinationCoords!.latitude) / 2, (_originCoords!.longitude + _destinationCoords!.longitude) / 2),
          zoom: 12,
        ),
        markers: {
          Marker(markerId: const MarkerId('o'), position: _originCoords!),
          Marker(markerId: const MarkerId('d'), position: _destinationCoords!),
        },
        polylines: {
          Polyline(polylineId: const PolylineId('route'), points: [_originCoords!, _destinationCoords!], color: Colors.blue, width: 4),
        },
        zoomControlsEnabled: false,
      ),
    );
  }

  Widget _buildMatchingRidesOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withOpacity(0.3),
          alignment: Alignment.bottomCenter,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.65,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5)],
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('RIDE RESULTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w200, letterSpacing: 4)),
                          Text('${_matchingRides.length} Active Options Found', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 20),
                        ),
                        onPressed: () => setState(() => _matchingRides = []),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _isSearchingRides 
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        itemCount: _matchingRides.length,
                        itemBuilder: (context, index) {
                          final ride = _matchingRides[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50], borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: const Color(0xFF15616D).withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                                child: const Icon(Icons.drive_eta_rounded, color: Color(0xFF15616D)),
                              ),
                              title: Text("${ride.originAddress.split(',')[0]} ➜ ${ride.destinationAddress.split(',')[0]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Price: \$${ride.negotiatedPrice.toStringAsFixed(0)} • ${ride.seatsAvailable} Seats", style: const TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                              onTap: () => _showRideDetailDialog(ride),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _showRideDetailDialog(RideModel ride) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "RideDetails",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: anim1,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 40, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF15616D), Color(0xFF001524)]),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(35), topRight: Radius.circular(35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('RIDE DETAILS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w200, letterSpacing: 4)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             FutureBuilder<UserModel?>(
                              future: _userCache.containsKey(ride.creatorId) 
                                ? Future.value(_userCache[ride.creatorId]) 
                                : context.read<FirestoreService>().getUser(ride.creatorId),
                              builder: (context, snapshot) {
                                final user = snapshot.data;
                                if (user != null && !_userCache.containsKey(ride.creatorId)) {
                                   _userCache[ride.creatorId] = user;
                                }
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: Colors.white,
                                        child: const Icon(Icons.person, color: Color(0xFF15616D), size: 30),
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(user?.name ?? 'Loading...', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                            Row(
                                              children: [
                                                const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                                                Text(' ${user?.rating.toStringAsFixed(1) ?? "0.0"} • ${user?.phoneNumber ?? "N/A"}', style: const TextStyle(color: Colors.black54)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            ),
                            const SizedBox(height: 24),
                            _detailRow(Icons.my_location, 'FROM', ride.originAddress),
                            _detailRow(Icons.location_on, 'TO', ride.destinationAddress),
                            const Divider(height: 48),
                            _detailRow(Icons.access_time_filled_rounded, 'DEPARTURE', ride.departureTime.toString().split('.')[0]),
                            _detailRow(Icons.monetization_on_rounded, 'PRICE', '\$${ride.negotiatedPrice.toStringAsFixed(2)}'),
                            _detailRow(Icons.airline_seat_recline_extra_rounded, 'SEATS', '${ride.seatsAvailable} available'),
                            const SizedBox(height: 24),
                            
                            // Interactive Map
                            GestureDetector(
                              onTap: () => _showFullScreenMap(LatLng(ride.origin.latitude, ride.origin.longitude), LatLng(ride.destination.latitude, ride.destination.longitude)),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(25),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 200,
                                      child: GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: LatLng(ride.origin.latitude, ride.origin.longitude),
                                          zoom: 12,
                                        ),
                                        markers: {
                                          Marker(markerId: const MarkerId('o'), position: LatLng(ride.origin.latitude, ride.origin.longitude)),
                                          Marker(markerId: const MarkerId('d'), position: LatLng(ride.destination.latitude, ride.destination.longitude)),
                                        },
                                        zoomControlsEnabled: false,
                                      ),
                                    ),
                                    Positioned(
                                      top: 15, right: 15,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                                        child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final user = _userCache[ride.creatorId];
                                      if (user != null) {
                                        final Uri url = Uri.parse('tel:${user.phoneNumber}');
                                        launchUrl(url);
                                      }
                                    },
                                    icon: const Icon(Icons.phone),
                                    label: const Text('CALL'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                      side: const BorderSide(color: Colors.green),
                                      foregroundColor: Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final user = _userCache[ride.creatorId];
                                      if (user != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => PeersChatScreen(otherUser: user, ride: ride)),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: const Text('CHAT'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF15616D),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final auth = context.read<AuthService>();
                                  if (auth.isAuthenticated) {
                                    await context.read<FirestoreService>().createNotification(NotificationModel(
                                      receiverId: ride.creatorId,
                                      senderId: auth.user!.uid,
                                      title: "Interest in your ride",
                                      body: "${auth.user?.displayName} is interested in your ride to ${ride.destinationAddress.split(',')[0]}",
                                      type: 'interest',
                                      referenceId: ride.id,
                                      timestamp: now,
                                    ));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Interest sent!")));
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                                child: const Text('I\'M INTERESTED', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFullScreenMap(LatLng origin, LatLng destination) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "FullscreenMap",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('LOCATION DETAILS', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 4)),
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng((origin.latitude + destination.latitude) / 2, (origin.longitude + destination.longitude) / 2),
                zoom: 14,
              ),
              markers: {
                Marker(markerId: const MarkerId('origin'), position: origin, infoWindow: const InfoWindow(title: 'Origin')),
                Marker(markerId: const MarkerId('dest'), position: destination, infoWindow: const InfoWindow(title: 'Destination')),
              },
              polylines: {
                Polyline(
                  polylineId: const PolylineId('full_route'),
                  points: [origin, destination],
                  color: Colors.blueAccent,
                  width: 6,
                ),
              },
              myLocationEnabled: true,
              zoomControlsEnabled: true,
            ),
            Positioned(
              bottom: 40, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.blueAccent),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Inspect the route and destination details before confirming.', style: TextStyle(fontSize: 12, color: Colors.black54))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRide() async {
    if (_pendingRide == null) return;
    try {
      await context.read<FirestoreService>().createRide(_pendingRide!);
      setState(() => _pendingRide = null);
      _sendEvent({
        "realtimeInput": {
          "content": {
            "parts": [{"text": "I have successfully confirmed and booked the ride. Please give me a brief verbal confirmation."}],
            "role": "user"
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride confirmed!'), backgroundColor: Colors.green));
      _log("Confirmed ride successfully via voice tool.");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

class _VoiceBars extends StatelessWidget {
  final double level;
  final Color color;

  const _VoiceBars({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(20, (index) {
        // Create a more dynamic look by adding some "noise" to each bar
        final randomOffset = (index % 5) * 0.15;
        final barHeight = 8 + (level * 100 * (0.3 + randomOffset));
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 3.5,
          height: barHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withOpacity(0.9),
                color.withOpacity(0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              if (level > 0.1)
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
            ],
          ),
        );
      }),
    );
  }
}

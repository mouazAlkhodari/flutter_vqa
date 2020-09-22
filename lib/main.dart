// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:convert' as convert;
import 'package:http/http.dart' as http;
import 'dart:io';

import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

// const base_url = 'http://192.168.1.8:5000';
const base_url = 'http://192.168.43.28:5000';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VQA Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: PickingImageScreen(title: 'Pick an Image'),
    );
  }
}

/* picking image */

class PickingImageScreen extends StatefulWidget {
  PickingImageScreen({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _PickingImageScreenState createState() => _PickingImageScreenState();
}

class _PickingImageScreenState extends State<PickingImageScreen> {
  PickedFile _imageFile;
  dynamic _pickImageError;
  String _retrieveDataError;

  final ImagePicker _picker = ImagePicker();

  void _onImageButtonPressed(ImageSource source, {dynamic context}) async {
    double maxWidth, maxHeight;
    int quality;

    try {
      final pickedFile = await _picker.getImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: quality,
      );

      setState(() => _imageFile = pickedFile);
    } catch (e) {
      setState(() => _pickImageError = e);
    }
  }

  Widget _previewImage() {
    final Text retrieveError = _getRetrieveErrorWidget();
    if (retrieveError != null) {
      return retrieveError;
    }

    if (_imageFile != null) {
      if (kIsWeb) {
        return Image.network(_imageFile.path);
      } else {
        return Image.file(File(_imageFile.path));
      }
    } else if (_pickImageError != null) {
      return Text(
        'Pick image error: $_pickImageError',
        textAlign: TextAlign.center,
      );
    } else {
      return const Text(
        'Press the button and and pick an image.',
        textAlign: TextAlign.center,
      );
    }
  }

  Future<void> retrieveLostData() async {
    final LostData response = await _picker.getLostData();
    if (response.isEmpty) {
      return;
    }
    if (response.file != null) {
      if (response.type == RetrieveType.image)
        setState(() => _imageFile = response.file);
    } else {
      _retrieveDataError = response.exception.code;
    }
  }

  List<Widget> _getFloatingActionsButtons(BuildContext context) {
    final pickButtons = <Widget>[
      FloatingActionButton(
        onPressed: () =>
            _onImageButtonPressed(ImageSource.gallery, context: context),
        heroTag: 'image0',
        tooltip: 'Pick Image from gallery',
        child: const Icon(Icons.photo_library),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: FloatingActionButton(
          onPressed: () =>
              _onImageButtonPressed(ImageSource.camera, context: context),
          heroTag: 'image1',
          tooltip: 'Take a Photo',
          child: const Icon(Icons.camera_alt),
        ),
      ),
    ];

    final nextButtons = <Widget>[
      FloatingActionButton(
        onPressed: () => setState(() => _imageFile = null),
        heroTag: 'image0',
        tooltip: 'remove the image',
        child: const Icon(Icons.delete),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: FloatingActionButton(
          onPressed: () async {
            final bytes = await _imageFile.readAsBytes();
            String img64 = convert.base64Encode(bytes);
            print({'img64': img64});
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SpeechScreen(
                  img64: img64,
                  title: 'Ask your question',
                  imgPath: _imageFile.path,
                ),
              ),
            );
            // arguments: {img64: img64});
          },
          heroTag: 'image1',
          tooltip: 'go to question',
          child: const Icon(Icons.arrow_forward),
        ),
      ),
    ];

    print(_imageFile == null);
    return _imageFile == null ? pickButtons : nextButtons;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? FutureBuilder<void>(
                future: retrieveLostData(),
                builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.waiting:
                      return const Text(
                        'Press the button and and pick an image.',
                        textAlign: TextAlign.center,
                      );
                    case ConnectionState.done:
                      return _previewImage();
                    default:
                      if (snapshot.hasError) {
                        return Text(
                          'Pick image error: ${snapshot.error}}',
                          textAlign: TextAlign.center,
                        );
                      } else {
                        return const Text(
                          'Press the button and and pick an image.',
                          textAlign: TextAlign.center,
                        );
                      }
                  }
                },
              )
            : _previewImage(),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _getFloatingActionsButtons(context),
      ),
    );
  }

  Text _getRetrieveErrorWidget() {
    if (_retrieveDataError != null) {
      final Text result = Text(_retrieveDataError);
      _retrieveDataError = null;
      return result;
    }
    return null;
  }
}

/* speach recognition */

class SpeechScreen extends StatefulWidget {
  SpeechScreen({Key key, this.title, this.img64, this.imgPath})
      : super(key: key);

  final String title;
  final String img64;
  final String imgPath;
  @override
  _SpeechScreenState createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> {
  bool startedSpeaking = false;
  bool _hasSpeech = false;
  String lastWords = "Press the button and start speaking";
  String lastError = "";
  String lastStatus = "";
  String _currentLocaleId = "en_US";
  String _currentLanguage = "en-US";
  double _confidence = 1.0;
  final SpeechToText speech = SpeechToText();

  final _contollrer = TextEditingController(text: '');
  final baseUrl_contollrer = TextEditingController(text: base_url);

  String answer = "";

  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    initSpeechToTextState();
    initTextToSpeechState();
  }

  Future<void> initSpeechToTextState() async {
    bool hasSpeech = await speech.initialize(
        onError: errorListener, onStatus: statusListener);
    var locals = await speech.locales();
    print({
      'locals': locals.map((e) => e.localeId).reduce((value, element) =>
          element.contains('en') ? element + ',' + value : value)
    });
    var selectedLocalId =
        await speech.systemLocale().then((value) => value.localeId);

    if (!mounted) return;

    setState(() {
      _hasSpeech = hasSpeech;
      _currentLocaleId = selectedLocalId;
    });
  }

  Future<void> initTextToSpeechState() async {
    var languages = await flutterTts.getLanguages;
    print({languages});
  }

  List<Widget> _getFloatingActionButtons() {
    final result = [
      AvatarGlow(
        animate: speech.isListening,
        glowColor: Theme.of(context).primaryColor,
        endRadius: 50.0,
        duration: const Duration(milliseconds: 2000),
        repeatPauseDuration: const Duration(milliseconds: 100),
        repeat: true,
        child: FloatingActionButton(
          onPressed: startListening,
          child: Icon(
              _hasSpeech && speech.isListening ? Icons.mic : Icons.mic_none),
        ),
      ),
    ];
    if (startedSpeaking)
      result.add(
        AvatarGlow(
          animate: false,
          glowColor: Theme.of(context).primaryColor,
          endRadius: 50.0,
          duration: const Duration(milliseconds: 2000),
          repeatPauseDuration: const Duration(milliseconds: 100),
          repeat: true,
          child: FloatingActionButton(
            onPressed: getAnswer,
            child: Icon(Icons.arrow_forward),
          ),
        ),
      );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title + ' ,${(_confidence * 100.0).toStringAsFixed(1)}%',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.mode_edit),
            onPressed: () => setState(() {
              startedSpeaking = true;
            }),
          )
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _getFloatingActionButtons(),
      ),
      body: SingleChildScrollView(
        reverse: true,
        child: Container(
            padding: const EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 140.0),
            child: Column(
              children: [
                ((kIsWeb)
                    ? Image.network(widget.imgPath)
                    : Image.file(File(widget.imgPath))),
                (!startedSpeaking || lastError != ""
                    ? Text(
                        lastError != "" ? lastError : lastWords,
                        style: const TextStyle(
                          fontSize: 32.0,
                          color: Colors.black,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    : TextField(
                        //autofocus: true,
                        controller: _contollrer,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 28.0,
                          color: Colors.black,
                          fontWeight: FontWeight.w400,
                        ),
                      )),
                Text(
                  answer == '' ? '' : 'answer: $answer',
                  style: const TextStyle(
                    fontSize: 28.0,
                    color: Colors.black,
                    fontWeight: FontWeight.w400,
                  ),
                )
              ],
            )),
      ),
    );
  }

  void resultListener(SpeechRecognitionResult result) {
    setState(() {
      startedSpeaking = true;
      setValue(result.recognizedWords);
      print(lastWords);
      if (result.hasConfidenceRating && result.confidence > 0) {
        _confidence = result.confidence;
      }
    });
  }

  void errorListener(SpeechRecognitionError error) {
    print("Received error status: $error, listening: ${speech.isListening}");
    setState(() {
      lastError = "${error.errorMsg} - ${error.permanent}";
    });
  }

  Future<void> statusListener(String status) async {
    print(
        "Received listener status: $status, listening: ${speech.isListening}");
    if (speech.isListening == false) await getAnswer();
    setState(() {
      lastStatus = "$status";
    });
  }

  void startListening() {
    if (speech.isListening) stopListening();
    _stop();
    speech.listen(
        onResult: resultListener,
        pauseFor: Duration(seconds: 6),
        cancelOnError: true,
        partialResults: true,
        onDevice: true,
        listenMode: ListenMode.confirmation);
    setState(() {});
  }

  void stopListening() {
    speech.stop();
  }

  void setValue(String value) {
    lastError = "";
    setState(() {
      lastWords = value;
      _contollrer.value = TextEditingValue(text: value);
    });
  }

  Future<void> getAnswer() async {
    _stop();
    if (lastWords == "" || !startedSpeaking) return;
    print('get answer');
    var question = _contollrer.text + " ?";
    print(question);
    // send http request to get the answer
    var response = await http.post(
      '$base_url/vqa',
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: convert.jsonEncode({
        'question': question,
        'img_base64': widget.img64,
      }),
    );

    // update the state accourding to the results
    setState(() {
      if (response.statusCode == 200) {
        var responseJson = convert.jsonDecode(response.body);
        answer = responseJson['answer'] as String;
        print(responseJson);
        _speak('answer is: $answer');
      } else {
        answer = "can't recognized the question... Try again";
      }
    });
  }

  Future _speak(word) async {
    print("started speaking: $word");
    await flutterTts.speak("$word");
  }

  Future _stop() async {
    print("stop speaking");
    await flutterTts.stop();
  }
}

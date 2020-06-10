import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  CameraController controller;
  String imagePath;
  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();
  Isolate _isolate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initAsync();
  }

  void initAsync() async {
    List<CameraDescription> cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.high);
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize.
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (controller != null) {
        onNewCameraSelected(controller.description);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: <Widget>[
            Center(
              child: controller == null
                  ? Container()
                  : Container(
                      height: double.infinity,
                      child: CameraPreview(controller),
                    ),
            ),
            Align(
              alignment: Alignment(0, 0.9),
              child: SizedBox(
                height: 90,
                width: 90,
                child: CupertinoButton(
                  child: Icon(Icons.ac_unit),
                  onPressed: () async {
                    setState(() {});
                    onTakePictureButtonPressed();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void onTakePictureButtonPressed() async {
    takePicture().then((String filePath) async {
      if (mounted) {
        setState(() {
          imagePath = filePath;
        });
        if (filePath == null) return;

        start();
      }
    });
  }

  void start() async {
    ReceivePort _mainPort = ReceivePort();
    _isolate = await Isolate.spawn(entryPoint, _mainPort.sendPort);
    SendPort _sendPort = await _mainPort.first;

    ReceivePort _secondaryPort = ReceivePort();
    _sendPort.send([imagePath, _secondaryPort.sendPort]);

    bool msg = await _secondaryPort.first;

    _mainPort.close();
    _secondaryPort.close();
    _isolate.kill(priority: Isolate.immediate);
    _isolate = null;

    if (mounted) {
      if (msg) {
        setState(() {});
      } else {
        setState(() {});
      }
    }
  }

  static void entryPoint(SendPort sendPort) async {
    var port = new ReceivePort();

    sendPort.send(port.sendPort);

    await for (var msg in port) {
      bool checkedImage = await HandRecognitionService.recogniseHand(msg[0]);

      SendPort replyToPort = msg[1];

      replyToPort.send(checkedImage);
    }
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      print('Error: select a camera first.');
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures';

    if (await Directory(dirPath).exists())
      await Directory(dirPath).delete(recursive: true);

    await Directory(dirPath).create(recursive: true);

    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    print('Error: ${e.code}\n${e.description}');
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }

    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        print('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }
}

class HandRecognitionService {
  static Future<bool> recogniseHand(String path) async {
    if (path == null) throw Exception;
    var decodedImage = decodeJpg(File(path).readAsBytesSync());
    decodedImage = copyResize(decodedImage, width: 512);

    bool booling = await checkThingOnPhoto(path);

    return booling;
  }

  static Future<bool> checkThingOnPhoto(String path) async {
    final FirebaseVisionImage visionImage =
        FirebaseVisionImage.fromFilePath(path);
    final ImageLabeler labeler = FirebaseVision.instance.imageLabeler();
    final List<ImageLabel> labels = await labeler.processImage(visionImage);
    labeler.close();

    ImageLabel foundLabel;
    try {
      foundLabel = labels.firstWhere((label) {
        return label.text == 'Hand';
      });
      print('Label: ' + foundLabel.text);
    } catch (_) {
      foundLabel = null;
    }

    return foundLabel != null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity/connectivity.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:multilogin2/provider/analytics_service.dart';
import 'package:multilogin2/screens/home_screen.dart';
import 'package:multilogin2/screens/your_issues_screen.dart';
import 'package:multilogin2/utils/issue.dart';
import 'package:multilogin2/utils/next_screen.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import '../utils/image_uploader.dart';

/// `SubmitIssueScreen` is a class that displays the issue submission form.
///
/// It uses `FirebaseAuth` to get the current user, `FirebaseFirestore` to submit the issue,
/// `ImagePicker` to select an image from the gallery, and `Connectivity` to check the internet connection.
/// It also provides several methods to handle form submissions, image selection, and internet connection checking.
///
/// Methods:
/// - `initState()`: Initializes the state of the widget.
/// - `dispose()`: Disposes the controllers when the widget is removed from the widget tree.
/// - `checkInternetConnection()`: Checks the internet connection and updates the `hasInternetConnection` state.
/// - `pickImageFromGallery()`: Opens the image picker and sets the selected image as the issue image.
/// - `_storeLocally(Issue issue)`: Stores the issue locally if there is no internet connection.
/// - `_submitIssue()`: Validates the form and submits the issue.
/// - `submitIssueToFirestore(Issue issue)`: Submits the issue to Firestore.
/// - `build(BuildContext context)`: Builds the widget tree for this screen.

class SubmitIssueScreen extends StatefulWidget {
  const SubmitIssueScreen({Key? key}) : super(key: key);

  @override
  _SubmitIssueScreenState createState() => _SubmitIssueScreenState();
}

class _SubmitIssueScreenState extends State<SubmitIssueScreen> {
  late TextEditingController _titleController = TextEditingController();
  late TextEditingController _descriptionController = TextEditingController();
  late TextEditingController _tagController = TextEditingController();
  late String _selectedTag;
  final List<String> _tagOptions = ['Work', 'Leisure', 'Health', 'Finance', 'Event', 'Other'];
  final RoundedLoadingButtonController submitController = RoundedLoadingButtonController();
  File? _imageFile;
  ImageUploader uploader = ImageUploader();
  bool hasInternetConnection = true;
  final AnalyticsService _analyticsService = AnalyticsService();


  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _tagController = TextEditingController();
    _selectedTag = _tagOptions.first;
    checkInternetConnection();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  /// Checks the internet connection and updates the `hasInternetConnection` state.
  /// This method uses the `Connectivity` plugin to check the internet connection.
  Future<void> checkInternetConnection() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      hasInternetConnection = connectivityResult != ConnectivityResult.none;
    });
  }

  /// Opens the image picker and sets the selected image as the issue image.
  /// This method uses the `ImagePicker` plugin to open the image picker.
  /// The selected image is stored in the `_imageFile` state.
  Future<void> pickImageFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  /// Stores the issue locally if there is no internet connection.
  /// This method uses the `SharedPreferences` plugin to store the issue locally.
  Future<void> _storeLocally(Issue issue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> jsonIssue = issue.toJson();
    if (_imageFile != null) {
      jsonIssue['imagePath'] = _imageFile!.path;
    }
    if (issue.createdAt != null) {
      jsonIssue['createdAt'] = issue.createdAt!.millisecondsSinceEpoch;
    }
    List<String> localIssues = prefs.getStringList('local_issues') ?? [];
    localIssues.add(jsonEncode(jsonIssue));
    await prefs.setStringList('local_issues', localIssues);
  }

  /// Validates the form and submits the issue to Firestore.
  void _submitIssue() async {
    String title = _titleController.text.trim();
    String description = _descriptionController.text.trim();
    String tag = _selectedTag.trim();

    if (title.isNotEmpty && description.isNotEmpty && tag.isNotEmpty) {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        Issue issue = Issue(
          title: title,
          description: description,
          createdAt: Timestamp.now(),
          tag: tag,
          uid: user.uid,
        );

        var connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult != ConnectivityResult.none) {
          submitController.start();
          if (_imageFile != null) {
            issue.image = await uploader.uploadImageToStorage(_imageFile!.path);
          }
          try {
            await submitIssueToFirestore(issue);
            if (issue.image != null) {
              _analyticsService.logCustomEvent(eventName: 'issue_with_image', parameters: null);
            }
            _analyticsService.logCustomEvent(eventName: 'issue_submit_w_connection', parameters: {'tag': tag});
            submitController.success();
          } catch (e) {
            print('Error submitting issue: $e');
            submitController.error();
          }
        } else {
          await _storeLocally(issue);
          _analyticsService.logCustomEvent(eventName: 'issue_stored_locally', parameters: {'tag': tag});
          submitController.error();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => LocalIssuesScreen(initialTabIndex: 0)),
          );
        }
      } else {
        print('User not logged in');
        submitController.error();
      }
    } else {
      submitController.error();
    }
  }

  /// Submits the issue to Firestore.
  Future<void> submitIssueToFirestore(Issue issue) async {
    try {
      await FirebaseFirestore.instance.collection('issues').add(issue.toJson());
      print('Issue submitted successfully');
      await Future.delayed(Duration(milliseconds: 500));
      nextScreenReplace(context, LocalIssuesScreen(initialTabIndex: 1));
    } catch (e) {
      print('Error submitting issue: $e');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Could not submit issue!'),
          content: Text('An unexpected error occured. Please try again later!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Builds the widget tree for this screen.
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
        return false; // Prevent the default back button behavior
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0.0, 0.40),
                colors: [Colors.black, Colors.white],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 80),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image(
                          image: AssetImage(Config.loba_icon_white),
                          height: 80,
                          width: 80,
                          fit: BoxFit.cover,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "Submit New Issue",
                          style: GoogleFonts.exo2(fontSize: 25, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          "What's going on?",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 30),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(30),
                            topRight: Radius.circular(30),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _titleController,
                                      decoration: InputDecoration(
                                        hintText: 'Issue Title',
                                        hintStyle: TextStyle(color: Colors.grey),
                                        filled: true,
                                        fillColor: Colors.grey[200],
                                        contentPadding: EdgeInsets.all(15),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: Colors.transparent),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: Colors.transparent),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  DropdownButton<String>(
                                    value: _selectedTag,
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedTag = value!;
                                      });
                                    },
                                    items: _tagOptions.map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(
                                          value,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.black,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    icon: Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.black,
                                      size: 30,
                                    ),
                                    elevation: 8,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                    underline: Container(
                                      height: 2,
                                      color: Colors.black,
                                    ),
                                    isExpanded: false,
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              Stack(
                                children: [
                                  TextFormField(
                                    controller: _descriptionController,
                                    decoration: InputDecoration(
                                      hintText: 'Description',
                                      hintStyle: TextStyle(color: Colors.grey),
                                      filled: true,
                                      fillColor: Colors.grey[200],
                                      contentPadding: EdgeInsets.all(15),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: Colors.transparent),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: Colors.transparent),
                                      ),
                                    ),
                                    maxLines: 8,
                                  ),
                                  Positioned(
                                    left: 5,
                                    bottom: 5,
                                    child: IconButton(
                                      icon: Icon(Icons.image),
                                      onPressed: () {
                                        pickImageFromGallery();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 30),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(builder: (context) => HomeScreen()),
                                      );
                                    },
                                    icon: Icon(Icons.arrow_back),
                                    color: Colors.black,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 16.0), // Adjust left padding as needed
                                      child: RoundedLoadingButton(
                                        controller: submitController,
                                        successColor: Colors.green,
                                        errorColor: Colors.red,
                                        onPressed: () async {
                                          submitController.start();
                                          await Future.delayed(Duration(milliseconds: 500));
                                          _submitIssue();
                                        },
                                        width: double.infinity, // Occupy all available width
                                        elevation: 0,
                                        borderRadius: 10,
                                        color: Colors.black,
                                        child: Wrap(
                                          children: const [
                                            Icon(
                                              Icons.subdirectory_arrow_right_outlined,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              "Submit Issue",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity/connectivity.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:multilogin2/provider/analytics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_uploader.dart';

class Issue {
  final String title;
  final String description;
  final String tag;
  String? image;
  String? imagePath; //for local issues
  final Timestamp? createdAt;
  final String uid;

  Issue({
    required this.title,
    required this.description,
    required this.tag,
    this.image,
    this.imagePath,
    this.createdAt,
    required this.uid
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'title': title,
      'description': description,
      'tag': tag,
      'uid': uid,
    };
    if (image != null) {
      json['image'] = image;
    }
    if (createdAt != null) {
      json['createdAt'] = createdAt;
    }
    return json;
  }

  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      title: json['title'],
      description: json['description'],
      tag: json['tag'],
      image: json['image'],
      createdAt: json['createdAt'] != null ? Timestamp.fromMillisecondsSinceEpoch(json['createdAt']) : null,
      uid: json['uid'],
    );
  }

  static Future<void> submitLocalIssues() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? localIssuesJson = prefs.getStringList('local_issues');
    ImageUploader uploader = ImageUploader();
    final AnalyticsService _analyticsService = AnalyticsService();

    if (localIssuesJson != null) {
      // Create a copy of the list to iterate over
      List<String> localIssuesJsonCopy = List.from(localIssuesJson);

      for (String issueJson in localIssuesJsonCopy) {
        // Deserialize the issue JSON string
        Map<String, dynamic> jsonIssue = jsonDecode(issueJson);
        Issue issue = Issue.fromJson(jsonIssue);

        // Check if the issue has an image path
        String? imagePath = jsonIssue['imagePath'];
        if (imagePath != null && imagePath.isNotEmpty) {
          _analyticsService.logCustomEvent(eventName: 'issue_with_image', parameters: null);
          // Upload the image to Firebase Storage
          String imageUrl = await uploader.uploadImageToStorage(imagePath);
          // Update the issue object with the image URL
          issue.image = imageUrl;
          issue.imagePath = null;
        }

        // Submit the updated issue to Firestore
        await submitIssueToFirebase(issue);
        _analyticsService.logCustomEvent(eventName: 'issue_submit_no_connection', parameters: {'tag': issue.tag});

        // Remove the local issue from SharedPreferences
        localIssuesJson.remove(issueJson);
      }

      // Update SharedPreferences after processing all local issues
      await prefs.setStringList('local_issues', localIssuesJson);
    }
  }




  static Future<void> submitIssueToFirebase(Issue issue) async {
    try {
      await FirebaseFirestore.instance.collection('issues').add(issue.toJson());
      print('Issue submitted successfully here.');
    } catch (e) {
      print('Error submitting issue: $e');
    }
  }

  static Future<bool> hasInternetConnection() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  static void checkInternetConnectivityPeriodically() {
    const duration = Duration(seconds: 3);
    Timer.periodic(duration, (Timer timer) async {
      var isConnected = await hasInternetConnection();
      if (isConnected) {
        timer.cancel();
      }
    });
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity/connectivity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Issue {
  final String title;
  final String description;
  final String tag;
  final String? image;
  final Timestamp? createdAt;
  final String? authorName; // Add author's name field
  final String? authorProfilePicture; // Add author's profile picture field
  final String uid;

  Issue({
    required this.title,
    required this.description,
    required this.tag,
    this.image,
    this.createdAt,
    this.authorName,
    this.authorProfilePicture,
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
    if (authorName != null) {
      json['authorName'] = authorName; // Add author's name field
    }
    if (authorProfilePicture != null) {
      json['authorProfilePicture'] = authorProfilePicture; // Add author's profile picture field
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
      authorName: json['authorName'], // Add author's name field
      authorProfilePicture: json['authorProfilePicture'], // Add author's profile picture field
      uid: json['uid'],
    );
  }

  static Future<void> submitLocalIssues() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? localIssuesJson = prefs.getStringList('local_issues');
    if (localIssuesJson != null) {
      List<Issue> localIssues = localIssuesJson
          .map((json) => Issue.fromJson(jsonDecode(json)))
          .toList();
      for (Issue issue in localIssues) {
        await submitIssueToFirebase(issue);
      }
      await prefs.remove('local_issues');
    }
  }

  static Future<void> submitIssueToFirebase(Issue issue) async {
    try {
      await FirebaseFirestore.instance.collection('issues').add(issue.toJson());
      print('Issue submitted successfully');
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
        await submitLocalIssues();
        timer.cancel();
      }
    });
  }
}

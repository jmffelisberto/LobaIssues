import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity/connectivity.dart'; // Import connectivity package
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:multilogin2/main.dart';
import 'package:multilogin2/provider/analytics_service.dart';
import 'package:multilogin2/provider/issue_service_provider.dart';
import 'package:multilogin2/screens/home_screen.dart';
import 'package:multilogin2/screens/issue_detail_screen.dart';
import 'package:multilogin2/utils/issue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `LocalIssuesScreen` is a class that displays the local and cloud issues of the user.
///
/// It uses `FirebaseAuth` and `FirebaseFirestore` to fetch the issues and `SharedPreferences` to store local issues.
/// It also provides several methods to handle issue fetching, time formatting, and navigation.
///
/// Methods:
/// - `initState()`: Initializes the state of the widget. It loads local issues and fetches cloud issues.
/// - `_selectTab(int index)`: Selects the specified tab in the tab bar.
/// - `_loadLocalIssues()`: Loads local issues from `SharedPreferences`.
/// - `_fetchCloudIssues()`: Fetches cloud issues from Firestore and submits local issues to the cloud.
/// - `_loadCloudIssues()`: Fetches cloud issues from Firestore.
/// - `_buildTagContainer(String tag)`: Builds a container for the specified tag with a specific color based on the tag.
/// - `getTimeElapsed(Timestamp? createdAt)`: Returns a string representing the time elapsed since the issue was created.
/// - `build(BuildContext context)`: Builds the widget tree for this screen.

class LocalIssuesScreen extends StatefulWidget {
  final int initialTabIndex;

  LocalIssuesScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  _LocalIssuesScreenState createState() => _LocalIssuesScreenState();
}

class _LocalIssuesScreenState extends State<LocalIssuesScreen>
    with TickerProviderStateMixin {
  List<Issue> _localIssues = [];
  List<Issue> _cloudIssues = [];
  late ConnectivityService _connectivityService;
  late AnimationController _animationController;
  bool _isSubmittingLocalIssues = false;
  bool _hasConnection = false; // Default to true assuming initial connection
  final AnalyticsService _analyticsService = AnalyticsService();

  @override
  void initState() {
    super.initState();
    _loadLocalIssues();
    _loadCloudIssues();
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      _selectTab(widget.initialTabIndex);
    });

    Issue.checkInternetConnectivityPeriodically();
    // Initialize the connectivity service
    _connectivityService = ConnectivityService(onConnectionRestored: () {
      if (_localIssues.isNotEmpty) {
        _fetchCloudIssues();
      }
      setState(() {
        _hasConnection = true;
      });
    });

    // Initialize the animation controller for the rotating icon
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2), // Adjust the duration as needed
    )..repeat(); // Repeat the animation indefinitely
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Selects the specified tab in the tab bar.
  void _selectTab(int index) {
    DefaultTabController.of(context)?.animateTo(index);
  }

  /// Loads local issues from `SharedPreferences`.
  Future<void> _loadLocalIssues() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? localIssuesJson = prefs.getStringList('local_issues');
    if (localIssuesJson != null) {
      setState(() {
        _localIssues =
            localIssuesJson.map((json) => Issue.fromJson(jsonDecode(json))).toList();
      });
    } else
      _localIssues = [];
  }

  /// Fetches cloud issues from Firestore and submits local issues to the cloud.
  /// It also removes local issues from `SharedPreferences` and reloads local issues to reflect changes.
  /// It also checks connectivity and updates `_hasConnection` accordingly.
  /// It sets `_isSubmittingLocalIssues` to true to trigger the rotating icon and false to stop it.
  void _fetchCloudIssues() async {
    // Set _isSubmittingLocalIssues to true to trigger the rotating icon
    _isSubmittingLocalIssues = true;
    setState(() {});

    // Submit local issues to the cloud
    await Issue.submitLocalIssues();

    // Fetch cloud issues to refresh the UI
    await _loadCloudIssues();

    // Remove local issues from SharedPreferences
    await eliminateLocalInstances();

    // Reload local issues to reflect changes
    await _loadLocalIssues();

    // Check connectivity and update _hasConnection accordingly
    bool hasConnection = await _connectivityService.checkConnectivity();
    setState(() {
      _hasConnection = hasConnection;
    });

    // Set _isSubmittingLocalIssues to false to stop the rotating icon
    _isSubmittingLocalIssues = false;
    setState(() {});
  }

  /// Removes local issues from `SharedPreferences`.
  /// It also updates the local issues list and logs a custom event.
  /// It is called after submitting local issues to the cloud.
  /// It is used to prevent duplicate issues in the cloud.
  Future<void> _loadCloudIssues() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('issues')
          .orderBy('createdAt', descending: true)
          .get();
      List<Issue> cloudIssues = querySnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        //print('Data from Firestore: $data'); // Print the data retrieved from Firestore
        return Issue(
          title: data['title'] ?? '', // Use default value if 'title' is null
          description: data['description'] ?? '', // Use default value if 'description' is null
          tag: data['tag'] ?? '', // Use default value if 'tag' is null
          createdAt: data['createdAt'],
          image: data['image'] ?? '', // Add image field
          uid: data['uid'] ?? '',
        );
      }).toList();

      setState(() {
        _cloudIssues = cloudIssues;
      });
      _analyticsService.logCustomEvent(
        eventName: 'load_cloud_issues',
        parameters: {'count': cloudIssues.length},
      );
    } catch (e) {
      print('Error fetching cloud issues: $e');
    }
  }

  /// Builds a container for the specified tag with a specific color based on the tag.
  Widget _buildTagContainer(String tag) {
    Color color;
    switch (tag) {
      case 'Work':
        color = Colors.orange;
        break;
      case 'Leisure':
        color = Colors.red;
        break;
      case 'Health':
        color = Colors.green;
        break;
      case 'Finance':
        color = Colors.blue;
        break;
      case 'Event':
        color = Colors.brown;
        break;
      default:
        color = Colors.grey; // Default color
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tag,
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  /// Returns a string representing the time elapsed since the issue was created.
  /// It returns 'just now' if the difference is less than 60 seconds.
  /// It returns 'x mins. ago' if the difference is less than 60 minutes.
  /// It returns 'x hours ago' if the difference is less than 24 hours.
  /// It returns 'yesterday' if the difference is 1 day.
  /// Otherwise, it returns 'x days ago'.
  String getTimeElapsed(Timestamp? createdAt) {
    if (createdAt == null) return ''; // Handle null createdAt

    final now = DateTime.now();
    final createdAtDateTime = createdAt.toDate();
    final difference = now.difference(createdAtDateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min${difference.inMinutes == 1 ? '' : 's'}. ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
  }

  /// Builds the widget tree for this screen.
  @override
  Widget build(BuildContext context) {
    var itsCloudIssues = _cloudIssues
        .where((issue) => issue.uid == FirebaseAuth.instance.currentUser?.uid)
        .toList();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
        return false; // Prevent the default back button behavior
      },
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.initialTabIndex,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              "Issues",
              style: GoogleFonts.exo2(),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => HomeScreen()),
                );
              },
            ),
            actions: [
              // Display no connection icon if there's no connection
              if (!_hasConnection)
                IconButton(
                  icon: Icon(Icons.signal_wifi_off),
                  onPressed: () {},
                ),
              // Display rotating icon if there's connection and local issues are being submitted
              if (_isSubmittingLocalIssues)
                RotationTransition(
                  turns: _animationController,
                  child: Icon(Icons.sync),
                ),
            ],
            bottom: TabBar(
              tabs: [
                Tab(text: 'Local Issues'),
                Tab(text: 'Cloud Issues'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              // Local Issues Tab
              _localIssues.isEmpty
                  ? Center(child: Text('No local issues found'))
                  : ListView.builder(
                itemCount: _localIssues.length,
                itemBuilder: (context, index) {
                  final issue = _localIssues[index];
                  return GestureDetector(
                    onTap: () {
                      _analyticsService.logCustomEvent(
                        eventName: 'inspect_issue',
                        parameters: {'issue_title': issue.title},
                      );
                      // Navigate to the issue detail page
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => IssueDetailPage(issue: issue),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 3,
                      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(issue.title),
                                Row(
                                  children: [
                                    Align(
                                      alignment: Alignment.center,
                                      child: _buildTagContainer(issue.tag),
                                    ),
                                  ],
                                ),
                                Text(
                                  getTimeElapsed(issue.createdAt),
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Icon(FontAwesomeIcons.angleRight),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Cloud Issues Tab
              itsCloudIssues.isEmpty
                  ? Center(child: Text('No cloud issues found'))
                  : ListView.builder(
                itemCount: itsCloudIssues.length,
                itemBuilder: (context, index) {
                  final issue = itsCloudIssues[index];
                  return GestureDetector(
                    onTap: () {
                      _analyticsService.logCustomEvent(
                        eventName: 'inspect_issue',
                        parameters: {'issue_title': issue.title},
                      );
                      // Navigate to the issue detail page when tapped
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => IssueDetailPage(issue: issue),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 3,
                      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(issue.title),
                                Row(
                                  children: [
                                    Align(
                                      alignment: Alignment.center,
                                      child: _buildTagContainer(issue.tag),
                                    ),
                                  ],
                                ),
                                Text(
                                  getTimeElapsed(issue.createdAt),
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Icon(FontAwesomeIcons.angleRight),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

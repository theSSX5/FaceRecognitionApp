// lib/photographer_home_screen.dart

import 'dart:convert';
import 'dart:html' as html; // For web-specific storage
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart'; // For advanced HTTP requests
import 'package:file_picker/file_picker.dart'; // For selecting multiple files
import 'login_screen.dart'; // Ensure this path is correct
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import Font Awesome
import 'package:http_parser/http_parser.dart'; // For MediaType

class PhotographerHomeScreen extends StatefulWidget {
  @override
  _PhotographerHomeScreenState createState() => _PhotographerHomeScreenState();
}

class _PhotographerHomeScreenState extends State<PhotographerHomeScreen>
    with SingleTickerProviderStateMixin {
  int totalEvents = 0;
  int activeEvents = 0;
  int futureEvents = 0;
  List<Map<String, dynamic>> registeredEvents = [];
  List<Map<String, dynamic>> displayedEvents = [];
  bool isLoading = true;

  String? token;

  final Dio _dio = Dio();

  // State variables for filter and sort
  String? filterLocation;
  String? sortBy;
  bool isAscending = true;

  // State variables for date interval filter
  DateTime? startDate;
  DateTime? endDate;

  // State variables for search
  bool _isSearchBarVisible = false;
  TextEditingController _searchController = TextEditingController();
  String _searchCriterion = 'name'; // default search criterion

  // Pagination variables
  int _currentPage = 0;
  int _rowsPerPage = 5; // Number of rows per page

  @override
  void initState() {
    super.initState();
    // Schedule _loadToken to run after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadToken();
    });
  }

  Future<void> _loadToken() async {
    // Retrieve the token from localStorage
    token = html.window.localStorage['jwt_token'];
    print('Token retrieved: $token'); // Debug: Check if token is retrieved

    if (token != null && token!.isNotEmpty) {
      await _fetchStatistics();
      await _fetchRegisteredEvents();
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    } else {
      // Navigate to Login Screen if token is missing after build
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      });
    }
  }

  Future<void> _fetchStatistics() async {
    try {
      final response = await http.get(
        Uri.parse(
            'http://localhost:5001/api/photographer/events/statistics'), // Update with your backend endpoint
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          totalEvents = data['totalEvents'];
          activeEvents = data['activeEvents'];
          futureEvents = data['futureEvents'];
        });
        print('Statistics fetched successfully.');
      } else {
        final data = jsonDecode(response.body);
        print('Failed to fetch statistics: ${data['message']}');
        _showErrorDialog(
            data['message'] ?? 'Failed to fetch statistics');
      }
    } catch (e) {
      print('Error fetching statistics: $e');
      _showErrorDialog(
          'An unexpected error occurred while fetching statistics.');
    }
  }

  Future<void> _fetchRegisteredEvents({
    String? filterLocation,
    String? sortBy,
    bool isAscending = true,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    String? searchCriterion,
  }) async {
    try {
      // Build query parameters
      Map<String, String> queryParams = {};

      if (filterLocation != null && filterLocation.isNotEmpty) {
        queryParams['location'] = filterLocation;
      }

      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sort_by'] = sortBy;
        queryParams['order'] = isAscending ? 'asc' : 'desc';
      }

      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }

      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      if (searchQuery != null &&
          searchQuery.isNotEmpty &&
          searchCriterion != null) {
        queryParams['search'] = searchQuery;
        queryParams['search_by'] = searchCriterion;
      }

      print('Query Parameters: $queryParams'); // Debug: Check query params

      String queryString = '';
      if (queryParams.isNotEmpty) {
        queryString = '?' +
            queryParams.entries
                .map((entry) =>
                    '${entry.key}=${Uri.encodeComponent(entry.value)}')
                .join('&');
      }

      print('Final Query String: $queryString'); // Debug: Check final query

      final response = await http.get(
        Uri.parse(
            'http://localhost:5001/api/photographer/events$queryString'), // Update with your backend endpoint
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        print('Fetched Registered Events Count: ${data.length}');
        if (!mounted) return;
        setState(() {
          registeredEvents =
              data.map((e) => e as Map<String, dynamic>).toList();
          _currentPage = 0; // Reset to first page on new fetch
          _applyFilters();
        });
      } else {
        final data = jsonDecode(response.body);
        print('Failed to fetch registered events: ${data['message']}');
        _showErrorDialog(
            data['message'] ?? 'Failed to fetch registered events');
      }
    } catch (e) {
      print('Error fetching registered events: $e');
      _showErrorDialog(
          'An unexpected error occurred while fetching registered events.');
    }
  }

  void _applyFilters() {
    setState(() {
      displayedEvents = registeredEvents;
      // Additional filtering can be applied here if needed
    });
  }

  Future<void> _registerForEvent() async {
    showDialog(
      context: context,
      builder: (ctx) => RegisterEventDialog(
        token: token!,
        onEventRegistered: () async {
          Navigator.of(ctx).pop(); // Close the register dialog
          await _fetchRegisteredEvents(
            filterLocation: filterLocation,
            sortBy: sortBy,
            isAscending: isAscending,
            startDate: startDate,
            endDate: endDate,
            searchQuery: _searchController.text,
            searchCriterion: _searchCriterion,
          ); // Refresh events after registration
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Registered for event successfully.')),
          );
        },
      ),
    );
  }

  Future<void> _uploadPhoto(int eventId) async {
  try {
    if (kIsWeb) {
      // Web-specific file picking
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true, // Necessary for accessing file bytes on web
      );

      if (result != null && result.files.isNotEmpty) {
        List<PlatformFile> files = result.files;

        // Show the upload progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return UploadProgressDialog(
              dio: _dio,
              token: token!,
              eventId: eventId,
              files: files,
            );
          },
        ).then((_) {
          // After upload completes, refresh the events
          _fetchRegisteredEvents(
            filterLocation: filterLocation,
            sortBy: sortBy,
            isAscending: isAscending,
            startDate: startDate,
            endDate: endDate,
            searchQuery: _searchController.text,
            searchCriterion: _searchCriterion,
          );
        });
      }
    } else {
      // Mobile/Desktop-specific file picking (if applicable)
      // Implement accordingly or restrict functionality to web
      _showErrorDialog('File uploading is only supported on web.');
    }
  } catch (e) {
    _showErrorDialog('Failed to pick images: $e');
  }

}


  void _showErrorDialog(String message) {
    // Ensure that the widget is still mounted before showing a dialog
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Operation Failed'),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            child: Text(
              'Okay',
              style: TextStyle(color: Colors.blueAccent),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Success'),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            child: Text(
              'Great!',
              style: TextStyle(color: Colors.blueAccent),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // Close the dialog
            },
          )
        ],
      ),
    );
  }

  // Method to handle logout
  Future<void> _logout() async {
    // Clear the stored token and user information
    html.window.localStorage.remove('jwt_token');
    html.window.localStorage.remove('user_name');
    html.window.localStorage.remove('user_role');

    // Navigate back to the LoginScreen after the current frame
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    });
  }

  // Method to handle search submission
  void _submitSearch() {
    print(
        'Search submitted with query: ${_searchController.text} and criterion: $_searchCriterion');
    _fetchRegisteredEvents(
      filterLocation: filterLocation,
      sortBy: sortBy,
      isAscending: isAscending,
      startDate: startDate,
      endDate: endDate,
      searchQuery: _searchController.text,
      searchCriterion: _searchCriterion,
    );
  }

  // Method to handle pagination (Next Page)
  void _nextPage() {
    setState(() {
      if ((_currentPage + 1) * _rowsPerPage < displayedEvents.length) {
        _currentPage++;
      }
    });
  }

  // Method to handle pagination (Previous Page)
  void _previousPage() {
    setState(() {
      if (_currentPage > 0) {
        _currentPage--;
      }
    });
  }

  // Method to open the filter dialog
  void _filterEvents() {
    showDialog(
      context: context,
      builder: (ctx) => FilterEventsDialog(
        currentFilter: filterLocation,
        currentStartDate: startDate,
        currentEndDate: endDate,
        onFilterApplied:
            (selectedLocation, selectedStartDate, selectedEndDate) {
          setState(() {
            filterLocation = selectedLocation;
            startDate = selectedStartDate;
            endDate = selectedEndDate;
          });
          Navigator.of(ctx).pop(); // Close the filter dialog
          _fetchRegisteredEvents(
            filterLocation: filterLocation,
            sortBy: sortBy,
            isAscending: isAscending,
            startDate: startDate,
            endDate: endDate,
            searchQuery: _searchController.text,
            searchCriterion: _searchCriterion,
          );
        },
      ),
    );
  }

  // Method to open the sort dialog
  void _sortEvents() {
    showDialog(
      context: context,
      builder: (ctx) => SortEventsDialog(
        currentSortBy: sortBy,
        isAscending: isAscending,
        onSortApplied: (selectedSortBy, ascending) {
          setState(() {
            sortBy = selectedSortBy;
            isAscending = ascending;
          });
          Navigator.of(ctx).pop(); // Close the sort dialog
          _fetchRegisteredEvents(
            filterLocation: filterLocation,
            sortBy: sortBy,
            isAscending: isAscending,
            startDate: startDate,
            endDate: endDate,
            searchQuery: _searchController.text,
            searchCriterion: _searchCriterion,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the events to display on the current page
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (_currentPage + 1) * _rowsPerPage;
    final paginatedEvents = displayedEvents.length > startIndex
        ? displayedEvents.sublist(
            startIndex,
            endIndex > displayedEvents.length
                ? displayedEvents.length
                : endIndex)
        : [];

    return Scaffold(
        backgroundColor:
            Colors.grey[100], // Light grey background for subtle contrast
        appBar: AppBar(
          // Removed the title
          backgroundColor: Colors.grey[100],
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () => _logout(),
              tooltip: 'Logout',
              color: Colors.black87,
            ),
          ],
        ),
        body: isLoading
            ? Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  await _fetchStatistics();
                  await _fetchRegisteredEvents(
                    filterLocation: filterLocation,
                    sortBy: sortBy,
                    isAscending: isAscending,
                    startDate: startDate,
                    endDate: endDate,
                    searchQuery: _searchController.text,
                    searchCriterion: _searchCriterion,
                  );
                },
                child: SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Message
                        Text(
                          'Welcome, Photographer',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            fontFamily: 'Roboto', // Default font
                          ),
                        ),
                        SizedBox(height: 30),
                        // Statistics Cards
                        LayoutBuilder(
                          builder: (context, constraints) {
                            double screenWidth = constraints.maxWidth;
                            int columns = 1;

                            if (screenWidth >= 1200) {
                              columns = 4;
                            } else if (screenWidth >= 800) {
                              columns = 3;
                            } else if (screenWidth >= 600) {
                              columns = 2;
                            }

                            double cardWidth =
                                (screenWidth - (columns - 1) * 16) / columns;

                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                // Total Events Card
                                _buildStatCard(
                                  icon: FontAwesomeIcons.calendarCheck,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blueAccent,
                                      Colors.lightBlue
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  title: 'Total Events',
                                  value: totalEvents.toString(),
                                  cardWidth: cardWidth,
                                ),
                                // Active Events Card
                                _buildStatCard(
                                  icon: FontAwesomeIcons.spinner,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.orangeAccent,
                                      Colors.deepOrange
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  title: 'Active Events',
                                  value: activeEvents.toString(),
                                  cardWidth: cardWidth,
                                ),
                                // Future Events Card
                                _buildStatCard(
                                  icon: FontAwesomeIcons.clock,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.greenAccent,
                                      Colors.lightGreen
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  title: 'Future Events',
                                  value: futureEvents.toString(),
                                  cardWidth: cardWidth,
                                ),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: 40),
                        // Events DataTable with Title and Buttons
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Text(
                              'Registered Events',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                fontFamily: 'Roboto', // Default font
                              ),
                            ),
                            SizedBox(height: 10),
                            // Buttons Row with Search Icon and Search Bar
                            Row(
                              children: [
                                // Search Icon and Search Bar
                                Expanded(
                                  child: Row(
                                    children: [
                                      // Search Icon
                                      IconButton(
                                        icon: Icon(Icons.search),
                                        onPressed: () {
                                          setState(() {
                                            _isSearchBarVisible =
                                                !_isSearchBarVisible;
                                            if (!_isSearchBarVisible) {
                                              _searchController.clear();
                                              _submitSearch();
                                            }
                                          });
                                        },
                                        tooltip: 'Search',
                                        color: Colors.black54,
                                      ),
                                      // Search Bar
                                      Expanded(
                                        child: _isSearchBarVisible
                                            ? Row(
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      controller:
                                                          _searchController,
                                                      decoration:
                                                          InputDecoration(
                                                        hintText: 'Search...',
                                                        border:
                                                            OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8.0),
                                                        ),
                                                        contentPadding:
                                                            EdgeInsets
                                                                .symmetric(
                                                                    horizontal:
                                                                        10.0),
                                                      ),
                                                      onSubmitted: (value) {
                                                        _submitSearch();
                                                      },
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  DropdownButton<String>(
                                                    value: _searchCriterion,
                                                    onChanged:
                                                        (String? newValue) {
                                                      setState(() {
                                                        _searchCriterion =
                                                            newValue!;
                                                      });
                                                    },
                                                    items: <String>[
                                                      'name',
                                                      'code'
                                                    ].map<
                                                            DropdownMenuItem<
                                                                String>>(
                                                        (String value) {
                                                      return DropdownMenuItem<
                                                          String>(
                                                        value: value,
                                                        child: Text(value[0]
                                                                .toUpperCase() +
                                                            value.substring(1)),
                                                      );
                                                    }).toList(),
                                                  ),
                                                  SizedBox(width: 10),
                                                  IconButton(
                                                    icon: Icon(Icons.clear),
                                                    onPressed: () {
                                                      setState(() {
                                                        _searchController
                                                            .clear();
                                                        _submitSearch();
                                                      });
                                                    },
                                                    tooltip: 'Clear Search',
                                                    color: Colors.black54,
                                                  ),
                                                ],
                                              )
                                            : Container(),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 10),
                                // Filter Button
                                ElevatedButton.icon(
                                  onPressed: _filterEvents,
                                  icon: Icon(Icons.filter_list),
                                  label: Text('Filter'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.blueAccent, // Changed from 'primary'
                                    foregroundColor: Colors
                                        .white, // Changed from 'onPrimary'
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                // Sort Button
                                ElevatedButton.icon(
                                  onPressed: _sortEvents,
                                  icon: Icon(Icons.sort),
                                  label: Text('Sort'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.orangeAccent, // Changed from 'primary'
                                    foregroundColor: Colors
                                        .white, // Changed from 'onPrimary'
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                // Register Button
                                ElevatedButton.icon(
                                  onPressed: _registerForEvent,
                                  icon: Icon(Icons.app_registration),
                                  label: Text('Register'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.green, // Changed from 'primary'
                                    foregroundColor: Colors
                                        .white, // Changed from 'onPrimary'
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        // DataTable Container
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Container(
                            width: double
                                .infinity, // Makes the container take all available width
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.2),
                                  spreadRadius: 2,
                                  blurRadius: 5,
                                  offset: Offset(
                                      0, 3), // changes position of shadow
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints
                                          .maxWidth, // Ensures the DataTable takes at least the full width
                                    ),
                                    child: DataTable(
                                      headingRowColor:
                                          MaterialStateColor.resolveWith(
                                              (states) => Colors.blueAccent),
                                      headingTextStyle: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        fontFamily: 'Roboto',
                                      ),
                                      dataTextStyle: TextStyle(
                                        color: Colors.black87,
                                        fontFamily: 'Roboto',
                                      ),
                                      columns: [
                                        DataColumn(label: Text('Event Code')),
                                        DataColumn(label: Text('Event Name')),
                                        DataColumn(label: Text('Date')),
                                        DataColumn(label: Text('Location')),
                                        DataColumn(label: Text('Actions')),
                                      ],
                                      rows: paginatedEvents.map((event) {
                                        return DataRow(cells: [
                                          DataCell(
                                              Text(event['code'] ?? 'N/A')),
                                          DataCell(
                                              Text(event['name'] ?? 'N/A')),
                                          DataCell(Text(event['date'] != null
                                              ? _formatDate(event['date'])
                                              : 'N/A')),
                                          DataCell(
                                              Text(event['location'] ?? 'N/A')),
                                          DataCell(
                                            Row(
                                              children: [
                                                TextButton.icon(
                                                  icon: Icon(
                                                    Icons.upload_file,
                                                    color: Colors.green,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    'Upload',
                                                    style: TextStyle(
                                                        color: Colors.green),
                                                  ),
                                                  onPressed: () {
                                                    _uploadPhoto(event['id']);
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]);
                                      }).toList(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        // Pagination Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed:
                                  _currentPage > 0 ? _previousPage : null,
                              child: Text('Previous'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.blueAccent, // Button color
                                foregroundColor: Colors.white, // Text color
                              ),
                            ),
                            SizedBox(width: 20),
                            Text(
                              'Page ${_currentPage + 1} of ${displayedEvents.length ~/ _rowsPerPage + (displayedEvents.length % _rowsPerPage == 0 ? 0 : 1)}',
                              style: TextStyle(fontSize: 16),
                            ),
                            SizedBox(width: 20),
                            ElevatedButton(
                              onPressed: (_currentPage + 1) * _rowsPerPage <
                                      displayedEvents.length
                                  ? _nextPage
                                  : null,
                              child: Text('Next'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.blueAccent, // Button color
                                foregroundColor: Colors.white, // Text color
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            );
  }

  // Helper method to format the date string
  String _formatDate(String dateStr) {
    try {
      DateTime dateTime = DateTime.parse(dateStr);
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    } catch (e) {
      print('Error formatting date: $e');
      return dateStr; // Return the original string if parsing fails
    }
  }

  // Widget for count-based statistics cards
  Widget _buildStatCard({
    required IconData icon,
    required Gradient gradient,
    required String title,
    required String value,
    double? cardWidth,
  }) {
    return Container(
      width: cardWidth ?? double.infinity,
      child: Container(
        height: 120, // Fixed height for consistency
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 7,
              offset: Offset(0, 3), // changes position of shadow
            ),
          ],
        ),
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            // Icon
            FaIcon(
              icon,
              color: Colors.white,
              size: 40,
            ),
            SizedBox(width: 20),
            // Texts
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UploadProgressDialog extends StatefulWidget {
  final Dio dio;
  final String token;
  final int eventId;
  final List<PlatformFile> files;

  UploadProgressDialog({
    required this.dio,
    required this.token,
    required this.eventId,
    required this.files,
  });

  @override
  _UploadProgressDialogState createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  // Map to hold progress for each file
  Map<String, double> _progressMap = {};

  // Map to hold status messages
  Map<String, String> _statusMap = {};

  // Determine if all uploads are completed
  bool get _allUploadsCompleted {
    return _statusMap.values.every((status) =>
        status == 'Uploaded Successfully' || status == 'Upload Failed');
  }

  // Initialize progress and status maps
  @override
  void initState() {
    super.initState();
    for (var file in widget.files) {
      _progressMap[file.name] = 0.0;
      _statusMap[file.name] = 'Uploading...';
      _uploadFile(file);
    }
  }

  // Method to upload a single file
  Future<void> _uploadFile(PlatformFile file) async {
    String fileName = file.name;
    try {
      String url = 'http://localhost:5001/api/photographer/upload'; // Update with your backend endpoint

      // Determine the content type using a helper function or map
      String contentTypeStr = _getContentType(file.extension);

      FormData formData = FormData.fromMap({
        'event_id': widget.eventId.toString(),
        'photos': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
          contentType: MediaType.parse(contentTypeStr),
        ),
      });

      await widget.dio.post(
        url,
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'multipart/form-data',
          },
        ),
        onSendProgress: (int sent, int total) {
          double progress = sent / total;
          if (!mounted) return;
          setState(() {
            _progressMap[file.name] = progress;
          });
        },
      );

      // Update status to success
      if (!mounted) return;
      setState(() {
        _statusMap[file.name] = 'Uploaded Successfully';
      });
      print('$fileName uploaded successfully.');
    } catch (e) {
      print('Error uploading $fileName: $e');
      if (!mounted) return;
      setState(() {
        _statusMap[file.name] = 'Upload Failed';
      });
    } finally {
      // Check if all uploads are completed
      if (_allUploadsCompleted) {
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pop(); // Close the dialog after a short delay
            // Optionally, show a snackbar or another dialog to notify completion
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('All uploads completed.')),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Uploading Photos'),
      content: Container(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.files.map((file) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.name),
                  SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: _progressMap[file.name],
                  ),
                  SizedBox(height: 5),
                  Text(_statusMap[file.name]!),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          child: Text('Close'),
          onPressed: () {
            if (_allUploadsCompleted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  String _getContentType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream'; // Fallback
    }
  }
}



///
/// Dialog for registering to an event
///
class RegisterEventDialog extends StatefulWidget {
  final String token;
  final VoidCallback onEventRegistered;

  RegisterEventDialog({required this.token, required this.onEventRegistered});

  @override
  _RegisterEventDialogState createState() => _RegisterEventDialogState();
}

class _RegisterEventDialogState extends State<RegisterEventDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? eventCode;

  bool isSubmitting = false;
  bool isSuccess = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller for checkmark
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _animation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      // Invalid input
      return;
    }

    _formKey.currentState!.save();

    setState(() {
      isSubmitting = true;
    });

    try {
      final response = await http.post(
        Uri.parse(
            'http://localhost:5001/api/photographer/register'), // Endpoint to register for event
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'event_code': eventCode,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Success
        setState(() {
          isSubmitting = false;
          isSuccess = true;
        });
        _animationController.forward();

        // Wait for animation to finish
        await Future.delayed(Duration(milliseconds: 1200));

        widget.onEventRegistered(); // Callback to refresh events
      } else {
        // Failure
        final data = jsonDecode(response.body);
        _showError(data['message'] ?? 'Failed to register for event');
      }
    } catch (e) {
      print('Error registering for event: $e');
      _showError(
          'An unexpected error occurred while registering for the event.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      isSubmitting = false;
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Registration Failed'),
        content: Text(message),
        actions: [
          TextButton(
            child: Text('Okay'),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: isSuccess
          ? ScaleTransition(
              scale: _animation,
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                      size: 80,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Registered Successfully!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Register for Event',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Divider(),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Event Code
                          TextFormField(
                            decoration:
                                InputDecoration(labelText: 'Event Code'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter event code';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              eventCode = value;
                            },
                          ),
                          SizedBox(height: 20),
                          // Submit Button
                          isSubmitting
                              ? CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: Text('Register'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.green, // Changed from 'primary'
                                    foregroundColor: Colors
                                        .white, // Changed from 'onPrimary'
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 30, vertical: 10),
                                    textStyle: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

///
/// Dialog for filtering events
///
class FilterEventsDialog extends StatefulWidget {
  final String? currentFilter;
  final DateTime? currentStartDate;
  final DateTime? currentEndDate;
  final Function(String?, DateTime?, DateTime?) onFilterApplied;

  FilterEventsDialog({
    this.currentFilter,
    this.currentStartDate,
    this.currentEndDate,
    required this.onFilterApplied,
  });

  @override
  _FilterEventsDialogState createState() => _FilterEventsDialogState();
}

class _FilterEventsDialogState extends State<FilterEventsDialog> {
  String? selectedLocation;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  @override
  void initState() {
    super.initState();
    selectedLocation = widget.currentFilter;
    selectedStartDate = widget.currentStartDate;
    selectedEndDate = widget.currentEndDate;
  }

  Future<void> _pickStartDate() async {
    DateTime initialDate = selectedStartDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: selectedEndDate ?? DateTime(2100),
    );
    if (picked != null && picked != selectedStartDate) {
      setState(() {
        selectedStartDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    DateTime initialDate = selectedEndDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: selectedStartDate ?? DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != selectedEndDate) {
      setState(() {
        selectedEndDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Filter Events'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Location Filter
            DropdownButtonFormField<String>(
              value: selectedLocation ?? 'All',
              decoration: InputDecoration(labelText: 'Location'),
              items: <String>['All', 'New York', 'Marrakesh', 'Los Angeles']
                  .map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedLocation = value == 'All' ? null : value;
                });
              },
            ),
            SizedBox(height: 20),
            // Start Date Picker
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedStartDate == null
                        ? 'No Start Date Chosen!'
                        : 'Start Date: ${_formatDate(selectedStartDate!.toIso8601String())}',
                  ),
                ),
                TextButton(
                  onPressed: _pickStartDate,
                  child: Text(
                    'Choose Start Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            // End Date Picker
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedEndDate == null
                        ? 'No End Date Chosen!'
                        : 'End Date: ${_formatDate(selectedEndDate!.toIso8601String())}',
                  ),
                ),
                TextButton(
                  onPressed: _pickEndDate,
                  child: Text(
                    'Choose End Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Clear'),
          onPressed: () {
            widget.onFilterApplied(null, null, null);
          },
        ),
        TextButton(
          child: Text('Apply'),
          onPressed: () {
            widget.onFilterApplied(
                selectedLocation, selectedStartDate, selectedEndDate);
          },
        ),
      ],
    );
  }

  // Helper method to format the date string
  String _formatDate(String dateStr) {
    try {
      DateTime dateTime = DateTime.parse(dateStr);
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    } catch (e) {
      print('Error formatting date: $e');
      return dateStr; // Return the original string if parsing fails
    }
  }
}

///
/// Dialog for sorting events
///
class SortEventsDialog extends StatefulWidget {
  final String? currentSortBy;
  final bool isAscending;
  final Function(String?, bool) onSortApplied;

  SortEventsDialog({
    this.currentSortBy,
    required this.isAscending,
    required this.onSortApplied,
  });

  @override
  _SortEventsDialogState createState() => _SortEventsDialogState();
}

class _SortEventsDialogState extends State<SortEventsDialog> {
  String? selectedSortBy;
  bool ascending = true;

  @override
  void initState() {
    super.initState();
    selectedSortBy = widget.currentSortBy;
    ascending = widget.isAscending;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sort Events'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sort By Dropdown
          DropdownButtonFormField<String>(
            value: selectedSortBy ?? 'none',
            decoration: InputDecoration(labelText: 'Sort By'),
            items: <String>['none', 'name', 'date', 'location']
                .map((String value) {
              String displayText;
              switch (value) {
                case 'none':
                  displayText = 'None';
                  break;
                case 'name':
                  displayText = 'Name';
                  break;
                case 'date':
                  displayText = 'Date';
                  break;
                case 'location':
                  displayText = 'Location';
                  break;
                default:
                  displayText = value;
              }
              return DropdownMenuItem<String>(
                value: value,
                child: Text(displayText),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedSortBy = value == 'none' ? null : value;
              });
            },
          ),
          SizedBox(height: 10),
          // Sort Order Switch
          Row(
            children: [
              Text('Descending'),
              Switch(
                value: ascending,
                onChanged: (value) {
                  setState(() {
                    ascending = value;
                  });
                },
              ),
              Text('Ascending'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          child: Text('Clear'),
          onPressed: () {
            widget.onSortApplied(null, true);
          },
        ),
        TextButton(
          child: Text('Apply'),
          onPressed: () {
            widget.onSortApplied(selectedSortBy, ascending);
          },
        ),
      ],
    );
  }
}

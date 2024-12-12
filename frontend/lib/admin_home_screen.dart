// lib/admin_home_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart'; // Ensure this path is correct
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import Font Awesome

class AdminHomeScreen extends StatefulWidget {
  @override
  _AdminHomeScreenState createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int totalEvents = 0;
  int activeEvents = 0;
  List<Map<String, dynamic>> allEvents = [];
  List<Map<String, dynamic>> displayedEvents = [];
  bool isLoading = true; // Loading state
  final storage = FlutterSecureStorage();

  String? token;

  // State variables for closest future event
  Map<String, dynamic>? closestFutureEvent;
  int daysUntilEvent = 0;

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
  int _rowsPerPage = 3; // Number of rows per page

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    token = await storage.read(key: 'jwt_token');
    if (token != null) {
      await _fetchStatistics();
      await _fetchEvents();
      setState(() {
        isLoading = false;
      });
    } else {
      // Navigate to Login Screen if token is missing
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    }
  }

  Future<void> _fetchStatistics() async {
    try {
      final response = await http.get(
        Uri.parse(
            'http://localhost:5001/api/admin/events/statistics'), // Updated endpoint
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          totalEvents = data['totalEvents'];
          activeEvents = data['activeEvents'];
        });
      } else {
        final data = jsonDecode(response.body);
        _showErrorDialog(data['message'] ?? 'Failed to fetch statistics');
      }
    } catch (e) {
      print('Error fetching statistics: $e');
      _showErrorDialog(
          'An unexpected error occurred while fetching statistics.');
    }
  }

  Future<void> _fetchEvents({
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

      print('Query Parameters: $queryParams');

      String queryString = '';
      if (queryParams.isNotEmpty) {
        queryString = '?' +
            queryParams.entries
                .map((entry) =>
                    '${entry.key}=${Uri.encodeComponent(entry.value)}')
                .join('&');
      }

      print('Final Query String: $queryString');

      final response = await http.get(
        Uri.parse('http://localhost:5001/api/admin/events$queryString'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        print('Fetched Events Count: ${data.length}');
        setState(() {
          allEvents = data.map((e) => e as Map<String, dynamic>).toList();
          _currentPage = 0; // Reset to first page on new fetch
          _applyFilters();
        });
        _findClosestFutureEvent();
      } else {
        final data = jsonDecode(response.body);
        print('Failed to fetch events: ${data['message']}');
        _showErrorDialog(data['message'] ?? 'Failed to fetch events');
      }
    } catch (e) {
      print('Error fetching events: $e');
      _showErrorDialog('An unexpected error occurred while fetching events.');
    }
  }

  void _applyFilters() {
    setState(() {
      displayedEvents = allEvents;
      // Additional filtering can be applied here if needed
    });
  }

  void _findClosestFutureEvent() {
    DateTime today = DateTime.now();
    DateTime? closestDate;
    Map<String, dynamic>? closestEvent;

    for (var event in allEvents) {
      if (event['date'] != null) {
        DateTime eventDate = DateTime.parse(event['date']);
        if (eventDate.isAfter(today)) {
          if (closestDate == null || eventDate.isBefore(closestDate)) {
            closestDate = eventDate;
            closestEvent = event;
          }
        }
      }
    }

    if (closestEvent != null && closestDate != null) {
      final nonNullClosestDate =
          closestDate; // Assign to a non-nullable variable

      setState(() {
        closestFutureEvent = closestEvent;
        daysUntilEvent = nonNullClosestDate.difference(today).inDays;
      });
    } else {
      setState(() {
        closestFutureEvent = null;
        daysUntilEvent = 0;
      });
    }
  }

  Future<void> _deleteEvent(int eventId) async {
    try {
      final response = await http.delete(
        Uri.parse(
            'http://localhost:5001/api/admin/events/$eventId'), // Updated endpoint
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _fetchEvents(
          filterLocation: filterLocation,
          sortBy: sortBy,
          isAscending: isAscending,
          startDate: startDate,
          endDate: endDate,
          searchQuery: _searchController.text,
          searchCriterion: _searchCriterion,
        ); // Refresh events after deletion
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event deleted successfully.')),
        );
      } else {
        final data = jsonDecode(response.body);
        _showErrorDialog(data['message'] ?? 'Failed to delete event');
      }
    } catch (e) {
      print('Error deleting event: $e');
      _showErrorDialog(
          'An unexpected error occurred while deleting the event.');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Operation Failed'),
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

  // Method to handle creating a new event
  void _createEvent() {
    showDialog(
      context: context,
      builder: (ctx) => CreateEventDialog(
        token: token!,
        onEventCreated: () async {
          Navigator.of(ctx).pop(); // Close the create event dialog
          await _fetchEvents(
            filterLocation: filterLocation,
            sortBy: sortBy,
            isAscending: isAscending,
            startDate: startDate,
            endDate: endDate,
            searchQuery: _searchController.text,
            searchCriterion: _searchCriterion,
          ); // Refresh events
        },
      ),
    );
  }

  // Method to handle filtering events
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
          _fetchEvents(
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

  // Method to handle sorting events
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
          _fetchEvents(
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

  // Method to handle modifying an event
  void _modifyEvent(Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (ctx) => ModifyEventDialog(
        token: token!,
        event: event,
        onEventModified: () async {
          Navigator.of(ctx).pop(); // Close the modify event dialog
          await _fetchEvents(
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

  // Method to handle logout
  Future<void> _logout() async {
    // Clear the stored token
    await storage.delete(key: 'jwt_token');

    // Navigate back to the LoginScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  // Method to handle search submission
  void _submitSearch() {
    print(
        'Search submitted with query: ${_searchController.text} and criterion: $_searchCriterion');
    _fetchEvents(
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
                  await _fetchEvents(
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
                          'Welcome, Admin',
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
                                // Closest Event Card
                                _buildEventCard(
                                  icon: FontAwesomeIcons.clock,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.greenAccent,
                                      Colors.lightGreen
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  title: 'Closest Event',
                                  eventName: closestFutureEvent != null
                                      ? closestFutureEvent!['name']
                                      : 'No upcoming events',
                                  eventDate: closestFutureEvent != null
                                      ? _formatDate(closestFutureEvent!['date'])
                                      : '',
                                  daysRemaining: daysUntilEvent,
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
                              'All Events', // Changed the title from 'Upcoming Events' to 'All Events'
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
                                    backgroundColor: Colors
                                        .blueAccent, // Changed from 'primary'
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
                                    backgroundColor: Colors
                                        .orangeAccent, // Changed from 'primary'
                                    foregroundColor: Colors
                                        .white, // Changed from 'onPrimary'
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                // Create Button
                                ElevatedButton.icon(
                                  onPressed: _createEvent,
                                  icon: Icon(Icons.add),
                                  label: Text('Create'),
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
                                        DataColumn(label: Text('Attendees')),
                                        DataColumn(
                                            label: Text('Photographers')),
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
                                          DataCell(Text(event['num_attendees']
                                                  ?.toString() ??
                                              '0')),
                                          DataCell(Text(
                                              event['num_photographers']
                                                      ?.toString() ??
                                                  '0')),
                                          DataCell(
                                            Row(
                                              children: [
                                                TextButton.icon(
                                                  icon: Icon(
                                                    Icons.edit,
                                                    color: Colors.blue,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    'Modify',
                                                    style: TextStyle(
                                                        color: Colors.blue),
                                                  ),
                                                  onPressed: () {
                                                    _modifyEvent(event);
                                                  },
                                                ),
                                                SizedBox(width: 8),
                                                TextButton.icon(
                                                  icon: Icon(
                                                    Icons.delete,
                                                    color: Colors.red,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                        color: Colors.red),
                                                  ),
                                                  onPressed: () =>
                                                      _deleteEvent(event['id']),
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
              ));
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

  // Widget for event-based statistics card
  Widget _buildEventCard({
    required IconData icon,
    required Gradient gradient,
    required String title,
    required String? eventName,
    required String? eventDate,
    required int? daysRemaining,
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
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eventName ?? 'No upcoming events',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 5),
                  if (eventDate != null &&
                      daysRemaining != null &&
                      daysRemaining > 0)
                    Text(
                      '$eventDate • $daysRemaining days remaining',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///
/// Dialog for creating a new event
///
class CreateEventDialog extends StatefulWidget {
  final String token;
  final VoidCallback onEventCreated;

  CreateEventDialog({required this.token, required this.onEventCreated});

  @override
  _CreateEventDialogState createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<CreateEventDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? eventCode;
  String? eventName;
  String? location;
  DateTime? date;

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
    if (!_formKey.currentState!.validate() || date == null) {
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
            'http://localhost:5001/api/admin/events'), // Endpoint to create event
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}', // Use the passed token
        },
        body: jsonEncode({
          'code': eventCode,
          'name': eventName,
          'location': location,
          'date': date!.toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        // Success
        setState(() {
          isSubmitting = false;
          isSuccess = true;
        });
        _animationController.forward();

        // Wait for animation to finish
        await Future.delayed(Duration(milliseconds: 1200));

        widget.onEventCreated(); // Callback to refresh events
      } else {
        // Failure
        final data = jsonDecode(response.body);
        _showError(data['message'] ?? 'Failed to create event');
      }
    } catch (e) {
      print('Error creating event: $e');
      _showError('An unexpected error occurred while creating the event.');
    }
  }

  void _showError(String message) {
    setState(() {
      isSubmitting = false;
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Creation Failed'),
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

  // Method to pick a date
  Future<void> _pickDate() async {
    DateTime initialDate = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: date ?? initialDate,
      firstDate: initialDate,
      lastDate: DateTime(initialDate.year + 5),
    );
    if (picked != null && picked != date) {
      setState(() {
        date = picked;
      });
    }
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
                      'Event Created Successfully!',
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
                      'Create New Event',
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
                          // Event Name
                          TextFormField(
                            decoration:
                                InputDecoration(labelText: 'Event Name'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter event name';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              eventName = value;
                            },
                          ),
                          // Location
                          TextFormField(
                            decoration: InputDecoration(labelText: 'Location'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter location';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              location = value;
                            },
                          ),
                          SizedBox(height: 10),
                          // Date Picker
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  date == null
                                      ? 'No Date Chosen!'
                                      : 'Picked Date: ${_formatDate(date!.toIso8601String())}',
                                ),
                              ),
                              TextButton(
                                onPressed: _pickDate,
                                child: Text(
                                  'Choose Date',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          // Submit Button
                          isSubmitting
                              ? CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: Text('Create Event'),
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
            items: <String>[
              'none',
              'name',
              'date',
              'num_attendees',
              'num_photographers'
            ].map((String value) {
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
                case 'num_attendees':
                  displayText = 'Number of Attendees';
                  break;
                case 'num_photographers':
                  displayText = 'Number of Photographers';
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

///
/// Dialog for modifying an event
///
class ModifyEventDialog extends StatefulWidget {
  final String token;
  final Map<String, dynamic> event;
  final VoidCallback onEventModified;

  ModifyEventDialog(
      {required this.token,
      required this.event,
      required this.onEventModified});

  @override
  _ModifyEventDialogState createState() => _ModifyEventDialogState();
}

class _ModifyEventDialogState extends State<ModifyEventDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late String eventCode;
  late String eventName;
  late String location;
  DateTime? date;

  bool isSubmitting = false;
  bool isSuccess = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    eventCode = widget.event['code'] ?? '';
    eventName = widget.event['name'] ?? '';
    location = widget.event['location'] ?? '';
    date = widget.event['date'] != null
        ? DateTime.parse(widget.event['date'])
        : null;

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
    if (!_formKey.currentState!.validate() || date == null) {
      // Invalid input
      return;
    }

    _formKey.currentState!.save();

    setState(() {
      isSubmitting = true;
    });

    try {
      final response = await http.put(
        Uri.parse(
            'http://localhost:5001/api/admin/events/${widget.event['id']}'), // Endpoint to modify event
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}', // Use the passed token
        },
        body: jsonEncode({
          'code': eventCode,
          'name': eventName,
          'location': location,
          'date': date!.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        // Success
        setState(() {
          isSubmitting = false;
          isSuccess = true;
        });
        _animationController.forward();

        // Wait for animation to finish
        await Future.delayed(Duration(milliseconds: 700));

        widget.onEventModified(); // Callback to refresh events
      } else {
        // Failure
        final data = jsonDecode(response.body);
        _showError(data['message'] ?? 'Failed to modify event');
      }
    } catch (e) {
      print('Error modifying event: $e');
      _showError('An unexpected error occurred while modifying the event.');
    }
  }

  void _showError(String message) {
    setState(() {
      isSubmitting = false;
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modification Failed'),
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

  // Method to pick a date
  Future<void> _pickDate() async {
    DateTime initialDate = date ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(initialDate.year - 5),
      lastDate: DateTime(initialDate.year + 5),
    );
    if (picked != null && picked != date) {
      setState(() {
        date = picked;
      });
    }
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
                      'Event Modified Successfully!',
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
                      'Modify Event',
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
                            initialValue: eventCode,
                            decoration:
                                InputDecoration(labelText: 'Event Code'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter event code';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              eventCode = value!;
                            },
                          ),
                          // Event Name
                          TextFormField(
                            initialValue: eventName,
                            decoration:
                                InputDecoration(labelText: 'Event Name'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter event name';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              eventName = value!;
                            },
                          ),
                          // Location
                          TextFormField(
                            initialValue: location,
                            decoration: InputDecoration(labelText: 'Location'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter location';
                              }
                              return null;
                            },
                            onSaved: (value) {
                              location = value!;
                            },
                          ),
                          SizedBox(height: 10),
                          // Date Picker
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  date == null
                                      ? 'No Date Chosen!'
                                      : 'Picked Date: ${_formatDate(date!.toIso8601String())}',
                                ),
                              ),
                              TextButton(
                                onPressed: _pickDate,
                                child: Text(
                                  'Choose Date',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          // Submit Button
                          isSubmitting
                              ? CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _submit,
                                  child: Text('Modify Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.orange, // Changed from 'primary'
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

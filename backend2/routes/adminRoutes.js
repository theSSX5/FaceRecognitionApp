// routes/adminRoutes.js

const express = require('express');
const supabase = require('../supabaseClient');
const { authenticateToken, requireAdmin } = require('../middlewares/authMiddleware');

const router = express.Router();

/**
 * @route   GET /api/admin/events/statistics
 * @desc    Get event statistics (total, active, future)
 * @access  Admin
 */
router.get('/events/statistics', authenticateToken, requireAdmin, async (req, res) => {
  try {
    const { data: events, error } = await supabase.from('events').select('date');

    if (error) {
      console.error('Supabase Error:', error);
      return res.status(500).json({ message: 'Error fetching events.', error: error.message });
    }

    const totalEvents = events.length;
    const currentDate = new Date().toISOString().split('T')[0]; // YYYY-MM-DD

    let activeEvents = 0;
    let futureEvents = 0;

    events.forEach((event) => {
      const eventDate = new Date(event.date).toISOString().split('T')[0];
      if (eventDate >= currentDate) activeEvents += 1;
      if (eventDate > currentDate) futureEvents += 1;
    });

    res.status(200).json({
      totalEvents,
      activeEvents,
      futureEvents,
    });
  } catch (err) {
    console.error('Server Error:', err);
    res.status(500).json({ message: 'An internal server error occurred.', error: err.message });
  }
});

/**
 * @route   GET /api/admin/events
 * @desc    Get all events with attendee and photographer counts, with optional sorting, filtering, and searching
 * @access  Admin
 */
router.get('/events', authenticateToken, requireAdmin, async (req, res) => {
    try {
      // Extract query parameters
      const { sort_by, order, location, start_date, end_date, search, search_by } = req.query;
  
      // Validate 'sort_by' parameter
      const validSortByFields = ['name', 'date', 'num_attendees', 'num_photographers'];
      let sortBy = null;
      if (sort_by && validSortByFields.includes(sort_by.toLowerCase())) {
        sortBy = sort_by.toLowerCase();
      }
  
      // Validate 'order' parameter
      let sortOrder = 'asc'; // default
      if (order && ['asc', 'desc'].includes(order.toLowerCase())) {
        sortOrder = order.toLowerCase();
      }
  
      // Validate 'search_by' parameter
      const validSearchByFields = ['name', 'code'];
      let searchBy = null;
      if (search && search_by && validSearchByFields.includes(search_by.toLowerCase())) {
        searchBy = search_by.toLowerCase();
      }
  
      // Start building the Supabase query
      let query = supabase.from('events').select('*');
  
      // Apply location filter if provided
      if (location && location.toLowerCase() !== 'all') {
        query = query.eq('location', location);
      }
  
      // Apply date interval filter if provided
      if (start_date && end_date) {
        query = query.gte('date', start_date).lte('date', end_date);
      } else if (start_date) {
        query = query.gte('date', start_date);
      } else if (end_date) {
        query = query.lte('date', end_date);
      }
  
      // Apply search filter if provided
      if (search && searchBy) {
        // Using 'ilike' for case-insensitive partial matches
        query = query.ilike(searchBy, `%${search}%`);
      }
  
      // Execute the query
      const { data: events, error: eventsError } = await query;
  
      if (eventsError) {
        console.error('Supabase Error:', eventsError);
        return res.status(500).json({ message: 'Error fetching events.', error: eventsError.message });
      }
  
      if (!events || events.length === 0) {
        return res.status(200).json([]); // Return empty array if no events found
      }
  
      // Extract event IDs
      const eventIds = events.map(event => event.id);
  
      // Fetch attendees counts using RPC
      const { data: attendeesData, error: attendeesError } = await supabase
        .rpc('get_attendees_counts', { event_ids: eventIds });
  
      if (attendeesError) {
        console.error('Supabase Error (Attendees):', attendeesError);
        return res.status(500).json({ message: 'Error fetching attendees counts.', error: attendeesError.message });
      }
  
      // Fetch photographers counts using RPC
      const { data: photographersData, error: photographersError } = await supabase
        .rpc('get_photographers_counts', { event_ids: eventIds });
  
      if (photographersError) {
        console.error('Supabase Error (Photographers):', photographersError);
        return res.status(500).json({ message: 'Error fetching photographers counts.', error: photographersError.message });
      }
  
      // Create maps for quick lookup
      const attendeesMap = {};
      attendeesData.forEach(item => {
        attendeesMap[item.event_id] = item.attendee_count; // Ensure correct field name
      });
  
      const photographersMap = {};
      photographersData.forEach(item => {
        photographersMap[item.event_id] = item.photographer_count; // Ensure correct field name
      });
  
      // Append counts to each event
      const eventsWithCounts = events.map(event => ({
        ...event,
        num_attendees: attendeesMap[event.id] || 0, // Use attendee_count
        num_photographers: photographersMap[event.id] || 0, // Use photographer_count
      }));
  
      // Apply sorting based on 'sort_by' and 'order'
      if (sortBy) {
        if (sortBy === 'name') {
          eventsWithCounts.sort((a, b) => {
            if (a.name < b.name) return sortOrder === 'asc' ? -1 : 1;
            if (a.name > b.name) return sortOrder === 'asc' ? 1 : -1;
            return 0;
          });
        } else if (sortBy === 'date') {
          eventsWithCounts.sort((a, b) => {
            const dateA = new Date(a.date);
            const dateB = new Date(b.date);
            if (dateA < dateB) return sortOrder === 'asc' ? -1 : 1;
            if (dateA > dateB) return sortOrder === 'asc' ? 1 : -1;
            return 0;
          });
        } else if (sortBy === 'num_attendees') {
          eventsWithCounts.sort((a, b) => {
            return sortOrder === 'asc'
                ? a.num_attendees - b.num_attendees
                : b.num_attendees - a.num_attendees;
          });
        } else if (sortBy === 'num_photographers') {
          eventsWithCounts.sort((a, b) => {
            return sortOrder === 'asc'
                ? a.num_photographers - b.num_photographers
                : b.num_photographers - a.num_photographers;
          });
        }
      }
  
      res.status(200).json(eventsWithCounts);
    } catch (err) {
      console.error('Server Error:', err);
      res.status(500).json({ message: 'An internal server error occurred.', error: err.message });
    }
  });

/**
 * @route   POST /api/admin/events
 * @desc    Create a new event
 * @access  Admin
 */
router.post('/events', authenticateToken, requireAdmin, async (req, res) => {
  try {
    const { code, name, location, date } = req.body;

    // Input Validation
    if (!code || !name || !location || !date) {
      return res.status(400).json({ message: 'All fields (code, name, location, date) are required.' });
    }

    // Optional: Check for unique event code
    const { data: existingEvent, error: existingError } = await supabase
      .from('events')
      .select('*')
      .eq('code', code)
      .single();

    if (existingError && existingError.code !== 'PGRST116') { // PGRST116: No rows found
      console.error('Supabase Error (Existing Event):', existingError);
      return res.status(500).json({ message: 'Error checking existing event.', error: existingError.message });
    }

    if (existingEvent) {
      return res.status(409).json({ message: 'An event with the provided code already exists.' });
    }

    // Insert the new event
    const { data: newEvent, error: insertError } = await supabase
      .from('events')
      .insert([
        {
          code,
          name,
          location,
          date, // Ensure date is in ISO8601 format
        }
      ])
      .single();

    if (insertError) {
      console.error('Supabase Error (Insert Event):', insertError);
      return res.status(500).json({ message: 'Error creating event.', error: insertError.message });
    }

    res.status(201).json({
      message: 'Event created successfully.',
      event: newEvent,
    });
  } catch (err) {
    console.error('Server Error:', err);
    res.status(500).json({ message: 'An internal server error occurred.', error: err.message });
  }
});

/**
 * @route   PUT /api/admin/events/:id
 * @desc    Modify an existing event
 * @access  Admin
 */
router.put('/events/:id', authenticateToken, requireAdmin, async (req, res) => {
  try {
    const eventId = req.params.id;
    const { code, name, location, date } = req.body;

    // Input Validation
    if (!code || !name || !location || !date) {
      return res.status(400).json({ message: 'All fields (code, name, location, date) are required.' });
    }

    // Optional: Check for unique event code excluding current event
    const { data: existingEvent, error: existingError } = await supabase
      .from('events')
      .select('*')
      .eq('code', code)
      .neq('id', eventId)
      .single();

    if (existingError && existingError.code !== 'PGRST116') { // PGRST116: No rows found
      console.error('Supabase Error (Existing Event):', existingError);
      return res.status(500).json({ message: 'Error checking existing event.', error: existingError.message });
    }

    if (existingEvent) {
      return res.status(409).json({ message: 'Another event with the provided code already exists.' });
    }

    // Update the event
    const { data: updatedEvent, error: updateError } = await supabase
      .from('events')
      .update({
        code,
        name,
        location,
        date, // Ensure date is in ISO8601 format
      })
      .eq('id', eventId)
      .single();

    if (updateError) {
      console.error('Supabase Error (Update Event):', updateError);
      return res.status(500).json({ message: 'Error updating event.', error: updateError.message });
    }

    res.status(200).json({
      message: 'Event updated successfully.',
      event: updatedEvent,
    });
  } catch (err) {
    console.error('Server Error:', err);
    res.status(500).json({ message: 'An internal server error occurred.', error: err.message });
  }
});

/**
 * @route   DELETE /api/admin/events/:id
 * @desc    Delete an existing event
 * @access  Admin
 */
router.delete('/events/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
      const eventId = req.params.id;
  
      // Check if the event exists
      const { data: existingEvent, error: fetchError } = await supabase
        .from('events')
        .select('*')
        .eq('id', eventId)
        .single();
  
      if (fetchError) {
        if (fetchError.code === 'PGRST116') { // No rows found
          return res.status(404).json({ message: 'Event not found.' });
        }
        console.error('Supabase Error (Fetch Event):', fetchError);
        return res.status(500).json({ message: 'Error fetching event.', error: fetchError.message });
      }
  
      // Delete the event
      const { error: deleteError } = await supabase
        .from('events')
        .delete()
        .eq('id', eventId);
  
      if (deleteError) {
        console.error('Supabase Error (Delete Event):', deleteError);
        return res.status(500).json({ message: 'Error deleting event.', error: deleteError.message });
      }
  
      res.status(200).json({ message: 'Event deleted successfully.' });
    } catch (err) {
      console.error('Server Error:', err);
      res.status(500).json({ message: 'An internal server error occurred.', error: err.message });
    }
  });
  

module.exports = router;
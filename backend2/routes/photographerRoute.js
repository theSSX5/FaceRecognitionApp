// routes/photographerRoute.js

const express = require('express');
const supabase = require('../supabaseClient');
const { authenticateToken, requirePhotographer } = require('../middlewares/authMiddleware');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const nodemailer = require('nodemailer');
const axios = require('axios');
const FormData = require('form-data');
const dotenv = require('dotenv');

dotenv.config();

const router = express.Router();

// Configure multer for memory storage
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

// Setup Nodemailer transporter
const transporter = nodemailer.createTransport({
    service: 'Gmail', // Replace with your email service if different
    auth: {
        user: process.env.EMAIL_USER, // Your email address
        pass: process.env.EMAIL_PASS, // Your email password or app-specific password
    },
});

/**
 * Helper function to send image to Python service for face recognition
 * @param {Buffer} imageBuffer - The image buffer
 * @returns {Promise<Array>} - Array of recognition results
 */
async function recognizeFaces(imageBuffer) {
    const form = new FormData();
    form.append('image', imageBuffer, 'photo.jpg');

    try {
        const response = await axios.post(`${process.env.FACE_RECOGNITION_URL}`, form, { // Ensure '/recognize' is appended
            headers: {
                ...form.getHeaders(),
                'x-api-key': process.env.FACE_RECOGNITION_API_KEY, // Add API Key if set
            },
            timeout: 60000, // 60 seconds timeout
        });
        console.log('Face Recognition Response:', response.data);
        return response.data.results;
    } catch (error) {
        console.error('Face Recognition Service Error:', error.message);
        throw new Error('Face recognition service failed.');
    }
}


/**
 * @route   GET /api/photographer/events
 * @desc    Get all events the photographer is registered for
 * @access  Photographer
 */
router.get(
    '/events',
    authenticateToken,
    requirePhotographer,
    async (req, res) => {
        try {
            const photographerId = req.user.id;

            // Fetch all photographer-event associations
            const { data: photographerEvents, error: assocError } = await supabase
                .from('photographers_events')
                .select('event_id')
                .eq('photographer_id', photographerId);

            if (assocError) {
                console.error('Error fetching photographer-event associations:', assocError);
                return res.status(500).json({ message: 'Failed to fetch photographer-event associations.' });
            }

            if (!photographerEvents || photographerEvents.length === 0) {
                return res.status(200).json([]); // No events found
            }

            // Extract event IDs
            const eventIds = photographerEvents.map(event => event.event_id);

            // Fetch event details
            const { data: events, error: eventsError } = await supabase
                .from('events')
                .select('id, code, name, location, date')
                .in('id', eventIds);

            if (eventsError) {
                console.error('Error fetching events:', eventsError);
                return res.status(500).json({ message: 'Failed to fetch events.' });
            }

            res.status(200).json(events);
        } catch (error) {
            console.error('Server Error:', error);
            res.status(500).json({ message: 'An internal server error occurred.' });
        }
    }
);

/**
 * @route   GET /api/photographer/events/statistics
 * @desc    Get statistics for photographer's events
 * @access  Photographer
 */
router.get(
    '/events/statistics',
    authenticateToken,
    requirePhotographer,
    async (req, res) => {
        try {
            const photographerId = req.user.id;

            // Current date for comparison
            const currentDate = new Date().toISOString().split('T')[0];

            // Fetch all events associated with the photographer
            const { data: photographerEvents, error: assocError } = await supabase
                .from('photographers_events')
                .select('event_id')
                .eq('photographer_id', photographerId);

            if (assocError) {
                console.error('Error fetching photographer-event associations:', assocError);
                return res.status(500).json({ message: 'Failed to fetch photographer-event associations.' });
            }

            if (!photographerEvents || photographerEvents.length === 0) {
                return res.status(200).json({
                    totalEvents: 0,
                    activeEvents: 0,
                    futureEvents: 0,
                });
            }

            // Extract event IDs
            const eventIds = photographerEvents.map(event => event.event_id);

            // Total Events
            const { count: totalEvents, error: totalError } = await supabase
                .from('events')
                .select('*', { count: 'exact', head: true })
                .in('id', eventIds);

            if (totalError) {
                console.error('Error fetching total events:', totalError);
                return res.status(500).json({ message: 'Failed to fetch total events.' });
            }

            // Active Events (events happening today)
            const { count: activeEvents, error: activeError } = await supabase
                .from('events')
                .select('*', { count: 'exact', head: true })
                .in('id', eventIds)
                .eq('date', currentDate);

            if (activeError) {
                console.error('Error fetching active events:', activeError);
                return res.status(500).json({ message: 'Failed to fetch active events.' });
            }

            // Future Events (events after today)
            const { count: futureEvents, error: futureError } = await supabase
                .from('events')
                .select('*', { count: 'exact', head: true })
                .in('id', eventIds)
                .gt('date', currentDate);

            if (futureError) {
                console.error('Error fetching future events:', futureError);
                return res.status(500).json({ message: 'Failed to fetch future events.' });
            }

            res.status(200).json({
                totalEvents: totalEvents || 0,
                activeEvents: activeEvents || 0,
                futureEvents: futureEvents || 0,
            });
        } catch (error) {
            console.error('Server Error:', error);
            res.status(500).json({ message: 'An internal server error occurred.' });
        }
    }
);

// ... [Other imports and configurations]

/**
 * @route   POST /api/photographer/upload
 * @desc    Photographer uploads event photos for face recognition
 * @access  Photographer
 */
router.post(
    '/upload',
    authenticateToken,
    requirePhotographer,
    upload.array('photos', 20), // Adjust the maximum number of photos as needed
    async (req, res) => {
        try {
            const { event_id } = req.body;
            const photos = req.files;

            // Validate inputs
            if (!event_id || !photos || photos.length === 0) {
                return res.status(400).json({ message: 'Event ID and at least one photo are required.' });
            }

            // Verify that the photographer is associated with the event
            const { data: event, error: eventError } = await supabase
                .from('events')
                .select('*')
                .eq('id', event_id)
                .single();

            if (eventError || !event) {
                console.error('Event Fetch Error:', eventError);
                return res.status(404).json({ message: 'Event not found.' });
            }

            const { data: association, error: assocError } = await supabase
                .from('photographers_events')
                .select('*')
                .eq('photographer_id', req.user.id)
                .eq('event_id', event_id)
                .single();

            if (assocError || !association) {
                console.error('Photographer-Event Association Error:', assocError);
                return res.status(403).json({ message: 'You are not associated with this event.' });
            }

            // Fetch known attendees for this event
            const { data: attendees, error: attendeesError } = await supabase
                .from('attendees_events')
                .select(`
                    attendee_id,
                    attendees (
                        user_id,
                        users (email)
                    )
                `)
                .eq('event_id', event_id);

            if (attendeesError) {
                console.error('Error fetching attendees for the event:', attendeesError);
                return res.status(500).json({ message: 'Failed to fetch attendees for the event.' });
            }

            // Create a mapping from attendee_id to email
            const attendeeMap = {};
            attendees.forEach(a => {
                if (a.attendees && a.attendees.users && a.attendees.users.email) {
                    attendeeMap[a.attendee_id] = a.attendees.users.email;
                }
            });

            // Prepare an array to hold upload statuses
            const uploadStatuses = [];

            for (const photo of photos) {
                let status = {
                    filename: photo.originalname,
                    success: false,
                    message: '',
                };

                try {
                    // Upload the photo to Supabase Storage
                    const fileExtension = path.extname(photo.originalname);
                    const fileName = `${uuidv4()}${fileExtension}`;
                    const filePath = `photos/${fileName}`;

                    const { data: uploadData, error: uploadError } = await supabase.storage
                        .from('photos')
                        .upload(filePath, photo.buffer, {
                            contentType: photo.mimetype,
                            upsert: false,
                        });

                    if (uploadError) {
                        console.error('Supabase Storage Upload Error:', uploadError.message);
                        status.message = 'Failed to upload photo to storage.';
                        uploadStatuses.push(status);
                        continue; // Skip processing this photo
                    }

                    // Get the public URL of the uploaded photo
                    const { data: urlData, error: urlError } = supabase.storage
                        .from('photos')
                        .getPublicUrl(filePath);

                    if (urlError || !urlData.publicUrl) {
                        console.error('Supabase Storage Get Public URL Error:', urlError ? urlError.message : 'No public URL returned.');
                        status.message = 'Failed to retrieve photo URL.';
                        uploadStatuses.push(status);
                        continue; // Skip processing this photo
                    }

                    const publicURL = urlData.publicUrl;

                    console.log('Public URL:', publicURL);

                    // Send the photo to the Python face recognition service
                    let recognitionResults;
                    try {
                        recognitionResults = await recognizeFaces(photo.buffer);
                    } catch (error) {
                        console.error('Face Recognition Error:', error.message);
                        status.message = 'Face recognition failed.';
                        uploadStatuses.push(status);
                        continue; // Skip further processing for this photo
                    }

                    // Insert photo metadata into the database
                    const insertResponse = await supabase
                        .from('photos')
                        .insert([
                            {
                                event_id: event_id,
                                photographer_id: req.user.id,
                                url: publicURL,
                            },
                        ])
                        .select() // This ensures the inserted row is returned
                        .single();

                    console.log('Insert Response:', insertResponse); // Debugging log

                    const { data: photoRecord, error: photoError } = insertResponse;

                    if (photoError || !photoRecord) {
                        console.error('Supabase Insert Photo Error:', photoError ? photoError.message : 'No photo record returned.');
                        status.message = 'Failed to insert photo record.';
                        uploadStatuses.push(status);
                        continue; // Skip further processing for this photo
                    }

                    const photoId = photoRecord.id;


                    // Process each face detected in the photo
                    for (const result of recognitionResults) {
                        if (result && result.user_id && attendeeMap[result.user_id]) {
                            const { user_id, email, distance, encoding } = result;

                            // Insert into photos_attendees table
                            const { data: paRecord, error: paError } = await supabase
                                .from('photos_attendees')
                                .insert([
                                    {
                                        photo_id: photoId,
                                        attendee_id: user_id,
                                        face_encoding: encoding, // Store the encoding array
                                        distance: distance, // Store the distance
                                    },
                                ]);

                            if (paError) {
                                console.error('Supabase Insert Photos_Attendees Error:', paError.message);
                                // Continue processing other faces
                            }

                            // Send email to the attendee with the photo
                            const attendeeEmail = email;

                            const mailOptions = {
                                from: process.env.EMAIL_USER,
                                to: attendeeEmail,
                                subject: `Your Photo from ${event.name}`,
                                text: `Hello,

We are pleased to share a photo from the event "${event.name}" where you attended.

You can view your photo here: ${publicURL}

Best regards,
Event Team`,
                            };

                            transporter.sendMail(mailOptions, (error, info) => {
                                if (error) {
                                    return console.error('Error sending email:', error);
                                }
                                console.log('Email sent:', info.response);
                            });
                        }
                    }

                    status.success = true;
                    status.message = 'Photo uploaded and processed successfully.';
                } catch (error) {
                    console.error('Photo Upload Error:', error);
                    status.message = 'An internal server error occurred.';
                }

                uploadStatuses.push(status);
            }

            res.status(200).json({ uploadStatuses });
        } catch (error) {
            console.error('Photo Upload Error:', error);
            res.status(500).json({ message: 'An internal server error occurred.', error: error.message });
        }
    }
);


/**
 * @route   POST /api/photographer/register
 * @desc    Register a photographer to an event using the event code
 * @access  Photographer
 */
router.post(
    '/register',
    authenticateToken,
    requirePhotographer,
    async (req, res) => {
        try {
            const { event_code } = req.body;

            // Validate the event code
            if (!event_code) {
                return res.status(400).json({ message: 'Event code is required.' });
            }

            // Check if the event exists
            const { data: event, error: eventError } = await supabase
                .from('events')
                .select('id, name')
                .eq('code', event_code)
                .single();

            if (eventError || !event) {
                console.error('Event Fetch Error:', eventError);
                return res.status(404).json({ message: 'Event not found.' });
            }

            // Check if the photographer is already registered for this event
            const photographerId = req.user.id;
            const { data: association, error: assocError } = await supabase
                .from('photographers_events')
                .select('*')
                .eq('photographer_id', photographerId)
                .eq('event_id', event.id)
                .single();

            if (association) {
                return res.status(400).json({ message: 'You are already registered for this event.' });
            }

            if (assocError && assocError.code !== 'PGRST116') { // PGRST116: No rows found
                console.error('Photographer-Event Association Check Error:', assocError);
                return res.status(500).json({ message: 'Failed to verify registration status.' });
            }

            // Register the photographer to the event
            const { data: registration, error: registrationError } = await supabase
                .from('photographers_events')
                .insert({
                    photographer_id: photographerId,
                    event_id: event.id,
                });

            if (registrationError) {
                console.error('Photographer Registration Error:', registrationError);
                return res.status(500).json({ message: 'Failed to register for the event.' });
            }

            res.status(201).json({
                message: `Successfully registered for the event "${event.name}".`,
            });
        } catch (error) {
            console.error('Register Event Error:', error);
            res.status(500).json({ message: 'An internal server error occurred.', error: error.message });
        }
    }
);

module.exports = router;
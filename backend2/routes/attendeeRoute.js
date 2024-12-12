// routes/attendeeRoute.js

const express = require('express');
const supabase = require('../supabaseClient');
const { authenticateToken } = require('../middlewares/authMiddleware');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const FormData = require('form-data');
const axios = require('axios');

const router = express.Router();

// Configure multer for memory storage
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

/**
 * Helper function to get the face encoding from the Python service
 * @param {Buffer} imageBuffer - The image buffer
 * @returns {Promise<Array>} - Returns a promise with the face encoding array
 */
async function getFaceEncoding(imageBuffer) {
    const form = new FormData();

    // Use a valid name and extension when appending the buffer
    form.append('image', imageBuffer, { filename: 'attendee_photo.jpg', contentType: 'image/jpeg' });

    try {
        const response = await axios.post(`${process.env.FACE_RECOGNITION_URL}`, form, {
            headers: {
                ...form.getHeaders(),
                'x-api-key': process.env.FACE_RECOGNITION_API_KEY, // Optional API Key
            },
            timeout: 60000, // 60 seconds timeout
        });

        // Ensure the response has the expected structure
        if (!response.data || !response.data.results || !Array.isArray(response.data.results)) {
            throw new Error('Invalid response structure from face recognition service.');
        }

        // Handle the case when multiple faces are detected
        const encodings = response.data.results;
        if (encodings.length === 0) {
            throw new Error('No faces detected in the photo.');
        }

        // Return the first face encoding's encoding array
        const firstEncoding = encodings[0];
        if (!firstEncoding || !firstEncoding.encoding || !Array.isArray(firstEncoding.encoding)) {
            throw new Error('Face encoding is missing or invalid.');
        }

        return firstEncoding.encoding; // Return the encoding array directly
    } catch (error) {
        console.error('Error in face encoding:', error.message);
        throw new Error('Face encoding failed.');
    }
}

/**
 * @route   POST /api/attendee/checkin
 * @desc    Attendee check-in with event code and face photo
 * @access  Attendee
 */
router.post(
  '/checkin',
  authenticateToken,
  upload.single('face_photo'),
  async (req, res) => {
    try {
      const { event_code } = req.body;
      const facePhoto = req.file;

      // Validate inputs
      if (!event_code || !facePhoto) {
        return res.status(400).json({ message: 'Event code and face photo are required.' });
      }

      // Fetch the event by code
      const { data: event, error: eventError } = await supabase
        .from('events')
        .select('*')
        .eq('code', event_code)
        .single();

      if (eventError || !event) {
        console.error('Event Fetch Error:', eventError);
        return res.status(404).json({ message: 'Event not found.' });
      }

      // Check if attendee is already registered for this event
      const { data: existingAssociation, error: assocError } = await supabase
        .from('attendees_events')
        .select('*')
        .eq('attendee_id', req.user.id)
        .eq('event_id', event.id)
        .single();

      if (existingAssociation) {
        return res.status(400).json({ message: 'You are already registered for this event.' });
      }

      if (assocError && assocError.code !== 'PGRST116') { // PGRST116: Row not found
        console.error('Association Check Error:', assocError);
        return res.status(500).json({ message: 'Failed to verify registration status.', error: assocError.message });
      }

      // Upload the face photo to Supabase Storage
      const fileExtension = path.extname(facePhoto.originalname);
      const fileName = `${uuidv4()}${fileExtension}`;
      const filePath = `photos/${fileName}`;

      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('photos')
        .upload(filePath, facePhoto.buffer, {
          contentType: facePhoto.mimetype,
          upsert: false,
        });

      if (uploadError) {
        console.error('Supabase Storage Upload Error:', uploadError);
        return res.status(500).json({ message: 'Failed to upload face photo.', error: uploadError.message });
      }

      // Get the public URL of the uploaded photo
      const { data: urlData, error: urlError } = supabase.storage
        .from('photos')
        .getPublicUrl(filePath);

      if (urlError || !urlData.publicUrl) {
        console.error('Supabase Storage Get Public URL Error:', urlError);
        return res.status(500).json({ message: 'Failed to retrieve face photo URL.', error: urlError.message });
      }

      const publicURL = urlData.publicUrl;

      if (!publicURL) {
        console.error('Public URL is undefined.');
        return res.status(500).json({ message: 'Failed to retrieve face photo URL.' });
      }

      console.log('Public URL:', publicURL);

      // Fetch the face encoding from the Python service
      let faceEncoding;
      try {
        faceEncoding = await getFaceEncoding(facePhoto.buffer);
      } catch (error) {
        console.error('Error getting face encoding:', error.message);
        return res.status(500).json({ message: 'Failed to process face encoding.', error: error.message });
      }

      console.log('Attendee Encoding:', faceEncoding);

      // Upsert attendee data
      const { data: attendeeData, error: attendeeError } = await supabase
        .from('attendees')
        .upsert([
          {
            user_id: req.user.id,
            face_encoding: faceEncoding, // Store the encoding array directly
            url: publicURL, // Store the public URL of the face photo
          },
        ])
        .single();

      if (attendeeError) {
        console.error('Supabase Upsert Attendee Error:', attendeeError);
        return res.status(500).json({ message: 'Failed to update attendee data.', error: attendeeError.message });
      }

      console.log('Attendee Upsert Success:', attendeeData);

      // Associate attendee with the event
      const { data: associationData, error: associationError } = await supabase
        .from('attendees_events')
        .insert([
          {
            attendee_id: req.user.id,
            event_id: event.id,
          },
        ]);

      if (associationError) {
        console.error('Supabase Associate Attendee with Event Error:', associationError);
        return res.status(500).json({ message: 'Failed to associate attendee with event.', error: associationError.message });
      }

      console.log('Attendee-Event Association Success:', associationData);

      res.status(200).json({ message: 'Check-in successful!' });
    } catch (error) {
      console.error('Check-In Error:', error);
      res.status(500).json({ message: 'An internal server error occurred.', error: error.message });
    }
  }
);

module.exports = router;
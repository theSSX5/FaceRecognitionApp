# face_recognition_service.py

from flask import Flask, request, jsonify
import face_recognition
import numpy as np
from supabase import create_client, Client
import os
from dotenv import load_dotenv
import threading
import time

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)

# Initialize Supabase client
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')
#FACE_RECOGNITION_API_KEY = os.getenv('FACE_RECOGNITION_API_KEY')  # For optional API key authentication

if not SUPABASE_URL or not SUPABASE_KEY:
    raise EnvironmentError("Supabase URL and Key must be set in environment variables.")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Global variables to store known faces
known_faces = []
known_ids = []
known_emails = []
cache_lock = threading.Lock()

def load_known_faces():
    """
    Fetches known attendees' face encodings, user IDs, and emails from Supabase.
    """
    global known_faces, known_ids, known_emails
    try:
        # Fetch attendees with their face encodings and associated user emails
        response = supabase.table('attendees').select('user_id, face_encoding, users(email)').execute()
        attendees = response.data

        with cache_lock:
            known_faces = []
            known_ids = []
            known_emails = []

            for attendee in attendees:
                # Ensure face_encoding and associated user email exist
                if attendee['face_encoding'] and attendee['users'] and attendee['users']['email']:
                    encoding = attendee['face_encoding']  # Changed line
                    if isinstance(encoding, list) and len(encoding) > 0:
                        known_faces.append(encoding)
                        known_ids.append(attendee['user_id'])
                        known_emails.append(attendee['users']['email'])

        print(f"Loaded {len(known_faces)} known attendee encodings from Supabase.")
    except Exception as e:
        print(f"Error loading known faces: {e}")


def periodic_reload(interval_seconds=300):
    """
    Periodically reloads known faces from Supabase to keep the cache updated.
    """
    while True:
        load_known_faces()
        time.sleep(interval_seconds)

# Initial load of known faces
load_known_faces()

# Start a background thread to periodically reload known faces
reload_thread = threading.Thread(target=periodic_reload, args=(300,), daemon=True)
reload_thread.start()

@app.route('/recognize', methods=['POST'])
def recognize():
    print("Received image for recognition.") 
    """
    Endpoint to recognize faces in an uploaded image.
    Expects an image file in the 'image' form-data field.
    """
    # Optional: API Key Authentication
    """
    api_key = request.headers.get('x-api-key')
    if FACE_RECOGNITION_API_KEY and api_key != FACE_RECOGNITION_API_KEY:
        return jsonify({'error': 'Unauthorized'}), 401
    """

    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400

    file = request.files['image']
    try:
        image = face_recognition.load_image_file(file)
    except Exception as e:
        return jsonify({'error': f'Invalid image file: {e}'}), 400

    # Detect faces and encode them
    face_locations = face_recognition.face_locations(image)
    face_encodings = face_recognition.face_encodings(image, face_locations)

    results = []

    with cache_lock:
        current_known_faces = known_faces.copy()
        current_known_ids = known_ids.copy()
        current_known_emails = known_emails.copy()

    for encoding in face_encodings:
        if len(current_known_faces) == 0:
            results.append({
                'user_id': None,
                'email': None,
                'distance': None,
                'encoding': encoding.tolist()
            })
            continue

        # Compare faces
        matches = face_recognition.compare_faces(current_known_faces, encoding, tolerance=0.6)
        face_distances = face_recognition.face_distance(current_known_faces, encoding)

        best_match_index = np.argmin(face_distances) if len(face_distances) > 0 else -1

        if best_match_index >= 0 and matches[best_match_index]:
            results.append({
                'user_id': current_known_ids[best_match_index],
                'email': current_known_emails[best_match_index],
                'distance': float(face_distances[best_match_index]),
                'encoding': encoding.tolist()  # Include the encoding vector
            })
        else:
            results.append({
                'user_id': None,
                'email': None,
                'distance': None,
                'encoding': encoding.tolist()
            })

    return jsonify({'results': results})

if __name__ == '__main__':
    # Optionally, set host to '0.0.0.0' to make it accessible externally
    app.run(host='0.0.0.0', port=5002)
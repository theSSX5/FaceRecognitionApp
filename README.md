# Face Recognition Event Management Application

This repository contains a full-stack solution integrating a Node.js backend with a Python-based face recognition service and a Flutter frontend. The system leverages Supabase as a backend database/storage provider and uses JWT for authentication. Users can register as attendees, photographers, or admins, each having distinct roles and capabilities within the system.

## Overview

### High-Level Architecture

1. **Frontend (Flutter)**:
   - Written in Dart, using the Flutter framework to build a responsive, cross-platform UI.
   - Provides distinct screens for attendees, photographers, and admins.
   - Interacts with the backend via HTTP requests, sending and receiving JSON.
   - Manages user sessions by storing JWT tokens in local or secure storage.
   
2. **Backend (Node.js)**:
   - Hosts RESTful endpoints for authentication, event management, attendee check-ins, and photographer photo uploads.
   - Uses Supabase as a database (PostgreSQL under the hood) and a storage layer for uploaded images.
   - Integrates with a separate Python service for face recognition, sending uploaded photos and receiving identification results.
   - Implements role-based access control and secure endpoints using JWT authentication.

3. **Face Recognition Service (Python)**:
   - Runs a Flask-based microservice exposing a `/recognize` endpoint.
   - Uses the `face_recognition` library to detect and encode faces from images.
   - Periodically caches known attendees’ face encodings from Supabase to speed up identification.
   - Returns match results (user_id, email, distance, and encoding) to the Node.js backend.

4. **Supabase (Database + Storage)**:
   - Stores users, events, attendees, photos, and relationships between them.
   - Provides a storage bucket for image files.
   - Offers RPC calls for bulk queries (e.g., getting attendee counts for events).
   - Security: Environment variables for keys and secrets.

### User Roles

- **Admin**:
  - Creates, updates, and deletes events.
  - Views event statistics (total, active, future events).
  - Searches, filters, sorts events by various criteria (name, code, date, attendee counts, etc.).
  - Manages event lifecycle (e.g., removing outdated or unnecessary events).

- **Photographer**:
  - Registers for events using event codes.
  - Uploads event photos for face recognition.
  - After recognition, sends out automated emails to matched attendees.
  - Views personal event statistics (total events, active today, future events).
  - Manages pagination, filtering, and searching for their associated events on the frontend.

- **Attendee**:
  - Checks into events by providing an event code and a face photo.
  - The system stores their face encoding for future recognition in event photos.
  - After the event, they may receive identified photos from photographers via email.

## Backend Detailed Analysis

**Technologies**:
- **Node.js** for handling routes and middleware.
- **Supabase** client for database interactions and file storage.
- **jsonwebtoken (JWT)** for authentication and authorization.
- **bcrypt** for password hashing.
- **multer** for handling file uploads.
- **nodemailer** for sending event photo emails to identified attendees.
- **axios** for communicating with the Python recognition service.

**API Endpoints Structure**:
- `POST /api/auth/register`: Register attendee or photographer.
- `POST /api/auth/login`: Login to obtain JWT token.
- `GET /api/attendee/checkin`: Attendee uploads a photo and event code to check into an event.
- `POST /api/photographer/register`: Photographer registers for an event using event code.
- `POST /api/photographer/upload`: Photographer uploads photos; backend sends them to Python service, identifies attendees, and sends emails.
- `GET /api/photographer/events`: Lists events for the photographer.
- `GET /api/admin/events`: Admin retrieves all events with counts, optional filters/sorts/search.
- `POST /api/admin/events`: Admin creates events.
- `PUT /api/admin/events/:id`: Admin modifies events.
- `DELETE /api/admin/events/:id`: Admin deletes events.
- `GET /api/admin/events/statistics`: Admin retrieves overall event statistics.

**Role-Based Authorization**:
- Middleware checks JWT payload for `role`.
- `requireAdmin`: Only admins can manage events via admin routes.
- `requirePhotographer`: Only photographers can use photography-related endpoints.
- `requireAttendee`: For attendee check-in endpoints.

**Error Handling and Logging**:
- Centralized error handlers return structured JSON responses.
- Uses standard HTTP status codes to reflect success or failure.
- Logs errors to console for debugging; can be extended with logging frameworks.

**Database Considerations**:
- Tables: `users`, `events`, `attendees`, `photographers_events`, `attendees_events`, `photos`, `photos_attendees`.
- Uses `in()` and RPC for efficient bulk querying.
- Face encodings stored as arrays, allowing vector comparison by the Python service.

**Face Recognition Flow**:
1. Attendee registers face during check-in -> Their encoding is stored.
2. When a photographer uploads a photo:
   - The image is sent to Python service.
   - The service returns matched attendees.
   - The backend creates `photos_attendees` entries and sends emails to those attendees.

## Python Face Recognition Service Detailed Analysis

- **face_recognition** library: High-level wrappers for face detection and encoding.
- **Cache Mechanism**:
  - On startup, loads all attendee encodings from Supabase into memory.
  - Periodically refreshes the cache (every 5 minutes) to account for new attendees.
- **API**:
  - `POST /recognize`: Receives an image, returns JSON with recognized faces or unknown encodings.
- **Performance**:
  - Storing face encodings in memory avoids repeated DB fetches.
  - NumPy arrays and face_recognition’s efficient C bindings speed up comparisons.

## Frontend Detailed Analysis

**Flutter UI**:
- Uses `MaterialApp` and named routes for navigation.
- Screens:
  - `welcome_screen.dart`: Intro screen with gradient, branding icon, and navigation to login or signup.
  - `login_screen.dart` & `signup_screen.dart`: Authentication forms, validates input, sends data to the backend, and stores JWT tokens.
  - `photographer_home_screen.dart`: Dashboard for photographers:
    - Displays event statistics.
    - Lets photographers register for events.
    - Lets them upload multiple photos at once (using `FilePicker` in web mode).
    - Shows search bars, filters, sorting dialogs, pagination controls for events.
  - `attendee_home_screen.dart`: Attendees can input event code and upload face photo:
    - Uses image picking and previewing (via HTML file picker for web).
    - Sends data to backend to check-in.
  - `admin_home_screen.dart`:
    - Displays total events, active events, and the closest upcoming event.
    - Provides a DataTable of events with pagination, filters, sorting, and searching.
    - Admin can create a new event or modify/delete existing events with dialogs.
    
**State and Data Handling**:
- Tokens stored using `FlutterSecureStorage` and `html.window.localStorage` for web builds.
- HTTP requests made with `http` or `dio` packages.
- Error dialogues appear for failures; success dialogues and snackbars for notifications.

**Responsive Design**:
- Uses `LayoutBuilder` and `ConstrainedBox` to handle different screen sizes.
- Conditionals for column counts in dashboards, ensuring UI remains clean on large or small screens.

## Security Considerations

- **JWT Authentication** ensures only valid users can access protected endpoints.
- Passwords hashed with `bcrypt`, mitigating data breaches.
- Role-based checks prevent unauthorized role actions (e.g., no photographer can access admin endpoints).
- HTTPS recommended in production to protect JWT tokens in transit.
- Supabase keys and secrets stored in `.env` files, not hard-coded.

## Performance and Scaling

- **Caching face encodings** in the Python service saves time on repeated queries.
- Pagination and filtering on the admin and photographer screens prevent UI slowdowns with large datasets.
- Sorting and searching handled by backend queries and RPC calls to reduce client computation.
- Could horizontally scale the Python service for face recognition if load grows large, as the backend just calls its endpoint.

## Deployment and Configuration

- **Backend**:
  - Install dependencies: `npm install`.
  - Run with `npm start` or `node index.js`.
  - Set environment variables in `.env`: `SUPABASE_URL`, `SUPABASE_KEY`, `JWT_SECRET`, `EMAIL_USER`, `EMAIL_PASS`, `FACE_RECOGNITION_URL`, `FACE_RECOGNITION_API_KEY`.

- **Python Service**:
  - Download the Dependencies.
  - Run `python face_recognition_service.py`.
  - Ensure `SUPABASE_URL` and `SUPABASE_KEY` are set for DB access.

- **Frontend**:
  - Requires Flutter environment setup.
  - `flutter run -d chrome` for web debugging.
  - Update backend endpoints from `http://localhost:5001` to production URIs when deploying.

- **Supabase**:
  - Configure public bucket `photos` for image storage.
  - Setup RPC functions for attendee/photographer counts if not pre-existing.
  - Ensure database schema matches the backend’s expected tables and columns.

## Conclusion

This Face Recognition Event Management Application demonstrates a modern, scalable approach to event management and personalization. By integrating a robust authentication system, well-structured APIs, a reliable and efficient face recognition microservice, and a responsive Flutter frontend, it provides a seamless experience for all user roles. Administrators can easily manage events; photographers can effortlessly upload and distribute event photos; and attendees can check in with minimal friction, benefiting from advanced facial recognition technology.

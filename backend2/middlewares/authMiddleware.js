// middlewares/authMiddleware.js

const jwt = require('jsonwebtoken');
const dotenv = require('dotenv');

dotenv.config();

const jwtSecret = process.env.JWT_SECRET;

// Middleware to verify JWT and attach user to request
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ message: 'Access token is missing or invalid.' });
  }

  jwt.verify(token, jwtSecret, (err, user) => {
    if (err) {
      return res.status(403).json({ message: 'Invalid or expired token.' });
    }
    req.user = user;
    next();
  });
};

// Middleware to check for admin role
const requireAdmin = (req, res, next) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Admin privileges required.' });
  }
  next();
};

// Middleware to check for attendee role
const requireAttendee = (req, res, next) => {
  if (req.user.role !== 'attendee') {
    return res.status(403).json({ message: 'Attendee privileges required.' });
  }
  next();
};

const requirePhotographer = (req, res, next) => {
  if (req.user.role !== 'photographer') {
      return res.status(403).json({ message: 'Access denied. Photographer role required.' });
  }
  next();
};

module.exports = { authenticateToken, requireAdmin, requireAttendee, requirePhotographer };
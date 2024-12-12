// routes/authRoutes.js

const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { body, validationResult } = require('express-validator');
const supabase = require('../supabaseClient');
const dotenv = require('dotenv');

dotenv.config();

const router = express.Router();
const jwtSecret = process.env.JWT_SECRET;
const jwtExpiry = '1h'; // Token expiry duration

/**
 * @route   POST /api/auth/register
 * @desc    Register a new user
 * @access  Public
 */
router.post(
    '/register',
    [
      // Validate Email
      body('email')
        .isEmail()
        .withMessage('Please provide a valid email.'),
  
      // Validate Password
      body('password')
        .isLength({ min: 6 })
        .withMessage('Password must be at least 6 characters long.'),
  
      // Validate Name
      body('name')
        .notEmpty()
        .withMessage('Name is required.')
        .trim()
        .escape(),
  
      // Validate Role
      body('role')
        .isIn(['attendee', 'photographer'])
        .withMessage('Role must be either attendee or photographer.'),
    ],
    async (req, res) => {
      // Handle validation errors
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        // Extract error messages
        const extractedErrors = errors.array().map(err => ({ [err.param]: err.msg }));
        return res.status(400).json({ errors: extractedErrors });
      }
  
      // Extract fields from the request body
      const { email, password, name, role } = req.body;
  
      try {
        // Check if user already exists
        const { data: existingUser, error: fetchError } = await supabase
          .from('users')
          .select('*')
          .eq('email', email)
          .single();
  
        if (existingUser) {
          return res.status(400).json({ message: 'User already exists.' });
        }
  
        // Hash the password
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);
  
        // Insert the new user into Supabase
        const { data, error } = await supabase.from('users').insert([
          {
            email,
            password: hashedPassword,
            name,
            role, // Assign role as provided by the user
          },
        ]);
  
        if (error) {
          throw error;
        }
  
        res.status(201).json({ message: 'User registered successfully.' });
      } catch (error) {
        console.error('Registration Error:', error);
        res.status(500).json({ message: 'Server error during registration.', error: error.message });
      }
    }
  );

/**
 * @route   POST /api/auth/login
 * @desc    Authenticate user and get token
 * @access  Public
 */
router.post(
  '/login',
  [
    body('email').isEmail().withMessage('Please provide a valid email.'),
    body('password').exists().withMessage('Password is required.'),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { email, password } = req.body;

    try {
      // Fetch the user from Supabase
      const { data: user, error: fetchError } = await supabase.from('users').select('*').eq('email', email).single();

      if (!user) {
        return res.status(400).json({ message: 'Invalid credentials.' });
      }

      // Compare the password
      const isMatch = await bcrypt.compare(password, user.password);
      if (!isMatch) {
        return res.status(400).json({ message: 'Invalid credentials.' });
      }

      // Create JWT payload
      const payload = {
        id: user.id,
        email: user.email,
        role: user.role,
        name: user.name,
      };

      // Sign the token
      const token = jwt.sign(payload, jwtSecret, { expiresIn: jwtExpiry });

      res.status(200).json({ access_token: token, message: 'Logged in successfully.', role: user.role, name: user.name });
    } catch (error) {
      console.error('Login Error:', error);
      res.status(500).json({ message: 'Server error during login.', error: error.message });
    }
  }
);

module.exports = router;
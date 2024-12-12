// index.js

const express = require("express");
const morgan = require("morgan");
const cors = require("cors");
const dotenv = require("dotenv");

dotenv.config();

const authRoutes = require("./routes/authRoutes");
const adminRoutes = require("./routes/adminRoutes");
const attendeeRoute = require("./routes/attendeeRoute");
const photographerRoute = require("./routes/photographerRoute");

const app = express();

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan("dev"));

// Routes
app.use("/api/auth", authRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/attendee", attendeeRoute);
app.use("/api/photographer", photographerRoute);

// Health Check Route
app.get("/", (req, res) => {
  res.send("Face Recognition Backend is running.");
});

// Error Handling Middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res
    .status(500)
    .json({
      message: "An internal server error occurred.",
      error: err.message,
    });
});

const PORT = process.env.PORT || 5001;

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
